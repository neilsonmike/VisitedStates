#!/bin/bash

# This script runs before the Xcode build in CI environments
# It ensures APIKeys.plist exists by either using the template or creating it with environment variables

API_KEYS_PATH="$CI_WORKSPACE/VisitedStates/Utilities/APIKeys.plist"
API_KEYS_TEMPLATE_PATH="$CI_WORKSPACE/VisitedStates/Utilities/APIKeys.plist.template"

echo "= Creating APIKeys.plist for CI build..."

# If template exists, copy it
if [ -f "$API_KEYS_TEMPLATE_PATH" ]; then
    echo "Using template file as base..."
    cp "$API_KEYS_TEMPLATE_PATH" "$API_KEYS_PATH"
else
    # Create a new file
    echo "Creating new APIKeys.plist file..."
    cat > "$API_KEYS_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>GoogleSheetsAPIKey</key>
    <string>CI_PLACEHOLDER</string>
</dict>
</plist>
EOF
fi

# If we have API key in environment variables, update the file
if [ ! -z "$GOOGLE_SHEETS_API_KEY" ]; then
    echo "Updating APIKeys.plist with environment variable..."
    # For macOS/Linux CI environments:
    sed -i '' "s/YOUR_API_KEY_HERE/$GOOGLE_SHEETS_API_KEY/g" "$API_KEYS_PATH"
    sed -i '' "s/CI_PLACEHOLDER/$GOOGLE_SHEETS_API_KEY/g" "$API_KEYS_PATH"
fi

echo " APIKeys.plist ready for build"
echo "File contents (keys redacted):"
cat "$API_KEYS_PATH" | sed 's/<string>.*<\/string>/<string>***REDACTED***<\/string>/g'