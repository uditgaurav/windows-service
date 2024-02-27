param(
    [string]$chaosBasePath = "C:\\HCE",
    [int]$waitTime = 180,
    [int]$delay = 2,
    [string]$ChaosServiceName = "WindowsChaosInfrastructure",
    [string]$LogDirectory = "C:\\HCE\Logs"
)

# Function to stop a service with a specified timeout
function Stop-ServiceWithTimeout {
    param(
        [string]$serviceName,
        [int]$timeoutSeconds,
        [int]$delaySeconds
    )

    # Attempt to get the service object
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service -eq $null) {
        Write-Host "Service '$serviceName' not found."
        return $false
    }

    # Check if the service is already stopped
    if ($service.Status -eq 'Stopped') {
        Write-Host "Service '$serviceName' is already stopped."
        return $true
    }

    # Attempt to stop the service
    Write-Host "Stopping service '$serviceName'..."
    Stop-Service -Name $serviceName -Force

    # Wait for the service to stop with a timeout
    $elapsed = 0
    while ($service.Status -ne 'Stopped' -and $elapsed -lt $timeoutSeconds) {
        Start-Sleep -Seconds $delaySeconds
        $elapsed += $delaySeconds
        $service.Refresh()
        Write-Host "Service '$serviceName' is $($service.Status)..."
    }

    # Check if the service stopped successfully
    if ($service.Status -eq 'Stopped') {
        Write-Host "Service '$serviceName' stopped successfully."
        return $true
    } else {
        Write-Host "Service '$serviceName' failed to stop within the timeout period."
        return $false
    }
}

# Function to remove a directory if it exists
function Remove-Directory {
    param(
        [string]$path
    )

    if ($path -and (Test-Path -Path $path)) {
        Write-Host "Removing directory '$path'..."
        Remove-Item -Path $path -Recurse -Force
        Write-Host "Directory '$path' removed."
    } elseif ($path) {
        Write-Host "Directory '$path' not found."
    }
}

# Function to remove a service if it exists
function Remove-Service {
    param(
        [string]$serviceName
    )

    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service -ne $null) {
        Write-Host "Deleting service '$serviceName'..."
        sc.exe delete $serviceName
        Write-Host "Service '$serviceName' deleted."
    } else {
        Write-Host "Service '$serviceName' not found or already deleted."
    }
}

$serviceName = $ChaosServiceName

# Stop the service with a timeout
if (Stop-ServiceWithTimeout -serviceName $serviceName -timeoutSeconds $waitTime -delaySeconds $delay) {
    # Remove the chaos directory
    Remove-Directory -path $chaosBasePath
    # Remove the log directory if it's different from the chaos directory
    if ($LogDirectory -and $LogDirectory -ne $chaosBasePath) {
        Remove-Directory -path $LogDirectory
    }
    # Remove the service
    Remove-Service -serviceName $serviceName
} else {
    Write-Host "Failed to stop service '$serviceName' within the specified timeout. Manual intervention may be required."
}
