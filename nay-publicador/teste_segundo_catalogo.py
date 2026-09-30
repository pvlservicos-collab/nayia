"""
Testa o SEGUNDO CATÁLOGO: o imóvel que nasce no site novo e não tem página.

O CASO (Tel, 30/09): ele mandou "Posta no grupo anunciar easy o 9003" e a Nay
respondeu *"o anúncio não está no ar no site -- deve estar arquivado"*. A
resposta estava CERTA para o que ela sabia: `buscar_imovel` lê ao vivo de
`imobeasy.com/anuncios/<codigo>`, e ali o 9003 redireciona para
/nao-encontrado.

MAS O IMÓVEL EXISTE. Ele nasceu no site NOVO (`imobeasy.online`), que não tem
página por anúncio -- é HTML estático que lê de `api.imobeasy.online`, e essa
API grava direto no naydb. Medido: o 9003 está em `imoveis` (Edifício Firenze,
Parque 10, aluguel 5.000) e as 16 fotos em `imovel_fotos`.

Existem DOIS catálogos: o antigo, que a varredura raspa, e o novo, que nasce no
banco. Os códigos do novo começam em 9001.

O QUE IMPORTA PROVAR, e o que cada coisa custa se quebrar:

  * o SITE ANTIGO continua mandando quando tem o anúncio. Se o banco passar na
    frente, a Nay volta a postar a partir de cópia velha -- é a regra
    "cadastrou agora, posta agora" que o projeto defende desde o começo;

  * a TRAVA DO "ESTÁ NO AR". No catálogo antigo era o próprio site responder;
    aqui é `nay_esta_no_mercado`. Sem ela o segundo caminho postaria em 14
    grupos o rascunho que ele ainda não publicou, e postagem não desfaz;

  * SEM `tipo` NÃO SE POSTA. Página morta devolve dict TRUTHY com tudo None, e
    linha de banco pode vir pela metade. Foi assim que o Easy postou
    "📍 Imóvel 2944 / Código: 2944";

  * UM MONTADOR DE CARD SÓ. A API do site novo já devolve card pronto em
    `/api/imovel-card/`, e usá-lo criaria a segunda cópia da regra. Aqui sai o
    mesmo dicionário e `montar_mensagem` segue sendo o único que escreve card;

  * a CAPA vem primeiro. Nove dos dez grupos recebem só a primeira foto --
    mandar o banheiro como capa é pior que não postar.

Uso:
    .venv/bin/python teste_segundo_catalogo.py
"""
from unittest.mock import patch

import buscar_imovel
from montar_mensagem import montar_mensagem

falhas = 0


def checar(titulo, condicao, detalhe=""):
    global falhas
    falhas += 0 if condicao else 1
    print(f"  {'OK  ' if condicao else 'FALHOU'} {titulo}")
    if not condicao and detalhe:
        print(f"         {detalhe}")


# A linha do 9003 como está em produção, medida em 30/09.
LINHA_9003 = {
    "codigo": "9003", "tipo": "Apartamento", "condominio_nome": "Edifício Firenze",
    "bairro": "Parque 10 de Novembro", "area_util": 130.0, "quartos": 3,
    "suites": 1, "banheiros": 3, "vagas": None, "vagas_cobertas": 2,
    "valor_venda": None, "valor_aluguel": 5000.0, "sol": "Nascente",
    "mobilia": "mobiliado (moveis + cama + tudo)", "descricao": "...",
    "incluso": "Taxa de Condomínio", "lances": None, "financia": None,
    "no_mercado": True,
}

FOTOS_9003 = [{"url": f"https://imobeasy.online/fotos-captacao/olx/9003/{n:02d}.jpg"}
              for n in range(1, 17)]


class CursorFake:
    def __init__(self, conn):
        self.conn = conn
        self.linhas = []

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def execute(self, sql, params=None):
        s = " ".join(sql.split())
        if "FROM imovel_fotos" in s:
            self.linhas = list(self.conn.fotos)
            # A ORDEM É DO BANCO: a consulta tem que pedir capa primeiro,
            # senão o grupo recebe a foto errada como capa.
            assert "e_capa DESC" in s, "a consulta perdeu a ordem da capa"
        elif "FROM imoveis WHERE" in s:
            self.linhas = [self.conn.linha] if self.conn.linha else []
            # A TRAVA TEM QUE ESTAR NA CONSULTA, não só no if.
            assert "nay_esta_no_mercado" in s, "a consulta perdeu a trava de mercado"

    def fetchone(self):
        return self.linhas[0] if self.linhas else None

    def fetchall(self):
        return self.linhas


class ConnFake:
    def __init__(self, linha=None, fotos=None):
        self.linha = linha
        self.fotos = fotos or []

    def cursor(self):
        return CursorFake(self)

    def close(self):
        pass


def com_banco(linha, fotos=None, pagina_viva=None):
    """Roda `buscar_imovel` com o site fingido e o banco fingido."""
    conn = ConnFake(linha, fotos)
    import db
    with patch.object(db, "conectar", return_value=conn), \
         patch.object(buscar_imovel, "baixar_anuncio",
                      return_value=pagina_viva or "<html></html>"):
        return buscar_imovel.buscar_imovel(linha["codigo"] if linha else "9003")


