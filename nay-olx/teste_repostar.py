"""Teste do Pedro (21/10/2026): "pegar os 2 anúncios de aluguel com menos visitas na OLX, excluir e depois postar de novo,
porque tenho a teoria desses anúncios estarem com baixa visualização por serem postados muito rápido".
Escolhidos (sem visualização pela API): IE1125L e IE9024L, do lote de 13 de 15/10 23:38, zero conversas e zero leads.

Mexe só no anúncio de LOCAÇÃO de cada código (o de venda fica). Registra no banco pelas mesmas funções da rodada.
No servidor, em /root/nay-olx com o .env carregado:
  python teste_repostar.py remover 1125 9024     manda a remoção e mostra o que a OLX respondeu
  python teste_repostar.py ver 1125 9024         a situação no banco (o worker confere a moderação sozinho)
  python teste_repostar.py publicar 1125 9024    publica de novo o de locação (anúncio montado do cadastro agora)
"""
import json
import sys

from olx import anuncios, api, banco

CONTA = "proprietarios"


def main(acao: str, codigos: list[int]) -> None:
    conn = banco.conectar()
    token = banco.token_da_conta(conn, CONTA)
    if acao == "ver":
        anuncios.conferir(conn)
        for r in banco.linhas(conn, """SELECT ad_id, estado, olx_status, list_id, url, mensagem,
                                              to_char(atualizado_em, 'DD/MM HH24:MI') AS quando
                                         FROM privado.olx_anuncio WHERE negocio = 'locacao' AND codigo = ANY(%s)""", (codigos,)):
            print(json.dumps(r, ensure_ascii=False, default=str))
        return
    for c in codigos:
        ad_id = f"IE{c}L"
        if acao == "remover":
            r = api.ler_importacao(api.importar(token, [{"id": ad_id, "operation": "delete"}]))
            print(ad_id, "remoção:", r.mensagem, "| aceita:", r.aceita, "| erros:", r.erros or "-")
            if r.aceita and ad_id not in r.ignorados:
                banco.um(conn, "SELECT olx_anuncio_enviado(%s, %s, 'locacao', %s, 'delete', NULL, NULL, %s)",
                         (ad_id, c, CONTA, r.token))
        elif acao == "publicar":
            m = banco.um(conn, "SELECT olx_anuncio_montar(%s, 'locacao')", (c,)) or {}
            if not m.get("ok"):
                print(ad_id, "não monta:", m.get("barrado") or m.get("falta"))
                continue
            r = api.ler_importacao(api.importar(token, [m["anuncio"]]))
            print(ad_id, "publicação:", r.mensagem, "| aceita:", r.aceita, "| erros:", r.erros or "-")
            if r.aceita and ad_id not in r.ignorados:
                banco.um(conn, "SELECT olx_anuncio_enviado(%s, %s, 'locacao', %s, 'insert', %s::jsonb, %s, %s)",
                         (ad_id, c, CONTA, banco.js(m["anuncio"]), m["hash"], r.token))


if __name__ == "__main__":
    main(sys.argv[1], [int(x) for x in sys.argv[2:]])
