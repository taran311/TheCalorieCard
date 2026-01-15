#!/usr/bin/env bash
set -e

REPO_NAME="TheCalorieCard"
BRANCH_SOURCE="master"
BRANCH_PAGES="gh-pages"
TMP_DIR=".gh-pages-build"

echo "🚀 Deploying Flutter web to GitHub Pages..."

# 1. Ensure source branch
git checkout $BRANCH_SOURCE

# 2. Build Flutter web (disable Git Bash path conversion)
echo "🏗️ Building Flutter web..."
MSYS_NO_PATHCONV=1 flutter build web --release --base-href=/$REPO_NAME/

# 3. Stage web build safely
echo "📦 Staging web build..."
rm -rf $TMP_DIR
mkdir $TMP_DIR
cp -r build/web/* $TMP_DIR/

# 4. Switch / create gh-pages
if git show-ref --quiet refs/heads/$BRANCH_PAGES; then
  git checkout $BRANCH_PAGES
else
  git checkout --orphan $BRANCH_PAGES
fi

# 5. Wipe gh-pages contents
git rm -rf . > /dev/null 2>&1 || true

# 6. Deploy staged build
cp -r $TMP_DIR/* .
touch .nojekyll

# 7. Commit & push
git add .
git commit -m "Deploy Flutter web build"
git push origin $BRANCH_PAGES --force

# 8. Return to source branch & cleanup
git checkout $BRANCH_SOURCE
rm -rf $TMP_DIR

echo "✅ Deployment complete!"
echo "🌍 https://taran311.github.io/$REPO_NAME/"
