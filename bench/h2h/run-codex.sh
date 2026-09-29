#!/bin/zsh
i=$1; q=$(python3 -c "import json;print(json.load(open('$2'))[$i]['q'])")
s=$(date +%s.%N)
timeout 240 codex --search exec --skip-git-repo-check -C "${TMPDIR:-/tmp}" "Use web search for: $q
Reply with ONLY: the top 5 result URLs you found, one per line, then a line 'ANSWER: <one sentence answer>'." > $3/codex-$i.txt 2>$3/codex-$i.err
echo "$(( $(date +%s.%N) - s ))" > $3/codex-$i.sec
