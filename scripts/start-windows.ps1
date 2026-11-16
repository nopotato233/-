[CmdletBinding()]
param(
    [ValidateRange(1, 65535)][int]$Port = 8000,
    [string]$ListenAddress = '127.0.0.1',
    [string]$CertFile = '',
    [string]$KeyFile = '',
    [switch]$NoBrowser
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$BrowserJob = $null
Push-Location $ProjectRoot
try {
    if (($CertFile -eq '') -ne ($KeyFile -eq '')) {
        throw 'CertFile and KeyFile must be supplied together.'
    }
    if ($CertFile -ne '' -and (!(Test-Path $CertFile) -or !(Test-Path $KeyFile))) {
        throw 'The TLS certificate or private key does not exist.'
    }
    $VenvPython = Join-Path $ProjectRoot '.venv\Scripts\python.exe'
    if (!(Test-Path $VenvPython)) {
        if (Get-Command py -ErrorAction SilentlyContinue) {
            & py -3.12 -m venv .venv
        } elseif (Get-Command python -ErrorAction SilentlyContinue) {
            & python -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)'
            if ($LASTEXITCODE -ne 0) { throw 'Install Python 3.12 or newer first.' }
            & python -m venv .venv
        } else { throw 'Install Python 3.12 (including the py launcher) first.' }
        if ($LASTEXITCODE -ne 0) { throw 'Unable to create the Python environment.' }
    }
    & $VenvPython -m pip install -r mobile_demo/requirements.txt
    if ($LASTEXITCODE -ne 0) { throw 'Dependency installation failed.' }

    $ServerArgs = @('-m', 'uvicorn', 'mobile_demo.app:app', '--host', $ListenAddress, '--port', "$Port")
    $Scheme = 'http'
    if ($CertFile -ne '') {
        $Scheme = 'https'
        $ServerArgs += @('--ssl-certfile', $CertFile, '--ssl-keyfile', $KeyFile)
    }
    $BrowserHost = if ($ListenAddress -eq '0.0.0.0' -or $ListenAddress -eq '::') { 'localhost' } else { $ListenAddress }
    if ($BrowserHost.Contains(':')) { $BrowserHost = "[$BrowserHost]" }
    $AppUrl = "${Scheme}://${BrowserHost}:$Port/"
    Write-Host "Tanbu is starting at $AppUrl"
    Write-Host 'For Android, use this PC LAN address with trusted HTTPS. Keep this terminal open.'
    if (!$NoBrowser) {
        $BrowserJob = Start-Job -ArgumentList $AppUrl -ScriptBlock {
            param($TargetUrl)
            for ($Attempt = 0; $Attempt -lt 40; $Attempt++) {
                try {
                    $Response = Invoke-WebRequest -Uri "${TargetUrl}health" -UseBasicParsing -TimeoutSec 1
                    if ($Response.StatusCode -eq 200) { Start-Process $TargetUrl; return }
                } catch { Start-Sleep -Milliseconds 500 }
            }
        }
    }
    & $VenvPython @ServerArgs
    if ($LASTEXITCODE -ne 0) { throw 'The server stopped with an error. Check the log above.' }
} finally {
    if ($null -ne $BrowserJob) {
        Stop-Job $BrowserJob -ErrorAction SilentlyContinue
        Remove-Job $BrowserJob -Force -ErrorAction SilentlyContinue
    }
    Pop-Location
}
