#!/bin/bash
# ==============================================================
#  uninstall.sh — Remove toda a instalação do VPN Watchdog
#  Uso: ./uninstall.sh <username>
#  Exemplo: ./uninstall.sh estrazulas
# ==============================================================

set -euo pipefail

if [ $# -lt 1 ]; then
        echo "Erro: informe seu nome de usuário do Linux."
        echo "Uso: $0 <username>"
        echo "Exemplo: $0 estrazulas"
        exit 1
fi

USERNAME="$1"

if ! id "$USERNAME" &>/dev/null; then
        echo "Erro: usuário '$USERNAME' não existe no sistema."
        exit 1
fi

HOME_DIR=$(eval echo "~$USERNAME")

echo "=========================================="
echo "  Removendo VPN Watchdog"
echo "  Usuário: $USERNAME"
echo "=========================================="

# ─── 1. Parar e desabilitar serviço ───
echo ""
echo "[1/4] Parando e desabilitando serviço systemd..."
if systemctl is-active vpn-watchdog &>/dev/null; then
        sudo systemctl stop vpn-watchdog
        echo "  ✔  Serviço parado"
else
        echo "  •  Serviço não está rodando"
fi

if systemctl is-enabled vpn-watchdog &>/dev/null; then
        sudo systemctl disable vpn-watchdog 2>/dev/null || true
        echo "  ✔  Serviço desabilitado"
else
        echo "  •  Serviço não estava habilitado"
fi

# ─── 2. Remover arquivo do serviço ───
echo ""
echo "[2/4] Removendo arquivo do serviço..."
if [ -f /etc/systemd/system/vpn-watchdog.service ]; then
        sudo rm /etc/systemd/system/vpn-watchdog.service
        sudo systemctl daemon-reload
        echo "  ✔  /etc/systemd/system/vpn-watchdog.service removido"
else
        echo "  •  Arquivo não encontrado"
fi

# ─── 3. Remover regra sudoers ───
echo ""
echo "[3/4] Removendo regra sudoers..."
SUDOERS_FILE="/etc/sudoers.d/openfortivpn-${USERNAME}"
if [ -f "$SUDOERS_FILE" ]; then
        sudo rm "$SUDOERS_FILE"
        echo "  ✔  ${SUDOERS_FILE} removido"
else
        echo "  •  Regra sudoers não encontrada"
fi

# ─── 4. Remover alias do bashrc ───
echo ""
echo "[4/4] Removendo alias 'vpn-status' do bashrc..."
BASHRC="${HOME_DIR}/.bashrc"
if grep -q "alias vpn-status" "$BASHRC" 2>/dev/null; then
        # Remove as linhas do alias (cabeçalho + alias)
        sed -i '/^# VPN Watchdog$/d' "$BASHRC"
        sed -i "/^alias vpn-status=/d" "$BASHRC"
        echo "  ✔  Alias removido de ${BASHRC}"
else
        echo "  •  Alias não encontrado no bashrc"
fi

# ─── 5. Matar processos órfãos ───
echo ""
echo "[extra] Matando processos openfortivpn remanescentes..."
FOUND=$(pgrep -x openfortivpn || true)
if [ -n "$FOUND" ]; then
        sudo kill "$FOUND" 2>/dev/null || true
        echo "  ✔  Processos encerrados"
else
        echo "  •  Nenhum processo rodando"
fi

# ─── Resumo ───
echo ""
echo "=========================================="
echo "  ✅ Desinstalação concluída!"
echo "=========================================="
echo ""
echo "  Os scripts em ~/git/scriptvpn/ foram"
echo "  mantidos. Para remover o diretório:"
echo "    rm -rf ~/git/scriptvpn"
echo ""
echo "  Para reinstalar:"
echo "    ./install.sh ${USERNAME}"
echo "    sudo systemctl enable vpn-watchdog --now"
echo ""
