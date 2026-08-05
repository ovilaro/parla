#!/bin/bash
# Notarize and staple every DMG in the current directory.
# Required environment: APPLE_ID, TEAM_ID, APP_PASSWORD
set -e

for dmg in *.dmg; do
    echo "Notarizing ${dmg}..."
    result=$(xcrun notarytool submit "${dmg}" \
        --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD" \
        --wait --output-format json) || true
    echo "${result}"
    id=$(echo "${result}" | jq -r '.id // empty' 2>/dev/null || true)
    status=$(echo "${result}" | jq -r '.status // empty' 2>/dev/null || true)
    if [ "${status}" != "Accepted" ]; then
        echo "::error::Notarization of ${dmg} failed (status: ${status:-unknown})"
        if [ -n "${id}" ]; then
            # Fetch the per-file rejection reasons from Apple
            xcrun notarytool log "${id}" \
                --apple-id "$APPLE_ID" --team-id "$TEAM_ID" --password "$APP_PASSWORD" || true
        fi
        exit 1
    fi
    xcrun stapler staple "${dmg}"
    xcrun stapler validate "${dmg}"
done
