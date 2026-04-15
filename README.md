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

On first use for a new account, the launcher:

1. creates the per-account home directory
2. copies the default `config.toml` from `.codex` if present
3. asks for the API key for that account
4. runs `codex login --with-api-key` inside that dedicated account home

After that, launching with the same account name reuses that account-specific auth cache.

## Files

- `Start-Codex-ProjectAccount.ps1`: main launcher
- `Install-CodexLauncher.ps1`: installs the launcher as the global `codex` command on this machine

## Usage

Install the global wrapper once:

```powershell
powershell -ExecutionPolicy Bypass -File .\Install-CodexLauncher.ps1
```

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

## Notes

- This project implements machine-local account separation for Codex CLI.
- It currently uses API-key login per account profile.
- The active machine copy was originally found at `C:\Users\USER\Start-Codex-ProjectAccount.ps1`.
- A future improvement is to add an explicit interactive menu for selecting from known account profiles.
- A regression test suite should be added for this project as part of the shared project rules.
