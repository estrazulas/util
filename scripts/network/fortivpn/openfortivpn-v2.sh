#!/bin/bash

# ==============================================================
#  openfortivpn-v2.sh — VPN com auto-reconnect + systemd
#  Uso: ./openfortivpn-v2.sh start|stop|status|restart|watch
# ==============================================================

SUDO=""
[[ "$EUID" -ne 0 ]] && SUDO="sudo"
PAUSE_FILE="/tmp/.vpn-watchdog-pausado"

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

# === Watchdog (auto-reconnect com backoff) ===

function watch(){
        local FAILS=0
        local DELAY=10
        local NOTIFIED=0
        local WAS_CONNECTED=false

        echo "====================================="
        echo "  Watchdog VPN — $(date '+%d/%m/%Y %H:%M')"
        echo "  Verificando conexão continuamente"
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

                        stop
                        sleep 2
                        start
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
    start)   start ;;
    stop)    stop_manual ;;
    restart) restart ;;
    status)  status ;;
    watch)   watch ;;
    *)
        echo "Uso: $0 start|stop|status|restart|watch" >&2
        exit 1
        ;;
esac
