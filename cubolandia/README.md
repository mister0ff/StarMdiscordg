# Cubolândia

Jogo estilo Minecraft feito em **Godot 4.3 (GDScript)**, para **PC (Windows/Linux) e Android** com o mesmo código.

## O que tem
- **Mundo procedural infinito** (chunks, relevo, mar, areia/deserto, neve, cavernas, árvores, minérios: carvão, ferro, diamante)
- **Sobrevivência**: vida, fome, afogamento, dano de queda, tempo de quebra por bloco/ferramenta, drops, morte (solta itens)
- **Criativo**: itens infinitos, voo (toque duplo em pular), quebra instantânea
- **Inventário** com 36 espaços + hotbar, **crafting** (mesa de trabalho, fornalha), ferramentas de 4 materiais com durabilidade
- **Dia e noite** (sol/lua, céu, escuridão), mobs passivos (porco, vaca) e hostis (zumbi, esqueleto com flechas, creeper que explode)
- **Combate** com knockback, golpe crítico, **PvP** entre jogadores
- **Multijogador** (host/entrar por IP e porta, ENet), **chat** e comandos (`/ajuda`)
- **Salvamento** automático (mundo + inventário)
- **Controles de PC** (teclas reconfiguráveis) e **controles de toque** (botões que você arrasta e redimensiona)

## Controles padrão (PC)
WASD andar · Espaço pular · Shift agachar · Ctrl correr · Mouse esq. quebrar/atacar · Mouse dir. colocar/usar/comer · E inventário · T chat · F voar (criativo) · 1-9 ou roda do mouse hotbar · Q largar · Esc pausa.
Tudo pode ser trocado em **Configurações → Teclas**.

## Celular
Em **Configurações → Toque → Ajustar posição e tamanho dos botões** você arrasta cada botão, escolhe um e usa `+`/`-` para o tamanho.
Modo de controle: Automático / Toque / Teclado e mouse (em Configurações → Geral).

## Comandos do chat
`/gm c|s` · `/time dia|noite|0-1` (host) · `/give <id> [qtd]` · `/itens` · `/tp x y z` · `/spawn` · `/heal` · `/kill` · `/seed` · `/mob pig|cow|zombie|skeleton|creeper` (host)

## Rodar no editor
1. Instale o [Godot 4.3](https://godotengine.org/download) (versão padrão, não .NET).
2. Abra a pasta do projeto (`project.godot`) e aperte **F5**.

## Gerar APK / executáveis pelo GitHub (automático)
1. Suba esta pasta para um repositório no GitHub (branch `main`).
2. Vá na aba **Actions** → **Build Cubolândia** (roda sozinho a cada push, ou clique em *Run workflow*).
3. Ao terminar, baixe em **Artifacts**: `Cubolandia-android-apk`, `Cubolandia-windows`, `Cubolandia-linux`.
O APK sai assinado com chave de *debug* (instala direto no celular; para a Play Store, crie sua própria keystore).

## Gerar APK manualmente
Godot → *Editor → Gerenciar templates de exportação* (instalar) → *Editor Settings → Export → Android* (SDK + JDK 17) → *Projeto → Exportar → Android → Exportar projeto*.

## Teste automático
`godot --headless --path . res://tests/smoke.tscn` (gera mundo, quebra/coloca blocos, crafting, mobs, KB, explosão, salvar/carregar).

## Multijogador
Quem hospeda: *Multijogador → Hospedar* (porta padrão 25565 UDP; libere no roteador/firewall ou use Radmin/ZeroTier/Tailscale). Os outros: *Entrar* com o IP do host.
