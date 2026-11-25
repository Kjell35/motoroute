#!/usr/bin/env bash
# Beweist den R8-Mapping-Kreis einmal vollstaendig:
#   1. Release-Build mit eingebauter Absturzsonde (-PcrashProbe=true)
#   2. Start auf einem Emulator/Geraet mit dem Extra `crash_probe`
#   3. Absturzbericht aus dem Crash-Buffer holen
#   4. Trace mit dem Mapping der *diesem* Build entstammenden Datei aufloesen
#
# Voraussetzungen: Flutter, laufendes Android-Geraet/Emulator (x86_64 oder
# arm64, je nach Ziel), Java auf PATH oder in JAVA_HOME, Android SDK.
#
# Ergebnis: .artifacts/r8-probe/ mit Rohbericht, verschleiertem und
# aufgeloestem Trace. Exit 0 nur, wenn der aufgeloeste Trace die
# Sonden-Frames zeigt und der Rohbericht verschleiert war.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP=apps/mobile
OUT=${R8_PROBE_OUT:-.artifacts/r8-probe}
MAP="$APP/build/app/outputs/mapping/release/mapping.txt"
APK="$APP/build/app/outputs/flutter-apk/app-release.apk"
PKG=de.motoroute.app
ACTIVITY="$PKG/.MainActivity"
EXTRA=crash_probe
PROBE_PKG=de.motoroute.probe
PROBE_CLASS="$PROBE_PKG.CrashProbe"
TARGET_PLATFORM=${R8_PROBE_TARGET:-android-x64}

mkdir -p "$OUT"
fail() { echo "FEHLER: $*" >&2; exit 1; }

# --- Werkzeuge ---
SDK=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
if [ -z "$SDK" ] && command -v cygpath >/dev/null 2>&1; then
    SDK="$(cygpath -u "${LOCALAPPDATA:-}")/Android/Sdk"
fi
[ -d "$SDK" ] || fail "Android SDK nicht gefunden - ANDROID_HOME setzen."
ADB="$SDK/platform-tools/adb.exe"
[ -x "$ADB" ] || ADB="$SDK/platform-tools/adb"
[ -x "$ADB" ] || fail "adb nicht gefunden unter $SDK/platform-tools."

RETRACE_JAR=$(find "$SDK/build-tools" -path "*/lib/d8.jar" 2>/dev/null | sort -V | tail -1)
[ -n "$RETRACE_JAR" ] || fail "kein build-tools/*/lib/d8.jar gefunden (enthaelt retrace)."

JAVA=${JAVA_HOME:+$JAVA_HOME/bin/java}
if [ -z "$JAVA" ] || [ ! -x "$JAVA" ]; then
    JAVA=$(command -v java || true)
fi
[ -n "$JAVA" ] || fail "kein java gefunden - JAVA_HOME setzen oder Java in den PATH legen."

DEVICE=$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')
[ -n "$DEVICE" ] || fail "kein Geraet/Emulator verbunden (adb devices ist leer)."
echo "== Geraet: $DEVICE   Mapping: $MAP"

# --- Build mit Sonde ---
PROPS="$APP/android/gradle.properties"
cp "$PROPS" "$OUT/gradle.properties.bak"
restore() { cp "$OUT/gradle.properties.bak" "$PROPS"; }
trap restore EXIT

if ! grep -q '^crashProbe=true$' "$PROPS"; then
    printf '\ncrashProbe=true\n' >> "$PROPS"
fi

# Von einem leeren build/ bauen: Kotlin bettet BuildConfig-Konstanten beim
# Uebersetzen ein, und AGP hat hier schon beides getan - eine Uebersetzung aus
# einem Normalbau (CRASH_PROBE=false) wiederverwenden (R8 entfernt die Sonde
# dann als toten Code) oder ein veraltetes Mapping behalten. Beides macht den
# Beweis wertlos, deshalb ohne Zwischenstaende.
rm -rf "$APP/build"

echo "== Release-Build mit Sonde ($TARGET_PLATFORM)"
( cd "$APP" && flutter build apk --release --target-platform "$TARGET_PLATFORM" ) \
    > "$OUT/build.log" 2>&1 || { tail -20 "$OUT/build.log" >&2; fail "Build fehlgeschlagen (siehe $OUT/build.log)."; }

