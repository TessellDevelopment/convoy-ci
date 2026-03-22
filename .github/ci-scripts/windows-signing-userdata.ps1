<powershell>
# Enable WinRM for Packer
Write-Host "Configuring WinRM for Packer..."

# Set Administrator password from user data
$password = "YourSecurePassword123!"
$securePassword = ConvertTo-SecureString $password -AsPlainText -Force
Get-LocalUser -Name "Administrator" | Set-LocalUser -Password $securePassword

# Configure WinRM
winrm quickconfig -q
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="1024"}'

# Configure firewall
netsh advfirewall firewall add rule name="WinRM-HTTP" dir=in localport=5985 protocol=TCP action=allow
netsh advfirewall firewall add rule name="WinRM-HTTPS" dir=in localport=5986 protocol=TCP action=allow

# Restart WinRM
Restart-Service WinRM

Write-Host "WinRM configured successfully"
</powershell>