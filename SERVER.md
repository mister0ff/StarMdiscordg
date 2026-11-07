# Servidor público 24h

O jogo tem modo servidor dedicado (sem tela, sem jogador local). O mundo é salvo sozinho a cada 60 s.

## Rodar
- **Docker (recomendado):** `docker compose up -d --build` → porta UDP 25565.
- **Sem Docker:** `godot --headless --path . -- --server --port 25565` (Godot 4.3). Opções: `--ws` (WebSocket), `--creative`, `--seed N`.
- Variáveis de ambiente: `CUBO_SERVER=1 CUBO_PORT CUBO_WS CUBO_CREATIVE CUBO_SEED`.

## Onde hospedar para ficar 24h
Precisa de uma máquina sempre ligada com IP público: uma VPS (qualquer uma que aceite UDP), um PC/Raspberry em casa com a porta liberada no roteador, ou um plano gratuito de nuvem que ofereça VM (confira os planos atuais). Se a hospedagem só aceitar HTTP/TCP, rode com `CUBO_WS=1` e use `wss://seu-dominio` (o proxy da hospedagem faz o TLS).

## Publicar na lista do jogo
Edite `scripts/server_list.gd` (campo `SERVERS`) com `{"name": "...", "addr": "ip:25565"}` e recompile, ou aponte `REMOTE_URL` para um JSON na internet para atualizar sem recompilar. Jogadores também podem adicionar servidores em Multijogador → Servidores públicos.

## Regras do servidor público
Comandos de cheat (/gm, /give, /time, /tp...) ficam desativados; o servidor valida alcance de blocos e limita o chat. Limite padrão: 16 jogadores.
Limitação conhecida: baús usam o jogador como autoridade do cursor (possível duplicar itens com cliente modificado).
