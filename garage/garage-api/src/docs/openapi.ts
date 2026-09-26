/**
 * OpenAPI-3.0-Spezifikation (Anforderung 14). Bewusst als Code-Objekt
 * gehalten - swagger-ui-express serviert sie direkt unter /api/docs,
 * roh unter /api/openapi.json.
 */

export const openapiSpec = {
  openapi: '3.0.3',
  info: {
    title: 'Garage API',
    version: '0.1.0',
    description: `Eigenständiges Fahrzeuggaragen-System (Motorräder + Autos).

**Kernfunktionen:** digitale Garage, zentrale Fahrzeugdatenbank (Hersteller/Modell/Variante/Specs),
Wartung mit automatischen Erinnerungen (grün/gelb/rot), Historie, Kosten, Reifen, Tankbuch, private Dokumente.

**Privatsphäre:** Kennzeichen, Kaufpreis, Kaufdatum und Notizen sind privat und verlassen
das System in geteilten Kontexten nie. Dokumente sind immer privat.

**Auth:** JWT-Bearer-Token via /api/auth/login.`,
  },
  servers: [{ url: '/', description: 'Basis-URL (lokaler Start oder Deployment)' }],
  components: {
    securitySchemes: {
      bearerAuth: { type: 'http', scheme: 'bearer', bearerFormat: 'JWT' },
    },
    schemas: {
      Error: {
        type: 'object',
        properties: { error: { type: 'string' }, message: { type: 'string' } },
      },
      AuthResult: {
        type: 'object',
        properties: {
          user: { $ref: '#/components/schemas/User' },
          accessToken: { type: 'string' },
        },
      },
      User: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          email: { type: 'string' },
          displayName: { type: 'string' },
          role: { type: 'string', enum: ['user', 'admin'] },
        },
      },
      Vehicle: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          category: { type: 'string', enum: ['motorcycle', 'car'] },
          manufacturerName: { type: 'string' },
          modelName: { type: 'string' },
          variantName: { type: 'string', nullable: true },
          year: { type: 'integer', nullable: true },
          nickname: { type: 'string', nullable: true },
          odometerKm: { type: 'integer' },
          licensePlate: { type: 'string', nullable: true, description: 'Privat - nur für den Owner sichtbar' },
          purchasePriceCents: { type: 'integer', nullable: true, description: 'Privat' },
          photoUrl: { type: 'string', nullable: true },
          isPublic: { type: 'boolean' },
        },
      },
      Reminder: {
        type: 'object',
        properties: {
          type: { type: 'string' },
          status: { type: 'string', enum: ['green', 'yellow', 'red', 'none'] },
          dueAt: { type: 'string', nullable: true },
          dueAtKm: { type: 'integer', nullable: true },
          messageDe: { type: 'string', example: 'Ölwechsel in 800 km' },
        },
      },
    },
  },
  paths: {
    '/api/health': { get: { summary: 'Health-Check', responses: { 200: { description: 'OK' } } } },
    '/api/auth/register': {
      post: {
        summary: 'Registrieren',
        requestBody: {
          required: true,
          content: { 'application/json': { schema: { type: 'object', required: ['email', 'password'], properties: { email: { type: 'string' }, password: { type: 'string' }, displayName: { type: 'string' } } } } },
        },
        responses: { 201: { description: 'Erstellt', content: { 'application/json': { schema: { $ref: '#/components/schemas/AuthResult' } } } }, 409: { description: 'E-Mail vergeben' } },
      },
    },
    '/api/auth/login': {
      post: {
        summary: 'Anmelden',
        requestBody: {
          required: true,
          content: { 'application/json': { schema: { type: 'object', required: ['email', 'password'], properties: { email: { type: 'string' }, password: { type: 'string' } } } } },
        },
        responses: { 200: { description: 'OK', content: { 'application/json': { schema: { $ref: '#/components/schemas/AuthResult' } } } }, 401: { description: 'Falsche Zugangsdaten' } },
      },
    },
    '/api/vehicles/garage': {
      get: {
        summary: 'Die Garage (Motorräder + Autos gruppiert, mit Erinnerungs-Badge)',
        security: [{ bearerAuth: [] }],
        responses: { 200: { description: 'OK' } },
      },
    },
    '/api/vehicles': {
      get: { summary: 'Alle Fahrzeuge', security: [{ bearerAuth: [] }], responses: { 200: { description: 'OK' } } },
      post: {
        summary: 'Fahrzeug anlegen',
        security: [{ bearerAuth: [] }],
        requestBody: { required: true, content: { 'application/json': { schema: { $ref: '#/components/schemas/Vehicle' } } } },
        responses: { 201: { description: 'Erstellt' }, 400: { description: 'Validierungsfehler', content: { 'application/json': { schema: { $ref: '#/components/schemas/Error' } } } } },
      },
    },
    '/api/vehicles/{id}': {
      get: { summary: 'Fahrzeugdetail', security: [{ bearerAuth: [] }], parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }], responses: { 200: { description: 'OK' }, 404: { description: 'Nicht gefunden' } } },
      put: { summary: 'Fahrzeug aktualisieren (inkl. Kilometerstand)', security: [{ bearerAuth: [] }], parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }], responses: { 200: { description: 'OK' } } },
      delete: { summary: 'Fahrzeug löschen', security: [{ bearerAuth: [] }], parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }], responses: { 204: { description: 'Gelöscht' } } },
    },
    '/api/vehicles/{id}/specifications': {
      get: { summary: 'Technische Daten aus der zentralen Fahrzeugdatenbank', security: [{ bearerAuth: [] }], parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }], responses: { 200: { description: 'OK' } } },
    },
    '/api/vehicles/{id}/reminders': {
      get: { summary: 'Automatische Wartungserinnerungen (grün/gelb/rot)', security: [{ bearerAuth: [] }], parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }], responses: { 200: { description: 'OK', content: { 'application/json': { schema: { type: 'object', properties: { reminders: { type: 'array', items: { $ref: '#/components/schemas/Reminder' } } } } } } } } },
    },
    '/api/vehicles/{id}/maintenance': {
      get: { summary: 'Wartungen (filterbar nach type)', security: [{ bearerAuth: [] }], parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }], responses: { 200: { description: 'OK' } } },
      post: { summary: 'Wartung erfassen', security: [{ bearerAuth: [] }], parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }], responses: { 201: { description: 'Erstellt' } } },
    },
    '/api/vehicles/{id}/maintenance/history': {
      get: { summary: 'Chronologische Wartungshistorie', security: [{ bearerAuth: [] }], parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }], responses: { 200: { description: 'OK' } } },
    },
    '/api/vehicles/{id}/maintenance/costs': {
      get: { summary: 'Kosten-Aggregation (Jahr, gesamt, Durchschnitt)', security: [{ bearerAuth: [] }], parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }], responses: { 200: { description: 'OK' } } },
    },
    '/api/vehicles/{id}/tires': {
      get: { summary: 'Reifen (mounted=true/false filtert montiert/abmontiert)', security: [{ bearerAuth: [] }], parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }], responses: { 200: { description: 'OK' } } },
      post: { summary: 'Reifen montieren', security: [{ bearerAuth: [] }], parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }], responses: { 201: { description: 'Erstellt' } } },
    },
    '/api/vehicles/{id}/fuel': {
      get: { summary: 'Tankbuch', security: [{ bearerAuth: [] }], parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }], responses: { 200: { description: 'OK' } } },
      post: { summary: 'Tankstopp erfassen', security: [{ bearerAuth: [] }], parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }], responses: { 201: { description: 'Erstellt' } } },
    },
    '/api/vehicles/{id}/fuel/stats': {
      get: { summary: 'Verbrauch & Kosten (aus VOLL-Tankungen)', security: [{ bearerAuth: [] }], parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }], responses: { 200: { description: 'OK' } } },
    },
    '/api/vehicles/{id}/documents': {
      get: { summary: 'Dokumente (privat)', security: [{ bearerAuth: [] }], parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }], responses: { 200: { description: 'OK' } } },
      post: { summary: 'Dokument-Metadaten speichern', security: [{ bearerAuth: [] }], parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }], responses: { 201: { description: 'Erstellt' } } },
    },
    '/api/catalog/search': {
      get: { summary: 'Fahrzeugdatenbank durchsuchen (Hersteller/Modell/Variante/Baujahr)', security: [{ bearerAuth: [] }], parameters: [{ name: 'q', in: 'query', schema: { type: 'string' } }, { name: 'category', in: 'query', schema: { type: 'string', enum: ['motorcycle', 'car'] } }, { name: 'year', in: 'query', schema: { type: 'integer' } }], responses: { 200: { description: 'OK' } } },
    },
    '/api/catalog/variants/{id}/specs': {
      get: { summary: 'Specs einer Variante', security: [{ bearerAuth: [] }], parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string' } }, { name: 'year', in: 'query', schema: { type: 'integer' } }], responses: { 200: { description: 'OK' } } },
    },
    '/api/admin/manufacturers': {
      post: { summary: 'Hersteller anlegen (Admin)', security: [{ bearerAuth: [] }], responses: { 201: { description: 'Erstellt' }, 403: { description: 'Kein Admin' } } },
    },
  },
} as const;
