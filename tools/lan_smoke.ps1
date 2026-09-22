param(
	[string]$GodotPath = "",
	[int]$Port = 2456,
	[int]$RunSeconds = 20,
	[int]$HostReadyTimeoutSec = 8,
	[double]$PickupAfterSec = 5.0,
	[switch]$ReconnectClient,
	[switch]$GameplayProbe,
	[switch]$DeathProbe,
	[switch]$SharedStateProbe,
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

Remove-Item -LiteralPath $hostLog,$clientLog,(Join-Path $projectRoot ".godot-lan-client-first.log") -ErrorAction SilentlyContinue

$smokeExitSec = [Math]::Max([int]$RunSeconds - 4, 6)
$pickupAfterSec = [Math]::Max([double]$PickupAfterSec, 0.0)
$pickupAfterArg = $pickupAfterSec.ToString([System.Globalization.CultureInfo]::InvariantCulture)
$hostArgs = @("--headless", "--path", $projectRoot, "--log-file", $hostLog, "--", "--lan-smoke-mode=host", "--lan-port=$Port", "--lan-smoke-exit-sec=$smokeExitSec")
$clientArgs = @("--headless", "--path", $projectRoot, "--log-file", $clientLog, "--", "--lan-smoke-mode=client", "--lan-host=127.0.0.1", "--lan-port=$Port", "--lan-smoke-exit-sec=$smokeExitSec")
if ($pickupAfterSec -gt 0.0) {
	$hostArgs += "--lan-smoke-pickup-after-sec=$pickupAfterArg"
}
if ($SharedStateProbe) {
	$hostArgs += "--lan-smoke-shared=1"
	$clientArgs += "--lan-smoke-shared=1"
}
if ($DeathProbe) {
	$GameplayProbe = $true
	$hostArgs += "--lan-smoke-death=1"
	$clientArgs += "--lan-smoke-death=1"
}
if ($GameplayProbe) {
	$hostArgs += "--lan-smoke-gameplay=1"
	$clientArgs += "--lan-smoke-gameplay=1"
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

$firstClientRunSeconds = $RunSeconds
if ($ReconnectClient) {
	$firstClientRunSeconds = [Math]::Max([int][Math]::Floor($RunSeconds / 2), 3)
}
for ($elapsed = 0; $elapsed -lt $firstClientRunSeconds; $elapsed++) { Start-Sleep -Seconds 1 }

if ($ReconnectClient -and -not $clientProc.HasExited) {
	& taskkill.exe /PID $clientProc.Id /T /F | Out-Null
	$clientProc.WaitForExit()
	Copy-Item -LiteralPath $clientLog -Destination (Join-Path $projectRoot ".godot-lan-client-first.log") -Force
	Start-Sleep -Milliseconds 400
	$clientProc = Start-Process -FilePath $GodotPath -ArgumentList $clientArgs -PassThru -WindowStyle Hidden
	for ($elapsed = 0; $elapsed -lt [Math]::Max($RunSeconds - $firstClientRunSeconds, 3); $elapsed++) { Start-Sleep -Seconds 1 }
}

if (-not $hostProc.HasExited) { & taskkill.exe /PID $hostProc.Id /T /F | Out-Null }
if (-not $clientProc.HasExited) { & taskkill.exe /PID $clientProc.Id /T /F | Out-Null }

Write-Host "LAN smoke run completed."
Write-Host "Host log: $hostLog"
Write-Host "Client log: $clientLog"

$logsToCheck = @($hostLog, $clientLog)
if ($ReconnectClient) { $logsToCheck += (Join-Path $projectRoot ".godot-lan-client-first.log") }
foreach ($testLog in $logsToCheck) {
	if (-not (Test-Path -LiteralPath $testLog)) { throw "Missing smoke log: $testLog" }
	if (Select-String -LiteralPath $testLog -Pattern 'ERROR:|SCRIPT ERROR:|LAN_GAMEPLAY_PROBE=FAIL|LAN_VITALS_PROBE=FAIL|LAN_WEAPON_ACTIONS_PROBE=FAIL|LAN_SHARED_STATE_PROBE=FAIL|LAN_DEATH_PROBE=FAIL|LAN_ACTIONS_PROBE=FAIL' -Quiet) { throw "LAN smoke failed; inspect $testLog" }
}
if (-not (Select-String -LiteralPath $clientLog -Pattern 'Client world ready acknowledged by host' -SimpleMatch -Quiet)) { throw "Client did not complete handshake" }
if ($GameplayProbe) {
	$passes = @(Select-String -LiteralPath $hostLog -Pattern 'LAN_GAMEPLAY_PROBE=PASS' -SimpleMatch).Count
	$requiredPasses = if ($ReconnectClient) { 2 } else { 1 }
	if ($passes -lt $requiredPasses) { throw "Gameplay probe incomplete: $passes / $requiredPasses" }
	$vitalsPasses = @(Select-String -LiteralPath $hostLog -Pattern 'LAN_VITALS_PROBE=PASS' -SimpleMatch).Count
	if ($vitalsPasses -lt $requiredPasses) { throw "Vitals/HUD probe incomplete: $vitalsPasses / $requiredPasses" }
	$weaponActionPasses = @(Select-String -LiteralPath $hostLog -Pattern 'LAN_WEAPON_ACTIONS_PROBE=PASS' -SimpleMatch).Count
	if ($weaponActionPasses -lt $requiredPasses) { throw "Weapon actions probe incomplete: $weaponActionPasses / $requiredPasses" }
}
if ($SharedStateProbe) {
	$passes = @(Select-String -LiteralPath $hostLog -Pattern "LAN_SHARED_STATE_PROBE=PASS" -SimpleMatch).Count
	$requiredPasses = if ($ReconnectClient) { 2 } else { 1 }
	if (-not (Select-String -LiteralPath $hostLog -Pattern "LAN_ACTIONS_PROBE=PASS" -SimpleMatch -Quiet)) { throw "Shared actions probe incomplete" }
	if ($passes -lt $requiredPasses) { throw "Shared state probe incomplete: $passes / $requiredPasses" }
}
if ($DeathProbe -and -not (Select-String -LiteralPath $hostLog -Pattern "LAN_DEATH_PROBE=PASS" -SimpleMatch -Quiet)) { throw "Death probe incomplete" }
Write-Host "LAN_SMOKE=PASS"
