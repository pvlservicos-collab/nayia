"""03/11/2026 (Pedro: "corrigir e tratar ele"): o Moacy (...5300) respondeu à pergunta da busca #59 no anúncio dele na OLX
("está disponível, vamos alugar") quando busca_corretor_e ainda o descartava (dono da campanha de setembro; 581 corrigiu).
Quando a Nay dos corretores passou a lê-lo, a mensagem foi marcada como lida sem cadastro. Aqui, UMA vez, o mesmo caminho do
corretores_volta: o anúncio vira o imóvel de parceiro e vai à busca #59 (cliente com a equipe: aviso no grupo). A equipe está
na conversa com ele (o "Grata!" das 15:12), então nada é mandado ao Moacy.

    cd /root/nay-olx && set -a && . ./.env && set +a && .venv/bin/python moacy_0311.py [--ensaio]
"""
import json
import sys
from datetime import datetime

from olx import banco, buscas as B

T8, BUSCA = "91315300", 59
ensaio = "--ensaio" in sys.argv

conn = banco.conectar()
c = B._cfg(conn)
cor = banco.linhas(conn, "SELECT * FROM privado.busca_corretor WHERE telefone8 = %s", (T8,))[0]
b = banco.linhas(conn, "SELECT * FROM privado.busca_cliente WHERE id = %s", (BUSCA,))[0]
conversa = B._conversa_corretor(conn, T8)
anuncio = B.anuncio_da_conversa(conn, T8, [m["texto"] or "" for m in conversa])
assert anuncio and int(anuncio["olx_id"]) == 1546851995, anuncio and anuncio.get("olx_id")
fotos_anuncio = [u for u in anuncio.get("fotos") or [] if u][:B.FOTOS_DO_ANUNCIO]
fotos = B._qtd_fotos(conn, T8, cor.get("codigo"))
if fotos < B.FOTOS_MINIMAS:
    fotos += len(fotos_anuncio)
# o título diz "Armários e ar condicionados": com modulados e ar (a busca pede semi)
im = B.venda_pelo_valor(B.juntar_imovel(B.imovel_do_anuncio(conn, anuncio), {"mobilia": "com modulados e ar"}))
falta = B.falta_no_imovel(im, fotos)
print("imóvel:", json.dumps(im, ensure_ascii=False))
print("fotos:", fotos, "| falta:", falta, "| corretor:", c["corretor"], "| busca:", b["estado"], b["teste"])
if ensaio:
    sys.exit(0)

banco.um(conn, "UPDATE privado.busca_corretor SET imovel = %s::jsonb, busca = %s, estado = 'cadastrando' WHERE telefone8 = %s",
         (json.dumps(im, ensure_ascii=False), BUSCA, T8))
cor = {**cor, "imovel": im, "busca": BUSCA}
completo = not falta and c["corretor"] == "sim"
codigo = B.cadastrar(conn, cor, b, ativo=completo, fotos_do_anuncio=fotos_anuncio, anuncio=anuncio)
banco.um(conn, "UPDATE privado.busca_corretor SET codigo = %s WHERE telefone8 = %s", (codigo, T8))
banco.um(conn, "UPDATE privado.busca_cliente SET ofertas = ofertas || %s::jsonb WHERE id = %s",
         (json.dumps([{"tel": cor["telefone"], "nome": cor.get("nome"), "codigo": codigo,
                       "em": datetime.now(B.MANAUS).isoformat(timespec="minutes"), "estado": "cadastrando"}], ensure_ascii=False), BUSCA))
B.passo(conn, BUSCA, "corretor", f"Corretor {cor.get('nome') or ''} (…{T8[-4:]}) ofereceu um imóvel: pré-cadastro #{codigo}")
conn.commit()
print("cadastrado:", codigo, "completo:", completo)
if completo:
    onde = B.oferecer_ao_cliente(conn, b, codigo, cor, c)
    if onde in ("cliente", "grupo"):
        banco.um(conn, """UPDATE privado.busca_cliente SET ofertas = (
                   SELECT coalesce(jsonb_agg(CASE WHEN o->>'codigo' = %s::text THEN o || jsonb_build_object('estado', %s::text)
                                                  ELSE o END ORDER BY n), '[]'::jsonb)
                     FROM jsonb_array_elements(ofertas) WITH ORDINALITY AS x(o, n)) WHERE id = %s""", (codigo, onde, BUSCA))
        banco.um(conn, "UPDATE privado.busca_corretor SET estado = 'ofertado' WHERE telefone8 = %s", (T8,))
    B.passo(conn, BUSCA, "oferta", {"cliente": f"Imóvel #{codigo} completo e oferecido ao cliente",
                                     "grupo": f"Imóvel #{codigo} completo; o cliente está com a equipe: avisado no grupo",
                                     "teste": f"Imóvel #{codigo} completo (teste: não foi ao cliente)",
                                     "espera": f"Imóvel #{codigo} completo; vai ao cliente na revisita da base"}[onde])
    conn.commit()
    print("oferta:", onde)
