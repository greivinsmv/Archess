$ErrorActionPreference = 'Stop'

# Load only the wait function; the Windows GUI launcher must not start in tests.
$launcher = Join-Path (Split-Path -Parent $PSScriptRoot) 'iniciar_juego.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $launcher, [ref]$tokens, [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
$waitFunction = $ast.Find({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Wait-ArChessMiddlewareReady'
}, $false)
if ($null -eq $waitFunction) { throw 'Middleware wait function not found.' }
. ([scriptblock]::Create($waitFunction.Extent.Text))

$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ('archess-launcher-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDirectory | Out-Null
$readyPath = Join-Path $testDirectory 'middleware_ready.json'
$running = [pscustomobject]@{ Id = 100; HasExited = $false }
$launcherId = [Guid]::NewGuid().ToString('N')
$passed = 0

function Assert-WaitRejected {
    param($Process = $running, [string]$Message = 'tiempo previsto')
    $failure = $null
    try {
        Wait-ArChessMiddlewareReady -Process $Process -ReadyPath $readyPath -LauncherId $launcherId -TimeoutSeconds 1
    } catch {
        $failure = $_.Exception.Message
    }
    if ($null -eq $failure -or -not $failure.Contains($Message)) {
        throw "Expected rejection containing '$Message', got '$failure'."
    }
}

try {
    # Windows .venv may return the redirector's PID while Python reports its child.
    @{ pid = 200; protocol = 2; launcher_id = $launcherId } |
        ConvertTo-Json | Set-Content -LiteralPath $readyPath -Encoding UTF8
    Wait-ArChessMiddlewareReady -Process $running -ReadyPath $readyPath -LauncherId $launcherId -TimeoutSeconds 1
    $passed++

    # A matching PID must not make a marker from a previous launch valid.
    @{ pid = 100; protocol = 2; launcher_id = 'previous-launch' } |
        ConvertTo-Json | Set-Content -LiteralPath $readyPath -Encoding UTF8
    Assert-WaitRejected
    $passed++

    @{ pid = 200; protocol = 1; launcher_id = $launcherId } |
        ConvertTo-Json | Set-Content -LiteralPath $readyPath -Encoding UTF8
    Assert-WaitRejected
    $passed++

    @{ pid = 100; protocol = 2 } |
        ConvertTo-Json | Set-Content -LiteralPath $readyPath -Encoding UTF8
    Assert-WaitRejected
    $passed++

    '{unfinished' | Set-Content -LiteralPath $readyPath -Encoding UTF8
    Assert-WaitRejected
    $passed++

    Remove-Item -LiteralPath $readyPath
    Assert-WaitRejected -Process ([pscustomobject]@{ HasExited = $true }) -Message 'No se pudo iniciar'
    $passed++

    Write-Output "Launcher readiness: $passed checks passed."
} finally {
    Remove-Item -LiteralPath $testDirectory -Recurse -Force
}
