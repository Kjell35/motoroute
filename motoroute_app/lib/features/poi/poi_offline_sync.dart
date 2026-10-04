import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'poi_offline_cache.dart';

/// Ergebnis eines Sync-Versuchs - unterscheidet bewusst STILL von LAUT:
/// - [ok]: Delta verarbeitet (auch "0 Änderungen").
/// - [offline]: kein Schnitt / Backend nicht erreichbar (auch 503-Kaltstart)
///   → kein Fehlerzustand, die Karte läuft aus SQLite weiter.
/// - [error]: Verbindung da, aber der Sync schlug fehl (z. B. 5xx nach
///   erfolgreicher Probe) → die UI darf warnen.
enum OfflineSyncResult { ok, offline, error }

/// Zentraler Offline-Sync für die Biker-POI-Datenbank.
///
/// Ablauf bei jedem [sync]-Aufruf:
/// 1. Läuft bereits ein Sync → No-Op (keine konkurrierenden Schreiber).
/// 2. Verbindungsprobe ([ConnectivityProbe]): ohne Schnitt/Erreichbarkeit
///    → [OfflineSyncResult.offline], gecachte POIs bleiben in SQLite
///    nutzbar (Funkloch-Pfad, z. B. Alpen).
/// 3. Delta-Sync gegen /v1/biker-pois/sync mit Timestamp-Delta (`since`-
///    Cursor aus der letzten erfolgreichen Antwort, erster Sync: Epoch -
///    der Dienst liefert dann ALLE aktiven POIs).
/// 4. Ergebnis (upserted + deletedIds) in SQLite persistieren, Cursor
///    in SharedPreferences ablegen.
///
/// Reconnect: [watchConnectivity] horcht auf connectivity_plus-Events und
/// startet nach der Rückkehr eines Schnitts einen Nachhol-Sync (Debounce).
class OfflineSyncService {
  OfflineSyncService({
    required Dio dio,
    required PoiOfflineDatabase database,
    ConnectivityProbe? probe,
    this.cursorKey = legacyCursorKey,
  })  : _dio = dio,
        _db = database,
        _probe = probe ?? ConnectivityProbe();

  final Dio _dio;
  final PoiOfflineDatabase _db;
  final ConnectivityProbe _probe;

  /// Cursor-Schlüssel - absichtlich der LEGACY-Schlüssel des bisherigen
  /// SharedPreferences-Syncs: bestehende Installationen behalten ihren
  /// Delta-Stand beim Wechsel auf SQLite ohne Neu- Erst-Sync.
  static const legacyCursorKey = 'biker_poi.sync.cursor';

  final String cursorKey;

  OfflineSyncResult _lastResult = OfflineSyncResult.offline;
  OfflineSyncResult get lastResult => _lastResult;

  /// Ob der letzte sync()-Aufruf tatsächlich Zeilen verändert hat
  /// (upserted/deleted). Ermöglicht dem Controller, State-Updates und
  /// damit Layer-Re-Renders bei "0 Änderungen" zu überspringen.
  bool _lastChangedData = false;
  bool get lastSyncChangedData => _lastChangedData;

  bool _syncing = false;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _debounce;

