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

//go:embed scripts/*
var scripts embed.FS

var elog debug.Log

type myservice struct{}

const serviceName = "chaos"

type ScriptParams struct {
	MemoryPercentage int
	CPUPercentage    int
	CPU              int
	Path             string
	Duration         int
}

func executePowerShellScript(ctx context.Context, scriptName string, params ScriptParams) error {
	logs("PowerShell", "script execution started", false, 1)

	psScript, err := scripts.ReadFile("scripts/" + scriptName)
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

	var cmd *exec.Cmd
	var cmdArgs []string

	switch scriptName {
	case "memory-stress.ps1":

		cmdArgs = []string{
			tmpFile.Name(),
			"-MemoryInPercentage", fmt.Sprint(params.MemoryPercentage),
			"-PathOfTestlimit", params.Path,
			"-Duration", fmt.Sprint(params.Duration),
		}

	case "cpu-stress.ps1":

		cmdArgs = []string{
			tmpFile.Name(),
			"-CPUPercentage", fmt.Sprint(params.CPUPercentage),
			"-CPU", fmt.Sprint(params.CPU),
			"-Duration", fmt.Sprint(params.Duration),
		}

	default:
		return fmt.Errorf("unknown script name: %s", scriptName)
	}
	cmd = exec.CommandContext(ctx, "powershell", cmdArgs...)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("error running script: %w; output: %s", err, string(output))
	}
	logs("PowerShell", fmt.Sprintf("script output: %s", output), false, 1)

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
					logs("Service", "Service is stopping", false, 1)
					cancel()
					return
				default:
					logs("Service", fmt.Sprintf("unexpected control request #%d", c), true, 1)
				}
			case <-time.After(10 * time.Second):
				params := ScriptParams{MemoryPercentage: 50, Path: "C:\\HCE\\Testlimit", Duration: 60}
				if err := executePowerShellScript(ctx, "memory-stress.ps1", params); err != nil {
					logs("PowerShell", fmt.Sprintf("error executing script: %v", err), true, 1)
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

	elog, err = eventlog.Open("windows-chaos-agent")
	if err != nil {
		log.Fatalf("failed to open event log: %v", err)
	}
	defer elog.Close()

	// Validation 1
	if !isTestlimitAvailable() {
		errorMessage := "All the prerequisites are not met: Testlimit is not available on the machine."
		logs("PreHookValidation", errorMessage, true, 1)
		log.Fatal(errorMessage)
		return
	}

	logs("Service", "Service is starting", false, 1)
	err = svc.Run("chaos", &myservice{})
	if err != nil {
		logs("Service", fmt.Sprintf("Service failed: %v", err), true, 1)
	}
	logs("Service", "Service stopped", false, 1)
}

// isTestlimitAvailable checks if Testlimit CLI tool is available on the system
func isTestlimitAvailable() bool {
	cmd := exec.Command("Testlimit")
	if err := cmd.Run(); err != nil {
		return false
	}
	return true
}

func logs(source, message string, isError bool, eventID uint32) {
	fullMessage := fmt.Sprintf("[%s] %s", source, message)
	if isError {
		elog.Error(eventID, fullMessage)
	} else {
		elog.Info(eventID, fullMessage)
	}
}