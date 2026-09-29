## Web search = the `websearch` CLI, not the built-in tool

For any web lookup, run `websearch "<query>" -n 8 --json 2>/dev/null` in the shell
and parse from the first `{` (progress lines precede the JSON). Use the built-in
`web_search` only if the CLI exits 3 (all providers exhausted) or 4 (no keys).
