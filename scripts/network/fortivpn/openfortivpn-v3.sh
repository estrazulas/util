#!/bin/bash

# ==============================================================
#  openfortivpn-v3.sh — VPN com auto-reconnect + fix-network
#  Uso: ./openfortivpn-v3.sh start|stop|status|restart|watch|network-check|network-fix
#
#  Novidades do v3:
#    - Detecta queda da rede base (não só da VPN)
#    - Aciona fix-network automaticamente quando a rede cai
#    - Notifica desktop em cada etapa
#    - v2 mantido inalterado para compatibilidade com a equipe
# ==============================================================

SUDO=""
[[ "$EUID" -ne 0 ]] && SUDO="sudo"
PAUSE_FILE="/tmp/.vpn-watchdog-pausado"

# Caminho para o script de correção de rede (symlink em /usr/local/bin)
FIX_NETWORK_SCRIPT="${FIX_NETWORK_SCRIPT:-/usr/local/bin/fix-network}"

function get_pid(){
        pgrep -x openfortivpn 2>/dev/null | head -n 1
}

function notify(){
        local MSG="$1"
        local URG="${2:-normal}"
        notify-send -u "$URG" "VPN" "$MSG" 2>/dev/null || true
}

# === Start ===

function start(){
        rm -f "$PAUSE_FILE"
        local PID
        PID=$(get_pid)
        if [ -z "$PID" ]; then
                echo "Iniciando openfortivpn..."
                $SUDO openfortivpn &
                sleep 4
                notify "Conectando..."
        else
                echo "Já existe um openfortivpn em execução. PID ${PID}"
        fi
        status
}

# === Stop ===

function stop(){
        local PID
        PID=$(get_pid)
        if [ -n "$PID" ]; then
                echo "Parando processo ${PID}..."
                kill "$PID"
                sleep 2
                if ip link show ppp0 &>/dev/null; then
                        $SUDO pkill -f pppd 2>/dev/null
                fi
        else
                echo "Nenhum processo openfortivpn encontrado."
        fi
        status
}

# Stop manual — pausa o watchdog
function stop_manual(){
        touch "$PAUSE_FILE"
        echo "⏸  Watchdog pausado. Para reativar: $0 start"
        notify "VPN desconectada. Watchdog pausado."
        stop
}

# === Status ===

function status(){
        local PID
        PID=$(get_pid)

        if [ -f "$PAUSE_FILE" ]; then
                echo "VPN: PAUSADA (watchdog inativo)"
                echo "      Para reativar: $0 start"
                return 3
        fi

        if [ -z "$PID" ]; then
                echo "VPN: DESCONECTADA"
                return 1
        fi

        if ip link show ppp0 &>/dev/null && ip addr show ppp0 | grep -q "inet "; then
                local IP
                IP=$(ip addr show ppp0 | grep "inet " | awk '{print $2}')
                echo "VPN: CONECTADA (PID ${PID}) — ${IP}"
                return 0
        else
                echo "VPN: PROCESSO VIVO (PID ${PID}) MAS INTERFACE CAÍDA"
                return 2
        fi
}

# === Restart ===

function restart(){
        rm -f "$PAUSE_FILE"
        stop
        sleep 2
        start
}

# === Network check (diagnóstico rápido da rede base) ===

function get_gateway(){
        # Tenta detectar o gateway da interface física (ignora ppp0 da VPN)
        local GW
        GW=$(ip route 2>/dev/null | awk '/^default / && !/ppp0/ {print $3; exit}')
        # Fallback: se não achou sem ppp0, tenta qualquer default
        [ -z "$GW" ] && GW=$(ip route 2>/dev/null | awk '/^default / {print $3; exit}')
        echo "${GW:-8.8.8.8}"
}

function check_base_network(){
        local GW
        GW=$(get_gateway)
        echo "  Testando rede base (ping ${GW})..."
        if ping -c 2 -W 3 "$GW" &>/dev/null; then
                echo "  ✔  Rede base OK"
                return 0
        else
                echo "  ✗  Rede base INACESSÍVEL"
                return 1
        fi
}

# === Network fix (aciona fix-network com timeout generoso) ===

function fix_base_network(){
        local GW
        GW=$(get_gateway)

        echo "  🔧 Rede base caída — acionando fix-network..."
        notify "Rede base caída! Tentando corrigir com fix-network..." critical

        if [ ! -x "$FIX_NETWORK_SCRIPT" ]; then
                echo "  ✗  ERRO: ${FIX_NETWORK_SCRIPT} não encontrado ou não executável"
                notify "ERRO: fix-network não encontrado em ${FIX_NETWORK_SCRIPT}" critical
                return 1
        fi

        # timeout generoso: fix-network pode levar até 90s nos piores casos
        if ! $SUDO "$FIX_NETWORK_SCRIPT" 2>&1 | while IFS= read -r line; do
                echo "       ${line}"
        done; then
                # Timeout tratado via wait no caller
                true
        fi

        local RC=${PIPESTATUS[0]}
        # Aguarda interface estabilizar
        sleep 3

        echo -n "  Verificando resultado..."
        if ping -c 2 -W 3 "$GW" &>/dev/null; then
                echo " ✔  Rede restaurada!"
                notify "Rede restaurada! Reconectando VPN..." normal
                return 0
        else
                echo " ✗  fix-network não resolveu"
                notify "fix-network falhou. Rede continua inacessível." critical
                return 1
        fi
}

