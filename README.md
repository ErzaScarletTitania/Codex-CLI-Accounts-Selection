# Codex-CLI-Accounts-Selection

Windows PowerShell launcher for running Codex with separate local account profiles.

## What it does

This project lets you launch Codex under a named account profile by changing `CODEX_HOME` per account instead of reusing the default `C:\Users\USER\.codex` profile every time.

Each account gets its own local home under:

- `C:\Users\USER\.codex-accounts\<account-name>`

By default, the launcher now shows an interactive menu with these options before Codex starts:

1. `Aleph General`
2. `GTB`
3. `IE - Imagined Earth`

The default homes used by those menu options are:

- `Aleph General` -> `C:\Users\USER\.codex`
- `GTB` -> `C:\Users\USER\.codex-second`
- `IE - Imagined Earth` -> `C:\Users\USER\.codex-accounts\ie-imagined-earth`

On first use for a new account, the launcher:

1. creates the per-account home directory
2. copies the default `config.toml` from `.codex` if present
3. prompts for a login method
4. either runs `codex login --device-auth` for ChatGPT sign-in or `codex login --with-api-key` for API-key auth inside that dedicated account home

After that, launching with the same account name reuses that account-specific auth cache.

## Files

- `Start-Codex-ProjectAccount.ps1`: main launcher
- `Start-Codex-ProjectAccount.cmd`: native cmd launcher used by the Windows `codex.cmd` shim
- `Install-CodexLauncher.ps1`: installs a persistent launcher as the global `codex` command on this machine
- `Invoke-RegressionTests.ps1`: runs the Pester regression suite in `tests\`

## Usage

Install the persistent global wrapper once:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-CodexLauncher.ps1
```

The installer copies the launcher into a stable user-owned directory:

- `C:\Users\USER\.codex-launcher`

and adds this bin directory to the user `PATH`:

- `C:\Users\USER\.codex-launcher\bin`

This avoids editing the npm-managed shims in `C:\Users\USER\AppData\Roaming\npm`, so future Codex upgrades do not remove the account selector.

After that, run from `cmd` or PowerShell:

```powershell
codex
```

Or call the launcher directly:

```powershell
powershell -ExecutionPolicy Bypass -File .\Start-Codex-ProjectAccount.ps1 -ProjectPath "C:\Users\USER"
```

You can still bypass the menu by passing `-AccountName` explicitly:

```powershell
powershell -ExecutionPolicy Bypass -File .\Start-Codex-ProjectAccount.ps1 -AccountName gtb -ProjectPath "D:\1. Escritorio\Expenses\AI_Invoice_Generation"
```

Any extra arguments are forwarded to `codex`.

## Regression tests

Run the PowerShell regression suite with:

```powershell
powershell -ExecutionPolicy Bypass -File .\Invoke-RegressionTests.ps1
```

The suite covers the account-selection logic, login-mode selection, executable resolution, and installer PATH/wrapper behavior.

## Notes

- This project implements machine-local account separation for Codex CLI.
- It supports either ChatGPT sign-in (`--device-auth`) or API-key login per account profile, depending on what your Codex CLI version supports.
- The launcher resolves the real Codex executable from `PATH` while ignoring its own installed wrapper directory.
- The installed launcher copy lives outside the npm shim directory, so `npm install -g @openai/codex` updates do not overwrite it.
