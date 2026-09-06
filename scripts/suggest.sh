#!/usr/bin/env bash
# Google Autocomplete suggestions. Usage: scripts/suggest.sh <lang> <COUNTRY> "<query>"  → one suggestion per line
set -euo pipefail
lang=$1; country=$2; q=$3
curl -sS --max-time 15 -A 'Mozilla/5.0' \
  "https://suggestqueries.google.com/complete/search?client=firefox&hl=${lang}&gl=${country}&q=$(node -pe 'encodeURIComponent(process.argv[1])' "$q")" \
  | node -e 'const a=JSON.parse(require("fs").readFileSync(0,"utf8")); (a[1]||[]).forEach(s=>console.log(s))'
