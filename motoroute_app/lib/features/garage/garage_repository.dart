import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Garage: Modelle + Repository. Spricht gegen die EIGENE Garage-API
/// (Express/Prisma, Basis-URL standardmaessig `garage.apiBaseUrl` ->
/// Default `http://10.0.2.2:4100`). Eigener Login (Bootstrap-Admin aus
/// der Garage-DB) - vollkommen unabhaengig vom MotoRoute-Backend.
///
/// Endpunkte (Spiegel garage/garage-api/src):
///   POST /api/auth/login            -> { accessToken, user }
///   GET  /api/vehicles/garage       -> { motorcycles, cars }
///   POST /api/vehicles              -> Vehicle (Namen ODER variantId)
///   GET  /api/vehicles/:id          -> Vehicle + specifications
///   GET  /api/vehicles/:id/specifications
///   GET  /api/vehicles/:id/reminders
///   POST /api/vehicles/:id/maintenance
///   GET  /api/vehicles/:id/fuel | /fuel/stats
///   GET  /api/vehicles/:id/tires | /documents
///   GET  /api/vehicles/:id/costs

// ---------------------------------------------------------------------------
// Modelle
// ---------------------------------------------------------------------------

/// Ampel-Status der Erinnerungen (Spiegel reminders.ts).
enum GarageReminderStatus { ok, dueSoon, overdue }

enum GarageCategory { motorcycle, car }

extension GarageCategoryX on GarageCategory {
  static GarageCategory from(String? raw) => raw == 'car' ? GarageCategory.car : GarageCategory.motorcycle;

  String get emoji => this == GarageCategory.motorcycle ? '🏍️' : '🚗';
  String get apiValue => name; // 'motorcycle' | 'car'
}

class GarageVehicle {
  final String id;
  final GarageCategory category;
  final String manufacturerName;
  final String modelName;
  final String? variantName;
  final int? year;
  final int odometerKm;
  final String? nickname;
  final String? color;
  final String? photoUrl;
  final String? worstStatus; // 'ok' | 'dueSoon' | 'overdue'
  final Map<String, dynamic>? specifications;

  const GarageVehicle({
    required this.id,
    required this.category,
    required this.manufacturerName,
    required this.modelName,
    this.variantName,
    this.year,
    required this.odometerKm,
    this.nickname,
    this.color,
    this.photoUrl,
    this.worstStatus,
    this.specifications,
  });

  factory GarageVehicle.fromJson(Map<String, dynamic> j) => GarageVehicle(
        id: j['id'] as String,
        category: GarageCategoryX.from(j['category'] as String?),
        manufacturerName: (j['manufacturerName'] ?? j['manufacturer']?['name'] ?? '') as String,
        modelName: (j['modelName'] ?? j['model']?['name'] ?? '') as String,
        variantName: j['variantName'] as String?,
        year: j['year'] as int?,
        odometerKm: (j['odometerKm'] ?? 0) as int,
        nickname: j['nickname'] as String?,
        color: j['color'] as String?,
        photoUrl: j['photoUrl'] as String?,
        worstStatus: (j['maintenanceWorstStatus'] ?? j['worstStatus']) as String?,
        specifications: j['specifications'] as Map<String, dynamic>?,
      );

  String get title => nickname?.isNotEmpty == true ? nickname! : '$manufacturerName $modelName';
  String get subtitle => [variantName, year != null ? '$year' : null].whereType<String>().join(' · ');
}

class GarageReminder {
  final String type;
  final String status; // green | dueSoon | overdue (Server-Namen: ok/dueSoon/overdue)
  final int? kmRemaining;
  final int? daysRemaining;
  final int? nextDueOdometerKm;
  final String? nextDueDate;

  const GarageReminder({
    required this.type,
    required this.status,
    this.kmRemaining,
    this.daysRemaining,
    this.nextDueOdometerKm,
    this.nextDueDate,
  });

