param(
    [string]$NpmShimDir = "$HOME\AppData\Roaming\npm"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$launcherPath = Join-Path $PSScriptRoot "Start-Codex-ProjectAccount.ps1"
if (-not (Test-Path -LiteralPath $launcherPath)) {
    throw "Launcher not found at $launcherPath"
}

$codexRealCmd = Join-Path $NpmShimDir "codex-real.cmd"
$codexRealPs1 = Join-Path $NpmShimDir "codex-real.ps1"
if (-not (Test-Path -LiteralPath $codexRealCmd)) {
    throw "Expected Codex CLI wrapper not found at $codexRealCmd"
}
if (-not (Test-Path -LiteralPath $codexRealPs1)) {
    throw "Expected Codex CLI PowerShell wrapper not found at $codexRealPs1"
}

$codexCmdPath = Join-Path $NpmShimDir "codex.cmd"
$codexPs1Path = Join-Path $NpmShimDir "codex.ps1"
$codexShPath = Join-Path $NpmShimDir "codex"

$cmdWrapper = @"
@ECHO off
SETLOCAL
PowerShell -ExecutionPolicy Bypass -File "$launcherPath" %*
EXIT /b %ERRORLEVEL%
"@

$ps1Wrapper = @"
#!/usr/bin/env pwsh
& "$launcherPath" @args
exit `$LASTEXITCODE
"@

$shWrapper = @"
#!/bin/sh
exec powershell.exe -ExecutionPolicy Bypass -File "$launcherPath" "\$@"
"@

Set-Content -LiteralPath $codexCmdPath -Value $cmdWrapper -NoNewline
Set-Content -LiteralPath $codexPs1Path -Value $ps1Wrapper -NoNewline
Set-Content -LiteralPath $codexShPath -Value $shWrapper -NoNewline

Write-Host "Updated global Codex launchers:"
Write-Host "  $codexCmdPath"
Write-Host "  $codexPs1Path"
Write-Host "  $codexShPath"
Write-Host ""
Write-Host "Typing 'codex' now opens the interactive account selector."
