# Larder

Recipe keeper: paste a TikTok, Instagram, Facebook or recipe-site link, or snap a cookbook page or handwritten card, and get a clean, searchable, cookable recipe. ("Larder" is a placeholder name.)

## Code graph (Graphify)

[Graphify](https://github.com/Graphify-Labs/graphify) maps the repo into a knowledge graph at `graphify-out/graph.json` (tree-sitter AST, local, no API key). Only `graph.json` is committed; the report and HTML are rebuilt locally. Coding agents pick up the rules in `AGENTS.md` and the skill in `.agents/skills/graphify/`.

```bash
uv tool install graphifyy                 # or: pipx install graphifyy
git config core.hooksPath .githooks       # pre-commit hook rebuilds and stages graph.json
PY="$(sed -n '1s/^#!//p' "$(command -v graphify)")"
git config merge.graphify.name "graphify graph.json union merge"
git config merge.graphify.driver "\"$PY\" -m graphify merge-driver %O %A %B"

graphify update .                         # refresh graph + GRAPH_REPORT.md + graph.html
graphify query "how does sync work?"      # also: graphify path A B, graphify explain X
```
