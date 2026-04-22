param(
    [string]$InstallRoot = "$HOME\.codex-launcher"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$sourceLauncherPs1Path = Join-Path $PSScriptRoot "Start-Codex-ProjectAccount.ps1"
$sourceLauncherCmdPath = Join-Path $PSScriptRoot "Start-Codex-ProjectAccount.cmd"
if (-not (Test-Path -LiteralPath $sourceLauncherPs1Path)) {
    throw "Launcher not found at $sourceLauncherPs1Path"
}
if (-not (Test-Path -LiteralPath $sourceLauncherCmdPath)) {
    throw "Launcher not found at $sourceLauncherCmdPath"
}

function Add-UserPathEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathEntry
    )

    $pathUpdate = Get-UserPathUpdate -CurrentPath ([Environment]::GetEnvironmentVariable("Path", "User")) -PathEntry $PathEntry
    if (-not $pathUpdate.WasAdded) {
        return $false
    }

    [Environment]::SetEnvironmentVariable("Path", $pathUpdate.UpdatedPath, "User")
    return $true
}

function Get-UserPathUpdate {
    param(
        [AllowEmptyString()]
        [string]$CurrentPath,
        [Parameter(Mandatory = $true)]
        [string]$PathEntry
    )

    $normalizedPathEntry = [IO.Path]::GetFullPath($PathEntry).TrimEnd('\')
    $existingEntries = @(
        $CurrentPath -split ';' |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    foreach ($existingEntry in $existingEntries) {
        $normalizedExistingEntry = [IO.Path]::GetFullPath($existingEntry).TrimEnd('\')
        if ($normalizedExistingEntry.Equals($normalizedPathEntry, [StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{
                WasAdded = $false
                UpdatedPath = ($existingEntries -join ';').Trim(';')
            }
        }
    }

    $updatedEntries = @($normalizedPathEntry) + $existingEntries
    return [pscustomobject]@{
        WasAdded = $true
        UpdatedPath = ($updatedEntries -join ';').Trim(';')
    }
}

function Invoke-InstallCodexLauncher {
    param(
        [string]$InstallRoot = "$HOME\.codex-launcher"
    )

    $resolvedInstallRoot = [IO.Path]::GetFullPath($InstallRoot)
    $binDir = Join-Path $resolvedInstallRoot "bin"
    $installedLauncherPs1Path = Join-Path $resolvedInstallRoot "Start-Codex-ProjectAccount.ps1"
    $installedLauncherCmdPath = Join-Path $resolvedInstallRoot "Start-Codex-ProjectAccount.cmd"

    New-Item -ItemType Directory -Force -Path $resolvedInstallRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null

    Copy-Item -LiteralPath $sourceLauncherPs1Path -Destination $installedLauncherPs1Path -Force
    Copy-Item -LiteralPath $sourceLauncherCmdPath -Destination $installedLauncherCmdPath -Force

    $codexCmdPath = Join-Path $binDir "codex.cmd"
    $codexPs1Path = Join-Path $binDir "codex.ps1"
    $codexShPath = Join-Path $binDir "codex"

    $cmdWrapper = @"
@ECHO off
SETLOCAL
CALL "$installedLauncherCmdPath" %*
EXIT /b %ERRORLEVEL%
"@

    $ps1Wrapper = @"
#!/usr/bin/env pwsh
& "$installedLauncherPs1Path" @args
exit `$LASTEXITCODE
"@

    $shWrapper = @"
#!/bin/sh
exec powershell.exe -ExecutionPolicy Bypass -File "$installedLauncherPs1Path" "\$@"
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
}

if ($MyInvocation.InvocationName -ne ".") {
    Invoke-InstallCodexLauncher -InstallRoot $InstallRoot
}
