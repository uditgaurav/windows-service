package main

import (
	"fmt"
	"log"
	"time"

	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/debug"
	"golang.org/x/sys/windows/svc/eventlog"
)

var elog debug.Log

type myservice struct{}

func (m *myservice) Execute(args []string, r <-chan svc.ChangeRequest, changes chan<- svc.Status) (svcSpecificEC bool, exitCode uint32) {
    const cmdsAccepted = svc.AcceptStop | svc.AcceptShutdown
    changes <- svc.Status{State: svc.StartPending}
    fasttick := time.Tick(500 * time.Millisecond)
    slowtick := time.Tick(2 * time.Second)
    tick := fasttick
    changes <- svc.Status{State: svc.Running, Accepts: cmdsAccepted}
loop:
    for {
        select {
        case <-tick:
            log.Print("tick")
        case c := <-r:
            switch c.Cmd {
            case svc.Interrogate:
                changes <- c.CurrentStatus
            case svc.Stop, svc.Shutdown:
                break loop
            case svc.Pause:
                // Switch to slow tick on pause
                tick = slowtick
                changes <- svc.Status{State: svc.Paused, Accepts: cmdsAccepted}
            case svc.Continue:
                // Switch back to fast tick on continue
                tick = fasttick
                changes <- svc.Status{State: svc.Running, Accepts: cmdsAccepted}
            default:
                log.Printf("unexpected control request #%d", c)
            }
        }
    }

    changes <- svc.Status{State: svc.StopPending}
    return
}

func main() {
    isIntSess, err := svc.IsAnInteractiveSession()
    if err != nil {
        log.Fatalf("failed to determine if we are running in an interactive session: %v", err)
    }
    if isIntSess {
        log.Printf("Hello World")
        return
    }

    elog, err = eventlog.Open("myprogram")
    if err != nil {
        return
    }
    defer elog.Close()

    elog.Info(1, "starting")
    run := svc.Run
    err = run("myprogram", &myservice{})
    if err != nil {
        elog.Error(1, fmt.Sprintf("service failed: %v", err))
        return
    }
    elog.Info(1, "stopped")
}