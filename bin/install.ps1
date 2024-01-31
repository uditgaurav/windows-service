param (
    [string]$AdminUser = ".\Administrator",
    [Parameter(Mandatory=$true)]
    [string]$AdminPass,
    [string]$InfraId = "",
    [string]$AccessKey = "",
    [string]$ServerUrl = "",
    [string]$LogDirectory = "C:\HCE\windows-chaos-infrastructure",
    [int]$TaskPollIntervalSeconds = 5,
    [int]$TaskUpdateIntervalSeconds = 5,
    [int]$UpdateRetries = 5,
    [int]$UpdateRetryIntervalSeconds = 5,
    [int]$ChaosInfraLivenessUpdateIntervalSeconds = 5,
    [int]$ChaosInfraLogFileMaxSizeMb = 5,
    [int]$ChaosInfraLogFileMaxBackups = 2,
    [string]$CustomTlsCertificate = "",
    [string]$HttpProxy = "",
    [string]$HttpClientTimeout = "30s"
)

# Converts plain password to a secure string
function ConvertTo-SecureStringWrapper {
    param(
        [string]$password
    )
    return ConvertTo-SecureString $password -AsPlainText -Force
}

# Checks if the script is running with administrative privileges
function Check-AdminPrivileges {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This script requires administrative privileges."
    }
}

# Creates a directory if it does not exist
function Create-DirectoryIfNotExists {
    param(
        [string]$Path
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -ItemType Directory
    }
}

# Downloads and extracts a specified tool
function Download-AndExtractTool {
    param(
        [hashtable]$tool
    )
    if (-not (Test-Path $tool.Destination)) {
        Write-Host ("Downloading {0}..." -f $tool.Name)
        Invoke-WebRequest -Uri $tool.DownloadUrl -OutFile $tool.Destination -ErrorAction Stop
        Write-Host ("Extracting {0}..." -f $tool.Name)
        Expand-Archive -Path $tool.Destination -DestinationPath $tool.ExtractPath -Force -ErrorAction Stop
        Remove-Item -Path $tool.Destination -Force
        Update-SystemPath $tool.ExecutablePath
    } else {
        Write-Host ("{0} is already downloaded." -f $tool.Name)
    }
}

# Updates the system PATH environment variable
function Update-SystemPath {
    param(
        [string]$NewPath
    )
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine)
    if (-not ($currentPath -like "*$NewPath*")) {
        $newPath = $currentPath + ";" + $NewPath
        [Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::Machine)
    }
}

# Downloads a service binary
function Download-ServiceBinary {
    param(
        [hashtable]$binary
    )
    if (-not (Test-Path $binary.Path)) {
        Write-Host ("Downloading {0} binary..." -f $binary.Name)
        Invoke-WebRequest -Uri $binary.DownloadUrl -OutFile $binary.Path -ErrorAction Stop
    } else {
        Write-Host ("{0} binary is already present." -f $binary.Name)
    }
}

# Creates a configuration file
function Create-ConfigFile {
    param(
        [string]$ConfigPath
    )
    $configContent = @"
infraID: "$InfraId"
accessKey: "$AccessKey"
serverURL: "$ServerUrl"
logDirectory: "$LogDirectory"
taskPollIntervalSeconds: $TaskPollIntervalSeconds
taskUpdateIntervalSeconds: $TaskUpdateIntervalSeconds
updateRetries: $UpdateRetries
updateRetryIntervalSeconds: $UpdateRetryIntervalSeconds
chaosInfraLivenessUpdateIntervalSeconds: $ChaosInfraLivenessUpdateIntervalSeconds
chaosInfraLogFileMaxSizeMB: $ChaosInfraLogFileMaxSizeMb
chaosInfraLogFileMaxBackups: $ChaosInfraLogFileMaxBackups
customTLSCertificate: "$CustomTlsCertificate"
httpProxy: "$HttpProxy"
httpClientTimeout: "$HttpClientTimeout"
"@

    New-Item -Path $ConfigPath -ItemType File -Force | Out-Null
    $configContent | Set-Content -Path $ConfigPath
    Write-Host "Config file created at $ConfigPath"
}

# Function to create a log file
function Create-LogFile {
    param(
        [string]$LogPath
    )
    if (-not (Test-Path $LogPath)) {
        New-Item -Path $LogPath -ItemType File -Force
    }
}

# Creates and starts a Windows service
function Create-Service {
    param(
        [string]$serviceName,
        [string]$servicePath,
        [string]$adminUser,
        [string]$adminPassPlainText
    )
    $scArgs = @("create", $serviceName, "binPath=", $servicePath, "start=", "auto", "obj=", $adminUser, "password=", $adminPassPlainText)
    $process = Start-Process "sc" -ArgumentList $scArgs -NoNewWindow -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        throw "Failed to create service with provided credentials. Exit code: $($process.ExitCode)"
    }

    Start-Service -Name $serviceName -ErrorAction Stop
    Write-Host "Service created and started successfully."
}

$secureAdminPass = ConvertTo-SecureStringWrapper -password $AdminPass

try {

    # Ensuring the script runs with administrative privileges
    Check-AdminPrivileges

    # Base path setup for chaos engineering tools
    $chaosBasePath = "C:\HCE"
    Create-DirectoryIfNotExists -Path $chaosBasePath

    # Define tools to download and extract
    $tools = @(
        @{
            Name = "clumsy";
            DownloadUrl = "https://github.com/jagt/clumsy/releases/download/0.3/clumsy-0.3-win64-a.zip";
            Destination = "$chaosBasePath\clumsy.zip";
            ExecutablePath = "$chaosBasePath\clumsy";
            ExtractPath = "$chaosBasePath\clumsy"
        },
        @{
            Name = "diskspd";
            DownloadUrl = "https://github.com/microsoft/diskspd/releases/download/v2.1/DiskSpd.ZIP";
            Destination = "$chaosBasePath\diskspd.zip";
            ExecutablePath = "$chaosBasePath\diskspd\amd64";
            ExtractPath = "$chaosBasePath\diskspd"
        },
        @{
            Name = "Testlimit";
            DownloadUrl = "https://download.sysinternals.com/files/Testlimit.zip";
            Destination = "$chaosBasePath\testlimit.zip";
            ExecutablePath = "$chaosBasePath\Testlimit";
            ExtractPath = "$chaosBasePath\Testlimit"
        }
    )

    # Define the service binary to download
    $serviceBinary = @{
        Name = "windows-chaos-infrastructure";
        DownloadUrl = "https://github.com/uditgaurav/windows-service/raw/master/setup.10/windows-chaos-infrastructure.exe";
        Path = "$chaosBasePath\windows-chaos-infrastructure.exe"
    }

    # Download and extract each tool
    foreach ($tool in $tools) {
        Download-AndExtractTool -tool $tool
    }

    # Download the service binary
    Download-ServiceBinary -binary $serviceBinary

    # Create the configuration file
    $configPath = "$chaosBasePath\config.yaml"
    Create-ConfigFile -ConfigPath $configPath

    # Create a log file under the specified log directory
    $logFilePath = Join-Path -Path $LogDirectory -ChildPath "windows-chaos-infrastructure.txt"
    Create-LogFile -LogPath $logFilePath

    # Create and start the Windows service
    $serviceName = "WindowsChaosInfrastructure"
    $servicePath = "$chaosBasePath\windows-chaos-infrastructure.exe"
    $adminPassPlainText = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureAdminPass))

    Create-Service -serviceName $serviceName -servicePath $servicePath -adminUser $AdminUser -adminPassPlainText $adminPassPlainText

} catch {
    Write-Error "Error occurred: $_"
    exit
}
