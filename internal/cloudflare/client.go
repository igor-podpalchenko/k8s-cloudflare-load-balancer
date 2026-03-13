package cloudflare

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"path"
	"strings"
	"time"

	"github.com/mgduke/k8s-cloudflare-load-balancer-private/internal/config"
)

const baseURL = "https://api.cloudflare.com/client/v4"

type Client struct {
	httpClient *http.Client
	cfg        *config.Config
}

type Zone struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type apiEnvelope[T any] struct {
	Success bool       `json:"success"`
	Errors  []apiError `json:"errors"`
	Result  T          `json:"result"`
}

type apiError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

type Tunnel struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Token string `json:"token,omitempty"`
}

type DNSRecord struct {
	ID      string `json:"id"`
	Type    string `json:"type"`
	Name    string `json:"name"`
	Content string `json:"content"`
	Proxied bool   `json:"proxied"`
}

type tunnelConfigRequest struct {
	Config tunnelConfig `json:"config"`
}

type tunnelConfig struct {
	Ingress     []tunnelIngressRule `json:"ingress"`
	WARPRouting warpRoutingConfig   `json:"warp-routing"`
}

type tunnelIngressRule struct {
	Hostname      string                    `json:"hostname,omitempty"`
	Service       string                    `json:"service"`
	OriginRequest *tunnelOriginRequestRules `json:"originRequest,omitempty"`
}

type tunnelOriginRequestRules struct {
	HTTPHostHeader string `json:"httpHostHeader,omitempty"`
}

type warpRoutingConfig struct {
	Enabled bool `json:"enabled"`
}

func NewClient(cfg *config.Config) *Client {
	return &Client{
		httpClient: &http.Client{Timeout: 20 * time.Second},
		cfg:        cfg,
	}
}

func (c *Client) EnsureTunnelIngressRoute(ctx context.Context, tunnelID, hostname, serviceURL string) error {
	return c.EnsureTunnelIngressRoutes(ctx, tunnelID, []TunnelRoute{
		{Hostname: hostname, ServiceURL: serviceURL},
	})
}

type TunnelRoute struct {
	Hostname   string
	ServiceURL string
}

func (c *Client) EnsureTunnelIngressRoutes(ctx context.Context, tunnelID string, routes []TunnelRoute) error {
	ingressRules := make([]tunnelIngressRule, 0, len(routes)+1)
	for _, route := range routes {
		host := strings.TrimSpace(route.Hostname)
		serviceURL := strings.TrimSpace(route.ServiceURL)
		if host == "" || serviceURL == "" {
			continue
		}
		ingressRules = append(ingressRules, tunnelIngressRule{
			Hostname: host,
			Service:  serviceURL,
			OriginRequest: &tunnelOriginRequestRules{
				HTTPHostHeader: host,
			},
		})
	}
	ingressRules = append(ingressRules, tunnelIngressRule{Service: "http_status:404"})

	payload := tunnelConfigRequest{
		Config: tunnelConfig{
			Ingress:     ingressRules,
			WARPRouting: warpRoutingConfig{Enabled: false},
		},
	}

	var result any
	return c.doJSON(ctx, http.MethodPut,
		fmt.Sprintf("/accounts/%s/cfd_tunnel/%s/configurations", c.cfg.AccountID, tunnelID),
		nil,
		payload,
		&result,
	)
}

func (c *Client) CreateTunnel(ctx context.Context, name string) (*Tunnel, error) {
	secret := make([]byte, 32)
	if _, err := rand.Read(secret); err != nil {
		return nil, fmt.Errorf("generate tunnel secret: %w", err)
	}

	body := map[string]any{
		"name":       name,
		"config_src": "cloudflare",
		"secret":     base64.StdEncoding.EncodeToString(secret),
	}

	var result Tunnel
	if err := c.doJSON(ctx, http.MethodPost,
		fmt.Sprintf("/accounts/%s/cfd_tunnel", c.cfg.AccountID),
		nil,
		body,
		&result,
	); err != nil {
		return nil, err
	}

	if result.Token == "" {
		token, err := c.GetTunnelToken(ctx, result.ID)
		if err != nil {
			return nil, err
		}
		result.Token = token
	}

	return &result, nil
}

func (c *Client) GetTunnelToken(ctx context.Context, tunnelID string) (string, error) {
	var raw json.RawMessage
	if err := c.doJSON(ctx, http.MethodGet,
		fmt.Sprintf("/accounts/%s/cfd_tunnel/%s/token", c.cfg.AccountID, tunnelID),
		nil,
		nil,
		&raw,
	); err != nil {
		return "", err
	}

	var token string
	if err := json.Unmarshal(raw, &token); err == nil && token != "" {
		return token, nil
	}

	var wrapped struct {
		Token string `json:"token"`
	}
	if err := json.Unmarshal(raw, &wrapped); err == nil && wrapped.Token != "" {
		return wrapped.Token, nil
	}

	return "", fmt.Errorf("empty tunnel token response")
}

func (c *Client) DeleteTunnel(ctx context.Context, tunnelID string) error {
	query := map[string]string{"force": "true"}
	var result any
	return c.doJSON(ctx, http.MethodDelete,
		fmt.Sprintf("/accounts/%s/cfd_tunnel/%s", c.cfg.AccountID, tunnelID),
		query,
		nil,
		&result,
	)
}

