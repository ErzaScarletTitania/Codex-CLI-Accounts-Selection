BeforeAll {
    . (Join-Path $PSScriptRoot "..\Install-CodexLauncher.ps1")
}

Describe "Get-UserPathUpdate" {
    It "prepends a missing path entry" {
        $result = Get-UserPathUpdate -CurrentPath "C:\Tools;C:\Windows" -PathEntry "C:\Users\lglez\bin"

        $result.WasAdded | Should -BeTrue
        $result.UpdatedPath | Should -Be "C:\Users\lglez\bin;C:\Tools;C:\Windows"
    }

    It "does not duplicate an existing path entry" {
        $result = Get-UserPathUpdate -CurrentPath "C:\Users\lglez\bin\;C:\Tools" -PathEntry "C:\USERS\LGLEZ\bin"

        $result.WasAdded | Should -BeFalse
        $result.UpdatedPath | Should -Be "C:\Users\lglez\bin\;C:\Tools"
    }
}

Describe "Invoke-InstallCodexLauncher" {
    BeforeEach {
        Mock Add-UserPathEntry { $true }
        Mock Write-Host {}
    }

    It "installs the launcher and command wrappers into the target directory" {
        $installRoot = Join-Path $TestDrive "launcher"

        Invoke-InstallCodexLauncher -InstallRoot $installRoot

        Test-Path -LiteralPath (Join-Path $installRoot "Start-Codex-ProjectAccount.ps1") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $installRoot "Start-Codex-ProjectAccount.cmd") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $installRoot "bin\codex.cmd") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $installRoot "bin\codex.ps1") | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $installRoot "bin\codex") | Should -BeTrue
        Assert-MockCalled Add-UserPathEntry -Times 1 -Exactly -ParameterFilter {
            $PathEntry -eq (Join-Path $installRoot "bin")
        }
    }

    It "points the installed cmd wrapper at the native cmd launcher" {
        $installRoot = Join-Path $TestDrive "launcher"

        Invoke-InstallCodexLauncher -InstallRoot $installRoot

        $wrapperContent = Get-Content -LiteralPath (Join-Path $installRoot "bin\codex.cmd") -Raw

        $expectedLauncherPath = [regex]::Escape((Join-Path $installRoot "Start-Codex-ProjectAccount.cmd"))
        $wrapperContent | Should -Match $expectedLauncherPath
    }
}
