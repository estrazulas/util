# VPN Watchdog — openfortivpn com auto-reconnect

Gerenciador de conexão VPN via `openfortivpn` com watchdog automático e serviço systemd.

## Pré-requisitos

Antes de usar este script, instale o `openfortivpn` (caso ainda não tenha):

```
sudo apt install openfortivpn
```

Depois, edite o arquivo `/etc/openfortivpn/config` (como root) com os dados da sua VPN:

```
host = vpn.exemplo.com.br
port = 443
username = seu-usuario
password = sua-senha
```

Um template vazio fica em `/usr/share/openfortivpn/config.template`.

> ⚠️ **Importante:** este repositório só gerencia a conexão (start, stop, watchdog).  
> A configuração do servidor, usuário e senha é de sua responsabilidade.

**Sobre o `trusted-cert`:** na primeira tentativa de conexão, o `openfortivpn` exibe
o hash do certificado do servidor e trava com erro. Copie o hash e adicione no
`/etc/openfortivpn/config`:

```
trusted-cert = xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Uma vez configurado, o `trusted-cert` dificilmente muda (a menos que o certificado
do servidor VPN seja renovado).

## Scripts

### `openfortivpn.sh` (original)

Script original mantido como referência. Comandos:

```
start   — inicia a VPN (pede senha sudo)
stop    — mata o processo openfortivpn
status  — mostra se o processo está rodando ou não
```

**Limitações:** não detecta se a conexão realmente caiu (o processo pode ficar vivo mesmo sem interface), e precisa de intervenção manual para reconectar.

---

### `openfortivpn-v2.sh` (versão melhorada)

Versão com watchdog e auto-reconnect. Comandos:

```
start   — inicia a VPN (sem pedir senha se o sudoers estiver configurado)
stop    — para a VPN e limpa a interface ppp0
status  — mostra 3 estados: conectada / desconectada / processo vivo mas interface caída
restart — stop + start rápido
watch   — monitora a conexão e reconecta automaticamente com backoff progressivo
```

**Melhorias em relação ao original:**
- Status inteligente: verifica se a interface `ppp0` está ativa (não só se o processo existe)
- Auto-reconnect: watchdog detecta queda e faz stop + start automático
- Backoff progressivo: 10s (5x) → 60s (10x) → 5min (após 15 falhas)
- Notificação no desktop: alerta visual via `notify-send` se falhar por muito tempo
- Senha: integração com sudoers para não solicitar senha
- Root detection: funciona como usuário (com sudo) ou como root (systemd)

### Watchdog — Comportamento

O watchdog (`watch`) gerencia a conexão em loop infinito com backoff progressivo:

| Tentativas falhas | Intervalo | Descrição                               |
|-------------------|-----------|-----------------------------------------|
| 0 — 5             | 10s       | Verificação rápida, reconexão imediata  |
| 6 — 15            | 60s       | Backoff após falhas consecutivas        |
| 16+               | 5 min     | Espera longa — provável problema crônico |

- **Auto-start na inicialização:** com `sudo systemctl enable vpn-watchdog`,
  o watchdog sobe junto com o sistema e já inicia a VPN automaticamente.
- **Transições:** quando a VPN cai ou volta, o watchdog notifica via `notify-send`.
- **Alerta crítico:** após 15 falhas (~5min), exibe notificação vermelha sugerindo verificar as credenciais.
- **Pause manual:** `$0 stop` cria `/tmp/.vpn-watchdog-pausado` e o watchdog
  entra em espera sem tentar reconectar — fica aguardando o usuário subir
  manualmente com `$0 start`, que remove o pause file e retoma o watchdog.

---

### `install.sh` — Instalador

Instala todos os componentes necessários para o funcionamento automático da VPN.

**Uso:** `sudo ./install.sh <seu-usuario>`

**O que faz:**
1. Cria regra no `/etc/sudoers.d/` para executar `openfortivpn` sem senha
2. Cria o serviço systemd `/etc/systemd/system/vpn-watchdog.service`
3. Adiciona o alias `vpn-status` no `.bashrc` do usuário
4. Torna os scripts executáveis

---

### `uninstall.sh` — Removedor

Remove toda a instalação do VPN Watchdog.

**Uso:** `sudo ./uninstall.sh <seu-usuario>`

**O que faz:**
1. Para e desabilita o serviço systemd `vpn-watchdog`
2. Remove o arquivo `/etc/systemd/system/vpn-watchdog.service`
3. Remove a regra `/etc/sudoers.d/openfortivpn-<usuario>`
4. Remove o alias `vpn-status` do `.bashrc`
5. Mata processos `openfortivpn` remanescentes

Os scripts originais no diretório não são apagados — apenas a instalação (sudoers + systemd + alias).

---

## Serviço systemd

O serviço `vpn-watchdog` roda o watchdog em segundo plano e:

- **Inicia automaticamente** com o sistema (quando habilitado)
- **Reinicia o watchdog** se ele morrer por qualquer motivo (`Restart=always`)
- **Loga tudo** no journald para diagnóstico

### Comandos úteis

```bash
# Gerenciar o serviço
sudo systemctl start vpn-watchdog        # iniciar agora
sudo systemctl stop vpn-watchdog         # parar
sudo systemctl restart vpn-watchdog      # reiniciar
sudo systemctl enable vpn-watchdog       # iniciar com o PC
sudo systemctl disable vpn-watchdog      # não iniciar com o PC
sudo systemctl status vpn-watchdog       # status do serviço

# Ver logs
sudo journalctl -u vpn-watchdog -f       # logs ao vivo
sudo journalctl -u vpn-watchdog -n 50    # últimas 50 linhas

# Status rápido
vpn-status                                # alias do .bashrc
```

---

## Instalação rápida

```bash
# 1. Executar o instalador
sudo ./install.sh estrazulas

# 2. Ativar o serviço
sudo systemctl enable vpn-watchdog --now

# 3. Verificar
systemctl status vpn-watchdog
vpn-status
```

## Dependências

- `openfortivpn` — cliente VPN Fortinet
- `systemd` — gerenciamento de serviço
- `iproute2` — comandos `ip link` / `ip addr` (padrão no Ubuntu)
