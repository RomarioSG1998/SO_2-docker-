const express = require("express");
const app = express();

app.get("/", (req, res) => {
  res.send(`
    <h1>Capstone Sistemas Operacionais 2</h1>
    <p>Projeto rodando com sucesso utilizando as seguintes tecnologias:</p>
    <ul>
      <li><strong>Rocket.chat:</strong> Comunicação e colaboração</li>
      <li><strong>Node.js:</strong> API de backend (esta aplicação)</li>
      <li><strong>MongoDB:</strong> Banco de dados NoSQL com Replica Set</li>
      <li><strong>Caddy:</strong> Servidor Web e Proxy Reverso com HTTPS</li>
    </ul>
    <p>🚀 Status: Operacional</p>
  `);
});

app.listen(4000, () => {
  console.log("Servidor Node rodando na porta 4000");
});