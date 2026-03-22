#!/bin/bash
set -euo pipefail

echo "🚀 Building Windows Signing AMI..."

# Export required variables
export WINDOWS_SIGNING_ADMIN_USER="signadmin"
export WINDOWS_SIGNING_ADMIN_PASSWORD="YourSecurePassword123!"

# Validate
if [[ -z "${WINDOWS_SIGNING_ADMIN_PASSWORD}" ]]; then
  echo "❌ WINDOWS_SIGNING_ADMIN_PASSWORD must be set"
  exit 1
fi

# Build AMI
cd "$(dirname "$0")"
packer init windows-signing-ami.pkr.hcl
packer validate windows-signing-ami.pkr.hcl
packer build windows-signing-ami.pkr.hcl

echo "✅ AMI build complete!"
echo "📋 Check windows-signing-ami-manifest.json for AMI ID"