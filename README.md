# VU: PowerShell helper for managing Python envs via uv

Usage

- `vu create [-p|--python <version>] <name>`
- `vu activate <name>`
- `vu env list`
- `vu env remove <name> [--force]`
- `vu install <package> [<more>...]`
- `vu uninstall <package> [<more>...]`
- `vu list`

Notes

- Uses env var `PYTHON_VENV_DIR` as root; defaults to `$HOME\python_venvs`.
- `install` / `uninstall` / `list` operate on the currently activated virtual env (`VIRTUAL_ENV`).
- If removal fails on Windows due to locked `.pyd` files, re-run `vu env remove <name> --force` to stop `python.exe` processes that came from that env, or close any IDEs/REPLs using it and ensure the env is deactivated.