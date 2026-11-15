param([string]$In, [string]$Out, [int]$MaxSize = 1024, [long]$Quality = 85)
# Re-encodes every embedded texture of a GLB as a downscaled JPEG and rebuilds the binary chunk.
Add-Type -AssemblyName System.Drawing
$bytes = [System.IO.File]::ReadAllBytes($In)
$jlen = [BitConverter]::ToUInt32($bytes, 12)
$json = [System.Text.Encoding]::UTF8.GetString($bytes, 20, $jlen)
$binStart = 20 + $jlen + 8
$j = $json | ConvertFrom-Json

$jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ep = New-Object System.Drawing.Imaging.EncoderParameters 1
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), $Quality

$imageViews = @{}
foreach ($im in $j.images) { $imageViews[[int]$im.bufferView] = $im }

$ms = New-Object System.IO.MemoryStream
for ($i = 0; $i -lt $j.bufferViews.Count; $i++) {
  $bv = $j.bufferViews[$i]
  $off = [int]$bv.byteOffset
  $data = New-Object byte[] $bv.byteLength
  [Array]::Copy($bytes, $binStart + $off, $data, 0, $bv.byteLength)
  if ($imageViews.ContainsKey($i)) {
    $src = [System.Drawing.Image]::FromStream((New-Object System.IO.MemoryStream (,$data)))
    $scale = [Math]::Min(1.0, $MaxSize / [Math]::Max($src.Width, $src.Height))
    $w = [int]($src.Width * $scale); $h = [int]($src.Height * $scale)
    $dst = New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($dst)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.DrawImage($src, 0, 0, $w, $h)
    $g.Dispose(); $src.Dispose()
    $o = New-Object System.IO.MemoryStream
    $dst.Save($o, $jpegCodec, $ep); $dst.Dispose()
    $data = $o.ToArray()
    $imageViews[$i].mimeType = 'image/jpeg'
    "  view $i -> $w x $h, $($data.Length) bytes"
  }
  while ($ms.Length % 4 -ne 0) { $ms.WriteByte(0) }
  $bv.byteOffset = [int]$ms.Length
  $bv.byteLength = $data.Length
  $ms.Write($data, 0, $data.Length)
}
while ($ms.Length % 4 -ne 0) { $ms.WriteByte(0) }
$bin = $ms.ToArray()
$j.buffers[0].byteLength = $bin.Length

$newJson = $j | ConvertTo-Json -Depth 20 -Compress
$raw = [System.Text.Encoding]::UTF8.GetBytes($newJson)
$padded = [int]([Math]::Ceiling($raw.Length / 4.0) * 4)
[byte[]]$jb = New-Object byte[] $padded
for ($k = 0; $k -lt $padded; $k++) { $jb[$k] = 0x20 }
[Array]::Copy($raw, $jb, $raw.Length)
$total = 12 + 8 + $jb.Length + 8 + $bin.Length
$glbStream = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter -ArgumentList $glbStream
$bw.Write([uint32]0x46546C67); $bw.Write([uint32]2); $bw.Write([uint32]$total)
$bw.Write([uint32]$jb.Length); $bw.Write([uint32]0x4E4F534A); $bw.Write($jb)
$bw.Write([uint32]$bin.Length); $bw.Write([uint32]0x004E4942); $bw.Write($bin)
$bw.Flush()
[System.IO.File]::WriteAllBytes($Out, $glbStream.ToArray())
"wrote $Out ($total bytes)"
