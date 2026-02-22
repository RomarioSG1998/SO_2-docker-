#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$PROJECT_DIR/compose.yml"

usage() {
  cat <<EOF
Uso: ./parar_servidores.sh [--volumes]

Opcoes:
  --volumes   Remove tambem os volumes do Docker Compose (dados serao apagados).
EOF
}

info() {
  echo "[INFO] $*"
}

error() {
  echo "[ERRO] $*" >&2
  exit 1
}

main() {
  local remove_volumes="false"

  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  if [[ "${1:-}" == "--volumes" ]]; then
    remove_volumes="true"
  elif [[ "${1:-}" != "" ]]; then
    usage
    error "Opcao invalida: $1"
  fi

  command -v docker >/dev/null 2>&1 || error "Comando docker nao encontrado."
  docker compose version >/dev/null 2>&1 || error "Docker Compose nao disponivel."
  [[ -f "$COMPOSE_FILE" ]] || error "Arquivo nao encontrado: $COMPOSE_FILE"

  if [[ "$remove_volumes" == "true" ]]; then
    info "Parando stack e removendo volumes..."
    docker compose -f "$COMPOSE_FILE" down -v
  else
    info "Parando stack..."
    docker compose -f "$COMPOSE_FILE" down
  fi

  info "Concluido."
}

main "$@"
