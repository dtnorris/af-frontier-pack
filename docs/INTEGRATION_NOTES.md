# Integration Notes — items intentionally not guessed in the initial repo

This initial repository implements the v0.1 product contract and a runnable safe fixture. Three live AdventureFinder interfaces still need to be verified against the real repositories before treating the tool as production-ready.

## 1. Canonical project-state manifest

The CLI already supports named-role resolution of `catalog_head` from either:

```yaml
catalog_head:
  path: ...
```

or:

```yaml
roles:
  catalog_head:
    path: ...
```

`config/authority.yml` lists conservative candidate locations. A Work implementation pass should inspect the actual project-state authority and narrow these defaults to the real contract rather than adding filename-version guessing.

## 2. Source registry / source mappings

`SourceRegistry` currently accepts a conservative family of YAML mapping forms, including a top-level `sources:` wrapper and fields such as `path`, `markdown_path`, `source_path`, or `source`.

Before production use, inspect the authoritative AdventureFinder mapping structure and replace/generalize this adapter only as required by evidence from the live repository.

Source-text emission deliberately requires an explicit `page_basis` (`pdf` or `printed`) and optional `page_offset`. If the existing project already has a stronger page-mapping mechanism, integrate that mechanism instead of duplicating it here.

## 3. Canonical parentage / nesting

The v0.1 record reserves:

```json
"parentage": null
```

The starter does not infer parent/child relationships from page overlap, repeated titles, source order, or any other heuristic. A production pass should populate this only if an authoritative deterministic parentage source exists.

## Principle

These are integration seams, not invitations to invent new truth. Until verified, the repo should fail closed or emit explicit null/unresolved state.
