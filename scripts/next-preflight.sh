set -euo pipefail
FAILED=0
report() {
  if [ "$STRICT" = "1" ]; then
    echo "::error::$1"
  else
    echo "::warning::$1 (auf einem Release-Tag bricht der Job hier ab)"
  fi
  FAILED=1
}
die() {
  report "$1"
  if [ "$STRICT" = "1" ]; then
    exit 1
  fi
  exit 0
}

STRICT=0
RELEASE_TAG=""
if [[ "$GITHUB_REF" == refs/tags/next-v* ]]; then
  STRICT=1
  RELEASE_TAG="$GITHUB_REF_NAME"
elif [ -n "${RELEASE_TAG_INPUT:-}" ]; then
  # workflow_dispatch: der Release entsteht unter release_tag. Der Tag wird
  # hier genauso streng geprueft wie ein gepushter - sonst koennte ein
  # Release unter einem Tag entstehen, das nicht zur pubspec passt.
  STRICT=1
  RELEASE_TAG="$RELEASE_TAG_INPUT"
  if [[ "$RELEASE_TAG" != next-v* ]]; then
    die "release_tag '$RELEASE_TAG' beginnt nicht mit 'next-v' - der Release wuerde unter einem fremden Tag entstehen."
  fi
fi
PUBSPEC_VERSION=$(sed -n 's/^version: *//p' pubspec.yaml | head -n1)
if [ -z "$PUBSPEC_VERSION" ]; then
  die "apps/motoroute_next/pubspec.yaml hat keine version-Zeile - der Vergleich waere wirkungslos."
fi
if [[ "$PUBSPEC_VERSION" != *+* ]]; then
  die "version in apps/motoroute_next/pubspec.yaml ist '$PUBSPEC_VERSION' - ohne +versionCode keine Monotoniepruefung."
fi
BASE_CODE="${PUBSPEC_VERSION#*+}"
# Sollwert fuer den versionName: der Tag (gepusht oder eingegeben), sonst die
# Version, die als naechstes getaggt wird.
if [ "$STRICT" = "1" ]; then
  EXPECTED="${RELEASE_TAG#next-v}"
else
  EXPECTED="${PUBSPEC_VERSION%%+*}"
fi
if [ -z "$EXPECTED" ]; then
  die "versionName-Sollwert nicht bestimmbar - der Vergleich waere wirkungslos."
fi
if [ "$STRICT" = "1" ] && [ "${PUBSPEC_VERSION%%+*}" != "$EXPECTED" ]; then
  report "Tag $RELEASE_TAG passt nicht zu apps/motoroute_next/pubspec.yaml ($PUBSPEC_VERSION) - erst bumpen, dann taggen."
fi
# Vergleichswert fuer die Build-Nummer: der Vorgaenger-Tag. Nur
# Git-Tags, kein Zustand zwischen Laeufen; der Checkout ist flach,
# die Tags werden deshalb nachgeladen.
if ! git fetch --quiet --depth=1 --force origin 'refs/tags/next-v*:refs/tags/next-v*'; then
  die "Tags liessen sich nicht nachladen - ohne Vorgaenger waere die Build-Nummer ungeprueft."
fi
DESC=$(git tag --list 'next-v*' --sort=-v:refname)
PREV=""
if [ "$STRICT" = "1" ]; then
  if grep -qx "$RELEASE_TAG" <<< "$DESC"; then
    # Bekannter Tag (auch ein erneuter workflow_dispatch darauf): der
    # Vergleichswert ist der naechstaeltere Tag.
    # shellcheck disable=SC2016 # awk-Programm, kein Shell-Ausdruck
    PREV=$(awk -v cur="$RELEASE_TAG" '$0 == cur { found = 1; next } found { print; exit }' <<< "$DESC")
  elif [[ "$GITHUB_REF" == refs/tags/next-v* ]]; then
    die "Tag $RELEASE_TAG fehlt in der Tag-Liste - Reihenfolge unklar, Build-Nummer waere ungeprueft."
  else
    # workflow_dispatch auf einen noch nicht existierenden Tag: dieser Lauf
    # legt ihn an, Vergleichswert ist der neueste vorhandene Tag.
    PREV=$(head -n1 <<< "$DESC")
    echo "Tag $RELEASE_TAG existiert noch nicht - verglichen wird mit ${PREV:-keinem}."
  fi
else
  PREV=$(head -n1 <<< "$DESC")
fi
if [ -z "$PREV" ]; then
  echo "::warning::Kein vorheriger v*-Tag gefunden - Build-Nummer bleibt ungeprueft (erster Release dieser Art)."
else
  PREV_VERSION=$(git show "$PREV:apps/motoroute_next/pubspec.yaml" | sed -n 's/^version: *//p' | head -n1)
  if [[ "$PREV_VERSION" != *+* ]]; then
    die "version in $PREV ist '$PREV_VERSION' - ohne +versionCode nicht vergleichbar."
  fi
  PREV_CODE="${PREV_VERSION#*+}"
  echo "vorher ($PREV): Build-Nummer $PREV_CODE - jetzt: $BASE_CODE"
  if [ "$BASE_CODE" -le "$PREV_CODE" ]; then
    report "Build-Nummer $BASE_CODE ist nicht hoeher als bei $PREV ($PREV_CODE) - Android bietet dann kein Update an. Bitte in apps/motoroute_next/pubspec.yaml erhoehen."
  fi
fi
if [ "$FAILED" = "1" ]; then
  if [ "$STRICT" = "1" ]; then
    exit 1
  fi
  echo "::notice::Preflight: die Abweichungen oben sind auf einem Branch nur Warnungen - bitte vor dem Taggen beheben."
fi
{
  echo "version=$EXPECTED"
  echo "build_code=$BASE_CODE"
} >> "$GITHUB_OUTPUT"
echo "Preflight-Werte: versionName $EXPECTED, Build-Nummer $BASE_CODE"
echo "Preflight ok: versionName $EXPECTED, Build-Nummer $BASE_CODE (Vorgaenger ${PREV:-keiner})."
