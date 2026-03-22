# Windows Signing AMI - Packer Template

This Packer template creates an AWS AMI (Amazon Machine Image) for Windows Server 2025 configured with all necessary tools for signing Windows binaries using Azure Trusted Signing.

## 🎯 Purpose

Creates a pre-configured Windows instance that can be used by the `sign-windows-binaries-via-ssm` script to sign `.exe` files via AWS Systems Manager (SSM).

## 📋 Prerequisites

1. **Packer installed** (v1.9.0+)
   ```bash
   brew install packer  # macOS
   # or download from https://www.packer.io/downloads
   ```

2. **AWS credentials configured**
   ```bash
   export AWS_ACCESS_KEY_ID="your-access-key"
   export AWS_SECRET_ACCESS_KEY="your-secret-key"
   export AWS_SESSION_TOKEN="your-session-token"  # if using temporary credentials
   ```

3. **AWS Profile** (optional, if not using environment variables)
   - Update `aws_profile` variable in the `.pkr.hcl` file

## 🛠️ What Gets Installed

The AMI includes:

- ✅ **AWS CLI v2** - For S3 operations and SSM communication
- ✅ **PowerShell 7** - Modern PowerShell for scripting
- ✅ **.NET 8 SDK** - Required for Azure Trusted Signing tools
- ✅ **Azure Trusted Signing Client** - CLI tool for code signing
- ✅ **TrustedSigning PowerShell Module** - PowerShell cmdlets for signing
- ✅ **tar utility** - For extracting/creating archives
- ✅ **Admin user** - Pre-configured with necessary permissions

## 🚀 Building the AMI

### Basic Build

```bash
cd convoy-ci/.github/ci-scripts
packer build windows-signing-ami.pkr.hcl
```

### Custom Variables

```bash
packer build \
  -var 'aws_region=us-east-1' \
  -var 'instance_type=c5.xlarge' \
  -var 'signing_admin_user=myuser' \
  -var 'signing_admin_password=MySecurePass123!' \
  windows-signing-ami.pkr.hcl
```

### Using Variables File

Create `variables.pkrvars.hcl`:
```hcl
aws_region              = "ap-south-1"
instance_type           = "c5.2xlarge"
signing_admin_user      = "signadmin"
signing_admin_password  = "YourSecurePassword123!"
ami_name_prefix         = "tessell-windows-signing"
```

Then build:
```bash
packer build -var-file=variables.pkrvars.hcl windows-signing-ami.pkr.hcl
```

## 📝 Configuration Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `ap-south-1` | AWS region for AMI creation |
| `instance_type` | `c5.2xlarge` | EC2 instance type for building |
| `source_ami_filter` | `Windows_Server-2025-English-Full-Base-*` | Base AMI filter |
| `signing_admin_user` | `signadmin` | Admin username for signing |
| `signing_admin_password` | `YourSecurePassword123!` | Admin password (change this!) |
| `ami_name_prefix` | `tessell-windows-signing` | Prefix for AMI name |
| `aws_profile` | `402291221517_AdministratorAccess` | AWS profile to use |

## 🔐 Security Notes

1. **Change the default password** - Never use the default password in production
2. **Store credentials securely** - Use AWS Secrets Manager or Parameter Store
3. **Restrict AMI access** - Share only with authorized AWS accounts
4. **Enable encryption** - Consider enabling EBS encryption for the AMI

## 🎬 Using the AMI

After the AMI is created:

1. **Launch an EC2 instance** from the AMI
2. **Note the Instance ID** - You'll need this for the signing script
3. **Ensure IAM role** - Instance needs permissions for S3 and SSM
4. **Set environment variables** for the signing script:

```bash
export WINDOWS_SIGNING_INSTANCE_ID="i-0123456789abcdef0"
export WINDOWS_SIGNING_AWS_REGION="ap-south-1"
export WINDOWS_SIGNING_S3_BUCKET="your-signing-bucket"
export WINDOWS_SIGNING_ADMIN_USER="signadmin"
export WINDOWS_SIGNING_ADMIN_PASSWORD="YourSecurePassword123!"
export WINDOWS_SIGNING_AZURE_TENANT_ID="your-tenant-id"
export WINDOWS_SIGNING_AZURE_CLIENT_ID="your-client-id"
export WINDOWS_SIGNING_AZURE_CLIENT_SECRET="your-client-secret"
export WINDOWS_SIGNING_ACCOUNT_NAME="your-account-name"
export WINDOWS_SIGNING_PROFILE_NAME="your-profile-name"
export WINDOWS_SIGNING_ENDPOINT="https://your-endpoint.codesigning.azure.net"
```

5. **Run the signing script**:
```bash
./sign-windows-binaries-via-ssm
```

## 🐛 Troubleshooting

### Build fails with "winget not found"
- ✅ **Fixed** - Now uses direct .NET SDK download instead of winget

### WinRM connection timeout
- Increase `winrm_timeout` in the template
- Check security group allows port 5985

### TrustedSigning module not found
- Verify PowerShell Gallery is accessible
- Check internet connectivity during build

### Signing fails in production
- Verify admin user has "Log on as batch job" right
- Check scheduled task permissions
- Ensure Azure credentials are correct

## 📊 Build Output

After successful build, you'll get:

1. **AMI ID** - Use this to launch instances
2. **Manifest file** - `windows-signing-ami-manifest.json` with build details
3. **Tags** - AMI tagged with Name, Purpose, ManagedBy, Environment

## 🔄 Updating the AMI

To update the AMI with new tools or configurations:

1. Edit `windows-signing-ami.pkr.hcl`
2. Run `packer build` again
3. Update your infrastructure to use the new AMI ID
4. Deregister old AMI (optional)

## 📚 Related Files

- `windows-signing-ami.pkr.hcl` - Main Packer template
- `sign-windows-binaries-via-ssm` - Signing script that uses this AMI
- `windows-signing-userdata.ps1` - User data script (if exists)

## ⏱️ Build Time

Typical build time: **5-10 minutes**

- Instance launch: ~2 min
- Software installation: ~3-5 min
- Configuration: ~1-2 min
- AMI creation: ~1 min

