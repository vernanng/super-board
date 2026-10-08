import { Plugin } from "@opencode/plugin"
import { spawn, spawnSync } from "node:child_process"
import { join } from "node:path"

// super-board's guards are Python PreToolUse hooks written for Claude Code's hook
// JSON (hooks/*.py). OpenCode has no settings.json hooks, so this plugin replays
// each tool action through them and turns a deny payload into a permission deny.
// The Python scripts stay the single source of truth.

// OpenCode permission action -> the Claude tool_name/tool_input field the guard reads.
const TOOL: Record<string, { name: string; field: string }> = {
  shell: { name: "Bash", field: "command" },
  read: { name: "Read", field: "file_path" },
  grep: { name: "Grep", field: "path" },
}

// OpenCode tool id -> the Claude PreToolUse tool_name/tool_input the guard reads.
// A file write/edit only exposes an `edit` permission action with the path, not the
// body, so guard-key-literals runs on the tool hook instead: event.input there holds
// the whole content/newString, and throwing from execute.before aborts the call.
const EDIT_TOOL: Record<string, { name: string; input: (i: any) => Record<string, unknown> }> = {
  write: { name: "Write", input: (i) => ({ content: i.content, file_path: i.path }) },
  edit: { name: "Edit", input: (i) => ({ new_string: i.newString, file_path: i.path }) },
}

// Which guard sees which permission action. guard-key-literals' Edit/Write coverage
// is wired separately below, on the tool hook.
const GUARDS: Array<{ script: string; actions: string[] }> = [
  { script: "guard-secrets.py", actions: ["shell", "read", "grep"] },
  { script: "guard-delete-outside.py", actions: ["shell"] },
  { script: "guard-worktree-path.py", actions: ["shell"] },
  { script: "guard-protected-push.py", actions: ["shell"] },
  { script: "guard-key-literals.py", actions: ["shell"] },
]

export default Plugin.define({
  id: "super-board.guards",
  async setup(ctx) {
    const dir = ctx.location.directory
    const hooks = join(dir, ".claude", "hooks")

    // Run one guard with a Claude hook payload; return its deny reason, if any.
    const guardDeny = (script: string, payload: object): string | undefined => {
      const res = spawnSync("python3", [join(hooks, script)], {
        input: JSON.stringify(payload),
        env: { ...process.env, CLAUDE_PROJECT_DIR: dir },
        encoding: "utf8",
      })
      const out = (res.stdout ?? "").trim()
      if (!out) return undefined
      try {
        const d = JSON.parse(out)?.hookSpecificOutput
        return d?.permissionDecision === "deny" ? d.permissionDecisionReason : undefined
      } catch {
        return undefined // a guard that printed something unparseable must not block
      }
    }

    const denyReason = (script: string, action: string, resources: readonly string[]): string | undefined => {
      const tool = TOOL[action]
      if (!tool) return undefined
      return guardDeny(script, {
        hook_event_name: "PreToolUse",
        tool_name: tool.name,
        tool_input: { [tool.field]: resources.join(" ") },
        cwd: dir,
      })
    }

    await ctx.permission.hook("evaluate", (event) => {
      for (const guard of GUARDS) {
        if (!guard.actions.includes(event.action)) continue
        const reason = denyReason(guard.script, event.action, event.resources)
        if (reason) {
          event.effect = "deny"
          event.message = reason
          return
        }
      }
    })

    // guard-key-literals on file writes/edits, before the body reaches disk.
    await ctx.tool.hook("execute.before", (event) => {
      const tool = EDIT_TOOL[event.tool]
      if (!tool) return
      const reason = guardDeny("guard-key-literals.py", {
        hook_event_name: "PreToolUse",
        tool_name: tool.name,
        tool_input: tool.input(event.input),
        cwd: dir,
      })
      if (reason) throw new Error(reason)
    })

    // cleanup-wt.py --auto is Claude Code's SessionStart hook. Run it once, when the
    // first primary session for this project starts; fire-and-forget so its fetch
    // never delays startup. The server event stream is global, so match the project
    // to avoid cleaning some other checkout's worktrees.
    const controller = new AbortController()
    let cleaned = false
    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          if (cleaned || event.type !== "session.created") continue
          const data = event.data as { projectID?: string; parentID?: string }
          if (data.parentID || data.projectID !== ctx.location.project.id) continue
          cleaned = true
          spawn("python3", [join(hooks, "cleanup-wt.py"), "--auto", "--fetch"], {
            cwd: dir,
            env: { ...process.env, CLAUDE_PROJECT_DIR: dir },
            stdio: "ignore",
          }).unref()
        }
      } catch {
        /* aborted on plugin unload */
      }
    })()

    return () => controller.abort()
  },
})
