# af-frontier-pack v0.1 — Product Specification

## Purpose

Deterministically package and expose AdventureFinder's canonical knowledge so a frontier model can reason efficiently across David's TTRPG adventure library.

> Given explicit authoritative AdventureFinder artifacts, assemble and expose the compact structured context and bounded source evidence a frontier model needs to explore, compare, rediscover, and reason about the library.

## Inputs

- Exact AMC workbook, or authoritative `catalog_head` resolution.
- `md-for-llm-book-content/source_registry.yml` (`adventurefinder-source-registry/v0.1`) by default, or an explicit compatible registry.
- Private canonical Markdown corpus root.
- Exact current AFAO authority, resolved deterministically and required for every build.
- `af-xlsx-data-sources/PROJECT_STATE.yml` (`adventurefinder-project-state/v0.2`) for default `catalog_head` resolution.

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

Explicit `--amc` wins. Otherwise resolve `catalog_head` from the authoritative project-state manifest, verify its version/filename/byte-size/SHA-256 declaration, and announce the exact selection. Never select a catalog because its filename appears numerically largest.

## AFAO resolution

Explicit `--afao` wins. Otherwise resolve the exact `afao` contract from `config/authority.yml`, relative to `AF_PROJECT_ROOT` unless absolute. The current production contract is `md-specification-files/AdventureFinder_Analysis_Ontology_v1.6.1.md`, version `1.6.1`, matching the production scorer.

The resolver verifies configured filename/version consistency and the file's `## Version` declaration. Missing or mismatched authority fails closed. Every generated manifest records AFAO filename, path, version, SHA-256, and byte size; `inputs.afao` is not optional.

AFAO authority is explicit and pinned. `af-frontier` must not discover ontology authority by sorting filenames or selecting a numerically newer version.

## Source resolution

Mirror AdventureFinder's production source contract: exact registry mappings first (including segmented mappings and signed `page_marker_offset`), then deterministic normalized-filename fallback when no explicit mapping exists. For extraction, prefer `Printed Page` markers when present; otherwise use `PDF Page` / `PAGE:` markers. Exact start/end markers are required.

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
