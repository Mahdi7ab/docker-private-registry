# Self-Hosted Docker Registry with TLS & Basic Auth

A fully automated, secure, self-hosted Docker Registry setup for Ubuntu servers using **Docker Compose**, **self-signed TLS**, and **htpasswd authentication**. Ideal for private CI/CD pipelines with **GitHub Actions**.

> No domain? No problem — works with **IP address only**.

---

## Features

- **TLS encryption** with self-signed certificate (IP-based SAN)
- **Basic authentication** via `htpasswd`
- **Persistent storage** in `/srv/data/registry`
- **Zero-downtime restarts**
- **Automated setup script** (one command)
- **GitHub Actions ready** (push/pull with self-hosted runners)
- **Docker daemon auto-trusts CA** on host

---

## Directory Structure

```
/srv/infra/registry/
├── docker-compose.yml
├── certs/
│   ├── registry.crt
│   └── registry.key
└── auth/
    └── htpasswd

/srv/data/registry/        # ← Docker image layers (persistent)
```

---

## Prerequisites

- Ubuntu 20.04 / 22.04 / 24.04
- Public IP address (e.g., `203.0.113.10`)
- Open port: `5000/tcp` (or change in compose)
- Root or sudo access

---

## Quick Start (One Command)

```bash
curl -fsSL https://raw.githubusercontent.com/yourusername/docker-registry-selfhosted/main/setup-registry.sh -o setup-registry.sh
chmod +x setup-registry.sh
sudo ./setup-registry.sh
```

> You’ll be prompted for:
> - Server **IP address**
> - Registry **username** (default: `admin`)
> - Registry **password**

Or skip prompts with environment variables:

```bash
sudo REGISTRY_IP=203.0.113.10 \
     REGISTRY_USER=admin \
     REGISTRY_PASS=MySecurePass123 \
     ./setup-registry.sh
```

---

## Manual Verification

```bash
# Check status
sudo docker compose -f /srv/infra/registry/docker-compose.yml ps

# View logs
sudo docker compose -f /srv/infra/registry/logs

# Test login
docker login 203.0.113.10:5000 -u admin -p MySecurePass123
```

---

## GitHub Actions Integration

### 1. Add Secrets to Your Repo

| Secret Name | Value |
|------------|-------|
| `REGISTRY_URL` | `203.0.113.10:5000` |
| `REGISTRY_USER` | `admin` |
| `REGISTRY_PASS` | `MySecurePass123` |
| `REGISTRY_CA_CERT` | *(content of `/srv/infra/registry/certs/registry.crt`)* |

```bash
cat /srv/infra/registry/certs/registry.crt
# → Copy entire output into the secret
```

### 2. Example Workflow (`.github/workflows/docker.yml`)

```yaml
name: Build & Push to Self-Hosted Registry

on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Trust self-signed CA
      - name: Install CA Certificate
        run: |
          echo "${{ secrets.REGISTRY_CA_CERT }}" | sudo tee /etc/docker/certs.d/${{ secrets.REGISTRY_URL }}/ca.crt
          sudo mkdir -p /etc/docker/certs.d/${{ secrets.REGISTRY_URL }}

      # Login
      - name: Login to Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ secrets.REGISTRY_URL }}
          username: ${{ secrets.REGISTRY_USER }}
          password: ${{ secrets.REGISTRY_PASS }}

      # Build & Push
      - name: Build and Push
        run: |
          docker build . -t ${{ secrets.REGISTRY_URL }}/my-nuxt-app:latest
          docker push ${{ secrets.REGISTRY_URL }}/my-nuxt-app:latest
```

---

## Security Notes

- **Self-signed cert**: Trusted only where you add the CA
- **Never expose over HTTP** in production
- Rotate credentials: re-run script or update `htpasswd` manually
- Firewall: Allow only `5000/tcp` from trusted sources

```bash
sudo ufw allow from 192.168.1.0/24 to any port 5000  # example: restrict to VPN
```

---

## Update Registry Image

```bash
cd /srv/infra/registry
sudo docker compose pull
sudo docker compose up -d
```

---

## Troubleshooting

| Issue | Solution |
|------|----------|
| `x509: certificate signed by unknown authority` | CA not trusted → copy `registry.crt` to client |
| `unauthorized: authentication required` | Wrong username/password |
| Port in use | Change host port in `docker-compose.yml` (e.g. `5001:5000`) |

Let me know if you want a **dark mode badge**, **GitHub Actions badge**, or **Persian version** too!
