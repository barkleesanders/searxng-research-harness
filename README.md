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

## How the order is chosen

The order is not fixed. Each search:

1. **Guesses the intent** from the query — `fresh` (news, "latest", "today"), `code`
   (errors, `foo()`, "how to … in python"), `facts` ("what / who / when / how many"),
   otherwise `general`. Override with `--intent nav|facts|fresh|code|smallweb|general`.
2. **Ranks providers by measured quality for that intent** (table below), with a small
   bonus for unmetered providers so they win ties.
3. **Multiplies by a budget pace factor.** Every call is counted in
   `~/.cache/websearch/usage.json`. A metered provider that is ahead of its pro-rata
   share of this period's free allowance slides down; one that has used it all goes to the
   back. Monthly allowances reset on the 1st; one-time credits (You.com) are paced over a
   year. The unmetered providers (SearXNG, TinyFish, Marginalia) absorb the rest.
4. **Demotes anything in cooldown** (see below).

`websearch quota` shows use against each free allowance and pulls live balances where the
provider exposes one (Linkup, Tavily). `--static` (or `WEBSEARCH_ROUTING=static`) uses
the fixed order instead; `-p` / `--order` are always honored as given.

### Quality table (2026-09-28, 60 queries)

| Provider | Free allowance | nav | facts | fresh | smallweb | code | overall |
|---|---|---|---|---|---|---|---|
| Brave | ~1,000/mo | 0.88 | 0.73 | **0.80** | 0.78 | **1.00** | **0.84** |
| You.com | $100 one-time (~20k) | 0.91 | 0.65 | **0.80** | 0.78 | **1.00** | 0.83 |
| Exa | ~830/mo | 0.97 | 0.66 | **0.80** | **0.88** | 0.83 | 0.83 |
| TinyFish | unmetered (30/min) | 0.96 | 0.88 | 0.20 | 0.85 | **1.00** | 0.78 |
| SearXNG | unmetered (self-hosted) | 0.95 | 0.80 | 0.25 | **0.88** | 0.84 | 0.74 |
| Parallel | ~5,000/mo | **1.00** | 0.78 | 0.10 | 0.81 | 0.88 | 0.71 |
| Tavily | 1,000/mo | 0.64 | **1.00** | 0.33 | 0.38 | 0.52 | 0.58 |
| Linkup | ~4,000/mo | 0.20 | 0.79 | 0.23 | 0.20 | 0.40 | 0.36 |
| Jina | one-time, empty | — | — | — | — | — | 402 |
| Marginalia | shared public key | — | — | — | — | — | 429 daily limit |

nav/smallweb/code = rank of the official page (1.0 = always first); facts = the known
answer appears in the top snippet; fresh = share of top-5 results dated in the last 14
days. Re-measure with `bench/bench2.py` — it rewrites `~/.config/websearch/quality.json`,
which the router reads, so the order follows the latest numbers.

## Cooldown

A provider that answers 402, 429, or 432 (quota exhausted) is moved to the end of
the order for 15 minutes, recorded in `~/.cache/websearch/cooldown.json`. It is still
tried as a last resort, so a cooldown never turns into a false "all providers
failed". `-p`/`--order` ignore it; `--no-cooldown` skips it for one run;
`WEBSEARCH_COOLDOWN_MIN=0` turns it off. `websearch keys` shows what is cooling down.

## SearXNG load spreading

SearXNG ranks by how many engines agree, so a normal search goes to every enabled
engine. Upstream engines throttle a single IP quickly, though: 16 fast searches
were enough to get Google CAPTCHA'd for an hour. So once more than 8 searches have
run in the last minute (`SEARXNG_BURST`), each search goes to only 4 engines
(`SEARXNG_FANOUT`) in rotation. Engines the instance reports as throttled are
skipped until they recover, and if too few results come back the next 4 are tried.
State lives in `~/.cache/websearch/searxng.json`.

Measured 2026-09-28, same conditions:

| Mode | Quality | Empty in a 64-search burst |
|---|---|---|
| All engines per search | 0.689 | 0 |
| 8 engines in rotation | 0.662 | — |
| 4 engines in rotation | 0.517 | 0 |

`SEARXNG_FANOUT=0` always uses every engine; `SEARXNG_BURST=0` always rotates.

## Fallback order (`--static`, and tie-breaker)

```
searxng → linkup → parallel → youcom → tavily → brave → jina → exa → tinyfish → marginalia
```

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
| `bench/bench2.py`, `bench/suite2.json` | 60-query provider benchmark; rewrites `~/.config/websearch/quality.json` |

## License

MIT — see [LICENSE](LICENSE).
