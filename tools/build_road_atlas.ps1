param(
    [string]$SourcePath = "Assets/World/Roads/RoadLayerSource.png",
    [string]$OutputPath = "Assets/World/Roads/RoadLayer256.png"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$sourceAbsolute = [System.IO.Path]::GetFullPath((Join-Path $root $SourcePath))
$outputAbsolute = [System.IO.Path]::GetFullPath((Join-Path $root $OutputPath))
$source = [System.Drawing.Bitmap]::FromFile($sourceAbsolute)

function New-TransparentBitmap([int]$width, [int]$height) {
    $bitmap = [System.Drawing.Bitmap]::new($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $bitmap.SetResolution(96, 96)
    return $bitmap
}

function Copy-Pixels($from, [System.Drawing.Rectangle]$sourceRect, $to, [System.Drawing.Point]$destination) {
    for ($y = 0; $y -lt $sourceRect.Height; $y++) {
        for ($x = 0; $x -lt $sourceRect.Width; $x++) {
            $to.SetPixel($destination.X + $x, $destination.Y + $y, $from.GetPixel($sourceRect.X + $x, $sourceRect.Y + $y))
        }
    }
}

function Crop-Padded($from, [int]$x, [int]$y) {
    $tile = New-TransparentBitmap 256 256
    $sourceX = [Math]::Max(0, $x)
    $sourceY = [Math]::Max(0, $y)
    $endX = [Math]::Min($from.Width, $x + 256)
    $endY = [Math]::Min($from.Height, $y + 256)
    if ($endX -gt $sourceX -and $endY -gt $sourceY) {
        Copy-Pixels $from ([System.Drawing.Rectangle]::new($sourceX, $sourceY, $endX - $sourceX, $endY - $sourceY)) $tile ([System.Drawing.Point]::new($sourceX - $x, $sourceY - $y))
    }
    return $tile
}

function Clone-Rotated($tile, [System.Drawing.RotateFlipType]$rotation) {
    $copy = $tile.Clone()
    $copy.RotateFlip($rotation)
    return $copy
}

function Make-Vertical-Periodic($tile) {
    $sourceCopy = $tile.Clone()
    for ($y = 0; $y -lt 256; $y++) {
        $sourceY = if ($y -lt 128) { 64 + $y } else { 191 - ($y - 128) }
        for ($x = 0; $x -lt 256; $x++) {
            $tile.SetPixel($x, $y, $sourceCopy.GetPixel($x, $sourceY))
        }
    }
    $sourceCopy.Dispose()
}

function Make-Horizontal-Periodic($tile) {
    $sourceCopy = $tile.Clone()
    for ($x = 0; $x -lt 256; $x++) {
        $sourceX = if ($x -lt 128) { 64 + $x } else { 191 - ($x - 128) }
        for ($y = 0; $y -lt 256; $y++) {
            $tile.SetPixel($x, $y, $sourceCopy.GetPixel($sourceX, $y))
        }
    }
    $sourceCopy.Dispose()
}

function Copy-ConnectorEdge($tile, [string]$side, $vertical, $horizontal, [int]$band) {
    switch ($side) {
        "U" {
            Copy-Pixels $vertical ([System.Drawing.Rectangle]::new(0, 0, 256, $band)) $tile ([System.Drawing.Point]::new(0, 0))
        }
        "D" {
            Copy-Pixels $vertical ([System.Drawing.Rectangle]::new(0, 256 - $band, 256, $band)) $tile ([System.Drawing.Point]::new(0, 256 - $band))
        }
        "L" {
            Copy-Pixels $horizontal ([System.Drawing.Rectangle]::new(0, 0, $band, 256)) $tile ([System.Drawing.Point]::new(0, 0))
        }
        "R" {
            Copy-Pixels $horizontal ([System.Drawing.Rectangle]::new(256 - $band, 0, $band, 256)) $tile ([System.Drawing.Point]::new(256 - $band, 0))
        }
    }
}

if ($source.Width -ne 2477 -or $source.Height -ne 259) {
    $source.Dispose()
    throw "Unexpected road source size: expected 2477x259."
}

# All crops preserve the source pixels 1:1. Coordinates are centered on the
# authored connection point of each piece rather than its visible alpha bounds.
$vertical = Crop-Padded $source 96 3
$horizontal = Crop-Padded $source 2165 2
$cross = Crop-Padded $source 480 0
$tMissingDown = Crop-Padded $source 928 40
$cornerUpLeft = Crop-Padded $source 1758 47
$connectorBand = 8
Make-Vertical-Periodic $vertical
Make-Horizontal-Periodic $horizontal

$tiles = @(
    $vertical,
    $cross,
    $tMissingDown,
    (Clone-Rotated $tMissingDown ([System.Drawing.RotateFlipType]::Rotate270FlipNone)),
    (Clone-Rotated $tMissingDown ([System.Drawing.RotateFlipType]::Rotate90FlipNone)),
    (Clone-Rotated $tMissingDown ([System.Drawing.RotateFlipType]::Rotate180FlipNone)),
    $horizontal,
    (Clone-Rotated $cornerUpLeft ([System.Drawing.RotateFlipType]::Rotate270FlipNone)),
    (Clone-Rotated $cornerUpLeft ([System.Drawing.RotateFlipType]::Rotate90FlipNone)),
    $cornerUpLeft,
    (Clone-Rotated $cornerUpLeft ([System.Drawing.RotateFlipType]::Rotate180FlipNone))
)

# The authored T and corner stop a few pixels short of their canvases. Copy a
# narrow edge directly from the canonical straight pieces after rotation. This
# is a hard 1:1 pixel copy: no interpolation, alpha averaging, or resampling.
$connections = @("UD", "UDLR", "ULR", "UDL", "UDR", "DLR", "LR", "DL", "UR", "UL", "DR")
for ($index = 0; $index -lt $tiles.Count; $index++) {
    $tile = $tiles[$index]
    $sides = $connections[$index]
    if ($sides.Contains("U")) { Copy-ConnectorEdge $tile "U" $vertical $horizontal $connectorBand }
    if ($sides.Contains("D")) { Copy-ConnectorEdge $tile "D" $vertical $horizontal $connectorBand }
    if ($sides.Contains("L")) { Copy-ConnectorEdge $tile "L" $vertical $horizontal $connectorBand }
    if ($sides.Contains("R")) { Copy-ConnectorEdge $tile "R" $vertical $horizontal $connectorBand }
}

$atlas = New-TransparentBitmap 1536 512
for ($index = 0; $index -lt $tiles.Count; $index++) {
    $column = if ($index -lt 6) { $index } else { $index - 6 }
    $row = if ($index -lt 6) { 0 } else { 1 }
    Copy-Pixels $tiles[$index] ([System.Drawing.Rectangle]::new(0, 0, 256, 256)) $atlas ([System.Drawing.Point]::new($column * 256, $row * 256))
}

[System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($outputAbsolute)) | Out-Null
$atlas.Save($outputAbsolute, [System.Drawing.Imaging.ImageFormat]::Png)

foreach ($tile in $tiles) { $tile.Dispose() }
$atlas.Dispose()
$source.Dispose()
Write-Output "Built road atlas: $outputAbsolute"
