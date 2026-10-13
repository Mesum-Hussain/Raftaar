// Command server serves the shop's static files and a health check.
package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"os/signal"
	"time"
)

type health struct {
	Status string        `json:"status"`
	Uptime time.Duration `json:"uptime_ns"`
}

func main() {
	started := time.Now()
	mux := http.NewServeMux()
	mux.Handle("/", http.FileServer(http.Dir("web/dist")))
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(health{"ok", time.Since(started)})
	})

	srv := &http.Server{Addr: ":8080", Handler: mux, ReadTimeout: 5 * time.Second}
	go func() {
		if err := srv.ListenAndServe(); err != http.ErrServerClosed {
			log.Fatalf("listen: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, os.Interrupt)
	<-stop
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
}
