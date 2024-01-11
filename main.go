package main

import (
	"embed"
	"fmt"
	"io/ioutil"
	"os"
	"os/exec"
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

// executePowerShellScript runs the PowerShell script with given parameters
func executePowerShellScript(cpuPercentage, cpu, duration int) error {
	// Read the embedded script
	psScript, err := script.ReadFile("script.ps1")
	if err != nil {
		return fmt.Errorf("failed to read embedded script: %w", err)
	}

	// Create a temporary file to store the script
	tmpFile, err := ioutil.TempFile("", "script-*.ps1")
	if err != nil {
		return fmt.Errorf("failed to create temporary file: %w", err)
	}
	defer os.Remove(tmpFile.Name())

	// Write the script to the temporary file
	if _, err := tmpFile.Write(psScript); err != nil {
		return fmt.Errorf("failed to write to temporary file: %w", err)
	}
	if err := tmpFile.Close(); err != nil {
		return fmt.Errorf("failed to close temporary file: %w", err)
	}

	// Construct the command with parameters
	cmd := exec.Command("powershell", tmpFile.Name(),
		"-CPUPercentage", fmt.Sprint(cpuPercentage),
		"-CPU", fmt.Sprint(cpu),
		"-Duration", fmt.Sprint(duration))

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("error running script: %w", err)
	}
	elog.Info(1, fmt.Sprintf("script output: %s", output))

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
					return
				default:
					// Execute PowerShell script with example parameters
					cpuPercentage := 50
					cpu := 2
					duration := 60

					if err := executePowerShellScript(cpuPercentage, cpu, duration); err != nil {
						elog.Error(1, fmt.Sprintf("error executing script: %v", err))
					}
					time.Sleep(30 * time.Second)
				}
			}
		}
	}()

	changes <- svc.Status{State: svc.StopPending}
	return
}

func main() {
	isIntSess, err := svc.IsAnInteractiveSession()
	if err != nil {
		elog.Error(1, fmt.Sprintf("failed to determine if we are running in an interactive session: %v", err))
		return
	}
	if isIntSess {
		return
	}

	elog, err = eventlog.Open("myprogram")
	if err != nil {
		return
	}
	defer elog.Close()

	err = svc.Run("myprogram", &myservice{})
	if err != nil {
		elog.Error(1, fmt.Sprintf("service failed: %v", err))
	}
}