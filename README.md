# af-frontier-pack

`af-frontier-pack` is AdventureFinder's deterministic consumption bridge for frontier-model reasoning.

It **does not recommend adventures** and **owns no canonical truth**. It consumes explicit authoritative AdventureFinder artifacts and produces a compact, disposable frontier pack plus small CLI utilities for inspecting, filtering, source-resolving, and bundling context for a frontier model.

## v0.1 product boundary

```text
canonical AdventureFinder artifacts
        |
        +-- AMC workbook
        +-- canonical source registry / mappings
        +-- private canonical Markdown corpus
        +-- pinned current AFAO ontology
        +-- project-state authority
        |
        v
   af-frontier-pack
        |
        +-- output/frontier-pack/manifest.json
        +-- output/frontier-pack/adventures.jsonl
        +-- output/frontier-pack/sources.jsonl
        +-- output/frontier-pack/bundles/*
        |
        v
 frontier-model reasoning
```

The project-wide `output/` directory is gitignored. Generated packs and bundles are disposable and reproducible from authoritative inputs.

## Commands

```bash
bin/af-frontier build
bin/af-frontier doctor
bin/af-frontier show ADV-0287
bin/af-frontier select --where 'GMPB<=2' --where 'CPA>=4'
bin/af-frontier source ADV-0287
bin/af-frontier bundle --ids ADV-0034,ADV-0287,ADV-0303
```

### Canonical AMC resolution

An explicit AMC always wins:

```bash
bin/af-frontier build --amc /path/to/5e_Adventure_Master_Catalog_X.Y.xlsx
```

If `--amc` is omitted, the CLI resolves the authoritative `catalog_head` from a project-state manifest and **prints the exact resolved file before building**. It never treats the numerically largest filename as canonical.

Resolution order in v0.1:

1. `--amc PATH`
2. `AF_FRONTIER_AMC`
3. `--state PATH`, resolving role `catalog_head`
4. `/Users/davidnorris/code/af-xlsx-data-sources/PROJECT_STATE.yml` (relative to `AF_PROJECT_ROOT`)

The production project-state contract is `adventurefinder-project-state/v0.2`. For a resolved `catalog_head`, `af-frontier` verifies the declared version/filename, byte size, and SHA-256 before building. If no authoritative head can be resolved, the command fails closed and asks for `--amc` or a project-state manifest.

### AFAO resolution

AFAO is a required build authority because `adventures.jsonl` exposes fields whose meanings come from the ontology. A normal build resolves the exact configured production contract rather than leaving `inputs.afao` null or scanning for the numerically newest ontology filename.

Resolution order in v0.1:

1. `--afao PATH`
2. `config/authority.yml` → `afao`

The current configured contract is:

```text
md-specification-files/AdventureFinder_Analysis_Ontology_v1.6.1.md
version: 1.6.1
```

The configured path is relative to `AF_PROJECT_ROOT` unless absolute. `af-frontier` verifies that the configured filename matches the configured version and that the file's `## Version` declaration matches as well. Missing or mismatched AFAO authority fails closed.

`manifest.json` records the resolved AFAO filename, absolute path, declared version, SHA-256, and byte size.

### Project root

The default AdventureFinder checkout root is:

```text
/Users/davidnorris/code
```

Override with:

```bash
export AF_PROJECT_ROOT=/another/path
```

### Output

The canonical pack is written to:

```text
output/frontier-pack/
├── manifest.json
├── adventures.jsonl
├── sources.jsonl
└── bundles/
```

Every file-producing `bundle` command ends by printing its **absolute output path**. When stdout is reserved for machine-readable content, human status is written to stderr so Unix pipelines stay clean.

## Build

Normal production build:

```bash
bin/af-frontier build
```

By default this resolves `catalog_head` from `af-xlsx-data-sources/PROJECT_STATE.yml`, resolves the pinned AFAO contract from `config/authority.yml`, uses `/Users/davidnorris/code/md-for-llm-book-content` as the corpus root, and reads `source_registry.yml` from that corpus root. These inputs remain explicitly overridable:

