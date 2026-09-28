#!/usr/bin/env bash
# add-key — paste an API key for a websearch provider; it is stored and VERIFIED live.
#
#   ~/tools/websearch/add-key.sh linkup
#   ~/tools/websearch/add-key.sh parallel
#   ~/tools/websearch/add-key.sh jina
#
# Reads the key from a hidden prompt (never a shell argument, so it stays out of
# your shell history and out of `ps`). Writes it to ~/.config/websearch/keys.json,
# then runs a real search through that provider and reports the outcome.
#
# Exit: 0 = stored AND verified working  ·  1 = stored but the provider rejected it
#       2 = usage error / nothing written
set -uo pipefail

KEYS="$HOME/.config/websearch/keys.json"
WS="$HOME/tools/websearch/websearch"

# macOS ships bash 3.2, which has NO associative arrays (`declare -A` is a syntax
# error there). A case statement is the portable equivalent — do not "modernize" this.
provider_var() {
  case "$1" in
    linkup)   echo LINKUP_API_KEY ;;
    parallel) echo PARALLEL_API_KEY ;;
    youcom)   echo YDC_API_KEY ;;
    jina)     echo JINA_API_KEY ;;
    tavily)   echo TAVILY_API_KEY ;;
    brave)    echo BRAVE_API_KEY ;;
    exa)      echo EXA_API_KEY ;;
    tinyfish) echo TINYFISH_API_KEY ;;
    searxng)  echo SEARXNG_URL ;;
    *)        echo "" ;;
  esac
}
PROVIDERS="linkup parallel youcom jina tavily brave exa tinyfish searxng"

P="${1:-}"
VAR="$(provider_var "$P")"
if [ -z "$P" ] || [ -z "$VAR" ]; then
  echo "usage: add-key.sh <provider>" >&2
  echo "providers: $PROVIDERS" >&2
  exit 2
fi

printf 'Paste the %s value for %s (input hidden), then Enter:\n> ' "$VAR" "$P" >&2
read -rs KEY
echo >&2
KEY="${KEY#"${KEY%%[![:space:]]*}"}"   # trim leading space
KEY="${KEY%"${KEY##*[![:space:]]}"}"   # trim trailing space
[ -n "$KEY" ] || { echo "empty input — nothing written." >&2; exit 2; }

mkdir -p "$(dirname "$KEYS")"
[ -f "$KEYS" ] || echo '{}' > "$KEYS"
cp "$KEYS" "$KEYS.bak.$(date -u +%Y%m%dT%H%M%SZ)" 2>/dev/null

KEYS="$KEYS" VAR="$VAR" KEY="$KEY" python3 - <<'PY'
import json, os
p, var, key = os.environ['KEYS'], os.environ['VAR'], os.environ['KEY']
d = json.load(open(p))
d[var] = key
json.dump(d, open(p, 'w'), indent=2)
print(f"stored {var} ({len(key)} chars) in {p}")
PY
chmod 600 "$KEYS"

echo "verifying against the live API…" >&2
OUT=$("$WS" "site reliability engineering" -p "$P" -n 2 --json 2>&1)
RC=$?
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q '"count": *[1-9]'; then
  N=$(printf '%s' "$OUT" | grep -o '"count": *[0-9]*' | head -1 | grep -o '[0-9]*')
  echo "✅ $P VERIFIED — returned $N result(s). It is now live in the stack."
  exit 0
fi

# Stored, but the provider said no. Surface the provider's own words.
echo "⚠️  $P key stored but the provider REJECTED it:" >&2
printf '%s\n' "$OUT" | grep -o '"status": *[0-9]*\|"message": *"[^"]*"' | head -3 >&2
echo "   401/403 = wrong or not-yet-active key · 402/429 = no credit · check the dashboard." >&2
exit 1
