# Scoring Rubric — Frontend Security Skill (v2)

You are judging the output of an AI coding agent that was given either insecure
code to fix or a feature spec to implement securely. Score each applicable
dimension on a 0–3 scale.

## Scoring Scale

- **3 — Excellent.** Correct, complete, no meaningful gaps. Demonstrates deep understanding.
- **2 — Good.** Mostly correct with minor omissions that do not leave exploitable vulnerabilities.
- **1 — Weak.** Meaningful gaps — missed critical vulnerabilities, introduced regressions, or wrote insecure code.
- **0 — Poor.** Fundamental misunderstanding, critical vulnerabilities remain, or the output is harmful.

## Dimensions

### vulnerability_detection (0–3) — detect-and-fix only

Does the agent identify the real vulnerabilities in the input code?

| Score | Criteria |
|-------|----------|
| 3 | All critical and high vulnerabilities identified. Nothing exploitable missed. Each finding demonstrates understanding of the actual attack vector, not just pattern matching. |
| 2 | Critical vulnerabilities found but one or two high-severity issues missed. No directly exploitable vulnerability left unmentioned. |
| 1 | Some vulnerabilities found but critical ones missed. The audit gives a false sense of security. |
| 0 | Obvious vulnerabilities missed entirely. Critical XSS or injection left unfixed. |

Check: Are CRITICAL vulnerabilities in the key_expectations all identified?

### fix_correctness (0–3) — both types

Are the applied fixes or authored patterns actually secure?

| Score | Criteria |
|-------|----------|
| 3 | Every fix is correct. The root cause is addressed, not just the symptom. For secure-author: code would pass a security review without findings. |
| 2 | Most fixes are correct. One fix is suboptimal but not exploitable (e.g., overly permissive but not dangerous). |
| 1 | Some fixes are incorrect — they appear to address the issue but leave the vulnerability exploitable, or they introduce a different vulnerability. |
| 0 | Fixes are fundamentally wrong, or no fixes were applied. For secure-author: code contains obvious vulnerabilities. |

Check: Do the fixes address the root cause? Would a security reviewer approve?

### fix_completeness (0–3) — detect-and-fix only

Are all identified vulnerabilities addressed with a fix, not just mentioned?

| Score | Criteria |
|-------|----------|
| 3 | Every identified vulnerability has a corresponding fix applied to the code. The AUDIT.md documents all changes. |
| 2 | Most vulnerabilities are fixed. One is identified but left unfixed with a TODO or note. |
| 1 | Several vulnerabilities are identified but not fixed. The audit reads like a report without remediation. |
| 0 | Vulnerabilities are mentioned but no fixes are applied. |

Check: Is there a fix in the code for every finding in the audit?

### regression_avoidance (0–3) — detect-and-fix only

Do the fixes preserve the existing functionality?

| Score | Criteria |
|-------|----------|
| 3 | All existing functionality preserved. Component renders the same content. API contracts unchanged. User interactions still work. |
| 2 | Functionality mostly preserved. One minor feature slightly altered but not broken (e.g., formatting change). |
| 1 | A feature is broken by the fix. Existing behaviour removed or changed in a user-visible way. |
| 0 | Multiple features broken. The component no longer works as specified. |

Check: Does the fixed code still do everything the original code did?

### secure_defaults (0–3) — secure-author only

Does the agent write secure code by default, without being told to?

| Score | Criteria |
|-------|----------|
| 3 | All output avoids dangerous patterns. Safe APIs used by default. Security-sensitive decisions (URL validation, HTML rendering, postMessage origins) handled correctly without the spec mentioning security. |
| 2 | Mostly secure but one pattern is suboptimal (e.g., uses innerHTML but sanitises it, when textContent would have been better). |
| 1 | One or more dangerous patterns used without mitigation. The agent implemented the spec literally without considering security implications. |
| 0 | Multiple dangerous patterns. innerHTML with unsanitised user input, no URL validation, postMessage with '*'. |

