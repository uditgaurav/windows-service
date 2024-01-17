# Check for administrative privileges
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script requires administrative privileges."
    exit
}

# Define the tools, service binary, and their expected paths
$tools = @(
    @{
        Name = "clumsy";
        DownloadUrl = "https://github.com/jagt/clumsy/releases/download/0.3/clumsy-0.3-win64-a.zip";
        Destination = "$env:USERPROFILE\Downloads\clumsy.zip"
        ExtractedPath = "$env:USERPROFILE\Downloads\clumsy\clumsy.exe"
    },
    @{
        Name = "diskpd";
        DownloadUrl = "https://github.com/microsoft/diskspd/releases/download/v2.1/DiskSpd.ZIP";
        Destination = "$env:USERPROFILE\Downloads\diskspd.zip"
        ExtractedPath = "$env:USERPROFILE\Downloads\diskspd\diskspd.exe"
    },
    @{
        Name = "Testlimit";
        DownloadUrl = "https://download.sysinternals.com/files/Testlimit.zip";
        Destination = "$env:USERPROFILE\Downloads\testlimit.zip"
        ExtractedPath = "$env:USERPROFILE\Downloads\Testlimit\Testlimit.exe"
    }
)

$serviceBinary = @{
    Name = "windows-chaos-agent";
    DownloadUrl = "https://github.com/uditgaurav/windows-service/raw/master/bin/windows-chaos-agent.exe";
    Path = "C:\Users\Administrator\Downloads\windows-chaos-agent.exe"
}

# Download and extract each tool if not already present
foreach ($tool in $tools) {
    if (-not (Test-Path $tool.ExtractedPath)) {
        Write-Host ("Downloading {0}..." -f $tool.Name)
        Invoke-WebRequest -Uri $tool.DownloadUrl -OutFile $tool.Destination

        Write-Host ("Extracting {0}..." -f $tool.Name)
        Expand-Archive -Path $tool.Destination -DestinationPath (Split-Path $tool.ExtractedPath) -Force

        # Add to PATH if not already present
        $env:Path += ";" + (Split-Path $tool.ExtractedPath)
    } else {
        Write-Host ("{0} is already present." -f $tool.Name)
    }
}

# Download the service binary if not already present
if (-not (Test-Path $serviceBinary.Path)) {
    Write-Host ("Downloading {0} binary..." -f $serviceBinary.Name)
    Invoke-WebRequest -Uri $serviceBinary.DownloadUrl -OutFile $serviceBinary.Path
} else {
    Write-Host ("{0} binary is already present." -f $serviceBinary.Name)
}

# Set Administrator username and password
$AdminUser = ".\Administrator"
Write-Host "Using default Administrator username: $AdminUser"
$AdminPass = Read-Host -Prompt "Enter Administrator password" -AsSecureString

# Create and configure the service
$serviceName = "WindowsChaosAgent"
$sc = sc.exe
& $sc create $serviceName binPath= $serviceBinary.Path start= auto obj= $AdminUser password= [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminPass))

if ($LASTEXITCODE -eq 0) {
    Write-Host "Service created successfully."
} else {
    Write-Host "Failed to create service. Error code: $LASTEXITCODE"
    exit
}

# Start the service
& $sc start $serviceName

if ($LASTEXITCODE -eq 0) {
    Write-Host "Service started successfully."
} else {
    Write-Host "Failed to start service. Error code: $LASTEXITCODE"
    exit
}

Write-Host "Setup complete. Press any key to close this window..."
pause
