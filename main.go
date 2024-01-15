package main

import (
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

// executePowerShellScript runs the PowerShell script with given parameters
func executePowerShellScript(ctx context.Context, cpuPercentage int, path string, duration int) error {
	elog.Info(1, "PowerShell script execution started.")

	psScript, err := script.ReadFile("script.ps1")
	if err != nil {
		return fmt.Errorf("failed to read embedded script: %w", err)
	}

	tmpFile, err := ioutil.TempFile("", "script-*.ps1")
	if err != nil {
		return fmt.Errorf("failed to create temporary file: %w", err)
	}
	defer os.Remove(tmpFile.Name())

	if _, err := tmpFile.Write(psScript); err != nil {
		return fmt.Errorf("failed to write to temporary file: %w", err)
	}
	if err := tmpFile.Close(); err != nil {
		return fmt.Errorf("failed to close temporary file: %w", err)
	}

	cmd := exec.CommandContext(ctx, "powershell", tmpFile.Name(),
		"-MemoryInPercentage", fmt.Sprint(cpuPercentage),
		"-PathOfTestlimit", fmt.Sprint(path),
		"-Duration", fmt.Sprint(duration))

	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("error running script: %w; output: %s", err, string(output))
	}
	elog.Info(1, fmt.Sprintf("script output: %s", output))

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
	cmd := exec.Command("Testlimit", "-?")
	if err := cmd.Run(); err != nil {
		return false
	}
	return true
}