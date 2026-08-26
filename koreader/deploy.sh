#!/bin/sh
# Deploy del plugin al Kindle por SSH (USBNetwork), un comando:
#   ./deploy.sh [ip]
# IP por argumento, variable KINDLE_IP, o la clásica de USBNetwork.
#
# VERIFICAR contra la instalación real (ver README): la ruta del directorio
# de plugins y el mecanismo de reinicio de KOReader de ESTA instalación.
set -e

IP="${1:-${KINDLE_IP:-192.168.15.244}}"
PLUGIN_DIR="/mnt/us/koreader/plugins" # ← pendiente de verificar en el device

cd "$(dirname "$0")"

rsync -av --delete --exclude 'assets/src' --exclude 'tests' \
  papertokens.koplugin/ "root@$IP:$PLUGIN_DIR/papertokens.koplugin/"

# Reinicio de KOReader. En Kindle suele bastar matar el proceso y relanzar
# desde KUAL; si esta instalación tiene un mecanismo propio, ajustarlo aquí.
ssh "root@$IP" "pkill -f koreader.sh || pkill luajit || true"

echo "Listo. Relanza KOReader en el Kindle si no se reinició solo."
