package main

import (
	"embed"
	"fmt"
	"log"
	"time"

	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/debug"
	"golang.org/x/sys/windows/svc/eventlog"
)

// Embed the PowerShell script
//go:embed script.ps1
var script embed.FS

// Global variable for logging in the service
var elog debug.Log

// myservice defines methods for the service like Execute method
type myservice struct{}

// Simplified executePowerShellScript for testing
func executePowerShellScript() error {
	elog.Info(1, "PowerShell script execution started.")
	// Add your script execution logic here
	// For now, just log a message and return nil
	elog.Info(1, "PowerShell script executed successfully.")
	return nil
}

// Execute is the method called by the Windows service manager
func (m *myservice) Execute(args []string, r <-chan svc.ChangeRequest, changes chan<- svc.Status) (svcSpecificEC bool, exitCode uint32) {
	const cmdsAccepted = svc.AcceptStop | svc.AcceptShutdown
	changes <- svc.Status{State: svc.StartPending}
	changes <- svc.Status{State: svc.Running, Accepts: cmdsAccepted}

	go func() {
		for {
			select {
			case c := <-r:
				switch c.Cmd {
				case svc.Interrogate:
					changes <- c.CurrentStatus
				case svc.Stop, svc.Shutdown:
					elog.Info(1, "Service is stopping.")
					return
				default:
					elog.Error(1, fmt.Sprintf("unexpected control request #%d", c))
				}
			default:
				// Simplified script execution for testing
				if err := executePowerShellScript(); err != nil {
					elog.Error(1, fmt.Sprintf("error executing script: %v", err))
				}
				time.Sleep(10 * time.Second) // Adjust as needed
			}
		}
	}()

	changes <- svc.Status{State: svc.StopPending}
	return
}

func main() {
	isIntSess, err := svc.IsAnInteractiveSession()
	if err != nil {
		log.Fatalf("failed to determine if we are running in an interactive session: %v", err)
	}
	if isIntSess {
		log.Println("Running in an interactive session.")
		return
	}

	elog, err = eventlog.Open("chaos")
	if err != nil {
		log.Fatalf("failed to open event log: %v", err)
	}
	defer elog.Close()

	elog.Info(1, "Service is starting.")
	err = svc.Run("chaos", &myservice{})
	if err != nil {
		elog.Error(1, fmt.Sprintf("Service failed: %v", err))
	}
	elog.Info(1, "Service stopped.")
}