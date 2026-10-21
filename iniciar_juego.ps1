param([switch]$Online)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
Add-Type -AssemblyName System.Windows.Forms

# Recuperar tambien ventanas ocultas: MainWindowHandle puede devolver cero.
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class ArChessWindow {
    private delegate bool WindowCallback(IntPtr window, IntPtr arg);
    [DllImport("user32.dll")] private static extern bool EnumWindows(WindowCallback callback, IntPtr arg);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll")] private static extern IntPtr GetWindow(IntPtr window, uint command);
    [DllImport("user32.dll")] private static extern int GetWindowTextLength(IntPtr window);
    [DllImport("user32.dll")] private static extern bool ShowWindowAsync(IntPtr window, int command);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr window);
    public static bool Reveal(uint processId) {
        bool found = false;
        EnumWindows(delegate(IntPtr window, IntPtr arg) {
            uint owner;
            GetWindowThreadProcessId(window, out owner);
            if (owner != processId || GetWindow(window, 4) != IntPtr.Zero || GetWindowTextLength(window) == 0) return true;
            ShowWindowAsync(window, 9);
            ShowWindowAsync(window, 5);
            SetForegroundWindow(window);
            found = true;
            return false;
        }, IntPtr.Zero);
        return found;
    }
}
"@
function Restore-ArChess {
    $expected = [IO.Path]::GetFullPath((Join-Path $projectRoot 'Debug\arChess.exe'))
    foreach ($candidate in @(Get-Process -Name arChess -ErrorAction SilentlyContinue)) {
        try {
            if ([string]::Equals($candidate.Path, $expected, [StringComparison]::OrdinalIgnoreCase)) {
                if ([ArChessWindow]::Reveal([uint32]$candidate.Id)) { return $true }
            }
        } catch { }
    }
    return $false
}

$ownedMiddleware = $null
$launcherLock = $null
try {
    try {
        $launcherLock = [IO.File]::Open((Join-Path $projectRoot 'launcher.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    } catch {
        if (($_.Exception.HResult -band 65535) -in @(32,33)) {
            if (Restore-ArChess) { return }
            throw 'Existe un inicio activo pero aun no se encontro su ventana. Espera unos segundos y vuelve a abrir iniciar_juego. Si persiste, cierra el inicio anterior desde el Administrador de tareas.'
        }
        throw ('No se pudo acceder al bloqueo de inicio: ' + $_.Exception.Message)
    }
    $gamePath = Join-Path $projectRoot 'Debug\arChess.exe'
    $middlewarePath = Join-Path $projectRoot 'firebase_multiplayer.py'
    if (-not (Test-Path -LiteralPath $gamePath -PathType Leaf)) {
        throw 'Primero compila TestMASM.sln en Debug | x86 para generar Debug\arChess.exe. Consulta README.es.md.'
    }
    if ($Online) {
        $pythonPath = Join-Path $projectRoot '.venv\Scripts\python.exe'
        if (-not (Test-Path -LiteralPath $pythonPath -PathType Leaf)) {
            throw 'Falta .venv\Scripts\python.exe. Crea el entorno de Python e instala requirements.txt antes de iniciar con -Online.'
        }
        if (-not $env:ARCHESS_FIREBASE_URL -or -not $env:ARCHESS_FIREBASE_CREDENTIALS) {
            throw 'Configura ARCHESS_FIREBASE_URL y ARCHESS_FIREBASE_CREDENTIALS para el prototipo online. Consulta README.es.md.'
        }
        if (-not (Test-Path -LiteralPath $env:ARCHESS_FIREBASE_CREDENTIALS -PathType Leaf)) {
            throw 'No se encontró la credencial indicada por ARCHESS_FIREBASE_CREDENTIALS.'
        }
        if (-not (Test-Path -LiteralPath $middlewarePath -PathType Leaf)) {
            throw 'No se encontró firebase_multiplayer.py.'
        }
        $logDir = Join-Path $projectRoot 'logs'
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        $readyPath = Join-Path $projectRoot 'middleware_ready.json'
        $ready = $false
        if (Test-Path -LiteralPath $readyPath) {
            try {
                $info = Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json
                $existing = Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$info.pid)"
                $ready = $null -ne $existing -and $existing.CommandLine.Contains($middlewarePath) -and $existing.CommandLine.Contains('--watch')
            } catch { $ready = $false }
        }
        if (-not $ready) {
            $ownedMiddleware = Start-Process -FilePath $pythonPath -ArgumentList @('-u',('"'+$middlewarePath+'"'),'--watch') -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logDir 'middleware.log') -RedirectStandardError (Join-Path $logDir 'middleware_error.log')
            $deadline = [DateTime]::UtcNow.AddSeconds(20)
            while ([DateTime]::UtcNow -lt $deadline) {
                if ($ownedMiddleware.HasExited) { throw "No se pudo iniciar el middleware. Revisa logs\middleware_error.log y logs\middleware.log." }
                if (Test-Path -LiteralPath $readyPath) {
                    try {
                        $info = Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json
                        if ([int]$info.pid -eq $ownedMiddleware.Id) { $ready = $true; break }
                    } catch {}
                }
                Start-Sleep -Milliseconds 100
            }
            if (-not $ready) { throw 'El middleware no respondio en 20 segundos. Revisa la carpeta logs.' }
        }
    }
    $game = Start-Process -FilePath $gamePath -WorkingDirectory $projectRoot -WindowStyle Normal -PassThru
    # Asegurar visibilidad aunque el proceso padre haya arrancado oculto.
    for ($attempt = 0; $attempt -lt 40 -and -not $game.HasExited; $attempt++) {
        if ([ArChessWindow]::Reveal([uint32]$game.Id)) { break }
        Start-Sleep -Milliseconds 100
    }
    $game.WaitForExit()
} catch {
    [Windows.Forms.MessageBox]::Show($_.Exception.Message,'arChess - No se pudo iniciar','OK','Error') | Out-Null
} finally {
    if ($null -ne $ownedMiddleware -and -not $ownedMiddleware.HasExited) { Stop-Process -Id $ownedMiddleware.Id -ErrorAction SilentlyContinue }
    if ($null -ne $launcherLock) { $launcherLock.Dispose() }
}
