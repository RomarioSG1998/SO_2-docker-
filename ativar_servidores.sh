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

upsert_env_var() {
  local key="$1"
  local value="$2"

  if grep -Eq "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    printf "\n%s=%s\n" "$key" "$value" >> "$ENV_FILE"
  fi
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

configure_compatibility_for_cpu() {
  local cpuinfo_file="/proc/cpuinfo"
  [[ -r "$cpuinfo_file" ]] || return 0

  if grep -Eqi '(^|\s)avx(\s|$)' "$cpuinfo_file"; then
    return 0
  fi

  warn "CPU sem suporte AVX detectada. Ajustando stack para imagens compativeis."
  upsert_env_var "MONGO_IMAGE" "mongo:4.4.29"
  upsert_env_var "ROCKETCHAT_IMAGE" "rocketchat/rocket.chat:4.8.7"
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

  # Mongo em container costuma executar com UID/GID 999 e precisa ler o keyfile.
  if command -v sudo >/dev/null 2>&1; then
    if ! sudo chown 999:999 "$keyfile" 2>/dev/null; then
      warn "Nao foi possivel ajustar owner do mongo-keyfile para 999:999. Tentando manter configuracao atual."
    fi
    sudo chmod 400 "$keyfile" 2>/dev/null || true
  else
    chown 999:999 "$keyfile" 2>/dev/null || true
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
  cid="$(docker compose -f "$COMPOSE_FILE" ps -q "$service" 2>/dev/null || true)"
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

wait_for_mongo_healthy() {
  local max_tries=30
  local sleep_seconds=3
  local try mongo_state

  for ((try=1; try<=max_tries; try++)); do
    mongo_state="$(container_health mongo)"
    info "Aguardando mongo (${try}/${max_tries}) -> ${mongo_state}"
    if [[ "$mongo_state" == "healthy" ]]; then
      return 0
    fi
    sleep "$sleep_seconds"
  done
  return 1
}

ensure_replica_set_ready() {
  local max_tries=30
  local sleep_seconds=3
  local try

  for ((try=1; try<=max_tries; try++)); do
    if docker compose -f "$COMPOSE_FILE" exec -T mongo sh -lc '
      if command -v mongosh >/dev/null 2>&1; then
        SHELL_CMD="mongosh"
      else
        SHELL_CMD="mongo"
      fi

      $SHELL_CMD --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --eval "
        try {
          const s = rs.status();
          if (s.ok === 1) { print(\"RS_OK\"); }
        } catch (e) {
          const r = rs.initiate({_id: \"rs0\", members: [{_id: 0, host: \"mongo:27017\"}]});
          printjson(r);
        }
      " >/tmp/rs_init_out.txt 2>/tmp/rs_init_err.txt

      $SHELL_CMD --quiet -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --eval "rs.status().ok" | grep -q 1
    ' >/dev/null 2>&1; then
      info "Replica set rs0 pronto."
      return 0
    fi

    info "Aguardando inicializacao do replica set (${try}/${max_tries})..."
    sleep "$sleep_seconds"
  done

  warn "Nao foi possivel confirmar replica set rs0."
  docker compose -f "$COMPOSE_FILE" logs --tail=80 mongo || true
  return 1
}

start_stack() {
  info "Subindo stack..."
  docker compose -f "$COMPOSE_FILE" up -d --build mongo nodeapp
  wait_for_mongo_healthy
  ensure_replica_set_ready
  docker compose -f "$COMPOSE_FILE" up -d --build rocketchat caddy
}

recover_from_mongo_unhealthy() {
  warn "Aplicando recuperacao automatica (docker compose down -v) e nova tentativa..."
  docker compose -f "$COMPOSE_FILE" down -v --remove-orphans || true
  ensure_keyfile_exists
  ensure_keyfile_permissions
  start_stack
  wait_for_services
}

recover_with_legacy_rocketchat() {
  warn "Aplicando fallback de compatibilidade do Rocket.Chat para Mongo 4.4..."
  upsert_env_var "ROCKETCHAT_IMAGE" "rocketchat/rocket.chat:4.8.7"
  docker compose -f "$COMPOSE_FILE" down -v --remove-orphans || true
  start_stack
  wait_for_services
}

main() {
  require_cmd docker
  docker compose version >/dev/null 2>&1 || error "Docker Compose nao disponivel."
  [[ -f "$COMPOSE_FILE" ]] || error "Arquivo nao encontrado: $COMPOSE_FILE"

  ensure_env_file
  configure_compatibility_for_cpu
  ensure_keyfile_exists
  ensure_keyfile_permissions
  ensure_hosts_mapping

  if ! start_stack; then
    warn "Falha ao subir stack na primeira tentativa."
    recover_from_mongo_unhealthy || {
      docker compose -f "$COMPOSE_FILE" ps || true
      docker compose -f "$COMPOSE_FILE" logs --tail=120 mongo rocketchat caddy || true
      error "Falha ao subir stack."
    }
  elif ! wait_for_services; then
    if ! recover_from_mongo_unhealthy; then
      if docker compose -f "$COMPOSE_FILE" logs --tail=200 rocketchat 2>/dev/null | grep -Eqi 'mongo.*(version|5\.0|6\.0|unsupported|minim)'; then
        recover_with_legacy_rocketchat || {
          docker compose -f "$COMPOSE_FILE" ps || true
          docker compose -f "$COMPOSE_FILE" logs --tail=120 mongo rocketchat caddy || true
          error "Falha ao aguardar servicos ficarem saudaveis."
        }
      else
        docker compose -f "$COMPOSE_FILE" ps || true
        docker compose -f "$COMPOSE_FILE" logs --tail=120 mongo rocketchat caddy || true
        error "Falha ao aguardar servicos ficarem saudaveis."
      fi
    fi
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
