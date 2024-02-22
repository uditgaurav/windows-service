param(
    [string]$chaosBasePath = "C:\\HCE",
    [int]$waitTime = 180,
    [int]$delay = 2,
    [string]$ChaosServiceName = "WindowsChaosInfrastructure",

)

function Stop-ServiceWithTimeout {
    param(
        [string]$serviceName,
        [int]$timeoutSeconds,
        [int]$delaySeconds
    )

    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service -eq $null) {
        Write-Host "Service '$serviceName' not found."
        return $false
    }

    if ($service.Status -eq 'Stopped') {
        Write-Host "Service '$serviceName' is already stopped."
        return $true
    }

    Write-Host "Stopping service '$serviceName'..."
    Stop-Service -Name $serviceName -Force

    $elapsed = 0
    while ($service.Status -ne 'Stopped' -and $elapsed -lt $timeoutSeconds) {
        Start-Sleep -Seconds $delaySeconds
        $elapsed += $delaySeconds
        $service.Refresh()
        Write-Host "Service '$serviceName' is $($service.Status)..."
    }

    if ($service.Status -eq 'Stopped') {
        Write-Host "Service '$serviceName' stopped successfully."
        return $true
    } else {
        Write-Host "Service '$serviceName' failed to stop within the timeout period."
        return $false
    }
}

function Remove-ChaosDirectory {
    param(
        [string]$path
    )

    if (Test-Path -Path $path) {
        Write-Host "Removing chaos directory '$path'..."
        Remove-Item -Path $path -Recurse -Force
        Write-Host "Chaos directory removed."
    } else {
        Write-Host "Chaos directory '$path' not found."
    }
}

$serviceName = $ChaosServiceName

# Stop the service with a timeout
if (Stop-ServiceWithTimeout -serviceName $serviceName -timeoutSeconds $waitTime -delaySeconds $delay) {
    # Remove the chaos directory
    Remove-ChaosDirectory -path $chaosBasePath
} else {
    Write-Host "Failed to stop service '$serviceName' within the specified timeout. Manual intervention may be required."
}
