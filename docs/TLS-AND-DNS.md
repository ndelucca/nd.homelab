# TLS and DNS — evaluation & options

Two resilience/UX gaps from the audit that are **deliberately left as documented
options** (not implemented), because both involve trade-offs only you can pick.

---

## 1. TLS: self-signed today, Let's Encrypt if you want trusted certs

### Current state

NGINX terminates TLS with a **self-signed** certificate
(`nginx_generate_selfsigned_cert: true`, `roles/nginx`). It is encrypted and
fine for a LAN, but every browser shows a warning and you click through it.

### Option: Let's Encrypt via DNS-01

You already own `ndelucca-server.com` and run your own DNS (AdGuard) — so the
**DNS-01 challenge** is the right fit. It does **not** require exposing the
server to the internet (unlike HTTP-01), so the services stay LAN-only.

How it would work:

1. Use a public DNS provider for the domain's authoritative zone (the registrar
   or e.g. Cloudflare) — DNS-01 needs a public TXT record the ACME CA can read.
   AdGuard handles *internal* resolution; it is not authoritative on the internet.
2. Run `certbot` (or `acme.sh`/`lego`) with the provider's DNS plugin + an API
   token to create the `_acme-challenge` TXT record automatically.
3. Issue a **wildcard** cert for `*.ndelucca-server.com` (one cert for every
   subdomain) and point `nginx_ssl_certificate` / `_key` at it.
4. Renew on a systemd timer; reload NGINX in the deploy hook.

Sketch of an `nginx_tls_mode` switch in the role:

```yaml
# roles/nginx/defaults/main.yml
nginx_tls_mode: selfsigned          # selfsigned | letsencrypt
nginx_letsencrypt_email: ""
nginx_letsencrypt_domain: "*.{{ nginx_domain }}"
nginx_letsencrypt_dns_provider: cloudflare   # certbot-dns-<provider> plugin
# nginx_letsencrypt_api_token lives in group_vars/homeservers/vault.yml
```

Trade-offs:

- **Pro:** no browser warnings, real chain of trust, wildcard covers all apps.
- **Con:** depends on a public DNS provider + an API token (a new secret to
  hold), and on outbound reachability to the ACME CA at renewal time.
- **Note:** a public cert for `*.ndelucca-server.com` is logged in public
  Certificate Transparency logs (the name is exposed; the services are not).

**Recommendation:** worthwhile only if the cert warning actually bothers you or
you want to share access. For a purely personal LAN, self-signed is acceptable —
keep the option here and revisit if usage changes.

---

## 2. DNS: AdGuard is the LAN's single point of failure

### Current state

AdGuard Home serves **both** DHCP and DNS for the whole LAN. If it goes down,
every device loses name resolution. This is mitigated by the post-boot watchdog
(`service_maintenance` restarts AdGuard), but a hard failure still takes the LAN
offline for resolution.

### Option A — advertise a secondary DNS in DHCP (cheap, recommended)

Hand clients a fallback resolver alongside AdGuard, so a single AdGuard outage
degrades to "ads not filtered" instead of "no internet":

- Add a public resolver (e.g. `1.1.1.1` / `9.9.9.9`) or the router as the
  **secondary** DNS in the DHCP options.
- Caveat: clients may use the secondary opportunistically, so some queries
  bypass filtering even when AdGuard is healthy. Acceptable for resilience; if
  strict filtering matters more than uptime, skip this and rely on the watchdog.

This is a small change in the AdGuard DHCP config (`adguard_dhcp_*` in
`group_vars/homeservers/services.yml`) — add the secondary DNS option.

### Option B — a real second AdGuard instance (more work)

Run a second lightweight AdGuard (e.g. on the Raspberry Pi already in the
inventory) and advertise both as DNS in DHCP. AdGuard Home doesn't natively sync
config between instances, so you'd manage both via this playbook (the config is
already declarative here). Highest resilience; highest effort.

**Recommendation:** start with **Option A** (one DHCP option) for a large
resilience win at near-zero cost; consider Option B only if DNS uptime becomes
critical.

---

## What was implemented vs. documented

- **Implemented:** monitoring (Uptime-Kuma) — so you'll *know* when AdGuard or
  any service is down; backup failure/disk alerts.
- **Documented only (this file):** Let's Encrypt and the secondary-DNS change,
  because each needs a decision (public DNS provider / filtering-vs-uptime).
