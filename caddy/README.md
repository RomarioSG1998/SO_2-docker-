# Diretorio `caddy`

Este diretorio guarda a configuracao do Caddy, que funciona como proxy reverso da stack.

## Funcao da pasta
- Receber as requisicoes HTTP de entrada.
- Redirecionar `http://localhost` para `http://rocket.chat`.
- Encaminhar rotas para os servicos corretos:
  - `/api` para `nodeapp`.
  - demais rotas para `rocketchat`.

## Arquivos
- `Caddyfile`: arquivo principal de configuracao do Caddy com regras de redirecionamento e proxy.
- `README.md`: esta documentacao da pasta.