  factory GarageReminder.fromJson(Map<String, dynamic> j) => GarageReminder(
        type: (j['type'] ?? j['typeKey'] ?? '') as String,
        status: (j['status'] ?? j['level'] ?? 'ok') as String,
        kmRemaining: j['kmRemaining'] as int?,
        daysRemaining: j['daysRemaining'] as int?,
        nextDueOdometerKm: (j['nextDueOdometerKm'] ?? j['nextDueKm']) as int?,
        nextDueDate: j['nextDueDate'] as String?,
      );

  GarageReminderStatus get level {
    switch (status) {
      case 'overdue':
        return GarageReminderStatus.overdue;
      case 'dueSoon':
        return GarageReminderStatus.dueSoon;
      default:
        return GarageReminderStatus.ok;
    }
  }

  String get labelDe => maintenanceTypeLabelDe(type);
}

/// Deutsche Labels der 17 Wartungstypen (Spiegel maintenance-types.ts).
String maintenanceTypeLabelDe(String type) => switch (type) {
      'OIL_CHANGE' => 'Ölwechsel',
      'OIL_FILTER' => 'Ölfilter',
      'AIR_FILTER' => 'Luftfilter',
      'BRAKE_PADS' => 'Bremsbeläge',
      'BRAKE_DISCS' => 'Bremsscheiben',
      'TIRES' => 'Reifen',
      'BATTERY' => 'Batterie',
      'COOLANT' => 'Kühlmittel',
      'BRAKE_FLUID' => 'Bremsflüssigkeit',
      'SPARK_PLUGS' => 'Zündkerzen',
      'CHAIN' => 'Kette spannen/schmieren',
      'CHAIN_OIL' => 'Kettenöl',
      'TIMING_BELT' => 'Zahnriemen',
      'INSPECTION' => 'Inspektion',
      'HU' => 'HU/TÜV',
      'AU' => 'AU',
      _ => 'Sonstige Wartung',
    };

class GarageMaintenanceRecord {
  final String id;
  final String type;
  final DateTime? performedAt;
  final int odometerKm;
  final int? costCents;
  final String? notes;
  final String? shopName;

  const GarageMaintenanceRecord({
    required this.id,
    required this.type,
    this.performedAt,
    required this.odometerKm,
    this.costCents,
    this.notes,
    this.shopName,
  });

  factory GarageMaintenanceRecord.fromJson(Map<String, dynamic> j) => GarageMaintenanceRecord(
        id: j['id'] as String,
        type: (j['type'] ?? 'OTHER') as String,
        performedAt: j['performedAt'] == null ? null : DateTime.tryParse(j['performedAt'] as String),
        odometerKm: (j['odometerKm'] ?? 0) as int,
        costCents: j['costCents'] as int?,
        notes: j['notes'] as String?,
        shopName: j['shopName'] as String?,
      );

  String get labelDe => maintenanceTypeLabelDe(type);
}

class GarageFuelEntry {
  final String id;
  final DateTime? date;
  final int odometerKm;
  final double liters;
  final int priceCentsTotal;

  const GarageFuelEntry({
    required this.id,
    this.date,
    required this.odometerKm,
    required this.liters,
    required this.priceCentsTotal,
  });

  factory GarageFuelEntry.fromJson(Map<String, dynamic> j) => GarageFuelEntry(
        id: j['id'] as String,
        date: j['date'] == null ? null : DateTime.tryParse(j['date'] as String),
        odometerKm: (j['odometerKm'] ?? 0) as int,
        liters: (j['liters'] as num?)?.toDouble() ?? 0,
        priceCentsTotal: (j['priceCentsTotal'] ?? j['totalPriceCents'] ?? 0) as int,
      );
}

class GarageFuelStats {
  final double? averageConsumptionPer100km;
  final int totalCostCents;
  final double totalLiters;
  final int? costPerKmCents;

  const GarageFuelStats({
    this.averageConsumptionPer100km,
    required this.totalCostCents,
    required this.totalLiters,
    this.costPerKmCents,
  });

  factory GarageFuelStats.fromJson(Map<String, dynamic> j) => GarageFuelStats(
        averageConsumptionPer100km: (j['averageConsumptionPer100km'] as num?)?.toDouble(),
        totalCostCents: (j['totalCostCents'] ?? 0) as int,
        totalLiters: ((j['totalLiters'] ?? 0) as num).toDouble(),
        costPerKmCents: j['costPerKmCents'] as int?,
      );
}

