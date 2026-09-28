# searxng-research-harness

A keyless-first, quota-resilient web-search stack for autonomous agents, skills, and
scripts. One command — `websearch` — fans a query across up to **10 providers** in
priority order and fails over automatically when one hits its quota, so no single
provider's monthly cap ever blocks the work. The default first hop is a **self-hosted
SearXNG** running as a plain Python venv (no Docker, no container runtime).

Two providers need no key at all: **SearXNG** (self-hosted, unmetered meta-search over
Google + Brave + DuckDuckGo) and **Marginalia** (independent small-web crawler). The
metered lanes are ordered by recurring free allowance, largest first, so small caps are
spent last.

## Why

Skills, hooks, and cron jobs can't call an interactive search tool — they need a shell
command that returns structured JSON. `websearch` is that command. When a provider
returns HTTP 402 (out of credits), 429/432 (rate/quota limited), or a transient error,
it transparently moves to the next. Piped output is JSON; interactive output is
human-readable. Typed exit codes: `0` results, `2` usage error, `3` all providers
exhausted, `4` no usable keys.

## Cooldown

A provider that answers 402, 429, or 432 (quota exhausted) is moved to the end of
the order for 15 minutes, recorded in `~/.cache/websearch/cooldown.json`. It is still
tried as a last resort, so a cooldown never turns into a false "all providers
failed". `-p`/`--order` ignore it; `--no-cooldown` skips it for one run;
`WEBSEARCH_COOLDOWN_MIN=0` turns it off. `websearch keys` shows what is cooling down.

## Provider order

```
searxng → linkup → parallel → youcom → tavily → brave → jina → exa → tinyfish → marginalia
```

Unmetered SearXNG first (absorbs volume); then by recurring free allowance, largest
first; independent indexes (TinyFish, Marginalia) held for deliberate second-source use.
A provider with no key is skipped, so an unkeyed entry is simply inert.

## Requirements

- **Node 18+** for `websearch` (uses built-in `fetch`, zero dependencies).
- **Python 3.11–3.13** for the self-hosted SearXNG (optional but recommended — it's the
  keyless default first hop). Newer interpreters (3.14+) may lack wheels for SearXNG's
  C dependencies; the installer prefers 3.13 → 3.12 → 3.11.

## Install

```sh
# 1. put the CLI on PATH
ln -s "$PWD/websearch" ~/.local/bin/websearch      # or copy it anywhere on PATH

# 2. configure keys (all optional; SearXNG + Marginalia need none)
mkdir -p ~/.config/websearch
cp keys.json.example ~/.config/websearch/keys.json  # then fill in what you have
#    …or add one at a time (hidden prompt, live-verified):
./add-key.sh tavily

# 3. (recommended) self-host SearXNG natively — no container
./searxng/build-native-searxng.sh
```

`websearch` reads keys from `~/.config/websearch/keys.json` or the environment.
`keys.json` is git-ignored — never commit real keys.

## Self-hosted SearXNG (native, no container)

`searxng/build-native-searxng.sh` installs SearXNG into `~/tools/searxng-native/`
(a venv + a shallow git checkout, ~140 MB on disk, ~70–120 MB resident) with the JSON API enabled and a
**fixed** bind on `127.0.0.1:8888`. Because the address is fixed, `SEARXNG_URL` never
rots — unlike a container whose IP can change on every restart.

Run it directly:

```sh
SEARXNG_SETTINGS_PATH=~/tools/searxng-native/settings.yml \
  ~/tools/searxng-native/venv/bin/python -m searx.webapp
```

Keep it running (macOS): edit `searxng/com.example.searxng-native.plist.template`,
replace `__HOME__` with your home dir, drop it in `~/Library/LaunchAgents/`, then:

```sh
sed "s|__HOME__|$HOME|g" searxng/com.example.searxng-native.plist.template \
  > ~/Library/LaunchAgents/com.example.searxng-native.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.searxng-native.plist
# force a restart any time:
launchctl kickstart -k gui/$(id -u)/com.example.searxng-native
```

`RunAtLoad` + `KeepAlive` start it at login and restart it on crash. (Linux users: run
the same venv under a systemd user service.)

**One hard requirement:** `settings.yml` must keep `search.formats: [html, json]` or the
JSON API returns nothing — public SearXNG instances disable JSON, which is why you
self-host.

## Quick start

```sh
websearch "latest claude opus pricing" -n 5      # human-readable in a terminal
websearch "va disability rating" --json -n 3     # JSON when piped or with --json
websearch keys                                   # which providers are configured + links
websearch "topic" -p brave --json                # force one provider (independent index)
```

⚠️ `websearch` prints human progress lines to stdout **before** the JSON, so when piping
to `jq`/`python`, strip to the first `{`:

```sh
websearch "q" --json -n 5 2>/dev/null | sed -n '/^{/,$p' | jq .
```

## Files

| Path | What |
|---|---|
| `websearch` | the CLI (Node, zero deps) |
| `add-key.sh` | add/replace one provider key (hidden prompt, live-verified) |
| `keys.json.example` | template for `~/.config/websearch/keys.json` |
| `searxng/build-native-searxng.sh` | install native SearXNG (venv, no container) |
| `searxng/settings.yml.template` | reference SearXNG config (JSON API on) |
| `searxng/com.example.searxng-native.plist.template` | macOS LaunchAgent template |

## License

MIT — see [LICENSE](LICENSE).
