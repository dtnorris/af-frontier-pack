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
        +-- explicitly selected, pinned public AFAO (or historical input)
        +-- project-state authority
        |
        v
   af-frontier-pack
        |
        +-- output/frontier-pack/CURRENT
        +-- output/frontier-pack/generations/<generation>/manifest.json
        +-- output/frontier-pack/generations/<generation>/adventures.jsonl
        +-- output/frontier-pack/generations/<generation>/sources.jsonl
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

If both `--amc` and `AF_FRONTIER_AMC` are absent, the CLI resolves the authoritative `catalog_head` from a project-state manifest and **prints the exact resolved file before building**. It never treats the numerically largest filename as canonical.

Resolution order in v0.1:

1. `--amc PATH`
2. `AF_FRONTIER_AMC`
3. `--state PATH`, resolving role `catalog_head`
4. `config/authority.yml` → `state_manifests` (currently `af-xlsx-data-sources/PROJECT_STATE.yml`, relative to an explicitly configured `AF_PROJECT_ROOT`)

The production project-state contract is `adventurefinder-project-state/v0.2`. For a resolved `catalog_head`, `af-frontier` validates all three roles, including separate `matcher_authorized_baseline` and `production_dependency_floor` bindings, and verifies version/filename, byte size, and SHA-256 before building. Explicit `--amc` / `AF_FRONTIER_AMC` selects a frozen artifact; it does not establish library acceptance. If no authoritative head can be resolved, the command fails closed and asks for `--amc` or a project-state manifest.

### AFAO resolution

AFAO is a required build authority because `adventures.jsonl` exposes fields whose meanings come from the ontology. A normal build selects the configured public identity without scanning for newer filenames or falling back to private specifications.

Resolution order in v0.1:

1. `--public-afao PATH` for the pinned public identity, **or** `--afao PATH` for deliberate historical/frozen input
2. `config/authority.yml` → `afao` when neither explicit selector is supplied

The current configured contract is:

```text
af-specification-md/AdventureFinder_Analysis_Ontology_AFAO_v1.6.1.md
version: 1.6.1
source revision: 394a44c2c2052ce2eeb6d28cd7647ad8a50acfcf
sha256: dcfad224ab9517272504a508f935a804032d04a7c812ede10498921ce4585fa1
bytes: 339101
```

