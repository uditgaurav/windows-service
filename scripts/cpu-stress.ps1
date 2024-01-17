param(
    [Int32]$CPUPercentage = 0,
    [Int32]$CPU = 1,
    [Int32]$Duration = 60
)

try {
    Set-StrictMode -Version 2.0

    if ($CPUPercentage -ne 0) {
        Write-Host "The value is not equal to zero"
        # Get the number of logical processors (cores) on the machine
        $cores = (Get-WmiObject Win32_Processor).NumberOfLogicalProcessors

        # Calculate the number of cores needed to achieve the desired CPU utilization percentage
        $CPU = [Math]::Round($cores * $CPUPercentage / 100)
        if ($CPU -eq 0) {
            $CPU = 1
        }
        Write-Host "The number of CPU cores to be consumed is: $CPU"
    }

    if ($CPU -eq 0) {
        Write-Host "The value is equal to zero"
        $NumberOfLogicalProcessors = Get-WmiObject win32_processor | Select-Object -ExpandProperty NumberOfLogicalProcessors
        ForEach ($core in 1..$NumberOfLogicalProcessors){
            Start-Job -Name "ChaosCpu$core" -ScriptBlock {
                $result = 1
                ForEach ($loopnumber in 1..2147483647){
                    $result = 1
                    ForEach ($loopnumber1 in 1..2147483647){
                        $result = 1
                        ForEach($number in 1..2147483647){
                            $result = $result * $number
                        }
                    }
                }
            } | Out-Null
            Write-Host "Started Job ChaosCpu$core"
        }
    } else {
        ForEach ($core in 1..$CPU){
            Start-Job -Name "ChaosCpu$core" -ScriptBlock {
                $result = 1
                ForEach ($loopnumber in 1..2147483647){
                    $result = 1
                    ForEach ($loopnumber1 in 1..2147483647){
                        $result = 1
                        ForEach($number in 1..2147483647){
                            $result = $result * $number
                        }
                    }
                }
            } | Out-Null
            Write-Host "Started Job ChaosCpu$core"
        }
    }

    Write-Host "About to sleep for $Duration seconds"
    $totalduration = $Duration
    Start-Sleep -Seconds ($totalduration/2)
    Get-WmiObject Win32_Processor | Select-Object LoadPercentage | Format-List
    Start-Sleep -Seconds ($totalduration/2)
    Get-WmiObject Win32_Processor | Select-Object LoadPercentage | Format-List

    Write-Host "About to stop jobs"
    $cpuJobs = Get-Job -Name "ChaosCpu*"
    ForEach ($job in $cpuJobs) {
        Stop-Job -Name $job.Name | Out-Null
        Write-Host "Stopped $($job.Name)"
        Remove-Job -Name $job.Name | Out-Null
        Write-Host "Removed $($job.Name)"
    }
} catch {
    Write-Error $_.Exception
    Exit 1
}