GRUPO = {"aceita_venda": True, "aceita_locacao": True, "todas_fotos": True}

print("--- o 9003 do site novo vira card ---")
i = com_banco(LINHA_9003, FOTOS_9003)
checar("acha o imóvel", bool(i) and i.get("tipo") == "Apartamento", i)
checar("com as 16 fotos", len(i.get("fotos") or []) == 16, len(i.get("fotos") or []))
card = montar_mensagem(i, GRUPO)
checar("o card traz o condomínio", "📍 Edifício Firenze" in card, card)
checar("o bairro", "• Bairro: Parque 10 de Novembro" in card, card)
checar("a metragem", "• 130m2" in card, card)
checar("quartos e suíte", "• 3 quartos sendo 1 suíte" in card, card)
checar("as vagas cobertas", "• 2 vagas cobertas" in card, card)
checar("o sol", "• nascente" in card, card)
checar("a mobília", "• mobiliado" in card, card)
# A taxa vem de `extras->>'incluso no aluguel'`, o mesmo campo do outro
# catálogo -- o Tel cobrou isso em 14/09.
checar("a taxa inclusa", "Locação: R$ 5.000 (incluso a tx)" in card, card)
checar("e o código", "Código: 9003" in card, card)

print()
print("--- o SITE ANTIGO manda quando tem o anúncio ---")
# Se o banco passasse na frente, a Nay voltaria a postar de cópia velha.
PAGINA = """<html><body>
<div><label class="form-control-label">Condomínio</label>
<span class="form-control">Arezzo Residencial</span></div>
<div><label class="form-control-label">Bairro</label>
<span class="form-control">Flores</span></div>
<h1>Apartamento</h1>
</body></html>"""
with patch.object(buscar_imovel, "extrair_imovel",
                  return_value={"codigo": "5718", "tipo": "Apartamento",
                                "condominio": "DO SITE", "fotos": ["s.jpg"]}), \
     patch.object(buscar_imovel, "_complementar_do_banco", side_effect=lambda x: x), \
     patch.object(buscar_imovel, "baixar_anuncio", return_value=PAGINA), \
     patch.object(buscar_imovel, "_do_banco",
                  return_value={"codigo": "5718", "tipo": "Apartamento",
                                "condominio": "DO BANCO", "fotos": []}):
    r = buscar_imovel.buscar_imovel("5718")
checar("o site ganha do banco", r.get("condominio") == "DO SITE", r)

print()
print("--- a TRAVA do 'está no ar' ---")
# Medido em 30/09: o 9002 é rascunho (publicado_no_site=false) e o 9001 já saiu
# (disponivel=false). Postar rascunho em 14 grupos não desfaz.
for rotulo, mudanca in [("rascunho / imóvel que saiu", {"no_mercado": False}),
                        ("no_mercado nulo", {"no_mercado": None})]:
    fora = dict(LINHA_9003, **mudanca)
    r = com_banco(fora, FOTOS_9003)
    checar(f"{rotulo} NÃO vira imóvel", not (r and (r.get('tipo') or '').strip()), r)

print()
print("--- sem `tipo` não se posta ---")
# Foi assim que o Easy postou "📍 Imóvel 2944 / Código: 2944".
for rotulo, mudanca in [("tipo vazio", {"tipo": ""}),
                        ("tipo nulo", {"tipo": None}),
                        ("tipo só com espaço", {"tipo": "   "})]:
    r = com_banco(dict(LINHA_9003, **mudanca), FOTOS_9003)
    checar(f"{rotulo} NÃO vira imóvel", not (r and (r.get('tipo') or '').strip()), r)

print()
print("--- código que não existe em lugar nenhum ---")
r = com_banco(None, [])
checar("devolve vazio, e a recusa de sempre acontece",
       not (r and (r.get("tipo") or "").strip()), r)

print()
print("--- imóvel sem foto no banco ainda vira card ---")
# O card vale sem foto: o Easy manda todas, os outros grupos mandam a capa, e
# `_fotos_para_grupo` já lida com lista vazia. Recusar aqui esconderia um
# imóvel que existe.
i = com_banco(LINHA_9003, [])
checar("acha o imóvel", bool(i) and i.get("tipo") == "Apartamento")
checar("com zero foto", (i.get("fotos") or []) == [], i.get("fotos"))

print()
print("--- o banco não derruba o envio quando falha ---")
# `_do_banco` nunca pode levantar: o caminho do site já falhou, e uma exceção
# aqui trocaria a recusa explicada por um traceback no log.
import db as _db
with patch.object(_db, "conectar", side_effect=RuntimeError("banco fora")), \
     patch.object(buscar_imovel, "baixar_anuncio", return_value="<html></html>"):
    try:
        r = buscar_imovel.buscar_imovel("9003")
        checar("banco fora do ar não levanta", True)
    except Exception as e:
        checar("banco fora do ar não levanta", False, f"levantou {e!r}")

print()
if falhas:
    print(f"{falhas} CASOS FALHARAM")
    raise SystemExit(1)
print("TODOS OS CASOS DO SEGUNDO CATALOGO PASSARAM")
