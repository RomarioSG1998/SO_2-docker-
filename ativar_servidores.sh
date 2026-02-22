#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$PROJECT_DIR/compose.yml"
ENV_FILE="$PROJECT_DIR/.env"
ENV_EXAMPLE_FILE="$PROJECT_DIR/.env.example"
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

ensure_env_file() {
  if [[ -f "$ENV_FILE" ]]; then
    info "Arquivo .env encontrado."
    return
  fi

  if [[ -f "$ENV_EXAMPLE_FILE" ]]; then
    info ".env nao encontrado. Criando automaticamente a partir de .env.example..."
    cp "$ENV_EXAMPLE_FILE" "$ENV_FILE"
    info ".env criado com sucesso."
    return
  fi

  info ".env e .env.example nao encontrados. Gerando .env padrao..."
  cat > "$ENV_FILE" <<'EOF'
MONGO_INITDB_ROOT_USERNAME=admin
MONGO_INITDB_ROOT_PASSWORD=123456
ROOT_URL=http://rocket.chat
PORT=3000
EOF
  info ".env padrao criado com sucesso."
}

ensure_keyfile_exists() {
  local keyfile="$PROJECT_DIR/mongo-keyfile"

  if [[ -d "$keyfile" ]]; then
    warn "Encontrado diretorio em '$keyfile' (era esperado arquivo). Tentando corrigir automaticamente..."
    if command -v sudo >/dev/null 2>&1; then
      sudo rm -rf "$keyfile" || error "Falha ao remover diretorio '$keyfile'."
    else
      rm -rf "$keyfile" || error "Falha ao remover diretorio '$keyfile'."
    fi
  fi

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
    if ! chmod 400 "$keyfile" 2>/dev/null; then
      if command -v sudo >/dev/null 2>&1; then
        sudo chmod 400 "$keyfile" || error "Falha ao aplicar chmod 400 em $keyfile."
      else
        error "Falha ao aplicar chmod 400 em $keyfile."
      fi
    fi
  else
    info "Permissao do mongo-keyfile OK (400)."
  fi

  if [[ ! -w "$keyfile" ]]; then
    if command -v sudo >/dev/null 2>&1; then
      sudo chown "$(id -u)":"$(id -g)" "$keyfile" >/dev/null 2>&1 || true
    fi
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
  return 1
}

start_stack() {
  info "Subindo stack..."
  docker compose -f "$COMPOSE_FILE" up -d --build
}

recover_from_mongo_unhealthy() {
  local mongo_state
  mongo_state="$(container_health mongo)"

  if [[ "$mongo_state" != "unhealthy" ]]; then
    return 1
  fi

  warn "Mongo ficou unhealthy. Aplicando recuperacao automatica (docker compose down -v) e nova tentativa..."
  docker compose -f "$COMPOSE_FILE" down -v --remove-orphans || true
  start_stack
  wait_for_services
}

main() {
  require_cmd docker
  docker compose version >/dev/null 2>&1 || error "Docker Compose nao disponivel."
  [[ -f "$COMPOSE_FILE" ]] || error "Arquivo nao encontrado: $COMPOSE_FILE"

  ensure_env_file
  ensure_keyfile_exists
  ensure_keyfile_permissions
  ensure_hosts_mapping

  if ! start_stack; then
    warn "Falha ao subir stack na primeira tentativa."
    recover_from_mongo_unhealthy || error "Falha ao subir stack."
  elif ! wait_for_services; then
    recover_from_mongo_unhealthy || error "Falha ao aguardar servicos ficarem saudaveis."
  fi

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
