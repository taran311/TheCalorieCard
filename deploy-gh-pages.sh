#!/usr/bin/env bash
set -euo pipefail

BRANCH_SOURCE="master"
BRANCH_PAGES="gh-pages"
CUSTOM_DOMAIN="thecaloriecard.com"
STASH_NAME="deploy-gh-pages-stash"
TMP_DIR="$(mktemp -d)"

echo "🚀 Deploying Flutter web → gh-pages"

# Must be on master
if [ "$(git branch --show-current)" != "$BRANCH_SOURCE" ]; then
  echo "❌ ABORT: Must run from '$BRANCH_SOURCE'"
  exit 1
fi

# Build
echo "🏗️ Building Flutter web (base-href=/)"
MSYS_NO_PATHCONV=1 flutter build web --release --base-href=/

# Stage ONLY build/web contents
echo "📦 Staging clean web output"
rm -rf "$TMP_DIR"/*
cp -R build/web/* "$TMP_DIR/"

# Stash noise
git stash push -u -m "$STASH_NAME" >/dev/null || true

# Switch to gh-pages
git checkout "$BRANCH_PAGES"

# Safety check
if [ "$(git branch --show-current)" != "$BRANCH_PAGES" ]; then
  echo "❌ ABORT: Not on gh-pages"
  exit 1
fi

# Preserve CNAME
if [ -f CNAME ]; then
  CNAME_VALUE="$(cat CNAME)"
else
  CNAME_VALUE="$CUSTOM_DOMAIN"
fi

# HARD clean gh-pages (static only)
echo "🧹 Cleaning gh-pages"
git rm -rf . >/dev/null 2>&1 || true
rm -rf .dart_tool build android ios linux macos windows || true

# Deploy to ROOT
echo "📂 Deploying site to root"
cp -R "$TMP_DIR"/* .
echo "$CNAME_VALUE" > CNAME
touch .nojekyll

# Commit & push
git add .
git commit -m "Deploy Flutter web (clean root)"
git push origin "$BRANCH_PAGES"

# Restore master
git checkout "$BRANCH_SOURCE"
git stash pop >/dev/null || true
rm -rf "$TMP_DIR"

echo "✅ Deployment complete"
echo "🌍 https://$CUSTOM_DOMAIN/"
