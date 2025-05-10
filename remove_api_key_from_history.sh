#!/bin/bash

# This script removes the API key from Git history using git filter-branch
# IMPORTANT: This will rewrite Git history - only run this if you understand the implications

# Replace this with your actual API key
API_KEY="[REDACTED-API-KEY]"
REPLACEMENT="[REDACTED-API-KEY]"

# First, commit any pending changes
git add .
git commit -m "Prepare for history cleaning"

echo "Removing API key from Git history..."
git filter-branch --force --tree-filter "find . -type f -exec sed -i '' 's/$API_KEY/$REPLACEMENT/g' {} \;" HEAD

# Clean up the repository
echo "Cleaning up the repository..."
git reflog expire --expire=now --all
git gc --prune=now --aggressive

echo "API key has been removed from Git history."
echo "To push these changes to GitHub, use: git push --force-with-lease"
echo "WARNING: This will rewrite history on GitHub. Make sure collaborators are aware."