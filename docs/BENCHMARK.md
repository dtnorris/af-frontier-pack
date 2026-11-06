# v0.1 Frontier Usefulness Benchmark

The pack exists to make these real library questions materially easier, more reliable, or more interesting.

1. What are eight adventures in my library worth rediscovering because they have unusually interesting measured combinations?
2. Which adventures are measured near-twins but radically different in premise, source, setting, or actual feel?
3. What are my strongest low-prep, high-agency adventures, and which of those actually sound most fun to run?
4. Find adventures that aren't extreme on any single dimension but have unusually distinctive overall profiles.
5. What unplayed adventures most strongly resemble things I've already played, and which ones deliberately break that pattern?
6. What have I probably overlooked because they come from books with many other cataloged adventures?
7. Find a handful of adventures that would give me dramatically different experiences while remaining similar in practical duration.
8. I want something short, beginner-friendly, and memorable. Which measured candidates fit the first two requirements, then which actually make the strongest first impression?
9. Which high-weirdness adventures are surprisingly approachable rather than demanding or punishing?
10. Which adventures combine high openness with relatively low GM improvisation demand? Is that combination actually rare in my library?
11. Show me interesting cases where high player agency does not come with high structural openness. What does that look like in the actual adventures?
12. Give me three adventures with almost the same measured play profile but completely different tones or fictional experiences.
13. Compare these four Adventure IDs using the catalog first, then inspect the source only where the scores fail to explain the difference.
14. What meaningful holes or underrepresented combinations exist in my current library—not in the ontology, but in the actual collection?
15. Surprise me with five things in my own library that I would not have thought to ask for, and explain exactly what in the artifact made them interesting.

## Evaluation prompts

For each question record:

- Could the model identify a defensible structured candidate set?
- Did it distinguish missing data from low scores?
- Did it know when catalog information was sufficient?
- Did it request/inspect source evidence only when useful?
- Did source inspection materially improve the answer?
- Did it make unsupported catalog claims?
- Was the result more useful or more fun than working directly from the raw AMC?

Do not collapse this into one aggregate score in v0.1. The purpose is to identify concrete failure modes.

## AMC 6.0 full-corpus build benchmark

AMC 6.0 is the first whole-Adventure-Catalog benchmark for the established
13-column production-scoring baseline. This is a deterministic artifact-health
benchmark, separate from the qualitative usefulness questions above.

Run it from the repository root with the authoritative AdventureFinder sibling
checkouts under an explicitly selected `AF_PROJECT_ROOT` (or pass
`--project-root PATH`; there is no implicit personal root):

```bash
AF_PROJECT_ROOT=/path/to/existing/components bin/benchmark-amc-6.0
```

The harness uses the exact frozen AMC 6.0 artifact identity (295,632 bytes,
SHA-256 `56e071a90c0e5adef82c19775a0f358cb93df647470eb64153f251475dba0920`)
and requires all of the following before reporting `PASS`:

- `PROJECT_STATE.yml` identifies AMC 6.0 as `catalog_head` with that exact hash and size;
- the pack builds twice in isolated temporary output roots and `doctor` passes on both builds;
- the pack contains exactly **879** adventures;
- all **11,427** cells in the established 13-column baseline are populated: Number of Sessions, Level Start, Level End, Combat, Exploration, Social Interaction, Investigation, Structural Openness, Seriousness, Darkness / Horror Intensity, GM Preparation Burden, Player Beginner Suitability, and GM Beginner Suitability;
- all 879 adventures resolve to canonical source Markdown;
- Level Start and Level End conform to frozen AFAO Levels v2.1: each endpoint is either a positive numeric level or the valid `Uncertain` assessment state, and numeric pairs satisfy `Level End >= Level Start`; and
- `manifest.json`, `adventures.jsonl`, and `sources.jsonl` are byte-identical across the two builds.

The benchmark writes the durable machine-readable record to:

```text
docs/benchmarks/amc-6.0-full-corpus.yml
```

The report records exact AMC/AFAO/source-registry identities, relevant repository
HEADs and dirty-state observations, full-corpus/source-resolution counts, 13-column
coverage, contract-valid uncertain-level Adventure IDs, build timings, generated-pack SHA-256 values, and every gate result. The
report is historical evidence, not moving catalog authority; `PROJECT_STATE.yml`
continues to own live catalog roles.
