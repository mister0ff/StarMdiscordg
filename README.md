# Bedrock Host — servidor Minecraft Bedrock 24/7 no seu Android

Seu celular vira o host. Tudo roda no aparelho: **Termux** + **Ubuntu (proot)** + **box64** (o servidor oficial é x86_64, o celular é ARM) + um **painel web** + um **APK** de controle.

```
Android ─ Termux ─ proot Ubuntu ─ box64 ─ bedrock_server
                        └─ panel.py (painel, logs, backups, watchdog) ── http://127.0.0.1:8080
APK Bedrock Host = WebView do painel + botões Ligar/Parar (via Termux) + monitor 24/7
```

> Por que não uma VM de verdade (QEMU)? Sem root, QEMU no celular é lentíssimo. proot+box64 é um contêiner com emulação só do binário x86: muito mais rápido.

## O que o painel faz
Ligar / desligar / reiniciar · console ao vivo · logs com rotação (5 MB × 5, baixáveis) · gerenciador de arquivos (editar, enviar, baixar, pastas em .zip) · backups **a quente** (`save hold/query/resume`, sem corromper o mundo) com restauração · instalar addons `.mcaddon/.mcpack` e ativar no mundo · editor de `server.properties` com perfis de desempenho · **watchdog** (religa se cair, com espera crescente) · backup automático e reinício diário · atualizar o servidor mantendo o mundo · tunnel opcional playit.gg · uso de CPU/RAM/disco/bateria/temperatura · login com senha.

## Instalação (uma vez)
1. Instale o **Termux pelo F-Droid ou GitHub** (a versão da Play Store é antiga e quebra). Instale também **Termux:Boot** (mesma fonte) se quiser iniciar junto com o aparelho.
2. Extraia este zip no celular e, no Termux:
   ```bash
   termux-setup-storage
   cd /sdcard/Download/bedrock-host     # ajuste o caminho
   bash install.sh
   ```
   Ele instala tudo, pede uma senha para o painel e baixa o servidor. **Compilar o box64 leva 10–40 min** (só na primeira vez; deixe carregando e a tela ligada).
3. Ligue: `bedrock start` → abra `http://127.0.0.1:8080` no navegador (ou no APK).

Comandos úteis: `bedrock status | stop | restart | logs | doctor | password | install-bds`.
Seus dados (mundo, backups, logs) ficam em `~/bedrock-host/data`.

## APK
O APK não precisa de Android Studio: o GitHub compila para você.
1. Crie um repositório no GitHub e suba o **conteúdo** desta pasta (inclusive `.github/`). No Termux: `pkg install git`, `git init`, `git add .`, `git commit -m inicio`, `git remote add origin URL`, `git push` (use um token como senha).
2. Aba **Actions** → "Build APK" roda sozinho (ou "Run workflow").
3. Baixe `app-debug.apk` em **Releases → apk-latest** (ou em Actions → Artifacts) e instale (permita "fontes desconhecidas").
4. Instale o Termux **antes** do APK; no app, conceda "Executar comandos no Termux" e as notificações.

Sem o APK tudo funciona igual: o painel abre em qualquer navegador.

## 24/7 no Android (leia!)
- **Bateria:** Termux e Bedrock Host em *Sem restrições* (o menu ⋮ do app abre as telas).
- **Android 12+ mata processos filhos** (“phantom process killer”), o que derruba o servidor sozinho. Corrija: Opções do desenvolvedor → *Desativar restrições de processos filhos* (Android 14+), ou via adb (pode ser Depuração sem fio no próprio celular):
  `adb shell "device_config put activity_manager max_phantom_processes 2147483647"`
  `adb shell settings put global settings_enable_monitor_phantom_procs false`
- Deixe no **carregador**, ventilado e sem capa grossa; o calor reduz o desempenho. Se for ficar sempre ligado, retire a bateria da conta (ou limite a carga a 80% se o aparelho permitir).
- Termux:Boot + o monitor do APK religam o host depois de reiniciar o aparelho (após desbloquear a tela uma vez).

## Jogar de fora da sua casa
Dados móveis/CGNAT não recebem conexões. No painel: **Ajustes → Túnel (playit.gg)** → instalar → ligar → abra o link de vínculo mostrado no Painel. Na mesma Wi-Fi, use o IP mostrado no painel e a porta 19132 (UDP).

## Desempenho
- Painel → Ajustes → *Desempenho*: perfis Leve / Equilibrado / Alto (view-distance, tick-distance, threads, compressão snappy).
- Perfil do **box64**: Equilibrado é o padrão; “Rápido” é mais veloz, mas pode ficar instável.
- Seja realista: é um binário x86 **emulado** em ARM. Espere um servidor pequeno (poucos jogadores, view-distance baixa). Quanto mais forte o chip (Snapdragon 8 / Dimensity 9000+) e mais RAM (6 GB+), melhor.

## Problemas comuns
- `bedrock doctor` mostra o que falta.
- *box64 não encontrado*: `bedrock setup-ubuntu`.
- Servidor “Iniciando…” por muito tempo: normal 1–3 min no celular; veja Console.
- Erro de biblioteca ao iniciar: `bedrock shell` e instale a lib ARM correspondente com `apt install`.
- “Caiu” em loop: veja o log; o watchdog desiste após 5 quedas em 10 min (ajustável).
- Esqueceu a senha: `bedrock set-password NOVA`.

## Avisos
Isto não é afiliado à Mojang/Microsoft. O servidor é baixado de minecraft.net e você aceita o EULA/Termos do Minecraft. O APK é de debug (assinatura de debug) para uso pessoal.
