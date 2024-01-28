 param (
    [string]$AdminUser = ".\Administrator",
    [Parameter(Mandatory=$true)]
    [string]$AdminPass
)

# Convert the password from a plain string to a secure string
$secureAdminPass = ConvertTo-SecureString $AdminPass -AsPlainText -Force

try {
    # Check for administrative privileges
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script requires administrative privileges."
    }

    # Base path for all dependencies
    $chaosBasePath = "C:\HCE"

    # Create base path directory if it doesn't exist
    if (-not (Test-Path $chaosBasePath)) {
        New-Item -Path $chaosBasePath -ItemType Directory
    }
} catch {
    Write-Error "Error in setting up base path: $_"
    exit
}

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
    Name = "windows-chaos-infrastructure";
    DownloadUrl = "https://github.com/uditgaurav/windows-service/raw/master/bin/windows-chaos-infrastructure.exe";
    Path = "$chaosBasePath\windows-chaos-infrastructure.exe"
}

foreach ($tool in $tools) {
    try {
        if (-not (Test-Path $tool.Destination)) {
            Write-Host ("Downloading {0}..." -f $tool.Name)
            Invoke-WebRequest -Uri $tool.DownloadUrl -OutFile $tool.Destination -ErrorAction Stop
            Write-Host ("Extracting {0}..." -f $tool.Name)
            Expand-Archive -Path $tool.Destination -DestinationPath $tool.ExractPath -Force -ErrorAction Stop
            Remove-Item -Path $tool.Destination -Force

            # Add tool executable path to the system PATH variable
            $currentPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine)
            if (-not ($currentPath -like "*$($tool.ExecutablePath)*")) {
                $newPath = $currentPath + ";" + $tool.ExecutablePath
                [Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::Machine)
            }
        } else {
            Write-Host ("{0} is already downloaded." -f $tool.Name)
        }
    } catch {
        Write-Error "Error downloading or extracting ${tool.Name}: $_"
        exit
    }
}

try {
    if (-not (Test-Path $serviceBinary.Path)) {
        Write-Host ("Downloading {0} binary..." -f $serviceBinary.Name)
        Invoke-WebRequest -Uri $serviceBinary.DownloadUrl -OutFile $serviceBinary.Path -ErrorAction Stop
    } else {
        Write-Host ("{0} binary is already present." -f $serviceBinary.Name)
    }

    # Create and configure the service in auto mode
    $serviceName = "WindowsChaosInfrastructure"
    $servicePath = "$chaosBasePath\windows-chaos-infrastructure.exe"
    $adminPassPlainText = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureAdminPass))

    # Arguments for the sc command
    $scArgs = @("create", $serviceName, "binPath=", $servicePath, "start=", "auto", "obj=", $AdminUser, "password=", $adminPassPlainText)
    Start-Process "sc" -ArgumentList $scArgs -NoNewWindow -Wait

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create service with provided credentials. Error code: $LASTEXITCODE."
    }

    # Start the service
    Start-Service -Name $serviceName -ErrorAction Stop
    Write-Host "Service created and started successfully."
} catch {
    Write-Error "Error in service setup or starting the service: $_"
    exit
}
