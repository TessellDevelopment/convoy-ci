# Windows Signing AMI - Quick Start Guide

## 🎯 What This Does

Creates a Windows Server 2025 AMI pre-configured with all tools needed to sign Windows binaries (`.exe` files) using Azure Trusted Signing via AWS Systems Manager (SSM).

## 🔧 What Was Fixed

### Original Issue
```
winget : The term 'winget' is not recognized as the name of a cmdlet...
```

### Changes Made

1. ✅ **Replaced winget with direct .NET SDK download**
   - Windows Server 2025 doesn't have winget by default
   - Now downloads .NET SDK installer directly from Microsoft

2. ✅ **Improved PATH handling**
   - Properly refreshes PATH after each installation
   - Ensures tools are accessible system-wide

3. ✅ **Enhanced admin user setup**
   - Grants "Log on as batch job" right (required for scheduled tasks)
   - Properly configures user for signing operations

4. ✅ **Added tar verification**
   - Ensures tar utility is available (needed by signing script)

5. ✅ **Better error handling**
   - More verbose output during build
   - Improved verification steps

6. ✅ **SSM Agent configuration**
   - Ensures SSM Agent is running and set to auto-start

## 📦 Files Created/Updated

```
convoy-ci/.github/ci-scripts/
├── windows-signing-ami.pkr.hcl              # ✏️ Updated - Main Packer template
├── windows-signing-userdata.ps1             # ✏️ Updated - WinRM setup script
├── windows-signing-ami.pkrvars.hcl.example  # ✨ New - Example variables
├── build-windows-signing-ami.sh             # ✨ New - Build helper script
├── WINDOWS_SIGNING_AMI_README.md            # ✨ New - Detailed documentation
├── WINDOWS_SIGNING_SETUP.md                 # ✨ New - This file
└── TROUBLESHOOTING.md                       # ✨ New - Troubleshooting guide
```

## 🚀 Quick Start

### Step 1: Set AWS Credentials

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_SESSION_TOKEN="your-session-token"  # if using temporary creds
```

### Step 2: Customize Variables (Optional)

```bash
cd convoy-ci/.github/ci-scripts
cp windows-signing-ami.pkrvars.hcl.example windows-signing-ami.pkrvars.hcl
# Edit the file to set your password and other settings
```

**Important:** Change the default password!

```hcl
signing_admin_password = "YourSecureP@ssw0rd123!"
```

### Step 3: Build the AMI

**Option A: Using the helper script (recommended)**
```bash
./build-windows-signing-ami.sh
```

**Option B: Using Packer directly**
```bash
packer build windows-signing-ami.pkr.hcl
```

**Option C: With custom variables**
```bash
packer build -var-file=windows-signing-ami.pkrvars.hcl windows-signing-ami.pkr.hcl
```

### Step 4: Note the AMI ID

After successful build, you'll see:
```
AMI ID: ami-0123456789abcdef0
Region: ap-south-1
```

Save this AMI ID - you'll need it to launch instances.

## 🖥️ Using the AMI

### Launch an Instance

```bash
aws ec2 run-instances \
  --image-id ami-0123456789abcdef0 \
  --instance-type c5.xlarge \
  --iam-instance-profile Name=YourSSMRole \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=windows-signing-instance}]' \
  --region ap-south-1
```

**Important:** The instance needs an IAM role with:
- `AmazonSSMManagedInstanceCore` (for SSM)
- S3 read/write permissions (for artifact transfer)

### Configure Environment Variables

```bash
# Instance details
export WINDOWS_SIGNING_INSTANCE_ID="i-0123456789abcdef0"
export WINDOWS_SIGNING_AWS_REGION="ap-south-1"
export WINDOWS_SIGNING_S3_BUCKET="your-signing-bucket"

# Admin credentials (must match what you used in Packer)
export WINDOWS_SIGNING_ADMIN_USER="signadmin"
export WINDOWS_SIGNING_ADMIN_PASSWORD="YourSecureP@ssw0rd123!"

# Azure Trusted Signing credentials
export WINDOWS_SIGNING_AZURE_TENANT_ID="your-tenant-id"
export WINDOWS_SIGNING_AZURE_CLIENT_ID="your-client-id"
export WINDOWS_SIGNING_AZURE_CLIENT_SECRET="your-client-secret"
export WINDOWS_SIGNING_ACCOUNT_NAME="your-account-name"
export WINDOWS_SIGNING_PROFILE_NAME="your-profile-name"
export WINDOWS_SIGNING_ENDPOINT="https://your-endpoint.codesigning.azure.net"

# Artifact details
export TAR_FILE="your-artifact"
export SIGNED_TAR_FILE="your-artifact-signed"
export BUILD_ID="12345"
```

### Run the Signing Script

```bash
cd convoy-ci/.github/ci-scripts/bash
./sign-windows-binaries-via-ssm
```

## 📋 What Gets Installed

The AMI includes:

| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | 2.x | S3 operations, SSM communication |
| PowerShell | 7.4.1 | Modern scripting |
| .NET SDK | 8.0.404 | Required for Trusted Signing |
| Azure Trusted Signing Client | 1.0.60 | CLI signing tool |
| TrustedSigning PowerShell Module | Latest | PowerShell signing cmdlets |
| tar | Built-in | Archive operations |

## 🔐 Security Best Practices

1. **Never use default passwords in production**
   - Change `signing_admin_password` before building
   - Use strong passwords (12+ chars, mixed case, numbers, symbols)

2. **Store credentials securely**
   - Use AWS Secrets Manager or Parameter Store
   - Don't commit passwords to Git

3. **Restrict AMI access**
   - Share only with authorized AWS accounts
   - Use AMI permissions to control access

4. **Enable encryption**
   - Consider enabling EBS encryption for the AMI
   - Encrypt S3 buckets used for artifacts

5. **Rotate credentials regularly**
   - Update Azure service principal secrets
   - Rebuild AMI with new admin password periodically

## ⏱️ Build Time & Cost

- **Build time:** 5-10 minutes
- **Instance type:** c5.2xlarge (default)
- **Estimated cost:** ~$0.50 per build
- **Storage:** ~30 GB EBS volume

## 🐛 Troubleshooting

If you encounter issues, check:

1. **TROUBLESHOOTING.md** - Common issues and solutions
2. **Packer logs** - Run with `PACKER_LOG=1` for verbose output
3. **AWS permissions** - Ensure you can create EC2 instances and AMIs
4. **Internet connectivity** - Instance needs internet to download tools

## 📚 Additional Resources

- **Detailed docs:** See `WINDOWS_SIGNING_AMI_README.md`
- **Troubleshooting:** See `TROUBLESHOOTING.md`
- **Packer docs:** https://www.packer.io/docs
- **Azure Trusted Signing:** https://learn.microsoft.com/azure/trusted-signing/

## 🎉 Success Indicators

After building, you should see:

```
✅ All tools verified successfully
✅ AMI built successfully!
AMI ID: ami-xxxxx
```

When running the signing script:

```
✅ Signing pipeline completed successfully
```

## 🔄 Updating the AMI

To update with new tools or configurations:

1. Edit `windows-signing-ami.pkr.hcl`
2. Run `./build-windows-signing-ami.sh`
3. Update your infrastructure to use the new AMI ID
4. (Optional) Deregister old AMI

## 📞 Support

For issues or questions:
- Check the troubleshooting guide
- Review Packer logs
- Contact DevOps team for Tessell-specific issues