class GarageTireSet {
  final String id;
  final String position; // front | rear
  final String brand;
  final String modelName;
  final String size;
  final DateTime? mountedAt;
  final int? mountedAtKm;
  final double? treadDepthMm;

  const GarageTireSet({
    required this.id,
    required this.position,
    required this.brand,
    required this.modelName,
    required this.size,
    this.mountedAt,
    this.mountedAtKm,
    this.treadDepthMm,
  });

  factory GarageTireSet.fromJson(Map<String, dynamic> j) => GarageTireSet(
        id: j['id'] as String,
        position: (j['position'] ?? 'front') as String,
        brand: (j['brand'] ?? '') as String,
        modelName: (j['modelName'] ?? j['model'] ?? '') as String,
        size: (j['size'] ?? '') as String,
        mountedAt: j['mountedAt'] == null ? null : DateTime.tryParse(j['mountedAt'] as String),
        mountedAtKm: j['mountedAtKm'] as int?,
        treadDepthMm: (j['treadDepthMm'] as num?)?.toDouble(),
      );
}

class GarageDocument {
  final String id;
  final String type;
  final String title;
  final String fileUrl;

  const GarageDocument({required this.id, required this.type, required this.title, required this.fileUrl});

  factory GarageDocument.fromJson(Map<String, dynamic> j) => GarageDocument(
        id: j['id'] as String,
        type: (j['type'] ?? 'other') as String,
        title: (j['title'] ?? '') as String,
        fileUrl: (j['fileUrl'] ?? '') as String,
      );
}

class GarageCosts {
  final int totalCents;
  final int thisYearCents;
  final int count;

  const GarageCosts({required this.totalCents, required this.thisYearCents, required this.count});

  factory GarageCosts.fromJson(Map<String, dynamic> j) => GarageCosts(
        totalCents: (j['totalCents'] ?? j['total'] ?? 0) as int,
        thisYearCents: (j['thisYearCents'] ?? j['thisYear'] ?? 0) as int,
        count: (j['count'] ?? 0) as int,
      );
}

class GarageCatalogEntry {
  final String id;
  final String name;
  final String? vehicleType;

  const GarageCatalogEntry({required this.id, required this.name, this.vehicleType});

