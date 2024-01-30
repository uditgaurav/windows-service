param (
    [string]$ServiceName = "WindowsChaosInfrastructure",
    [int]$TimeoutSeconds = 180,
    [string]$ChaosBaseDirectory = "C:\HCE",
    [int]$CheckIntervalSeconds = 10
)

# Function to check if a service is stopped
function Is-ServiceStopped {
    param (
        [string]$serviceName
    )
    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    return ($service -eq $null) -or ($service.Status -eq 'Stopped')
}

try {
    Write-Host "Stopping service '$ServiceName'..."
    Stop-Service -Name $ServiceName -Force -ErrorAction Stop

    $timeRemaining = $TimeoutSeconds
    while ($timeRemaining -gt 0) {
        Start-Sleep -Seconds $CheckIntervalSeconds
        $timeRemaining -= $CheckIntervalSeconds

        if (Is-ServiceStopped -serviceName $ServiceName) {
            Write-Host "Service '$ServiceName' stopped successfully."
            break
        } else {
            Write-Host "Waiting for service '$ServiceName' to get to the stopped state ($timeRemaining seconds remaining)..."
        }
    }

    if (-not (Is-ServiceStopped -serviceName $ServiceName)) {
        Write-Host "Service '$ServiceName' did not stop within the timeout period."
    } else {
        Write-Host "Service '$ServiceName' is removed. Proceeding."
        Write-Host "Removing directory '$ChaosBaseDirectory'..."
        Remove-Item -Path $ChaosBaseDirectory -Recurse -Force
        Write-Host "Directory '$ChaosBaseDirectory' removed successfully."
    }
} catch {
    Write-Error "Error occurred: $_"
    exit
}
