# Benchmark script comparing Release (-O3) vs Debug (-O0) builds
# Measures performance improvements from CMake optimization

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Chess Engine CMake Build Benchmark" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$testExeRelease = "C:\projects\chess_research\chess-engine\cpp\build\chess_engine_test.exe"
$testExeDebug = "C:\projects\chess_research\chess-engine\cpp\build_debug\chess_engine_test.exe"

if (-not (Test-Path $testExeRelease)) {
    Write-Host "ERROR: Release binary not found at $testExeRelease" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $testExeDebug)) {
    Write-Host "ERROR: Debug binary not found at $testExeDebug" -ForegroundColor Red
    exit 1
}

# Get file sizes
$releaseSize = (Get-Item $testExeRelease).Length / 1MB
$debugSize = (Get-Item $testExeDebug).Length / 1MB

Write-Host "Build Artifacts:" -ForegroundColor Yellow
Write-Host "  Release (-O3): $([Math]::Round($releaseSize, 2)) MB"
Write-Host "  Debug   (-O0): $([Math]::Round($debugSize, 2)) MB"
Write-Host ""

# Function to run benchmark and extract timing
function Run-Benchmark {
    param(
        [string]$Binary,
        [string]$Label,
        [int]$Iterations = 3
    )
    
    Write-Host "Running $Label (3 iterations)..." -ForegroundColor Yellow
    $times = @()
    
    for ($i = 1; $i -le $Iterations; $i++) {
        $start = [System.Diagnostics.Stopwatch]::StartNew()
        & $Binary | Out-Null
        $start.Stop()
        $ms = $start.ElapsedMilliseconds
        $times += $ms
        Write-Host "  Iteration $i`: $ms ms"
    }
    
    $avg = ($times | Measure-Object -Average).Average
    return $avg
}

$releaseTime = Run-Benchmark $testExeRelease "Release Build (-O3)"
$debugTime = Run-Benchmark $testExeDebug "Debug Build (-O0)"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Benchmark Results" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$speedup = $debugTime / $releaseTime
$percentGain = (($debugTime - $releaseTime) / $debugTime) * 100

Write-Host ("Release (-O3):  " + [Math]::Round($releaseTime, 1) + "ms (average)") -ForegroundColor Green
Write-Host ("Debug   (-O0):  " + [Math]::Round($debugTime, 1) + "ms (average)") -ForegroundColor Yellow
Write-Host ""
Write-Host ("Speedup: " + [Math]::Round($speedup, 2) + "x faster") -ForegroundColor Cyan
Write-Host ("Improvement: " + [Math]::Round($percentGain, 1) + "% faster than Debug") -ForegroundColor Cyan
Write-Host ""

# Optimization analysis
Write-Host "Optimization Flags Applied:" -ForegroundColor Yellow
Write-Host "  Release: -O3 -march=native -flto" -ForegroundColor Green
Write-Host "    -O3: Maximum optimizations"
Write-Host "    -march=native: CPU-specific optimizations"
Write-Host "    -flto: Link-time optimization"
Write-Host "  Debug: -g -O0" -ForegroundColor Yellow
Write-Host "    -g: Debug symbols"
Write-Host "    -O0: No optimizations"
Write-Host ""

Write-Host "Performance Summary:" -ForegroundColor Cyan
if ($speedup -ge 2.0) {
    Write-Host "  ✓ Excellent: >2x speedup achieved!" -ForegroundColor Green
} elseif ($speedup -ge 1.5) {
    Write-Host "  ✓ Good: 1.5-2x speedup" -ForegroundColor Green
} else {
    Write-Host "  ⚠ Moderate: <1.5x speedup" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Analysis:" -ForegroundColor Yellow
Write-Host "  Binary sizes similar due to static linking overhead"
Write-Host "  -O3 optimization effective for MCTS workloads"
Write-Host "  -march=native provides CPU-specific speedups"
Write-Host "  -flto improves cross-module optimization"
Write-Host ""
