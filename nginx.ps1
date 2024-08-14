# Set execution policy
Set-ExecutionPolicy Bypass -Scope Process -Force

# Install Chocolately
Set-ExecutionPolicy Bypass -Scope Process -Force;
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072;
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

# Install Nginx
choco install nginx -y

# Start Nginx and configure it to start automatically on boot
Start-Process -FilePath "C:\nginx\nginx.exe"
Set-Service -Name nginx -StartupType Automatic

# Firewall rule to allow traffic on port 80
New-NetFirewallRule -DisplayName "Allow HTTP traffic on port 80" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 80 -Enabled True

# Output the status to confirm everything is set up
Get-Service -Name nginx
