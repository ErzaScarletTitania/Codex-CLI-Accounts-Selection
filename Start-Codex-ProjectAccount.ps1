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
    $candidateCommands = @("codex-real", "codex")
    foreach ($candidateCommand in $candidateCommands) {
        $resolvedCommand = Get-Command $candidateCommand -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $resolvedCommand) {
            return $resolvedCommand.Source
        }
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

$resolvedProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$selectedAccount = Resolve-AccountProfile -RequestedAccountName $AccountName -Profiles $accountProfiles
$displayAccountName = $selectedAccount.Label
$safeAccountName = $selectedAccount.Slug
$codexExecutable = Get-CodexExecutable
$supportsDeviceAuth = Test-CodexSupportsDeviceAuth -CodexExecutable $codexExecutable

$accountHome = $selectedAccount.HomePath
if ([string]::IsNullOrWhiteSpace($accountHome)) {
    $accountHome = Join-Path $CodexHomeRoot $safeAccountName
}
$primaryCodexHome = Join-Path $HOME ".codex"
$primaryConfig = Join-Path $primaryCodexHome "config.toml"
$accountConfig = Join-Path $accountHome "config.toml"
$accountAuth = Join-Path $accountHome "auth.json"

New-Item -ItemType Directory -Force -Path $accountHome | Out-Null

if ((Test-Path -LiteralPath $primaryConfig) -and -not (Test-Path -LiteralPath $accountConfig)) {
    Copy-Item -LiteralPath $primaryConfig -Destination $accountConfig
}

if (-not (Test-Path -LiteralPath $accountAuth)) {
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

$previousCodexHome = $env:CODEX_HOME
$exitCode = 0
try {
    $env:CODEX_HOME = $accountHome
    Push-Location -LiteralPath $resolvedProjectPath
    & $codexExecutable @args
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

exit $exitCode
