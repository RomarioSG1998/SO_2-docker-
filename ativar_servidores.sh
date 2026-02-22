#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$PROJECT_DIR/compose.yml"
DOMAIN="rocket.chat"

info() {
  echo "[INFO] $*"
}

warn() {
  echo "[WARN] $*" >&2
}

error() {
  echo "[ERRO] $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || error "Comando obrigatorio nao encontrado: $1"
}

ensure_keyfile_exists() {
  local keyfile="$PROJECT_DIR/mongo-keyfile"

  if [[ ! -f "$keyfile" ]]; then
    info "mongo-keyfile nao encontrado. Gerando automaticamente com openssl..."
    command -v openssl >/dev/null 2>&1 || error "openssl nao encontrado. Instale openssl e tente novamente."
    openssl rand -base64 756 > "$keyfile"
    info "mongo-keyfile gerado com sucesso."
  fi
}

ensure_keyfile_permissions() {
  local keyfile="$PROJECT_DIR/mongo-keyfile"

  [[ -f "$keyfile" ]] || error "mongo-keyfile nao encontrado em: $keyfile"

  local perms
  perms="$(stat -c '%a' "$keyfile" 2>/dev/null || stat -f '%A' "$keyfile" 2>/dev/null)"

  if [[ "$perms" != "400" ]]; then
    info "Corrigindo permissao do mongo-keyfile: $perms -> 400"
    chmod 400 "$keyfile" || error "Falha ao aplicar chmod 400 em $keyfile. Tente: sudo chmod 400 mongo-keyfile"
  else
    info "Permissao do mongo-keyfile OK (400)."
  fi
}

ensure_hosts_mapping() {
  if grep -Eq "^[[:space:]]*127\\.0\\.0\\.1[[:space:]].*\\<${DOMAIN}\\>" /etc/hosts; then
    info "Mapeamento local ja existe: 127.0.0.1 ${DOMAIN}"
    return
  fi

  info "Adicionando mapeamento local no /etc/hosts: 127.0.0.1 ${DOMAIN}"
  if command -v sudo >/dev/null 2>&1; then
    echo "127.0.0.1 ${DOMAIN}" | sudo tee -a /etc/hosts >/dev/null
  else
    echo "127.0.0.1 ${DOMAIN}" >> /etc/hosts
  fi
}

container_health() {
  local service="$1"
  local cid
  cid="$(docker compose -f "$COMPOSE_FILE" ps -q "$service")"
  if [[ -z "$cid" ]]; then
    echo "missing"
    return
  fi
  docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo "unknown"
}

wait_for_services() {
  local max_tries=60
  local sleep_seconds=5
  local try mongo_state node_state rocket_state

  for ((try=1; try<=max_tries; try++)); do
    mongo_state="$(container_health mongo)"
    node_state="$(container_health nodeapp)"
    rocket_state="$(container_health rocketchat)"

    info "Checagem ${try}/${max_tries} -> mongo=${mongo_state} nodeapp=${node_state} rocketchat=${rocket_state}"

    if [[ "$mongo_state" == "healthy" && "$node_state" == "healthy" && "$rocket_state" == "healthy" ]]; then
      info "Servicos saudaveis."
      return
    fi
    sleep "$sleep_seconds"
  done

  warn "Tempo limite excedido aguardando healthcheck."
  docker compose -f "$COMPOSE_FILE" ps || true
  docker compose -f "$COMPOSE_FILE" logs --tail=80 rocketchat caddy mongo || true
  error "Falha ao aguardar servicos ficarem saudaveis."
}

main() {
  require_cmd docker
  docker compose version >/dev/null 2>&1 || error "Docker Compose nao disponivel."
  [[ -f "$COMPOSE_FILE" ]] || error "Arquivo nao encontrado: $COMPOSE_FILE"

  ensure_keyfile_exists
  ensure_keyfile_permissions
  ensure_hosts_mapping

  info "Subindo stack..."
  docker compose -f "$COMPOSE_FILE" up -d --build

  wait_for_services

  info "Status final:"
  docker compose -f "$COMPOSE_FILE" ps

  cat <<EOF

[OK] Ambiente ativo.
- App: http://${DOMAIN}
- Redirecionamento: http://localhost -> http://${DOMAIN}
- API Node: http://${DOMAIN}/api
EOF
}

main "$@"
