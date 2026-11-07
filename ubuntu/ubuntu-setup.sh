#!/usr/bin/env bash
# Roda DENTRO do Ubuntu (proot-distro). Instala Python e o box64 (emulador x86_64 -> ARM64),
# necessario porque o Bedrock Dedicated Server oficial so existe para x86_64.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "==> Atualizando pacotes do Ubuntu"
apt-get update
apt-get install -y --no-install-recommends python3 curl unzip ca-certificates procps tzdata libcurl4 libssl3 || \
  apt-get install -y --no-install-recommends python3 curl unzip ca-certificates procps tzdata

ARCH="$(uname -m)"
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
  echo "==> Arquitetura $ARCH: nao precisa de box64 (o servidor roda nativo)."
  exit 0
fi

if command -v box64 >/dev/null 2>&1; then
  echo "==> box64 ja instalado: $(box64 --version 2>&1 | head -1)"
  exit 0
fi

echo "==> Tentando instalar box64 pelo apt"
if apt-cache show box64 >/dev/null 2>&1 && apt-get install -y box64; then
  command -v box64 >/dev/null 2>&1 && { echo "==> box64 (apt): $(box64 --version 2>&1 | head -1)"; exit 0; }
fi

echo "==> Compilando box64 do codigo-fonte (demora 10-40 min no celular; deixe a tela ligada e carregando)"
apt-get install -y --no-install-recommends git cmake build-essential python3
SRC=/tmp/box64-src
rm -rf "$SRC"
git clone --depth 1 https://github.com/ptitSeb/box64 "$SRC"
mkdir -p "$SRC/build"
cd "$SRC/build"
# -DARM64=1 e a opcao generica para ARM64 (Android/proot); a dynarec e o que da desempenho.
cmake .. -DARM64=1 -DARM_DYNAREC=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo ${BOX64_CMAKE_FLAGS:-}
JOBS="${JOBS:-$(nproc)}"
[ "$JOBS" -gt 4 ] && JOBS=4   # evita estourar a RAM do celular
make -j"$JOBS"
make install
cd /
rm -rf "$SRC"

echo "==> box64 instalado: $(box64 --version 2>&1 | head -1)"
