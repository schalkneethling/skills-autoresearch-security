# Agent Skill — Dual-Skill Incremental Build-Up (v2)

Build two complementary security skills from scratch, driven by evidence of
what the model actually needs help with.

## The Two Skills

This process produces two separate skills for two distinct use cases.

### Security Audit Skill

**Purpose:** Guide an agent that has been explicitly asked to review code for
security vulnerabilities. The agent knows it is in security mode.

**Trigger:** Obvious — someone asks for a security review, audit, or
vulnerability scan.

### Secure Authoring Skill

**Purpose:** Intervene when a general-purpose coding agent enters a
security-sensitive context. Nobody says "write secure code" — the agent is
building a feature and the skill must recognise that the feature involves
patterns with security implications.

**Trigger:** Subtle — the skill's description must precisely encode which coding
contexts have security implications (rendering user content, handling external
URLs, postMessage, configuring CSP) without triggering on contexts that do not
(static markup, layout, tests).

**The skill description is a first-class deliverable.** A brilliant skill with a
poor description never gets loaded.

## How It Works

```
Phase 1: Baseline           Phase 2: Build             Phase 3: Iterate
─────────────────           ──────────────             ─────────────────
Run ALL evals           →   Read baseline analyses  →  Run each track's evals
without any skill            Build TWO minimal skills   with its skill
                             from observed weaknesses
Score and analyse                                      Score, compare to baseline
  Split analysis:            Audit skill: focused       Three outcomes:
  - Audit track               on detection gaps          ✓ Improved → keep
  - Authoring track          Authoring skill: focused    — No change → rewrite
                               on insecure defaults      ✗ Regressed → remove
                               + careful description
                                                       Cross-pollinate findings
                                                       between tracks
```

## Current Run: Frontend Injection & Defence

**Topics:** XSS prevention, DOM security, CSP configuration

| # | Name | Type | Used for |
|---|------|------|----------|
| 1 | React XSS detect-and-fix | detect-and-fix | Audit skill |
| 2 | Twig XSS/CSRF detect-and-fix | detect-and-fix | Audit skill |
| 3 | DOM comment section detect-and-fix | detect-and-fix | Audit skill |
| 4 | CSP configuration detect-and-fix | detect-and-fix | Audit skill |
| 5 | React search secure-author | secure-author | Authoring skill |
| 6 | Vanilla widget secure-author | secure-author | Authoring skill |

## Project Structure

```
skills-autoresearch-v2/
├── program.md                  ← Conceptual guide
├── config.json                 ← Points origin_skill at your skill repo
├── skills/
│   ├── security-audit/
│   │   └── SKILL.md            ← Audit skill (starts empty)
│   └── secure-authoring/
│       └── SKILL.md            ← Authoring skill (starts empty)
├── reference/                  ← Copied from origin_skill at startup
│   ├── origin-SKILL.md         ← The origin skill's SKILL.md
│   ├── xss-prevention.md       ← Origin references (all copied in)
│   ├── dom-security.md
│   └── ...
├── evals/
│   ├── eval-cases.json
│   └── rubric.md
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

## Setup

1. Update `origin_skill` in `config.json` to point at your skill:

   ```json
   {
     "origin_skill": "~/dev/claude-toolkit/skills/frontend-security",
     "max_iterations": 5,
     "target_score": 2.7
   }
   ```

2. The run script copies the origin skill's SKILL.md and all its reference
   files into `reference/` at startup. The origin is never modified.

## Quick Start

### Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI
- Python 3.10+

### Recommended: Baseline First

```bash
# Run baseline only — review before building skills
bash run-loop.sh --baseline-only

# Review the analyses
cat workspace/baseline/analysis-audit.md
cat workspace/baseline/analysis-authoring.md

# Then run the full loop
bash run-loop.sh --skip-baseline
```

### Single Track

```bash
bash run-loop.sh --track audit       # Audit skill only
bash run-loop.sh --track authoring   # Authoring skill only
```

### Interactive

```bash
claude
> Read program.md. Run the baseline and show me both analyses before
> we build anything.
```

## Scoring Dimensions

| Dimension | Audit | Authoring | What it measures |
|-----------|:-----:|:---------:|-----------------|
| vulnerability_detection | ✓ | | Are real vulnerabilities found? |
| fix_correctness | ✓ | ✓ | Are fixes/code actually secure? |
| fix_completeness | ✓ | | Is every finding addressed? |
| regression_avoidance | ✓ | | Does the fix preserve functionality? |
| secure_defaults | | ✓ | Is code secure without being told? |
| false_positive_avoidance | ✓ | | Are safe patterns not flagged? |
| framework_idiom | ✓ | ✓ | Is code idiomatic for the framework? |
| defence_in_depth | | ✓ | Are multiple defensive layers applied? |

## Cross-Pollination

After iterating both tracks, a cross-pollination step identifies findings that
should flow between the skills. For example, if the audit track consistently
finds a vulnerability pattern, the authoring skill should prevent writing that
pattern in the first place.

## Future Topic Groups

| Group | Topics | Status |
|-------|--------|--------|
| Frontend injection & defence | XSS, DOM security, CSP | ← current |
| Authentication & sessions | JWT, CSRF, session management | planned |
| Input & uploads | Input validation, file upload security | planned |
| Dependencies & config | npm audit, CORS, error handling | planned |

Each run preserves the existing skills and adds content for new topics.

## Licence

MIT