The source is [`dtnorris/af-specification-md`](https://github.com/dtnorris/af-specification-md/tree/394a44c2c2052ce2eeb6d28cd7647ad8a50acfcf), bound to its reviewed `documents.json` inventory. `AnalysisOntologyResolver::PUBLIC_AFAO` pins the expected identity independently of supplied bytes. The configured path is relative to `AF_PROJECT_ROOT` unless absolute; `--public-afao` selects an existing file at any explicit location with the exact basename, declared version, digest and size. Only the AFAO file is required, without a runtime Git/network lookup or the other seven documents. The recorded revision identifies the source of the pinned bytes; it does not attest the local checkout's HEAD.

Missing, incompatible or changed public inputs fail before replacing `CURRENT`. The builder rechecks the pin at consumption. No alias, private fallback or automatic adoption of a different revision is provided. AFAO 1.6.1 remains **Candidate**, pending targeted GM Preparation Burden 4/5 revalidation; selection does not establish method acceptance or model qualification.

`--afao` retains its existing explicit input behavior: require a declared version and record the supplied bytes without asserting the public pin. It overrides configured authority and remains usable for historical versions and legacy locations. Supplying both selectors is an error. Existing custom historical authority configurations retain their filename/version checks.

`manifest.json` records the resolved AFAO filename, absolute path, declared version, SHA-256 and byte size. Public selections additionally record `inputs.afao.public_specification` with repository, source revision and repository-relative path. Existing pack reads retain their behavior; `doctor` checks recorded input hashes without requiring a build-time project root.

### Project root

There is no implicit project root. With fully selected build inputs, leave
`AF_PROJECT_ROOT` unset. Missing or blank means unconfigured; Frontier Pack never
discovers a library from cwd, home, or a developer's personal directories.

Set `AF_PROJECT_ROOT` only when using relative paths from `config/authority.yml`
or the default corpus `md-for-llm-book-content` beneath that root:

```bash
export AF_PROJECT_ROOT=/path/to/existing/components
bin/af-frontier build
```

An existing installation can deliberately retain its legacy location, for example
`export AF_PROJECT_ROOT=/Users/davidnorris/code` if that directory contains the
configured sibling layout. This selects existing paths; it moves or initializes
nothing. Missing/invalid required roots fail with configuration guidance. An
unused root does not affect explicit inputs or existing pack reads.

Explicit CLI paths remain relative to the invoking cwd unless absolute. State
filenames are relative to their manifest; registry file mappings are relative to
the selected corpus. The registry defaults to `source_registry.yml` inside that
corpus. An invalid explicit operand fails without selecting another library.

`help`, `version` and existing pack commands require no build-time root.
`--output` wins over `AF_FRONTIER_OUTPUT`; otherwise output defaults beneath
this code checkout. Set `AF_FRONTIER_OUTPUT` for subsequent pack reads (or use
`doctor --root PATH`).

### Output

The canonical pack is written to:

```text
output/frontier-pack/
├── CURRENT
├── generations/
│   └── generation-<unique-id>/
│       ├── manifest.json
│       ├── adventures.jsonl
│       └── sources.jsonl
└── bundles/
```

Builds validate the input descriptors, catalog records, and source bindings with
the existing `doctor` rules before publication. Unresolved sources retain their
existing explicit unresolved status. Complete artifacts are written privately on
the same filesystem; one atomic replacement of `CURRENT` selects the generation.
Its manifest records SHA-256 hashes for both JSONL files, and `CURRENT` records
the manifest hash. Manifest and JSONL bytes remain deterministic across identical
builds; generation names and pointer bytes are intentionally unique.

`Pack.new(root: ...)` binds once and loads all three verified artifacts before
returning. Reuse that instance for related reads; `root` remains the output root,
and `artifact_root` identifies its selected generation. `Paths.manifest_path`,
`adventures_path`, and `sources_path` resolve the current verified generation.
Missing, malformed, or mismatched artifacts raise `IntegrityError` without a
fallback to another generation. CLI commands and source resolution use this same
reader. Authority files and source Markdown must remain stable during a build.

Legacy flat roots have no verifiable generation and require `build` before use.
A successful rebuild creates `CURRENT` without modifying the old flat files;
those files are ignored thereafter. External file consumers must resolve one
generation rather than reading the old flat paths.

An interruption before replacing `CURRENT` leaves the previous generation
selected; on the first build it leaves no usable pack. After replacement, the
new generation is committed even if the writer subsequently reports an error.
Previous generations remain usable by bound readers. Builds never delete
published generations or another writer's files; abandoned staging directories
can remain after abrupt process exit. Reclaim old output only when all readers
and writers have stopped. Atomic visibility assumes local filesystem rename
semantics; it does not promise persistence through power loss.

Every file-producing `bundle` command ends by printing its **absolute output path**. When stdout is reserved for machine-readable content, human status is written to stderr so Unix pipelines stay clean.

## Build

Build from a deliberately selected library without `AF_PROJECT_ROOT` or
`AF_FRONTIER_AMC`:

```bash
unset AF_PROJECT_ROOT AF_FRONTIER_AMC
export AF_FRONTIER_OUTPUT=/path/to/selected/frontier-pack
bin/af-frontier build \
  --state /path/to/selected/catalog/PROJECT_STATE.yml \
  --source-registry /path/to/selected/corpus/source_registry.yml \
  --corpus-root /path/to/selected/corpus \
  --public-afao /path/to/af-specification-md/AdventureFinder_Analysis_Ontology_AFAO_v1.6.1.md
bin/af-frontier doctor
bin/af-frontier show ADV-0001
```

Replace the example locators with existing inputs. For deliberate historical
ontology selection use `--afao /path/to/frozen/ONTOLOGY.md` instead of
`--public-afao`. For historical/frozen catalog work, replace `--state PATH` with
`--amc /path/to/5e_Adventure_Master_Catalog_X.Y.xlsx`; this is artifact selection,
not accepted-state resolution.

With `AF_PROJECT_ROOT` configured, `bin/af-frontier build` instead uses the
configured relative state and ontology authorities, the default corpus beneath
that root, and its `source_registry.yml`. Each explicit selector overrides only
its own default.

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
