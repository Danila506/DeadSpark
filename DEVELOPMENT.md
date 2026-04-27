# DeadSpark Development Notes

## Git

The project is initialized as a Git repository. Keep generated editor state out of commits:

- `.godot/`
- `*.tmp`
- `export_credentials.cfg`

Before larger refactors, check the working tree:

```powershell
git status --short
```

## Godot Check

Run the project smoke check with:

```powershell
powershell -ExecutionPolicy Bypass -File tools/check_project.ps1
```

If Godot is not in `PATH`, pass the executable explicitly:

```powershell
powershell -ExecutionPolicy Bypass -File tools/check_project.ps1 -GodotPath "C:\Path\To\Godot.exe"
```

The script runs:

```powershell
godot --headless --path <project-root> --quit
```

## Runtime Save/Load

`ItemInstance` runtime split now has end-to-end serialization:

- `runtime_id`
- `definition_path` (`definition.resource_path`)
- `stack_count` / `endurance`
- nested `runtime_storage_items`
- runtime weapon state (`ammo`, scope, attachments)

Full game persistence is managed by `GameSaveManager` in `user://savegame.json`:

- inventory runtime state (`InventoryManager.get_save_data()/apply_save_data()`)
- player runtime vitals and position
- interactable world runtime state (`box`, `medicine_kit`, `forester_house`, `tree`)
- world pickups (`pickup_item`) with runtime `ItemInstance`

In-game hotkeys:

- `F5` - save game
- `F9` - load game

## Current Tooling Notes

GodexCLI plugin is intentionally not used in this project. Keep `project.godot` free of `res://addons/godex-cli/plugin.cfg` entries unless you reinstall that addon.
