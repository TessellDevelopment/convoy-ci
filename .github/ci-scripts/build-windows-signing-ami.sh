#!/bin/bash
set -euo pipefail

# Build Windows Signing AMI using Packer
# This script helps build the Windows Server 2025 AMI with all signing tools pre-installed

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Building Windows Signing AMI${NC}"
echo ""

# Check if Packer is installed
if ! command -v packer &> /dev/null; then
    echo -e "${RED}❌ Packer is not installed${NC}"
    echo "Install it from: https://www.packer.io/downloads"
    echo "Or use: brew install packer (macOS)"
    exit 1
fi

echo -e "${GREEN}✅ Packer version:${NC}"
packer version
echo ""

# Check AWS credentials
if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]] && [[ -z "${AWS_PROFILE:-}" ]]; then
    echo -e "${YELLOW}⚠️  No AWS credentials found in environment${NC}"
    echo "Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY, or AWS_PROFILE"
    echo ""
    read -p "Do you want to continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if custom variables file exists
VARS_FILE="windows-signing-ami.pkrvars.hcl"
if [[ -f "$VARS_FILE" ]]; then
    echo -e "${GREEN}✅ Using custom variables from: $VARS_FILE${NC}"
    VARS_ARG="-var-file=$VARS_FILE"
else
    echo -e "${YELLOW}⚠️  No custom variables file found${NC}"
    echo "Using default values from windows-signing-ami.pkr.hcl"
    echo "To customize, copy windows-signing-ami.pkrvars.hcl.example to $VARS_FILE"
    VARS_ARG=""
fi
echo ""

# Validate Packer template
echo -e "${BLUE}🔍 Validating Packer template...${NC}"
if packer validate $VARS_ARG windows-signing-ami.pkr.hcl; then
    echo -e "${GREEN}✅ Template is valid${NC}"
else
    echo -e "${RED}❌ Template validation failed${NC}"
    exit 1
fi
echo ""

# Confirm before building
echo -e "${YELLOW}⚠️  This will create a new AMI in AWS${NC}"
echo "Estimated time: 5-10 minutes"
echo "Estimated cost: ~\$0.50 (c5.2xlarge for 10 minutes)"
echo ""
read -p "Continue with build? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Build cancelled"
    exit 0
fi

# Build the AMI
echo ""
echo -e "${BLUE}🏗️  Building AMI...${NC}"
echo ""

if packer build $VARS_ARG windows-signing-ami.pkr.hcl; then
    echo ""
    echo -e "${GREEN}✅ AMI built successfully!${NC}"
    echo ""
    
    # Show the manifest if it exists
    if [[ -f "windows-signing-ami-manifest.json" ]]; then
        echo -e "${BLUE}📋 Build Details:${NC}"
        AMI_ID=$(jq -r '.builds[0].artifact_id' windows-signing-ami-manifest.json | cut -d: -f2)
        AMI_REGION=$(jq -r '.builds[0].artifact_id' windows-signing-ami-manifest.json | cut -d: -f1)
        
        echo "  AMI ID: $AMI_ID"
        echo "  Region: $AMI_REGION"
        echo ""
        echo -e "${GREEN}🎉 You can now launch instances from this AMI${NC}"
        echo ""
        echo "Next steps:"
        echo "1. Launch an EC2 instance from AMI: $AMI_ID"
        echo "2. Note the instance ID"
        echo "3. Set WINDOWS_SIGNING_INSTANCE_ID environment variable"
        echo "4. Run: ./sign-windows-binaries-via-ssm"
    fi
else
    echo ""
    echo -e "${RED}❌ AMI build failed${NC}"
    echo "Check the output above for errors"
    exit 1
fi

