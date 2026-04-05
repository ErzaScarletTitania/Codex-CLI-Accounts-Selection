# Codex-CLI-Accounts-Selection

Windows PowerShell launcher for running Codex with separate local account profiles.

## What it does

This project lets you launch Codex under a named account profile by changing `CODEX_HOME` per account instead of reusing the default `C:\Users\USER\.codex` profile every time.

Each account gets its own local home under:

- `C:\Users\USER\.codex-accounts\<account-name>`

On first use for a new account, the launcher:

1. creates the per-account home directory
2. copies the default `config.toml` from `.codex` if present
3. asks for the API key for that account
4. runs `codex login --with-api-key` inside that dedicated account home

After that, launching with the same account name reuses that account-specific auth cache.

## Files

- `Start-Codex-ProjectAccount.ps1`: main launcher

## Usage

Run from PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\Start-Codex-ProjectAccount.ps1 -AccountName personal -ProjectPath "C:\Users\USER"
```

Example for a project folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\Start-Codex-ProjectAccount.ps1 -AccountName work -ProjectPath "D:\1. Escritorio\Expenses\AI_Invoice_Generation"
```

Any extra arguments are forwarded to `codex`.

## Notes

- This project implements machine-local account separation for Codex CLI.
- It currently uses API-key login per account profile.
- The active machine copy was originally found at `C:\Users\USER\Start-Codex-ProjectAccount.ps1`.
- A future improvement is to add an explicit interactive menu for selecting from known account profiles.
- A regression test suite should be added for this project as part of the shared project rules.
