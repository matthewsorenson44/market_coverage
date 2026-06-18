param(
  [int]$Port = 5757
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$url = "http://localhost:$Port"
$chromeProfile = Join-Path $root ".dart_tool\stable_chrome_profile"

Set-Location $root

function Stop-StaleFlutterServer {
  param([int]$PortToClear)

  $connections = netstat -ano |
    Select-String "[:.]$PortToClear\s+.*LISTENING" |
    ForEach-Object {
      $parts = $_.Line.Trim() -split '\s+'
      $parts[-1]
    } |
    Sort-Object -Unique

  foreach ($processId in $connections) {
    if (-not $processId) { continue }

    try {
      $process = Get-Process -Id ([int]$processId) -ErrorAction Stop
      if ($process.ProcessName -in @('dart', 'dartvm', 'dartaotruntime', 'flutter')) {
        Write-Host "Stopping stale Flutter web server on port $PortToClear (PID $processId)."
        Stop-Process -Id ([int]$processId) -Force
      }
    } catch {
      # Process already exited; nothing to do.
    }
  }
}

Stop-StaleFlutterServer -PortToClear $Port

Write-Host "Starting Market Coverage at $url"
Write-Host "Using stable Chrome profile: $chromeProfile"
Write-Host "Use this same launcher/URL for testing so Supabase login stays saved."
Write-Host "If prompted once, log in; future relaunches should restore the session."

New-Item -ItemType Directory -Force -Path $chromeProfile | Out-Null

flutter run `
  -d chrome `
  --web-hostname localhost `
  --web-port $Port `
  --web-browser-flag="--user-data-dir=$chromeProfile"
