"""O PALPITE da fila do Cadastro rápido: "O que a IA supõe que é" (332).

Pedro, 09/10/2026: "quero que você prejulgue em categorias analisando, e crie uma categoria com cores lá, 'O que a IA
supõe que é', e separe os julgamentos em ordem por categorias".

Cada item da fila (nai_cadastro_pendente: a ficha que o dono ditou na conversa, ou o imóvel que espera alguém) vai ao
modelo com o que se sabe dele -- a ficha, a conversa, os outros imóveis do mesmo dono, os parecidos da fila -- e volta
com UMA categoria e o porquê. O resultado fica em cadastro_rapido_palpite; a tela ordena e filtra por ele. Nada é
mudado no cadastro: é só a triagem, quem decide é a pessoa.

    python -m captacao.palpite              os itens sem palpite, ou que mudaram depois dele (até 15 por vez)
    python -m captacao.palpite --tudo       a fila inteira, de novo
    python -m captacao.palpite --item ficha:72   um item só (ficha:<id> ou imovel:<código>)
    python -m captacao.palpite --ensaio --limite 8   mostra o palpite sem gravar (não precisa da tabela)

Roda junto com o preparar, de 5 em 5 minutos (/etc/cron.d/captacao-preparar-fichas).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys

import psycopg2

from captacao import banco, config
from captacao.modelo import FalhaDoModelo, _chamar, _texto_da

# a ordem é a da tela: o que mais vale a pena abrir primeiro
CATEGORIAS = {
    "novo": "Imóvel novo para anunciar",
    "atualizacao": "Atualização de imóvel que já temos",
    "completar": "Cadastro para completar",
    "indisponivel": "Alugado ou indisponível agora",
    "repetido": "Repetido de outro da fila",
    "nao_e": "Não é para cadastrar",
}

FILA = "SELECT * FROM nai_cadastro_pendente()"

FEITOS = "SELECT fonte, item, base FROM cadastro_rapido_palpite"

GUARDAR = """
INSERT INTO cadastro_rapido_palpite (fonte, item, categoria, porque, base, analisado_em, modelo)
VALUES (%(fonte)s, %(item)s, %(categoria)s, %(porque)s, %(base)s, now(), %(modelo)s)
ON CONFLICT (fonte, item) DO UPDATE
   SET categoria = EXCLUDED.categoria, porque = EXCLUDED.porque, base = EXCLUDED.base, analisado_em = now(), modelo = EXCLUDED.modelo
