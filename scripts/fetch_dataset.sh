#!/usr/bin/env bash
#
# fetch_dataset.sh — rigenera Sources/GymCore/Resources/exercises.json
# dal dataset upstream.
#
# Fonte: https://github.com/hasaneyldrm/exercises-dataset
#   - dati: licenza MIT © Hasan Emir Yıldırım
#   - media (image / gif_url): © Gym visual — https://gymvisual.com/
#     I media NON vengono mai scaricati né committati: il JSON contiene solo i
#     percorsi, le immagini si caricano a runtime (docs/SPEC.md §1.7, §2).
#
# Il file committato è una versione RIDOTTA dell'upstream: via `instructions` e
# `created_at`/`media_id`, e di `instruction_steps` si tengono solo `it` e `en`.
#
# ATTENZIONE: il file attualmente in repo è già stato generato con questo esatto
# filtro. Esegui lo script solo per aggiornare il dataset a monte.
#
# Uso:
#   ./scripts/fetch_dataset.sh
#
# Variabili d'ambiente:
#   EXPECTED_COUNT=1324     numero di record atteso (sanity check)
#   ALLOW_COUNT_CHANGE=1    accetta un conteggio diverso da EXPECTED_COUNT
#   DATASET_URL=...         sorgente alternativa (es. un mirror locale)
#

set -euo pipefail

readonly DATASET_URL="${DATASET_URL:-https://raw.githubusercontent.com/hasaneyldrm/exercises-dataset/main/data/exercises.json}"
readonly EXPECTED_COUNT="${EXPECTED_COUNT:-1324}"
readonly MIN_COUNT=1000

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly OUT="$REPO_ROOT/Sources/GymCore/Resources/exercises.json"

die() {
    printf 'fetch_dataset: errore: %s\n' "$*" >&2
    exit 1
}

info() {
    printf 'fetch_dataset: %s\n' "$*"
}

# --- Prerequisiti -----------------------------------------------------------

for tool in curl jq; do
    command -v "$tool" >/dev/null 2>&1 || die "'$tool' non trovato nel PATH (su macOS: /usr/bin/$tool)"
done

[ -d "$(dirname "$OUT")" ] || die "cartella di destinazione mancante: $(dirname "$OUT")"

# --- Area di lavoro temporanea ---------------------------------------------

TMPDIR_WORK="$(mktemp -d "${TMPDIR:-/tmp}/gymapp-dataset.XXXXXX")"
cleanup() { rm -rf "$TMPDIR_WORK"; }
trap cleanup EXIT

readonly RAW="$TMPDIR_WORK/upstream.json"
readonly REDUCED="$TMPDIR_WORK/reduced.json"

# --- Download ---------------------------------------------------------------

info "scarico $DATASET_URL"
curl --fail --location --silent --show-error \
     --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 300 \
     --output "$RAW" \
     "$DATASET_URL" \
    || die "download fallito"

[ -s "$RAW" ] || die "il file scaricato è vuoto"

jq empty "$RAW" 2>/dev/null || die "il file scaricato non è JSON valido"
[ "$(jq -r 'type' "$RAW")" = "array" ] || die "il JSON upstream non è un array"

raw_count="$(jq 'length' "$RAW")"
info "record upstream: $raw_count"

# --- Riduzione (filtro concordato: non modificarlo senza rigenerare tutto) ---

jq -c '[.[] | {id,name:(.name|gsub("в°";"°")),category,body_part,equipment,target,muscle_group,secondary_muscles,instruction_steps:{it:.instruction_steps.it,en:.instruction_steps.en},image,gif_url,attribution}]' \
    "$RAW" > "$REDUCED" \
    || die "il filtro jq è fallito"

# --- Validazione ------------------------------------------------------------

jq empty "$REDUCED" 2>/dev/null || die "il JSON ridotto non è valido"

count="$(jq 'length' "$REDUCED")"

[ "$count" = "$raw_count" ] || die "il filtro ha perso record: $raw_count → $count"
[ "$count" -ge "$MIN_COUNT" ] || die "solo $count record (minimo atteso: $MIN_COUNT): dataset sospetto, non sovrascrivo"

if [ "$count" != "$EXPECTED_COUNT" ]; then
    if [ "${ALLOW_COUNT_CHANGE:-0}" = "1" ]; then
        info "attenzione: $count record invece di $EXPECTED_COUNT (accettato via ALLOW_COUNT_CHANGE=1)"
    else
        die "$count record invece di $EXPECTED_COUNT attesi.
       Se l'upstream è cambiato davvero, riesegui con:
         ALLOW_COUNT_CHANGE=1 EXPECTED_COUNT=$count ./scripts/fetch_dataset.sh
       e aggiorna docs/SPEC.md §2."
    fi
fi

# Ogni record deve avere almeno id e name non vuoti: se il formato upstream
# cambia, il filtro produrrebbe silenziosamente un array di oggetti a null.
broken="$(jq '[.[] | select((.id // "") == "" or (.name // "") == "")] | length' "$REDUCED")"
[ "$broken" = "0" ] || die "$broken record senza id o name: formato upstream cambiato?"

with_it="$(jq '[.[] | select((.instruction_steps.it // []) | length > 0)] | length' "$REDUCED")"
info "record con istruzioni in italiano: $with_it / $count"

# --- Scrittura atomica ------------------------------------------------------

readonly STAGED="$OUT.tmp.$$"
cp "$REDUCED" "$STAGED"
mv -f "$STAGED" "$OUT"

info "scritto $OUT ($count record, $(du -h "$OUT" | cut -f1))"
info "ricorda: i media restano su gymvisual.com, non vanno committati."
