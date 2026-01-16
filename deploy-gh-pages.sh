#!/usr/bin/env bash
set -e

BRANCH_SOURCE="master"
BRANCH_PAGES="gh-pages"
CUSTOM_DOMAIN="thecaloriecard.com"
TMP_DIR="/tmp/gh-pages-build"

echo "🚀 Deploying Flutter web to GitHub Pages (custom domain: $CUSTOM_DOMAIN)"

# ------------------------------------------------------------------
# 1. Ensure source branch
# ------------------------------------------------------------------
git checkout $BRANCH_SOURCE

# ------------------------------------------------------------------
# 2. Build Flutter web FOR ROOT DOMAIN
# ------------------------------------------------------------------
echo "🏗️ Building Flutter web (base-href=/)"
MSYS_NO_PATHCONV=1 flutter build web --release --base-href=/

# ------------------------------------------------------------------
# 3. Stage build OUTSIDE repo (cannot be deleted by git)
# ------------------------------------------------------------------
echo "📦 Staging web build..."
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
cp -r build/web/* "$TMP_DIR/"

# ------------------------------------------------------------------
# 4. Stash ALL local changes (Flutter always mutates files)
# ------------------------------------------------------------------
echo "📦 Stashing local changes..."
git stash push -u -m "auto-stash-for-gh-pages"

# ------------------------------------------------------------------
# 5. Switch to gh-pages
# ------------------------------------------------------------------
if git show-ref --quiet refs/heads/$BRANCH_PAGES; then
  git checkout $BRANCH_PAGES
else
  git checkout --orphan $BRANCH_PAGES
fi

# ------------------------------------------------------------------
# 6. FORCE WIPE gh-pages (ROOT ONLY)
# ------------------------------------------------------------------
echo "🧹 Wiping gh-pages root..."
git rm -rf . > /dev/null 2>&1 || true

# ------------------------------------------------------------------
# 7. Copy build to ROOT
# ------------------------------------------------------------------
cp -r "$TMP_DIR"/* .

# ------------------------------------------------------------------
# 8. FORCE CUSTOM DOMAIN (THIS IS THE KEY)
# ------------------------------------------------------------------
echo "$CUSTOM_DOMAIN" > CNAME
touch .nojekyll

# ------------------------------------------------------------------
# 9. Commit & push
# ------------------------------------------------------------------
git add .
git commit -m "Deploy Flutter web to custom domain ($CUSTOM_DOMAIN)"
git push origin $BRANCH_PAGES --force

# ------------------------------------------------------------------
# 10. Restore source branch + stash
# ------------------------------------------------------------------
git checkout $BRANCH_SOURCE
git stash pop || true
rm -rf "$TMP_DIR"

echo "✅ Deployment complete!"
echo "🌍 LIVE AT: https://$CUSTOM_DOMAIN/"