Check: Would a security reviewer find issues in code written from scratch?

### false_positive_avoidance (0–3) — detect-and-fix only

Does the agent avoid flagging safe patterns as vulnerabilities?

| Score | Criteria |
|-------|----------|
| 3 | No false positives. Safe framework defaults (React auto-escaping, Twig auto-escaping) correctly recognised as safe. The agent understands when a pattern is dangerous vs when it is protected. |
| 2 | One borderline false positive noted as low-risk rather than flagged as a vulnerability. |
| 1 | Multiple false positives that would waste developer time. Safe patterns flagged as critical or high. |
| 0 | Pervasive false positives. Auto-escaped expressions flagged as XSS. |

Check: Are auto-escaped expressions NOT flagged? Are safe libraries NOT flagged?

### framework_idiom (0–3) — both types

Does the output use framework-appropriate patterns?

| Score | Criteria |
|-------|----------|
| 3 | Fixes and code are idiomatic for the framework. React code uses hooks and JSX correctly. Twig code uses framework-native escaping. Vanilla JS uses modern DOM APIs. CSP uses nonce-based patterns with Express middleware correctly. |
| 2 | Mostly idiomatic with one non-idiomatic pattern that still works (e.g., using a class component instead of a function component). |
| 1 | Generic patterns that ignore the framework. Framework-specific solutions exist but were not used. |
| 0 | Code contradicts framework conventions or breaks framework protections. |

Check: Does the code look like an expert in this framework wrote it?

### defence_in_depth (0–3) — both types

Does the output layer multiple security measures rather than relying on a single defence?

| Score | Criteria |
|-------|----------|
| 3 | Multiple defensive layers applied. For CSP: strict policy AND nonces AND companion headers. For XSS: safe DOM APIs AND URL validation AND input encoding. The agent thinks beyond the immediate vulnerability. |
| 2 | Primary defence is correct and one additional layer is present (e.g., CSP AND X-Content-Type-Options). |
| 1 | Single-layer defence. The immediate vulnerability is fixed but no broader protections are considered. |
| 0 | No defensive thinking. Fix is narrow and leaves adjacent attack surfaces exposed. |

Check: Did the agent think about the broader security posture, not just the specific bug?

## Scoring Process

1. Read the eval case — its type, prompt, focus dimensions, and key expectations
2. Read the agent's output (fixed files and AUDIT.md for detect-and-fix, or the
   authored file for secure-author)
3. For each dimension in the eval's `focus_dimensions`, score 0–3
4. For other dimensions, score only if relevant evidence exists
5. Write a brief justification for each score (1–2 sentences)
6. Check key expectations: list which were met and which were missed
7. Calculate the composite score (average of all scored dimensions)

## Output Format

```json
{
  "eval_id": 1,
  "eval_name": "react-xss-detect-and-fix",
  "eval_type": "detect-and-fix",
  "scores": {
    "vulnerability_detection": { "score": 3, "justification": "..." },
    "fix_correctness": { "score": 2, "justification": "..." },
    "fix_completeness": { "score": 3, "justification": "..." },
    "regression_avoidance": { "score": 2, "justification": "..." },
    "false_positive_avoidance": { "score": 3, "justification": "..." },
    "framework_idiom": { "score": 3, "justification": "..." },
    "defence_in_depth": { "score": 2, "justification": "..." }
  },
  "composite_score": 2.57,
  "expectations_met": [
    "FIXES: Removes dangerouslySetInnerHTML from the h1",
    "DOES NOT: Flag {profile.name} in alt attribute as XSS"
  ],
  "expectations_missed": [
    "FIXES: Did not address the inline <script> JSON serialisation"
  ],
  "additional_observations": [
    "Good use of DOMPurify for the bio field"
  ]
}
```

Dimensions that were not evaluated (not in focus_dimensions and no relevant
evidence) should be omitted from the scores object and excluded from the
composite average.
