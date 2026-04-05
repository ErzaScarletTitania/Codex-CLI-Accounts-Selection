param(
    [string]$AccountName = "project-account",
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

$resolvedProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path
$safeAccountName = ($AccountName -replace "[^A-Za-z0-9._-]", "-").Trim("-")
if ([string]::IsNullOrWhiteSpace($safeAccountName)) {
    throw "AccountName must contain at least one letter or number."
}

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
    Write-Host "No Codex login is stored yet for account '$AccountName'."
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
            throw "Codex login failed for account '$AccountName'."
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
