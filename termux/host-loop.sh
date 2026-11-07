#!/data/data/com.termux/files/usr/bin/bash
# Supervisor 24/7 (roda no Termux): mantem o painel (e portanto o servidor) vivo.
# Se o painel cair, religa com espera crescente. Para de vez quando existe data/stop.flag.

HOST_DIR="${BEDROCK_HOST_DIR:-$HOME/bedrock-host}"
DATA="$HOST_DIR/data"
mkdir -p "$DATA/logs" "$DATA/server"

echo $$ > "$DATA/supervisor.pid"
rm -f "$DATA/stop.flag"
trap 'rm -f "$DATA/supervisor.pid"' EXIT

# impede o Android de suspender o Termux (precisa da notificacao do Termux ativa)
termux-wake-lock 2>/dev/null || true

# o Ubuntu (proot) usa UTC por padrao; repassa o fuso do aparelho para agenda/reinicio diario
TZ_NAME="$(getprop persist.sys.timezone 2>/dev/null || true)"
[ -n "$TZ_NAME" ] || TZ_NAME="UTC"

fails=0
while [ ! -f "$DATA/stop.flag" ]; do
  started=$(date +%s)
  echo "$(date '+%F %T') iniciando painel..."
  proot-distro login ubuntu --shared-tmp \
    --bind "$DATA:/srv/bedrock" \
    --bind "$HOST_DIR/panel:/opt/panel" \
    -- env BEDROCK_DATA=/srv/bedrock TZ="$TZ_NAME" python3 /opt/panel/panel.py
  rc=$?
  [ -f "$DATA/stop.flag" ] && break
  up=$(( $(date +%s) - started ))
  if [ "$up" -lt 30 ]; then fails=$((fails + 1)); else fails=0; fi
  wait_s=$(( fails > 5 ? 60 : 5 * fails + 5 ))
  echo "$(date '+%F %T') painel saiu (codigo $rc apos ${up}s). Reiniciando em ${wait_s}s"
  sleep "$wait_s"
done
echo "$(date '+%F %T') supervisor encerrado."
