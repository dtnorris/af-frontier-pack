# af-frontier-pack v0.1 — Product Specification

## Purpose

Deterministically package and expose AdventureFinder's canonical knowledge so a frontier model can reason efficiently across David's TTRPG adventure library.

> Given explicit authoritative AdventureFinder artifacts, assemble and expose the compact structured context and bounded source evidence a frontier model needs to explore, compare, rediscover, and reason about the library.

## Inputs

- Exact AMC workbook, or authoritative `catalog_head` resolution.
- Source identity / locator registry.
- Private canonical Markdown corpus root.
- AFAO specification/version metadata when available.
- Project-state manifest when available.

## Outputs

```text
output/frontier-pack/
├── manifest.json
├── adventures.jsonl
├── sources.jsonl
└── bundles/
```

`output/` is project-wide generated state and must be gitignored.

## Commands

1. `build` — build the compact frontier pack.
2. `doctor` — validate pack integrity and source resolution.
3. `show` — inspect one Adventure ID.
4. `select` — deterministic AND-ed scalar filtering.
5. `source` — resolve an Adventure ID to canonical source evidence.
6. `bundle` — create a task-specific Markdown/JSON handoff, optionally with source evidence.

## AMC resolution

Explicit `--amc` wins. Otherwise resolve a named authoritative `catalog_head` and announce the exact selection. Never select a catalog because its filename appears numerically largest.

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
