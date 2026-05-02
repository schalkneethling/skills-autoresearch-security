# Frontend Security — Dual-Skill Incremental Build-Up

You are an autonomous agent building two complementary security skills from
scratch, driven by evidence of what the model actually needs help with.

## The Two Skills

This process produces two separate skills for two distinct use cases.

### 1. Security Audit Skill (`skills/security-audit/SKILL.md`)

**When it is used:** Explicitly, by an agent tasked with reviewing code for
security vulnerabilities. Someone says "audit this code" or "do a security
review." The agent knows it is in security mode.

**What it does:** Guides the agent through systematic vulnerability detection,
correct severity classification, framework-aware analysis, and remediation that
preserves existing functionality.

**Description challenge:** Low. The trigger is obvious — the user asks for a
security review.

### 2. Secure Authoring Skill (`skills/secure-authoring/SKILL.md`)

**When it is used:** Implicitly, by a general-purpose coding agent that
recognises it has entered a security-sensitive context. Nobody says "write
secure code" — the agent is just building a feature, and the skill must
intervene when the feature involves patterns that have security implications.

**What it does:** Steers the agent towards safe defaults when writing code that
handles user input, renders dynamic content, communicates across origins, or
configures security boundaries.

**Description challenge:** High. The skill's description is a threat-surface
detector — it must encode which coding contexts have security implications
without triggering on contexts that do not.

#### Contexts Where the Authoring Skill Should Trigger

- Rendering user-provided or externally sourced content in the DOM
- Building components that accept and display user input
- Working with URLs from external/untrusted sources (href, src, redirects)
- Implementing postMessage or cross-origin communication
- Configuring Content Security Policy or security headers
- Handling file uploads or user-submitted media
- Building authentication or session management flows
- Making fetch/XHR requests with user-controlled parameters
- Serialising data for injection into HTML (SSR, inline scripts)
- Using innerHTML, dangerouslySetInnerHTML, set:html, |raw, or any raw
  HTML rendering mechanism

#### Contexts Where It Should NOT Trigger

- Writing static markup with developer-controlled content
- Implementing pure layout, styling, or animation
- Writing unit or integration tests
- Building components that only display hardcoded or developer-controlled data
- Working with build tooling, bundler configuration, or CI/CD
- General refactoring that does not change data flow

## Philosophy

1. **Build from evidence, not assumptions.** Every line in each skill exists
   because an eval proved the model needs it.
2. **Steer, do not teach.** The model already knows a lot. The skills correct
   specific blind spots and failure modes.
3. **The two skills are independent.** They are scored independently, improved
   independently, and may diverge significantly in content and tone. What helps
   an auditor may confuse an author, and vice versa.
4. **The authoring skill's description is a first-class deliverable.** A
   brilliant skill with a poor description never gets loaded. The description
   is evaluated and refined alongside the skill content.
5. **Token efficiency matters.** Every line consumes context. If a line does not
   change model behaviour, it should not exist.

## Topic Groups

The full security domain covers many topics. We work in focused groups of three
or four related areas per run. This keeps each run fast and the resulting skill
additions targeted.

**Run 1 — Frontend injection and defence**
- XSS prevention (reflected, stored, DOM-based)
- DOM security (safe APIs, dangerous sinks, postMessage)
- Content Security Policy (configuration, nonce/hash, common mistakes)

Future runs: authentication and sessions, input validation and file uploads,
dependency and configuration security.

## Process

### Phase 1 — Baseline (no skill)

Run ALL eval cases without either skill. This measures the model's native
ability at both auditing and authoring.

The baseline analysis should answer, separately for each skill track:

**For the audit track (detect-and-fix evals):**
- Which vulnerability categories does the model already find reliably?
- Which does it miss? (These are what the audit skill should address.)
- Does it produce false positives? (The skill should include DO NOT guidance.)
- Are its severity classifications accurate?
- Are its fixes correct and complete?

**For the authoring track (secure-author evals):**
- Which dangerous patterns does the model already avoid by default?
- Which does it use without mitigation? (These are what the authoring skill
  should address.)
- Does it recognise security-sensitive contexts without being told?
- Does it apply defence in depth or just single-layer fixes?

### Phase 2 — Build Initial Skills

Construct two minimal skills from the baseline findings. Use the existing
reference documents as raw material — extract only what addresses observed
weaknesses.

**Audit skill construction:**
- Focus on missed vulnerability patterns and incorrect severity classifications
- Add DO NOT guidance for false positives
- Include framework-specific patterns the model misses
- Structure around the audit workflow: scan → classify → fix → verify

