#!/usr/bin/env bash
#
# scripts/nl_parse_llm.sh -- LLM-as-preprocessor for CrossEngin NL surface
# (R48p6, ADR-0104).
#
# Reads one natural-language sentence, calls an external LLM to convert it
# into the CrossEngin StructuredQuery wire format, writes the wire text to
# --output (or stdout with -). The LLM is a PREPROCESSOR ONLY -- the wire
# text is parsed by src/nl/llm_parser.nova into a StructuredQuery, which
# nl_execute then dispatches to the skill runtime. The reasoning path
# stays 100% NOVA-symbolic (ADR-0013 / ADR-0014). The LLM cannot write
# the response the user sees -- src/nl/templater.nova does that from the
# ProposalResult the skill produces.
#
# Wire format (line-oriented, whitespace-tolerant):
#   KIND <name>          -- one of: research | research_filtered | relate |
#                                    contradict_scan | is_a | retract |
#                                    capsule_install | skill_install |
#                                    capsule_list | skill_list |
#                                    skill_run | unparsed
#   ARG  <string>        -- 0..N args in the order the kind expects. E.g.
#                           research needs 1 arg (topic); relate needs 2;
#                           skill_run needs 2 (skill_name, arg).
#   # ...                -- comment, ignored
#   (blank)              -- ignored
#
# Example wire outputs:
#   KIND research
#   ARG mars
#
#   KIND relate
#   ARG mitochondria
#   ARG cell
#
#   KIND unparsed              (LLM refused / could not fit any kind)
#
# LLM safety wall (ADR-0104 §Component 2 / ADR-0013):
#   * Wire output is data, not prose -- the parser rejects anything else
#   * Wire output validated against StructuredQuery schema in NOVA;
#     malformed -> refused, not answered
#   * Any observation the resulting query later creates carries source
#     tag `src:parser:llm:MODEL:RUN`, distinct from grammar-parsed
#     queries so audit can slice by parser
#
# Usage:
#   scripts/nl_parse_llm.sh \
#       --input "does the sun relate to gravity" \
#       --output /tmp/query.wire \
#       --model  llama3.1:8b \
#       --run    q-2026-08-15-01 \
#       [--backend ollama | llama-cpp | openai | dry-run]
#
#   Pass --output - to write to stdout instead of a file.
#
# Backends (mirrors scripts/llm_extract.sh):
#   ollama       (default) uses `ollama run MODEL` locally.
#   llama-cpp    uses `llama-cli -m MODEL_PATH -p PROMPT`.
#   openai       uses `curl` against $OPENAI_BASE_URL with $OPENAI_API_KEY.
#   dry-run      skips the LLM entirely; emits KIND unparsed by default
#                or the kind requested via CE_NL_LLM_DRY_KIND for testing.

set -uo pipefail

INPUT=""
OUTPUT=""
MODEL=""
RUN=""
BACKEND="ollama"

_usage() {
    sed -n '3,55p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --input)   INPUT="$2";   shift 2 ;;
        --output)  OUTPUT="$2";  shift 2 ;;
        --model)   MODEL="$2";   shift 2 ;;
        --run)     RUN="$2";     shift 2 ;;
        --backend) BACKEND="$2"; shift 2 ;;
        -h|--help) _usage ;;
        *) echo "unknown arg: $1" >&2; _usage ;;
    esac
done

if [ -z "$INPUT" ] || [ -z "$OUTPUT" ] || [ -z "$MODEL" ] || [ -z "$RUN" ]; then
    _usage
fi

# ---- prompt template ------------------------------------------------------
#
# Kept SHORT + STRICT: the LLM's job is a one-shot classification. Any
# prose, apology, or answer content is a schema violation and the NOVA
# parser rejects it. The wire vocabulary is fixed; the LLM chooses ONE
# KIND and the right number of ARGs.
_prompt() {
    cat <<EOF
You convert a single natural-language question into a CrossEngin
StructuredQuery wire record. Emit ONLY the wire record. NO prose.
NO apology. NO answer to the question -- CrossEngin's own reasoning
engine will answer it; your job is to classify the question.

Wire vocabulary (case-sensitive line-oriented):
  KIND <name>    one of:
    research            (single topic: "what is X", "tell me about X")
    research_filtered   (topic + filter kind: who/when/where)
    relate              (does X relate to Y)
    contradict_scan     (does X contradict Y)
    is_a                (is X a Y)
    retract             (retract LABEL)
    capsule_install     (install capsule NAME)
    skill_install       (install skill NAME)
    capsule_list        (list capsules)
    skill_list          (list skills)
    skill_run           (run skill NAME on ARG)
    unparsed            (question does not fit any kind)
  ARG <string>   0..N args in the order the kind expects. Arity:
    research: 1 (topic)
    research_filtered: 2 (topic, filter_kind)     filter_kind in {person,event,place}
    relate / contradict_scan / is_a: 2 (a, b)
    retract / capsule_install / skill_install: 1
    capsule_list / skill_list / unparsed: 0
    skill_run: 2 (skill_name, arg)
  # ...           comment, ignored

Rules:
  - Emit ONE KIND line, then zero or more ARG lines matching its arity.
  - If the question does not fit any kind, emit exactly:
      KIND unparsed
  - Do NOT emit code fences, markdown, JSON, or explanation.
  - Do NOT answer the question. Do NOT add commentary.

Examples:

Question: what is photosynthesis
KIND research
ARG photosynthesis

Question: does mitochondria relate to cell
KIND relate
ARG mitochondria
ARG cell

Question: who is einstein
KIND research_filtered
ARG einstein
ARG person

Question: list capsules
KIND capsule_list

Question: something we cannot classify at all
KIND unparsed

Question: $INPUT
EOF
}

