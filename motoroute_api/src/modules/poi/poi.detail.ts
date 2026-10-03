/**
 * Antwortform des POI-Detail-Endpunkts (GET /v1/pois/:id).
 *
 * Das Detail-Sheet der App zeigt: Bild, Name, Beschreibung + Website und
 * unten "Veröffentlicht am ... von ...". Die Felder kommen entweder aus
 * der poi-Tabelle (kuratierte/gespeicherte POIs) oder werden on-demand
 * angereichert:
 *  - Live-Overpass-POIs haben keine Zeile in der DB - deren Detail baut
 *    der Endpunkt (wenn GOOGLE_PLACES_API_KEY gesetzt ist) aus einem
 *    Nearby-Match bei den mitgelieferten Koordinaten (Quelle dann
 *    ehrlich "Google Places").
 *  - DB-POIs bekommen fehlende Felder (Website/Bild/Summary) ebenfalls
 *    aus dem Google-Nearby-Match ergänzt - vorhandene eigene Daten
 *    (OSM/TomTom) gewinnen aber immer.
 *
 * Fotos laufen NIE direkt von Google zum Gerät: die Media-URL verlangt
 * den API-Key, der im Client nichts zu suchen hat (Punkt 22). Das Backend
 * stellt sie über /v1/pois/photo?name=... als Proxy bereit - die App
 * löst relative URLs gegen die API-Basis auf.
 */
export interface PoiDetail {
  id: string;
  category: string;
  name: string;
  lat: number;
  lng: number;
  source: string;
  /** Klartext-Beschreibung (opening_hours + address) oder Fallback. */
  description: string | null;
  /** Vollständige Website-URL (https ergänzt, wenn nötig) oder null. */
  website: string | null;
  /** Bild-URL: absolute externe URL ODER Backend-relativer Foto-Proxy. */
  imageUrl: string | null;
  /** Biker-Score (0-100) bei kuratierten POIs, sonst null. */
  bikerScore: number | null;
  /** Zeilencode der OSM-Community ("amenity=pub") - Quellenangabe. */
  originTag: string | null;
  /** ISO-Zeitstempel der Veröffentlichung (created_at), sonst null. */
  publishedAt: string | null;
  /** "Community/OSM" bzw. kuratierte Kennung - Anzeige "von ...". */
  publishedBy: string | null;
  /** Deeplink in Google Maps (Places), wenn ein Match gefunden wurde. */
  googleMapsUri: string | null;
  /** Einzeiler von Google ("Klassisches bayerisches Wirtshaus ..."), sonst null. */
  googleSummary: string | null;
  /** Pflicht-Attribution des Google-Fotos ("Foto: Max Muster"), sonst null. */
  photoAttribution: string | null;
}
