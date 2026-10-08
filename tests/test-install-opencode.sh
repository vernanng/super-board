#!/usr/bin/env bash
# Tests install-opencode.sh: the OpenCode install path. Skills go in via
# install.sh --no-hooks (OpenCode reads .claude/skills natively); this script adds
# .opencode/commands, .claude/hooks/*.py and the guard plugin — and must NOT write
# a Claude settings.json, because that is install.sh's Claude-only job.
set -euo pipefail
cd "$(dirname "$0")"
INSTALL="../install-opencode.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }

ALL_SKILLS="super-board super-build super-qa super-review super-collect ui-refine-loop visual git-sync"
COMMANDS="super-board super-collect ui-refine-loop visual git-sync"

# 1 — fresh project: every skill, the five commands, the guard scripts and the
#     plugin land; no Claude settings.json is written.
T=$(mktemp -d)
"$INSTALL" "$T" >/dev/null 2>&1
for s in $ALL_SKILLS; do
  [ -f "$T/.claude/skills/$s/SKILL.md" ] || fail "$s/SKILL.md missing"
done
for c in $COMMANDS; do
  [ -f "$T/.opencode/commands/$c.md" ] || fail "command $c.md missing"
done
[ -f "$T/.opencode/plugins/super-board-guards.ts" ] || fail "guard plugin missing"
for h in guard-secrets guard-delete-outside guard-worktree-path guard-protected-push guard-key-literals cleanup-wt; do
  [ -f "$T/.claude/hooks/$h.py" ] || fail "guard script $h.py missing"
done
[ ! -f "$T/.claude/settings.json" ] || fail "settings.json written — install-opencode must not wire Claude hooks"
rm -rf "$T"

# 2 — --no-guards: skills + commands only; no plugin, no guard scripts.
T=$(mktemp -d)
"$INSTALL" --no-guards "$T" >/dev/null 2>&1
[ -f "$T/.opencode/commands/super-board.md" ] || fail "--no-guards: commands missing"
[ ! -e "$T/.opencode/plugins/super-board-guards.ts" ] || fail "--no-guards: plugin installed"
[ ! -e "$T/.claude/hooks/guard-secrets.py" ] || fail "--no-guards: guard scripts installed"
rm -rf "$T"

# 3 — an unknown flag is rejected, not silently ignored.
T=$(mktemp -d)
if "$INSTALL" --bogus "$T" >/dev/null 2>&1; then fail "unknown flag should exit non-zero"; fi
rm -rf "$T"

echo "PASS: test-install-opencode"
