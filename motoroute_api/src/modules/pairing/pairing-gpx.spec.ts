import { NotFoundException } from '@nestjs/common';
import type { Response } from 'express';
import { PairingGpxController } from './pairing-gpx.controller';
import { buildGpx, GpxPoint } from './pairing-gpx';
import { PairingService } from './pairing.service';

const points: GpxPoint[] = [
  { label: 'Eibsee', detail: null, lat: 47.4211, lon: 10.9848 },
  { label: 'Zugspitze & Co <b>', detail: null, lat: 47.5, lon: 11.5 },
];

describe('GPX-Export: Datei', () => {
  it('enthält jeden Punkt als Wegpunkt und als Trackpunkt', () => {
    const gpx = buildGpx('K7G7YY', points);

    expect(gpx.startsWith('<?xml version="1.0" encoding="UTF-8"?>')).toBe(true);
    expect(gpx).toContain('xmlns="http://www.topografix.com/GPX/1/1"');
    expect(gpx.match(/<wpt /g)).toHaveLength(2);
    expect(gpx.match(/<trkpt /g)).toHaveLength(2);
    expect(gpx).toContain('<wpt lat="47.4211" lon="10.9848">');
    expect(gpx).toContain('<name>Eibsee</name>');
    expect(gpx).toContain('<name>MotoRoute K7G7YY</name>');
  });

  it('escaped Namen, damit die Datei gültiges XML bleibt', () => {
    const gpx = buildGpx('K7G7YY', points);

    expect(gpx).toContain('<name>Zugspitze &amp; Co &lt;b&gt;</name>');
    expect(gpx).not.toContain('<b>');
  });

  it('liefert ohne Punkte eine gültige, leere Datei', () => {
    const gpx = buildGpx('K7G7YY', []);

    expect(gpx).toContain('<trkseg>');
    expect(gpx).not.toContain('<wpt ');
    expect(gpx.trimEnd().endsWith('</gpx>')).toBe(true);
  });
});

describe('GPX-Export: Download', () => {
  function controllerFor(result: GpxPoint[] | null): { controller: PairingGpxController; res: any } {
    const controller = new PairingGpxController({
      getPoints: async () => result,
    } as unknown as PairingService);
    const res: any = {
      setHeader: jest.fn(),
      send: jest.fn(),
    };
    return { controller, res };
  }

  it('liefert die Datei als Download mit Dateinamen', async () => {
    const { controller, res } = controllerFor(points);

    await controller.download('k7g7yy', res as Response);

    expect(res.setHeader).toHaveBeenCalledWith(
      'Content-Type',
      'application/gpx+xml; charset=utf-8',
    );
    // Kleingeschriebener Code in der URL wird normalisiert.
    expect(res.setHeader).toHaveBeenCalledWith(
      'Content-Disposition',
      'attachment; filename="MotoRoute-K7G7YY.gpx"',
    );
    expect(res.send.mock.calls[0][0]).toContain('<name>Eibsee</name>');
  });

  it('meldet unbekannte oder abgelaufene Codes als 404', async () => {
    const { controller, res } = controllerFor(null);

    await expect(controller.download('ZZZZZZ', res as Response)).rejects.toBeInstanceOf(
      NotFoundException,
    );
    expect(res.send).not.toHaveBeenCalled();
  });
});
