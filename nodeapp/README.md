# Diretorio `nodeapp`

Este diretorio contem a aplicacao Node.js usada como API simples do projeto.

## Funcao da pasta
- Empacotar e executar o servico `nodeapp` no Docker.
- Expor uma rota HTTP basica para validar que o backend esta funcionando.

## Arquivos
- `server.js`: codigo da API em Express; sobe servidor na porta `4000` e responde na rota `/`.
- `package.json`: metadados e dependencias do projeto Node.js (inclui `express`).
- `Dockerfile`: instrucoes de build da imagem do `nodeapp`.
- `README.md`: esta documentacao da pasta.
