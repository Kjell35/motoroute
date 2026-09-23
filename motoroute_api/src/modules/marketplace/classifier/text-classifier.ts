/**
 * Serverseitiger Text-Klassifikator fuer Marktplatz-Angebote.
 *
 * Erkennt aus Titel/Beschreibung/Marke/Modell/Kategorie, ob der Artikel
 * ueberhaupt zu Motorrad, Auto oder Fahrrad gehoert. Bewusst als
 * regelbasiertes System gebaut (Wortstamm-Matching auf DE/EN-Begriffen):
 * deterministisch, testbar und ohne Netz-Zugriff. Die Bildpruefung
 * (Gemini-Vision) kommt DADURCH HINAUS hinzu - die Textpruefung allein
 * waere umgehbar, deshalb entscheidet am Ende immer die kombinierte
 * Pruefung im ReviewService.
 *
 * Ergebnisse:
 *   RELEVANT  -> Text passt eindeutig zu Fahrzeugteilen
 *   FOREIGN   -> eindeutig fremdes Produkt (Toaster, PS5, iPhone ...)
 *   UNCERTAIN -> weder noch (z.B. "Originales Teil, selten benutzt")
 */

export type TextVerdict = 'RELEVANT' | 'FOREIGN' | 'UNCERTAIN';

/** Starke Signale fuer eindeutig FREMDE Produkte (Wortstaemme, case-insensitive). */
const FOREIGN_STEMS: RegExp[] = [
  // Haushalt/Kueche
  /toaster/, /kuehlschrank|kühlschrank|refrigerator|fridge/, /mikrowelle|microwave/,
  /kaffeemaschine|kaffeevollautomat|coffee\s?machine/, /wasserkocher|kettle/,
  /geschirrspueler|geschirrspüler|dishwasher/, /waschmaschine|washing\s?machine/,
  /trockner|dryer/, /herd|backofen|oven/, /mixer|standmixer|blender/,
  /pfanne|pan\b/, /topf|pot\b/, /besteck|cutlery/, /geschirr|dishes|tableware/,
  /staubsauger|vacuum/, /buegeleisen|bügeln|iron\b/, /fritteuse|fryer/,
  // Unterhaltungselektronik
  /playstation|ps[2-5]\b/, /xbox/, /nintendo|switch\b|wii\b/, /steam\s?deck/,
  /fernseher|tv\b|television/, /beamer|projector/, /soundbar|heimkino|hifi|stereoanlage/,
  /lautsprecher|speaker|boxen\b/, /koplhoerer|kopfhörer|headphone|earbud|airpod/,
  // Computer/Handy
  /iphone/, /smartphone|handy\b|android\b/, /ipad|tablet\b/, /laptop|notebook|macbook/,
  /pc\b|rechner|computer|desktop\b/, /monitor|bildschirm/, /tastatur|keyboard/,
  /maus\b|mouse\b/, /drucker|printer/, /router|modem/, /gaming|gamer|konsol|console/,
  /grafikkarte|cpu\b|prozessor|mainboard|ram\b|ssd\b|festplatte/,
  // Moebel/Wohnen
  /sofa|couch/, /stuhl|chair/, /tisch|table\b/, /schrank|wardrobe|cupboard/,
  /bett\b|bed\b/, /matratze|mattress/, /regal|shelf|shelves/, /kommode|dresser/,
  /gartenmoebel|garden\s?furniture/, /lampe|leuchte|lamp/,
  // Kleidung/Sonstiges
  /jacke\b|jacket/, /hemd\b|shirt/, /hose\b|trouser|jeans/, /schuh|shoe|sneaker/,
  /kleid\b|dress\b/, /pullover|sweater|hoodie/, /spielzeug|toy\b|lego/,
  /puzzle/, /buch\b|book\b/, /vinyl|schallplatte|cd\b|dvd\b|blu-?ray/,
  /kosmetik|parfum|perfume|creme\b/, /lebensmittel|food\b/,
];

/**
 * Starke Signale fuer eindeutig FAHRZEUGBEZOGENE Angebote. Ein Treffer
 * gewichtet deutlich: Teile-Wortschatz + Fahrzeug-/Marken-Kontext.
 */
