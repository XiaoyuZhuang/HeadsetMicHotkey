Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Drawing.Common -ErrorAction SilentlyContinue

$size = 256
$bmp = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.Clear([System.Drawing.Color]::Transparent)

function New-RoundedRectPath([System.Drawing.RectangleF]$rect, [float]$radius) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $radius * 2
    $path.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
    $path.AddArc($rect.Right - $d, $rect.Y, $d, $d, 270, 90)
    $path.AddArc($rect.Right - $d, $rect.Bottom - $d, $d, $d, 0, 90)
    $path.AddArc($rect.X, $rect.Bottom - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

# Deep Windows-style blue tile.
$rect = New-Object System.Drawing.RectangleF(8, 8, 240, 240)
$path = New-RoundedRectPath $rect 54
$c1 = [System.Drawing.Color]::FromArgb(255, 15, 23, 42)
$c2 = [System.Drawing.Color]::FromArgb(255, 37, 99, 235)
$bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $c1, $c2, 35)
$g.FillPath($bg, $path)

# Microphone capsule.
$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(248, 250, 252))
$micRect = New-Object System.Drawing.RectangleF(91, 47, 74, 112)
$micPath = New-RoundedRectPath $micRect 37
$g.FillPath($white, $micPath)

# Microphone cradle and stand.
$pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(248, 250, 252), 14)
$pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$g.DrawArc($pen, 67, 92, 122, 99, 10, 160)
$g.DrawLine($pen, 128, 186, 128, 211)
$g.DrawLine($pen, 94, 213, 162, 213)

# AI sparkle: a bright four-point star plus a smaller companion dot/star.
$accent = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(103, 232, 249))
$star = New-Object System.Drawing.Drawing2D.GraphicsPath
$cx = 187; $cy = 61
$star.AddPolygon([System.Drawing.PointF[]]@(
    (New-Object System.Drawing.PointF($cx, $cy-31)),
    (New-Object System.Drawing.PointF($cx+8, $cy-8)),
    (New-Object System.Drawing.PointF($cx+31, $cy)),
    (New-Object System.Drawing.PointF($cx+8, $cy+8)),
    (New-Object System.Drawing.PointF($cx, $cy+31)),
    (New-Object System.Drawing.PointF($cx-8, $cy+8)),
    (New-Object System.Drawing.PointF($cx-31, $cy)),
    (New-Object System.Drawing.PointF($cx-8, $cy-8))
))
$g.FillPath($accent, $star)
$g.FillEllipse($accent, 207, 93, 17, 17)

# Tiny neural-node motif.
$nodePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(185, 240, 253), 5)
$nodePen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
$nodePen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
$g.DrawLine($nodePen, 189, 112, 211, 126)
$g.FillEllipse($accent, 181, 104, 14, 14)
$g.FillEllipse($accent, 205, 120, 14, 14)

# PNG-compressed 256x256 ICO, supported by modern Windows.
$pngStream = New-Object System.IO.MemoryStream
$bmp.Save($pngStream, [System.Drawing.Imaging.ImageFormat]::Png)
$pngBytes = $pngStream.ToArray()
$outPath = Join-Path $PSScriptRoot 'app.ico'
$fs = [System.IO.File]::Create($outPath)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([UInt16]0)       # reserved
$bw.Write([UInt16]1)       # icon
$bw.Write([UInt16]1)       # one image
$bw.Write([Byte]0)         # 256px width
$bw.Write([Byte]0)         # 256px height
$bw.Write([Byte]0)         # palette
$bw.Write([Byte]0)         # reserved
$bw.Write([UInt16]1)       # planes
$bw.Write([UInt16]32)      # bpp
$bw.Write([UInt32]$pngBytes.Length)
$bw.Write([UInt32]22)      # image offset
$bw.Write($pngBytes)
$bw.Flush()
$bw.Close()

$nodePen.Dispose(); $pen.Dispose(); $accent.Dispose(); $white.Dispose(); $bg.Dispose(); $path.Dispose(); $micPath.Dispose(); $star.Dispose(); $g.Dispose(); $bmp.Dispose(); $pngStream.Dispose()
Write-Host "Generated $outPath"
