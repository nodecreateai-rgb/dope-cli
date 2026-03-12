# dope-cli

A standalone cross-platform `dope` CLI for managing OpenClaw host/tenant installs.

## Install

### Linux / macOS
```bash
curl -fsSL https://raw.githubusercontent.com/nodecreateai-rgb/dope-cli/main/install.sh | bash
```

### Windows PowerShell
```powershell
irm https://raw.githubusercontent.com/nodecreateai-rgb/dope-cli/main/install.ps1 | iex
```

### Windows CMD
```cmd
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/nodecreateai-rgb/dope-cli/main/install.ps1 | iex"
```

After install:

```bash
dope --help
```

## What gets installed

The installer copies the CLI bundle into a user-owned directory and exposes `dope` on your PATH.

- Linux / macOS:
  - bundle: `~/.local/share/dope-cli`
  - launcher: `~/.local/bin/dope`
- Windows:
  - bundle: `%USERPROFILE%\\.dope\\bundle`
  - launchers: `%USERPROFILE%\\.dope\\bin\\dope.cmd` and `dope.ps1`

## Notes

- `dope` is implemented in Python and requires Python 3.
- The CLI reuses the existing OpenClaw installer scripts for host and tenant flows.
- `tenant info` intentionally omits secrets such as API keys and Feishu app secrets.

## Development

Basic local checks:

```bash
python3 ./dope --help
python3 ./dope tenant renew --help
python3 ./dope tenant list --json
```
