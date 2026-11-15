param([string]$In, [string]$OutDir, [string]$Name = 'hajin')
# GLB -> glTF JSON (geometry as base64 data URI) + external texture files.
$bytes = [System.IO.File]::ReadAllBytes($In)
$jlen = [BitConverter]::ToUInt32($bytes, 12)
$j = [System.Text.Encoding]::UTF8.GetString($bytes, 20, $jlen) | ConvertFrom-Json
$binStart = 20 + $jlen + 8

$imageViews = @{}
for ($i = 0; $i -lt $j.images.Count; $i++) { $imageViews[[int]$j.images[$i].bufferView] = $i }

$ms = New-Object System.IO.MemoryStream
$remap = @{}
$views = New-Object System.Collections.ArrayList
for ($v = 0; $v -lt $j.bufferViews.Count; $v++) {
  $bv = $j.bufferViews[$v]
  $data = New-Object byte[] $bv.byteLength
  [Array]::Copy($bytes, $binStart + [int]$bv.byteOffset, $data, 0, $bv.byteLength)
  if ($imageViews.ContainsKey($v)) {
    $ii = $imageViews[$v]
    $ext = if ($j.images[$ii].mimeType -eq 'image/png') { 'png' } else { 'jpg' }
    $file = "${Name}_tex$ii.$ext"
    [System.IO.File]::WriteAllBytes((Join-Path $OutDir $file), $data)
    $j.images[$ii] = [pscustomobject]@{ uri = $file; name = $j.images[$ii].name }
    continue
  }
  while ($ms.Length % 4 -ne 0) { $ms.WriteByte(0) }
  $bv.byteOffset = [int]$ms.Length
  $ms.Write($data, 0, $data.Length)
  $remap[$v] = $views.Count
  [void]$views.Add($bv)
}
foreach ($a in $j.accessors) { $a.bufferView = $remap[[int]$a.bufferView] }
$j.bufferViews = $views.ToArray()
$bin = $ms.ToArray()
$j.buffers = @([pscustomobject]@{ byteLength = $bin.Length; uri = 'data:application/octet-stream;base64,' + [Convert]::ToBase64String($bin) })
$out = Join-Path $OutDir "$Name.json"
[System.IO.File]::WriteAllText($out, ($j | ConvertTo-Json -Depth 20 -Compress), (New-Object System.Text.UTF8Encoding $false))
"wrote $out " + (Get-Item $out).Length
