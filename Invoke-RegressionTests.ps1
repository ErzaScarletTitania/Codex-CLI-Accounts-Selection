param(
    [string]$Path = (Join-Path $PSScriptRoot "tests")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-Module -ListAvailable -Name Pester)) {
    throw "Pester is required to run the regression suite. Install it with: Install-Module Pester -Scope CurrentUser"
}

Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop
$testResult = Invoke-Pester -Path $Path -PassThru

if ($testResult.FailedCount -gt 0) {
    exit 1
}

exit 0
