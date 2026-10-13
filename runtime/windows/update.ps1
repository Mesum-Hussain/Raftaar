# The installer scriptblock is embedded by the build. Parameters are environment data,
# never interpolated into PowerShell source or downloaded as executable script text.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$exe = [IO.Path]::GetFullPath($env:RAFTAAR_UP_EXE)
$directory = Split-Path -Parent $exe
$stage = Join-Path (Split-Path -Parent $directory) ('.raftaar-update-' + $env:RAFTAAR_UP_PID)
$restart = @{
    FilePath = $exe
    WorkingDirectory = $env:USERPROFILE
}
if (-not [string]::IsNullOrEmpty($env:RAFTAAR_UP_ARGS)) {
    # The editor supplies Windows command-line quoting. Treat it as argument data.
    $restart.ArgumentList = $env:RAFTAAR_UP_ARGS
}
$options = @{
    InstallDir = $directory
    Version = $env:RAFTAAR_UP_VERSION
    ReleasesUrl = $env:RAFTAAR_UP_URL
    UpdateStage = $stage
    WaitPid = [int]$env:RAFTAAR_UP_PID
    NoModifyPath = $true
    NoShortcut = $true
}
try {
    if ($env:RAFTAAR_UP_ACTION -eq 'prepare') {
        & $installer @options -PrepareUpdate
    } elseif ($env:RAFTAAR_UP_ACTION -eq 'discard') {
        & $installer @options -DiscardUpdate
    } elseif ($env:RAFTAAR_UP_ACTION -eq 'apply') {
        & $installer @options -ApplyUpdate
        Start-Process @restart
    } else { throw 'Invalid update action.' }
} catch {
    if ($env:RAFTAAR_UP_ACTION -eq 'apply') {
        # The editor has exited. Keep the failed stage and show a visible recovery message.
        Add-Type -AssemblyName System.Windows.Forms
        [Windows.Forms.MessageBox]::Show("The update could not be installed. $($_.Exception.Message)`nThe previous installation and the update files are in $directory and $stage.", 'raftaar update') | Out-Null
        if (Test-Path -LiteralPath $exe) { Start-Process @restart }
    }
    Write-Output $_.Exception.Message
    exit 1
}
