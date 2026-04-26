param(
	[string]$GodotPath = ""
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Resolve-GodotCommand {
	param([string]$ExplicitPath)

	if ($ExplicitPath -ne "") {
		if (Test-Path -LiteralPath $ExplicitPath -PathType Leaf) {
			return (Resolve-Path -LiteralPath $ExplicitPath).Path
		}
		if (Test-Path -LiteralPath $ExplicitPath -PathType Container) {
			$directoryPath = (Resolve-Path -LiteralPath $ExplicitPath).Path
			$preferredNames = @(
				"godot4_console.exe",
				"godot_console.exe",
				"godot4.exe",
				"godot.exe"
			)

			foreach ($preferredName in $preferredNames) {
				$candidatePath = Join-Path $directoryPath $preferredName
				if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
					return $candidatePath
				}
			}

			$genericCandidate = Get-ChildItem -LiteralPath $directoryPath -Filter "Godot*.exe" -File -ErrorAction SilentlyContinue |
				Sort-Object Name |
				Select-Object -First 1
			if ($null -ne $genericCandidate) {
				return $genericCandidate.FullName
			}

			throw "No Godot executable was found in '$directoryPath'."
		}
		throw "Godot executable was not found at '$ExplicitPath'."
	}

	$commandNames = @("godot", "godot4", "godot4_console")
	foreach ($name in $commandNames) {
		$command = Get-Command $name -ErrorAction SilentlyContinue
		if ($null -ne $command) {
			return $command.Source
		}
	}

	throw "Godot CLI was not found in PATH. Pass -GodotPath 'C:\Path\To\Godot.exe' or add Godot to PATH."
}

$godot = Resolve-GodotCommand -ExplicitPath $GodotPath
Write-Host "Using Godot: $godot"

$logPath = Join-Path $ProjectRoot ".godot-headless.log"
$arguments = @("--headless", "--path", $ProjectRoot, "--log-file", $logPath, "--quit")
$process = Start-Process -FilePath $godot -ArgumentList $arguments -NoNewWindow -Wait -PassThru
$exitCode = $process.ExitCode
if ($exitCode -ne 0) {
	throw "Godot headless project check failed with exit code $exitCode."
}

Write-Host "Godot headless project check passed."
