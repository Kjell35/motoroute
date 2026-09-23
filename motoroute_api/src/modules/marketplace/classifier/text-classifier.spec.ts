import { classifyText } from './text-classifier';

/**
 * Der Klassifikator ist die erste Verteidigungslinie des Marktplatzes:
 * Die Anforderung verlangt explizit, dass Toaster/PS5/iPhone/Fernseher
 * abgelehnt und Fahrzeugteile zugelassen werden.
 */
describe('Text-Klassifikator (Marktplatz-KI, Stufe 1)', () => {
  // --- Erlaubte Angebote (Anforderung 1/5) -------------------------------
  const allowedCases: [string, string][] = [
    ['BMW R1250 Auspuff', 'motorcycle exhaust'],
    ['Yamaha MT-07 Bremsscheibe', 'vorne und hinten, wenig gebraucht'],
    ['Shimano Fahrradschaltung', 'Deore XT, 11-fach'],
    ['VW Golf Felgen', '4 Stueck 16 Zoll Alufelgen'],
    ['Motorradkette neu', 'passt fuer 525er Umschlung'],
    ['Hauptbremszylinder Honda CB500', 'originales Ersatzteil'],
    ['E-Bike Akku 500Wh', 'Bosch Powertube, gut erhalten'],
    ['Stoßdaempfer hinten KTM', 'fertig eingestellt'],
  ];

  it.each(allowedCases)('laesst zu: "%s"', (title, description) => {
    const result = classifyText({ title, description });
    expect(result.verdict).toBe('RELEVANT');
    expect(result.relevanceHits).toBeGreaterThan(0);
  });

  // --- Verbotene Angebote (Anforderung 1/5) ------------------------------
  const blockedCases: [string, string][] = [
    ['Toaster', '2 Scheiben, Edelstahl, kaum benutzt'],
    ['PlayStation 5', 'neuwertig, mit 2 Controllern'],
    ['Fernseher 55 Zoll', '4K Smart TV'],
    ['iPhone 13', '128 GB, sehr gut'],
    ['Wandregal', 'weiss, 3 Boeden'],
    ['Kaffeemaschine', 'Vollautomat mit Mahlwerk'],
    ['Sofa 3-Sitzer', 'grau, inkl. Kissen'],
    ['Gaming Notebook', 'RTX 4070'],
  ];

  it.each(blockedCases)('lehnt ab: "%s"', (title, description) => {
    const result = classifyText({ title, description });
    expect(result.verdict).toBe('FOREIGN');
  });

  // --- Unsichere Faelle (Anforderung 9) ----------------------------------
  const uncertainCases: [string, string][] = [
    ['Originales Teil', 'selten benutzt, nur an Gewittertagen gefahren'],
    ['Wie neu', 'wurde 2x benutzt'],
  ];

  it.each(uncertainCases)('stuft unsicher ein: "%s"', (title, description) => {
    const result = classifyText({ title, description });
    expect(result.verdict).toBe('UNCERTAIN');
  });

  // --- Gewichtung: Teile-Vokabular schlaegt einzelnen Fremd-Begriff ------
  it('bleibt RELEVANT, wenn die Beschreibung zufaellig ein Fremdwort enthaelt', () => {
    const result = classifyText({
      title: 'Auspuffanlage Yamaha MT-07',
      description: 'Passt NICHT auf andere Modelle. Wegen Umbau auf einen Endtopf abzugeben. Kein Versand an Packstation.',
    });
    expect(result.verdict).toBe('RELEVANT');
  });

  it('gewichtet den Titel dreifach gegen die Beschreibung', () => {
    // Titel klar Fahrzeugteil, Beschreibung neutral lang.
    const result = classifyText({
      title: 'Bremssattel vorne BMW',
      description: 'Estado muy bueno, funciona perfectamente.',
    });
    expect(result.verdict).toBe('RELEVANT');
  });

  it('ist deterministisch', () => {
    const input = { title: 'Kettenkit Yamaha', description: 'Kette, Kettenrad, Ritzel' };
    expect(classifyText(input)).toEqual(classifyText(input));
  });
});