  /// Führt einen Delta-Sync aus. Wirft bewusst NICHT: der Aufrufer
  /// (Intervall/Reconnect/Push) muss nie catchen.
  Future<OfflineSyncResult> sync({
    double? lat,
    double? lng,
    double? radiusKm,
    Set<String>? categories,
  }) async {
    if (_syncing) return _lastResult;
    _syncing = true;
    _lastChangedData = false;
    try {
      // 1) Erreichbarkeit: connectivity-Schnitt + Backend-Kopfprobe.
      if (!await _probe.isOnline()) {
        return _lastResult = OfflineSyncResult.offline;
      }

      // 2) Delta-Cursor: letzte Serverzeit oder Epoch (Erst-Sync).
      var since = await readCursor() ?? '1970-01-01T00:00:00.000Z';

      // 3+4) Delta ziehen und Seite für Seite persistieren: Der BFF
      // liefert max. 2000 POIs pro Call (hasMore + mitgelieferter
      // Cursor). Erst wenn hasMore=false ist, ist das Delta KOMPLETT -
      // der persistierte Cursor wird erst dann fortgeschrieben. Anders
      // herum würden beim Erst-Sync (>2000 POIs) alle Folgeseiten
      // PERMANENT verloren gehen (Cursor überspringt sie).
      var pages = 0;
      while (true) {
        final res = await _dio.get<Map<String, dynamic>>(
          '/v1/biker-pois/sync',
          queryParameters: {
            'since': since,
            if (lat != null && lng != null && radiusKm != null) ...{
              'lat': lat,
              'lon': lng,
              'radiusKm': radiusKm,
            },
            if (categories != null && categories.isNotEmpty)
              'categories': categories.join(','),
          },
        );
        final body = res.data ?? const {};
        final upserted = ((body['pois'] as List<dynamic>? ?? const []))
            .map((e) => CachedBikerPoi.fromSyncJson(e as Map<String, dynamic>))
            .toList();
        final deletedIds =
            (body['deletedIds'] as List<dynamic>? ?? const []).cast<String>();
        final returned = body['since'] as String?;
        final hasMore = body['hasMore'] == true;

        await _db.upsertAll(upserted);
        await _db.deleteByIds(deletedIds);
        if (upserted.isNotEmpty || deletedIds.isNotEmpty) _lastChangedData = true;

        if (returned == null || !hasMore || ++pages >= 10) {
          // Delta abgeschlossen (oder Server ohne Folgeseiten-Cursor -
          // defensiv gegen eine Endlosschleife bei kaputtem BFF; 10 Seiten
          // à 2000 POIs reichen für jeden Regionalsync mit Deckelung).
          if (returned != null) await writeCursor(returned);
          return _lastResult = OfflineSyncResult.ok;
        }
        since = returned;
      }
    } on DioException catch (e) {
      // 503 = Biker-POI-Dienst nicht konfiguriert (Vertrag des BFF): kein
      // Fehler, kein Retry-Sturm - die Karte läuft mit OSM-POIs weiter.
      if (e.response?.statusCode == 503) {
        return _lastResult = OfflineSyncResult.offline;
      }
      // Nach erfolgreicher Probe trotzdem ein Netzfehler: Abbruch MITTEN
      // IM Delta (_lastChangedData=true, z. B. Funkloch auf Seite 2) hat
      // bereits verarbeitete Seiten persistiert und den Cursor UNVER-
      // ÄNDERT - der nächste Sync wiederholt die Restseiten. Bewusst
      // still. Ein Fehler auf Seite 1 (nichts verarbeitet) bleibt wie
      // bisher ein lauter error - die UI darf warnen.
      if (_lastChangedData) return _lastResult = OfflineSyncResult.offline;
      return _lastResult = OfflineSyncResult.error;
    } catch (_) {
      // Kaputter Cursor/Parsing: Bestand bleibt, nächster Zyklus erneut.
      return _lastResult = OfflineSyncResult.error;
    } finally {
      _syncing = false;
    }
  }

  /// Reconnect-Watcher: nach Verbindungsverlust startet die Rückkehr
  /// eines Schnitts einen Nachhol-Sync (Debounce 2 s gegen Event-Stürme
  /// am Funkloch-Rand). Explizit stoppen (dispose/Tests).
  void watchConnectivity() {
    _connSub ??= _probe.events.listen((statuses) {
      final connected = statuses.any((s) =>
          s == ConnectivityResult.wifi ||
          s == ConnectivityResult.mobile ||
          s == ConnectivityResult.ethernet ||
          s == ConnectivityResult.vpn);
      if (!connected) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 2), sync);
    });
  }

  /// Cursor lesbar machen (Status-UI: „POIs vom …").
  Future<String?> readCursor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(cursorKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeCursor(String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(cursorKey, value);
    } catch (_) {
      // Persistenz-Fehler: Sync bleibt trotzdem erfolgreich.
    }
  }

  /// Cursor verwerfen (nächster Sync wird zum Erst-Sync / Vollzugriff).
  Future<void> resetCursor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(cursorKey);
    } catch (_) {
      // Ignorierbar: notfalls liefert readCursor den alten Stand weiter.
    }
  }

  /// Lokale DB für Leseseiten (Karten-Layer, Controller-Mapping).
  PoiOfflineDatabase get database => _db;

  Future<void> dispose() async {
    await _connSub?.cancel();
    _debounce?.cancel();
    await _db.close();
  }
}