const PART_STEMS: RegExp[] = [
  // Antrieb/Motor
  /motor/, /zylinder|cylinder/, /kolben|piston/, /kupplung|clutch/,
  /getriebe|gearbox|transmission/, /kurbelwelle|crank/, /nockenwelle|camshaft/,
  /ventil\b|valve/, /dichtung|gasket/, /oelpumpe|oil\s?pump/, /riemen|belt\b/,
  /kette\b|chain\b/, /antrieb|drivetrain/, /schaltung|derailleur|shifter/,
  /pedale|pedal/, /kurbel\b|crankset/,
  // Auspuff
  /auspuff|exhaust/, /kruemmer|krümmer|header/, /schalldämpfer|schalldaempfer|muffler|silencer/,
  /endtopf|abgasanlage/,
  // Fahrwerk
  /fahrwerk|suspension/, /st(o|ö|oe)(ss|ß)?d(a|ä|ae)mpfer|shock\s?absorber/,
  /gabel|fork\b/, /feder|spring\b/, /swingarm|laengsträger|lenker|handlebar/,
  /rahmen\b|frame\b/, /gabelschaft|steuersatz|headset/,
  // Bremsen
  /bremse|brake/, /bremsscheibe|brake\s?disc|rotor/, /bremsbelag|brake\s?pad/,
  /bremssattel|caliper/, /bremsleitung|brake\s?line/, /bremszange/,
  // Elektrik
  /batterie|battery|akku\b/, /lichtmaschine|alternator/, /anlasser|starter/,
  /zündkerze|zuendkerze|spark\s?plug/, /zündspule|ignition\s?coil/, /steuergerät|steuergeraete|ecu\b|cdi\b/,
  /licht\b|headlight|scheinwerfer|blink|tail\s?light|lamp/, /kabelbaum|wiring|harness/,
  // Räder
  /felge|rim\b/, /reifen|tire\b|tyre\b/, /nabe\b|hub\b/, /speiche|spoke/,
  /laufrad|wheelset/, /radlager|wheel\s?bearing/,
  // Karosserie/Verkleidung
  /verkleidung|fairing/, /kotflügel|kotfluegel|fender|mudguard/, /tank\b/,
  /haube\b|hood\b/, /heckklappe|trunk\s?lid|boot\s?lid/, /stossstange|stoßstange|bumper/,
  /spiegel\b|mirror/, /scheibe\b|windshield|windschutz|visier/,
  // Zubehör
  /gepäck|gepaeck|luggage|topcase|koffer|satteltasche|pannier/,
  /halterung|mount|bracket/, /schutz|protection| crash\s?bar|sturzbügel/,
  /kofferraum|gepäckträger|rack\b/, /helm\b|helmet/, /handschuh|glove/,
  // Fahrrad-spezifisch
  /schaltwerk|rear\s?derailleur/, /umwerfer|front\s?derailleur/, /griff|grip\b/,
  /sattel|saddle|seat\b/, /sattelstütze|seatpost/, /vorbau|stem\b/,
  /e-?bike|pedelec/, /nabe\b|dynamo/,
  // Autoteile
  /insasse|innenraum|interior|armaturenbrett|dashboard/, /tür\b|tuer\b|door\b/,
  /airbag/, /lenkung|steering/, /servolenkung|lenkrad|steering\s?wheel/,
  /kühler|radiator|intercooler/, /turbo|lader\b/, /einspritzung|injection/,
  /diesel|benzin|otto\b/, /keilriemen|timing\s?belt/,
];

