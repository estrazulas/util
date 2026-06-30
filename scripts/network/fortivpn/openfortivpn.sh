#!/bin/bash

function start(){
	PID=$(pgrep -f "sudo -S openfortivpn")
	if [ -z ${PID} ];
	then
		echo "sudo password:"
		read -s SUDOPASS
		echo $SUDOPASS |  sudo -S openfortivpn &
	else 
		echo "Já existe um openfortivpn em execução. pid ${PID}"
	fi
	status
}

function stop(){
	PID=$(pgrep -f "sudo -S openfortivpn"  | head -n 1)
	if [ ! -z ${PID} ];
	then
		kill $PID
	fi
	sleep 2
	status 
}

function status(){
	PID=$(pgrep -f "sudo -S openfortivpn"  | head -n 1)
        if [ -z ${PID} ];
        then
			echo "VPN desconectada!" 
        else
			echo "VPN conectada (pid ${PID}) !"
        fi
}

case "$1" in 
    start)   start ;;
    stop)    stop ;;
    status)  status ;;
    *) echo "Uso: $0 start|stop|status" >&2
       exit 1
       ;;
esac

