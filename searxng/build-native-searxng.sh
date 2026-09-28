#!/usr/bin/env bash
# build-native-searxng.sh — install SearXNG as a plain Python venv (NO container).
#
# Produces ~/tools/searxng-native/{venv,searxng-src,settings.yml} bound to a
# FIXED 127.0.0.1:8888 with the JSON API enabled. ~140 MB on disk and ~70–120 MB
# resident, vs several GB of container disk plus a 1 GiB-default VM (the image
# itself is only ~96 MB compressed). Idempotent: re-running reuses an existing checkout/venv.
#
# After this, load the LaunchAgent (macOS) — see com.example.searxng-native.plist.template
# and the README — or run it directly:  ~/tools/searxng-native/venv/bin/python -m searx.webapp
set -uo pipefail
SRC="${SEARXNG_HOME:-$HOME/tools/searxng-native}"
LOG="$SRC/build.log"
mkdir -p "$SRC"; : > "$LOG"
say() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG"; }

# Pick a supported interpreter (SearXNG needs 3.11+). Prefer 3.13 > 3.12 > 3.11.
# Very new interpreters (e.g. 3.14) may lack wheels for lxml/cffi — avoid by default.
PY=""
for cand in python3.13 python3.12 python3.11; do
  p=$(command -v "$cand" 2>/dev/null) && { PY="$p"; break; }
done
[ -z "$PY" ] && { v=$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null); \
  case "$v" in 3.11|3.12|3.13) PY=$(command -v python3);; esac; }
[ -z "$PY" ] && { say "no python 3.11–3.13 found (SearXNG needs 3.11+); install one and retry. FAIL"; echo FAIL>>"$LOG"; exit 1; }
say "python: $($PY --version 2>&1) ($PY)"

if [ ! -d "$SRC/searxng-src/.git" ]; then
  say "cloning searxng (shallow)"
  git clone --depth 1 https://github.com/searxng/searxng "$SRC/searxng-src" >>"$LOG" 2>&1 \
    || { say "clone FAILED"; echo FAIL>>"$LOG"; exit 3; }
else
  say "source already present"
fi

if [ ! -x "$SRC/venv/bin/python" ]; then
  say "creating venv"; "$PY" -m venv "$SRC/venv" >>"$LOG" 2>&1 || { say "venv FAILED"; echo FAIL>>"$LOG"; exit 4; }
fi
# shellcheck disable=SC1091
. "$SRC/venv/bin/activate"
say "pip bootstrap"
pip install --no-cache-dir -U pip setuptools wheel pyyaml msgspec typing-extensions pybind11 >>"$LOG" 2>&1 \
  || { say "pip bootstrap FAILED"; echo FAIL>>"$LOG"; exit 5; }
say "pip install searxng (editable, pep517)"
( cd "$SRC/searxng-src" && pip install --no-cache-dir --use-pep517 --no-build-isolation -e . ) >>"$LOG" 2>&1 \
  || { say "searxng install FAILED"; echo FAIL>>"$LOG"; exit 6; }

# Slim settings: fixed localhost bind (no IP churn), JSON API ON. Fresh secret each build.
if [ ! -f "$SRC/settings.yml" ]; then
  SECRET=$(openssl rand -hex 32)
  cat > "$SRC/settings.yml" <<YML
use_default_settings: true
server:
  bind_address: "127.0.0.1"
  port: 8888
  secret_key: "${SECRET}"
  limiter: false
  image_proxy: false
search:
  formats:
    - html
    - json
YML
  say "wrote $SRC/settings.yml (127.0.0.1:8888, formats html+json, fresh secret)"
else
  say "settings.yml exists — left as-is (delete it to regenerate)"
fi

say "footprint: venv $(du -sh "$SRC/venv" 2>/dev/null | cut -f1), src $(du -sh "$SRC/searxng-src" 2>/dev/null | cut -f1)"
say "BUILD-OK — start with: SEARXNG_SETTINGS_PATH=$SRC/settings.yml $SRC/venv/bin/python -m searx.webapp"
echo DONE >> "$LOG"
