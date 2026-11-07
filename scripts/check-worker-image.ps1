<#
.SYNOPSIS
  Pre-upgrade gate: does ghcr.io/yoyoithink/warmbly-worker:<tag> exist?

.DESCRIPTION
  Run this BEFORE changing WARMBLY_TAG in Coolify. Exit code 0 = the patched
  worker for that tag is published, safe to bump. Exit code 1 = not published
  (build failed, not built yet, or the package is private): do not bump yet.
  Needs no login (the GHCR package must be Public) and no tools besides PowerShell.

.EXAMPLE
  .\check-worker-image.ps1 v0.6.78
#>
param(
  [Parameter(Mandatory = $true)][string]$Tag
)

$ErrorActionPreference = 'Stop'
$repo = 'yoyoithink/warmbly-worker'
$actions = 'https://github.com/yoyoithink/warmbly-worker-patch/actions/workflows/build-worker.yml'

if ($Tag -notmatch '^v\d+\.\d+\.\d+$') {
  Write-Host "Tag must look like v0.6.78, got '$Tag'" -ForegroundColor Red
  exit 2
}

try {
  $tok = (Invoke-RestMethod -Uri "https://ghcr.io/token?service=ghcr.io&scope=repository:${repo}:pull").token
  $hdr = @{
    Authorization = "Bearer $tok"
    Accept        = 'application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'
  }
  $r = Invoke-WebRequest -Method Head -Uri "https://ghcr.io/v2/$repo/manifests/$Tag" -Headers $hdr -UseBasicParsing
  $digest = $r.Headers['Docker-Content-Digest']
  Write-Host "OK  ghcr.io/${repo}:$Tag exists  ($digest)" -ForegroundColor Green
  Write-Host "    Safe to set WARMBLY_TAG=$Tag in Coolify."
  exit 0
}
catch {
  $code = $null
  if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
  Write-Host "MISSING  ghcr.io/${repo}:$Tag (HTTP $code)" -ForegroundColor Red
  Write-Host "  Do NOT bump WARMBLY_TAG yet. Build it:"
  Write-Host "    1. Open $actions"
  Write-Host "    2. Run workflow -> tag = $Tag"
  Write-Host "    3. Wait for green, then run this script again."
  Write-Host "  If the run fails at 'Apply the source patch', the patch needs a rebase (see RUNBOOK.md)."
  Write-Host "  HTTP 401/403/404 right after a green run usually means the package is still Private."
  exit 1
}
