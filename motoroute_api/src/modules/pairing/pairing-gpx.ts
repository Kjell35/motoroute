export type GpxPoint = { label: string; detail: string | null; lat: number; lon: number };

/**
 * GPX 1.1 aus den Punkten eines Plans.
 *
 * Die Namen stehen an zwei Stellen: als `<wpt>` (Wegpunkt, den Navis in der
 * Liste zeigen) und als `<name>` im `<trkpt>` (erlaubt, weil trkpt vom Typ
 * wptType ist; viele Geräte ignorieren es, andere zeigen es im Track an).
 * Höhen gibt es nicht - die Luftlinie der Seite kennt keine.
 *
 * Bewusst von Hand statt mit einer GPX-Bibliothek: das Format ist ein paar
 * Zeilen XML, eine Abhängigkeit dafür wäre teurer als der Nutzen.
 */
export function buildGpx(token: string, points: GpxPoint[]): string {
  const name = escapeXml(`MotoRoute ${token}`);
  const waypoints = points.map(
    (point) =>
      `  <wpt lat="${point.lat}" lon="${point.lon}">\n` +
      `    <name>${escapeXml(point.label)}</name>\n` +
      '  </wpt>',
  );
  const trackPoints = points.map(
    (point) =>
      `      <trkpt lat="${point.lat}" lon="${point.lon}">\n` +
      `        <name>${escapeXml(point.label)}</name>\n` +
      '      </trkpt>',
  );

  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<gpx version="1.1" creator="MotoRoute" xmlns="http://www.topografix.com/GPX/1/1">',
    '  <metadata>',
    `    <name>${name}</name>`,
    '  </metadata>',
    ...waypoints,
    '  <trk>',
    `    <name>${name}</name>`,
    '    <trkseg>',
    ...trackPoints,
    '    </trkseg>',
    '  </trk>',
    '</gpx>',
    '',
  ].join('\n');
}

/** Namen sind frei editierbar - auch `&`, `<` und Anführungszeichen. */
function escapeXml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}
