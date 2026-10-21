# gmux installer for Windows: irm https://get.wandpod.com/gmux.ps1 | iex
# Options: https://github.com/wandpod/gmux#install. The layout itself is `gmux.exe install`.
# Isolate bootstrap variables from the caller's interactive session.
& {
    $ErrorActionPreference = 'Stop'
    # Windows PowerShell 5.1 renders Invoke-WebRequest progress so slowly that it dominates the download.
    $ProgressPreference = 'SilentlyContinue'

    $Base = if ($env:GMUX_DOWNLOAD_BASE) { $env:GMUX_DOWNLOAD_BASE.TrimEnd('/') } else { 'https://get.wandpod.com/gmux' }
    # Env vars, not RuntimeInformation.OSArchitecture: PSReadLine shadows that type on Windows PowerShell 5.1.
    $RawArch = $env:PROCESSOR_ARCHITEW6432
    if (-not $RawArch) { $RawArch = $env:PROCESSOR_ARCHITECTURE }
    $Arch = switch ($RawArch) {
        'AMD64' { 'amd64' }
        'ARM64' { 'arm64' }
        default { throw "gmux install: unsupported architecture '$RawArch' (need AMD64 or ARM64)" }
    }
    $Dir = if ($env:GMUX_INSTALL_DIR) { $env:GMUX_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'Programs\gmux' }

    $Version = $env:GMUX_VERSION
    if (-not $Version) { $Version = (Invoke-RestMethod -UseBasicParsing -Uri "$Base/version").Trim() }
    $Version = $Version.TrimStart('v')
    if (-not $Version) { throw "gmux install: empty version from $Base/version" }

    $Tmp = Join-Path ([IO.Path]::GetTempPath()) ('gmux-install-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $Tmp | Out-Null
    try {
        $Archive = Join-Path $Tmp "gmux-windows-$Arch.tar.gz"
        $Bundle = Join-Path $Tmp 'gmux-agent-binaries.tar.gz'
        Write-Host "Downloading gmux $Version (windows/$Arch)..."
        Invoke-WebRequest -UseBasicParsing -Uri "$Base/$Version/gmux-windows-$Arch.tar.gz" -OutFile $Archive
        Write-Host 'Downloading agent binaries for all platforms...'
        Invoke-WebRequest -UseBasicParsing -Uri "$Base/$Version/gmux-agent-binaries.tar.gz" -OutFile $Bundle
        # tar.exe ships with Windows 10 1803 and later.
        tar.exe -xzf $Archive -C $Tmp
        if ($LASTEXITCODE -ne 0) { throw "gmux install: tar.exe failed to extract $Archive (exit $LASTEXITCODE)" }

        & (Join-Path $Tmp 'gmux.exe') install --dir $Dir --bundle $Bundle --license-dir $Tmp
        if ($LASTEXITCODE -ne 0) { throw "gmux install: gmux.exe install failed (exit $LASTEXITCODE)" }
    } finally {
        Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    # The registry PATH reaches new shells; this one ran the installer and should find gmux too.
    if (-not (($env:Path -split ';') -contains $Dir)) { $env:Path = $env:Path.TrimEnd(';') + ';' + $Dir }
    $Exe = Join-Path $Dir 'gmux.exe'
    Write-Host "gmux v$Version installed to $Exe"

    # Non-interactive invocations have nobody to answer a completion prompt.
    $Mode = $env:GMUX_COMPLETION_INSTALL
    if ($Mode -ne '0') {
        $Activate = $Mode -eq '1'
        $NonInteractive = [Environment]::GetCommandLineArgs() | Where-Object { $_ -like '-NonI*' }
        # UserInteractive describes the session, not this invocation: redirected input means no one can answer.
        $CanPrompt = [Environment]::UserInteractive -and -not $NonInteractive -and -not [Console]::IsInputRedirected
        if (-not $Activate -and $CanPrompt) {
            $Answer = Read-Host 'Install PowerShell completion for your user? [Y/n]'
            $Activate = $Answer -match '^\s*(y|yes)?\s*$'
        }
        if ($Activate) {
            & $Exe completion install powershell
            # 3: the execution policy blocks the profile and the user may allow scripts; 4: Group Policy blocks it. gmux printed the hint.
            if ($LASTEXITCODE -eq 3 -and $CanPrompt) {
                $Answer = Read-Host 'Completion needs local PowerShell scripts allowed for your user. Allow (Set-ExecutionPolicy -Scope CurrentUser RemoteSigned)? [y/N]'
                if ($Answer -match '^\s*(y|yes)\s*$') { & $Exe completion install powershell --allow-scripts }
            }
            if ($LASTEXITCODE -notin 0, 3, 4) { Write-Warning 'completion activation failed; the binary and the adapter beside it were installed.' }
        }
    }
}
