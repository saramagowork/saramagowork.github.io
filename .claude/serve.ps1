# Servidor local só para pré-visualizar o site. Não vai para o GitHub (.claude/ está no .git/info/exclude).
param(
  [int]$Port = $(if ($env:PORT) { [int]$env:PORT } else { 8765 }),
  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$types = @{
  ".html" = "text/html; charset=utf-8"; ".css" = "text/css; charset=utf-8"; ".js" = "text/javascript; charset=utf-8"
  ".json" = "application/json"; ".md" = "text/plain; charset=utf-8"; ".txt" = "text/plain; charset=utf-8"
  ".mp4" = "video/mp4"; ".webp" = "image/webp"; ".jpg" = "image/jpeg"; ".jpeg" = "image/jpeg"
  ".png" = "image/png"; ".svg" = "image/svg+xml"; ".ico" = "image/x-icon"; ".woff2" = "font/woff2"
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Servindo $Root em http://localhost:$Port/"

while ($listener.IsListening) {
  $context = $listener.GetContext()
  $response = $context.Response
  try {
    $relative = [Uri]::UnescapeDataString($context.Request.Url.AbsolutePath).TrimStart("/")
    $file = Join-Path $Root $relative
    if (Test-Path -LiteralPath $file -PathType Container) { $file = Join-Path $file "index.html" }
    if ($relative -match "\.\." -or -not (Test-Path -LiteralPath $file -PathType Leaf)) {
      $response.StatusCode = 404
      continue
    }

    $bytes = [IO.File]::ReadAllBytes($file)
    $extension = [IO.Path]::GetExtension($file).ToLowerInvariant()
    $contentType = "application/octet-stream"
    if ($types.ContainsKey($extension)) { $contentType = $types[$extension] }
    $response.ContentType = $contentType
    $response.AddHeader("Accept-Ranges", "bytes")
    $response.AddHeader("Cache-Control", "no-store")

    # Vídeos pedem pedaços do arquivo (Range) para tocar em loop.
    $start = 0
    $end = $bytes.Length - 1
    $range = $context.Request.Headers["Range"]
    if ($range -match "^bytes=(\d*)-(\d*)$") {
      if ($Matches[1]) { $start = [int]$Matches[1] }
      if ($Matches[2]) { $end = [Math]::Min([int]$Matches[2], $bytes.Length - 1) }
      $response.StatusCode = 206
      $response.AddHeader("Content-Range", "bytes $start-$end/$($bytes.Length)")
    }
    $count = $end - $start + 1
    $response.ContentLength64 = $count
    $response.OutputStream.Write($bytes, $start, $count)
  } catch {
    # O navegador pode fechar a conexão no meio do envio.
  } finally {
    $response.Close()
  }
}
