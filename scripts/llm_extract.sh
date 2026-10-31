#!/usr/bin/env bash
#
# scripts/llm_extract.sh -- LLM-as-preprocessor for CrossEngin ingestion.
#
# Reads unstructured text (an article, a paper, a PDF converted to text),
# calls an external LLM to extract structured curriculum records, writes
# a .cerec file ready for `/ingest_llm PATH MODEL_ID RUN_ID` in the chat
# REPL. The LLM is NEVER in CrossEngin's answer path -- this script is
# an offline preprocessor that emits data-only records; the reasoning
# path stays 100% NOVA-symbolic (ADR-0013 / ADR-0014).
#
# LLM safety wall enforced downstream (src/ingest/llm_extractor.nova):
#   * source tag rewritten to src:extractor:llm:MODEL:RUN
#   * beliefs capped at 800 (no Tier-A user-taught equivalent minting)
#   * FORMAL implications downgraded to EMPIRICAL (no kernel axiom
#     minting via LLM)
#   * EVERY record enters review queue (never direct-to-KG) so an
#     operator approves individual records before atoms land.
#
# Usage:
#   scripts/llm_extract.sh \
#       --input path/to/text.txt \
#       --output path/to/output.cerec \
#       --kg     religion \
#       --model  llama3.1:8b \
#       --run    r-2026-08-15-01 \
#       [--backend ollama | llama-cpp | openai | dry-run]
#
# Backends
#   ollama       (default) uses `ollama run MODEL` locally. Requires
#                Ollama running at $OLLAMA_HOST (default 127.0.0.1:11434).
#   llama-cpp    uses `llama-cli -m MODEL_PATH -p PROMPT` (llama.cpp).
#                Set MODEL_PATH via --model /path/to/model.gguf.
#   openai       uses `curl` against an OpenAI-compatible endpoint at
#                $OPENAI_BASE_URL (default https://api.openai.com/v1)
#                with $OPENAI_API_KEY.
#   dry-run      skips the LLM entirely and echoes a minimal .cerec
#                stub. Useful for testing the pipeline end-to-end.
#
# Prompt template lives inline below (function _prompt). It instructs
# the LLM to emit .cerec directives ONLY, no prose. Tweak per model as
# needed; smaller local models may need a stricter one-shot example.
#
set -uo pipefail

INPUT=""
OUTPUT=""
KG=""
MODEL=""
RUN=""
BACKEND="ollama"

_usage() {
    sed -n '3,40p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --input)   INPUT="$2";   shift 2 ;;
        --output)  OUTPUT="$2";  shift 2 ;;
        --kg)      KG="$2";      shift 2 ;;
        --model)   MODEL="$2";   shift 2 ;;
        --run)     RUN="$2";     shift 2 ;;
        --backend) BACKEND="$2"; shift 2 ;;
        -h|--help) _usage ;;
        *) echo "unknown arg: $1" >&2; _usage ;;
    esac
done

if [ -z "$INPUT" ] || [ -z "$OUTPUT" ] || [ -z "$KG" ] || [ -z "$MODEL" ] || [ -z "$RUN" ]; then
    _usage
fi

if [ ! -f "$INPUT" ]; then
    echo "error: input file not found: $INPUT" >&2
    exit 1
fi

# ---- prompt template ------------------------------------------------------

_prompt() {
    cat <<EOF
You are an extraction preprocessor for CrossEngin, a symbolic reasoning
engine. Read the passage below and emit a .cerec file that captures ONLY
the concrete factual claims you can support directly from the text.

FORMAT RULES (STRICT -- output ONLY these directives, no prose, no code
fences, no explanation):

  KG      <kg_name>                    (exactly one, always: $KG)
  SRC     <src:tag>                    (always: src:extractor:llm:$MODEL:$RUN)
  ATOM    <label> <kind> <belief>      kind: 1=FACT, 3=CONCEPT
                                       belief: integer 0..800 milli.
                                       800 = confident fact stated
                                       plainly; 600 = probable claim;
                                       400 = uncertain / hedged.
  IMP     <ante> <conseq> <STRENGTH>   STRENGTH: always EMPIRICAL.
                                       Downstream will re-check.
  OBS     <label> <sign> <weight>      sign: +1 supports, -1 contradicts.
                                       weight: 0..1000.

LABEL RULES:
  * Lowercase, snake_case. ASCII letters + digits + underscore + hyphen.
  * Concise noun/phrase. NOT sentences. Good: "photosynthesis";
    "boiling_point_of_water"; "battle_of_hastings_1066".
    Bad: "the_process_by_which_plants_make_food".
  * Same real-world thing -> same label. Reuse existing labels; do NOT
    invent synonyms.

CONTENT RULES:
  * ONLY claims you can point at a specific sentence for. No inference
    beyond the text.
  * Skip opinions, interpretations, and rhetorical claims.
  * Skip claims about currently-living named individuals.
  * If uncertain about a claim, lower the belief -- do not omit it and
    do not upgrade it.
  * Prefer more small atoms over few large ones. Two atoms + one IMP
    beats one long-label atom.

FILE STRUCTURE:
  * Exactly one KG directive at the top.
  * Exactly one SRC directive next.
  * Then ATOM directives (dedup by label).
  * Then IMP directives referencing atoms declared above.
  * Then optional OBS directives.
  * Blank lines and # comments are OK -- they are ignored by the parser.
  * NO other output. No prose. No explanation. No code fences. Just the
    directives.

EXAMPLE (from a passage about the invention of the printing press):

  KG history
  SRC src:extractor:llm:$MODEL:$RUN
  ATOM johannes_gutenberg 1 800
  ATOM printing_press_1440 1 800
  ATOM person 3 800
  ATOM invention 3 800
  IMP johannes_gutenberg person EMPIRICAL
  IMP printing_press_1440 invention EMPIRICAL
  IMP johannes_gutenberg printing_press_1440 EMPIRICAL

--- PASSAGE START ---
$(cat "$INPUT")
--- PASSAGE END ---

Emit the .cerec file now. Directives only.
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
    # MODEL is the .gguf path in this backend.
    llama-cli -m "$MODEL" -p "$prompt" -n 4096 --temp 0.2 2>/dev/null
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
        '{model: $model, messages: [{role: "user", content: $content}], temperature: 0.2}')
    curl -sS "$base/chat/completions" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$body" \
        | jq -r '.choices[0].message.content'
}

_run_dry() {
    cat <<EOF
KG $KG
SRC src:extractor:llm:$MODEL:$RUN
# Dry-run stub -- replace with real LLM output.
ATOM sample_topic_atom 1 500
ATOM sample_related_concept 3 500
IMP sample_topic_atom sample_related_concept EMPIRICAL
EOF
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

# Belt-and-braces: strip any accidental ``` fences the model may emit.
SANITIZED=$(printf "%s\n" "$RAW" | sed -e '/^```/d')

printf "%s\n" "$SANITIZED" > "$OUTPUT"

# Report what we did.
n_atoms=$(grep -c '^ATOM ' "$OUTPUT" 2>/dev/null || echo 0)
n_imps=$(grep -c '^IMP '  "$OUTPUT" 2>/dev/null || echo 0)
n_obs=$(grep -c '^OBS '   "$OUTPUT" 2>/dev/null || echo 0)
echo "wrote $OUTPUT  ($n_atoms atoms, $n_imps implications, $n_obs observations)"
echo "ingest with:  /ingest_llm $OUTPUT $MODEL $RUN"
echo "then review:  /ingest_review"
echo "then approve: /ingest_approve <id>   (per record)"
