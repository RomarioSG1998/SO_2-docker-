# 🛠️ Estudo de Caso: Colisão de Rota /api no Proxy Reverso (Caddy)

Este documento detalha o erro de colisão de rotas identificado durante a integração do **Rocket.Chat** com a **API Node.js**, utilizando o **Caddy** como proxy reverso.

---

## 🚨 O Problema (O Erro)

Ao tentar acessar o Rocket.Chat através do domínio configurado, a aplicação ficava travada na tela de carregamento. Ao inspecionar o tráfego de rede, notou-se que requisições essenciais para a inicialização do Rocket.Chat estavam retornando erro **404 Not Found**.

### Sintomas
- Frontend do Rocket.Chat não carregava completamente.
- Requisições para `GET /api/info` e `GET /api/v1/settings.public` falhavam com erro 404.
- A API Node.js recebia requisições que não pertenciam a ela.

---

## 🔍 Causa Raiz

A configuração inicial do `Caddyfile` utilizava um seletor genérico para a API Node.js:

```caddy
# Configuração ANTERIOR (Problemática)
handle_path /api* {
    reverse_proxy nodeapp:4000
}
```

**O que acontecia:**
O Caddy interpretava o curinga `*` em `/api*` como *"qualquer rota que comece com /api"*. Isso incluía não apenas a nossa API Node (`/api`), mas também todas as rotas de API nativas do Rocket.Chat (que também começam com `/api/v1/...`). Como o Nodeapp não possuía essas rotas definidas, ele retornava 404.

---

## ✅ Solução Aplicada

A solução consistiu em refinar o roteamento no `Caddyfile` para distinguir entre a **rota exata** da nossa API e as rotas destinadas ao Rocket.Chat.

### Ajuste no Caddyfile

Utilizamos um "Matcher" nomeado para capturar apenas o caminho exato `/api`:

```caddy
# Configuração ATUAL (Corrigida)
http://rocket.chat {
    # 1. Define um matcher para o caminho EXATO /api
    @node_api_root path /api
    
    # 2. Trata apenas a raiz da nossa API
    handle @node_api_root {
        uri strip_prefix /api
        reverse_proxy nodeapp:4000
    }

    # 3. Todo o restante (incluindo /api/v1/*) vai para o Rocket.Chat
    handle {
        reverse_proxy rocketchat:3000 {
            header_up X-Real-IP {remote_host}
        }
    }
}
```

### Por que isso funciona?
Ao usar `@node_api_root path /api`, garantimos que o Caddy só envie para o container `nodeapp` o que for exatamente `/api`. Qualquer sub-caminho (como `/api/info`) não dará "match" nessa regra e cairá no `handle` padrão, sendo redirecionado corretamente para o `rocketchat`.

---

## 🛠️ Comandos de Verificação

Para garantir que a solução foi eficaz, executamos os seguintes testes de integridade:

1. **Checar API Node (Rota Customizada):**
   ```bash
   curl -I http://rocket.chat/api
   # Esperado: HTTP 200 (Vindo do nodeapp)
   ```

2. **Checar API Rocket.Chat (Nativa):**
   ```bash
   curl -I http://rocket.chat/api/info
   # Esperado: HTTP 200 (Vindo do rocketchat)
   ```

3. **Logs do Docker Compose:**
   ```bash
   docker compose logs -f caddy
   # Verificar se as rotas estão sendo distribuídas corretamente entre os "upstreams"
   ```

---

## 📈 Conclusão

Este erro ressalta a importância de sermos específicos ao configurar proxies reversos quando múltiplos serviços compartilham prefixos de URL semelhantes. A distinção clara entre `/api` e `/api/*` resolveu a colisão sem a necessidade de alterar as URLs públicas dos serviços, mantendo a arquitetura limpa e funcional.
