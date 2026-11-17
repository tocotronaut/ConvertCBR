
#!/bin/zsh

# ==========================================
# CBR to CBZ Converter for macOS
#
# Requires:
#   - unar
#   - zip
#   - osascript (macOS)
#
# Features:
#   - Recursive CBR search
#   - Preserves folder structure
#   - Finder tag: cbz-konvertiert
#   - Optional deletion of original files
#   - Progress display
#   - No overwriting existing CBZ files
# ==========================================

# ------------------------------------------
# Einstellungen
# ------------------------------------------

DELETE_ORIGINAL=false
FINDER_TAG="cbz-konvertiert"

ROOT_DIR="."

# ------------------------------------------
# Kommandozeilenoptionen
# ------------------------------------------

for arg in "$@"; do
    case "$arg" in
        --delete)
            DELETE_ORIGINAL=true
            ;;
        *)
            ROOT_DIR="$arg"
            ;;
    esac
done

# ------------------------------------------
# Temporäres Arbeitsverzeichnis
# ------------------------------------------

TEMP_DIR=$(mktemp -d)

cleanup() {
    rm -rf "$TEMP_DIR"
}

trap cleanup EXIT INT TERM

# ------------------------------------------
# Abhängigkeiten prüfen
# ------------------------------------------

if ! command -v unar >/dev/null 2>&1; then
    echo "FEHLER: unar wurde nicht gefunden."
    exit 1
fi

if ! command -v zip >/dev/null 2>&1; then
    echo "FEHLER: zip wurde nicht gefunden."
    exit 1
fi

if ! command -v osascript >/dev/null 2>&1; then
    echo "FEHLER: osascript wurde nicht gefunden."
    exit 1
fi

if [[ ! -d "$ROOT_DIR" ]]; then
    echo "FEHLER: Ordner existiert nicht: $ROOT_DIR"
    exit 1
fi

# ------------------------------------------
# Finder-Tag setzen
# ------------------------------------------

set_finder_tag() {
    local file="$1"

    osascript - "$file" "$FINDER_TAG" <<'APPLESCRIPT'
on run argv
    set targetFile to POSIX file (item 1 of argv) as alias
    set targetTag to item 2 of argv

    tell application "Finder"
        set tag names of targetFile to {targetTag}
    end tell
end run
APPLESCRIPT
}

# ------------------------------------------
# CBR-Dateien suchen
# ------------------------------------------

echo ""
echo "Suche nach CBR-Dateien..."
echo ""

typeset -a files

files=("${(@f)$(find "$ROOT_DIR" -type f -iname '*.cbr' -print)}")

TOTAL=${#files}
COUNT=0
SUCCESS=0
FAILED=0
SKIPPED=0
TAGGED=0
DELETED=0

if (( TOTAL == 0 )); then
    echo "Keine CBR-Dateien gefunden."
    exit 0
fi

echo "Gefunden: $TOTAL CBR-Dateien"
echo "Finder-Tag: $FINDER_TAG"
echo "Originale löschen: $DELETE_ORIGINAL"
echo ""

# ------------------------------------------
# Konvertierung
# ------------------------------------------

for file in "${files[@]}"; do

    (( COUNT++ ))

    OUTPUT="${file%.*}.cbz"
    WORK="$TEMP_DIR/work"

    PERCENT=$(( COUNT * 100 / TOTAL ))

    echo ""
    echo "------------------------------------------"
    echo "[$COUNT/$TOTAL - $PERCENT%]"
    echo "$file"
    echo "------------------------------------------"

    # Existierende CBZ überspringen
    if [[ -e "$OUTPUT" ]]; then
        echo "Übersprungen: CBZ existiert bereits."
        (( SKIPPED++ ))
        continue
    fi

    # Arbeitsverzeichnis vorbereiten
    rm -rf "$WORK"
    mkdir -p "$WORK"

    # --------------------------------------
    # CBR entpacken
    # --------------------------------------

    echo "Entpacke Archiv..."

    if ! unar -quiet -output-directory "$WORK" "$file"; then
        echo "FEHLER: Entpacken fehlgeschlagen."
        (( FAILED++ ))
        continue
    fi

    # Prüfen, ob Dateien vorhanden sind
    if [[ -z "$(find "$WORK" -type f -print -quit)" ]]; then
        echo "FEHLER: Archiv enthält keine Dateien."
        (( FAILED++ ))
        continue
    fi

    # --------------------------------------
    # CBZ erstellen
    # --------------------------------------

    echo "Erstelle CBZ..."

    (
        cd "$WORK" || exit 1
        zip -q -r "$OUTPUT" . -x '*/.DS_Store' '.DS_Store'
    )

    if [[ $? -ne 0 || ! -s "$OUTPUT" ]]; then
        echo "FEHLER: ZIP-Erstellung fehlgeschlagen."

        rm -f "$OUTPUT"

        (( FAILED++ ))
        continue
    fi

    echo "CBZ erfolgreich erstellt."

    # --------------------------------------
    # Finder-Tag setzen
    # --------------------------------------

    echo "Setze Finder-Tag..."

    if set_finder_tag "$file"; then
        echo "Finder-Tag '$FINDER_TAG' gesetzt."
        (( TAGGED++ ))
    else
        echo "WARNUNG: Finder-Tag konnte nicht gesetzt werden."
        
        # Original bleibt bei Tag-Fehler erhalten
        (( FAILED++ ))
        continue
    fi

    # --------------------------------------
    # Original optional löschen
    # --------------------------------------

    if [[ "$DELETE_ORIGINAL" == true ]]; then

        if rm "$file"; then
            echo "Original gelöscht."
            (( DELETED++ ))
        else
            echo "WARNUNG: Original konnte nicht gelöscht werden."
        fi

    else
        echo "Original bleibt erhalten."
    fi

    (( SUCCESS++ ))

done

# ------------------------------------------
# Zusammenfassung
# ------------------------------------------

echo ""
echo "=========================================="
echo "       KONVERTIERUNG ABGESCHLOSSEN"
echo "=========================================="
echo ""
echo "Gefunden:          $TOTAL"
echo "Erfolgreich:       $SUCCESS"
echo "Fehlgeschlagen:    $FAILED"
echo "Übersprungen:      $SKIPPED"
echo "Finder-Tags:       $TAGGED"
echo "Original gelöscht: $DELETED"
echo ""
echo "=========================================="
