$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$assetDirectory = Join-Path $PSScriptRoot 'assets'
$null = New-Item -ItemType Directory -Path $assetDirectory -Force
$images = @()
foreach ($size in @(16, 24, 32, 48, 64, 128, 256)) {
    $bitmap = New-Object System.Drawing.Bitmap $size, $size
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = 'AntiAlias'
    $graphics.ScaleTransform(($size / 256.0), ($size / 256.0))
    $background = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(16, 24, 28))
    $mint = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(156, 230, 210))
    $graphics.Clear([System.Drawing.Color]::Transparent)
    $graphics.FillEllipse($background, 4, 4, 248, 248)
    # An upward paper-plane silhouette, matching the launcher's mint palette.
    $points = [System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new(128, 38),
        [System.Drawing.PointF]::new(211, 205),
        [System.Drawing.PointF]::new(128, 166),
        [System.Drawing.PointF]::new(45, 205)
    )
    $graphics.FillPolygon($mint, $points)
    $graphics.FillPolygon($background, [System.Drawing.PointF[]]@(
        [System.Drawing.PointF]::new(128, 97),
        [System.Drawing.PointF]::new(142, 162),
        [System.Drawing.PointF]::new(128, 155)
    ))
    $stream = New-Object System.IO.MemoryStream
    $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    $images += ,($stream.ToArray())
    if ($size -eq 256) {
        [System.IO.File]::WriteAllBytes((Join-Path $assetDirectory 'AirLauncher.png'), $stream.ToArray())
    }
    $stream.Dispose()
    $mint.Dispose()
    $background.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}
$file = [System.IO.File]::Create((Join-Path $assetDirectory 'AirLauncher.ico'))
$writer = New-Object System.IO.BinaryWriter $file
try {
    $writer.Write([uint16]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]$images.Count)
    $offset = 6 + 16 * $images.Count
    $sizes = @(16, 24, 32, 48, 64, 128, 256)
    for ($i = 0; $i -lt $images.Count; $i++) {
        $dimension = if ($sizes[$i] -eq 256) { 0 } else { $sizes[$i] }
        $writer.Write([byte]$dimension)
        $writer.Write([byte]$dimension)
        $writer.Write([uint16]0)
        $writer.Write([uint16]1)
        $writer.Write([uint16]32)
        $writer.Write([uint32]$images[$i].Length)
        $writer.Write([uint32]$offset)
        $offset += $images[$i].Length
    }
    foreach ($bytes in $images) { $writer.Write([byte[]]$bytes) }
}
finally { $writer.Dispose() }
