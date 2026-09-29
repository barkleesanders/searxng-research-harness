#!/bin/bash
# PreToolUse(WebSearch): route web search through the `websearch` CLI instead.
# Measured 2026-09-28 on 20 benchmark queries (expected site / answer in top 5):
#   websearch CLI 20/20 at 0.6 s median; Claude WebSearch 16/20; Codex web_search
#   19/20 at 23 s and ~40k tokens per query.
# The first WebSearch for a query is denied with instructions. An identical retry
# in the same session is allowed, so agents without Bash still work.
# Off switch: CLAUDE_ALLOW_WEBSEARCH=1.
[ "${CLAUDE_ALLOW_WEBSEARCH:-0}" = "1" ] && exit 0
command -v websearch >/dev/null 2>&1 || [ -x "$HOME/tools/websearch/websearch" ] || exit 0
exec python3 -c '
import json, os, sys, hashlib
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
q = (d.get("tool_input") or {}).get("query", "")
if not q:
    sys.exit(0)
tmp = os.environ.get("TMPDIR", "/tmp")
mdir = os.path.join(tmp, "claude-websearch-redirect"); os.makedirs(mdir, exist_ok=True)
mark = os.path.join(mdir, (d.get("session_id") or "nosession") + ".txt")
h = hashlib.sha1(q.encode()).hexdigest()
seen = open(mark).read().split() if os.path.exists(mark) else []
if h in seen:
    sys.exit(0)  # retry of the same query: allow the built-in tool
open(mark, "a").write(h + "\n")
qs = q.replace("\x27", "")
reason = ("Use the websearch CLI via Bash instead (better top-5 results, ~0.6 s, free providers first):\n"
          f"  websearch \x27{qs}\x27 -n 8 --json 2>/dev/null\n"
          "Parse from the first { (progress lines precede the JSON). If you have no Bash tool, "
          "repeat this exact WebSearch call and it will be allowed.")
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
      "permissionDecision": "deny", "permissionDecisionReason": reason}}))
'
