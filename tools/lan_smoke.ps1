param(
	[string]$GodotPath = "",
	[int]$Port = 2456,
	[int]$RunSeconds = 20
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$hostLog = Join-Path $projectRoot ".godot-lan-host.log"
$clientLog = Join-Path $projectRoot ".godot-lan-client.log"

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
	$GodotPath = (Get-Command godot -ErrorAction SilentlyContinue)?.Source
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
	throw "Godot CLI not found. Pass -GodotPath 'C:\Path\To\Godot.exe'."
}

Remove-Item -LiteralPath $hostLog,$clientLog -ErrorAction SilentlyContinue

$smokeExitSec = [Math]::Max([int]$RunSeconds - 4, 6)
$hostArgs = @("--headless", "--path", $projectRoot, "--log-file", $hostLog, "--", "--lan-smoke-mode=host", "--lan-port=$Port", "--lan-smoke-exit-sec=$smokeExitSec")
$clientArgs = @("--headless", "--path", $projectRoot, "--log-file", $clientLog, "--", "--lan-smoke-mode=client", "--lan-host=127.0.0.1", "--lan-port=$Port", "--lan-smoke-exit-sec=$smokeExitSec")

$hostProc = Start-Process -FilePath $GodotPath -ArgumentList $hostArgs -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 800
$clientProc = Start-Process -FilePath $GodotPath -ArgumentList $clientArgs -PassThru -WindowStyle Hidden

Start-Sleep -Seconds $RunSeconds

if (-not $hostProc.HasExited) { $hostProc.Kill() }
if (-not $clientProc.HasExited) { $clientProc.Kill() }

Write-Host "LAN smoke run completed."
Write-Host "Host log: $hostLog"
Write-Host "Client log: $clientLog"