func (c *Client) EnsureCNAME(ctx context.Context, fqdn string, target string) error {
	zoneID, err := c.zoneID(ctx)
	if err != nil {
		return err
	}

	rec, err := c.GetDNSRecordByName(ctx, fqdn)
	if err != nil {
		return err
	}

	payload := map[string]any{
		"type":    "CNAME",
		"name":    fqdn,
		"content": target,
		"proxied": true,
		"ttl":     1,
	}

	if rec == nil {
		var created DNSRecord
		return c.doJSON(ctx, http.MethodPost,
			fmt.Sprintf("/zones/%s/dns_records", zoneID),
			nil,
			payload,
			&created,
		)
	}

	if strings.EqualFold(rec.Content, target) && rec.Proxied {
		return nil
	}

	var updated DNSRecord
	return c.doJSON(ctx, http.MethodPut,
		fmt.Sprintf("/zones/%s/dns_records/%s", zoneID, rec.ID),
		nil,
		payload,
		&updated,
	)
}

func (c *Client) DeleteDNSRecordByName(ctx context.Context, fqdn string) error {
	zoneID, err := c.zoneID(ctx)
	if err != nil {
		return err
	}

	rec, err := c.GetDNSRecordByName(ctx, fqdn)
	if err != nil {
		return err
	}
	if rec == nil {
		return nil
	}

	var result any
	return c.doJSON(ctx, http.MethodDelete,
		fmt.Sprintf("/zones/%s/dns_records/%s", zoneID, rec.ID),
		nil,
		nil,
		&result,
	)
}

func (c *Client) DeleteDNSRecordByID(ctx context.Context, recordID string) error {
	zoneID, err := c.zoneID(ctx)
	if err != nil {
		return err
	}
	if strings.TrimSpace(recordID) == "" {
		return nil
	}
	var result any
	return c.doJSON(ctx, http.MethodDelete,
		fmt.Sprintf("/zones/%s/dns_records/%s", zoneID, recordID),
		nil,
		nil,
		&result,
	)
}

func (c *Client) GetDNSRecordByName(ctx context.Context, fqdn string) (*DNSRecord, error) {
	zoneID, err := c.zoneID(ctx)
	if err != nil {
		return nil, err
	}

	query := map[string]string{
		"type": "CNAME",
		"name": fqdn,
	}
	var result []DNSRecord
	if err := c.doJSON(ctx, http.MethodGet,
		fmt.Sprintf("/zones/%s/dns_records", zoneID),
		query,
		nil,
		&result,
	); err != nil {
		return nil, err
	}
	if len(result) == 0 {
		return nil, nil
	}
	return &result[0], nil
}

func (c *Client) ListTunnels(ctx context.Context) ([]Tunnel, error) {
	query := map[string]string{
		"is_deleted": "false",
		"per_page":   "1000",
	}
	var result []Tunnel
	if err := c.doJSON(ctx, http.MethodGet,
		fmt.Sprintf("/accounts/%s/cfd_tunnel", c.cfg.AccountID),
		query,
		nil,
		&result,
	); err != nil {
		return nil, err
	}
	return result, nil
}

func (c *Client) ListCNAMERecords(ctx context.Context) ([]DNSRecord, error) {
	zoneID, err := c.zoneID(ctx)
	if err != nil {
		return nil, err
	}
	query := map[string]string{
		"type":     "CNAME",
		"per_page": "5000",
	}
	var result []DNSRecord
	if err := c.doJSON(ctx, http.MethodGet,
		fmt.Sprintf("/zones/%s/dns_records", zoneID),
		query,
		nil,
		&result,
	); err != nil {
		return nil, err
	}
	return result, nil
}

func (c *Client) zoneID(ctx context.Context) (string, error) {
	if strings.TrimSpace(c.cfg.ZoneID) != "" {
		return c.cfg.ZoneID, nil
	}

	query := map[string]string{
		"name":   c.cfg.PrimaryDomain,
		"status": "active",
	}
	var zones []Zone
	if err := c.doJSON(ctx, http.MethodGet, "/zones", query, nil, &zones); err != nil {
		return "", err
	}
	if len(zones) == 0 {
		return "", fmt.Errorf("zone not found for primary domain %s", c.cfg.PrimaryDomain)
	}
	c.cfg.ZoneID = zones[0].ID
	return c.cfg.ZoneID, nil
}

func (c *Client) doJSON(ctx context.Context, method string, apiPath string, query map[string]string, payload any, out any) error {
	u, err := url.Parse(baseURL)
	if err != nil {
		return err
	}
	u.Path = path.Join(u.Path, apiPath)

	q := u.Query()
	for k, v := range query {
		q.Set(k, v)
	}
	u.RawQuery = q.Encode()

	var body io.Reader
	if payload != nil {
		raw, err := json.Marshal(payload)
		if err != nil {
			return fmt.Errorf("marshal request payload: %w", err)
		}
		body = bytes.NewReader(raw)
	}

	req, err := http.NewRequestWithContext(ctx, method, u.String(), body)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+c.cfg.APIToken)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 400 {
		raw, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("cloudflare api %s %s failed: status=%d body=%s", method, apiPath, resp.StatusCode, string(raw))
	}

	var envelope apiEnvelope[json.RawMessage]
	if err := json.NewDecoder(resp.Body).Decode(&envelope); err != nil {
		return fmt.Errorf("decode cloudflare envelope: %w", err)
	}

	if !envelope.Success {
		parts := make([]string, 0, len(envelope.Errors))
		for _, e := range envelope.Errors {
			parts = append(parts, fmt.Sprintf("%d:%s", e.Code, e.Message))
		}
		return fmt.Errorf("cloudflare api error: %s", strings.Join(parts, ", "))
	}

	if out == nil {
		return nil
	}
	if len(envelope.Result) == 0 || string(envelope.Result) == "null" {
		return nil
	}
	if err := json.Unmarshal(envelope.Result, out); err != nil {
		return fmt.Errorf("decode cloudflare result: %w", err)
	}
	return nil
}
