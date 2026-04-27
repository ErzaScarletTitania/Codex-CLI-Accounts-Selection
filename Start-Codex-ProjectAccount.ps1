[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$AccountName,
    [string]$ProjectPath = (Get-Location).Path,
    [string]$CodexHomeRoot = "$HOME\\.codex-accounts",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CliArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-PSNativeCommandErrorPreferenceState {
    if (Test-Path Variable:PSNativeCommandUseErrorActionPreference) {
        return [pscustomobject]@{
            Exists = $true
            Value = $PSNativeCommandUseErrorActionPreference
        }
    }

    return [pscustomobject]@{
        Exists = $false
        Value = $null
    }
}

function Set-PSNativeCommandErrorPreference {
    param(
        [bool]$Enabled
    )

    Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $Enabled -Scope Script
}

function Restore-PSNativeCommandErrorPreferenceState {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    if ($State.Exists) {
        Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $State.Value -Scope Script
    } else {
        Remove-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Script -ErrorAction SilentlyContinue
    }
}

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

function Invoke-CodexCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CodexExecutable,
        [string[]]$Arguments = @(),
        [switch]$RedirectStderr
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"

        $extension = [IO.Path]::GetExtension($CodexExecutable)
        if ($extension.Equals(".cmd", [StringComparison]::OrdinalIgnoreCase) -or
            $extension.Equals(".bat", [StringComparison]::OrdinalIgnoreCase)) {
            if ($RedirectStderr) {
                $quotedExecutable = '"' + $CodexExecutable.Replace('"', '""') + '"'
                $quotedArguments = @(
                    foreach ($argument in $Arguments) {
                        '"' + $argument.Replace('"', '""') + '"'
                    }
                )
                $commandLine = (($quotedExecutable) + ' ' + ($quotedArguments -join ' ') + ' 2>&1').Trim()
                return & cmd.exe /d /c $commandLine
            }

            return & $CodexExecutable @Arguments
        }

        if ($RedirectStderr) {
            return & $CodexExecutable @Arguments 2>&1
        }

        return & $CodexExecutable @Arguments
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function Invoke-CodexCommandWithStdin {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CodexExecutable,
        [Parameter(Mandatory = $true)]
        [string]$StandardInput,
        [string[]]$Arguments = @()
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"

        $extension = [IO.Path]::GetExtension($CodexExecutable)
        if ($extension.Equals(".cmd", [StringComparison]::OrdinalIgnoreCase) -or
            $extension.Equals(".bat", [StringComparison]::OrdinalIgnoreCase)) {
            $quotedExecutable = '"' + $CodexExecutable.Replace('"', '""') + '"'
            $quotedArguments = @(
                foreach ($argument in $Arguments) {
                    '"' + $argument.Replace('"', '""') + '"'
                }
            )
            $commandLine = (($quotedExecutable) + ' ' + ($quotedArguments -join ' ')).Trim()
            return $StandardInput | & cmd.exe /d /c $commandLine
        }

        return $StandardInput | & $CodexExecutable @Arguments
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function ConvertTo-CmdQuotedArgument {
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if ($null -eq $Value) {
        return '""'
    }

    return '"' + $Value.Replace('"', '""') + '"'
}

function Invoke-CodexCommandInCmdSession {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CodexExecutable,
        [Parameter(Mandatory = $true)]
        [string]$CodexHome,
        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,
        [string[]]$Arguments = @()
    )

    $quotedExecutable = ConvertTo-CmdQuotedArgument -Value $CodexExecutable
    $quotedWorkingDirectory = ConvertTo-CmdQuotedArgument -Value $WorkingDirectory
    $quotedCodexHome = ConvertTo-CmdQuotedArgument -Value $CodexHome
    $quotedArguments = @(
        foreach ($argument in $Arguments) {
            ConvertTo-CmdQuotedArgument -Value $argument
        }
    )

    $commandSegments = @(
        'setlocal'
        ('cd /d ' + $quotedWorkingDirectory)
        ('set "CODEX_HOME=' + $CodexHome.Replace('"', '""') + '"')
        (($quotedExecutable + ' ' + ($quotedArguments -join ' ')).Trim())
    )

    $commandLine = $commandSegments -join ' && '
    & cmd.exe /d /c $commandLine
    return $LASTEXITCODE
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
    $candidatePaths = @()
    foreach ($resolvedCommand in $resolvedCommands) {
        $resolvedPath = $resolvedCommand.Source
        if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
            continue
        }

        $resolvedPath = [IO.Path]::GetFullPath($resolvedPath)
        if ($null -ne $launcherRoot -and $resolvedPath.StartsWith($launcherRoot, [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        $candidatePaths += $resolvedPath
    }

    $preferredCandidate = $candidatePaths |
        Sort-Object {
            switch ([IO.Path]::GetExtension($_).ToLowerInvariant()) {
                ".cmd" { 0; break }
                ".exe" { 1; break }
                ".bat" { 2; break }
                ".ps1" { 3; break }
                default { 4; break }
            }
        } |
        Select-Object -First 1

    if (-not [string]::IsNullOrWhiteSpace($preferredCandidate)) {
        return $preferredCandidate
    }

    throw "Could not find a Codex executable. Install Codex CLI first."
}

function Test-CodexSupportsDeviceAuth {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CodexExecutable
    )

    $previousNativeErrorPreference = Get-PSNativeCommandErrorPreferenceState
    try {
        Set-PSNativeCommandErrorPreference -Enabled $false
        $helpOutput = Invoke-CodexCommand -CodexExecutable $CodexExecutable -Arguments @("login", "--help") -RedirectStderr
    } finally {
        Restore-PSNativeCommandErrorPreferenceState -State $previousNativeErrorPreference
    }
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
    $normalizedCliArgs = @($CliArgs)
    $selectedAccount = Resolve-AccountProfile -RequestedAccountName $AccountName -Profiles $accountProfiles
    $displayAccountName = $selectedAccount.Label
    $safeAccountName = $selectedAccount.Slug
    $codexExecutable = Get-CodexExecutable
    $supportsDeviceAuth = Test-CodexSupportsDeviceAuth -CodexExecutable $codexExecutable
    $isLoginCommand = $normalizedCliArgs.Count -gt 0 -and $normalizedCliArgs[0] -eq "login"

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
        $previousNativeErrorPreference = Get-PSNativeCommandErrorPreferenceState
        try {
            $env:CODEX_HOME = $accountHome
            Set-PSNativeCommandErrorPreference -Enabled $false
            if ($loginMethod -eq "device-auth") {
                $loginExitCode = Invoke-CodexCommandInCmdSession -CodexExecutable $codexExecutable -CodexHome $accountHome -WorkingDirectory $resolvedProjectPath -Arguments @("login", "--device-auth")
                $global:LASTEXITCODE = $loginExitCode
            } else {
                $secureApiKey = Read-Host "Paste the OpenAI API key for this account" -AsSecureString
                $plainApiKey = Get-PlainTextFromSecureString -SecureString $secureApiKey
                if ([string]::IsNullOrWhiteSpace($plainApiKey)) {
                    throw "No API key was provided."
                }

                Invoke-CodexCommandWithStdin -CodexExecutable $codexExecutable -StandardInput $plainApiKey -Arguments @("login", "--with-api-key")
            }

            if ($LASTEXITCODE -ne 0) {
                throw "Codex login failed for account '$displayAccountName'."
            }
        } finally {
            $plainApiKey = $null
            Restore-PSNativeCommandErrorPreferenceState -State $previousNativeErrorPreference
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
    $previousNativeErrorPreference = Get-PSNativeCommandErrorPreferenceState
    $exitCode = 0
    try {
        $env:CODEX_HOME = $accountHome
        Set-PSNativeCommandErrorPreference -Enabled $false
        Push-Location -LiteralPath $resolvedProjectPath
        $exitCode = Invoke-CodexCommandInCmdSession -CodexExecutable $codexExecutable -CodexHome $accountHome -WorkingDirectory $resolvedProjectPath -Arguments $normalizedCliArgs
        $global:LASTEXITCODE = $exitCode
    } finally {
        Restore-PSNativeCommandErrorPreferenceState -State $previousNativeErrorPreference
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
    $scriptExitCode = Invoke-StartCodexProjectAccount -AccountName $AccountName -ProjectPath $ProjectPath -CodexHomeRoot $CodexHomeRoot -CliArgs @($CliArgs)
    exit $scriptExitCode
}
