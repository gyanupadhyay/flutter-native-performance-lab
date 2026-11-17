param(
    [Parameter(Mandatory = $true)][string]$Device,
    [switch]$Interactive,
    [switch]$SkipBuild,
    [switch]$SkipInstall,
    [string]$Adb = 'adb',
    [string]$Flutter = 'flutter'
)

$ErrorActionPreference = 'Stop'
$labRoot = $PSScriptRoot
$projectRoot = (Resolve-Path (Join-Path $labRoot '../..')).Path
$artifactRoot = Join-Path $labRoot 'artifacts'
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$prefix = Join-Path $artifactRoot $stamp

function Invoke-Adb {
    & $Adb -s $Device @args
    if ($LASTEXITCODE -ne 0) { throw "adb failed: $args" }
}

Push-Location $projectRoot
try {
    if (-not $SkipBuild) {
        $auto = if ($Interactive) { 'false' } else { 'true' }
        & $Flutter build apk --release --target-platform android-arm64 `
            -t example/performance_lab/main.dart "--dart-define=LAB_AUTO=$auto" *> "$prefix-build.log"
        if ($LASTEXITCODE -ne 0) { throw "Build failed; see $prefix-build.log" }
    }

    $metadata = [ordered]@{
        local_time = (Get-Date -Format 'o')
        model = (Invoke-Adb shell getprop ro.product.model | Out-String).Trim()
        android = (Invoke-Adb shell getprop ro.build.version.release | Out-String).Trim()
        abi = (Invoke-Adb shell getprop ro.product.cpu.abi | Out-String).Trim()
        flutter = (& $Flutter --version | Out-String).Trim()
        battery_before = (Invoke-Adb shell dumpsys battery | Out-String)
    }
    if (-not $SkipInstall) {
        Invoke-Adb install -r (Join-Path $projectRoot 'build/app/outputs/flutter-apk/app-release.apk')
    }
    Invoke-Adb shell am force-stop dev.bench.native_bench
    Invoke-Adb shell am start -W -n dev.bench.native_bench/.MainActivity
    if ($Interactive) {
        Write-Host 'Interactive release app installed and launched.'
        return
    }

    $appProcess = (Invoke-Adb shell pidof dev.bench.native_bench | Out-String).Trim()
    if (-not $appProcess) { throw 'The app did not start.' }
    $deadline = (Get-Date).AddMinutes(4)
    $records = @()
    do {
        Start-Sleep -Seconds 2
        $lines = @(Invoke-Adb logcat -d "--pid=$appProcess" -s flutter:I)
        $records = @($lines | ForEach-Object {
            if ($_ -match 'PERF_LAB (\{.*\})') { $Matches[1] | ConvertFrom-Json }
        })
        $failure = $records | Where-Object { $_.type -eq 'error' }
        $frameworkFailure = $lines | Select-String 'Another exception was thrown:|Unhandled Exception|EXCEPTION CAUGHT BY'
        if ($failure -or $frameworkFailure) {
            $lines | Set-Content -LiteralPath "$prefix-logcat.txt" -Encoding UTF8
            throw "Device suite failed: $($failure.message). See $prefix-logcat.txt"
        }
        $done = $records | Where-Object { $_.type -eq 'complete' }
    } until ($done -or (Get-Date) -gt $deadline)

    $lines | Set-Content -LiteralPath "$prefix-logcat.txt" -Encoding UTF8
    if (-not $done) { throw "Timed out; see $prefix-logcat.txt. Make sure the phone is unlocked and LAB_AUTO=true." }
    $computeRecords = @($records | Where-Object { $_.type -eq 'compute' })
    $animationRecords = @($records | Where-Object { $_.type -eq 'animation' })
    $modeRecord = $records | Where-Object { $_.type -eq 'environment' }
    if ($computeRecords.Count -ne 8 -or $animationRecords.Count -ne 18 -or $modeRecord.mode -ne 'release') {
        throw "Incomplete release suite; see $prefix-logcat.txt"
    }
    if ($computeRecords | Where-Object { -not $_.exact_output_match }) {
        throw "Kernel output validation failed; see $prefix-logcat.txt"
    }
    $metadata['battery_after'] = (Invoke-Adb shell dumpsys battery | Out-String)
    [ordered]@{ device = $metadata; results = $records } |
        ConvertTo-Json -Depth 12 | Set-Content -LiteralPath "$prefix-results.json" -Encoding UTF8
    Invoke-Adb shell screencap -p /data/local/tmp/performance-lab.png
    Invoke-Adb pull /data/local/tmp/performance-lab.png "$prefix-screen.png"
    Write-Host "Report: $prefix-results.json"
    $records | Where-Object { $_.type -eq 'compute' } |
        Format-Table workload, engine, median_ms, exact_output_match
} finally {
    Pop-Location
}
