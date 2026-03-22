# Windows Signing AMI - Troubleshooting Guide

## Common Build Issues

### 1. "winget is not recognized" Error

**Problem:**
```
winget : The term 'winget' is not recognized as the name of a cmdlet...
```

**Solution:**
✅ **FIXED** - The template now uses direct .NET SDK download instead of winget.

If you still see this error, you're using an old version of the template. Pull the latest changes.

---

### 2. WinRM Connection Timeout

**Problem:**
```
Waiting for WinRM to become available...
Timeout waiting for WinRM
```

**Solutions:**

1. **Increase timeout:**
   ```hcl
   winrm_timeout = "45m"  # Increase from 30m
   ```

2. **Add pause before connecting:**
   ```hcl
   pause_before_connecting = "5m"
   ```

3. **Check security group:**
   - Ensure port 5985 is open
   - Packer creates temporary security group automatically

4. **Verify user data:**
   - Check `windows-signing-userdata.ps1` is present
   - Ensure it's configuring WinRM correctly

---

### 3. .NET SDK Installation Fails

**Problem:**
```
Failed to install .NET SDK
```

**Solutions:**

1. **Check internet connectivity:**
   - Instance needs internet access to download .NET SDK
   - Verify NAT Gateway or Internet Gateway is configured

2. **Use different .NET version:**
   Update the download URL in the template:
   ```powershell
   $dotnetUrl = 'https://download.visualstudio.microsoft.com/download/pr/...'
   ```

3. **Manual verification:**
   After build, check if dotnet is installed:
   ```powershell
   dotnet --version
   ```

---

### 4. TrustedSigning Module Installation Fails

**Problem:**
```
Install-Module : Unable to find repository 'PSGallery'
```

**Solutions:**

1. **Check PowerShell Gallery access:**
   ```powershell
   Get-PSRepository
   Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
   ```

2. **Install NuGet provider first:**
   ```powershell
   Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
   ```

3. **Use alternative source:**
   Download module manually and install offline

---

### 5. Admin User Creation Fails

**Problem:**
```
New-LocalUser : Password does not meet complexity requirements
```

**Solutions:**

1. **Use complex password:**
   - At least 8 characters
   - Uppercase + lowercase + numbers + special chars
   - Example: `MySecureP@ssw0rd123!`

2. **Update variable:**
   ```hcl
   signing_admin_password = "YourComplexP@ssw0rd123!"
   ```

---

### 6. AWS Credentials Issues

**Problem:**
```
Error: No valid credential sources found
```

**Solutions:**

1. **Set environment variables:**
   ```bash
   export AWS_ACCESS_KEY_ID="your-key"
   export AWS_SECRET_ACCESS_KEY="your-secret"
   export AWS_SESSION_TOKEN="your-token"  # if using temporary creds
   ```

2. **Use AWS profile:**
   ```bash
   export AWS_PROFILE="your-profile-name"
   ```

3. **Update Packer template:**
   ```hcl
   aws_profile = "your-profile-name"
   ```

---

## Runtime Issues (After AMI is Created)

### 7. Signing Script Fails - "TrustedSigningClient not found"

**Problem:**
Signing fails because TrustedSigningClient is not in PATH

**Solutions:**

1. **Verify installation in AMI:**
   ```powershell
   Get-Command TrustedSigningClient
   dotnet tool list --global
   ```

2. **Add to PATH manually:**
   ```powershell
   $env:Path += ";$env:USERPROFILE\.dotnet\tools"
   ```

3. **Rebuild AMI** with latest template

---

### 8. Scheduled Task Fails - "Access Denied"

**Problem:**
```
schtasks : ERROR: Access is denied
```

**Solutions:**

1. **Verify admin user exists:**
   ```powershell
   Get-LocalUser -Name signadmin
   Get-LocalGroupMember -Group Administrators
   ```

2. **Check "Log on as batch job" right:**
   ```powershell
   secedit /export /cfg C:\temp\secpol.cfg
   # Look for SeBatchLogonRight
   ```

3. **Grant right manually:**
   - Run `secpol.msc`
   - Local Policies → User Rights Assignment
   - "Log on as a batch job"
   - Add user

---

### 9. SSM Command Timeout

**Problem:**
```
Waiting for command to complete (timeout: 5min)...
Timeout
```

**Solutions:**

1. **Check SSM Agent:**
   ```powershell
   Get-Service AmazonSSMAgent
   Start-Service AmazonSSMAgent
   ```

2. **Verify IAM role:**
   - Instance needs `AmazonSSMManagedInstanceCore` policy
   - Or custom policy with SSM permissions

3. **Check instance connectivity:**
   ```bash
   aws ssm describe-instance-information \
     --filters "Key=InstanceIds,Values=i-xxxxx"
   ```

---

### 10. Signature Verification Fails

**Problem:**
```
Signature verification failed: NotSigned
```

**Solutions:**

1. **Check Azure credentials:**
   ```bash
   echo $WINDOWS_SIGNING_AZURE_TENANT_ID
   echo $WINDOWS_SIGNING_AZURE_CLIENT_ID
   # Don't echo the secret!
   ```

2. **Verify certificate profile:**
   - Ensure profile name is correct
   - Check Azure Trusted Signing account is active

3. **Test signing manually:**
   ```powershell
   Invoke-TrustedSigning `
     -Endpoint "https://your-endpoint.codesigning.azure.net" `
     -CodeSigningAccountName "your-account" `
     -CertificateProfileName "your-profile" `
     -Files "C:\test.exe"
   ```

---

## Debugging Tips

### Enable Verbose Logging

In Packer template:
```hcl
provisioner "powershell" {
  inline = [
    "$VerbosePreference = 'Continue'",
    "$DebugPreference = 'Continue'",
    # ... your commands
  ]
}
```

### Check Build Logs

```bash
# Run with debug output
PACKER_LOG=1 packer build windows-signing-ami.pkr.hcl
```

### Connect to Build Instance

1. **Don't terminate on error:**
   ```hcl
   error_cleanup_provisioner {
     # Keep instance running for debugging
   }
   ```

2. **Get instance ID from Packer output**

3. **Connect via Session Manager:**
   ```bash
   aws ssm start-session --target i-xxxxx
   ```

### Verify AMI Contents

After AMI is created:

1. Launch test instance
2. Connect via RDP or Session Manager
3. Verify installations:
   ```powershell
   aws --version
   dotnet --version
   Get-Module -ListAvailable TrustedSigning
   Get-Command TrustedSigningClient
   ```

---

## Getting Help

If you're still stuck:

1. **Check Packer logs** - Look for specific error messages
2. **Verify AWS permissions** - Ensure you can create EC2 instances, AMIs
3. **Test components individually** - Install tools manually on a test instance
4. **Review signing script** - Ensure it matches AMI configuration

For Tessell-specific issues, contact the DevOps team.

