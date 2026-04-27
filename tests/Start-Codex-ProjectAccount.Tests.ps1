BeforeAll {
    . (Join-Path $PSScriptRoot "..\Start-Codex-ProjectAccount.ps1")
}

Describe "Resolve-AccountProfile" {
    It "matches built-in aliases" {
        $profile = Resolve-AccountProfile -RequestedAccountName "aleph gtb" -Profiles $accountProfiles

        $profile.Label | Should -Be "GTB"
        $profile.Slug | Should -Be "gtb"
    }

    It "creates a sanitized custom profile" {
        $profile = Resolve-AccountProfile -RequestedAccountName "Team Ops" -Profiles $accountProfiles

        $profile.Label | Should -Be "Team Ops"
        $profile.Slug | Should -Be "Team-Ops"
        $profile.HomePath | Should -Be $null
    }

    It "rejects account names without letters or numbers" {
        {
            Resolve-AccountProfile -RequestedAccountName "@@@@" -Profiles $accountProfiles
        } | Should -Throw "AccountName must contain at least one letter or number."
    }
}

Describe "Select-LoginMethod" {
    BeforeEach {
        Mock Write-Host {}
    }

    It "falls back to API key when device auth is unavailable" {
        Select-LoginMethod -SupportsDeviceAuth $false | Should -Be "api-key"
    }

    It "defaults to device auth when the user presses Enter" {
        Mock Read-Host { "" }

        Select-LoginMethod -SupportsDeviceAuth $true | Should -Be "device-auth"
    }

    It "retries invalid selections until a valid option is entered" {
        $script:selectionReadCount = 0
        Mock Read-Host {
            $script:selectionReadCount += 1
            if ($script:selectionReadCount -eq 1) {
                return "9"
            }

            return "2"
        }

        Select-LoginMethod -SupportsDeviceAuth $true | Should -Be "api-key"
    }
}

Describe "Get-CodexExecutable" {
    It "prefers codex-real.cmd when it is available" {
        $expectedExecutable = [IO.Path]::GetFullPath("C:\Tools\codex-real.cmd")

        Mock Get-Command {
            [pscustomobject]@{ Source = $expectedExecutable }
        } -ParameterFilter { $Name -eq "codex-real.cmd" }

        Get-CodexExecutable | Should -Be $expectedExecutable
    }

    It "falls back to the first non-launcher codex command" {
        $script:expectedExecutable = [IO.Path]::GetFullPath("C:\Users\tester\AppData\Roaming\npm\codex.cmd")
        $script:launcherExecutable = Join-Path $PSScriptRoot "..\codex.cmd"

        Mock Get-Command { $null } -ParameterFilter { $Name -eq "codex-real.cmd" }
        Mock Get-Command { $null } -ParameterFilter { $Name -eq "codex-real" }
        Mock Get-Command {
            @(
                [pscustomobject]@{ Source = $script:launcherExecutable }
                [pscustomobject]@{ Source = $script:expectedExecutable }
            )
        } -ParameterFilter { $Name -eq "codex" -and $All }

        Get-CodexExecutable | Should -Be $script:expectedExecutable
    }
}

Describe "Test-CodexSupportsDeviceAuth" {
    It "returns true when login help advertises device auth" {
        function TestCodexWithDeviceAuth {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

            $global:LASTEXITCODE = 0
            return @"
Usage: codex login
  --device-auth
"@
        }

        Test-CodexSupportsDeviceAuth -CodexExecutable "TestCodexWithDeviceAuth" | Should -BeTrue
    }

    It "returns false when the help command fails" {
        function BrokenCodexLoginHelp {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

            $global:LASTEXITCODE = 1
            return "login help failed"
        }

        Test-CodexSupportsDeviceAuth -CodexExecutable "BrokenCodexLoginHelp" | Should -BeFalse
    }
}
