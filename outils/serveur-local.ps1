# SCEA Guidal - petit serveur local pour tester l'application sur cet ordinateur.
# Usage : clic droit > Executer avec PowerShell, puis ouvrir http://localhost:8080/?demo
# Arret : fermer la fenetre (ou Ctrl+C).
param([int]$Port = 8080)
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\app")).Path
$types = @{ ".html"="text/html; charset=utf-8"; ".js"="text/javascript; charset=utf-8"; ".css"="text/css; charset=utf-8";
            ".svg"="image/svg+xml"; ".json"="application/json"; ".webmanifest"="application/manifest+json"; ".png"="image/png"; ".jpg"="image/jpeg" }
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Serveur local demarre : http://localhost:$Port/?demo  (mode demo, donnees fictives)"
try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    try {
    $path = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath).TrimStart("/")
    if ($path -eq "") { $path = "index.html" }
    $file = [System.IO.Path]::GetFullPath((Join-Path $root $path))
    $res = $ctx.Response
    if ($file.StartsWith($root) -and (Test-Path $file -PathType Leaf)) {
      $bytes = [System.IO.File]::ReadAllBytes($file)
      $ext = [System.IO.Path]::GetExtension($file).ToLower()
      $res.ContentType = if ($types.ContainsKey($ext)) { $types[$ext] } else { "application/octet-stream" }
      $res.Headers.Add("Cache-Control", "no-store")
      $res.ContentLength64 = $bytes.Length
      $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } else { $res.StatusCode = 404 }
    $res.Close()
    } catch { Write-Host "Erreur : $_" }
  }
} finally { $listener.Stop() }
