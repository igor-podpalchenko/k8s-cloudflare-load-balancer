package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	APIToken              string
	AccountID             string
	ZoneID                string
	PrimaryDomain         string
	LBClass               string
	TunnelReplicas        int32
	CloudflaredImage      string
	VIPAddress            string
	VIPCIDR               string
	VIPInterface          string
	VIPRouterID           string
	VIPAuthPass           string
	AllowClasslessLB      bool
	EnableMutatingWebhook bool
	WebhookPort           int
}

func FromEnv() (*Config, error) {
	replicas := int32(2)
	replicasRaw := strings.TrimSpace(os.Getenv("TUNNEL_REPLICAS"))
	if replicasRaw != "" {
		n, err := strconv.Atoi(replicasRaw)
		if err != nil {
			return nil, fmt.Errorf("invalid TUNNEL_REPLICAS: %w", err)
		}
		if n < 2 {
			return nil, fmt.Errorf("TUNNEL_REPLICAS must be >= 2")
		}
		replicas = int32(n)
	}

	cfg := &Config{
		APIToken:              strings.TrimSpace(os.Getenv("CF_API_TOKEN")),
		AccountID:             strings.TrimSpace(os.Getenv("CF_ACCOUNT_ID")),
		ZoneID:                strings.TrimSpace(os.Getenv("CF_ZONE_ID")),
		PrimaryDomain:         strings.Trim(strings.TrimSpace(os.Getenv("PRIMARY_DOMAIN")), "."),
		LBClass:               strings.TrimSpace(os.Getenv("LB_CLASS")),
		TunnelReplicas:        replicas,
		CloudflaredImage:      strings.TrimSpace(os.Getenv("CLOUDFLARED_IMAGE")),
		VIPAddress:            strings.TrimSpace(os.Getenv("VIP_ADDRESS")),
		VIPCIDR:               strings.TrimSpace(os.Getenv("VIP_CIDR")),
		VIPInterface:          strings.TrimSpace(os.Getenv("VIP_INTERFACE")),
		VIPRouterID:           strings.TrimSpace(os.Getenv("VIP_ROUTER_ID")),
		VIPAuthPass:           strings.TrimSpace(os.Getenv("VIP_AUTH_PASS")),
		AllowClasslessLB:      strings.EqualFold(strings.TrimSpace(os.Getenv("ALLOW_CLASSLESS_LB")), "true"),
		EnableMutatingWebhook: strings.EqualFold(strings.TrimSpace(os.Getenv("ENABLE_MUTATING_WEBHOOK")), "true"),
		WebhookPort:           9443,
	}

	if raw := strings.TrimSpace(os.Getenv("WEBHOOK_PORT")); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil {
			return nil, fmt.Errorf("invalid WEBHOOK_PORT: %w", err)
		}
		if n <= 0 || n > 65535 {
			return nil, fmt.Errorf("WEBHOOK_PORT must be between 1 and 65535")
		}
		cfg.WebhookPort = n
	}

	if cfg.CloudflaredImage == "" {
		cfg.CloudflaredImage = "cloudflare/cloudflared:latest"
	}
	if cfg.VIPInterface == "" {
		cfg.VIPInterface = "eth0"
	}
	if cfg.VIPRouterID == "" {
		cfg.VIPRouterID = "51"
	}
	if cfg.VIPAuthPass == "" {
		cfg.VIPAuthPass = "CHANGE_ME"
	}
	if cfg.VIPAddress != "" && cfg.VIPCIDR == "" {
		cfg.VIPCIDR = cfg.VIPAddress + "/24"
	}

	if cfg.APIToken == "" || cfg.AccountID == "" || cfg.PrimaryDomain == "" || cfg.LBClass == "" {
		return nil, fmt.Errorf("missing required configuration: CF_API_TOKEN, CF_ACCOUNT_ID, PRIMARY_DOMAIN, LB_CLASS")
	}

	return cfg, nil
}
