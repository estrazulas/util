# Headroom Admin Demo GIF

Gera um GIF animado mostrando a interface de administração do Headroom (dashboard, usuários, times, chaves, uso com histórico e busca semântica).

## Pré-requisitos

- Python 3.10+
- Playwright + Chromium
- ffmpeg (para gerar o GIF)
- Proxy Headroom rodando e acessível

```bash
pip install playwright
playwright install chromium
sudo apt install ffmpeg   # Linux
```

## Uso

```bash
# Via variável de ambiente (localhost:8787)
export HEADROOM_API_KEY="hr_..."
python scripts/headroom/generate-admin-demo.py

# URL customizada
python scripts/headroom/generate-admin-demo.py \
  --url https://proxy.exemplo.com \
  --api-key "hr_..." \
  --output /tmp/admin-demo.gif
```

## O que o GIF mostra

1. Dashboard — visão geral do admin
2. Users — lista de usuários
3. Teams — gerenciamento de times
4. Keys — chaves de API
5. Usage — painel de uso com sumário
6. User History — combobox + sessões do usuário
7. Semantic Search — busca textual com resultados

O login não aparece no GIF — apenas as páginas internas.
