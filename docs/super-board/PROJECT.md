# super-board — project notes

super-board is a GitHub-Project-driven autonomous pipeline: you put cards on a
board, and headless lane agents (Build → QA → Review) turn them into merged PRs
with evidence on the issue and PR. This checkout is the OpenCode-enabled fork of
the pack, dogfooding itself.

## What it is

- Five verbs you type: `/super-board` (onboard · lint · status · run · stop),
  `/super-collect`, `/ui-refine-loop`, `/visual`, `/git-sync`.
- Three lanes the board runs: `super-build` (builder), `super-qa` (tester),
  `super-review` (reviewer + merge gate).
- Skills live in `skills/`; dispatcher scripts and helpers in `scripts/`;
  guard hooks in `hooks/`. An install copies them into `.claude/` and `.opencode/`.

## Host

OpenCode. Skills load from `.claude/skills`; slash commands from
`.opencode/commands`; the guards from `.opencode/plugins/super-board-guards.ts`
(which replays `hooks/*.py` through OpenCode permission/tool hooks).
`worker_backend: "opencode"` makes the runner spawn `opencode run --auto` lane
workers via `.claude/bin/super-board-run.sh`.

## Commands

| Task | Command |
|---|---|
| Offline test suite | `bash tests/run-safety.sh` |
| Install for OpenCode | `./install-opencode.sh <target>` |
| One-line install | `get.sh` with `--opencode` |
| Sync the branch | `/git-sync` |

## Where things live

- `skills/<name>/SKILL.md` — agent instructions per skill.
- `scripts/super-board-*.sh|py` — board engine, dispatcher, gate, helpers.
- `hooks/guard-*.py`, `hooks/cleanup-wt.py` — safety guards.
- `workflows/super-board-wave.js` — Claude Code in-session wave workflow (unused
  on OpenCode; the headless runner covers the same ground).
- `.claude/super-board/configs/<slug>.json` — this board's config; `active` points at it.

## Conventions

- One branch and one PR per issue: `issue-<N>-<kebab-title>`.
- Commits, PR bodies, tickets and comments follow
  `skills/super-board/references/writing-standard.md`.
- The interactive session is an **orchestrator, not a worker**: it dispatches and
  reports; lanes do all product work.