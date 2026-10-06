# Compressão (gzip) do site e da API pelo Traefik

Feito em 06/10/2026 (Pedro: "otimiza o /imoveis para carregar rápido"). Antes, HTML, JS e JSON saíam sem
compressão: o `/imoveis` baixava uns 320 KB só de texto (página 52 KB, script 49 KB, imóveis 114 KB,
bairros 107 KB). Com gzip isso cai para uns 70 KB.

Quem comprime é o Traefik (3.7), que está na frente dos dois containers, com um middleware só:
`nay-site-compress`. Ele é declarado no compose do site e usado pelos quatro roteadores.

## Rótulos (no srv1894338)

`/docker/nay-site-web/docker-compose.yml`:

```yaml
      - traefik.http.routers.nay-site.middlewares=nay-site-compress
      - traefik.http.middlewares.nay-site-compress.compress=true
      - traefik.http.routers.nay-site-admin.middlewares=nay-site-admin-auth,nay-site-compress
```

`/docker/nay-site-api/docker-compose.yml`:

```yaml
      - traefik.http.routers.nay-site-api.middlewares=nay-site-compress@docker
      - traefik.http.routers.nay-site-admin-api.middlewares=nay-site-admin-auth@docker,nay-site-compress@docker
```

Depois de mudar rótulo: `docker compose up -d` na pasta (o `./scripts/nay site` já faz isso para a API).
Os compose de antes ficaram em `*.bk_20261006_1611_antes_compressao`.

## Cache

- API (`nay-site-api/app.py`, `after_request`): a rota que já põe `Cache-Control` é respeitada
  (imoveis-para-enviar 2 min, mapa/bairros 1 h, imoveis/opcoes 5 min); as outras continuam `no-store`.
- Site (`nay-site-web.nginx-default.conf`, nesta pasta): `.js/.css` com `?v=` ficam um ano no navegador
  (a página troca o `v` a cada publicação); páginas, com ou sem extensão, sempre revalidam.

## Conferir

```sh
curl -s -o /dev/null -D - -H "Accept-Encoding: gzip" https://imobeasy.online/imoveis | grep -i "encoding\|cache"
curl -s -o /dev/null -D - -H "Accept-Encoding: gzip" https://api.imobeasy.online/api/imoveis-para-enviar | grep -i "encoding\|cache"
```
