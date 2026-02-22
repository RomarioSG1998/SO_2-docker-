# 🎓 JALA University — Sistemas Operacionais II

**Tarefa Final — Grupo 2**  
Graduação em Engenharia de Software

---

## 👥 Integrantes

| Nome |
|------|
| Bruna Caroline Monteiro de Sousa |
| Durval Lima de Araújo Neto |
| José Lucas de Oliveira Raposo |
| Romário de Souza Galdino |
| Thalles Eduardo Rodrigues de Araújo |
| Lucas Barbosa Ferreira |

---

## 📋 Sobre o Projeto

Infraestrutura completa implantada via **Docker Compose**, composta por quatro serviços integrados:

| Serviço | Imagem | Função |
|---------|--------|--------|
| `mongo` | `mongo:7` | Banco de dados NoSQL com Replica Set |
| `rocketchat` | `rocketchat/rocket.chat:6.9.0` | Plataforma de comunicação e colaboração |
| `nodeapp` | Build local | API Node.js (Express) — porta 4000 |
| `caddy` | `caddy:latest` | Servidor web e proxy reverso — porta 80 |

---

## 🏗️ Arquitetura

```
Cliente (Browser)
       │
       ▼
  Caddy :80  (http://rocket.chat)
       │
       ├── /api  ──────────► nodeapp:4000
       │
       └── /*    ──────────► rocketchat:3000
                                   │
                                   ▼
                             mongo:27017 (Replica Set rs0)
```

---

## ⚙️ Pré-requisitos

- [Docker](https://docs.docker.com/get-docker/) `>= 24`
- [Docker Compose](https://docs.docker.com/compose/) `>= 2`
- Entrada no `/etc/hosts` da máquina host:

```
127.0.0.1   rocket.chat
```

---

## 🚀 Como Executar

### 1. Clonar / Extrair o projeto

```bash
unzip drive-download-*.zip
cd drive-download-20260222T101945Z-1-001
```

### 2. Configurar variáveis de ambiente

Copie o arquivo de exemplo e edite com suas credenciais:

```bash
cp .env.example .env
```

```env
MONGO_INITDB_ROOT_USERNAME=admin
MONGO_INITDB_ROOT_PASSWORD=sua_senha_aqui   # ⚠️ Altere antes de subir
ROOT_URL=http://rocket.chat
PORT=3000
```

> Se o `.env` nao existir, o `./ativar_servidores.sh` cria automaticamente (usando `.env.example` quando disponivel).
> O `compose.yml` tambem possui valores padrao para variaveis criticas, evitando falha em ambiente novo.

### 3. Subir a stack

**Opção A — via script (recomendado):**

```bash
./ativar_servidores.sh
```

> O script realiza automaticamente, em ordem:
> 1. ✅ Corrige a permissão do `mongo-keyfile` para `400` — sem precisar rodar `chmod` manualmente
> 2. ✅ Adiciona a entrada `127.0.0.1 rocket.chat` no `/etc/hosts` (se ainda não existir)
> 3. ✅ Sobe todos os containers com `docker compose up -d --build`
> 4. ✅ Aguarda todos os serviços ficarem `healthy`
> 5. ✅ Se o `mongo` ficar `unhealthy`, tenta recuperacao automatica com `down -v` e sobe novamente
> 6. ✅ Exibe o status final e as URLs de acesso

**Opção B — via comandos manuais:**

```bash
# 1. Corrigir permissão do keyfile (obrigatório para o MongoDB)
chmod 400 mongo-keyfile

# 2. Adicionar o domínio no /etc/hosts
echo "127.0.0.1 rocket.chat" | sudo tee -a /etc/hosts

# 3. Subir a stack
docker compose up -d --build
```

### 4. Parar a stack

**Opção A — via script:**

```bash
./parar_servidores.sh           # Apenas para os containers
./parar_servidores.sh --volumes # Para e apaga os dados
```

**Opção B — manual:**

```bash
docker compose down             # Apenas para os containers
docker compose down -v          # Para e apaga os dados
```

### 5. Acessar

| Serviço | URL |
|---------|-----|
| Rocket.Chat | http://rocket.chat |
| API Node.js | http://rocket.chat/api |

### 6. Primeira execucao em outra maquina (sem ajuste manual)

Se voce apenas clonou/baixou o projeto em um ambiente novo, basta executar:

```bash
./ativar_servidores.sh
```

O script ja cobre os pontos que mais quebram em primeira execucao:
- Cria `.env` automaticamente quando ele nao existe.
- Reaplica permissao `400` no `mongo-keyfile`.
- Garante `127.0.0.1 rocket.chat` no `/etc/hosts`.
- Sobe os servicos e aguarda todos ficarem `healthy`.

---

## 🔄 Comandos Úteis

```bash
# Ver status dos containers
docker compose ps

# Ver logs em tempo real
docker compose logs -f

# Parar tudo
docker compose down

# Rebuild da nodeapp após alterações
docker compose up -d --build nodeapp

# Reiniciar apenas um serviço
docker compose restart rocketchat
```

---

## 📁 Estrutura do Projeto

```
.
├── .env                    # Variáveis de ambiente (credenciais)
├── compose.yml             # Definição da stack Docker
├── mongo-keyfile           # Chave para autenticação do Replica Set
├── caddy/
│   └── Caddyfile           # Configuração do proxy reverso Caddy
├── nodeapp/
│   ├── Dockerfile          # Build da API Node.js
│   ├── package.json        # Dependências Node.js
│   └── server.js           # Código da API Express
├── ativar_servidores.sh    # Script auxiliar para subir a stack
└── parar_servidores.sh     # Script auxiliar para parar a stack
```

---

## ⚠️ Observações

- **Não comite o `.env`** em repositórios públicos — ele contém credenciais.
- O `mongo-keyfile` **deve ter permissão `400`** após qualquer cópia entre máquinas.
- A variável `OVERWRITE_SETTING_Site_Url` no `compose.yml` define a URL base do Rocket.Chat — altere se mudar o domínio.

---

> Projeto desenvolvido para a disciplina de **Sistemas Operacionais II** — JALA University, 2026.
