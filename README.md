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
