#!/usr/bin/env bash
# snap_diff -- structural diff of two CrossEngin snapshot files.
#
# Usage:    bash scripts/snap_diff.sh OLD.snap NEW.snap
#
# What it reports:
#   * Atoms added / removed by label (one line each, with kg label + kind).
#   * Beliefs changed (same kg+label present in both, alpha or beta delta).
#   * Sections added / removed (`*.present 1` keys that newly appear/vanish).
#   * Soul mood (valence + arousal) drift and per-OCEAN-trait drift.
#
# Output colour: ANSI on a tty, plain when piped (so `snap_diff a b | less`
# stays readable). Format authority is src/persistence/snapshot_disk.nova
# (one `key val` pair per line, ASCII, line-oriented).
#
# Exit codes:
#   0  diff printed (or files identical)
#   2  usage error (missing args, file unreadable)

set -uo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 OLD.snap NEW.snap" >&2
    exit 2
fi

OLD="$1"
NEW="$2"
for f in "$OLD" "$NEW"; do
    if [ ! -r "$f" ]; then
        echo "snap_diff: cannot read '$f'" >&2
        exit 2
    fi
done

# ---- colour helpers -----------------------------------------------------
if [ -t 1 ]; then
    C_GRN=$'\033[32m'; C_RED=$'\033[31m'; C_YEL=$'\033[33m'
    C_CYN=$'\033[36m'; C_DIM=$'\033[2m'; C_BLD=$'\033[1m'; C_RST=$'\033[0m'
else
    C_GRN=""; C_RED=""; C_YEL=""; C_CYN=""; C_DIM=""; C_BLD=""; C_RST=""
fi

# ---- atom extractor -----------------------------------------------------
# Emit one "<kg>\t<kind>\t<label>\t<alpha>\t<beta>" record per atom block in
# the snapshot. The format is a contiguous run of kgs.atoms[N].{kg,id,kind,
# label,alpha,beta} lines; we parse in awk by remembering the most recent
# value per field-name and flushing when the field set is complete.
extract_atoms() {
    awk '
    /^kgs\.atoms\[[0-9]+\]\.kg / {
        split($0, a, " ")
        # rejoin everything past the key as the value (labels can contain spaces)
        sub("^kgs\\.atoms\\[[0-9]+\\]\\.kg ", "")
        kg=$0
        next
    }
    /^kgs\.atoms\[[0-9]+\]\.kind / { kind=$2; next }
    /^kgs\.atoms\[[0-9]+\]\.label / { sub("^kgs\\.atoms\\[[0-9]+\\]\\.label ",""); label=$0; next }
    /^kgs\.atoms\[[0-9]+\]\.alpha / { alpha=$2; next }
    /^kgs\.atoms\[[0-9]+\]\.beta / {
        beta=$2
        # Key by "kg|label" because (kg, label) is the natural atom identity
        # across snapshots; ids drift when atoms are added in a different
        # order. The reader/writer preserves ids only WITHIN a single run.
        print kg "|" label "\t" kind "\t" alpha "\t" beta
        next
    }
    ' "$1"
}

# ---- sections present ---------------------------------------------------
extract_sections() {
    awk -F' ' '/\.present 1$/ { sub(/\.present.*/, ""); print $1 }' "$1" | sort -u
}

# ---- soul fields --------------------------------------------------------
extract_soul_field() {
    # extract_soul_field <file> <field-name>  -> prints value or empty
    grep -E "^${2} " "$1" | head -n 1 | sed -E "s/^${2} //"
}

printf "${C_BLD}=== snap_diff ===${C_RST}\n"
printf "${C_DIM}old:${C_RST} %s\n" "$OLD"
printf "${C_DIM}new:${C_RST} %s\n" "$NEW"
printf "\n"

# ---- sections diff ------------------------------------------------------
OLD_SEC="$(extract_sections "$OLD")"
NEW_SEC="$(extract_sections "$NEW")"
SEC_ADDED="$(comm -13 <(printf '%s\n' "$OLD_SEC") <(printf '%s\n' "$NEW_SEC"))"
SEC_REMOVED="$(comm -23 <(printf '%s\n' "$OLD_SEC") <(printf '%s\n' "$NEW_SEC"))"
printf '%s-- sections --%s\n' "$C_CYN" "$C_RST"
if [ -z "$SEC_ADDED" ] && [ -z "$SEC_REMOVED" ]; then
    printf "  (no change)\n"