[ -f "$APK" ] || fail "APK fehlt: $APK"
[ -f "$MAP" ] || fail "Mapping fehlt: $MAP"

grep -q "^$PROBE_CLASS -> " "$MAP" \
    || fail "Sonde steht nicht im Mapping - Build ohne -PcrashProbe?"

OBF_CLASS=$(grep "^$PROBE_CLASS -> " "$MAP" | head -1 | sed 's/.* -> //; s/:$//')
case "$OBF_CLASS" in
    *REMOVED*) fail "Sonde wurde von R8 entfernt statt umbenannt (probe-rules.pro nicht geladen?)." ;;
esac
[ "$OBF_CLASS" != "$PROBE_CLASS" ] \
    || fail "Sonde behielt ihren Namen - das Mapping beweist nichts."
echo "== Umbenannt zu: $OBF_CLASS"

# --- Absturz ausloesen ---
echo "== Installieren und starten mit --ez $EXTRA true"
"$ADB" -s "$DEVICE" shell am force-stop "$PKG" >/dev/null 2>&1 || true
"$ADB" -s "$DEVICE" install -r "$APK" > "$OUT/install.log" 2>&1 \
    || { tail -5 "$OUT/install.log" >&2; fail "Installation fehlgeschlagen."; }
"$ADB" -s "$DEVICE" logcat -c
"$ADB" -s "$DEVICE" shell am start -n "$ACTIVITY" --ez "$EXTRA" true > "$OUT/start.log" 2>&1
sleep 8

"$ADB" -s "$DEVICE" logcat -d -b crash > "$OUT/crash-logcat.txt" 2>/dev/null || true
[ -s "$OUT/crash-logcat.txt" ] || fail "Crash-Buffer ist leer - Sonde nicht ausgeloest?"

# --- Trace extrahieren ---
sed -E 's/^[0-9]{2}-[0-9]{2} [0-9:.]+ +[0-9]+ +[0-9]+ E AndroidRuntime: //' "$OUT/crash-logcat.txt" \
    | grep -E '^(java\.|Caused by|	at |FATAL EXCEPTION|Process:)' \
    > "$OUT/trace-obfuscated.txt" || true

grep -q 'r8-map-id-' "$OUT/trace-obfuscated.txt" || fail "Trace enthaelt keine R8-Map-ID - kein verschleierter Build."
if grep -q "$PROBE_CLASS" "$OUT/trace-obfuscated.txt"; then
    fail "Trace nennt die Sonde im Klartext - nichts zu beweisen."
fi
MAP_ID=$(grep -o 'r8-map-id-[0-9a-f]*' "$OUT/trace-obfuscated.txt" | head -1 | sed 's/r8-map-id-//')
grep -q "$MAP_ID" "$MAP" || fail "Map-ID $MAP_ID steht nicht im Mapping - Trace und Mapping passen nicht zusammen."
echo "== Map-ID: $MAP_ID (im Mapping bestaetigt)"

# --- Aufloesen ---
"$JAVA" -cp "$RETRACE_JAR" com.android.tools.r8.retrace.Retrace "$MAP" "$OUT/trace-obfuscated.txt" \
    > "$OUT/trace-retraced.txt" 2>&1 || { cat "$OUT/trace-retraced.txt" >&2; fail "retrace fehlgeschlagen."; }

grep -q "$PROBE_CLASS.explode(" "$OUT/trace-retraced.txt" \
    || fail "retrace zeigt CrashProbe.explode nicht (siehe $OUT/trace-retraced.txt)."
grep -q "$PKG.MainActivity.onCreate(" "$OUT/trace-retraced.txt" \
    || fail "retrace zeigt MainActivity.onCreate nicht."

echo
echo "== BESTANDEN"
echo "   verschleiert: $(grep -m1 -o 'at [A-Za-z0-9$]*\.[a-z]*(' "$OUT/trace-obfuscated.txt" || echo '-')"
grep -m3 'CrashProbe\|MainActivity.onCreate(' "$OUT/trace-retraced.txt" | sed 's/^/   aufgeloest: /'
echo "   Dateien: $OUT/trace-obfuscated.txt, $OUT/trace-retraced.txt"
