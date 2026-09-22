# Manual Loot Validation

Open `tests/manual_loot_validation.tscn` with F6. The scene remains open during a normal run; CI uses `--manual-loot-smoke`.

Choose a provider, enter a seed, then use **Generate**, **Materialize**, **Opened**, **Remove slot**, and **Serialize**. **Clear / restore** creates a new production instance and applies the JSON-safe snapshot. Use **Change seed** or **Change profile** before restore to verify saved state wins. **Reset** and **Regenerate unopened** support same-seed comparison.

For Bunker, verify the explicit-empty profile, zero slots and zero materialized items before and after restore. Compare seed 1337 manifest/content values with `tests/artifacts/loot/fixed_seed_loot_matrix.json`.

Failures: blocking errors, changed same-seed hashes, a returned removed item, changed saved manifest after seed/profile changes, non-empty Bunker, or changed repeated-restore snapshot hash. Acceptable warnings: existing duplicate resource UID and headless teardown resource warnings.
