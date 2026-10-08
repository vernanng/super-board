# AGENTS.md

super-board — a GitHub-Project-driven pipeline: the interactive agent session orchestrates, lane workers build · QA · review each card.

## Commands

| Task | Command |
|---|---|
| Install the pack into a target project | `./install.sh [--no-hooks] [--protect-main] <target>` — copies the pack into the target's `.claude/` tree |
| Run the offline test suite | `bash tests/run-safety.sh` |
| Regenerate README skill tables | `python3 scripts/super-board-readme-sync.py` from SKILL.md frontmatter + `skills/families.json` |
| Release | push a `v*` tag → the same checks on Linux/macOS + status-reader smoke checks, publish only if they pass; follow `RELEASING.md` (also lists settings to limit manual bypass) |

## Where things live

| Path | What |
|---|---|
| `skills/` | eight skills: user-typed `super-board`, `super-collect`, `ui-refine-loop`, `visual`, `git-sync`; board-run lane workers `super-build`, `super-qa`, `super-review` |
| `hooks/cleanup-wt.py` | worktree-cleanup hook, NOT a skill |
| `hooks/guard-*.py` | safety guards, wired into settings.json (`--no-hooks` skips) |
| `workflows/super-board-wave.js`, `ui-refine-loop.js` | board wave + UI refine workflows |
| `.claude/` (installed tree) | `skills/<all eight>/` · `hooks/guard-*.py, cleanup-wt.py` · `workflows/super-board-wave.js, ui-refine-loop.js` · `bin/super-board-*.sh (incl. pr-body), super-board-*.py (status, merge-policy, agents-md, settings, setup), super-qa-file-bug.sh, super-review-file-refactor.sh` |
| `scripts/` | pack source copies; skills call the installed form `.claude/bin/<script>` |
| `scripts/super-board-github-read.py`, `super-board-gh-guard.sh` | GitHub reads + `gh` quota guard |
| `scripts/super-board-readme-sync.py`, `skills/families.json` | generate README skill tables |
| `skills/super-board/references/` | writing-standard.md · rate-limit-etiquette.md · pr-author-notes.md · ticket-format.md · run-workflow.md |
| `docs/agents/issue-tracker.md` | ticket format read by `/to-tickets` |
| `tests/` | offline suite `run-safety.sh`; `test_writing_format.py` |
| Install side effects | refreshes the managed `<!-- super-board:begin … -->` block in the target's AGENTS.md when one exists (nothing outside the markers) · records an older install in `.claude/super-board/upgrade.json` · prints grouped emoji output · asks nothing |

## Conventions

| Rule | Value |
|---|---|
| Board shape | columns Backlog · Ready · Building · QA · Review · Blocked · Done, no Skipped, no per-board `variant`; labels `qa` (skips Building) · `bug` · `feature`/none (built); change routing in `scripts/super-board-wave-plan.sh`, `workflows/super-board-wave.js` and `run.md` → "Lanes and label routing" together |
| Orchestrator | the interactive agent session that invokes `/super-board run` is an orchestrator, NOT a worker |

### Orchestrator duties

| # | Duty |
|---|---|
| 1 | Verify preconditions: clean git, no orphan workers, GraphQL quota, etc. |
| 2 | Dispatch per the config's `worker_backend` — `"workflow"` (default): stay in-session and run the wave loop in `skills/super-board/references/run-workflow.md` (plan a wave · claim assignees · launch the `super-board-wave` workflow · reconcile · repeat; lane agents do all product work) · `"claude-p"` (legacy, explicit opt-in only): spawn `nohup .claude/bin/super-board-run.sh <slug> &`, report PID + log path, exit — the runner refuses to start (exit 78) unless the config sets this value |
| 3 | Report back to the user: dispatch confirmation (claude-p) or one status line per wave (workflow) |

## Boundaries

### Always

Workers (`super-build`, `super-qa`, `super-review`) share the dispatcher's `gh` token bucket; they MUST:

- Use `.claude/bin/super-board-github-read.py` for required GitHub reads; exit 79 stops the run.
- Run its `--check` before GitHub writes, migrations, merges and new dispatch; preserve work when halted.
- Source `.claude/bin/super-board-gh-guard.sh` (`scripts/` in this repo) at worker start.
- Call `sb_gh_guard_check 200` before any burst of `gh` calls.
- Prefer local `git blame` / `git log` over `gh api graphql` for any sub-agent that doesn't need fresh state.
- Cap adversarial sub-agents at 50 gh calls each; on exhaustion return `confidence: insufficient_data` rather than burn the shared quota.
- Append `gh-quota-on-exit: graphql=<n>/5000 rest=<n>/5000` to the PR handoff comment.
- Full discipline: `skills/super-board/references/rate-limit-etiquette.md`.

### Ask first

