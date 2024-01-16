@echo off
SETLOCAL EnableDelayedExpansion

net session >nul 2>&1
if %errorLevel% == 0 (
    echo Administrative privileges confirmed.
) else (
    echo This script requires administrative privileges.
    pause
    exit
)

:: Set Administrator username and password
set AdminUser=.\Administrator
echo Using default Administrator username: %AdminUser%
set /p AdminPass=Enter Administrator password: 

sc create MyService binPath= "C:\Users\Administrator\Downloads\windows-service.exe" obj= "%AdminUser%" password= "%AdminPass%"

if %errorLevel% == 0 (
    echo Service created successfully.
) else (
    echo Failed to create service. Error code: %errorLevel%
    pause
    exit
)

sc start MyService

if %errorLevel% == 0 (
    echo Service started successfully.
) else (
    echo Failed to start service. Error code: %errorLevel%
    pause
    exit
)

echo Press any key to close this window...
pause >nul
