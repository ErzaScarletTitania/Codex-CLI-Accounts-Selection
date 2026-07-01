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

function Normalize-PathEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $trimmedValue = $Value.Trim().Trim('"')
    if ([string]::IsNullOrWhiteSpace($trimmedValue)) {
        return $null
    }

    try {
        return [IO.Path]::GetFullPath($trimmedValue).TrimEnd('\')
    } catch {
        return $trimmedValue.TrimEnd('\')
    }
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

    $normalizedPathEntry = Normalize-PathEntry -Value $PathEntry
    if ([string]::IsNullOrWhiteSpace($normalizedPathEntry)) {
        throw "PathEntry cannot be empty."
    }

    $existingEntries = @(
        $CurrentPath -split ';' |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    foreach ($existingEntry in $existingEntries) {
        $normalizedExistingEntry = Normalize-PathEntry -Value $existingEntry
        if ([string]::IsNullOrWhiteSpace($normalizedExistingEntry)) {
            continue
        }
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

function New-CodexCmdWrapperContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstalledLauncherPs1Path,
        [Parameter(Mandatory = $true)]
        [string]$InstalledLauncherCmdPath
    )

@"
@ECHO off
SETLOCAL
SET "CODEX_HAS_ACCOUNT_ARG="
FOR %%A IN (%*) DO (
  IF /I "%%~A"=="-AccountName" SET "CODEX_HAS_ACCOUNT_ARG=1"
)
IF DEFINED CODEX_HAS_ACCOUNT_ARG (
  powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$InstalledLauncherPs1Path" %*
) ELSE (
  CALL "$InstalledLauncherCmdPath" %*
)
EXIT /b %ERRORLEVEL%
"@
}

function New-CodexPs1WrapperContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstalledLauncherPs1Path
    )

@"
#!/usr/bin/env pwsh
`$launcherArgs = @args
`$hasExplicitAccountArgument = `$false
foreach (`$argument in `$launcherArgs) {
    if (`$argument -eq '-AccountName') {
        `$hasExplicitAccountArgument = `$true
        break
    }
}

if (-not `$hasExplicitAccountArgument) {
    while (`$true) {
        Write-Host ''
        Write-Host 'Select the Codex account to use:'
        Write-Host '  1. Aleph General'
        Write-Host '  2. GTB'
        Write-Host '  3. IE - Imagined Earth'
        Write-Host ''
        `$selection = (Read-Host 'Choose 1, 2, or 3').Trim()
        if (`$selection -in @('1', '2', '3')) {
            `$launcherArgs = @('-AccountName', `$selection) + `$launcherArgs
            break
        }

        Write-Host 'Invalid selection. Enter 1, 2, or 3.' -ForegroundColor Yellow
    }
}

& "$InstalledLauncherPs1Path" @launcherArgs
exit `$LASTEXITCODE
"@
}

function New-CodexShWrapperContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstalledLauncherPs1Path
    )

@"
#!/bin/sh
set -eu

if command -v pwsh.exe >/dev/null 2>&1; then
  powershell_exe='pwsh.exe'
elif command -v powershell.exe >/dev/null 2>&1; then
  powershell_exe='powershell.exe'
else
  echo "Could not find PowerShell. Install PowerShell or Windows PowerShell first." >&2
  exit 1
fi

has_explicit_account_arg=0
for arg in "`$@"; do
  case "`$arg" in
    -AccountName)
      has_explicit_account_arg=1
      break
      ;;
  esac
done

if [ "`$has_explicit_account_arg" -eq 0 ]; then
  while :; do
    printf '\n'
    printf 'Select the Codex account to use:\n'
    printf '  1. Aleph General\n'
    printf '  2. GTB\n'
    printf '  3. IE - Imagined Earth\n\n'
    printf 'Choose 1, 2, or 3: '
    IFS= read -r selection || selection=''
    case "`$selection" in
      1|2|3)
        set -- -AccountName "`$selection" "`$@"
        break
        ;;
      *)
        printf 'Invalid selection. Enter 1, 2, or 3.\n\n' >&2
        ;;
    esac
  done
fi

if [ -t 0 ] && command -v winpty >/dev/null 2>&1; then
  exec winpty "`$powershell_exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$InstalledLauncherPs1Path" "`$@"
fi

exec "`$powershell_exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$InstalledLauncherPs1Path" "`$@"
"@
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

    Set-Content -LiteralPath $codexCmdPath -Value (New-CodexCmdWrapperContent -InstalledLauncherPs1Path $installedLauncherPs1Path -InstalledLauncherCmdPath $installedLauncherCmdPath) -NoNewline
    Set-Content -LiteralPath $codexPs1Path -Value (New-CodexPs1WrapperContent -InstalledLauncherPs1Path $installedLauncherPs1Path) -NoNewline
    Set-Content -LiteralPath $codexShPath -Value (New-CodexShWrapperContent -InstalledLauncherPs1Path $installedLauncherPs1Path) -NoNewline

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
