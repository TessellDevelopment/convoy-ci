variable "aws_region" {
  description = "AWS region for AMI creation"
  default     = "ap-south-1"
}

variable "instance_type" {
  description = "EC2 instance type for building"
  default     = "c5.2xlarge"
}

variable "source_ami_filter" {
  description = "Filter for Windows Server 2025 base AMI"
  default     = "Windows_Server-2025-English-Full-Base-*"
}

variable "signing_admin_user" {
  description = "Admin user for code signing"
  default     = "signadmin"
}

variable "signing_admin_password" {
  description = "Admin password for code signing"
  default     = "YourSecurePassword123!"
  sensitive   = true
}

variable "ami_name_prefix" {
  description = "Prefix for AMI name"
  default     = "tessell-windows-signing"
}

variable "aws_profile" {
  description = "AWS profile to use"
  default     = "402291221517_AdministratorAccess"
}

data "amazon-ami" "windows_2025" {
  filters = {
    name                = var.source_ami_filter
    root-device-type    = "ebs"
    virtualization-type = "hvm"
  }
  most_recent = true
  owners      = ["amazon"]
  region      = var.aws_region
  profile     = var.aws_profile
}

source "amazon-ebs" "windows-signing" {
  region        = var.aws_region
  source_ami    = data.amazon-ami.windows_2025.id
  instance_type = var.instance_type
  profile       = var.aws_profile
  
  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.signing_admin_password
  winrm_insecure = true
  # winrm_use_ssl  = true
  
  ami_name        = "${var.ami_name_prefix}-{{timestamp}}"
  ami_description = "Windows Server 2025 with Azure Trusted Signing tools for Tessell code signing"
  
  # pause_before_connecting = "3m"
  winrm_timeout          = "10m"
  
  user_data_file = "windows-signing-userdata.ps1"
  
  tags = {
    Name        = "tessell-windows-signing-ami"
    Purpose     = "Code signing for Windows binaries"
    ManagedBy   = "Packer"
    Environment = "CI/CD"
  }
  
  run_tags = {
    Name = "packer-windows-signing-builder"
  }
}

