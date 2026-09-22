# Forest generation

This document records the initial forest-only iteration. Current structure/container
placement, expanded tile palettes and tuning instructions are documented in
`World/Generation/GENERATION_SETTINGS.md`. The counts below are the earlier baseline,
not the current mixed-content map.

The active environment resource is `Resources/WorldGen/environment_generation_profile.tres`.

## Findings

- Only Biom1 and Biom2 trees were in the active profile. Oak, birch and maple scenes were absent.
- Tree candidate density was 0.02 / 0.015 per cell. Global clearance 1 plus entry spacing 1 reserved 5x5 cells per object.
- Equal-priority candidates were resolved by their IDs, giving earlier entry names first access to land.
- Scene position and generated ID were assigned after `add_child`, so `_ready` observed the wrong position/identity. Stone and puddle variants derive their appearance from position.
- The old visual coordinate XOR preserved even parity on this grid, making half of an even-sized texture list unreachable. Coordinate hashing now reaches all six stone variants; the contract test checks this on real instances.
- Standalone house, bunker and bandit spawners are disabled in `World/world_generation.tscn`. Village houses and scrap have separate pools under `Resources/Village`; they are not wilderness scatter entries.

## Current changes

- A deterministic smooth forest mask assigns 75% of available land to forest. Available land excludes existing occupancy reservations. This measures forest territory, not canopy pixels or trunk occupancy.
- Five tree scenes compete in seed-based order. Trees use 2x2 cell reservations; small props use one cell. Existing forbidden occupancy flags remain enforced.
- Forest coverage and patch size are resource properties; candidate density and limits remain per entry.
- Position and generated identity are set before the instance enters the scene tree.
- Per-entry chunk counts are cached instead of rescanning all accepted objects for every candidate.
- Road generation code and its profiles are unchanged. The new environment profile deliberately changes world compatibility; existing save compatibility must not be bypassed.

## Verification

Run Godot 4.6.2 with `--headless --path .` followed by:

- `tests/block_d_contract_test.tscn`
- `tests/block_d_persistence_test.tscn`
- `tests/block_d_fixed_seed_matrix_test.tscn`
- `--script tests/world_generation_smoke_test.gd`

The matrix checks repeatability, entry/chunk enumeration independence, all five species, at least 500 trees, 75% forest territory, and unchanged road graph/raster baseline hashes over six seeds.

For rendered inspection, run without `--headless`:

`--path . --resolution 1280x900 tests/forest_preview_capture.tscn`

Screenshots go to `tests/artifacts/forest/`. This is a generation preview using production environment tilesets, not a player traversal test.

Validated locally with Godot 4.6.2: contract tests (including six stone variants), resource persistence, six-seed matrix and production smoke all passed. Seed 1337 produces 1,329 trees across five species, with 6,595 forest cells out of 8,793 available cells. The production smoke also reports an exit-time ObjectDB/resource leak warning; a PASS is not a claim of a clean shutdown. Startup remains synchronous and requires performance work.

## Remaining work

- Profile and distribute startup generation over frames: dense object materialization still blocks startup.
- Validate movement, chopping and save/reload of the full dense forest in gameplay, including target Android hardware.
- Standalone houses, bunkers and camps are now integrated through shared occupancy;
  their legacy spawners remain disabled to avoid duplicate generation.
- Audit unused atlas cells and author footprint/placement rules for new scenery. Inventory icons and building props should not be indiscriminately scattered through the wilderness.
- Tune canopy density and forest boundaries against the desired in-game appearance. A 75% territory mask does not imply 75% visual canopy coverage.
