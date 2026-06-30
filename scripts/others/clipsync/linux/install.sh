#!/bin/bash
# ============================================================
# clipsync installer - roda em qualquer VM Linux
# ============================================================
# Uso:
#   curl -sSL https://seu-git/clipsync/install.sh | bash
#   ou
#   ./install.sh <ip-remoto> [porta]
#
# Exemplos:
#   ./install.sh 192.168.56.1        # Windows host (VirtualBox)
#   ./install.sh 192.168.56.1 8888   # porta customizada
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo "  clipsync - Clipboard Sync Installer"
echo "============================================"
echo ""

# ── Argumentos ──
REMOTE="${1:-}"
PORT="${2:-9999}"

if [ -z "$REMOTE" ]; then
    read -rp "IP da outra maquina (ex: 192.168.56.1): " REMOTE
fi

echo "Remote: $REMOTE:$PORT"

# ── Detecta display ──
if [ -n "$WAYLAND_DISPLAY" ] || command -v wl-copy &>/dev/null; then
    echo "Display: Wayland detectado"
    PKG="wl-clipboard"
elif [ -n "$DISPLAY" ] || command -v xclip &>/dev/null; then
    echo "Display: X11 detectado"
    PKG="xclip"
else
    echo "ERRO: nao foi possivel detectar Wayland nem X11"
    exit 1
fi

# ── Instala dependencia ──
if command -v wl-copy &>/dev/null || command -v xclip &>/dev/null; then
    echo "Dependencia de clipboard ja instalada ($PKG)"
else
    echo "Instalando $PKG..."
    if command -v apt &>/dev/null; then
        sudo apt update -qq && sudo apt install -y "$PKG"
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y "$PKG"
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm "$PKG"
    else
        echo "AVISO: nao foi possivel instalar $PKG automaticamente"
        echo "Instale manualmente e rode o script de novo"
        exit 1
    fi
fi

# ── Instala script ──
echo "Instalando clipsync em /usr/local/bin..."
sudo cp "$SCRIPT_DIR/clipsync" /usr/local/bin/clipsync
sudo chmod +x /usr/local/bin/clipsync

# ── Cria systemd user service ──
SERVICE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$SERVICE_DIR"

echo "Criando servico systemd..."
cat > "$SERVICE_DIR/clipsync.service" << SERVICE_EOF
[Unit]
Description=Clipboard sync to $REMOTE:$PORT
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/clipsync $REMOTE $PORT
Restart=always
RestartSec=5
Environment=DISPLAY=${DISPLAY:-:0}

[Install]
WantedBy=default.target
SERVICE_EOF

# ── Ativa servico ──
systemctl --user daemon-reload
systemctl --user enable clipsync.service
systemctl --user start clipsync.service

echo ""
echo "============================================"
echo "  Instalado com sucesso!"
echo "============================================"
echo ""
echo "  Servico: systemctl --user status clipsync"
echo "  Logs:    journalctl --user -u clipsync -f"
echo ""
systemctl --user status clipsync.service --no-pager --lines=0 2>/dev/null || true
