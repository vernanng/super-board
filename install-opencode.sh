#!/usr/bin/env bash
# super-board installer for OpenCode.
#
# OpenCode reads .claude/skills natively, so install.sh already puts the eight
# skills where OpenCode looks. This adds the OpenCode-only pieces:
#   - .opencode/commands/*.md   the five typed skills as slash commands
#   - .claude/hooks/*.py        the guard scripts (install.sh --no-hooks skips them)
#   - .opencode/plugins/super-board-guards.ts   replays those scripts via OpenCode hooks
#
# Usage: ./install-opencode.sh [--no-guards] [target-project-dir]
# Defaults to the current working directory. --no-guards skips the plugin and the
# guard scripts (OpenCode will not wire settings.json hooks either way).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARDS=1
TARGET=""
for arg in "$@"; do
  case "$arg" in
    --no-guards) GUARDS=0 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $arg" >&2; exit 64 ;;
    *) TARGET="$arg" ;;
  esac
done
TARGET="${TARGET:-$PWD}"
[ -d "$TARGET" ] || { echo "target directory not found: $TARGET" >&2; exit 64; }

# Copy unless source and destination are the same file. Re-running the installer
# in the pack itself (dogfooding) must not make `cp` fail on an identical path.
copy_file() { [ "$1" -ef "$2" ] || cp "$1" "$2"; }

# Skills, .claude/bin scripts and workflows. --no-hooks leaves .claude/settings.json
# alone: OpenCode ignores it, and the guards are wired by the plugin below.
SUPER_BOARD_QUIET_NEXT=1 bash "$ROOT/install.sh" --no-hooks "$TARGET"

# OpenCode does not run skills as /commands, so bridge the five typed skills. The
# board-run lanes (super-build/-qa/-review) are dispatched by the runner, not typed.
mkdir -p "$TARGET/.opencode/commands"
for c in "$ROOT"/.opencode/commands/*.md; do
  copy_file "$c" "$TARGET/.opencode/commands/$(basename "$c")"
done
echo "   ✓ $(ls "$ROOT"/.opencode/commands/*.md | wc -l | tr -d ' ') slash commands → .opencode/commands/"

if [ "$GUARDS" -eq 1 ]; then
  mkdir -p "$TARGET/.claude/hooks" "$TARGET/.opencode/plugins"
  for h in "$ROOT"/hooks/*.py; do
    [ -f "$h" ] || continue
    copy_file "$h" "$TARGET/.claude/hooks/$(basename "$h")"
  done
  copy_file "$ROOT/.opencode/plugins/super-board-guards.ts" "$TARGET/.opencode/plugins/super-board-guards.ts"
  echo "   🛡️  guard scripts + plugin → .claude/hooks/ + .opencode/plugins/"
fi

echo "🎉 super-board installed for OpenCode in $TARGET"
echo "👉 next: open OpenCode here and run /super-board onboard (worker_backend \"opencode\")"
