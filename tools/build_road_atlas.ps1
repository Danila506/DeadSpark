param(
    [string]$SourcePath = "",
    [string]$OutputPath = "Assets/World/Roads/RoadLayer256.png"
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$outputAbsolute = [System.IO.Path]::GetFullPath((Join-Path $root $OutputPath))
# The artist's atlas is authoritative. Default invocation only validates it.
# Publishing another atlas requires explicit -SourcePath; pixels are copied.
$inputAbsolute = if ($SourcePath -eq "") { $outputAbsolute } else {
    [System.IO.Path]::GetFullPath((Join-Path $root $SourcePath))
}
$atlas = [System.Drawing.Bitmap]::FromFile($inputAbsolute)
try {
    if ($atlas.Width % 256 -ne 0 -or $atlas.Height % 256 -ne 0) {
        throw "Authored road atlas dimensions must be multiples of 256px."
    }
} finally { $atlas.Dispose() }
if ($inputAbsolute -ne $outputAbsolute) {
    [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($outputAbsolute)) | Out-Null
    Copy-Item -LiteralPath $inputAbsolute -Destination $outputAbsolute
}
Write-Output "Preserved authored road atlas unchanged: $outputAbsolute"