"""

# a conversa de um lead da captação, a mais recente no fim
CONVERSA = """
SELECT string_agg(to_char(m.criada_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') || ' '
                  || CASE m.direcao WHEN 'recebida' THEN 'DONO' ELSE 'NOS' END || ': '
                  || left(regexp_replace(CASE WHEN coalesce(btrim(m.texto), '') = '' THEN '[' || coalesce(m.origem, 'mídia') || ']' ELSE m.texto END,
                                         '\\s+', ' ', 'g'), 400), E'\\n' ORDER BY m.id) AS conversa
  FROM (SELECT * FROM captacao_mensagens x WHERE x.lead_id = %s ORDER BY x.id DESC LIMIT %s) m
"""

FICHA = """
SELECT c.id, c.lead_id, c.estado, c.dados, c.criado_em,
       jsonb_array_length(CASE WHEN jsonb_typeof(c.fotos) = 'array' THEN c.fotos ELSE '[]' END) AS fotos,
       l.nome, l.situacao AS situacao_do_imovel_da_campanha, l.codigo AS codigo_da_campanha,
       concat_ws(' · ', l.imovel_desc, l.condominio, l.bairro) AS imovel_da_campanha, l.proprietario_id,
       a.campos AS campos_analisados, a.pronto AS pronto_para_anunciar, a.observacao, a.duplicado_de,
       (SELECT json_agg(json_build_object('ficha', o.id, 'estado', o.estado, 'codigo', o.codigo, 'dados', o.dados) ORDER BY o.id)
          FROM captacao_cadastro o WHERE o.lead_id = c.lead_id AND o.id <> c.id) AS outras_fichas_do_dono
  FROM captacao_cadastro c
  LEFT JOIN captacao_leads l ON l.id = c.lead_id
  LEFT JOIN captacao_ficha_campos a ON a.ficha_id = c.id
 WHERE c.id = %s
"""

IMOVEL = """
SELECT i.codigo, i.tipo, i.status, i.condominio_nome AS condominio, i.bairro, i.logradouro, i.area_util, i.quartos, i.suites,
       i.vagas, i.valor_venda, i.valor_aluguel, i.mobilia, left(coalesce(i.descricao, ''), 500) AS descricao, i.origem,
       i.publicado_no_site, i.disponivel, i.bloqueado, i.motivo_bloqueio, i.e_parceiro, i.travado_motivo, i.criado_em,
       coalesce(i.proprietario_id, (SELECT p.proprietario_id FROM imovel_privado p WHERE p.codigo = i.codigo)) AS proprietario_id,
       (SELECT count(*) FROM imovel_fotos f WHERE f.codigo = i.codigo AND coalesce(f.url, '') <> '') AS fotos,
       (SELECT json_agg(json_build_object('ficha', c.id, 'tipo', c.tipo, 'estado', c.estado, 'dados', c.dados) ORDER BY c.id)
          FROM captacao_cadastro c WHERE c.codigo = i.codigo) AS o_que_o_dono_ditou_na_conversa,
       coalesce((SELECT max(c.lead_id) FROM captacao_cadastro c WHERE c.codigo = i.codigo),
                (SELECT l.id FROM captacao_leads l WHERE l.codigo = i.codigo::text AND l.respondeu_em IS NOT NULL
                  ORDER BY l.respondeu_em DESC LIMIT 1)) AS lead
  FROM imoveis i WHERE i.codigo = %s
"""

# os outros imóveis do mesmo dono que já estão cadastrados (para saber se a ficha é atualização de um deles)
DO_DONO = """
SELECT i.codigo, i.tipo, i.status, i.condominio_nome AS condominio, i.bairro, i.valor_venda, i.valor_aluguel
  FROM imoveis i
 WHERE i.status <> 'Excluído' AND i.codigo <> coalesce(%(codigo)s, -1)
   AND (i.proprietario_id = %(dono)s OR EXISTS (SELECT 1 FROM imovel_privado p WHERE p.codigo = i.codigo AND p.proprietario_id = %(dono)s))
 ORDER BY i.codigo LIMIT 25
"""

INSTRUCAO = """Você faz a TRIAGEM da fila de cadastro de uma imobiliária de Manaus. Recebe UM item da fila -- uma ficha que o
proprietário ditou no WhatsApp (ainda não é imóvel cadastrado), ou um imóvel já cadastrado que espera alguém -- e diz o
que ele PARECE ser, para a pessoa abrir primeiro o que vale mais.

Responda SÓ um objeto JSON: {"categoria": "<uma das chaves abaixo>", "porque": "<uma frase curta e concreta>"}

As categorias:
  repetido      é o MESMO imóvel de outro item da fila ou de outra ficha do mesmo dono, e ESTE é a cópia (diga de qual:
                "mesmo Forest Hill da ficha 51"). Veja a regra da principal, abaixo
  atualizacao   os dados são de um imóvel que JÁ está cadastrado: a ficha descreve um imóvel da lista 'imoveis_do_dono'
                (mesmo condomínio ou endereço), ou é um imóvel cadastrado em que o dono ditou situação, valor ou fotos na
                conversa e ninguém aplicou. Imóvel cadastrado SEM nada ditado na conversa não é "atualizacao": se só
                falta dado (dono, foto, bairro), é "completar"
  indisponivel  o imóvel existe mas não é para anunciar agora: está alugado, ocupado, em obra, já foi vendido, ou o dono
                disse que avisa depois
  nao_e         não há imóvel para cadastrar: a pessoa só citou, recusou, é corretor ou parceiro, foi engano ou teste, ou a
                ficha não tem dado nenhum
  novo          imóvel que NÃO temos e que o dono quer vender ou alugar AGORA
  completar     imóvel que já é nosso (pré-cadastro, rascunho, anúncio antigo) e só falta gente completar: foto, bairro,
                área, valor, descrição

Regras:
- A PRINCIPAL não é repetida. Entre itens que são o mesmo imóvel, UM é o principal e recebe a categoria de verdade
  (novo, indisponivel...); só os outros são "repetido". O principal é, nesta ordem: o imóvel já cadastrado (tem código);
  senão a ficha em estado "pronto" contra a "coletando"; senão a que tem mais dados; senão a de número MENOR.
  Compare 'este_item' com 'outras_fichas_do_dono' por essa ordem antes de dizer "repetido". Se este é o principal, o
  porquê pode terminar com "(a ficha 77 repete este)".
- Na dúvida entre duas categorias, vale a que aparece primeiro na lista acima.
- FICHA da conversa nunca é "completar" (ela ainda não é imóvel): imóvel novo com poucos dados é "novo", e o porquê diz o que falta.
- IMÓVEL já cadastrado (tem código) nunca é "novo".
- O imóvel da campanha (aquele sobre o qual perguntamos) já está cadastrado: se a ficha fala dele, é "atualizacao".
- O porquê cita o FATO que decidiu, com as palavras do caso ("disse que está alugado até dez/2027", "rascunho do site
  antigo, sem foto e sem valor", "casa nova no Forest Hill, 3 suítes, R$ 1,29 mi, com fotos"). Até 140 caracteres, sem floreio.
"""


def chave_de(linha: dict) -> tuple[str, int]:
    return ("ficha", int(linha["ficha_id"])) if linha["fonte"] == "ficha" else ("imovel", int(linha["codigo"]))


def base_de(linha: dict) -> str:
    """O que, mudando, pede palpite novo: a situação, o que falta, os motivos, as fotos e a ficha."""
    visto = {k: linha.get(k) for k in ("titulo", "tipo", "bairro", "condominio", "status", "falta", "motivos", "fotos", "dados")}
    return hashlib.md5(json.dumps(visto, sort_keys=True, ensure_ascii=False, default=str).encode("utf-8")).hexdigest()


def _sem_acento(t: str | None) -> str:
    import unicodedata
    return "".join(c for c in unicodedata.normalize("NFD", (t or "").lower()) if unicodedata.category(c) != "Mn").strip()


def parecidos(linha: dict, fila: list[dict]) -> list[dict]:
    """Os outros da fila com o mesmo condomínio ou o mesmo dono: é entre eles que mora o repetido."""
    condo, dono = _sem_acento(linha.get("condominio")), _sem_acento(linha.get("dono"))
    achados = []
    for o in fila:
        if o is linha:
            continue
        if (condo and len(condo) > 3 and _sem_acento(o.get("condominio")) == condo) or (dono and _sem_acento(o.get("dono")) == dono):
            achados.append({"item": "%s %s" % chave_de(o), "titulo": o.get("titulo"), "tipo": o.get("tipo"), "bairro": o.get("bairro"),
                            "status": o.get("status"), "dono": o.get("dono")})
    return achados[:12]


def entrada_de(conn, linha: dict, fila: list[dict]) -> tuple[dict, str]:
    """O que o modelo lê sobre o item, e a conversa (quando há)."""
    comum = {"por_que_esta_na_fila": linha.get("motivos"), "falta_preencher": linha.get("falta"),
             "parecidos_na_fila": parecidos(linha, fila)}
    conversa = ""
    if linha["fonte"] == "ficha":
        f = banco.linhas(conn, FICHA, (linha["ficha_id"],))
        if not f:
            raise ValueError("a ficha sumiu")
        f = f[0]
        dono = f.pop("proprietario_id")
        lead = f.pop("lead_id")
        entrada = {"item": "FICHA da conversa (ainda não é imóvel cadastrado)",
                   "este_item": {"ficha": f["id"], "estado": f["estado"], "campos_ditos": len(f.get("dados") or {})},
                   **f, **comum,
                   "imoveis_do_dono": banco.linhas(conn, DO_DONO, {"dono": dono, "codigo": None}) if dono else []}
        conversa = (banco.linhas(conn, CONVERSA, (lead, 80)) or [{}])[0].get("conversa") or ""
    else:
        i = banco.linhas(conn, IMOVEL, (linha["codigo"],))
        if not i:
            raise ValueError("o imóvel sumiu")
        i = i[0]
        dono = i.pop("proprietario_id")
        lead = i.pop("lead")
        entrada = {"item": "IMÓVEL já cadastrado", **i, "preenchido_pct": linha.get("pct"), **comum,
                   "imoveis_do_dono": banco.linhas(conn, DO_DONO, {"dono": dono, "codigo": linha["codigo"]}) if dono else []}
        # a conversa só entra quando o motivo é ela: senão é ruído (o dono falou de outra coisa)
        if lead and any("conversa" in (m or "") for m in linha.get("motivos") or []):
            conversa = (banco.linhas(conn, CONVERSA, (lead, 50)) or [{}])[0].get("conversa") or ""
    return entrada, conversa


def julgar(conn, linha: dict, fila: list[dict], guardar: bool = True) -> dict:
    entrada, conversa = entrada_de(conn, linha, fila)
    corpo = {"model": config.MODELO, "text": {"format": {"type": "json_object"}},
             "input": [{"role": "system", "content": INSTRUCAO},
                       {"role": "user", "content": "ITEM DA FILA:\n" + json.dumps(entrada, ensure_ascii=False, default=str) +
                                                   ("\n\nCONVERSA (a mais recente no fim):\n" + conversa if conversa else "")}]}
    bruto = json.loads(_texto_da(_chamar(corpo)) or "{}")
    categoria = str(bruto.get("categoria") or "").strip().lower()
    if categoria not in CATEGORIAS:
        raise ValueError(f"categoria que não existe: {categoria!r}")
    # as duas paredes da instrução, conferidas aqui: ficha não é "completar", imóvel com código não é "novo"
    if linha["fonte"] == "ficha" and categoria == "completar":
        categoria = "novo"
    if linha["fonte"] != "ficha" and categoria == "novo":
        categoria = "completar"
    # "atualizacao" num imóvel cadastrado só vale quando HÁ o que aplicar: o dono ditou algo na conversa.
    # Sem isso (falta o dono, falta foto) é cadastro para completar.
    if (linha["fonte"] != "ficha" and categoria == "atualizacao" and not entrada.get("o_que_o_dono_ditou_na_conversa")
            and not any("conversa" in (m or "") for m in linha.get("motivos") or [])):
        categoria = "completar"
    fonte, item = chave_de(linha)
    porque = " ".join(str(bruto.get("porque") or "").split())[:200] or None
    if guardar:
        banco.linhas(conn, GUARDAR, {"fonte": fonte, "item": item, "categoria": categoria, "porque": porque,
                                     "base": base_de(linha), "modelo": config.MODELO})
    return {"item": f"{fonte}:{item}", "titulo": linha.get("titulo"), "categoria": categoria, "porque": porque}


def rodar(conn, tudo: bool = False, limite: int = 15, so: tuple[str, int] | None = None, ensaio: bool = False) -> list[dict]:
    """Os palpites que faltam. Sem a tabela (a 332 ainda não entrou), não faz nada -- a não ser no ensaio, que só mostra."""
    try:
        feitos = {(r["fonte"], int(r["item"])): r["base"] for r in banco.linhas(conn, FEITOS)}
    except psycopg2.errors.UndefinedTable:
        if not ensaio:
            return []
        feitos = {}
    fila = banco.linhas(conn, FILA)
    na_fila = {chave_de(l) for l in fila}
    # quem saiu da fila não precisa mais de palpite
    for fonte, item in (set(feitos) - na_fila if not ensaio else ()):
        banco.linhas(conn, "DELETE FROM cadastro_rapido_palpite WHERE fonte = %s AND item = %s", (fonte, item))
    pendentes = [l for l in fila if (so is None or chave_de(l) == so)
                 and (tudo or so is not None or feitos.get(chave_de(l)) != base_de(l))]
    saida = []
    for l in pendentes[: (len(pendentes) if tudo or so else limite)]:
        try:
            saida.append(julgar(conn, l, fila, guardar=not ensaio))
        except (FalhaDoModelo, ValueError, json.JSONDecodeError) as erro:
            print("%s %s: sem palpite (%s)" % (*chave_de(l), erro), file=sys.stderr)
    return saida


def main() -> None:
    a = argparse.ArgumentParser(description="O palpite da IA para cada item da fila do Cadastro rápido.")
    a.add_argument("--tudo", action="store_true")
    a.add_argument("--limite", type=int, default=15)
    a.add_argument("--item", help="ficha:<id> ou imovel:<código>")
    a.add_argument("--ensaio", action="store_true", help="mostra o palpite sem gravar")
    args = a.parse_args()
    so = None
    if args.item:
        fonte, _, n = args.item.partition(":")
        if fonte not in ("ficha", "imovel") or not n.isdigit():
            a.error("--item é ficha:<id> ou imovel:<código>")
        so = (fonte, int(n))
    conn = banco.conectar()
    try:
        for r in rodar(conn, args.tudo, args.limite, so, args.ensaio):
            print(json.dumps(r, ensure_ascii=False))
    finally:
        conn.close()


if __name__ == "__main__":
    main()