# === Watchdog (auto-reconnect com backoff + fix-network) ===

function watch(){
        local FAILS=0
        local DELAY=10
        local NOTIFIED=0
        local WAS_CONNECTED=false
        local LAST_NETWORK_FIX=0
        local FIX_COOLDOWN=180   # segundos entre chamadas ao fix-network

        echo "====================================="
        echo "  Watchdog VPN v3 — $(date '+%d/%m/%Y %H:%M')"
        echo "  Verificando conexão continuamente"
        echo "  fix-network: ${FIX_NETWORK_SCRIPT}"
        echo "====================================="

        # Garante que está rodando ao iniciar
        if [ -z "$(get_pid)" ] && [ ! -f "$PAUSE_FILE" ]; then
                echo "[$(date '+%H:%M:%S')] VPN não está rodando. Iniciando..."
                start
        fi

        while true; do
                # Verifica pause manual
                if [ -f "$PAUSE_FILE" ]; then
                        if [ "$WAS_CONNECTED" == true ]; then
                                notify "Desconectado manualmente. Watchdog pausado."
                                WAS_CONNECTED=false
                        fi
                        echo "[$(date '+%H:%M:%S')] ⏸  Watchdog pausado (stop manual). Aguardando start..."
                        sleep 30
                        continue
                fi

                status > /dev/null
                local RC=$?
                local NEED_RECONNECT=false

                # Detecta transição: conectado → desconectado
                if [ "$RC" -ne 0 ] && [ "$WAS_CONNECTED" == true ]; then
                        WAS_CONNECTED=false
                        if [ -z "$(get_pid)" ]; then
                                notify "Conexão perdida!"
                        fi
                fi

                # Detecta transição: desconectado → conectado
                if [ "$RC" -eq 0 ] && [ "$WAS_CONNECTED" == false ]; then
                        WAS_CONNECTED=true
                        FAILS=0
                        LAST_NETWORK_FIX=0
                        notify "Conectado!"
                        echo "[$(date '+%H:%M:%S')] ✅  VPN conectada"
                fi

                if [ "$RC" -eq 2 ]; then
                        echo "[$(date '+%H:%M:%S')] ⚠  Processo vivo mas interface caída. Reiniciando..."
                        NEED_RECONNECT=true
                elif [ "$RC" -eq 1 ]; then
                        echo "[$(date '+%H:%M:%S')] ⚠  VPN desconectada. Iniciando..."
                        NEED_RECONNECT=true
                fi

                if [ "$NEED_RECONNECT" == true ]; then
                        FAILS=$((FAILS + 1))
                        NOTIFIED=0

                        if   [ "$FAILS" -le 5 ];   then DELAY=10
                        elif [ "$FAILS" -le 15 ];  then DELAY=60
                        else                            DELAY=300
                        fi

                        # ── v3: verifica rede base antes de tentar VPN ──
                        echo "[$(date '+%H:%M:%S')] Verificando rede base antes de reconectar VPN..."
                        if check_base_network; then
                                # Rede OK → reconecta VPN normalmente
                                stop
                                sleep 2
                                start
                        else
                                # Rede caída → tenta fix-network (com cooldown)
                                local NOW
                                NOW=$(date +%s)
                                local ELAPSED=$((NOW - LAST_NETWORK_FIX))

                                if [ "$ELAPSED" -ge "$FIX_COOLDOWN" ]; then
                                        LAST_NETWORK_FIX="$NOW"
                                        fix_base_network
                                        if [ $? -eq 0 ]; then
                                                # Rede voltou → reconecta VPN
                                                stop
                                                sleep 2
                                                start
                                        else
                                                echo "[$(date '+%H:%M:%S')] ❌  Rede base continua inacessível. VPN não será tentada."
                                                echo "[$(date '+%H:%M:%S')]     Aguardando próximo ciclo (cooldown fix: ${FIX_COOLDOWN}s)..."
                                        fi
                                else
                                        echo "[$(date '+%H:%M:%S')] ⏳  fix-network em cooldown (próxima tentativa em $((FIX_COOLDOWN - ELAPSED))s). Aguardando..."
                                fi
                        fi
                fi

                # Notificação se falhando por muito tempo
                if [ "$FAILS" -gt 0 ] && [ "$NOTIFIED" -eq 0 ] && [ "$FAILS" -ge 15 ] && [ "$((FAILS % 6))" -eq 0 ]; then
                        NOTIFIED=1
                        notify "⚠  ${FAILS} tentativas sem sucesso. Verifique suas credenciais." critical
                fi

                sleep "$DELAY"
        done
}

# === Main ===

case "$1" in
    start)         start ;;
    stop)          stop_manual ;;
    restart)       restart ;;
    status)        status ;;
    watch)         watch ;;
    network-check) check_base_network ;;
    network-fix)   fix_base_network ;;
    *)
        echo "Uso: $0 start|stop|status|restart|watch|network-check|network-fix" >&2
        exit 1
        ;;
esac
