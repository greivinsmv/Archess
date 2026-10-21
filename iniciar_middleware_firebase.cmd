@echo off
setlocal
cd /d "%~dp0"
if not exist ".venv\Scripts\python.exe" (
    echo Crea el entorno .venv e instala requirements.txt. Consulta README.es.md.
    exit /b 1
)
".venv\Scripts\python.exe" -u "%~dp0firebase_multiplayer.py" --watch
