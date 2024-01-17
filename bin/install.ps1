 # Check for administrative privileges
$identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script requires administrative privileges."
    exit
}

# Base path for all dependencies
$chaosBasePath = "$env:USERPROFILE\Downloads\chaos"

# Dependencies, service binary, and their names
$tools = @(
    @{
        Name = "clumsy";
        DownloadUrl = "https://github.com/jagt/clumsy/releases/download/0.3/clumsy-0.3-win64-a.zip";
        Destination = "$chaosBasePath\clumsy.zip";
        ExecutablePath = "$chaosBasePath\clumsy";
        ExractPath = "$chaosBasePath\clumsy"
    },
    @{
        Name = "diskspd";
        DownloadUrl = "https://github.com/microsoft/diskspd/releases/download/v2.1/DiskSpd.ZIP";
        Destination = "$chaosBasePath\diskspd.zip";
        ExecutablePath = "$chaosBasePath\diskspd\amd64";
        ExractPath = "$chaosBasePath\diskspd"
    },
    @{
        Name = "Testlimit";
        DownloadUrl = "https://download.sysinternals.com/files/Testlimit.zip";
        Destination = "$chaosBasePath\testlimit.zip";
        ExecutablePath = "$chaosBasePath\Testlimit";
        ExractPath = "$chaosBasePath\Testlimit"
    }
)

$serviceBinary = @{
    Name = "windows-chaos-agent";
    DownloadUrl = "https://github.com/uditgaurav/windows-service/raw/master/bin/windows-chaos-agent.exe";
    Path = "$chaosBasePath\windows-chaos-agent.exe"
}

# Create base path directory if it doesn't exist
if (-not (Test-Path $chaosBasePath)) {
    New-Item -Path $chaosBasePath -ItemType Directory
}

# Download and extract each tool, then add its path to the system PATH variable
foreach ($tool in $tools) {
    if (-not (Test-Path $tool.Destination)) {
        Write-Host ("Downloading {0}..." -f $tool.Name)
        Invoke-WebRequest -Uri $tool.DownloadUrl -OutFile $tool.Destination
        Write-Host ("Extracting {0}..." -f $tool.Name)
        Expand-Archive -Path $tool.Destination -DestinationPath $tool.ExractPath -Force

        $currentPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine)
        if (-not ($currentPath -like "*$($tool.ExecutablePath)*")) {
            Write-Host ("Adding {0} to PATH..." -f $tool.Name)
            $newPath = $currentPath + ";" + $tool.ExecutablePath
            [Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::Machine)
        } else {
            Write-Host ("{0} path is already in PATH." -f $tool.Name)
        }
    } else {
        Write-Host ("{0} is already downloaded." -f $tool.Name)
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
$defaultAdminUser = ".\Administrator"
$AdminUser = Read-Host -Prompt "Enter Administrator username"
if ([string]::IsNullOrWhiteSpace($AdminUser)) {
    $AdminUser = $defaultAdminUser
}
$AdminPass = Read-Host -Prompt "Enter Administrator password" -AsSecureString

# Create and configure the service in auto mode
$serviceName = "WindowsChaosAgent"
$servicePath = "$chaosBasePath\windows-chaos-agent.exe"
$adminPassPlainText = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminPass))

# Arguments for the sc command
$scArgs = @("create", $serviceName, "binPath=", $servicePath, "start=", "auto", "obj=", $AdminUser, "password=", $adminPassPlainText)

# Execute the command using Start-Process
Start-Process "sc" -ArgumentList $scArgs -NoNewWindow -Wait

if ($LASTEXITCODE -eq 0) {
    Write-Host "Service created successfully."
} else {
    Write-Host "Failed to create service. Error code: $LASTEXITCODE"
    exit
}

# Start the service
Start-Service -Name $serviceName

if ($LASTEXITCODE -eq 0) {
    Write-Host "Service started successfully."
} else {
    Write-Host "Failed to start service. Error code: $LASTEXITCODE"
    exit
}
