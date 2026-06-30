#!/bin/bash
# ==============================================================
#  install.sh — Instalação completa do VPN Watchdog
#  Uso: ./install.sh <username>
#  Exemplo: ./install.sh estrazulas
# ==============================================================

set -euo pipefail

if [ $# -lt 1 ]; then
        echo "Erro: informe seu nome de usuário do Linux."
        echo "Uso: $0 <username>"
        echo "Exemplo: $0 estrazulas"
        exit 1
fi

USERNAME="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WATCHDOG_SCRIPT="${SCRIPT_DIR}/openfortivpn-v2.sh"

# Valida se o usuário existe
if ! id "$USERNAME" &>/dev/null; then
        echo "Erro: usuário '$USERNAME' não existe no sistema."
        exit 1
fi

HOME_DIR=$(eval echo "~$USERNAME")

echo "=========================================="
echo "  Instalação VPN Watchdog"
echo "  Usuário:     $USERNAME"
echo "  Diretório:   $SCRIPT_DIR"
echo "=========================================="

# ─── 1. Verificar script ───
if [ ! -f "$WATCHDOG_SCRIPT" ]; then
        echo "Erro: $WATCHDOG_SCRIPT não encontrado."
        echo "Certifique-se de que openfortivpn-v2.sh está no mesmo diretório."
        exit 1
fi

chmod +x "$WATCHDOG_SCRIPT"

# ─── 2. Permissão sudo sem senha ───
echo ""
echo "[1/4] Criando regra sudoers (sudo sem senha)..."
SUDOERS_FILE="/etc/sudoers.d/openfortivpn-${USERNAME}"

sudo tee "$SUDOERS_FILE" > /dev/null << EOF
# Permitir que ${USERNAME} execute openfortivpn e kill sem senha
${USERNAME} ALL=(ALL) NOPASSWD: /usr/bin/openfortivpn
${USERNAME} ALL=(ALL) NOPASSWD: /bin/kill
${USERNAME} ALL=(ALL) NOPASSWD: /usr/bin/pkill
EOF

sudo chmod 440 "$SUDOERS_FILE"
echo "  ✔  ${SUDOERS_FILE} criado"

# ─── 3. Serviço systemd ───
echo ""
echo "[2/4] Criando serviço systemd..."
SERVICE_FILE="/etc/systemd/system/vpn-watchdog.service"

sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=VPN Watchdog — openfortivpn com auto-reconnect
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=${WATCHDOG_SCRIPT} watch
Restart=always
RestartSec=10
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable vpn-watchdog
sudo systemctl start vpn-watchdog
echo "  ✔  ${SERVICE_FILE} criado e ativado (enable + start)"

# ─── 4. Alias no bashrc ───
echo ""
echo "[3/4] Adicionando alias 'vpn-status' no bashrc..."
BASHRC="${HOME_DIR}/.bashrc"

if grep -q "alias vpn-status" "$BASHRC" 2>/dev/null; then
        echo "  • alias vpn-status já existe, pulando."
else
        echo "" >> "$BASHRC"
        echo "# VPN Watchdog" >> "$BASHRC"
        echo "alias vpn-status='${WATCHDOG_SCRIPT} status'" >> "$BASHRC"
        echo "  ✔  alias adicionado em ${BASHRC}"
fi

# ─── 5. Git (se for repo) ───
echo ""
echo "[4/4] Git..."
if [ -d "${SCRIPT_DIR}/.git" ]; then
        echo "  • Git já inicializado."
else
        echo "  • Diretório não é um repositório git."
        echo "  • Para iniciar:"
        echo "      cd ${SCRIPT_DIR}"
        echo "      git init"
        echo "      git add ."
        echo "      git commit -m \"feat: vpn watchdog com auto-reconnect\""
fi

# ─── Resumo ───
echo ""
echo "=========================================="
echo "  ✅ Instalação concluída!"
echo "=========================================="
echo ""
echo "  Comandos disponíveis:"
echo ""
echo "  Manual:"
echo "    ${WATCHDOG_SCRIPT} start        # Iniciar VPN"
echo "    ${WATCHDOG_SCRIPT} stop         # Parar VPN"
echo "    ${WATCHDOG_SCRIPT} status       # Ver status"
echo "    vpn-status                      # Atalho (mesmo que acima)"
echo ""
echo "  Serviço automático:"
echo "    sudo systemctl start vpn-watchdog       # Iniciar agora"
echo "    sudo systemctl enable vpn-watchdog      # Iniciar com o PC"
echo "    sudo systemctl status vpn-watchdog      # Ver status do serviço"
echo "    sudo journalctl -u vpn-watchdog -f      # Ver logs ao vivo"
echo ""
echo "  Para testar agora:"
echo "    source ~/.bashrc"
echo "    ${WATCHDOG_SCRIPT} start"
echo "    ${WATCHDOG_SCRIPT} status"
echo ""
