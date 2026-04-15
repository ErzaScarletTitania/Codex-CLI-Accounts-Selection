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

$accountProfiles = @(
    [pscustomobject]@{
        MenuOption = "1"
        Label = "Aleph General"
        Slug = "aleph-general"
        Aliases = @("1", "aleph general", "aleph-general", "general")
    },
    [pscustomobject]@{
        MenuOption = "2"
        Label = "GTB"
        Slug = "gtb"
        Aliases = @("2", "gtb", "aleph / gtb", "aleph-gtb", "aleph gtb")
    },
    [pscustomobject]@{
        MenuOption = "3"
        Label = "IE - Imagined Earth"
        Slug = "ie-imagined-earth"
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
        Aliases = @($normalizedRequestedAccountName)
    }
}

$resolvedProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$selectedAccount = Resolve-AccountProfile -RequestedAccountName $AccountName -Profiles $accountProfiles
$displayAccountName = $selectedAccount.Label
$safeAccountName = $selectedAccount.Slug

$accountHome = Join-Path $CodexHomeRoot $safeAccountName
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
    Write-Host "The API key will be used only to create a separate auth cache in:"
    Write-Host "  $accountHome"
    Write-Host ""

    $secureApiKey = Read-Host "Paste the OpenAI API key for this account" -AsSecureString
    $plainApiKey = Get-PlainTextFromSecureString -SecureString $secureApiKey
    if ([string]::IsNullOrWhiteSpace($plainApiKey)) {
        throw "No API key was provided."
    }

    $previousCodexHome = $env:CODEX_HOME
    try {
        $env:CODEX_HOME = $accountHome
        $plainApiKey | codex login --with-api-key
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
    & codex @args
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