/** Fahrzeug-Kontext: Marken, Modelle, Fahrzeug-Typen. */
const VEHICLE_CONTEXT: RegExp[] = [
  // Motorrad-Marken
  /bmw\b|motorrad/, /yamaha/, /honda/, /suzuki/, /kawasaki/, /ktm/, /ducati/,
  /triumph/, /aprilia/, /mv\s?agusta/, /moto\s?guzzi/, /husqvarna/, /benelli/,
  /royal\s?enfield/, /harley|davidson/, /hyosung/, /sym\b/, /piaggio/, /vespa/,
  /gilera/, /peugeot\s?motocycles/, /kundgebung/,
  // Modellnamen (typische Motorrad-Reihen)
  /\bgs\b|\bgsr\b|\bgsx|cbr|cb\b|r[1-9]\b|mt-?0?[2-9]|ninja|z[6-9]00|hornet|tiger|explorer|multistrada|monster|streetfighter|panigale|s1000|f850|r1250|r1200|nc750|cb500|xmax|tmax|nmax|pcx|sh\b|aerox/,
  // Auto-Marken
  /volkswagen|vw\b|audi|opel|ford\b|mercedes|bmw\b|skoda|seat\b|porsche|renault|peugeot|citroen|fiat\b|alfa\s?romeo|volvo|toyota|nissan|mazda|mitsubishi|subaru|hyundai|kia\b|dacia|chevrolet|dodge|jeep\b|mini\b|smart\b|tesla|land\s?rover|jaguar|bentley|lamborghini|ferrari/,
  // Auto-Modelle
  /golf\b|passat|polo\b|tiguan|touran|caddy|astra|insignia|corsa|zafira|focus|fiesta|mondeo|kuga|escort|klasse\b|3er|5er|7er|octavia|fabia|superb|leon\b|ibiza|911\b|cayenne|macan|boxster|c4\b|c3\b|c5\b|berlingo|panda|punto|500\b|giulietta|giulia|mito|v40|v60|xc90|s60|s80|corolla|yaris|auris|avensis|hilux|cruiser|leaf\b|qashqai|juke\b|micra|trail\b|navara|cx-[35]|mx-5|outback|forester|legacy|impreza|i30|i20|i10|tucson|sportage|ceed|picanto|logan|sandero|duster|captur|clio|megane|twingo|kangoo|208\b|3008|308\b|508/,
  // Fahrrad-Marken
  /shimano|sram\b|campagnolo|cube\b|canyon|giant\b|trek\b|specialized|scott\b|merida|rose\b|kalkhoff|haibike|stevens|radon|ghost\b|felt\b|bmc\b|pinarello|colnago|bianchi|cervelo|cannondale/,
  // Fahrrad-Typen
  /mountainbike|mtb\b|rennrad|road\s?bike|crossrad|trekkingrad|cityrad|city\s?bike|e-?bike|pedelec|hollandrad|bmx\b|downhill|enduro/,
  // Fahrzeug-Typen allgemein
  /motorrad|motorbike|motorcycle|moped|mofa|roller|scooter|quad\b|trike\b/,
];

function normalize(text: string): string {
  return text.toLowerCase().replace(/\s+/g, ' ').trim();
}

export interface TextInput {
  title: string;
  description?: string;
  brand?: string;
  model?: string;
  category?: string;
  subcategory?: string;
}

export interface TextReview {
  verdict: TextVerdict;
  /** Gewichte fuer die kombinierte Entscheidung (Vision-Service). */
  relevanceHits: number;
  foreignHits: number;
  contextHits: number;
}

/**
 * Klassifiziert den Text eines Angebots. Kein Netz, deterministisch.
 */
export function classifyText(input: TextInput): TextReview {
  const haystack = normalize(
    [
      input.title,
      input.title,
      input.title, // Titel 3x gewichten
      input.description ?? '',
      input.brand ?? '',
      input.model ?? '',
    ].join(' \u2022 '),
  );

  const relevanceHits = PART_STEMS.filter((re) => re.test(haystack)).length;
  const foreignHits = FOREIGN_STEMS.filter((re) => re.test(haystack)).length;
  const contextHits = VEHICLE_CONTEXT.filter((re) => re.test(haystack)).length;

  let verdict: TextVerdict;
  if (foreignHits > 0 && relevanceHits === 0) {
    // Eindeutig fremdes Produkt, null Teile-Vokabular
    verdict = 'FOREIGN';
  } else if (relevanceHits >= 1 && foreignHits === 0) {
    verdict = 'RELEVANT';
  } else if (relevanceHits >= 2 && foreignHits >= 1) {
    // Mischtext: Beschreibung erwaehnt z.B. "passt nicht in den Kuehlschrank"
    // - zwei klare Teile-Signale schlagen einen Fremd-Begriff.
    verdict = 'RELEVANT';
  } else {
    verdict = 'UNCERTAIN';
  }

  // Kategorie-Kontext hilft nicht alleine ("Sonstiges" darf niemand nutzen,
  // um Fremdes durchzuschleusen) - er fliesst nur in die Gewichtung ein.
  return { verdict, relevanceHits, foreignHits, contextHits };
}
