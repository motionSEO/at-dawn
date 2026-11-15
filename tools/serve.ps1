param([string]$Root, [int]$Port = 8765)
# Serves $Root; .html pages get the same skeleton the artifact host adds.
$types = @{ '.html' = 'text/html; charset=utf-8'; '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.glb' = 'model/gltf-binary'; '.js' = 'text/javascript'; '.webp' = 'image/webp'; '.json' = 'application/json' }
$l = New-Object System.Net.HttpListener
$l.Prefixes.Add("http://localhost:$Port/")
$l.Start()
while ($l.IsListening) {
  $c = $l.GetContext()
  $rel = [Uri]::UnescapeDataString($c.Request.Url.AbsolutePath.TrimStart('/'))
  if ($rel -eq '') { $rel = 'index.html' }
  $path = Join-Path $Root $rel
  if (Test-Path $path -PathType Leaf) {
    $ext = [IO.Path]::GetExtension($path).ToLower()
    if ($ext -eq '.html') {
      $body = [Text.Encoding]::UTF8.GetBytes('<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body>' + [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) + '</body></html>')
    } else { $body = [IO.File]::ReadAllBytes($path) }
    $c.Response.ContentType = $types[$ext]
    $c.Response.OutputStream.Write($body, 0, $body.Length)
  } else { $c.Response.StatusCode = 404 }
  $c.Response.Close()
}
