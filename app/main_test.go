package main

import (
	"strings"
	"testing"
)

func env(values map[string]string) func(string) string {
	return func(key string) string { return values[key] }
}

func TestLoadConfig(t *testing.T) {
	cfg, err := loadConfig(env(map[string]string{
		"WORKERS":       "4",
		"QUEUE_URL":     "https://sqs.eu-west-1.amazonaws.com/123456789012/transcode-jobs",
		"OUTPUT_BUCKET": "video-pipeline-prod-output",
		"DB_PASSWORD":   "s3cret",
	}))
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Workers != 4 || cfg.LogLevel != "info" || cfg.FFmpegPreset != "medium" {
		t.Fatalf("unexpected config: %+v", cfg)
	}
}

func TestLoadConfigReportsEveryMissingSetting(t *testing.T) {
	_, err := loadConfig(env(map[string]string{}))
	if err == nil {
		t.Fatal("expected an error")
	}
	for _, name := range []string{"QUEUE_URL", "OUTPUT_BUCKET", "DB_PASSWORD"} {
		if !strings.Contains(err.Error(), name) {
			t.Errorf("error %q does not mention %s", err, name)
		}
	}
}

func TestLoadConfigRejectsBadWorkers(t *testing.T) {
	if _, err := loadConfig(env(map[string]string{"WORKERS": "zero"})); err == nil {
		t.Fatal("expected an error for WORKERS=zero")
	}
}

func TestFingerprintHidesTheSecret(t *testing.T) {
	fp := fingerprint("hunter2")
	if len(fp) != 8 || strings.Contains(fp, "hunter2") {
		t.Fatalf("fingerprint %q leaks or has the wrong length", fp)
	}
	if fp != fingerprint("hunter2") {
		t.Fatal("fingerprint is not stable")
	}
}
