param(
    [string]$InstallRoot = "$HOME\.codex-launcher"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$sourceLauncherPath = Join-Path $PSScriptRoot "Start-Codex-ProjectAccount.ps1"
if (-not (Test-Path -LiteralPath $sourceLauncherPath)) {
    throw "Launcher not found at $sourceLauncherPath"
}

function Add-UserPathEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathEntry
    )

    $normalizedPathEntry = [IO.Path]::GetFullPath($PathEntry).TrimEnd('\')
    $existingEntries = @(
        [Environment]::GetEnvironmentVariable("Path", "User") -split ';' |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    foreach ($existingEntry in $existingEntries) {
        $normalizedExistingEntry = [IO.Path]::GetFullPath($existingEntry).TrimEnd('\')
        if ($normalizedExistingEntry.Equals($normalizedPathEntry, [StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }

    $updatedEntries = @($normalizedPathEntry) + $existingEntries
    $updatedPath = ($updatedEntries -join ';').Trim(';')
    [Environment]::SetEnvironmentVariable("Path", $updatedPath, "User")
    return $true
}

$resolvedInstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$binDir = Join-Path $resolvedInstallRoot "bin"
$installedLauncherPath = Join-Path $resolvedInstallRoot "Start-Codex-ProjectAccount.ps1"

New-Item -ItemType Directory -Force -Path $resolvedInstallRoot | Out-Null
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

Copy-Item -LiteralPath $sourceLauncherPath -Destination $installedLauncherPath -Force

$codexCmdPath = Join-Path $binDir "codex.cmd"
$codexPs1Path = Join-Path $binDir "codex.ps1"
$codexShPath = Join-Path $binDir "codex"

$cmdWrapper = @"
@ECHO off
SETLOCAL
PowerShell -ExecutionPolicy Bypass -File "$installedLauncherPath" %*
EXIT /b %ERRORLEVEL%
"@

$ps1Wrapper = @"
#!/usr/bin/env pwsh
& "$installedLauncherPath" @args
exit `$LASTEXITCODE
"@

$shWrapper = @"
#!/bin/sh
exec powershell.exe -ExecutionPolicy Bypass -File "$installedLauncherPath" "\$@"
"@

Set-Content -LiteralPath $codexCmdPath -Value $cmdWrapper -NoNewline
Set-Content -LiteralPath $codexPs1Path -Value $ps1Wrapper -NoNewline
Set-Content -LiteralPath $codexShPath -Value $shWrapper -NoNewline

$pathUpdated = Add-UserPathEntry -PathEntry $binDir

Write-Host "Installed persistent Codex launchers:"
Write-Host "  Launcher root: $resolvedInstallRoot"
Write-Host "  $codexCmdPath"
Write-Host "  $codexPs1Path"
Write-Host "  $codexShPath"
Write-Host ""
if ($pathUpdated) {
    Write-Host "Added '$binDir' to the user PATH."
    Write-Host "Open a new terminal before running 'codex' so the new PATH entry is loaded."
} else {
    Write-Host "'$binDir' is already present in the user PATH."
}
Write-Host ""
Write-Host "Typing 'codex' now opens the interactive account selector without modifying npm-managed Codex files."
