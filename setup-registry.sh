#!/usr/bin/env bash
# =============================================================================
# Automated Self-Hosted Docker Registry Setup
# - Ubuntu (tested on 20.04/22.04/24.04)
# - TLS with self-signed cert (IP-based)
# - Basic auth via htpasswd
# - Docker Compose v2 (docker compose)
# =============================================================================

set -euo pipefail

# --------------------------- Configuration ------------------------------------
# Change these values before running (or pass them as env vars)
REGISTRY_IP="${REGISTRY_IP:-}"          # e.g. 203.0.113.10   (will ask if empty)
REGISTRY_USER="${REGISTRY_USER:-admin}" # default username
REGISTRY_PASS="${REGISTRY_PASS:-}"      # will ask interactively if empty
REGISTRY_PORT=5000

INFRA_DIR="/srv/infra/registry"
DATA_DIR="/srv/data/registry"
CERT_DIR="${INFRA_DIR}/certs"
AUTH_DIR="${INFRA_DIR}/auth"
COMPOSE_FILE="${INFRA_DIR}/docker-compose.yml"
# -----------------------------------------------------------------------------

# Helper: print with color
info()    { echo -e "\033[1;34m[INFO]\033[0m $*"; }
success() { echo -e "\033[1;32m[SUCCESS]\033[0m $*"; }
error()   { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

# Root check
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root (or with sudo)."
fi

# --------------------------- Gather missing input ---------------------------
if [[ -z "$REGISTRY_IP" ]]; then
    echo "Enter your server's public IP address (e.g. 203.0.113.10):"
    read -r REGISTRY_IP
fi
[[ -z "$REGISTRY_IP" ]] && error "IP address is required."

if [[ -z "$REGISTRY_PASS" ]]; then
    echo "Enter password for registry user '${REGISTRY_USER}':"
    read -rs REGISTRY_PASS
    echo
fi
[[ -z "$REGISTRY_PASS" ]] && error "Password cannot be empty."

# --------------------------- Install Docker & Compose -----------------------
install_docker() {
    info "Installing Docker and Docker Compose..."
    apt-get update -y
    apt-get install -y ca-certificates curl gnupg

    # Add Docker's official GPG key
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Add repo
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    success "Docker installed."
}

# Check if docker is available
if ! command -v docker &> /dev/null; then
    install_docker
else
    info "Docker already installed."
fi

# --------------------------- Create directories -----------------------------
info "Creating directory structure..."
mkdir -p "$CERT_DIR" "$AUTH_DIR" "$DATA_DIR"
success "Directories ready."

# --------------------------- Generate TLS certificate ------------------------
generate_cert() {
    info "Generating self-signed TLS certificate for IP ${REGISTRY_IP}..."
    local subj="/CN=${REGISTRY_IP}"
    local san="subjectAltName = IP:${REGISTRY_IP}"

    openssl req -newkey rsa:2048 -nodes \
        -keyout "${CERT_DIR}/registry.key" \
        -x509 -days 365 -out "${CERT_DIR}/registry.crt" \
        -subj "$subj" -addext "$san" >/dev/null 2>&1

    chmod 644 "${CERT_DIR}/registry.crt"
    chmod 600 "${CERT_DIR}/registry.key"
    success "TLS certificate created."
}
generate_cert

# --------------------------- Generate htpasswd ------------------------------
generate_htpasswd() {
    info "Creating htpasswd file for user '${REGISTRY_USER}'..."
    # Use httpd container to generate bcrypt hash
    docker run --rm \
        -v "${AUTH_DIR}:/auth" \
        httpd:2 \
        htpasswd -Bbn "$REGISTRY_USER" "$REGISTRY_PASS" > "${AUTH_DIR}/htpasswd"
    success "htpasswd file created."
}
generate_htpasswd

# --------------------------- Write docker-compose.yml ------------------------
write_compose() {
    info "Writing docker-compose.yml..."
    cat > "$COMPOSE_FILE" <<EOF
version: '3.8'
services:
  registry:
    image: registry:2
    restart: always
    ports:
      - "${REGISTRY_PORT}:5000"
    environment:
      REGISTRY_HTTP_TLS_CERTIFICATE: /certs/registry.crt
      REGISTRY_HTTP_TLS_KEY: /certs/registry.key
      REGISTRY_AUTH: htpasswd
      REGISTRY_AUTH_HTPASSWD_PATH: /auth/htpasswd
      REGISTRY_AUTH_HTPASSWD_REALM: Registry Realm
    volumes:
      - ${DATA_DIR}:/var/lib/registry
      - ${CERT_DIR}:/certs:ro
      - ${AUTH_DIR}:/auth:ro
EOF
    success "docker-compose.yml written."
}
write_compose

# --------------------------- Start the registry -----------------------------
start_registry() {
    info "Starting Docker registry..."
    cd "$INFRA_DIR"
    docker compose up -d
    success "Registry is running on https://${REGISTRY_IP}:${REGISTRY_PORT}"
}
start_registry

# --------------------------- Trust CA on the host ---------------------------
trust_ca() {
    info "Adding registry CA to Docker daemon..."
    mkdir -p "/etc/docker/certs.d/${REGISTRY_IP}:${REGISTRY_PORT}"
    cp "${CERT_DIR}/registry.crt" "/etc/docker/certs.d/${REGISTRY_IP}:${REGISTRY_PORT}/ca.crt"
    systemctl restart docker
    success "Docker daemon now trusts the registry CA."
}
trust_ca

# --------------------------- Final test ------------------------------------
test_login() {
    info "Testing login as '${REGISTRY_USER}'..."
    if docker login "${REGISTRY_IP}:${REGISTRY_PORT}" -u "$REGISTRY_USER" -p "$REGISTRY_PASS"; then
        success "Login successful!"
    else
        error "Login failed – check logs with: docker compose -f $COMPOSE_FILE logs"
    fi
}
test_login

# --------------------------- Summary ----------------------------------------
echo
echo "==================================================================="
echo "Self-hosted Docker Registry is READY!"
echo "   Registry URL : https://${REGISTRY_IP}:${REGISTRY_PORT}"
echo "   Username     : ${REGISTRY_USER}"
echo "   Password     : [hidden]"
echo
echo "To push from GitHub Actions, use:"
echo "   registry: ${REGISTRY_IP}:${REGISTRY_PORT}"
echo "   username: \${{ secrets.REGISTRY_USER }}"
echo "   password: \${{ secrets.REGISTRY_PASS }}"
echo "   CA cert : copy the content of ${CERT_DIR}/registry.crt into a secret"
echo "==================================================================="
echo

exit 0
