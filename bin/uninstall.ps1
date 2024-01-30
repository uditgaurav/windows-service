param (
    [string]$ServiceName = "WindowsChaosInfrastructure",
    [int]$TimeoutSeconds = 180,
    [string]$ChaosBaseDirectory = "C:\HCE",
    [int]$CheckIntervalSeconds = 10
)

# Function to stop and remove a Windows service
function Stop-AndRemove-Service {
    param(
        [string]$serviceName
    )
    Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
    sc.exe delete $serviceName
    Write-Host "Service '$serviceName' stopped and removed successfully."
}

# Function to check if the service is removed
function Is-ServiceRemoved {
    param(
        [string]$serviceName
    )
    return -not (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)
}

try {
    # Stop and remove the service
    Stop-AndRemove-Service -serviceName $ServiceName

    # Wait for the specified timeout
    $remainingTime = $TimeoutSeconds
    while ($remainingTime -gt 0) {
        Write-Host "Waiting for service '$ServiceName' to get to the stopped state ($remainingTime seconds remaining)..."
        Start-Sleep -Seconds $CheckIntervalSeconds
        $remainingTime -= $CheckIntervalSeconds

        # Check if the service is removed
        if (Is-ServiceRemoved -serviceName $ServiceName) {
            Write-Host "Service '$ServiceName' is removed. Proceeding."
            break
        }
    }

    # Remove the service directory
    if (Test-Path $ChaosBaseDirectory) {
        Remove-Item -Path $ChaosBaseDirectory -Recurse -Force
        Write-Host "Directory '$ChaosBaseDirectory' removed successfully."
    } else {
        Write-Host "Directory '$ChaosBaseDirectory' does not exist."
    }

} catch {
    Write-Error "Error occurred: $_"
    exit 1
}