else
    if [ -n "$SEC_ADDED" ]; then
        printf '%s\n' "$SEC_ADDED" | while IFS= read -r s; do
            [ -n "$s" ] && printf "  ${C_GRN}added:${C_RST}   %s\n" "$s"
        done
    fi
    if [ -n "$SEC_REMOVED" ]; then
        printf '%s\n' "$SEC_REMOVED" | while IFS= read -r s; do
            [ -n "$s" ] && printf "  ${C_RED}removed:${C_RST} %s\n" "$s"
        done
    fi
fi
printf "\n"

# ---- atoms diff ---------------------------------------------------------
TMPDIR_DIFF="$(mktemp -d -t snap_diff.XXXXXX)"
trap 'rm -rf "$TMPDIR_DIFF"' EXIT
extract_atoms "$OLD" | sort -t$'\t' -k1,1 > "$TMPDIR_DIFF/old_atoms.tsv"
extract_atoms "$NEW" | sort -t$'\t' -k1,1 > "$TMPDIR_DIFF/new_atoms.tsv"

# Just the keys (kg|label) for set-difference.
cut -f1 "$TMPDIR_DIFF/old_atoms.tsv" > "$TMPDIR_DIFF/old_keys"
cut -f1 "$TMPDIR_DIFF/new_atoms.tsv" > "$TMPDIR_DIFF/new_keys"
ATOMS_ADDED_KEYS="$(comm -13 "$TMPDIR_DIFF/old_keys" "$TMPDIR_DIFF/new_keys")"
ATOMS_REMOVED_KEYS="$(comm -23 "$TMPDIR_DIFF/old_keys" "$TMPDIR_DIFF/new_keys")"
ATOMS_COMMON_KEYS="$(comm -12 "$TMPDIR_DIFF/old_keys" "$TMPDIR_DIFF/new_keys")"

OLD_ATOM_COUNT="$(wc -l < "$TMPDIR_DIFF/old_atoms.tsv" | tr -d ' ')"
NEW_ATOM_COUNT="$(wc -l < "$TMPDIR_DIFF/new_atoms.tsv" | tr -d ' ')"
N_ADDED="$(printf '%s' "$ATOMS_ADDED_KEYS" | grep -c . || true)"
N_REMOVED="$(printf '%s' "$ATOMS_REMOVED_KEYS" | grep -c . || true)"

printf '%s-- atoms --%s\n' "$C_CYN" "$C_RST"
printf "  total: %s -> %s   (added %s, removed %s)\n" \
    "$OLD_ATOM_COUNT" "$NEW_ATOM_COUNT" "$N_ADDED" "$N_REMOVED"

# Cap the per-side list to keep large snapshot diffs readable. The full
# count is in the header above; this is just the inspectable preview.
LIST_CAP="${CE_SNAP_DIFF_LIST_CAP:-50}"

if [ "$N_ADDED" -gt 0 ]; then
    printf "%s\n" "$ATOMS_ADDED_KEYS" | head -n "$LIST_CAP" | while IFS= read -r k; do
        [ -n "$k" ] || continue
        # Look up the new record so we can print kg + label cleanly.
        kg="${k%%|*}"
        label="${k#*|}"
        printf "  ${C_GRN}added:${C_RST}   %s/%s\n" "$kg" "$label"
    done
    if [ "$N_ADDED" -gt "$LIST_CAP" ]; then
        printf "  ${C_DIM}(... %s more, set CE_SNAP_DIFF_LIST_CAP to lift)${C_RST}\n" \
            "$((N_ADDED - LIST_CAP))"
    fi
fi
if [ "$N_REMOVED" -gt 0 ]; then
    printf "%s\n" "$ATOMS_REMOVED_KEYS" | head -n "$LIST_CAP" | while IFS= read -r k; do
        [ -n "$k" ] || continue
        kg="${k%%|*}"
        label="${k#*|}"
        printf "  ${C_RED}removed:${C_RST} %s/%s\n" "$kg" "$label"
    done
    if [ "$N_REMOVED" -gt "$LIST_CAP" ]; then
        printf "  ${C_DIM}(... %s more)${C_RST}\n" "$((N_REMOVED - LIST_CAP))"
    fi
fi

