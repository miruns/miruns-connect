# Miruns Flutter Development Script
# Run this to start development with hot reload

param(
    [string]$Device = "emulator-5554"
)

Write-Host "🚀 Starting Miruns Flutter Development..." -ForegroundColor Cyan
Write-Host ""

# Check if device is connected
Write-Host "📱 Checking device connection..." -ForegroundColor Yellow
$devices = flutter devices 2>&1 | Out-String
if ($devices -notmatch $Device) {
    Write-Host "❌ Device $Device not found. Available devices:" -ForegroundColor Red
    flutter devices
    exit 1
}

Write-Host "✅ Device found: $Device" -ForegroundColor Green
Write-Host ""

# Start the app with hot reload
Write-Host "🔥 Starting Flutter with hot reload enabled..." -ForegroundColor Cyan
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Blue
Write-Host "  Hot Reload Commands:" -ForegroundColor Yellow
Write-Host "  • Press 'r' to hot reload (fast)" -ForegroundColor White
Write-Host "  • Press 'R' to hot restart (full restart)" -ForegroundColor White
Write-Host "  • Press 'h' for help" -ForegroundColor White
Write-Host "  • Press 'q' to quit" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Blue
Write-Host ""

# Run Flutter
flutter run -d $Device --hot
