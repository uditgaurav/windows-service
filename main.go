package main

import (
	"bytes"
	"context"
	"embed"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"time"

	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/debug"
	"golang.org/x/sys/windows/svc/eventlog"
)

//go:embed script.ps1
var script embed.FS

// for logging in the service
var elog debug.Log

// myservice defines methods for the service like Execute method
type myservice struct{}

const serviceName = "chaos"

func executePowerShellScript(ctx context.Context, memoryPercentage int, path string, duration int) error {
	elog.Info(1, "PowerShell script execution started.")

	// Read the embedded PowerShell script
	psScript, err := script.ReadFile("script.ps1")
	if err != nil {
		return fmt.Errorf("failed to read embedded script: %w", err)
	}

	// Create a temporary file for the embedded script
	tmpFile, err := ioutil.TempFile("", "script-*.ps1")
	if err != nil {
		return fmt.Errorf("failed to create temporary file: %w", err)
	}
	defer os.Remove(tmpFile.Name())

	// Write the embedded script to the temporary file
	if _, err := tmpFile.Write(psScript); err != nil {
		return fmt.Errorf("failed to write to temporary file: %w", err)
	}
	if err := tmpFile.Close(); err != nil {
		return fmt.Errorf("failed to close temporary file: %w", err)
	}

	// PowerShell command to run your script as admin
	cmdString := fmt.Sprintf("Start-Process PowerShell -Verb RunAs -ArgumentList '-File \"%s\", \"-MemoryInPercentage %d\", \"-PathOfTestlimit %s\", \"-Duration %d\"'", tmpFile.Name(), memoryPercentage, path, duration)

	// Execute the elevation command directly
	cmd := exec.CommandContext(ctx, "powershell", "-Command", cmdString)

	// Capture the standard output
	var stdoutBuf bytes.Buffer
	cmd.Stdout = &stdoutBuf

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("error running script with elevation: %w", err)
	}

	// Read the output from the buffer
	scriptOutput := stdoutBuf.String()
	elog.Info(1, fmt.Sprintf("script output: %s", scriptOutput))

	return nil
}

// Execute is the method called by the Windows service manager
func (m *myservice) Execute(args []string, r <-chan svc.ChangeRequest, changes chan<- svc.Status) (svcSpecificEC bool, exitCode uint32) {
	const cmdsAccepted = svc.AcceptStop | svc.AcceptShutdown
	changes <- svc.Status{State: svc.StartPending}
	changes <- svc.Status{State: svc.Running, Accepts: cmdsAccepted}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go func() {
		for {
			select {
			case c := <-r:
				switch c.Cmd {
				case svc.Interrogate:
					changes <- c.CurrentStatus
				case svc.Stop, svc.Shutdown:
					elog.Info(1, "Service is stopping.")
					cancel()
					return
				default:
					elog.Error(1, fmt.Sprintf("unexpected control request #%d", c))
				}
			case <-time.After(10 * time.Second):
				if err := executePowerShellScript(ctx, 50, "C:\\Testlimit", 60); err != nil {
					elog.Error(1, fmt.Sprintf("error executing script: %v", err))
				}
			}
		}
	}()

	<-ctx.Done()
	changes <- svc.Status{State: svc.StopPending}
	return false, 0
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

	elog, err = eventlog.Open("chaos-engg")
	if err != nil {
		log.Fatalf("failed to open event log: %v", err)
	}
	defer elog.Close()

	elog.Info(1, "checking prerequisites")

	// Validation 1
	if !isTestlimitAvailable() {
		errorMessage := "All the prerequisites are not met: Testlimit is not available on the machine."
		elog.Error(1, errorMessage)
		log.Fatal(errorMessage)
		return
	}

	elog.Info(1, "Service is starting.")
	err = svc.Run("chaos", &myservice{})
	if err != nil {
		elog.Error(1, fmt.Sprintf("Service failed: %v", err))
	}
	elog.Info(1, "Service stopped.")
}

// isTestlimitAvailable checks if Testlimit CLI tool is available on the system
func isTestlimitAvailable() bool {
	cmd := exec.Command("Testlimit")
	if err := cmd.Run(); err != nil {
		return false
	}
	return true
}
