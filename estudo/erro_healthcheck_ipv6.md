# 🛠️ Estudo de Caso: Falha no Healthcheck (Localhost vs IPv6)

Este documento detalha o erro de monitoramento de estado (healthcheck) identificado nos containers Docker, onde os serviços permaneciam em estado `starting` ou `unhealthy` mesmo estando operacionais.

---

## 🚨 O Problema (O Erro)

Após subir a stack com `docker compose`, os serviços (especialmente o Rocket.Chat e a Nodeapp) demoravam excessivamente para serem marcados como `healthy` pelo Docker, ou falhavam permanentemente no healthcheck.

### Sintomas
- Status do container travado em `(health: starting)`.
- Dependências (como o Caddy) não subiam porque aguardavam o status `healthy` dos serviços anteriores.
- Logs do Docker indicavam que o comando de healthcheck estava retornando erro, apesar de o serviço estar acessível externamente.

---

## 🔍 Causa Raiz

A configuração inicial utilizava o nome `localhost` para realizar as chamadas de teste internas:

```yaml
# Configuração ANTERIOR (Problemática)
healthcheck:
  test: ["CMD-SHELL", "wget -qO- http://localhost:4000 >/dev/null 2>&1"]
```

**O que acontecia:**
Dentro de muitos containers Docker modernos (como os baseados em Alpine ou Debian Slim), o nome `localhost` é resolvido primeiramente para o endereço IPv6 `::1`. No entanto, a maioria dos serviços (Node.js, Rocket.Chat) estava configurada para escutar apenas em interfaces IPv4 ou o loopback IPv4 (`127.0.0.1`).

O utilitário de teste (`wget`, `curl` ou `node`) tentava conectar em `::1`, recebia um "Connection Refused" e o Docker marcava a tentativa como falha, ignorando que o serviço estava pronto no endereço IPv4.

---

## ✅ Solução Aplicada

A solução foi forçar o uso do endereço IP de loopback IPv4 (`127.0.0.1`) em todos os comandos de healthcheck, eliminando a ambiguidade da resolução do nome `localhost`.

### Ajustes no Compose.yml

**Para a Nodeapp:**
```yaml
healthcheck:
  test: ["CMD-SHELL", "wget -qO- http://127.0.0.1:4000 >/dev/null 2>&1"]
```

**Para o Rocket.Chat:**
```yaml
healthcheck:
  test: ["CMD-SHELL", "node -e \"require('http').get('http://127.0.0.1:3000/', r => process.exit(r.statusCode && r.statusCode < 500 ? 0 : 1)).on('error', () => process.exit(1));\""]
```

**Para o MongoDB:**
Também garantimos o uso de `127.0.0.1` ou a execução direta via shell do mongo autenticado.

---

## 🛠️ Comandos de Verificação

Para validar se o healthcheck está funcionando corretamente agora:

1. **Verificar status resumido:**
   ```bash
   docker compose ps
   # Esperado: Status "healthy" para todos os serviços após o start_period.
   ```

2. **Inspecionar detalhes do healthcheck:**
   ```bash
   docker inspect --format='{{json .State.Health}}' <container_id> | jq
   # Permite ver o log das últimas 5 tentativas e o erro exato, se houver.
   ```

---

## 📈 Conclusão

Em ambientes de containerização, o uso de IPs explícitos para comunicação interna (loopback) é uma prática recomendada para evitar problemas de resolução de nomes e incompatibilidades entre stacks IPv4/IPv6. Esta mudança garantiu que a stack subisse de forma determinística e na ordem correta das dependências.
