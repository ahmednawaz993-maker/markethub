#!/usr/bin/env bash
# MarketHub deploy script (Git Bash / POSIX).
# Builds the Flutter web release and deploys it to Firebase Hosting.
#
# Usage:
#   ./deploy.sh           # build + deploy hosting only
#   ./deploy.sh --rules   # also deploy Firestore + Storage security rules
#
# Run from the project root (C:/MarketHubNew/markethub).

set -euo pipefail

project="markethub-80276"

targets="hosting"
if [ "${1:-}" = "--rules" ]; then
    targets="hosting,firestore:rules,storage"
fi

echo "==> Building Flutter web release..."
flutter build web --release

echo "==> Deploying [$targets] to '$project'..."
firebase deploy --only "$targets" --project "$project"

echo ""
echo "Deploy complete -> https://$project.web.app"
