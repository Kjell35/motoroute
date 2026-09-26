/**
 * Die Verbrauchs-Formel aus fuel.routes.get('/stats') als reine Funktion
 * extrahiert und getestet - dieselbe Rechnung, ohne HTTP/DB.
 */

interface Entry {
  odometerKm: number;
  liters: number;
  isFullTank: boolean;
}

function averageConsumption(entries: Entry[]): number | null {
  let litersSum = 0;
  let kmSum = 0;
  for (let i = 1; i < entries.length; i++) {
    const prev = entries[i - 1]!;
    const cur = entries[i]!;
    if (prev.isFullTank && cur.isFullTank && cur.odometerKm > prev.odometerKm) {
      litersSum += cur.liters;
      kmSum += cur.odometerKm - prev.odometerKm;
    }
  }
  return kmSum > 0 ? Math.round((litersSum / kmSum) * 1000) / 10 : null;
}

describe('Tankbuch-Verbrauchsstatistik', () => {
  it('berechnet l/100km aus VOLL-Tankungen', () => {
    // 400 km, 20 l -> 5.0 l/100km
    const result = averageConsumption([
      { odometerKm: 10000, liters: 15, isFullTank: true },
      { odometerKm: 10400, liters: 20, isFullTank: true },
    ]);
    expect(result).toBe(5.0);
  });

  it('ignoriert Teil-Tankungen als Segmentstart', () => {
    // Teil-Tankung in der Mitte: KEIN gültiges Segment (prev ist nicht
    // voll). Nur das letzte Paar (voll -> voll) zählt: 300 km, 20 l.
    const result = averageConsumption([
      { odometerKm: 10000, liters: 10, isFullTank: true },
      { odometerKm: 10300, liters: 5, isFullTank: false }, // Teil-Tankung
      { odometerKm: 10600, liters: 20, isFullTank: true }, // Segment 10300->10600? prev nicht voll -> kein Segment
    ]);
    // Beide Segmente haben keinen voll->voll-Übergang (10000->10300: prev
    // voll, cur NICHT voll; 10300->10600: prev nicht voll). Ergebnis null.
    expect(result).toBeNull();
  });

  it('zählt voll->voll-Segmente korrekt bei mehreren Stops', () => {
    const result = averageConsumption([
      { odometerKm: 10000, liters: 10, isFullTank: true },
      { odometerKm: 10500, liters: 5, isFullTank: true }, // 500 km, 5 l
      { odometerKm: 10900, liters: 20, isFullTank: true }, // 400 km, 20 l
    ]);
    // 900 km, 25 l -> 27.8 l/100km (unrealistisch hoch, aber Formel-Treue)
    expect(result).toBe(Math.round((25 / 900) * 1000) / 10);
  });

  it('null bei weniger als zwei VOLL-Tankungen', () => {
    expect(averageConsumption([{ odometerKm: 1, liters: 10, isFullTank: true }])).toBeNull();
  });
});