  factory GarageCatalogEntry.fromJson(Map<String, dynamic> j) => GarageCatalogEntry(
        id: j['id'] as String,
        name: (j['name'] ?? '') as String,
        vehicleType: j['vehicleType'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

class GarageApiException implements Exception {
  final String message;
  final int? statusCode;
  GarageApiException(this.message, [this.statusCode]);
  @override
  String toString() => 'GarageApiException($statusCode): $message';
}

class GarageRepository {
  GarageRepository(this._dio);

  final Dio _dio;

  // -- Session --------------------------------------------------------------

  Future<String> login(String baseUrl, String email, String password) async {
    final res = await _post(baseUrl, null, '/api/auth/login', {'email': email, 'password': password});
    final token = (res['accessToken'] ?? res['token']) as String?;
    if (token == null || token.isEmpty) {
      throw GarageApiException('Login ohne Token - Server-Antwort unerwartet');
    }
    return token;
  }

  // -- Garage ---------------------------------------------------------------

  Future<List<GarageVehicle>> garage(String baseUrl, String token) async {
    final res = await _get(baseUrl, token, '/api/vehicles/garage');
    final motos = (res['motorcycles'] as List?) ?? const [];
    final cars = (res['cars'] as List?) ?? const [];
    return [...motos, ...cars].map((e) => GarageVehicle.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<GarageVehicle> vehicle(String baseUrl, String token, String id) async {
    final res = await _get(baseUrl, token, '/api/vehicles/$id');
    return GarageVehicle.fromJson((res as Map).cast<String, dynamic>());
  }

  Future<GarageVehicle> createVehicle(
    String baseUrl,
    String token, {
    required GarageCategory category,
    required String manufacturerName,
    required String modelName,
    String? variantName,
    String? variantId,
    int? year,
    int? odometerKm,
    String? nickname,
    String? color,
    String? licensePlate,
    int? purchasePriceCents,
    String? notes,
  }) async {
    final res = await _post(baseUrl, token, '/api/vehicles', {
      'category': category.apiValue,
      'manufacturerName': manufacturerName,
      'modelName': modelName,
      if (variantName != null) 'variantName': variantName,
      if (variantId != null) 'variantId': variantId,
      if (year != null) 'year': year,
      if (odometerKm != null) 'odometerKm': odometerKm,
      if (nickname != null) 'nickname': nickname,
      if (color != null) 'color': color,
      if (licensePlate != null) 'licensePlate': licensePlate,
      if (purchasePriceCents != null) 'purchasePriceCents': purchasePriceCents,
      if (notes != null) 'notes': notes,
    });
    return GarageVehicle.fromJson((res as Map).cast<String, dynamic>());
  }

  Future<void> updateOdometer(String baseUrl, String token, String id, int odometerKm) async {
    await _put(baseUrl, token, '/api/vehicles/$id', {'odometerKm': odometerKm});
  }

  Future<void> deleteVehicle(String baseUrl, String token, String id) async {
    await _delete(baseUrl, token, '/api/vehicles/$id');
  }

  // -- Specs / Erinnerungen / Kosten -----------------------------------------

  Future<Map<String, dynamic>> specifications(String baseUrl, String token, String id) async {
    final res = await _get(baseUrl, token, '/api/vehicles/$id/specifications');
    if (res is Map<String, dynamic> && res.containsKey('specifications')) {
      return (res['specifications'] as Map).cast<String, dynamic>();
    }
    return (res as Map).cast<String, dynamic>();
  }

  Future<List<GarageReminder>> reminders(String baseUrl, String token, String id) async {
    final res = await _get(baseUrl, token, '/api/vehicles/$id/reminders');
    final list = (res['reminders'] as List?) ?? (res is List ? res : const []);
    return list.map((e) => GarageReminder.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<GarageCosts> costs(String baseUrl, String token, String id) async {
    final res = await _get(baseUrl, token, '/api/vehicles/$id/costs');
    return GarageCosts.fromJson((res as Map).cast<String, dynamic>());
  }

  // -- Wartung / Tank / Reifen / Dokumente -----------------------------------

  Future<List<GarageMaintenanceRecord>> maintenance(String baseUrl, String token, String id) async {
    final res = await _get(baseUrl, token, '/api/vehicles/$id/maintenance');
    final list = (res['records'] as List?) ?? (res['maintenance'] as List?) ?? (res is List ? res : const []);
    return list.map((e) => GarageMaintenanceRecord.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<void> addMaintenance(
    String baseUrl,
    String token,
    String vehicleId, {
    required String type,
    required String performedAt, // yyyy-MM-dd
    required int odometerKm,
    int? costCents,
    String? notes,
  }) async {
    await _post(baseUrl, token, '/api/vehicles/$vehicleId/maintenance', {
      'type': type,
      'performedAt': performedAt,
      'odometerKm': odometerKm,
      if (costCents != null) 'costCents': costCents,
      if (notes != null) 'notes': notes,
    });
  }

  Future<List<GarageFuelEntry>> fuel(String baseUrl, String token, String id) async {
    final res = await _get(baseUrl, token, '/api/vehicles/$id/fuel');
    final list = (res['entries'] as List?) ?? (res is List ? res : const []);
    return list.map((e) => GarageFuelEntry.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<void> addFuel(
    String baseUrl,
    String token,
    String vehicleId, {
    required String date,
    required int odometerKm,
    required double liters,
    required int priceCentsTotal,
    String? station,
  }) async {
    await _post(baseUrl, token, '/api/vehicles/$vehicleId/fuel', {
      'date': date,
      'odometerKm': odometerKm,
      'liters': liters,
      'priceCentsTotal': priceCentsTotal,
      if (station != null) 'station': station,
    });
  }

  Future<GarageFuelStats> fuelStats(String baseUrl, String token, String id) async {
    final res = await _get(baseUrl, token, '/api/vehicles/$id/fuel/stats');
    return GarageFuelStats.fromJson((res as Map).cast<String, dynamic>());
  }

  Future<List<GarageTireSet>> tires(String baseUrl, String token, String id) async {
    final res = await _get(baseUrl, token, '/api/vehicles/$id/tires');
    final list = (res['tires'] as List?) ?? (res['sets'] as List?) ?? (res is List ? res : const []);
    return list.map((e) => GarageTireSet.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<void> addTire(
    String baseUrl,
    String token,
    String vehicleId, {
    required String position,
    required String brand,
    required String modelName,
    required String size,
    required String mountedAt,
    required int mountedAtKm,
    double? treadDepthMm,
  }) async {
    await _post(baseUrl, token, '/api/vehicles/$vehicleId/tires', {
      'position': position,
      'brand': brand,
      'modelName': modelName,
      'size': size,
      'mountedAt': mountedAt,
      'mountedAtKm': mountedAtKm,
      if (treadDepthMm != null) 'treadDepthMm': treadDepthMm,
    });
  }

  Future<List<GarageDocument>> documents(String baseUrl, String token, String id) async {
    final res = await _get(baseUrl, token, '/api/vehicles/$id/documents');
    final list = (res['documents'] as List?) ?? (res is List ? res : const []);
    return list.map((e) => GarageDocument.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<void> addDocument(
    String baseUrl,
    String token,
    String vehicleId, {
    required String type,
    required String title,
    required String fileUrl,
  }) async {
    await _post(baseUrl, token, '/api/vehicles/$vehicleId/documents', {
      'type': type,
      'title': title,
      'fileUrl': fileUrl,
    });
  }

  // -- Katalog ----------------------------------------------------------------

  Future<List<GarageCatalogEntry>> manufacturers(String baseUrl, String token, {bool motorcycle = true}) async {
    final res = await _get(baseUrl, token, '/api/catalog/manufacturers?type=${motorcycle ? 'MOTORCYCLE' : 'CAR'}');
    final list = (res['manufacturers'] as List?) ?? (res is List ? res : const []);
    return list.map((e) => GarageCatalogEntry.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<List<GarageCatalogEntry>> models(String baseUrl, String token, String manufacturerId) async {
    final res = await _get(baseUrl, token, '/api/catalog/manufacturers/$manufacturerId/models');
    final list = (res['models'] as List?) ?? (res is List ? res : const []);
    return list.map((e) => GarageCatalogEntry.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<List<GarageCatalogEntry>> variants(String baseUrl, String token, String modelId) async {
    final res = await _get(baseUrl, token, '/api/catalog/models/$modelId/variants');
    final list = (res['variants'] as List?) ?? (res is List ? res : const []);
    return list.map((e) => GarageCatalogEntry.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  // -- HTTP-Primitives --------------------------------------------------------

  Future<dynamic> _get(String baseUrl, String? token, String path) async {
    try {
      final res = await _dio.get<dynamic>('$baseUrl$path',
          options: Options(headers: {if (token != null) 'Authorization': 'Bearer $token'}));
      return res.data;
    } on DioException catch (e) {
      throw GarageApiException(_msg(e), e.response?.statusCode);
    }
  }

  Future<dynamic> _post(String baseUrl, String? token, String path, Map<String, dynamic> body) async {
    try {
      final res = await _dio.post<dynamic>('$baseUrl$path',
          data: body, options: Options(headers: {if (token != null) 'Authorization': 'Bearer $token'}));
      return res.data;
    } on DioException catch (e) {
      throw GarageApiException(_msg(e), e.response?.statusCode);
    }
  }

  Future<dynamic> _put(String baseUrl, String? token, String path, Map<String, dynamic> body) async {
    try {
      final res = await _dio.put<dynamic>('$baseUrl$path',
          data: body, options: Options(headers: {if (token != null) 'Authorization': 'Bearer $token'}));
      return res.data;
    } on DioException catch (e) {
      throw GarageApiException(_msg(e), e.response?.statusCode);
    }
  }

  Future<dynamic> _delete(String baseUrl, String? token, String path) async {
    try {
      final res = await _dio.delete<dynamic>('$baseUrl$path',
          options: Options(headers: {if (token != null) 'Authorization': 'Bearer $token'}));
      return res.data;
    } on DioException catch (e) {
      throw GarageApiException(_msg(e), e.response?.statusCode);
    }
  }

  String _msg(DioException e) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      return (err['message'] ?? 'Serverfehler') as String;
    }
    return e.message ?? 'Netzwerkfehler';
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Basis-URL der Garage-API. Reihenfolge:
///   1. --dart-define=GARAGE_API_URL=... (CI backt die Produktions-URL ins APK,
///      genau wie beim MotoRoute-Backend - der Endnutzer traegt NICHTS ein)
///   2. Emulator-Default 10.0.2.2:4100 (Android-Emulator -> PC-localhost)
///
/// Absicherung: Ohne gesetztes CI-Secret wrapt der Workflow GARAGE_API_URL
/// als LEEREN String - dann greift bewusst der Default statt '', damit die
/// Garage nicht mit defekten URLs aufschlägt.
const _kGarageEnvUrl = String.fromEnvironment('GARAGE_API_URL');
const _kGarageFallbackUrl = 'http://10.0.2.2:4100';
const _kGarageOverrideKey = 'settings.garageApiBaseUrl';
const _kGarageTokenKey = 'garage.accessToken';
const _kGarageEmailKey = 'garage.email';

final garageBaseUrlProvider = FutureProvider<String>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final override = prefs.getString(_kGarageOverrideKey)?.trim();
  if (override != null && override.isNotEmpty) return override;
  return _kGarageEnvUrl.isEmpty ? _kGarageFallbackUrl : _kGarageEnvUrl;
});

final garageRepositoryProvider = Provider<GarageRepository>((ref) {
  return GarageRepository(Dio());
});

/// Session: Token + Email persistiert. Ausloggen entfernt beides.
class GarageSession {
  final String token;
  final String email;
  const GarageSession({required this.token, required this.email});
}

class GarageSessionController extends StateNotifier<AsyncValue<GarageSession?>> {
  GarageSessionController(this._ref) : super(const AsyncValue.loading()) {
    _restore();
  }

  final Ref _ref;

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kGarageTokenKey);
    final email = prefs.getString(_kGarageEmailKey);
    state = AsyncValue.data(token != null && token.isNotEmpty ? GarageSession(token: token, email: email ?? '') : null);
  }

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final baseUrl = await _ref.read(garageBaseUrlProvider.future);
      final repo = _ref.read(garageRepositoryProvider);
      final token = await repo.login(baseUrl, email, password);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kGarageTokenKey, token);
      await prefs.setString(_kGarageEmailKey, email);
      state = AsyncValue.data(GarageSession(token: token, email: email));
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kGarageTokenKey);
    await prefs.remove(_kGarageEmailKey);
    state = const AsyncValue.data(null);
  }
}

final garageSessionProvider =
    StateNotifierProvider<GarageSessionController, AsyncValue<GarageSession?>>((ref) => GarageSessionController(ref));

/// Aktuelle Garage (Fahrzeugliste), abhaengig von der Session.
/// WICHTIG: Niemals State aendern (logout) WAEHREND des Builds - das
/// liess frueher den ganzen Tab grau werden. Bei 401/403 geben wir
/// einfach eine leere Liste zurueck; die Session-Aufraeumung macht der
/// naechste Interaktionszyklus (Screen invalidiert selbst).
final garageListProvider = FutureProvider<List<GarageVehicle>>((ref) async {
  final session = ref.watch(garageSessionProvider).value;
  if (session == null) return [];
  final baseUrl = await ref.watch(garageBaseUrlProvider.future);
  final repo = ref.watch(garageRepositoryProvider);
  try {
    return await repo.garage(baseUrl, session.token);
  } on GarageApiException catch (e) {
    if (e.statusCode == 401 || e.statusCode == 403) {
      // Token abgelaufen: Ohne Build-Seiteneffekt behandeln. Die
      // Session wird beim naechsten Login-Versuch ohnehin ueberschrieben.
      return [];
    }
    rethrow;
  }
});
