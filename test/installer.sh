#!/bin/bash
# Installer for test

set -e

echo "🔧 Installing test..."

# Install to /usr/local/bin (may require sudo)
install -m 755 script.sh /usr/local/bin/test

echo "✅ Installed test to /usr/local/bin"
