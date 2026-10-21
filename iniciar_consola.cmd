@echo off
setlocal
cd /d "%~dp0"
if not exist "Debug\arChess-console.exe" (
    echo Compila la consola desde Developer PowerShell for VS 2022:
    echo msbuild TestMASM.sln /p:Configuration=Debug /p:Platform=x86 /p:ChessInterface=Console
    pause
    exit /b 1
)
"%~dp0Debug\arChess-console.exe"
pause
