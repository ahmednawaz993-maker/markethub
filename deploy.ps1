# MarketHub deploy script.
# Builds the Flutter web release and deploys it to Firebase Hosting.
#
# Usage:
#   ./deploy.ps1            # build + deploy hosting only
#   ./deploy.ps1 -Rules     # also deploy Firestore + Storage security rules
#
# Run from the project root (C:\MarketHubNew\markethub).

param(
    [switch]$Rules
)

$project = 'markethub-80276'

Write-Host "==> Building Flutter web release..." -ForegroundColor Cyan
flutter build web --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "Build failed. Aborting deploy." -ForegroundColor Red
    exit 1
}

if ($Rules) {
    $targets = 'hosting,firestore:rules,storage'
} else {
    $targets = 'hosting'
}

Write-Host "==> Deploying [$targets] to '$project'..." -ForegroundColor Cyan
firebase deploy --only $targets --project $project
if ($LASTEXITCODE -ne 0) {
    Write-Host "Deploy failed." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Deploy complete -> https://$project.web.app" -ForegroundColor Green