build {
  name    = "windows-signing-ami"
  sources = ["source.amazon-ebs.windows-signing"]
  
  #####################################
  # Install AWS CLI
  #####################################
  provisioner "powershell" {
    elevated_user     = "Administrator"
    elevated_password = var.signing_admin_password
    inline = [
      "$ErrorActionPreference = 'Stop'",
      "Write-Host '📦 Installing AWS CLI...'",
      "$ProgressPreference = 'SilentlyContinue'",
      "Invoke-WebRequest -Uri 'https://awscli.amazonaws.com/AWSCLIV2.msi' -OutFile 'C:\\awscliv2.msi'",
      "Start-Process msiexec.exe -ArgumentList '/i C:\\awscliv2.msi /quiet /norestart' -Wait",
      "Remove-Item 'C:\\awscliv2.msi' -Force",
      "$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine')",
      "aws --version"
    ]
  }
  
  #####################################
  # Install PowerShell 7
  #####################################
  provisioner "powershell" {
    elevated_user     = "Administrator"
    elevated_password = var.signing_admin_password
    inline = [
      "$ErrorActionPreference = 'Stop'",
      "Write-Host '📦 Installing PowerShell 7...'",
      "$ProgressPreference = 'SilentlyContinue'",
      "Invoke-WebRequest -Uri 'https://github.com/PowerShell/PowerShell/releases/download/v7.4.1/PowerShell-7.4.1-win-x64.msi' -OutFile 'C:\\pwsh.msi'",
      "Start-Process msiexec.exe -ArgumentList '/i C:\\pwsh.msi /quiet /norestart ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ENABLE_PSREMOTING=1 REGISTER_MANIFEST=1' -Wait",
      "Remove-Item 'C:\\pwsh.msi' -Force",
      "Write-Host '✅ PowerShell 7 installed'"
    ]
  }

  #####################################
  # Ensure tar is available (comes with Windows Server 2019+)
  #####################################
  provisioner "powershell" {
    elevated_user     = "Administrator"
    elevated_password = var.signing_admin_password
    inline = [
      "$ErrorActionPreference = 'Stop'",
      "Write-Host '📦 Verifying tar utility...'",
      "try {",
      "  tar --version",
      "  Write-Host '✅ tar is available'",
      "} catch {",
      "  Write-Host '⚠️ tar not found in PATH, checking system32...'",
      "  if (Test-Path 'C:\\Windows\\System32\\tar.exe') {",
      "    Write-Host '✅ tar.exe found in System32'",
      "  } else {",
      "    Write-Error 'tar.exe not found - required for signing pipeline'",
      "    exit 1",
      "  }",
      "}"
    ]
  }
  
  #####################################
  # Install .NET SDK (required for TrustedSigning)
  #####################################
  provisioner "powershell" {
    elevated_user     = "Administrator"
    elevated_password = var.signing_admin_password
    inline = [
      "$ErrorActionPreference = 'Stop'",
      "Write-Host '📦 Installing .NET 8 SDK...'",
      "$ProgressPreference = 'SilentlyContinue'",
      "",
      "# Use official .NET install script",
      "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12",
      "Invoke-WebRequest -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile 'C:\\dotnet-install.ps1'",
      "",
      "# Install .NET 8 SDK",
      "& C:\\dotnet-install.ps1 -Channel 8.0 -InstallDir 'C:\\Program Files\\dotnet' -NoPath",
      "",
      "# Add to system PATH",
      "$dotnetPath = 'C:\\Program Files\\dotnet'",
      "$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')",
      "if ($machinePath -notlike \"*$dotnetPath*\") {",
      "  [Environment]::SetEnvironmentVariable('Path', \"$machinePath;$dotnetPath\", 'Machine')",
      "}",
      "",
      "# Refresh PATH for current session",
      "$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')",
      "",
      "# Verify installation",
      "dotnet --version",
      "Write-Host '✅ .NET SDK installed successfully'",
      "",
      "# Cleanup",
      "Remove-Item 'C:\\dotnet-install.ps1' -Force"
    ]
  }
  
  #####################################
  # Install Azure Trusted Signing tools
  #####################################
  provisioner "powershell" {
    elevated_user     = "Administrator"
    elevated_password = var.signing_admin_password
    inline = [
      "$ErrorActionPreference = 'Continue'",
      "Write-Host '📦 Installing Azure Trusted Signing client...'",
      "",
      "# Refresh PATH to include dotnet",
      "$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')",
      "",
      "# Try to install the trusted signing client globally (may fail but that's OK)",
      "# We suppress errors and force exit code 0",
      "$output = dotnet tool install --global Microsoft.Trusted.Signing.Client --version 1.0.60 2>&1",
      "if ($LASTEXITCODE -eq 0) {",
      "  Write-Host '  ✅ TrustedSigning CLI tool installed'",
      "} else {",
      "  Write-Host '  ⚠️ TrustedSigning CLI tool install had issues (will use PowerShell module instead)'",
      "  Write-Host \"  Output: $output\"",
      "}",
      "",
      "# Add .dotnet/tools to system PATH for all users",
      "$toolPath = Join-Path $env:USERPROFILE '.dotnet\\tools'",
      "$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')",
      "if ($machinePath -notlike \"*$toolPath*\") {",
      "  [Environment]::SetEnvironmentVariable('Path', \"$machinePath;$toolPath\", 'Machine')",
      "  Write-Host \"  Added $toolPath to system PATH\"",
      "}",
      "",
      "# Force success exit code",
      "exit 0"
    ]
  }
  
  #####################################
  # Install TrustedSigning PowerShell module
  #####################################
  provisioner "powershell" {
    elevated_user     = "Administrator"
    elevated_password = var.signing_admin_password
    inline = [
      "$ErrorActionPreference = 'Stop'",
      "Write-Host '📦 Installing TrustedSigning PowerShell module...'",
      "Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force",
      "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted",
      "Install-Module -Name TrustedSigning -Force -AllowClobber",
      "Import-Module TrustedSigning",
      "Get-Command -Module TrustedSigning"
    ]
  }
  
  #####################################
  # Grant Administrator batch logon rights
  #####################################
  provisioner "powershell" {
    inline = [
      "$ErrorActionPreference = 'Continue'",
      "Write-Host '🔐 Configuring Administrator account for scheduled tasks...'",
      "",
      "# Grant Log on as a batch job right to Administrator (required for schtasks)",
      "$tempFile = [System.IO.Path]::GetTempFileName()",
      "secedit /export /cfg $tempFile /quiet | Out-Null",
      "$content = Get-Content $tempFile",
      "$newContent = @()",
      "$found = 0",
      "foreach ($line in $content) {",
      "  if ($line -match '^SeBatchLogonRight') {",
      "    if ($line -notmatch 'Administrator') {",
      "      $line = $line.TrimEnd() + ',*Administrator'",
      "    }",
      "    $found = 1",
      "  }",
      "  $newContent += $line",
      "}",
      "if ($found -eq 0) {",
      "  $newContent += 'SeBatchLogonRight = *Administrator'",
      "}",
      "$newContent | Set-Content $tempFile",
      "secedit /configure /db secedit.sdb /cfg $tempFile /quiet | Out-Null",
      "Remove-Item $tempFile -Force -ErrorAction SilentlyContinue",
      "Remove-Item -Path secedit.sdb -Force -ErrorAction SilentlyContinue",
      "",
      "Write-Host '✅ Administrator account configured for batch logon'",
      "exit 0"
    ]
  }
  
  #####################################
  # Configure Windows for signing
  #####################################
  provisioner "powershell" {
    inline = [
      "$ErrorActionPreference = 'Continue'",
      "Write-Host '⚙️ Configuring Windows for code signing...'",
      "",
      "# Disable IE Enhanced Security",
      "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Active Setup\\Installed Components\\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}' -Name 'IsInstalled' -Value 0",
      "Set-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Active Setup\\Installed Components\\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}' -Name 'IsInstalled' -Value 0",
      "",
      "# Set execution policy (ignore if already set)",
      "Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction SilentlyContinue | Out-Null",
      "",
      "# Enable long paths",
      "Set-ItemProperty -Path 'HKLM:\\SYSTEM\\CurrentControlSet\\Control\\FileSystem' -Name 'LongPathsEnabled' -Value 1",
      "",
      "# Disable Windows Defender real-time monitoring for build directories",
      "Add-MpPreference -ExclusionPath 'C:\\build-*'",
      "Add-MpPreference -ExclusionPath 'C:\\signing-temp'",
      "",
      "# Ensure SSM Agent is running (required for remote signing)",
      "Write-Host '  Checking SSM Agent...'",
      "$ssmService = Get-Service -Name 'AmazonSSMAgent' -ErrorAction SilentlyContinue",
      "if ($ssmService) {",
      "  if ($ssmService.Status -ne 'Running') {",
      "    Start-Service -Name 'AmazonSSMAgent'",
      "    Write-Host '  ✅ SSM Agent started'",
      "  } else {",
      "    Write-Host '  ✅ SSM Agent already running'",
      "  }",
      "  Set-Service -Name 'AmazonSSMAgent' -StartupType Automatic",
      "} else {",
      "  Write-Host '  ⚠️ SSM Agent not found (will be available in EC2 instance)'",
      "}",
      "",
      "Write-Host '✅ Windows configured for signing'",
      "exit 0"
    ]
  }
  
  #####################################
  # Create working directories
  #####################################
  provisioner "powershell" {
    inline = [
      "$ErrorActionPreference = 'Stop'",
      "Write-Host '📁 Creating working directories...'",
      "New-Item -ItemType Directory -Force -Path 'C:\\signing-temp' | Out-Null",
      "icacls 'C:\\signing-temp' /grant 'Everyone:(OI)(CI)F' /T",
      "Write-Host '✅ Working directories created'"
    ]
  }
  
  #####################################
  # Verify installations
  #####################################
  provisioner "powershell" {
    inline = [
      "$ErrorActionPreference = 'Stop'",
      "Write-Host '🔍 Verifying installations...'",
      "Write-Host ''",
      "",
      "# Refresh PATH from system",
      "$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')",
      "",
      "Write-Host '1️⃣ AWS CLI version:'",
      "aws --version",
      "Write-Host ''",
      "",
      "Write-Host '2️⃣ .NET SDK version:'",
      "dotnet --version",
      "Write-Host ''",
      "",
      "Write-Host '3️⃣ PowerShell 7:'",
      "pwsh --version",
      "Write-Host ''",
      "",
      "Write-Host '4️⃣ TrustedSigning client:'",
      "try {",
      "  $tsClient = Get-Command TrustedSigningClient -ErrorAction SilentlyContinue",
      "  if ($tsClient) {",
      "    Write-Host \"  ✅ Found at: $($tsClient.Source)\"",
      "  } else {",
      "    Write-Host \"  ⚠️ TrustedSigningClient not in PATH, checking dotnet tools...\"",
      "    dotnet tool list --global | Select-String 'microsoft.trusted.signing.client'",
      "  }",
      "} catch {",
      "  Write-Host \"  ⚠️ Warning: $_\"",
      "}",
      "Write-Host ''",
      "",
      "Write-Host '5️⃣ TrustedSigning PowerShell module:'",
      "$module = Get-Module -ListAvailable TrustedSigning",
      "if ($module) {",
      "  Write-Host \"  ✅ Version: $($module.Version)\"",
      "} else {",
      "  Write-Host \"  ❌ Module not found\"",
      "  exit 1",
      "}",
      "Write-Host ''",
      "",
      "Write-Host '✅ All critical tools verified successfully'"
    ]
  }
  
  #####################################
  # Cleanup
  #####################################
  provisioner "powershell" {
    inline = [
      "Write-Host '🧹 Cleaning up...'",
      "Remove-Item -Path 'C:\\Windows\\Temp\\*' -Recurse -Force -ErrorAction SilentlyContinue",
      "Clear-RecycleBin -Force -ErrorAction SilentlyContinue",
      "Write-Host '✅ Cleanup complete'"
    ]
  }
  
  post-processor "manifest" {
    output     = "windows-signing-ami-manifest.json"
    strip_path = true
  }
}
