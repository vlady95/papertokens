#!/bin/sh
# Deploy del plugin al Kindle. Un comando:
#
#   ./deploy.sh              → USB mass storage (el Kindle montado en /Volumes)
#   ./deploy.sh 192.168.15.244 → USBNetwork por SSH
#
# VERIFICADO en el device (KOReader v2026.07.1): el directorio de plugins es
# koreader/plugins/ en la raíz de la unidad, que en USBNetwork corresponde a
# /mnt/us/koreader/plugins.
#
# Nota: en modo USB mass storage KOReader NO está corriendo. Tras copiar hay
# que expulsar la unidad y abrir KOReader en el Kindle.
set -e

cd "$(dirname "$0")"
SRC="papertokens.koplugin"
EXCLUDES="--exclude assets/src --exclude .DS_Store"

if [ -n "$1" ]; then
    IP="$1"
    echo "Deploy por SSH a $IP…"
    rsync -av --delete $EXCLUDES \
        "$SRC/" "root@$IP:/mnt/us/koreader/plugins/$SRC/"
    ssh "root@$IP" "pkill -f koreader.sh || pkill luajit || true"
    echo "Listo. Relanza KOReader en el Kindle si no se reinició solo."
else
    VOL="${KINDLE_VOLUME:-/Volumes/Kindle}"
    if [ ! -d "$VOL/koreader" ]; then
        echo "No encuentro KOReader en $VOL." >&2
        echo "Conecta el Kindle por USB (o pasa la IP para USBNetwork)." >&2
        exit 1
    fi
    DEST="$VOL/koreader/plugins/$SRC"
    DECKS="$VOL/papertokens"
    echo "Deploy por USB a $DEST…"
    mkdir -p "$DEST"
    rsync -av --delete $EXCLUDES "$SRC/" "$DEST/"

    # Carpeta de mazos, hermana de koreader/ para que se vea al montar por USB.
    # Los .txt los genera la webapp; aquí solo se crea la carpeta, y si está
    # vacía se deja el mazo de ejemplo para poder probar de una vez.
    mkdir -p "$DECKS"
    if [ -z "$(ls -A "$DECKS"/*.txt 2>/dev/null)" ]; then
        cp "$SRC/tests/fixtures/jund-wildfire.txt" "$DECKS/"
        echo "Carpeta de mazos vacía: copiado el mazo de ejemplo."
    fi

    # FAT32 no guarda el bit de ejecución; nada del plugin lo necesita.
    sync
    echo ""
    echo "Copiado. Ahora en el Kindle:"
    echo "  1. Expulsa la unidad:  diskutil eject $VOL"
    echo "  2. Abre KOReader"
    echo "  3. Menú ☰ → Herramientas (more tools) → PaperTokens → Mazos"
    echo ""
    echo "Los .txt de mazo van en $DECKS (se generan en la webapp)."
fi
