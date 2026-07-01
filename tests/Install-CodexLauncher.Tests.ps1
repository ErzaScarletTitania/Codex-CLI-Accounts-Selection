. (Join-Path $PSScriptRoot "..\Install-CodexLauncher.ps1")

Describe "Get-UserPathUpdate" {
    It "prepends a missing path entry" {
        $result = Get-UserPathUpdate -CurrentPath "C:\Tools;C:\Windows" -PathEntry "C:\Users\lglez\bin"

        $result.WasAdded | Should Be $true
        $result.UpdatedPath | Should Be "C:\Users\lglez\bin;C:\Tools;C:\Windows"
    }

    It "does not duplicate an existing path entry" {
        $result = Get-UserPathUpdate -CurrentPath "C:\Users\lglez\bin\;C:\Tools" -PathEntry "C:\USERS\LGLEZ\bin"

        $result.WasAdded | Should Be $false
        $result.UpdatedPath | Should Be "C:\Users\lglez\bin\;C:\Tools"
    }

    It "ignores malformed existing path entries instead of failing" {
        $result = Get-UserPathUpdate -CurrentPath '"C:\BadPathSegment;C:\Tools' -PathEntry "C:\Users\lglez\bin"

        $result.WasAdded | Should Be $true
        $result.UpdatedPath | Should Be "C:\Users\lglez\bin;""C:\BadPathSegment;C:\Tools"
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

        Test-Path -LiteralPath (Join-Path $installRoot "Start-Codex-ProjectAccount.ps1") | Should Be $true
        Test-Path -LiteralPath (Join-Path $installRoot "Start-Codex-ProjectAccount.cmd") | Should Be $true
        Test-Path -LiteralPath (Join-Path $installRoot "bin\codex.cmd") | Should Be $true
        Test-Path -LiteralPath (Join-Path $installRoot "bin\codex.ps1") | Should Be $true
        Test-Path -LiteralPath (Join-Path $installRoot "bin\codex") | Should Be $true
        Assert-MockCalled Add-UserPathEntry -Times 1 -Exactly -ParameterFilter {
            $PathEntry -eq (Join-Path $installRoot "bin")
        }
    }

    It "points the installed cmd wrapper at both native cmd and PowerShell launchers" {
        $installRoot = Join-Path $TestDrive "launcher"

        Invoke-InstallCodexLauncher -InstallRoot $installRoot

        $wrapperContent = Get-Content -LiteralPath (Join-Path $installRoot "bin\codex.cmd") -Raw

        $expectedCmdLauncherPath = [regex]::Escape((Join-Path $installRoot "Start-Codex-ProjectAccount.cmd"))
        $expectedPs1LauncherPath = [regex]::Escape((Join-Path $installRoot "Start-Codex-ProjectAccount.ps1"))
        $wrapperContent | Should Match $expectedCmdLauncherPath
        $wrapperContent | Should Match $expectedPs1LauncherPath
        $wrapperContent | Should Match 'IF /I "%%~A"=="-AccountName" SET "CODEX_HAS_ACCOUNT_ARG=1"'
    }

    It "builds a shell wrapper that forwards arguments correctly" {
        $wrapperContent = New-CodexShWrapperContent -InstalledLauncherPs1Path 'C:\Test Root\Start-Codex-ProjectAccount.ps1'

        $wrapperContent | Should Match 'set -- -AccountName "\$selection" "\$@"'
        $wrapperContent | Should Match 'exec "\$powershell_exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "C:\\Test Root\\Start-Codex-ProjectAccount\.ps1" "\$@"'
        $wrapperContent | Should Not Match '\\\$@'
    }
}
