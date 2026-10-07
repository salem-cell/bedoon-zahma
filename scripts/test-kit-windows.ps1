# Runs BedoonZahmaKit logic tests on Windows (Swift 6.4 toolchain + VS Build Tools).
# Usage:  powershell -File scripts\test-kit-windows.ps1 [build|test]   (default: test)
# Keep this file ASCII-only: Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI.
param([string]$Command = "test")

$toolchain = Get-ChildItem "$env:LOCALAPPDATA\Programs\Swift\Toolchains" -Directory | Sort-Object Name -Descending | Select-Object -First 1
$runtime = Get-ChildItem "$env:LOCALAPPDATA\Programs\Swift\Runtimes" -Directory | Sort-Object Name -Descending | Select-Object -First 1
$platform = Get-ChildItem "$env:LOCALAPPDATA\Programs\Swift\Platforms" -Directory | Sort-Object Name -Descending | Select-Object -First 1
if (-not $toolchain) { Write-Error "Swift toolchain not found. Install: winget install Swift.Toolchain (requires VS Build Tools with C++ and Windows SDK)."; exit 1 }

$env:Path = "$($toolchain.FullName)\usr\bin;$($runtime.FullName)\usr\bin;" + $env:Path
$env:SDKROOT = "$($platform.FullName)\Windows.platform\Developer\SDKs\Windows.sdk\"

$vcvars = "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if (-not (Test-Path $vcvars)) { Write-Error "vcvars64.bat not found. Install Visual Studio 2022 Build Tools (C++ tools + Windows 11 SDK)."; exit 1 }

# The repo lives under a non-ASCII path; keep SwiftPM's scratch dir ASCII to avoid I/O errors.
$scratch = Join-Path $env:LOCALAPPDATA "Temp\bzkit-build"
$pkg = Join-Path $PSScriptRoot "..\BedoonZahma\Packages\BedoonZahmaKit"
Set-Location $pkg

$swiftArgs = if ($Command -eq "build") { "build --build-tests" } else { "test" }
$out = cmd /c "`"$vcvars`" >nul 2>&1 && swift $swiftArgs --scratch-path `"$scratch`" 2>&1"
$exit = $LASTEXITCODE
# Hide the known harmless WinSDK wchar_t modularization warnings.
$out | Where-Object { $_ -notmatch "wchar_t|_Builtin_stddef|SwiftShims|modularization issue|clang preprocessor macros|^\s*$|^\s*1 \| |^\s*\| |unable to create symbolic link" }
exit $exit