# ---- backends -------------------------------------------------------------

_run_ollama() {
    local prompt
    prompt="$(_prompt)"
    if ! command -v ollama >/dev/null 2>&1; then
        echo "error: ollama not on PATH -- install from https://ollama.com" >&2
        return 1
    fi
    ollama run "$MODEL" <<<"$prompt"
}

_run_llama_cpp() {
    local prompt
    prompt="$(_prompt)"
    if ! command -v llama-cli >/dev/null 2>&1; then
        echo "error: llama-cli (llama.cpp) not on PATH" >&2
        return 1
    fi
    llama-cli -m "$MODEL" -p "$prompt" -n 512 --temp 0 2>/dev/null
}

_run_openai() {
    local prompt
    prompt="$(_prompt)"
    if [ -z "${OPENAI_API_KEY:-}" ]; then
        echo "error: OPENAI_API_KEY not set" >&2
        return 1
    fi
    local base="${OPENAI_BASE_URL:-https://api.openai.com/v1}"
    local body
    body=$(jq -n --arg model "$MODEL" --arg content "$prompt" \
        '{model: $model, messages: [{role: "user", content: $content}], temperature: 0}')
    curl -sS "$base/chat/completions" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$body" \
        | jq -r '.choices[0].message.content'
}

# Dry-run: no LLM. Emits a fixed record so integration tests / operators
# can exercise the pipeline end-to-end without a live model. Override
# with CE_NL_LLM_DRY_KIND=<kind> and CE_NL_LLM_DRY_ARGS=<comma,list> to
# simulate a specific classification.
_run_dry() {
    local k="${CE_NL_LLM_DRY_KIND:-unparsed}"
    printf "KIND %s\n" "$k"
    if [ -n "${CE_NL_LLM_DRY_ARGS:-}" ]; then
        local IFS=,
        for a in $CE_NL_LLM_DRY_ARGS; do
            printf "ARG %s\n" "$a"
        done
    fi
}

# ---- dispatch + sanitize + write ------------------------------------------

RAW=""
case "$BACKEND" in
    ollama)    RAW="$(_run_ollama)"   ;;
    llama-cpp) RAW="$(_run_llama_cpp)" ;;
    openai)    RAW="$(_run_openai)"   ;;
    dry-run)   RAW="$(_run_dry)"      ;;
    *) echo "unknown backend: $BACKEND" >&2; exit 2 ;;
esac

if [ -z "$RAW" ]; then
    echo "error: LLM returned empty output" >&2
    exit 1
fi

# Strip any code fences the model may emit; keep only lines that look
# like wire records (start with KIND / ARG / #) plus blank lines. This
# is belt-and-braces; NOVA-side llm_parse_wire is the authoritative
# validator.
SANITIZED=$(printf "%s\n" "$RAW" \
    | sed -e '/^```/d' \
    | grep -E '^[[:space:]]*(KIND|ARG|#|$)' \
    || true)

# Emit an audit header the NOVA parser skips (# ... comments) so operator
# can tell which LLM / run produced which wire record. Order matters: the
# NOVA parser reads sequentially, ignoring comments, and stops after the
# first KIND + its ARG lines.
_emit() {
    printf "# nl_parse_llm.sh: model=%s run=%s backend=%s\n" "$MODEL" "$RUN" "$BACKEND"
    printf "# input: %s\n" "$INPUT"
    printf "%s\n" "$SANITIZED"
}

if [ "$OUTPUT" = "-" ]; then
    _emit
else
    tmp="$OUTPUT.tmp"
    _emit > "$tmp"
    mv -- "$tmp" "$OUTPUT"
    kind_line=$(grep -m1 '^KIND ' -- "$OUTPUT" 2>/dev/null || echo "KIND (none)")
    n_args=$(grep -c '^ARG '  -- "$OUTPUT" 2>/dev/null || echo 0)
    echo "wrote $OUTPUT  ($kind_line, $n_args arg(s))"
fi