# ---- beliefs changed (kg|label present in both, alpha or beta differ) ---
printf '\n%s-- beliefs --%s\n' "$C_CYN" "$C_RST"
BELIEF_CHANGED=0
if [ -n "$ATOMS_COMMON_KEYS" ]; then
    # Use join on the per-key TSVs to emit rows where alpha or beta moved.
    # Field layout from extract_atoms:
    #   $1 = "kg|label"  $2 = kind  $3 = alpha  $4 = beta
    join -t$'\t' -1 1 -2 1 \
        "$TMPDIR_DIFF/old_atoms.tsv" "$TMPDIR_DIFF/new_atoms.tsv" \
        > "$TMPDIR_DIFF/joined.tsv"
    # joined rows: key  old_kind  old_a  old_b  new_kind  new_a  new_b
    awk -F'\t' -v cap="${CE_SNAP_DIFF_LIST_CAP:-50}" -v g="$C_GRN" -v r="$C_RED" -v d="$C_DIM" -v rst="$C_RST" '
    {
        oa=$3; ob=$4; na=$6; nb=$7
        da = na - oa
        db = nb - ob
        if (da != 0 || db != 0) {
            count++
            if (count <= cap) {
                key=$1
                split(key, kp, "|")
                kg=kp[1]; lbl=kp[2]
                # Format the delta with sign for readability.
                fa = (da >= 0 ? "+" da : da)
                fb = (db >= 0 ? "+" db : db)
                printf "  %s/%s: alpha %d->%d (%s)  beta %d->%d (%s)\n", \
                    kg, lbl, oa, na, fa, ob, nb, fb
            }
        }
    }
    END {
        if (count == 0) print "  (no belief changes among atoms present in both)"
        else if (count > cap) printf "  %s(... %d more belief changes)%s\n", d, count - cap, rst
        # Stash the count so the shell summary can pick it up.
        printf "__BELIEF_CHANGED__=%d\n", count > "/dev/stderr"
    }
    ' "$TMPDIR_DIFF/joined.tsv" 2>"$TMPDIR_DIFF/belief_count.tmp"
    BELIEF_CHANGED="$(awk -F= '/__BELIEF_CHANGED__/{print $2}' "$TMPDIR_DIFF/belief_count.tmp" 2>/dev/null)"
    BELIEF_CHANGED="${BELIEF_CHANGED:-0}"
else
    printf "  (no atoms in common -- belief comparison skipped)\n"
fi

# ---- soul drift ---------------------------------------------------------
printf '\n%s-- soul --%s\n' "$C_CYN" "$C_RST"
diff_field() {
    # diff_field <human-label> <field-key>
    local lbl="$1" key="$2"
    local ov nv
    ov="$(extract_soul_field "$OLD" "$key")"
    nv="$(extract_soul_field "$NEW" "$key")"
    if [ -z "$ov" ] && [ -z "$nv" ]; then return; fi
    if [ "$ov" = "$nv" ]; then
        return
    fi
    if [ -z "$ov" ]; then ov="(absent)"; fi
    if [ -z "$nv" ]; then nv="(absent)"; fi
    # If both are numeric, also show the signed delta.
    if [[ "$ov" =~ ^-?[0-9]+$ ]] && [[ "$nv" =~ ^-?[0-9]+$ ]]; then
        local d=$((nv - ov)) sign=""
        if [ "$d" -ge 0 ]; then sign="+"; fi
        printf "  %s: %s -> %s (${C_YEL}%s%d${C_RST})\n" "$lbl" "$ov" "$nv" "$sign" "$d"
    else
        printf "  %s: %s -> %s\n" "$lbl" "$ov" "$nv"
    fi
    SOUL_DRIFT=$((SOUL_DRIFT + 1))
}
SOUL_DRIFT=0
diff_field "name           " "soul.name"
diff_field "mood.valence   " "soul.mood.valence"
diff_field "mood.arousal   " "soul.mood.arousal"
diff_field "ocean.openness " "soul.ocean.o"
diff_field "ocean.conscient" "soul.ocean.c"
diff_field "ocean.extravers" "soul.ocean.e"
diff_field "ocean.agreeable" "soul.ocean.a"
diff_field "ocean.neuroti  " "soul.ocean.n"
if [ "$SOUL_DRIFT" -eq 0 ]; then
    printf "  (no mood / OCEAN drift)\n"
fi

# ---- summary ------------------------------------------------------------
printf "\n${C_BLD}summary:${C_RST} atoms +%s -%s   beliefs ~%s   soul-drifted-fields %s\n" \
    "$N_ADDED" "$N_REMOVED" "$BELIEF_CHANGED" "$SOUL_DRIFT"
exit 0
