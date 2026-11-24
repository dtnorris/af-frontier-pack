# Integration Notes — verified AdventureFinder interfaces

The v0.1 live-integration pass verified the initial repo's three deliberately open seams against the current AdventureFinder repositories. Two are now implemented directly. The third remains intentionally unresolved because the project does not yet publish a consolidated current-state authority for it.

## 1. Canonical project-state manifest — integrated

The canonical moving catalog authority is:

```text
af-xlsx-data-sources/PROJECT_STATE.yml
```

relative to an explicitly configured `AF_PROJECT_ROOT`. Fully explicit selections
need no project root; see [selection and path semantics](../README.md#project-root).

Its schema is:

```text
adventurefinder-project-state/v0.2
```

and `catalog_head` contains:

```yaml
catalog_head:
  version: "X.Y.Z"
  filename: 5e_Adventure_Master_Catalog_X.Y.Z.xlsx
  sha256: ...
  bytes: ...
```

When `--amc` / `AF_FRONTIER_AMC` is not supplied, `af-frontier build` validates all three project-state roles, resolves `catalog_head`, and verifies the declared filename/version, byte size, and SHA-256. It never derives canonicality from filename ordering.

Explicit AMC selection remains a deliberate override for historical/frozen work.

## 2. Source registry and page mapping — integrated

The production source-mapping authority is:

```text
af-source-md-data/source_registry.yml
```

with schema:

```text
adventurefinder-source-registry/v0.1
```

This is the same contract consumed by `af-cli-scoring-utility`.

Supported explicit mappings are:

```yaml
Source Book:
  file: Canonical_Source_LLM_Edition.md
  page_marker_offset: "+3"   # optional; default +0
```

or segmented mappings:

```yaml
Source Book:
  segments:
    - start_page: 22
      end_page: 102
      file: Part_One_LLM_Edition.md
    - start_page: 104
      end_page: 175
      file: Part_Two_LLM_Edition.md
```

Segment selection uses the AMC canonical start/end page range and requires it to be fully contained by exactly one segment. Configured missing files, malformed mappings, invalid offsets, gaps, and ambiguity fail closed.

For sources without an explicit registry entry, v0.1 mirrors the scorer's deterministic normalized-filename fallback. A unique match is permitted and carries `SOURCE_RESOLVED_BY_FILENAME`; zero matches remain explicitly unresolved; multiple matches fail closed.

Source text extraction also mirrors the scorer's default contract:

1. if any `Printed Page` markers exist, use those;
2. otherwise use `PDF Page` / `PAGE:` markers;
3. add the mapping's signed `page_marker_offset` to the AMC start/end pages;
4. require exact boundary markers;
5. emit through the end of the requested end page (up to the next page marker).

`af-frontier-pack` intentionally does not enable the scorer's optional boundary-clamp or full-source fallback behavior.

## 3. Canonical parentage / nesting — intentionally null in v0.1

`af-data-pipeline`'s frozen boundary contract does preserve authoritative parent edges for newly ingested records using `parent_key` / `parent_adventure_id`, and freeze-to-AMC apply reports preserve a resolved parent Adventure ID.

However, the current AMC does not contain a parentage column and there is not yet a verified consolidated current-state parentage artifact spanning the whole catalog.

Therefore v0.1 continues to emit:

```json
"parentage": null
```

for every adventure.

It deliberately does **not** reconstruct parentage from historical audit reports, page containment, title similarity, source order, or any other heuristic. If AdventureFinder later publishes a consolidated canonical parentage authority, that can be consumed without changing this principle.

## Principle

`af-frontier-pack` consumes explicit current authorities; it does not create missing AdventureFinder truth. Fail closed on ambiguity, preserve unresolved state explicitly, and keep generated frontier artifacts disposable.