- Patch the dispatcher script or skill files mid-run? Capture the symptom and tell the user; wait for explicit approval.
- A problem surfaces during a run? Reply "I saw X. Want me to dig in or stop the runner?" — not "I went ahead and fixed it."

### Never

The orchestrator MUST NOT:

- Build, test, review or fix issues itself — all product work goes to workflow lane agents (or `claude -p` workers on the legacy backend).
- Wait on individual workers or relay their work — evidence goes back to the GitHub issue + PR; orchestrator output is the dispatch confirmation or one short report per wave, not the run result.
- Hold context for multi-card progress — state lives on the GitHub Project board + the inflight lockfiles, not in the session.

<!-- super-board:begin v3.1.1 (managed; edits inside are overwritten on upgrade) -->
## Super Board

Board: Backlog · Ready · Building · QA · Review · Blocked · Done. Labels route: `qa` skips Building · `bug`, `feature`, none → built first.

| When | Use | NEVER |
|---|---|---|
| Set up / repair the board | `/super-board onboard` | DON'T hand-edit config mid-run |
| Check tickets before a run | `/super-board lint` | NEVER run with AC-less tickets |
| Drain the board | `/super-board run` | NEVER build, test or merge from the orchestrator |
| Board state / halt | `/super-board status` · `/super-board stop` | |
| Build one ticket | `/super-build` | NEVER build outside the card's worktree |
| QA a branch, or a live URL alone | `/super-qa` · `/super-qa <url>` | NEVER mark QA pass without evidence |
| Review a PR, merge | `/super-review` | NEVER `gh pr merge` direct — merge gate only |
| File bugs from Sentry, PostHog, PRs | `/super-collect` | DON'T file without a verifier pass |
| UI polish | `/ui-refine-loop` (human runs it) | board NEVER runs it |
| Diagram / explainer page | `/visual` | |
| Commit, pull, push this branch | `/git-sync` | NEVER force push or rebase shared history |

| Rule | Value |
|---|---|
| Config | `.claude/super-board/configs/<slug>.json` |
| Isolation | 1 card · 1 worktree · 1 branch |
| Merge | auto for normal changes · money, auth, destructive schema (DROP/TRUNCATE/RENAME) → human · PR > 400 changed lines → human |
| Migrations | additive → robot migrates allowed DBs only · live DB ALWAYS → 🙋 needs you |
| Blocked card | block-template comment · last line `blocked-by:` · 🙋 = needs you |
| Secrets | NEVER read `.env`; key names via `.claude/bin/super-board-env-check.sh` |

## Writing (super-board)

| Thing | Format → `.claude/skills/super-board/references/writing-standard.md` |
|---|---|
| Commit, PR title | `<emoji> [type] scope: subject` + short bullets · ✨ feat 🐛 fix 🔧 chore ♻️ refactor 🧪 test 📝 docs |
| PR body | blocks: status · Problem · Solution · AC + proof · history · Before\|After · Risk — `super-board-pr-body.sh` |
| Ticket | Problem · Context · Fix · AC · Risk · Blocked by → `docs/agents/issue-tracker.md` |
| Comment | `[role] [label] status` · Did · ✅ Done · ❌ Not done · Next · ≤ 8 lines |
| PR author notes | file + critical inline review comments: Purpose · What changed · Why it matters → `pr-author-notes.md` |

- NEVER chain steps with arrows. One step per line, lettered under Where.
- NEVER link screenshots. Embed a raw URL pinned to a sha.
- DON'T repeat file lists in status comments. DON'T write "Not verified" or "Next" in a PR body.
<!-- super-board:end -->

## Commits and PRs

Commits, PR bodies, tickets and comments follow `skills/super-board/references/writing-standard.md` — the same standard super-board writes into every project it installs.

| Thing | Format |
|---|---|
| Commit | `<emoji> [type] scope: subject` + short bullets · ✨ feat · 🐛 fix · 🔧 chore · ♻️ refactor · 🧪 test · ⚡ perf · 📝 docs · 👷 ci · 💄 ui · 🔒 security · ⏪ revert · 🚧 wip |
| PR body | marker blocks, one owner each: status · problem · solution · ac · history · visual · risk |
| Ticket | Problem · Context · Fix · Acceptance Criteria · Risk · Blocked by (+ Evidence for bugs) → `docs/agents/issue-tracker.md` |
| Comment | `[role] [label] status` · Did · ✅ Done · ❌ Not done · Next · ≤ 8 lines |
| PR author notes | Purpose · What changed · Why it matters, in native file/inline review comments → `skills/super-board/references/pr-author-notes.md` |

- NEVER rewrite a whole PR body — `scripts/super-board-pr-body.sh` rewrites one block.
- ALWAYS change a format in `writing-standard.md` first, then the templates and `tests/test_writing_format.py`.
