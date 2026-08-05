#!/bin/bash
# Import the Developer ID certificate into a dedicated keychain.
# Required environment:
#   CERTIFICATE_BASE64: base64 of the p12 export (cert+private key)
#   CERTIFICATE_PASSWORD: password used to encrypt the exported p12
#   KEYCHAIN_PASSWORD: password for the temporary keychain
set -e

security create-keychain -p "${KEYCHAIN_PASSWORD}" release.keychain
security default-keychain -s release.keychain
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" release.keychain
security set-keychain-settings -t 3600 -u release.keychain

echo "$CERTIFICATE_BASE64" | base64 --decode > certificate.p12
security import certificate.p12 -k release.keychain -P "${CERTIFICATE_PASSWORD}" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "${KEYCHAIN_PASSWORD}" release.keychain

# Check that the certificate was imported correctly
security find-identity -v -p codesigning release.keychain

rm certificate.p12
