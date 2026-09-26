/**
 * Antwortform des POI-Detail-Endpunkts (GET /v1/pois/:id).
 *
 * Das Detail-Sheet der App zeigt: Bild, Name, Beschreibung + Website und
 * unten "Veröffentlicht am ... von ...". Die Felder kommen entweder aus
 * der poi-Tabelle (kuratierte/gespeicherte POIs) oder werden on-demand
 * aus der OSM-Metadaten-Ableitung gefüllt (Live-Overpass-POIs haben
 * keine Zeile in der DB - deren Detail bauen wir aus dem ids-Format
 * osm-<type>-<id> erneut per Overpass).
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
  /** Öffentliche Bild-URL, wenn vorhanden (kuratierte POIs), sonst null. */
  imageUrl: string | null;
  /** Biker-Score (0-100) bei kuratierten POIs, sonst null. */
  bikerScore: number | null;
  /** Zeilencode der OSM-Community ("amenity=pub") - Quellenangabe. */
  originTag: string | null;
  /** ISO-Zeitstempel der Veröffentlichung (created_at), sonst null. */
  publishedAt: string | null;
  /** "Community/OSM" bzw. kuratierte Kennung - Anzeige "von ...". */
  publishedBy: string | null;
}
