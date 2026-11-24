# af-frontier-pack v0.1 — Product Specification

## Purpose

Deterministically package and expose AdventureFinder's canonical knowledge so a frontier model can reason efficiently across David's TTRPG adventure library.

> Given explicit authoritative AdventureFinder artifacts, assemble and expose the compact structured context and bounded source evidence a frontier model needs to explore, compare, rediscover, and reason about the library.

## Inputs

- Exact AMC workbook, or authoritative `catalog_head` resolution.
- `af-source-md-data/source_registry.yml` (`adventurefinder-source-registry/v0.1`) by default, or an explicit compatible registry.
- Private canonical Markdown corpus root.
- Exact current AFAO authority, resolved deterministically and required for every build.
- `af-xlsx-data-sources/PROJECT_STATE.yml` (`adventurefinder-project-state/v0.2`) for default `catalog_head` resolution.

A project root is optional: fully explicit state/catalog, ontology, registry and
corpus selections need none. Relative configured authority paths and the default
corpus require an existing, explicitly selected `AF_PROJECT_ROOT`. Missing/blank
means unconfigured, with no cwd/home discovery. Resolve defaults after options
and only when needed; invalid selected inputs fail without another-library
fallback. Explicit paths remain cwd-relative; manifest filenames and registry
mappings retain their owner-relative semantics. Existing pack reads need only
the selected output, independent of build roots. See [README](../README.md#project-root).

## Outputs

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

`output/` is project-wide generated state and must be gitignored.

`CURRENT` is the sole publication commit point. It identifies one complete
generation and its manifest SHA-256; the manifest binds both JSONL artifact
hashes. Readers bind once and verify all artifacts before exposing data.
Prepublication validation failures preserve the selected generation, and
published generations are retained for existing readers. Legacy flat roots
require an explicit rebuild. See [README output](../README.md#output) for
migration, file-consumer compatibility, and safe reclamation responsibilities.

## Commands

1. `build` — build the compact frontier pack.
2. `doctor` — validate pack integrity and source resolution.
3. `show` — inspect one Adventure ID.
4. `select` — deterministic AND-ed scalar filtering.
5. `source` — resolve an Adventure ID to canonical source evidence.
6. `bundle` — create a task-specific Markdown/JSON handoff, optionally with source evidence.

## AMC resolution

Selection order is `--amc`, `AF_FRONTIER_AMC`, `--state`, then configured state manifests. The first two select an explicit frozen artifact without establishing acceptance. Otherwise validate the complete three-role v0.2 state and resolve `catalog_head` from the authoritative project-state manifest, verify its version/filename/byte-size/SHA-256 declaration, and announce the exact selection. Never select a catalog because its filename appears numerically largest.

## AFAO resolution

Select the pinned public identity with `--public-afao PATH`, or deliberate historical input with `--afao PATH`. Supplying both is an error. Otherwise resolve the exact `afao` contract from `config/authority.yml`, relative to `AF_PROJECT_ROOT` unless absolute. The default selects the public `AdventureFinder_Analysis_Ontology_AFAO_v1.6.1.md` at source revision `394a44c2c2052ce2eeb6d28cd7647ad8a50acfcf` of `dtnorris/af-specification-md`.

Public selection verifies basename, declared version and independently pinned digest/size both at resolution and builder consumption. Only AFAO is required; missing or mismatched input fails before publication without private fallback. Historical explicit inputs retain their version detection and recorded-byte behavior. Every manifest records AFAO filename, path, version, SHA-256 and byte size; public selections add source repository/revision/relative path. See [README](../README.md#afao-resolution) for the exact identity and compatibility contract. AFAO 1.6.1 retains its Candidate status; consumption does not establish acceptance or qualification.

AFAO authority is explicit and pinned. `af-frontier` must not discover ontology authority by sorting filenames or selecting a numerically newer version.

## Source resolution

Mirror AdventureFinder's production source contract: exact registry mappings first (including segmented mappings and signed `page_marker_offset`), then deterministic normalized-filename fallback when no explicit mapping exists. For extraction, prefer `Printed Page` markers when present; otherwise use `PDF Page` / `PAGE:` markers. Exact start/end markers are required.

An explicit private [reviewed source declaration](../README.md#reviewed-two-volume-source-references) can retain two verified file references for one catalog entry with no single containing segment. The entry keeps its full catalog span and carries an excerpt limitation. Each reference records registry bounds, which can leave pages of that span unmapped. Exact excerpts and source-bearing bundles refuse the entry.

Canonical parentage remains `null` in v0.1 because current parent edges are preserved in ingestion provenance but are not yet exposed as one consolidated current-state catalog authority.

## Critical null rule

`null` means AdventureFinder currently provides no assessed value for that field. It does not mean zero, 1, low, false, irrelevant, or undesirable.

## Copyright boundary

The repo may contain code, schemas, tests, safe fixtures, and generated catalog metadata. It must not permanently contain David's copyrighted Markdown corpus. Source-bearing bundles are ephemeral local output.

## Frontier reasoning contract

A frontier model should distinguish, where useful:

- **catalog-measured** claims;
- **source-grounded** interpretation;
- **frontier judgment**.

Unsupported qualitative questions remain legitimate frontier-layer questions. When structured data is insufficient, inspect bounded source evidence rather than inventing ontology mappings.

## Non-goals

No embeddings, vector search, vector database, SQLite just for retrieval, hosted infrastructure, API, MCP server, web UI, LLM provider integration, automatic recommendations, AFPS replacement, AFMRS replacement, generated summaries/tags, automatic ontology expansion, or general RAG framework.

## Done condition

```text
explicit AMC / authoritative catalog_head
            ↓
      af-frontier build
            ↓
 deterministic compact pack
            ↓
      af-frontier doctor
            ↓
   whole-library reasoning
            ↓
 candidate Adventure IDs
            ↓
 af-frontier bundle/source
            ↓
 selective primary evidence
            ↓
 frontier-model comparison,
 discovery, and judgment
```