```bash
bin/af-frontier build \
  --amc /Users/davidnorris/code/af-xlsx-data-sources/5e_Adventure_Master_Catalog_X.Y.xlsx \
  --source-registry /Users/davidnorris/code/md-for-llm-book-content/source_registry.yml \
  --corpus-root /Users/davidnorris/code/md-for-llm-book-content \
  --afao /Users/davidnorris/code/md-specification-files/AdventureFinder_Analysis_Ontology_v1.6.1.md
```

The production source registry contract is `adventurefinder-source-registry/v0.1`. Explicit mappings may point to one Markdown file or to page-bounded segments. `page_marker_offset`, when present, must be an explicitly signed integer string such as `"+3"` or `"-4"`. If a source has no explicit registry entry, the same deterministic normalized-filename fallback used by `af-cli-scoring-utility` is available and is surfaced with a warning; ambiguity fails closed.

## Deterministic filtering

`select` is deliberately boring. v0.1 supports only repeated AND-ed comparisons:

```bash
bin/af-frontier select \
  --where 'GMPB<=2' \
  --where 'CPA>=4'
```

Operators:

```text
= != < <= > >=
```

No OR, fuzzy matching, preference scoring, natural-language parsing, or semantic ranking belongs here.

For composition:

```bash
bin/af-frontier select \
  --where 'GMPB<=2' \
  --where 'CPA>=4' \
  --ids-only \
| bin/af-frontier bundle --ids -
```

`select --ids-only` writes only Adventure IDs to stdout; pack authority/status goes to stderr.

## Source resolution

```bash
bin/af-frontier source ADV-0287
```

returns the deterministic locator. `--emit` follows the production AdventureFinder source contract: it uses `Printed Page` markers when a source contains them, otherwise falls back to `PDF Page` / `PAGE:` markers, and applies the registry's `page_marker_offset` before requiring exact start/end markers. Missing or ambiguous boundaries fail closed; there is no full-source fallback in `af-frontier-pack`.

## Bundle

```bash
bin/af-frontier bundle \
  --ids ADV-0034,ADV-0287,ADV-0303 \
  --format markdown
```

With source evidence:

```bash
bin/af-frontier bundle \
  --ids ADV-0034,ADV-0287,ADV-0303 \
  --with-source \
  --format markdown
```

Bundles are written beneath `output/frontier-pack/bundles/`. Source-bearing bundles are local ephemeral artifacts and should remain uncommitted.

## Invariants

- Zero canonical truth ownership.
- Same authoritative inputs + same generator version => same semantic pack.
- Explicit artifact selection or authoritative `catalog_head` resolution only.
- Every pack records a concrete AFAO authority; `inputs.afao` is never `null`.
- Never infer canonicality from filename version ordering.
- Missing assessment values remain `null`; missing never means low.
- No LLM calls for build/doctor/show/select/source/bundle.
- No hidden semantic proxies.
- Fail closed on identity/source ambiguity.
- Source prose is not copied into the canonical pack.
- Task bundles are convenience artifacts, not authorities.

## Explicit v0.1 non-goals

No embeddings, vector database, SQLite retrieval layer, hosted service, API, MCP server, web UI, LLM provider integration, recommendation engine, AFPS/AFMRS replacement, semantic similarity ranking, generated summaries/tags, ontology expansion, or permanent copied copyrighted corpus.

See [`docs/PRODUCT_SPEC.md`](docs/PRODUCT_SPEC.md) and [`docs/BENCHMARK.md`](docs/BENCHMARK.md).

## Development

```bash
bundle install
bundle exec rake
```

The test fixture includes a tiny `.xlsx`, production-schema source registry, and safe Markdown corpus so the core v0.1 flow can be exercised without copying any private AdventureFinder source content.