**Authoring skill construction:**
- Focus on dangerous patterns the model uses by default
- Emphasise safe alternatives with clear reasoning
- Structure around the authoring workflow: the agent is building a feature and
  needs to recognise when a security decision is being made
- Write the description — this is critical and should be treated as part of the
  skill, not metadata

**Authoring skill description guidelines:**

The description is what the skill-loading system uses to decide whether to load
the skill. It must be:

- Specific enough to trigger on security-sensitive coding contexts
- Broad enough to cover the range of contexts listed above
- Concrete — mention actual patterns (innerHTML, dangerouslySetInnerHTML,
  postMessage, href with user data) rather than abstract concepts
- Negative — mention what it is NOT for (static markup, layout, tests) to
  avoid false triggers

Example structure:
```
Use this skill when writing code that renders user-provided content, handles
URLs from external sources, implements cross-origin communication (postMessage,
CORS), configures Content Security Policy, or uses raw HTML rendering
(innerHTML, dangerouslySetInnerHTML, set:html, |raw). Applies to React, Twig,
Astro, and vanilla JavaScript. Do NOT load for static markup, layout/styling,
test files, or components with only developer-controlled data.
```

### Phase 3 — Iterative Improvement

Run evals with each skill loaded (audit skill for detect-and-fix evals,
authoring skill for secure-author evals). Score, compare to baseline, and
iterate.

Each skill is improved independently:

**Audit skill iteration:**
1. Run detect-and-fix evals with the audit skill
2. Score against audit-relevant dimensions (vulnerability_detection,
   fix_correctness, fix_completeness, regression_avoidance,
   false_positive_avoidance, framework_idiom)
3. Compare to baseline — improved / unchanged / regressed?
4. Refine the skill

**Authoring skill iteration:**
1. Run secure-author evals with the authoring skill
2. Score against authoring-relevant dimensions (secure_defaults,
   fix_correctness, framework_idiom, defence_in_depth)
3. Compare to baseline — improved / unchanged / regressed?
4. Refine the skill AND its description

**Cross-pollination:** After each iteration, check whether findings from one
track should inform the other. If the audit track reveals a pattern the model
consistently misses, the authoring skill should include guidance to avoid
writing that pattern in the first place.

### Phase 4 — Graduation

When both skills reach the target score for this topic group:
1. Snapshot both skills
2. Document what worked and what did not
3. Move to the next topic group, preserving both skills as starting points

## Files

```
skills-autoresearch-v2/
├── program.md                ← You are reading this
├── config.json               ← Points origin_skill at your skill repo
├── skills/
│   ├── security-audit/
│   │   └── SKILL.md          ← Audit skill (starts empty)
│   └── secure-authoring/
│       └── SKILL.md          ← Authoring skill (starts empty)
├── reference/                ← Copied from origin_skill at startup (read-only)
│   ├── origin-SKILL.md       ← The origin skill's SKILL.md
│   ├── xss-prevention.md     ← Origin skill's references (all copied)
│   ├── dom-security.md
│   ├── csp-configuration.md
│   ├── framework-patterns.md
│   └── ...                   ← Any other reference files from the origin
├── evals/
│   ├── eval-cases.json       ← All eval cases (both types)
│   └── rubric.md             ← Scoring dimensions
├── scripts/
│   ├── setup-evals.py
│   ├── aggregate.py
│   └── judge-prompt.md
├── run-loop.sh
└── workspace/
    ├── baseline/
    │   ├── analysis-audit.md
    │   └── analysis-authoring.md
    ├── audit/
    │   ├── iteration-1/ ... iteration-N/
    │   └── changelog.md
    ├── authoring/
    │   ├── iteration-1/ ... iteration-N/
    │   └── changelog.md
    └── cross-pollination.md
```

The `reference/` directory is populated automatically from `origin_skill` in
config.json when the run starts. The origin skill is never modified — the
harness copies its SKILL.md (as `origin-SKILL.md`) and all files from its
`references/` subdirectory into `reference/`. These serve as raw material for
the skill-building step.

## Running

### Option A: Full run

```bash
bash run-loop.sh
```

### Option B: Baseline only (recommended first time)

```bash
bash run-loop.sh --baseline-only
# Review workspace/baseline/analysis-audit.md
# Review workspace/baseline/analysis-authoring.md
# Then continue:
bash run-loop.sh --skip-baseline
```

### Option C: Single track

```bash
bash run-loop.sh --track audit       # Only audit skill
bash run-loop.sh --track authoring   # Only authoring skill
```

### Option D: Let Claude Code drive

```bash
claude
> Read program.md. Run the baseline and show me both analyses before we
> build the initial skills.
```
