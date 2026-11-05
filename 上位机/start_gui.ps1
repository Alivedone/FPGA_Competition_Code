param([switch]$SelfTest)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
try {
    $candidates = @()
    foreach ($commandName in @('python.exe', 'python3.exe')) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if ($command -and $command.Source -notlike '*\WindowsApps\*') {
            $candidates += @{ Path = $command.Source; Prefix = @() }
        }
    }
    $pythonBase = Join-Path $env:LOCALAPPDATA 'Programs\Python'
    if (Test-Path -LiteralPath $pythonBase) {
        foreach ($item in (Get-ChildItem -LiteralPath $pythonBase -Directory)) {
            $exe = Join-Path $item.FullName 'python.exe'
            if (Test-Path -LiteralPath $exe) { $candidates += @{ Path = $exe; Prefix = @() } }
        }
    }
    $pyCommand = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($pyCommand) { $candidates += @{ Path = $pyCommand.Source; Prefix = @('-3') } }
    $selected = $null
    foreach ($candidate in $candidates) {
        $pythonExe = $candidate.Path
        $prefixArgs = $candidate.Prefix
        $ErrorActionPreference = 'Continue'
        $probe = & $pythonExe @prefixArgs -c 'import sys, tkinter; assert sys.version_info >= (3, 10)' 2>&1
        $probeExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($probeExit -eq 0) { $selected = $candidate; break }
    }
    if ($null -eq $selected) { throw 'No usable Python 3.10+ with Tk found. Install Python including Tcl/Tk.' }
    $pythonExe = $selected.Path
    $prefixArgs = $selected.Prefix
    Write-Host ('Python: ' + $pythonExe)
    $launchArgs = @((Join-Path $PSScriptRoot 'launcher.py'))
    if ($SelfTest) { $launchArgs += '--self-test' }
    & $pythonExe @prefixArgs @launchArgs
    if ($LASTEXITCODE -ne 0) { throw 'GUI failed. Check output/startup.log in this folder.' }
    exit 0
} catch {
    Write-Host ('Startup error: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
