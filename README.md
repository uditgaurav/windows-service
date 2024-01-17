# windows-service


#### Create Binary

```
GOOS=windows GOARCH=amd64 go build

windows-service.exe*
```

#### Launch Service On Windows

- Use Windows Service Control Manager to install the service
- https://learn.microsoft.com/en-us/windows/win32/services/service-control-manager
```
C:\Users\Administrator\Downloads>sc create WindowsChaosAgent binPath= "C:\Users\Administrator\Downloads\windows-chaos-agent.exe"
[SC] CreateService SUCCESS

C:\Users\Administrator\Downloads>sc start WindowsChaosAgent

SERVICE_NAME: WindowsChaosAgent
        TYPE               : 10  WIN32_OWN_PROCESS
        STATE              : 2  START_PENDING
                                (NOT_STOPPABLE, NOT_PAUSABLE, IGNORES_SHUTDOWN)
        WIN32_EXIT_CODE    : 0  (0x0)
        SERVICE_EXIT_CODE  : 0  (0x0)
        CHECKPOINT         : 0x0
        WAIT_HINT          : 0x7d0
        PID                : 1980
        FLAGS              :
```

<img width="1234" alt="Screenshot 2024-01-11 at 8 05 44 PM" src="https://github.com/uditgaurav/windows-service/assets/35391335/d0e01ff7-8528-48a6-b6b0-07269cffa457">

#### Get the status of the service

```
C:\Users\Administrator\Downloads>sc query WindowsChaosAgent

SERVICE_NAME: WindowsChaosAgent
        TYPE               : 10  WIN32_OWN_PROCESS
        STATE              : 4  RUNNING
                                (STOPPABLE, NOT_PAUSABLE, ACCEPTS_SHUTDOWN)
        WIN32_EXIT_CODE    : 0  (0x0)
        SERVICE_EXIT_CODE  : 0  (0x0)
        CHECKPOINT         : 0x0
        WAIT_HINT          : 0x0
```

#### Delete the service

```
C:\Users\Administrator\Downloads>sc delete WindowsChaosAgent
[SC] DeleteService SUCCESS
```

### TBD

- Batch script for installation of the service in Administrator mode.
- Pass flags to the service for input or override the chaos parameters.
- Proper event logging in windows eventviewer.
- Service Management - that is via manual trigger or system trigger.
- Once the agent is running it should be able to run the powershell script in administrator mode.
- Cleanup script.
