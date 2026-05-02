#!/usr/bin/env bash
# =============================================================================
# Dual-Skill Incremental Build-Up Loop (v2)
# =============================================================================
#
# Produces two skills from a shared baseline:
#   1. security-audit   — for agents doing explicit code reviews
#   2. secure-authoring — for general coding agents in security-sensitive contexts
#
# Usage:
#   bash run-loop.sh                    # Full run (baseline + both tracks)
#   bash run-loop.sh --baseline-only    # Baseline only, stop for review
#   bash run-loop.sh --skip-baseline    # Skip baseline, iterate only
#   bash run-loop.sh --track audit      # Only the audit track
#   bash run-loop.sh --track authoring  # Only the authoring track
#
# =============================================================================

set -euo pipefail

CONFIG_FILE="config.json"
EVALS_FILE="evals/eval-cases.json"
RUBRIC_FILE="evals/rubric.md"
JUDGE_PROMPT="scripts/judge-prompt.md"
REFERENCE_DIR="reference"
WORKSPACE="workspace"

CLAUDE_FLAGS="--dangerously-skip-permissions"

# ---- Parse arguments ----
SKIP_BASELINE=false
BASELINE_ONLY=false
TRACK_FILTER="both"  # "both", "audit", or "authoring"

for arg in "$@"; do
    case "$arg" in
        --skip-baseline) SKIP_BASELINE=true ;;
        --baseline-only) BASELINE_ONLY=true ;;
        --track)         ;; # handled below
        audit)           TRACK_FILTER="audit" ;;
        authoring)       TRACK_FILTER="authoring" ;;
    esac
done

# ---- Read config ----
MAX_ITERATIONS=$(python3 -c "import json; print(json.load(open('${CONFIG_FILE}')).get('max_iterations', 5))")
TARGET_SCORE=$(python3 -c "import json; print(json.load(open('${CONFIG_FILE}')).get('target_score', 2.7))")
SKILL_NAME=$(python3 -c "import json; print(json.load(open('${EVALS_FILE}')).get('skill_name', 'unknown'))")
TOPIC_GROUP=$(python3 -c "import json; print(json.load(open('${EVALS_FILE}')).get('topic_group', 'unknown'))")
NUM_EVALS=$(python3 -c "import json; print(len(json.load(open('${EVALS_FILE}'))['evals']))")

