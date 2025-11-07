# VU: PowerShell helper for managing Python envs via uv

Set-StrictMode -Version Latest

function Show-VUHelp {
    Write-Host "Usage:" -ForegroundColor Cyan
    Write-Host "  vu create [-p|--python <version>] <name>" -ForegroundColor Cyan
    Write-Host "  vu activate <name>" -ForegroundColor Cyan
    Write-Host "  vu env list" -ForegroundColor Cyan
    Write-Host "  vu env remove <name> [--force]" -ForegroundColor Cyan
    Write-Host "  vu install <package> [<more packages>...]" -ForegroundColor Cyan
    Write-Host "  vu uninstall <package> [<more packages>...]" -ForegroundColor Cyan
    Write-Host "  vu list" -ForegroundColor Cyan
    Write-Host "" 
    Write-Host "Notes:" -ForegroundColor DarkGray
    Write-Host "  Uses env var PYTHON_VENV_DIR as root; defaults to: $HOME\\python_venvs" -ForegroundColor DarkGray
    Write-Host "  install/uninstall/list operate on the currently activated virtual env (VIRTUAL_ENV)." -ForegroundColor DarkGray
    Write-Host "  env remove supports --force to stop python.exe from that env if needed." -ForegroundColor DarkGray
}


function vu {
    if ($args.Count -eq 0) { Show-VUHelp; return }
    if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
        Write-Error 'uv is not detected. Install it: https://docs.astral.sh/uv/'; return
    }
    if ([string]::IsNullOrWhiteSpace($env:PYTHON_VENV_DIR)) {
        $env:PYTHON_VENV_DIR = Join-Path -Path $HOME -ChildPath 'python_venvs'
    }
    if (-not (Test-Path -Path $env:PYTHON_VENV_DIR)) {
        New-Item -ItemType Directory -Path $env:PYTHON_VENV_DIR -Force | Out-Null
    }
    $venvRoot = $env:PYTHON_VENV_DIR

    $cmd = $args[0].ToLower()
    switch ($cmd) {
        'create' {
            $name = $null
            $pythonVersion = $null
            for ($i = 1; $i -lt $args.Count; $i++) {
                $token = $args[$i]
                switch ($token) {
                    '-p' { if ($i + 1 -lt $args.Count) { $pythonVersion = $args[$i + 1]; $i++ } else { Write-Error 'Missing value for -p'; return } }
                    '--python' { if ($i + 1 -lt $args.Count) { $pythonVersion = $args[$i + 1]; $i++ } else { Write-Error 'Missing value for --python'; return } }
                    default { if (-not $name) { $name = $token } }
                }
            }
            if (-not $name) { Write-Error 'Missing NAME'; return }

            if ($pythonVersion) {
                & uv init --name $name --no-description --vcs none --no-readme --no-workspace -p $pythonVersion --directory $venvRoot $name
            }
            else {
                & uv init --name $name --no-description --vcs none --no-readme --no-workspace --directory $venvRoot $name
            }

            $projDir = Join-Path -Path $venvRoot -ChildPath $name
            & uv sync --directory $projDir

            Write-Host "Created and synced: $projDir" -ForegroundColor Green
        }

        'activate' {
            if ($args.Count -lt 2) { Write-Error 'Missing NAME'; return }
            $name = $args[1]
            $activateExc = '.venv\\Scripts\\Activate.ps1'
            $activatePath = Join-Path -Path (Join-Path -Path $venvRoot -ChildPath $name) -ChildPath $activateExc

            if (-not (Test-Path -Path $activatePath)) {
                Write-Error "Activation script not found: $activatePath. Run 'vu create $name' first."
                return
            }

            Invoke-Expression $activatePath
        }

        'env' {
            if ($args.Count -lt 2) {
                Write-Error "Missing subcommand. Usage: vu env list | vu env remove <name>"; return
            }
            $sub = $args[1].ToLower()
            switch ($sub) {
                'list' {
                    $dirs = Get-ChildItem -Path $venvRoot -Directory -ErrorAction SilentlyContinue
                    if (-not $dirs) { Write-Host "No environments found in: $venvRoot" -ForegroundColor Yellow; break }
                    Write-Host ("Found {0} environment(s) in {1}:" -f $dirs.Count, $venvRoot) -ForegroundColor Cyan
                    foreach ($d in $dirs) {
                        $venvPath = Join-Path -Path $d.FullName -ChildPath '.venv'
                        $marker = if (Test-Path -Path $venvPath) { '[ready]' } else { '[no .venv]' }
                        Write-Host ("  {0}  {1}" -f $d.Name, $marker)
                    }
                }
                'remove' {
                    if ($args.Count -lt 3) { Write-Error "Missing NAME. Usage: vu env remove <name> [--force]"; break }
                    $name = $args[2]
                    $force = $false
                    if ($args.Count -gt 3) {
                        for ($j = 3; $j -lt $args.Count; $j++) {
                            $tok = $args[$j]
                            if ($tok -eq '--force' -or $tok -eq '-f') { $force = $true }
                        }
                    }

                    $target = Join-Path -Path $venvRoot -ChildPath $name
                    if (-not (Test-Path -Path $target)) { Write-Host "Environment does not exist: $target" -ForegroundColor Yellow; break }

                    $venvPath = Join-Path -Path $target -ChildPath '.venv'

                    # If this env is currently active, try to deactivate to release file locks
                    $activeVenv = $env:VIRTUAL_ENV
                    if (-not [string]::IsNullOrWhiteSpace($activeVenv)) {
                        $activeResolved = $activeVenv
                        $targetResolved = $venvPath
                        try { $activeResolved = (Resolve-Path -Path $activeVenv -ErrorAction Stop).Path } catch {}
                        try { $targetResolved = (Resolve-Path -Path $venvPath -ErrorAction Stop).Path } catch {}
                        if ($activeResolved -eq $targetResolved) {
                            $deact = Get-Command -Name 'deactivate' -ErrorAction SilentlyContinue
                            if ($deact) { try { deactivate } catch {} }
                        }
                    }

                    # If --force is provided, stop python processes that are using this env's python.exe
                    if ($force -and (Test-Path -Path $venvPath)) {
                        $pythonExe = Join-Path -Path $venvPath -ChildPath 'Scripts\\python.exe'
                        $procs = Get-Process -Name 'python','python3' -ErrorAction SilentlyContinue
                        $toKill = @()
                        foreach ($p in $procs) {
                            $pPath = $null
                            try { $pPath = $p.Path } catch {}
                            if (-not $pPath) { try { $pPath = $p.MainModule.FileName } catch {} }
                            if ($pPath -and ($pPath -eq $pythonExe)) { $toKill += $p }
                        }
                        if ($toKill.Count -gt 0) {
                            Write-Host ("Stopping {0} python process(es) from env '{1}'..." -f $toKill.Count, $name) -ForegroundColor Yellow
                            foreach ($p in $toKill) { try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {} }
                        }
                    }

                    # Clear read-only attributes before removal
                    try {
                        Get-ChildItem -Path $target -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                            try { $_.Attributes = 'Normal' } catch {}
                        }
                    } catch {}

                    try {
                        Remove-Item -Recurse -Force -Path $target -ErrorAction Stop
                        Write-Host "Removed environment: $venvRoot\\$name" -ForegroundColor Green
                    }
                    catch {
                        Write-Host "Failed to remove environment due to locked files." -ForegroundColor Yellow
                        Write-Host "Tips:" -ForegroundColor DarkGray
                        Write-Host "  - Close Python REPLs, IDEs, or servers using this env." -ForegroundColor DarkGray
                        Write-Host "  - Run again with --force to stop python.exe from this env." -ForegroundColor DarkGray
                        Write-Host "  - Ensure the env is deactivated in the current shell." -ForegroundColor DarkGray
                    }
                }
                default { Write-Error "Unknown env subcommand: $sub. Use 'list' or 'remove'." }
            }
        }

        'install' {
            if ($args.Count -lt 2) { Write-Error "Missing package name(s). Usage: vu install <package> [<more>...]"; return }
            if ([string]::IsNullOrWhiteSpace($env:VIRTUAL_ENV)) {
                Write-Error "No active virtual environment. Run 'vu activate <name>' first."; return
            }
            $projDir = Split-Path -Path $env:VIRTUAL_ENV -Parent
            $packages = [string[]]($args | Select-Object -Skip 1)

            & uv add --directory $projDir $packages
            & uv sync --directory $projDir
        }

        'uninstall' {
            if ($args.Count -lt 2) { Write-Error "Missing package name(s). Usage: vu uninstall <package> [<more>...]"; return }
            if ([string]::IsNullOrWhiteSpace($env:VIRTUAL_ENV)) {
                Write-Error "No active virtual environment. Run 'vu activate <name>' first."; return
            }
            $projDir = Split-Path -Path $env:VIRTUAL_ENV -Parent
            $packages = [string[]]($args | Select-Object -Skip 1)

            & uv remove --directory $projDir $packages
            & uv sync --directory $projDir
            Write-Host "Uninstalled from active env via uv: $($packages -join ', ')" -ForegroundColor Green
        }

        'list' {
            if ([string]::IsNullOrWhiteSpace($env:VIRTUAL_ENV)) {
                Write-Error "No active virtual environment. Run 'vu activate <name>' first."; return
            }
            & uv pip list
        }

        default { Show-VUHelp }
    }
}