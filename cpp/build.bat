@echo off
REM Build script for Chess Engine
REM Sets up PATH for MinGW and builds the project

set MINGW_PATH=C:\Users\%USERNAME%\AppData\Local\Microsoft\WinGet\Packages\BrechtSanders.WinLibs.POSIX.UCRT_Microsoft.Winget.Source_8wekyb3d8bbwe\mingw64\bin
set PATH=%MINGW_PATH%;%PATH%

echo Building Chess Engine...
echo MinGW Path: %MINGW_PATH%
g++ --version

cd /d "%~dp0"

REM Try mingw32-make first, then make
mingw32-make %* 2>nul
if errorlevel 1 (
    make %*
)
