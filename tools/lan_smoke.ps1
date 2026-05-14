param(
	[string]$GodotPath = "",
	[int]$Port = 2456,
	[int]$RunSeconds = 20,
	[int]$HostReadyTimeoutSec = 8,
	[double]$PickupAfterSec = 5.0,
	[switch]$NetDebug
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$hostLog = Join-Path $projectRoot ".godot-lan-host.log"
$clientLog = Join-Path $projectRoot ".godot-lan-client.log"

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
	throw "Godot CLI not found. Pass -GodotPath 'C:\Path\To\Godot.exe' or add Godot to PATH."
}

$GodotPath = Resolve-GodotCommand -ExplicitPath $GodotPath

Remove-Item -LiteralPath $hostLog,$clientLog -ErrorAction SilentlyContinue

$smokeExitSec = [Math]::Max([int]$RunSeconds - 4, 6)
$pickupAfterSec = [Math]::Max([double]$PickupAfterSec, 0.0)
$pickupAfterArg = $pickupAfterSec.ToString([System.Globalization.CultureInfo]::InvariantCulture)
$hostArgs = @("--headless", "--path", $projectRoot, "--log-file", $hostLog, "--", "--lan-smoke-mode=host", "--lan-port=$Port", "--lan-smoke-exit-sec=$smokeExitSec")
$clientArgs = @("--headless", "--path", $projectRoot, "--log-file", $clientLog, "--", "--lan-smoke-mode=client", "--lan-host=127.0.0.1", "--lan-port=$Port", "--lan-smoke-exit-sec=$smokeExitSec")
if ($pickupAfterSec -gt 0.0) {
	$hostArgs += "--lan-smoke-pickup-after-sec=$pickupAfterArg"
}
if ($NetDebug) {
	$hostArgs += "--lan-net-debug=1"
	$clientArgs += "--lan-net-debug=1"
}

$hostProc = Start-Process -FilePath $GodotPath -ArgumentList $hostArgs -PassThru -WindowStyle Hidden
$hostReady = $false
$hostDeadline = (Get-Date).AddSeconds([Math]::Max($HostReadyTimeoutSec, 1))
while ((Get-Date) -lt $hostDeadline) {
	if ($hostProc.HasExited) {
		break
	}
	if (Test-Path -LiteralPath $hostLog) {
		$hostReadyLine = Select-String -Path $hostLog -Pattern "LAN gameplay world initialized as server" -SimpleMatch -ErrorAction SilentlyContinue | Select-Object -First 1
		if ($null -ne $hostReadyLine) {
			$hostReady = $true
			break
		}
	}
	Start-Sleep -Milliseconds 150
}
if (-not $hostReady -and -not $hostProc.HasExited) {
	Start-Sleep -Milliseconds 600
}
$clientProc = Start-Process -FilePath $GodotPath -ArgumentList $clientArgs -PassThru -WindowStyle Hidden

Start-Sleep -Seconds $RunSeconds

if (-not $hostProc.HasExited) { $hostProc.Kill() }
if (-not $clientProc.HasExited) { $clientProc.Kill() }

Write-Host "LAN smoke run completed."
Write-Host "Host log: $hostLog"
Write-Host "Client log: $clientLog"
