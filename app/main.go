// Command transcoder is a small stand-in for a video transcoding worker.
//
// It exists to show where each kind of configuration comes from at runtime:
// tuning from a ConfigMap, infrastructure values from Parameter Store and a
// database password from Secrets Manager, the last two synced into a Kubernetes
// Secret by the External Secrets Operator. AWS credentials come from the SDK's
// default chain, which is how EKS Pod Identity and IRSA reach the process.
package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
)

// Config is everything the worker needs, grouped by where it comes from.
type Config struct {
	// From the ConfigMap: app tuning the team owns and reviews in Git.
	LogLevel     string
	Workers      int
	FFmpegPreset string

	// From Parameter Store via ESO: values Terraform produced.
	QueueURL     string
	OutputBucket string

	// From Secrets Manager via ESO.
	DBPassword string

	// SecretsDir is where the same Secret is also mounted as files. Files are
	// refreshed by the kubelet; environment variables are fixed at start.
	SecretsDir string
}

func loadConfig(getenv func(string) string) (Config, error) {
	cfg := Config{
		LogLevel:     valueOr(getenv("LOG_LEVEL"), "info"),
		FFmpegPreset: valueOr(getenv("FFMPEG_PRESET"), "medium"),
		QueueURL:     getenv("QUEUE_URL"),
		OutputBucket: getenv("OUTPUT_BUCKET"),
		DBPassword:   getenv("DB_PASSWORD"),
		SecretsDir:   valueOr(getenv("SECRETS_DIR"), "/etc/transcoder/secrets"),
	}
	workers, err := strconv.Atoi(valueOr(getenv("WORKERS"), "1"))
	if err != nil || workers < 1 {
		return Config{}, fmt.Errorf("WORKERS must be a positive integer, got %q", getenv("WORKERS"))
	}
	cfg.Workers = workers

	var missing []string
	for name, value := range map[string]string{
		"QUEUE_URL":     cfg.QueueURL,
		"OUTPUT_BUCKET": cfg.OutputBucket,
		"DB_PASSWORD":   cfg.DBPassword,
	} {
		if value == "" {
			missing = append(missing, name)
		}
	}
	if len(missing) > 0 {
		return Config{}, fmt.Errorf("missing required settings: %s", strings.Join(missing, ", "))
	}
	return cfg, nil
}

func valueOr(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}

// fingerprint identifies a secret in logs without revealing it.
func fingerprint(secret string) string {
	sum := sha256.Sum256([]byte(secret))
	return hex.EncodeToString(sum[:4])
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if err := run(ctx); err != nil && !errors.Is(err, context.Canceled) {
		slog.Error("transcoder stopped", "err", err)
		os.Exit(1)
	}
}

func run(ctx context.Context) error {
	cfg, err := loadConfig(os.Getenv)
	if err != nil {
		return err
	}
	level := slog.LevelInfo
	if cfg.LogLevel == "debug" {
		level = slog.LevelDebug
	}
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{Level: level})))

	// No keys, no profile: the default chain finds Pod Identity, IRSA, or
	// whatever else the environment provides.
	awsCfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return fmt.Errorf("load AWS config: %w", err)
	}
	creds, err := awsCfg.Credentials.Retrieve(ctx)
	if err != nil {
		return fmt.Errorf("resolve AWS credentials: %w", err)
	}

	slog.Info("transcoder starting",
		"workers", cfg.Workers,
		"preset", cfg.FFmpegPreset,
		"queue", cfg.QueueURL,
		"bucket", cfg.OutputBucket,
		"db_password", fingerprint(cfg.DBPassword),
		"aws_region", awsCfg.Region,
		"aws_credentials", creds.Source,
	)

	queue := sqs.NewFromConfig(awsCfg)
	ticker := time.NewTicker(10 * time.Second)
	defer ticker.Stop()
	for {
		checkSecretFile(cfg)
		if err := pollOnce(ctx, queue, cfg); err != nil {
			slog.Warn("poll failed", "err", err)
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
	}
}

// checkSecretFile compares the password the process started with against the
// mounted file, which the kubelet keeps up to date.
func checkSecretFile(cfg Config) {
	data, err := os.ReadFile(cfg.SecretsDir + "/DB_PASSWORD")
	if err != nil {
		slog.Debug("no mounted secret file", "err", err)
		return
	}
	env, file := fingerprint(cfg.DBPassword), fingerprint(string(data))
	if env != file {
		slog.Warn("db password changed on disk; this process still uses the old one",
			"env", env, "file", file)
		return
	}
	slog.Info("db password unchanged", "env", env, "file", file)
}

func pollOnce(ctx context.Context, queue *sqs.Client, cfg Config) error {
	out, err := queue.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
		QueueUrl:            aws.String(cfg.QueueURL),
		MaxNumberOfMessages: int32(min(cfg.Workers, 10)),
		WaitTimeSeconds:     5,
	})
	if err != nil {
		return err
	}
	for _, msg := range out.Messages {
		slog.Info("transcoding", "job", aws.ToString(msg.Body), "preset", cfg.FFmpegPreset,
			"destination", "s3://"+cfg.OutputBucket)
		if _, err := queue.DeleteMessage(ctx, &sqs.DeleteMessageInput{
			QueueUrl:      aws.String(cfg.QueueURL),
			ReceiptHandle: msg.ReceiptHandle,
		}); err != nil {
			return err
		}
	}
	return nil
}
