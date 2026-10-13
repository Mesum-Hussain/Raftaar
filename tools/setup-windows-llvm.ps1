# The normal LLVM installer omits llvm-mc. Use the complete, pinned upstream archive.
[CmdletBinding()]
param([string]$Destination = (Join-Path $PSScriptRoot '..\build\llvm'))
$ErrorActionPreference = 'Stop'
$Destination = [IO.Path]::GetFullPath($Destination)
$package = 'clang+llvm-23.1.2-x86_64-pc-windows-msvc'
$extension = '.tar.xz'
$checksum = '8fb91cdc44fcbbdcf6b3ffd0a1f9859abd14a3c3aae4423c2b6d4a4f90bf0095'
if (Get-Command zstd -ErrorAction SilentlyContinue) {
    $extension = '.tar.zst'
    $checksum = 'ceaee048142fece144752c6f6431cb0905a7a6160f78ab8cf5cf0b6216f99418'
}
$bin = Join-Path $Destination 'bin'
$required = @('llvm-mc.exe', 'llvm-dlltool.exe', 'llvm-rc.exe', 'lld-link.exe')
$missing = @($required | Where-Object { -not (Test-Path (Join-Path $bin $_)) })
if ($missing.Count -gt 0) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $archive = Join-Path $Destination ($package + $extension)
    try {
        Write-Output 'Downloading the LLVM archive...'
        & curl.exe --fail --location --connect-timeout 30 --max-time 600 --retry 3 --retry-max-time 900 --output $archive "https://github.com/llvm/llvm-project/releases/download/llvmorg-23.1.2/$package$extension"
        if ($LASTEXITCODE -ne 0) { throw 'Could not download the LLVM tools.' }
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ine $checksum) {
            throw 'The LLVM archive checksum does not match.'
        }
        Write-Output 'Extracting the LLVM tools...'
        & python (Join-Path $PSScriptRoot 'extract-windows-llvm.py') $archive $Destination $package
        if ($LASTEXITCODE -ne 0) { throw 'Could not extract the LLVM tools.' }
    } finally {
        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    }
}
foreach ($name in $required) {
    if (-not (Test-Path (Join-Path $bin $name))) { throw "The LLVM archive is missing $name." }
}
$env:LLVM_BIN = $bin
$env:Path = "$bin;$env:Path"
if ($env:GITHUB_PATH) { $bin | Out-File -FilePath $env:GITHUB_PATH -Append }
Write-Output "LLVM tools: $bin"
