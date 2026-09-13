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
        +-- AFAO/version metadata
        +-- project-state authority where available
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
bin/af-frontier build --amc /path/to/5e_Adventure_Master_Catalog_5.7.2.xlsx
```

If `--amc` is omitted, the CLI resolves the authoritative `catalog_head` from a project-state manifest and **prints the exact resolved file before building**. It never treats the numerically largest filename as canonical.

Resolution order in v0.1:

1. `--amc PATH`
2. `AF_FRONTIER_AMC`
3. `--state PATH`, resolving role `catalog_head`
4. configured/default project-state manifest candidates containing an explicit `catalog_head` role

If no authoritative head can be resolved, the command fails closed and asks for `--amc` or a project-state manifest.

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

Typical explicit build:

```bash
bin/af-frontier build \
  --amc /Users/davidnorris/code/af-xlsx-data-sources/5e_Adventure_Master_Catalog_5.7.2.xlsx \
  --source-registry /Users/davidnorris/code/af-cli-scoring-utility/config/source_mappings.yml \
  --corpus-root /Users/davidnorris/code/md-for-llm-book-content \
  --afao /Users/davidnorris/code/md-specification-files/AdventureFinder_Analysis_Ontology_v1.6.md
```

The starter repository intentionally treats the exact live source-registry schema and the eventual project-state manifest location as integration seams. It supports a conservative family of common YAML mapping shapes and fails closed when a source cannot be resolved unambiguously.

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

returns the deterministic locator. `--emit` extracts source text only if the source registry provides an explicit page-marker contract (`page_basis` and optional `page_offset`). If that information is absent, v0.1 refuses to guess whether AMC pages correspond to PDF-page or printed-page markers.

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

The test fixture includes a tiny `.xlsx`, source registry, and Markdown corpus so the core v0.1 flow can be exercised without any private AdventureFinder repository.
