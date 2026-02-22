# Documentacao de Erros e Solucoes

## Erro 1 - App fica carregando ao abrir
- Sintoma:
  - Tela do Rocket.Chat carregando sem concluir.
  - Logs do Caddy com `502` e `connection refused` para `rocketchat:3000`.
- Causa:
  - O Caddy recebia requisicoes antes do Rocket.Chat ficar pronto.
- Solucao aplicada:
  - Adicao de `healthcheck` em `mongo`, `rocketchat` e `nodeapp` no `compose.yml`.
  - Uso de `depends_on` com `condition: service_healthy` para controlar ordem de subida.

## Erro 2 - Healthcheck falhando mesmo com app no ar
- Sintoma:
  - `rocketchat` ficava em `health: starting` por muito tempo.
- Causa:
  - Healthcheck usando `localhost`, que no container tentava IPv6 (`::1`) e falhava.
- Solucao aplicada:
  - Troca de `localhost` para `127.0.0.1` nos healthchecks:
    - Rocket.Chat: `http://127.0.0.1:3000/api/info`
    - Node app: `http://127.0.0.1:4000`

## Erro 3 - Colisao de rota `/api` entre Node e Rocket.Chat (causa raiz)
- Sintoma:
  - Frontend do Rocket.Chat travava em carregamento.
  - Requisicoes essenciais retornavam `404`:
    - `GET /api/info`
    - `GET /api/v1/settings.public`
- Causa:
  - O `Caddyfile` roteava `handle_path /api*` para `nodeapp:4000`.
  - Isso interceptava APIs nativas do Rocket.Chat.
- Solucao aplicada:
  - Separacao de roteamento sem alterar estrutura publica:
    - `/api` (rota exata) -> `nodeapp`
    - `/api/*` -> Rocket.Chat
  - Mantido Rocket.Chat como destino padrao para o restante das rotas.

## Erro 4 - Projeto nao sobe em maquina nova por falta do `.env`
- Sintoma:
  - Ao executar `bash ativar_servidores.sh`, o Docker Compose falhava com:
    - `env file .../.env not found`
  - Tambem apareciam avisos de variaveis nao definidas:
    - `MONGO_INITDB_ROOT_USERNAME`
    - `MONGO_INITDB_ROOT_PASSWORD`
- Causa:
  - O `compose.yml` dependia de `.env` obrigatorio em ambientes recem-clonados.
- Solucao aplicada:
  - `ativar_servidores.sh` agora cria `.env` automaticamente:
    - Primeiro tenta copiar de `.env.example`.
    - Se `.env.example` nao existir, gera `.env` padrao.
  - `compose.yml` passou a usar defaults para variaveis essenciais:
    - `MONGO_INITDB_ROOT_USERNAME` (`admin`)
    - `MONGO_INITDB_ROOT_PASSWORD` (`123456`)
    - `ROOT_URL` (`http://rocket.chat`)
    - `PORT` (`3000`)
- Resultado:
  - O projeto sobe de forma natural em maquina nova, sem erro por ausencia de `.env`.

## Erro 5 - Mongo inicia, mas fica `unhealthy` e bloqueia dependencias
- Sintoma:
  - `dependency failed to start: container ...-mongo-1 is unhealthy`
  - Servicos dependentes (`rocketchat`) nao iniciam.
- Causa:
  - Com autenticacao habilitada no Mongo, o healthcheck sem usuario/senha falhava.
- Solucao aplicada:
  - Ajuste do healthcheck do `mongo` no `compose.yml` para autenticar com:
    - `MONGO_INITDB_ROOT_USERNAME`
    - `MONGO_INITDB_ROOT_PASSWORD`
  - Fallback no healthcheck para cenario com volume antigo (tentativa sem autenticacao).
  - `ativar_servidores.sh` agora tenta recuperacao automatica quando detecta `mongo` unhealthy:
    - executa `docker compose down -v --remove-orphans`
    - sobe a stack novamente
  - Com isso, o status `healthy` reflete o estado real do banco.

## Erro 6 - `mongo-keyfile` vira pasta e fica sem permissao para apagar
- Sintoma:
  - O caminho `mongo-keyfile` aparece como diretorio.
  - Nao e possivel apagar/alterar sem `sudo`.
- Causa:
  - Em alguns cenarios de bind mount, quando o arquivo nao existe, o Docker pode criar o caminho como pasta (root).
- Solucao aplicada:
  - `ativar_servidores.sh` agora detecta automaticamente quando `mongo-keyfile` e diretorio.
  - O script remove o diretorio (com `sudo` quando necessario), recria o arquivo e reaplica permissao `400`.

## Erro 7 - Mongo falha com `Illegal instruction` em CPU sem AVX
- Sintoma:
  - Container `mongo` entra em restart loop com mensagem:
    - `MongoDB 5.0+ requires a CPU with AVX support`
    - `Illegal instruction (core dumped)`
- Causa:
  - A imagem `mongo:7` exige AVX e nao roda em CPUs antigas sem essa instrucao.
- Solucao aplicada:
  - O `compose.yml` passou a aceitar `MONGO_IMAGE` e `ROCKETCHAT_IMAGE` por variaveis de ambiente.
  - O `ativar_servidores.sh` detecta CPU sem AVX e ajusta automaticamente:
    - `MONGO_IMAGE=mongo:4.4.29`
    - `ROCKETCHAT_IMAGE=rocketchat/rocket.chat:5.4.3`
  - Healthcheck do Mongo ficou compativel com `mongosh` (Mongo 7) e `mongo` (Mongo 4.4).

## Validacao final
- `GET /api/info` -> `200` (Rocket.Chat)
- `GET /api/v1/settings.public` -> `200` (Rocket.Chat)
- `GET /api` -> `200` (Node app)
- `docker compose -f compose.yml ps` com servicos `healthy`

## Observacao operacional
- Se o navegador continuar com comportamento antigo, limpar cache/local storage/service worker de `localhost` e testar novamente.
