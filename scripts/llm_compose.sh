#!/usr/bin/env bash
#
# scripts/llm_compose.sh -- LLM-as-fluency-layer for CrossEngin replies
# (Phase 2 pt1).
#
# Reads a templated reply + optional atom-labels CSV from --input (or
# stdin via `--input -`), rewrites it in natural, conversational tone,
# and writes one line of fluent prose to --output (or stdout).
#
# The LLM is a STYLIST ONLY. CrossEngin's reasoning engine has already
# decided what to say; this script turns a dry template like
#   "infection leads to headache (infection->symptom->fever->headache)."
# into
#   "A fever usually points to an infection, and infections tend to
#    bring on headaches."
# -- same claim, nicer wording.
#
# Input format (line-oriented, read from stdin or the --input file):
#   TEMPLATE <single line of templated reply>
#   ATOMS    <optional comma-separated atom labels in reasoning order>
#
# Both lines are optional-but-recommended. Missing TEMPLATE => passthrough.
#
# Output format (one line, written to stdout or --output):
#   <fluent rewrite of TEMPLATE>
#
# Fail-closed: on any error (missing backend, non-zero exit, empty
# body, timeout) the script exits 0 after writing TEMPLATE verbatim.
# Callers get at-worst identical output to the pre-composer behaviour.
#
# Usage:
#   scripts/llm_compose.sh \
#       --input   /tmp/compose_in.txt \
#       --output  -                       \
#       --model   llama3.2:3b-instruct    \
#       [--backend ollama | llama-cpp | openai | dry-run]
#
# Backends mirror scripts/llm_extract.sh and scripts/nl_parse_llm.sh:
#   ollama       (default) uses `ollama run MODEL` locally.
#   llama-cpp    uses `llama-cli -m MODEL_PATH -p PROMPT`.
#   openai       uses `curl` against $OPENAI_BASE_URL with $OPENAI_API_KEY.
#   dry-run      skips the LLM entirely; echoes TEMPLATE as-is. Useful
#                when running the composer plumbing in CI without a
#                live model.

set -uo pipefail

INPUT=""
OUTPUT=""
MODEL="${OLLAMA_COMPOSER_MODEL:-llama3.2:3b-instruct}"
BACKEND="${OLLAMA_COMPOSER_BACKEND:-ollama}"

_usage() {
    sed -n '3,45p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --input)   INPUT="$2";   shift 2 ;;
        --output)  OUTPUT="$2";  shift 2 ;;
        --model)   MODEL="$2";   shift 2 ;;
        --backend) BACKEND="$2"; shift 2 ;;
        -h|--help) _usage ;;
        *) echo "unknown arg: $1" >&2; _usage ;;
    esac
done

if [ -z "$INPUT" ] || [ -z "$OUTPUT" ]; then
    _usage
fi

# ---- read + split the input ----------------------------------------------
if [ "$INPUT" = "-" ]; then
    RAW_IN="$(cat)"
else
    RAW_IN="$(cat "$INPUT" 2>/dev/null || echo "")"
fi

TEMPLATE=""
ATOMS=""
while IFS= read -r line; do
    case "$line" in
        TEMPLATE\ *) TEMPLATE="${line#TEMPLATE }" ;;
        ATOMS\ *)    ATOMS="${line#ATOMS }" ;;
    esac
done <<<"$RAW_IN"

# Passthrough helper. One-line writer that honours --output = -.
_emit() {
    if [ "$OUTPUT" = "-" ]; then
        printf '%s\n' "$1"
    else
        printf '%s\n' "$1" >"$OUTPUT"
    fi
}

# Missing TEMPLATE => nothing to compose, nothing to pass through.
if [ -z "$TEMPLATE" ]; then
    _emit ""
    exit 0
fi

# ---- strict prompt --------------------------------------------------------
_prompt() {
    cat <<EOF
You rewrite a single sentence in a natural, conversational tone.

Rules:
  - Preserve every noun phrase and the semantic claim EXACTLY.
  - Do NOT add facts not present in the input.
  - Do NOT add caveats, disclaimers, apologies, or questions.
  - Keep it to ONE short sentence (<= 25 words).
  - If the input is already natural, return it unchanged.

Relevant atoms (for context only; do not introduce new ones): $ATOMS

Templated reply: $TEMPLATE

Rewrite:
EOF
}

# ---- backends -------------------------------------------------------------
_run_ollama() {
    if ! command -v ollama >/dev/null 2>&1; then
        return 1
    fi
    local url="${OLLAMA_URL:-http://127.0.0.1:11434}"
    OLLAMA_HOST="$url" ollama run "$MODEL" <<<"$(_prompt)" 2>/dev/null
}

_run_llama_cpp() {
    if ! command -v llama-cli >/dev/null 2>&1; then
        return 1
    fi
    llama-cli -m "$MODEL" -p "$(_prompt)" -n 128 --temp 0.2 2>/dev/null
}

_run_openai() {
    if [ -z "${OPENAI_API_KEY:-}" ]; then
        return 1
    fi
    if ! command -v curl >/dev/null 2>&1; then
        return 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        return 1
    fi
    local base="${OPENAI_BASE_URL:-https://api.openai.com/v1}"
    local body
    body=$(jq -n --arg model "$MODEL" --arg content "$(_prompt)" \
        '{model: $model, messages: [{role: "user", content: $content}], temperature: 0.2}')
    curl -sS "$base/chat/completions" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$body" 2>/dev/null \
        | jq -r '.choices[0].message.content' 2>/dev/null
}

_run_dry() {
    printf '%s' "$TEMPLATE"
}

# ---- dispatch -------------------------------------------------------------
RAW=""
case "$BACKEND" in
    ollama)    RAW="$(_run_ollama)"    ;;
    llama-cpp) RAW="$(_run_llama_cpp)" ;;
    openai)    RAW="$(_run_openai)"    ;;
    dry-run)   RAW="$(_run_dry)"       ;;
    *)         RAW="" ;;
esac

# ---- sanitize + fall-through ---------------------------------------------
# Trim whitespace. Collapse multi-line output to its first non-empty line
# (the LLM may add an explanation we don't want).
CLEAN="$(printf '%s' "$RAW" | sed -n '/./{p;q}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

# If the LLM returned nothing, or something that looks like a refusal
# ("I cannot...", "Sorry..."), fall through to the template.
if [ -z "$CLEAN" ]; then
    _emit "$TEMPLATE"
    exit 0
fi

case "$CLEAN" in
    "I cannot "*|"I can't "*|"Sorry"*|"sorry"*|"As an AI"*)
        _emit "$TEMPLATE"
        exit 0
        ;;
esac

# Length cap: if the LLM went long, prefer the template.
MAX_LEN=$(( ${#TEMPLATE} * 2 + 256 ))
if [ ${#CLEAN} -gt $MAX_LEN ]; then
    _emit "$TEMPLATE"
    exit 0
fi

_emit "$CLEAN"
exit 0
