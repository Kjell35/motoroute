# MotoRoute – Build-Anleitung

## Voraussetzungen

- Node.js 20+
- Flutter 3.4+
- Java 17 (für GraphHopper-Modul)
- Maven (für GraphHopper-Modul)
- Supabase-Projekt (für Backend)

## Backend (`motoroute_api`)

```bash
cd motoroute_api
cp .env.example .env   # echte Werte eintragen
npm install
npm run build
npm run start:dev
```

## Flutter-App (`motoroute_app`)

```bash
cd motoroute_app
flutter create . --project-name motoroute_app --org com.motoroute --platforms=android,ios
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

## GraphHopper (`graphhopper-curvature-ext`)

```bash
cd graphhopper-curvature-ext
mvn clean install
```

## Tests

```bash
# Backend (26 Unit-Tests)
cd motoroute_api
npm test

# Flutter (22 Unit-Tests)
cd motoroute_app
flutter test
```

## Linting

```bash
# Backend
cd motoroute_api
npm run lint

# Flutter
cd motoroute_app
flutter analyze
```