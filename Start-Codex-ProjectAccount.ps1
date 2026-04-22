[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$AccountName,
    [string]$ProjectPath = (Get-Location).Path,
    [string]$CodexHomeRoot = "$HOME\\.codex-accounts"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-PlainTextFromSecureString {
    param(
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$SecureString
    )

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Get-CodexExecutable {
    $launcherRoot = $null
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $launcherRoot = [IO.Path]::GetFullPath($PSScriptRoot)
    }

    $resolvedRealCommand = Get-Command codex-real.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $resolvedRealCommand -or [string]::IsNullOrWhiteSpace($resolvedRealCommand.Source)) {
        $resolvedRealCommand = Get-Command codex-real -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    if ($null -ne $resolvedRealCommand -and -not [string]::IsNullOrWhiteSpace($resolvedRealCommand.Source)) {
        return [IO.Path]::GetFullPath($resolvedRealCommand.Source)
    }

    $resolvedCommands = @(Get-Command codex -All -ErrorAction SilentlyContinue)
    foreach ($resolvedCommand in $resolvedCommands) {
        $resolvedPath = $resolvedCommand.Source
        if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
            continue
        }

        $resolvedPath = [IO.Path]::GetFullPath($resolvedPath)
        if ($null -ne $launcherRoot -and $resolvedPath.StartsWith($launcherRoot, [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if ([IO.Path]::GetFileNameWithoutExtension($resolvedPath).Equals("codex-real", [StringComparison]::OrdinalIgnoreCase)) {
            return $resolvedPath
        }

        if ([IO.Path]::GetFileNameWithoutExtension($resolvedPath).Equals("codex", [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        return $resolvedPath
    }

    throw "Could not find a Codex executable. Install Codex CLI first."
}

function Test-CodexSupportsDeviceAuth {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CodexExecutable
    )

    $helpOutput = & $CodexExecutable login --help 2>&1
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    return ($helpOutput | Out-String) -match "--device-auth"
}

function Select-LoginMethod {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$SupportsDeviceAuth
    )

    if (-not $SupportsDeviceAuth) {
        return "api-key"
    }

    while ($true) {
        Write-Host "Choose how to authenticate this account:"
        Write-Host "  1. Sign in with ChatGPT (recommended for ChatGPT Business)"
        Write-Host "  2. Use an OpenAI API key"
        Write-Host ""

        $selection = (Read-Host "Choose 1 or 2 (Enter for 1)").Trim()
        if ([string]::IsNullOrWhiteSpace($selection) -or $selection -eq "1") {
            return "device-auth"
        }

        if ($selection -eq "2") {
            return "api-key"
        }

        Write-Host "Invalid selection. Enter 1, 2, or press Enter for 1." -ForegroundColor Yellow
        Write-Host ""
    }
}

$accountProfiles = @(
    [pscustomobject]@{
        MenuOption = "1"
        Label = "Aleph General"
        Slug = "aleph-general"
        HomePath = (Join-Path $HOME ".codex")
        Aliases = @("1", "aleph general", "aleph-general", "general")
    },
    [pscustomobject]@{
        MenuOption = "2"
        Label = "GTB"
        Slug = "gtb"
        HomePath = (Join-Path $HOME ".codex-second")
        Aliases = @("2", "gtb", "aleph / gtb", "aleph-gtb", "aleph gtb")
    },
    [pscustomobject]@{
        MenuOption = "3"
        Label = "IE - Imagined Earth"
        Slug = "ie-imagined-earth"
        HomePath = $null
        Aliases = @("3", "ie", "imagined earth", "ie - imagined earth", "ie-imagined-earth")
    }
)

function Select-AccountProfile {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Profiles
    )

    while ($true) {
        Write-Host ""
        Write-Host "Select the Codex account to use:"
        foreach ($profile in $Profiles) {
            Write-Host ("  {0}. {1}" -f $profile.MenuOption, $profile.Label)
        }
        Write-Host ""

        $selection = (Read-Host "Choose 1, 2, or 3").Trim()
        $matchedProfile = $Profiles | Where-Object { $_.MenuOption -eq $selection } | Select-Object -First 1
        if ($null -ne $matchedProfile) {
            return $matchedProfile
        }

        Write-Host "Invalid selection. Enter 1, 2, or 3." -ForegroundColor Yellow
    }
}

function Resolve-AccountProfile {
    param(
        [string]$RequestedAccountName,
        [Parameter(Mandatory = $true)]
        [object[]]$Profiles
    )

    if ([string]::IsNullOrWhiteSpace($RequestedAccountName)) {
        return Select-AccountProfile -Profiles $Profiles
    }

    $normalizedRequestedAccountName = $RequestedAccountName.Trim().ToLowerInvariant()
    foreach ($profile in $Profiles) {
        if ($profile.Aliases -contains $normalizedRequestedAccountName) {
            return $profile
        }
    }

    $customSlug = ($RequestedAccountName -replace "[^A-Za-z0-9._-]", "-").Trim("-")
    if ([string]::IsNullOrWhiteSpace($customSlug)) {
        throw "AccountName must contain at least one letter or number."
    }

    return [pscustomobject]@{
        MenuOption = ""
        Label = $RequestedAccountName
        Slug = $customSlug
        HomePath = $null
        Aliases = @($normalizedRequestedAccountName)
    }
}

function Invoke-StartCodexProjectAccount {
    param(
        [string]$AccountName,
        [string]$ProjectPath,
        [string]$CodexHomeRoot,
        [string[]]$CliArgs = @()
    )

    $resolvedProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
    $selectedAccount = Resolve-AccountProfile -RequestedAccountName $AccountName -Profiles $accountProfiles
    $displayAccountName = $selectedAccount.Label
    $safeAccountName = $selectedAccount.Slug
    $codexExecutable = Get-CodexExecutable
    $supportsDeviceAuth = Test-CodexSupportsDeviceAuth -CodexExecutable $codexExecutable
    $isLoginCommand = $CliArgs.Count -gt 0 -and $CliArgs[0] -eq "login"

    $accountHome = $selectedAccount.HomePath
    if ([string]::IsNullOrWhiteSpace($accountHome)) {
        $accountHome = Join-Path $CodexHomeRoot $safeAccountName
    }
    $primaryCodexHome = Join-Path $HOME ".codex"
    $primaryConfig = Join-Path $primaryCodexHome "config.toml"
    $accountConfig = Join-Path $accountHome "config.toml"
    $accountAuth = Join-Path $accountHome "auth.json"
    $authWasMissing = -not (Test-Path -LiteralPath $accountAuth)

    New-Item -ItemType Directory -Force -Path $accountHome | Out-Null

    if ((Test-Path -LiteralPath $primaryConfig) -and -not (Test-Path -LiteralPath $accountConfig)) {
        Copy-Item -LiteralPath $primaryConfig -Destination $accountConfig
    }

    if ($authWasMissing) {
        Write-Host ""
        Write-Host "No Codex login is stored yet for account '$displayAccountName'."
        Write-Host "A separate auth cache will be created in:"
        Write-Host "  $accountHome"
        Write-Host ""

        $loginMethod = Select-LoginMethod -SupportsDeviceAuth $supportsDeviceAuth

        $previousCodexHome = $env:CODEX_HOME
        $plainApiKey = $null
        try {
            $env:CODEX_HOME = $accountHome
            if ($loginMethod -eq "device-auth") {
                & $codexExecutable login --device-auth
            } else {
                $secureApiKey = Read-Host "Paste the OpenAI API key for this account" -AsSecureString
                $plainApiKey = Get-PlainTextFromSecureString -SecureString $secureApiKey
                if ([string]::IsNullOrWhiteSpace($plainApiKey)) {
                    throw "No API key was provided."
                }

                $plainApiKey | & $codexExecutable login --with-api-key
            }

            if ($LASTEXITCODE -ne 0) {
                throw "Codex login failed for account '$displayAccountName'."
            }
        } finally {
            $plainApiKey = $null
            if ($null -eq $previousCodexHome) {
                Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
            } else {
                $env:CODEX_HOME = $previousCodexHome
            }
        }
    }

    if ($isLoginCommand -and $authWasMissing) {
        return 0
    }

    $previousCodexHome = $env:CODEX_HOME
    $exitCode = 0
    try {
        $env:CODEX_HOME = $accountHome
        Push-Location -LiteralPath $resolvedProjectPath
        & $codexExecutable @CliArgs
        if ($null -ne $LASTEXITCODE) {
            $exitCode = $LASTEXITCODE
        }
    } finally {
        Pop-Location
        if ($null -eq $previousCodexHome) {
            Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
        } else {
            $env:CODEX_HOME = $previousCodexHome
        }
    }

    return $exitCode
}

if ($MyInvocation.InvocationName -ne ".") {
    $forwardedCliArgs = @($MyInvocation.UnboundArguments)
    $scriptExitCode = Invoke-StartCodexProjectAccount -AccountName $AccountName -ProjectPath $ProjectPath -CodexHomeRoot $CodexHomeRoot -CliArgs $forwardedCliArgs
    exit $scriptExitCode
}