# ---- Resolve and copy origin skill into reference/ ----
ORIGIN_SKILL=$(python3 -c "
import json, os
config = json.load(open('${CONFIG_FILE}'))
source = config.get('origin_skill', '')
print(os.path.expanduser(source) if source else '')
")

if [ -n "${ORIGIN_SKILL}" ]; then
    if [ ! -d "${ORIGIN_SKILL}" ]; then
        echo "Error: origin_skill directory not found: ${ORIGIN_SKILL}"
        echo "Update the 'origin_skill' path in ${CONFIG_FILE} to point at your skill."
        exit 1
    fi

    echo "Copying origin skill into ${REFERENCE_DIR}/..."
    rm -rf "${REFERENCE_DIR}"
    mkdir -p "${REFERENCE_DIR}"

    # Copy SKILL.md as the main reference
    if [ -f "${ORIGIN_SKILL}/SKILL.md" ]; then
        cp "${ORIGIN_SKILL}/SKILL.md" "${REFERENCE_DIR}/origin-SKILL.md"
        echo "  ✓ origin-SKILL.md"
    fi

    # Copy all reference files (flatten into reference/)
    if [ -d "${ORIGIN_SKILL}/references" ]; then
        for ref_file in "${ORIGIN_SKILL}"/references/*.md; do
            if [ -f "${ref_file}" ]; then
                cp "${ref_file}" "${REFERENCE_DIR}/$(basename "${ref_file}")"
                echo "  ✓ $(basename "${ref_file}")"
            fi
        done
    fi

    echo ""
else
    # No origin_skill configured — reference/ must already be populated
    if [ ! -d "${REFERENCE_DIR}" ] || [ -z "$(ls -A "${REFERENCE_DIR}" 2>/dev/null)" ]; then
        echo "Warning: No origin_skill configured and ${REFERENCE_DIR}/ is empty."
        echo "The skill-building step will have no reference material to draw from."
        echo ""
    fi
fi

# Count evals by type
NUM_AUDIT=$(python3 -c "
import json
data = json.load(open('${EVALS_FILE}'))
print(len([e for e in data['evals'] if e['type'] == 'detect-and-fix']))
")
NUM_AUTHOR=$(python3 -c "
import json
data = json.load(open('${EVALS_FILE}'))
print(len([e for e in data['evals'] if e['type'] == 'secure-author']))
")

echo "=============================================="
echo "  ${SKILL_NAME} — Dual-Skill Build-Up"
echo "  Topic group: ${TOPIC_GROUP}"
echo "=============================================="
echo "  Origin skill:    ${ORIGIN_SKILL:-none (using existing reference/)}"
echo "  Audit evals:     ${NUM_AUDIT}"
echo "  Authoring evals: ${NUM_AUTHOR}"
echo "  Max iterations:  ${MAX_ITERATIONS}"
echo "  Target score:    ${TARGET_SCORE}"
echo "  Track filter:    ${TRACK_FILTER}"
echo "=============================================="
echo ""

# ---- Helpers ----

score_meets_target() {
    python3 -c "import sys; sys.exit(0 if float('$1') >= float('$2') else 1)"
}

get_evals_by_type() {
    python3 -c "
import json
data = json.load(open('${EVALS_FILE}'))
indices = [i for i, e in enumerate(data['evals']) if e['type'] == '$1']
print(' '.join(str(i) for i in indices))
"
}

run_single_eval() {
    local EVAL_IDX="$1"
    local PHASE_DIR="$2"
    local SKILL_PATH="$3"  # empty string = no skill

    local EVAL_ID=$((EVAL_IDX + 1))
    local EVAL_NAME=$(python3 -c "import json; print(json.load(open('${EVALS_FILE}'))['evals'][${EVAL_IDX}]['name'])")
    local EVAL_TYPE=$(python3 -c "import json; print(json.load(open('${EVALS_FILE}'))['evals'][${EVAL_IDX}]['type'])")
    local EVAL_DIR="${PHASE_DIR}/eval-${EVAL_ID}"

    echo "    [${EVAL_ID}] ${EVAL_NAME} (${EVAL_TYPE})..."

    # Materialise input files for this eval
    python3 -c "
import json, os
data = json.load(open('${EVALS_FILE}'))
ec = data['evals'][${EVAL_IDX}]
input_dir = '${EVAL_DIR}/input'
output_dir = '${EVAL_DIR}/output'
os.makedirs(input_dir, exist_ok=True)
os.makedirs(output_dir, exist_ok=True)
for fname, content in ec['input_files'].items():
    with open(os.path.join(input_dir, fname), 'w') as f:
        f.write(content)
with open('${EVAL_DIR}/task.md', 'w') as f:
    f.write(ec['task'])
" 2>/dev/null

    local TASK=$(cat "${EVAL_DIR}/task.md")
    local INPUT_FILES=$(ls "${EVAL_DIR}/input/")
    local SKILL_INSTRUCTION=""

    if [ -n "${SKILL_PATH}" ] && [ -f "${SKILL_PATH}" ] && [ -s "${SKILL_PATH}" ]; then
        SKILL_INSTRUCTION="First, read the skill at ${SKILL_PATH} and follow its guidance.
"
    fi

    claude -p "${SKILL_INSTRUCTION}
Read the input files in ${EVAL_DIR}/input/ and complete this task. Write your
output files to ${EVAL_DIR}/output/.

${TASK}

Input files available: ${INPUT_FILES}

Copy the input files to the output directory first, then apply your changes
there. Do not modify the files in input/." \
        ${CLAUDE_FLAGS} \
        --append-system-prompt "Complete the task. Write all output files to the output/ directory." \
        --max-turns 10 \
        > /dev/null 2>&1 || {
        echo "      ⚠ Failed"
    }

    local OUTPUT_COUNT=$(ls "${EVAL_DIR}/output/" 2>/dev/null | wc -l)
    if [ "${OUTPUT_COUNT}" -gt 0 ]; then
        echo "      ✓ ${OUTPUT_COUNT} output file(s)"
    else
        echo "      ⚠ No output"
    fi
}

score_single_eval() {
    local EVAL_IDX="$1"
    local PHASE_DIR="$2"

    local EVAL_ID=$((EVAL_IDX + 1))
    local EVAL_DIR="${PHASE_DIR}/eval-${EVAL_ID}"
    local SCORES_FILE="${PHASE_DIR}/scores-${EVAL_IDX}.json"

    # Write the eval case (without input_files) to a temp file to avoid
    # bash interpolation issues with special characters in JSON
    local EVAL_CASE_FILE="${PHASE_DIR}/.eval-case-${EVAL_IDX}.json"
    python3 -c "
import json
data = json.load(open('${EVALS_FILE}'))
ec = dict(data['evals'][${EVAL_IDX}])
del ec['input_files']
with open('${EVAL_CASE_FILE}', 'w') as f:
    json.dump(ec, f, indent=2)
"

    local OUTPUT_LISTING=""
    for f in "${EVAL_DIR}"/output/*; do
        [ -f "$f" ] && OUTPUT_LISTING="${OUTPUT_LISTING}  - ${f}
"
    done

    local INPUT_LISTING=""
    for f in "${EVAL_DIR}"/input/*; do
        [ -f "$f" ] && INPUT_LISTING="${INPUT_LISTING}  - ${f}
"
    done

    # Write the judge prompt to a temp file too, to keep the claude -p
    # argument simple and avoid interpolation problems
    local JUDGE_TASK_FILE="${PHASE_DIR}/.judge-task-${EVAL_IDX}.md"
    cat > "${JUDGE_TASK_FILE}" << JUDGE_EOF
You are judging an AI coding agent's output for a security eval.

Read the judge instructions at ${JUDGE_PROMPT}.
Read the scoring rubric at ${RUBRIC_FILE}.
Read the eval case definition at ${EVAL_CASE_FILE}.

## Original Input Files (read these for comparison)
${INPUT_LISTING}

## Agent Output Files (evaluate these)
${OUTPUT_LISTING}

Read ALL listed files. Compare the agent's output to the original input
and the eval case expectations. Score the output following the rubric.

Write your scores as a JSON object to ${SCORES_FILE}.
JUDGE_EOF

    claude -p "Read ${JUDGE_TASK_FILE} and follow its instructions exactly." \
        ${CLAUDE_FLAGS} \
        --append-system-prompt "Read all referenced files. Score the output. Write only the JSON scores file." \
        --max-turns 8 \
        > /dev/null 2>&1 || {
        echo "      ⚠ Scoring failed for eval ${EVAL_ID}"
        echo '{"eval_id": '${EVAL_ID}', "composite_score": 0, "scores": {}, "expectations_met": [], "expectations_missed": ["scoring failed"]}' > "${SCORES_FILE}"
    }

    if [ ! -f "${SCORES_FILE}" ]; then
        echo "      ⚠ No scores file produced for eval ${EVAL_ID}"
        echo '{"eval_id": '${EVAL_ID}', "composite_score": 0, "scores": {}, "expectations_met": [], "expectations_missed": ["no scores file"]}' > "${SCORES_FILE}"
    fi

    # Clean up temp files
    rm -f "${EVAL_CASE_FILE}" "${JUDGE_TASK_FILE}"
}

run_and_score_evals() {
    local PHASE_DIR="$1"
    local SKILL_PATH="$2"
    local EVAL_TYPE="$3"  # "detect-and-fix" or "secure-author" or "all"

    local EVAL_INDICES
    if [ "${EVAL_TYPE}" == "all" ]; then
        EVAL_INDICES=$(seq 0 $((NUM_EVALS - 1)))
    else
        EVAL_INDICES=$(get_evals_by_type "${EVAL_TYPE}")
    fi

    echo "  Running evals..."
    for idx in ${EVAL_INDICES}; do
        run_single_eval "${idx}" "${PHASE_DIR}" "${SKILL_PATH}"
    done

    echo ""
    echo "  Scoring..."
    for idx in ${EVAL_INDICES}; do
        score_single_eval "${idx}" "${PHASE_DIR}"
        echo "    ✓ Scored eval $((idx + 1))"
    done
}

aggregate_by_type() {
    local PHASE_DIR="$1"
    local EVAL_TYPE="$2"
    local OUTPUT_FILE="$3"

    python3 -c "
import json, os, glob

evals = json.load(open('${EVALS_FILE}'))['evals']
type_indices = [i for i, e in enumerate(evals) if e['type'] == '${EVAL_TYPE}']

scores = []
for idx in type_indices:
    path = os.path.join('${PHASE_DIR}', f'scores-{idx}.json')
    if os.path.exists(path):
        try:
            scores.append(json.load(open(path)))
        except:
            pass

if not scores:
    json.dump({'overall_composite': 0, 'by_eval': [], 'by_dimension': {}}, open('${OUTPUT_FILE}', 'w'), indent=2)
    exit()

# Aggregate by dimension
dim_scores = {}
for s in scores:
    for dim, data in s.get('scores', {}).items():
        score = data.get('score', data) if isinstance(data, dict) else data
        if score is not None:
            dim_scores.setdefault(dim, []).append(float(score))

dim_avgs = {d: round(sum(v)/len(v), 2) for d, v in dim_scores.items()}

# Overall composite
all_scores = [s for vals in dim_scores.values() for s in vals]
overall = round(sum(all_scores) / len(all_scores), 2) if all_scores else 0

# Per-eval composites
by_eval = []
for s in scores:
    eval_scores = []
    for dim, data in s.get('scores', {}).items():
        score = data.get('score', data) if isinstance(data, dict) else data
        if score is not None:
            eval_scores.append(float(score))
    by_eval.append({
        'eval_id': s.get('eval_id', '?'),
        'eval_name': s.get('eval_name', '?'),
        'composite': round(sum(eval_scores)/len(eval_scores), 2) if eval_scores else 0,
        'expectations_met': s.get('expectations_met', []),
        'expectations_missed': s.get('expectations_missed', []),
    })

result = {
    'eval_type': '${EVAL_TYPE}',
    'overall_composite': overall,
    'by_dimension': dim_avgs,
    'by_eval': by_eval,
}
json.dump(result, open('${OUTPUT_FILE}', 'w'), indent=2)
print(f'  Composite ({\"${EVAL_TYPE}\"}): {overall}')
"
}

# ===========================================================================
# PHASE 1: BASELINE
# ===========================================================================
BASELINE_DIR="${WORKSPACE}/baseline"

if [ "${SKIP_BASELINE}" == "false" ]; then
    if [ -f "${BASELINE_DIR}/summary-audit.json" ] && [ -f "${BASELINE_DIR}/summary-authoring.json" ]; then
        echo "Baseline exists. Skipping."
        echo ""
    else
        mkdir -p "${BASELINE_DIR}"

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  PHASE 1: BASELINE (no skill)"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""

        run_and_score_evals "${BASELINE_DIR}" "" "all"

        echo ""
        echo "  Aggregating by track..."
        aggregate_by_type "${BASELINE_DIR}" "detect-and-fix" "${BASELINE_DIR}/summary-audit.json"
        aggregate_by_type "${BASELINE_DIR}" "secure-author" "${BASELINE_DIR}/summary-authoring.json"

        # Also do a combined aggregate for the overall score
        python3 scripts/aggregate.py "${BASELINE_DIR}" 2>/dev/null || true

        # Generate split analyses
        echo ""
        echo "  Generating audit baseline analysis..."
        claude -p "Read ${BASELINE_DIR}/summary-audit.json and the individual score files.
Read the eval case definitions at ${EVALS_FILE} — focus on the detect-and-fix type evals.

Produce a concise analysis at ${BASELINE_DIR}/analysis-audit.md covering:

1. **Strong areas (2.5+):** What the model already does well when auditing code.
   The audit skill should NOT add content for these.
2. **Weak areas (below 2.0):** Where the model needs help. Focus here.
3. **Consistently missed expectations:** Specific patterns the model fails to
   detect or fix correctly.
4. **False positives:** Safe patterns the model incorrectly flags.
5. **Recommended skill focus:** 3–5 specific things the audit skill should
   contain, tied to eval evidence.

Keep it concise and actionable." \
            ${CLAUDE_FLAGS} --max-turns 8 > /dev/null 2>&1 || echo "  ⚠ Audit analysis failed"

        echo "  Generating authoring baseline analysis..."
        claude -p "Read ${BASELINE_DIR}/summary-authoring.json and the individual score files.
Read the eval case definitions at ${EVALS_FILE} — focus on the secure-author type evals.

Produce a concise analysis at ${BASELINE_DIR}/analysis-authoring.md covering:

1. **Secure defaults the model already applies:** Patterns the model avoids
   without being told. The authoring skill should NOT add content for these.
2. **Dangerous patterns the model uses by default:** Where it writes insecure
   code. Focus here.
3. **Context recognition:** Does the model recognise security-sensitive contexts
   (HTML in API responses, user URLs in href, etc.) without being told?
4. **Defence in depth:** Does the model layer defences or rely on single fixes?
5. **Recommended skill focus:** 3–5 specific things the authoring skill should
   contain, tied to eval evidence.
6. **Description keywords:** Based on which contexts the model misses, what
   trigger words should the skill description include?

Keep it concise and actionable." \
            ${CLAUDE_FLAGS} --max-turns 8 > /dev/null 2>&1 || echo "  ⚠ Authoring analysis failed"

        echo "  ✓ Baseline complete"
        echo ""
    fi

    if [ "${BASELINE_ONLY}" == "true" ]; then
        echo "Baseline only mode."
        echo "  Review: ${BASELINE_DIR}/analysis-audit.md"
        echo "  Review: ${BASELINE_DIR}/analysis-authoring.md"
        exit 0
    fi
fi

# ===========================================================================
# PHASE 2: BUILD INITIAL SKILLS
# ===========================================================================

build_initial_skill() {
    local TRACK="$1"  # "audit" or "authoring"
    local SKILL_PATH="skills/security-${TRACK}/SKILL.md"
    local ANALYSIS_PATH="${BASELINE_DIR}/analysis-${TRACK}.md"
    local EVAL_TYPE
    [ "${TRACK}" == "audit" ] && EVAL_TYPE="detect-and-fix" || EVAL_TYPE="secure-author"

    if [ -s "${SKILL_PATH}" ]; then
        echo "  ${TRACK} skill already exists. Skipping initial build."
        return
    fi

    echo "  Building initial ${TRACK} skill..."

    REF_LISTING=""
    for f in "${REFERENCE_DIR}"/*.md; do
        [ -f "$f" ] && REF_LISTING="${REF_LISTING}  - ${f}
"
    done

    local EXTRA_INSTRUCTIONS=""
    if [ "${TRACK}" == "authoring" ]; then
        EXTRA_INSTRUCTIONS="
IMPORTANT: The skill description (in the YAML frontmatter) is a FIRST-CLASS
DELIVERABLE. It must precisely describe which coding contexts should trigger
the skill to load. Read the program.md section on 'Contexts Where the Authoring
Skill Should Trigger' for guidance.

The description should mention specific patterns (innerHTML,
dangerouslySetInnerHTML, postMessage, href with user data) and specific contexts
(rendering user content, cross-origin communication, security header config).
It should also say what it is NOT for (static markup, layout, tests)."
    fi

    claude -p "You are building a minimal ${TRACK} security skill.

Read the baseline analysis at ${ANALYSIS_PATH}.
Read the baseline results at ${BASELINE_DIR}/summary-${TRACK}.json.
Read the reference documents:
${REF_LISTING}
Read program.md for context on the dual-skill model.

Create a MINIMAL skill at ${SKILL_PATH} that addresses ONLY the weaknesses
found in the baseline analysis for ${EVAL_TYPE} evals.

Rules:
1. Start small — 50–100 lines addressing 3–5 specific failure modes.
2. Focus on what the model gets wrong, not what it gets right.
3. Be specific. Tie guidance to actual patterns and frameworks.
4. Include DO NOT guidance for false positives.
5. Explain WHY, not just WHAT.
6. No boilerplate. Every line earns its place.
${EXTRA_INSTRUCTIONS}

Write the skill to ${SKILL_PATH}.
Write construction notes to ${WORKSPACE}/${TRACK}-construction-notes.md." \
        ${CLAUDE_FLAGS} --max-turns 10 > /dev/null 2>&1 || {
        echo "    ⚠ ${TRACK} skill construction failed"
        return
    }

    if [ -s "${SKILL_PATH}" ]; then
        local LINES=$(wc -l < "${SKILL_PATH}")
        echo "    ✓ ${TRACK} skill created (${LINES} lines)"
    else
        echo "    ⚠ No skill produced"
    fi
}

if [ "${TRACK_FILTER}" == "both" ] || [ "${TRACK_FILTER}" == "audit" ]; then
    build_initial_skill "audit"
fi
if [ "${TRACK_FILTER}" == "both" ] || [ "${TRACK_FILTER}" == "authoring" ]; then
    build_initial_skill "authoring"
fi
echo ""

# ===========================================================================
# PHASE 3: ITERATIVE IMPROVEMENT
# ===========================================================================

iterate_track() {
    local TRACK="$1"
    local SKILL_PATH="skills/security-${TRACK}/SKILL.md"
    local TRACK_DIR="${WORKSPACE}/${TRACK}"
    local EVAL_TYPE
    [ "${TRACK}" == "audit" ] && EVAL_TYPE="detect-and-fix" || EVAL_TYPE="secure-author"

    mkdir -p "${TRACK_DIR}"

    local BEST_SCORE="0"
    local BEST_ITER="0"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  TRACK: ${TRACK} (${EVAL_TYPE} evals)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    for ITER in $(seq 1 "${MAX_ITERATIONS}"); do
        local ITER_DIR="${TRACK_DIR}/iteration-${ITER}"
        mkdir -p "${ITER_DIR}"

        echo "  ── Iteration ${ITER}/${MAX_ITERATIONS} ──"

        # Snapshot
        cp "${SKILL_PATH}" "${ITER_DIR}/skill-snapshot.md"

        # Run and score
        run_and_score_evals "${ITER_DIR}" "${SKILL_PATH}" "${EVAL_TYPE}"

        echo ""
        aggregate_by_type "${ITER_DIR}" "${EVAL_TYPE}" "${ITER_DIR}/summary.json"

        local COMPOSITE=$(python3 -c "import json; print(json.load(open('${ITER_DIR}/summary.json'))['overall_composite'])")

        # Baseline comparison
        local BASELINE_FILE="${BASELINE_DIR}/summary-${TRACK}.json"
        local DELTA="n/a"
        if [ -f "${BASELINE_FILE}" ]; then
            local BL=$(python3 -c "import json; print(json.load(open('${BASELINE_FILE}'))['overall_composite'])")
            DELTA=$(python3 -c "print(f'{float(\"${COMPOSITE}\") - float(\"${BL}\"):+.2f}')")
            echo "  Delta from baseline: ${DELTA}"
        fi

        # Track best
        if python3 -c "import sys; sys.exit(0 if float('${COMPOSITE}') > float('${BEST_SCORE}') else 1)"; then
            BEST_SCORE="${COMPOSITE}"
            BEST_ITER="${ITER}"
        fi

        # Check target
        if score_meets_target "${COMPOSITE}" "${TARGET_SCORE}"; then
            echo ""
            echo "  ✅ TARGET REACHED for ${TRACK}! ${COMPOSITE} >= ${TARGET_SCORE}"
            echo ""
            break
        fi

        # Improve
        if [ "${ITER}" -lt "${MAX_ITERATIONS}" ]; then
            echo ""
            echo "  Improving ${TRACK} skill..."

            local EXTRA=""
            if [ "${TRACK}" == "authoring" ]; then
                EXTRA="

Also evaluate and refine the skill's DESCRIPTION (YAML frontmatter). The
description determines whether the skill gets loaded at all. If the authoring
skill is not being triggered in the right contexts, improve the description."
            fi

            local PREV_REF=""
            if [ "${ITER}" -gt 1 ]; then
                local PREV=$((ITER - 1))
                [ -f "${TRACK_DIR}/iteration-${PREV}/summary.json" ] && \
                    PREV_REF="Also read the previous iteration results at ${TRACK_DIR}/iteration-${PREV}/summary.json for comparison."
            fi

            # Write improvement instructions to a temp file
            local IMPROVE_FILE="${TRACK_DIR}/.improve-task-${ITER}.md"
            cat > "${IMPROVE_FILE}" << IMPROVE_EOF
You are improving the ${TRACK} skill based on eval results.

## Read These Files

- Current iteration results: ${ITER_DIR}/summary.json
- Baseline results: ${BASELINE_FILE}
- Baseline analysis: ${BASELINE_DIR}/analysis-${TRACK}.md
- Current skill: ${SKILL_PATH}
${PREV_REF}

## Instructions

Read all the files listed above. Based on the results:

- Dimensions that IMPROVED from baseline → refine the relevant skill content
- Dimensions that are UNCHANGED → rewrite the relevant skill content
- Dimensions that REGRESSED → remove or simplify the relevant content
${EXTRA}

Write the updated skill to ${SKILL_PATH}.
Write a changelog entry to ${TRACK_DIR}/changelog-iteration-${ITER}.md.
IMPROVE_EOF

            claude -p "Read ${IMPROVE_FILE} and follow its instructions." \
                ${CLAUDE_FLAGS} --max-turns 12 > /dev/null 2>&1 || echo "  ⚠ Improvement failed"

            rm -f "${IMPROVE_FILE}"

            if [ -f "${TRACK_DIR}/changelog-iteration-${ITER}.md" ]; then
                {
                    echo "## Iteration ${ITER}"
                    echo "Score: ${COMPOSITE} (delta: ${DELTA})"
                    cat "${TRACK_DIR}/changelog-iteration-${ITER}.md"
                    echo ""
                    echo "---"
                } >> "${TRACK_DIR}/changelog.md"
            fi

            echo "  ✓ Skill updated"
        fi
        echo ""
    done

    echo "  ${TRACK} track complete. Best: ${BEST_SCORE} (iteration ${BEST_ITER})"
    echo ""
}

# Run the tracks
if [ "${TRACK_FILTER}" == "both" ] || [ "${TRACK_FILTER}" == "audit" ]; then
    iterate_track "audit"
fi
if [ "${TRACK_FILTER}" == "both" ] || [ "${TRACK_FILTER}" == "authoring" ]; then
    iterate_track "authoring"
fi

# ===========================================================================
# CROSS-POLLINATION
# ===========================================================================
if [ "${TRACK_FILTER}" == "both" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  CROSS-POLLINATION"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    claude -p "Read the final changelogs:
- ${WORKSPACE}/audit/changelog.md
- ${WORKSPACE}/authoring/changelog.md

Read both skills:
- skills/security-audit/SKILL.md
- skills/secure-authoring/SKILL.md

Produce ${WORKSPACE}/cross-pollination.md identifying:

1. Patterns the audit track revealed that should also appear in the authoring
   skill (e.g., if audits consistently found a vulnerability type, the
   authoring skill should prevent writing that pattern).
2. Patterns from the authoring track that might improve the audit skill
   (e.g., if the model writes certain patterns by default, the audit skill
   should know to check for them).
3. Any contradictions between the two skills that need resolving.

Keep it concise. Actionable items only." \
        ${CLAUDE_FLAGS} --max-turns 8 > /dev/null 2>&1 || echo "  ⚠ Cross-pollination failed"

    [ -f "${WORKSPACE}/cross-pollination.md" ] && echo "  ✓ Cross-pollination analysis written"
    echo ""
fi

# ---- Final report ----
echo "=============================================="
echo "  DUAL-SKILL BUILD-UP COMPLETE"
echo "=============================================="
echo "  Audit skill:     skills/security-audit/SKILL.md"
echo "  Authoring skill: skills/secure-authoring/SKILL.md"
echo ""
echo "  Review cross-pollination: ${WORKSPACE}/cross-pollination.md"
echo ""
