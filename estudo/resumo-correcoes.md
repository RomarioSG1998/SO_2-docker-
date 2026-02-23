# Resumo de Correcoes Aplicadas

## Objetivo
Tornar o projeto executavel em maquina nova com o menor numero de passos manuais possivel.

## Principais correcoes

1. Bootstrap automatico de ambiente
- Criacao automatica de `.env` quando ausente.
- Fallback para valores padrao de variaveis criticas no `compose.yml`.

2. Correcao de `mongo-keyfile`
- Geracao automatica quando ausente.
- Correcao de permissao para `400`.
- Tratamento do caso em que `mongo-keyfile` vira diretorio.
- Ajuste de ownership para `999:999` para compatibilidade com o Mongo no container.

3. Compatibilidade por hardware (CPU sem AVX)
- Deteccao automatica no script.
- Ajuste de imagens para modo legado quando necessario:
  - `MONGO_IMAGE=mongo:4.4.29`
  - `ROCKETCHAT_IMAGE=rocketchat/rocket.chat:4.8.7`

4. Inicializacao confiavel do Mongo + Replica Set
- Subida em etapas: `mongo` e `nodeapp` primeiro.
- Inicializacao e validacao idempotente do `rs0` antes de subir Rocket.Chat.
- URLs do Mongo com `replicaSet=rs0`.

5. Subida robusta do Rocket.Chat e Caddy
- Rocket.Chat sobe antes do Caddy para evitar falha de dependencia prematura.
- Caddy sobe por ultimo.

6. Healthchecks e timeout
- Healthcheck do Rocket.Chat ajustado para endpoint mais tolerante (`/`, status `<500`).
- Janela de espera aumentada no script para maquinas lentas (`120` checagens).
- Mensagem explicita quando Rocket.Chat ainda esta em `starting` na primeira execucao.

7. Acesso Docker sem friccao
- Se o usuario nao tiver permissao direta no Docker, o script usa `sudo docker` automaticamente.

## Fluxo final recomendado
```bash
bash ativar_servidores.sh
```

## Documento detalhado
- Veja `estudo/documentacao-erros.md` para historico completo de sintomas, causas e solucoes.
