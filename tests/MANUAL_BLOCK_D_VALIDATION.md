# Manual Block D validation

Open `res://tests/manual_block_d_validation.tscn` in Godot. It is an editor-facing entry point for the production generation order: base terrain → road graph → road raster → POI/Village → Environment → legacy spawners. It does not modify production profiles.

After generating prerequisites, inspect `road_raster_diagnostics` in the Inspector. It reports RoadRaster-only ROAD occupancy (not decorative tiles), component counts, and any isolated or 1–3-cell component records with their seed, cell, TileMap source/atlas, and nearest graph node. Any nonzero isolated/small component count is a failure.

Set `world_seed`, use **Generate full world** (or **Generate prerequisites** then **Generate Block D**), then inspect the production result and its hashes against `tests/artifacts/block_d/fixed_seed_environment_matrix.json`. **Clear Block D** must preserve Road, POI and Village; **Regenerate Block D** must return the same hashes.

Check all six seeds: `1337`, `7331`, `15885`, `1001`, `2026`, `99999`. For each, compare environment manifest/content hashes, placement/category/rejection counts, RoadGraph/Raster, compatibility, manifest and output hashes with the matrix artifact. Seed 1337 must retain RoadGraph `75916414acdf7aef1502e082bcc72bd976b5b24f8b7aca5a4177e4d5e48d49f7` and RoadRaster `0c17ddbedde7fdf8c6e98690b73cba62dc100d15231ee2a4f4dc59827ed2dcb8`.

Use the Inspector toggles for world bounds, road/clearance, water, POI/building bounds, environment footprint/clearance/spacing, occupancy, generated IDs, rejected candidates, TileMap/scene content and categories. Real category IDs are `biom1_static_tiles`, `biom2_static_tiles`, `xz_static_tiles`, `trees`, `bushes`, `puddles`, `stones`, `deadwood`, `berry_bushes`.

Fail validation if Environment overlaps road, clearance, water, POI/buildings, leaves bounds, violates expanded-footprint spacing, changes IDs/hashes after regenerate, accumulates content or claims, Clear removes prerequisites, debug changes hashes, counts disagree with the artifact, or a valid profile reports a blocking error.

Acceptable pre-existing warnings: duplicate UID `geiger_counter/cigarettes_pack`, unavailable LAN discovery in headless, and normal headless cleanup/stutter output without a test failure. Do not treat new warnings as acceptable.
