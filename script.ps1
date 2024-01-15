param (
    [Parameter(Mandatory=$false)]
    [int]$MemoryInPercentage = 50,

    [Parameter(Mandatory=$false)]
    [int]$Duration = 60,

    [Parameter(Mandatory=$false)]
    [int]$MemoryConsumption,

    [Parameter(Mandatory=$false)]
    [string]$PathOfTestlimit
)

try {
    Set-StrictMode -Version 2.0
    $Date = Get-Date
    $Seconds = $Duration
    $EndTime = $Date.AddSeconds($Seconds)

    Write-Host "Starting Chaos injection... Seconds: $Seconds, MemoryInPercentage: $MemoryInPercentage, PathOfTestlimit: $PathOfTestlimit, MemoryConsumption: $MemoryConsumption"

    if ($MemoryInPercentage -ne 0) {
        $CompObject = Get-WmiObject -Class WIN32_OperatingSystem
        $TotalAvailableMemory = $CompObject.FreePhysicalMemory / 1024
        $MemoryToConsume = $TotalAvailableMemory * ($MemoryInPercentage / 100)
        Write-Host "Memory To Consume $MemoryInPercentage % that is:" $MemoryToConsume
        Start-Process Testlimit64.exe -ArgumentList "-d -c $MemoryToConsume" -WorkingDirectory $PathOfTestlimit
    }
    elseif ($MemoryConsumption -ne $null) {
        Write-Host "Memory To Consume: $MemoryConsumption"
        Start-Process Testlimit64.exe -ArgumentList "-d -c $MemoryConsumption" -WorkingDirectory $PathOfTestlimit
    }

    Write-Host "Chaos started, wait for chaos duration of $Seconds s"

    Do {
        Start-Sleep -Seconds 1
    }
    Until ((Get-Date) -ge $EndTime)

    Get-Process | Where-Object {$_.Name -eq "Testlimit64"} | Stop-Process
    Write-Host "Chaos completed!!!"
}
catch {
    Write-Error $_.Exception
    Exit 1
}