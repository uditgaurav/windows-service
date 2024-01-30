package main

import (
	"bufio"
	"context"
	"embed"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"strings"
	"sync"
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

// Global variables
var logChannel chan string
var wg sync.WaitGroup

func init() {
	logChannel = make(chan string, 100)
	wg = sync.WaitGroup{}
}

func executePowerShellScript(ctx context.Context, scriptName string, params ScriptParams) error {
    logs("PowerShell", "script execution started", false, 1)

    // Read and prepare the PowerShell script
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

    // Determine the script to execute and its parameters
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

    // Prepare the PowerShell command with context
    cmd = exec.CommandContext(ctx, "powershell", cmdArgs...)

    // Setting up a scanner to read the script output in real-time
    cmdReader, err := cmd.StdoutPipe()
    if err != nil {
        return fmt.Errorf("error creating StdoutPipe for Cmd: %w", err)
    }

    scanner := bufio.NewScanner(cmdReader)
    go func() {
        for scanner.Scan() {
            logChannel <- fmt.Sprintf("[PowerShell] %s", scanner.Text())
        }
    }()

    // Start the PowerShell script
    err = cmd.Start()
    if err != nil {
        logChannel <- fmt.Sprintf("[PowerShell] error starting script: %s", err.Error())
        return fmt.Errorf("error starting script: %w", err)
    }

    // Wait for the command to finish in a separate goroutine
    errChan := make(chan error, 1)
    go func() {
        errChan <- cmd.Wait()
    }()

    select {
    case <-ctx.Done():
        // Context is cancelled, kill the process
        if killErr := cmd.Process.Kill(); killErr != nil {
            logChannel <- fmt.Sprintf("[PowerShell] error killing script: %s", killErr.Error())
        }
        <-errChan // Wait for cmd.Wait to return
        return ctx.Err()
    case err := <-errChan:
        // Command completed
        if err != nil {
            logChannel <- fmt.Sprintf("[PowerShell] error running script: %s", err.Error())
            return fmt.Errorf("error running script: %w", err)
        }
    }

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

	wg.Add(1)
	go fileLogger("C:\\HCE\\windows-chaos-infrastructure.txt")

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

func fileLogger(filePath string) {
	defer wg.Done()

	file, err := os.OpenFile(filePath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		log.Fatalf("Failed to open log file: %v", err)
	}
	defer file.Close()

	for logEntry := range logChannel {
		if _, err := file.WriteString(logEntry + "\n"); err != nil {
			log.Printf("Failed to write to log file: %v", err)
		}
	}
}

func logs(source, message string, isError bool, eventID uint32) {
	fullMessage := fmt.Sprintf("[%s] %s", source, message)

	// Send log to event log
	if isError {
		elog.Error(eventID, fullMessage)
	} else {
		elog.Info(eventID, fullMessage)
	}

	// Send log to file log channel
	logChannel <- strings.ReplaceAll(fullMessage, "\n", " ")
}