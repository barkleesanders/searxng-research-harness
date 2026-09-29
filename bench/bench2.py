#!/usr/bin/env python3
"""websearch provider benchmark v2 — 60 queries in 5 categories, all providers.

nav / smallweb / code : MRR@10 of the first result on an expected domain (official page).
facts                 : MRR@5 of the first result whose title+snippet contains the known answer.
fresh                 : share of top-5 results carrying a date within FRESH_DAYS of the run
                        (published field, or a date in the url/title/snippet). Approximate.
Also: answer rate, error kinds, latency p50/p90, and URL overlap between providers
(low overlap = a more independent second source).
Usage: bench2.py [provider,provider,...]"""
import concurrent.futures as cf, datetime as dt, json, re, statistics, subprocess, sys, time
from pathlib import Path
from urllib.parse import urlparse

HERE = Path(__file__).parent
WS = str(HERE.parent / "websearch")
ALL = "searxng,linkup,parallel,youcom,tavily,brave,jina,exa,tinyfish,marginalia".split(",")
PROV = sys.argv[1].split(",") if len(sys.argv) > 1 else ALL
SUITE = json.loads((HERE / "suite2.json").read_text())
SPACING = {"brave": 1.1, "tinyfish": 2.1}  # stay under per-second / per-minute limits
TODAY = dt.date.today()
FRESH_DAYS = 14
MONTHS = "jan feb mar apr may jun jul aug sep oct nov dec".split()

def norm(u):
    p = urlparse(u or "")
    return p.netloc.lower().removeprefix("www.") + p.path.lower().rstrip("/")

def dates_in(text):
    out = []
    for y, m, d in re.findall(r"(20\d\d)[-/](\d{1,2})[-/](\d{1,2})", text):
        out.append((int(y), int(m), int(d)))
    for mon, d, y in re.findall(r"\b(" + "|".join(MONTHS) + r")[a-z]*\.? (\d{1,2}),? (20\d\d)", text.lower()):
        out.append((int(y), MONTHS.index(mon) + 1, int(d)))
    for d, mon, y in re.findall(r"\b(\d{1,2}) (" + "|".join(MONTHS) + r")[a-z]* (20\d\d)", text.lower()):
        out.append((int(y), MONTHS.index(mon) + 1, int(d)))
    res = []
    for y, m, d in out:
        try: res.append(dt.date(y, m, d))
        except ValueError: pass
    if re.search(r"\b\d+ (hours?|minutes?|days?) ago\b", text.lower()): res.append(TODAY)
    return res

def is_fresh(r):
    text = " ".join(str(r.get(k) or "") for k in ("published", "url", "title", "snippet"))
    return any(0 <= (TODAY - d).days <= FRESH_DAYS for d in dates_in(text))

def search(p, q, n):
    t = time.time()
    r = subprocess.run([WS, q, "-p", p, "-n", str(n), "--json", "--quiet", "--timeout", "20000"],
                       capture_output=True, text=True)
    sec = time.time() - t
    out = r.stdout[r.stdout.find("{"):] if "{" in r.stdout else "{}"
    try: d = json.loads(out)
    except Exception: d = {}
    err = ""
    if r.returncode:
        a = (d.get("attempts") or [{}])[-1]
        err = f'{a.get("kind","?")} {a.get("status","")}'.strip()
    return r.returncode, sec, d.get("results", []), err

def bench(p):
    rows = []
    for cat, items in SUITE.items():
        for it in items:
            n = 5 if cat in ("facts", "fresh") else 10
            rc, sec, res, err = search(p, it["q"], n)
            row = {"cat": cat, "q": it["q"], "rc": rc, "sec": round(sec, 2), "n": len(res), "err": err,
                   "urls": [norm(x.get("url")) for x in res],
                   "snip": [((x.get("title") or "") + " | " + (x.get("snippet") or ""))[:400] for x in res]}
            if "expect" in it:
                row["rank"] = next((i + 1 for i, u in enumerate(row["urls"]) if any(e in u for e in it["expect"])), None)
            elif "a" in it:
                txt = [((x.get("title") or "") + " " + (x.get("snippet") or "")).lower() for x in res]
                row["rank"] = next((i + 1 for i, t in enumerate(txt) if any(a in t for a in it["a"])), None)
            else:
                row["fresh"] = sum(is_fresh(x) for x in res[:5]) / 5
            rows.append(row)
            time.sleep(SPACING.get(p, 0))
    return p, rows

with cf.ThreadPoolExecutor(len(PROV)) as ex:
    R = dict(ex.map(bench, PROV))
stamp = time.strftime("%Y-%m-%dT%H%M")
(HERE / f"v2-{stamp}.json").write_text(json.dumps(R, indent=1))

def mrr(rows): return sum(1 / r["rank"] for r in rows if r.get("rank")) / len(rows) if rows else 0
cats = list(SUITE)
summary = {}
for p, rows in R.items():
    ok = [r for r in rows if r["rc"] == 0]
    s = {c: round(mrr([r for r in rows if r["cat"] == c]), 3) for c in cats if c != "fresh"}
    fr = [r["fresh"] for r in rows if r["cat"] == "fresh"]
    s["fresh"] = round(sum(fr) / len(fr), 3) if fr else 0
    s["answered"] = f"{len(ok)}/{len(rows)}"
    lat = sorted(r["sec"] for r in ok)
    s["p50"] = round(statistics.median(lat), 2) if lat else None
    s["p90"] = round(lat[int(len(lat) * .9) - 1], 2) if len(lat) >= 10 else None
    s["errors"] = sorted({r["err"] for r in rows if r["err"]})
    s["quality"] = round(statistics.mean([s[c] for c in cats]), 3)
    summary[p] = s
# overlap: mean Jaccard of each provider's top-10 URL set vs every other answering provider
nav_like = [i for i, r in enumerate(next(iter(R.values()))) if r["cat"] in ("nav", "smallweb", "code")]
for p in R:
    js = []
    for q in R:
        if q == p: continue
        for i in nav_like:
            a, b = set(R[p][i]["urls"]), set(R[q][i]["urls"])
            if a and b: js.append(len(a & b) / len(a | b))
    summary[p]["overlap"] = round(statistics.mean(js), 3) if js else None
(HERE / f"v2-summary-{stamp}.json").write_text(json.dumps(summary, indent=1))
cols = cats + ["quality", "answered", "p50", "p90", "overlap"]
print(f"{'provider':11} " + " ".join(f"{c:>8}" for c in cols) + "  errors")
for p, s in sorted(summary.items(), key=lambda x: -x[1]["quality"]):
    print(f"{p:11} " + " ".join(f"{str(s[c]):>8}" for c in cols) + "  " + ",".join(s["errors"]))

# Feed the router: merge fresh scores into ~/.config/websearch/quality.json, which
# websearch reads to rank providers. A provider that answered under half the queries was
# down or throttled, not measured, so its previous scores are kept.
QFILE = Path.home() / ".config" / "websearch" / "quality.json"
try:
    qdoc = json.loads(QFILE.read_text())
except Exception:
    qdoc = {"providers": {}}
updated, kept = [], []
for p, s in summary.items():
    a, t = map(int, s["answered"].split("/"))
    if a >= t * 0.5:
        qdoc.setdefault("providers", {})[p] = {c: s[c] for c in cats}
        updated.append(p)
    else:
        kept.append(p)
qdoc["measured"] = stamp
QFILE.parent.mkdir(parents=True, exist_ok=True)
QFILE.write_text(json.dumps(qdoc, indent=1) + "\n")
print(f"\nquality.json: updated {','.join(updated) or '-'}; kept previous for {','.join(kept) or '-'}")
