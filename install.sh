#!/data/data/com.termux/files/usr/bin/bash
# Instalador do Bedrock Host. Rode DENTRO DO TERMUX:   bash install.sh
# Idempotente: pode rodar de novo para reparar/atualizar sem perder o mundo (fica em ~/bedrock-host/data).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_DIR="$HOME/bedrock-host"
DATA="$HOST_DIR/data"

say() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERRO: %s\033[0m\n' "$*"; exit 1; }

[ -n "${PREFIX:-}" ] && [[ "$PREFIX" == *com.termux* ]] || die "rode isto dentro do app Termux (baixe-o do F-Droid ou do GitHub, nao da Play Store)."
ARCH="$(uname -m)"
[ "$ARCH" = "aarch64" ] || warn "arquitetura $ARCH: o esperado e aarch64 (celular 64 bits). Vou continuar mesmo assim."

say "1/7  Pacotes do Termux"
pkg update -y
pkg install -y proot-distro curl termux-tools procps

say "2/7  Copiando arquivos para $HOST_DIR"
mkdir -p "$DATA"
if [ "$SRC" != "$HOST_DIR" ]; then
  mkdir -p "$HOST_DIR"
  cp -a "$SRC/panel" "$SRC/termux" "$SRC/ubuntu" "$HOST_DIR/"
  [ -f "$SRC/README.md" ] && cp -a "$SRC/README.md" "$HOST_DIR/"
fi
chmod +x "$HOST_DIR/termux/bedrock" "$HOST_DIR/termux/host-loop.sh" "$HOST_DIR/ubuntu/ubuntu-setup.sh" || true
mkdir -p "$PREFIX/bin"
ln -sf "$HOST_DIR/termux/bedrock" "$PREFIX/bin/bedrock"

say "3/7  Ubuntu (proot-distro) - a 'maquina virtual' leve"
if [ -d "$PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu" ]; then
  echo "Ubuntu ja instalado."
else
  proot-distro install ubuntu
fi

say "4/7  Dependencias e box64 dentro do Ubuntu"
proot-distro login ubuntu --shared-tmp --bind "$HOST_DIR/ubuntu:/opt/setup" -- bash /opt/setup/ubuntu-setup.sh

in_ubuntu() {
  proot-distro login ubuntu --shared-tmp --bind "$DATA:/srv/bedrock" --bind "$HOST_DIR/panel:/opt/panel" \
    -- env BEDROCK_DATA=/srv/bedrock "$@"
}

say "5/7  Senha do painel"
PW="${PANEL_PASSWORD:-}"
if [ -z "$PW" ] && [ -t 0 ]; then
  read -r -s -p "Defina uma senha (6+ caracteres) ou Enter para gerar uma aleatoria: " PW || true
  echo
fi
if [ -n "$PW" ]; then
  in_ubuntu python3 /opt/panel/panel.py --set-password "$PW"
else
  echo "A senha sera gerada na primeira execucao (veja com: bedrock password)."
fi

say "6/7  Baixando o Minecraft Bedrock Dedicated Server"
if [ -x "$DATA/server/bedrock_server" ]; then
  echo "Servidor ja instalado - pulando (para atualizar: bedrock install-bds)."
elif ! in_ubuntu python3 /opt/panel/panel.py --install; then
  warn "Nao consegui baixar agora. Depois rode: bedrock install-bds   (ou use o painel > Ajustes > Instalar)."
fi

say "7/7  Ajustes do Termux (controle pelo app, inicio no boot)"
mkdir -p "$HOME/.termux/boot"
touch "$HOME/.termux/termux.properties"
grep -q '^allow-external-apps' "$HOME/.termux/termux.properties" \
  && sed -i 's/^allow-external-apps.*/allow-external-apps = true/' "$HOME/.termux/termux.properties" \
  || echo 'allow-external-apps = true' >> "$HOME/.termux/termux.properties"
termux-reload-settings 2>/dev/null || true
cat > "$HOME/.termux/boot/bedrock-host.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Executado pelo app Termux:Boot quando o aparelho liga.
termux-wake-lock
sleep 20
bedrock start
EOF
chmod +x "$HOME/.termux/boot/bedrock-host.sh"

say "Pronto!"
cat <<EOF

  Ligar o host:     bedrock start
  Painel:           http://127.0.0.1:8080   (abra no navegador ou no app Bedrock Host)
  Senha inicial:    $( [ -f "$DATA/initial-password.txt" ] && cat "$DATA/initial-password.txt" || echo "a que voce definiu")
  Diagnostico:      bedrock doctor
  Parar:            bedrock stop

  Importante para ficar 24/7: leia a secao "24/7 no Android" do README.md
  (bateria sem restricoes, processos filhos, carregador, Termux:Boot).

EOF
