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

## Current Tooling Notes

GodexCLI plugin is intentionally not used in this project. Keep `project.godot` free of `res://addons/godex-cli/plugin.cfg` entries unless you reinstall that addon.
