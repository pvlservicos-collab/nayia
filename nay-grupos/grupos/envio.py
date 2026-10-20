"""O ENVIO AUTOMÁTICO (modo "ativo", Pedro 19/10/2026).

Pedro, 09/10: "TREINO: lê, extrai, pontua e mostra. NUNCA envia ... Não prossiga para o modo ATIVO até eu confirmar".
Pedro, 19/10, confirmando: "pode ativar um envio automático para o corretor que pediu, em imóveis com a nota acima de
88, com uma mensagem bacana: 'Oi, vi seu pedido lá no grupo, veja se esse imóvel serve' ... pode botar para chamar o
corretor no PV pelo número da Parceria no automático".

Pedro, 20/10 (o Júlio recebeu o 9003 MOBILIADO para "modulados e climatizado"): "se achar uma opção de nota acima de
88 ela não manda direto, ela vai lá no corretor e pergunta se serve para ele com modulados e ar, ou serve para ele
mobiliado ... essa Nay deve se chamar NAY CAPTAÇÃO DOS GRUPOS". Desde então o automático NÃO manda o card: manda só a
PERGUNTA (`pergunta`, abaixo: o imóvel em uma linha, a mobília dele dita, "serve para o seu cliente?") pela
`site_captacao_grupos_perguntar` (429), que deixa em `nay_contexto_do_grupo` o pedido do grupo e o imóvel. A Nay da
Parceria (nay-core) lê esse contexto antes de responder: "sim" manda o card e as fotos; "não" recusa o imóvel e a busca
segue com o pedido do grupo (nada do pedido velho do corretor). O botão manual do painel continua mandando o card.

Este módulo não fala com a rede: escolhe os pedidos e chama a função do banco, que põe a pergunta na caixa de saída da
Nay (número da Parceria) com as travas do botão "Enviar ao corretor" (339): janela de 48 h, um envio por card, o imóvel
tem de ter casado com o pedido, e as paredes da caixa da Nay (imóvel de parceiro nunca sai para corretor).

As travas daqui, a mais:
  - só com modo "ativo" em config.json; só pedido com nota ACIMA de `nota_min_automatico` (88), o melhor imóvel dele;
  - só pedido chegado depois de `automatico_desde` (o envio liga do momento em diante, não varre o que já passou);
  - nunca a quem é da equipe; nunca de um grupo nosso (`privado.grupo_fora`, 418);
  - um corretor recebe no máximo um envio automático por hora, e nunca o mesmo imóvel duas vezes;
  - no máximo `automatico_max_dia` envios automáticos por dia;
  - só entre `automatico_das` e `automatico_ate` (hora de Manaus): o pedido da noite sai de manhã, se ainda na janela;
  - o pedido que o banco recusou não é tentado de novo até o serviço reiniciar.
"""
from __future__ import annotations

import datetime
import logging

from grupos.catalogo import mobilia_do, tipo_do
from grupos.texto import mobilia_pedida, normal

log = logging.getLogger("grupos.envio")
QUEM = "automático"
MANAUS = datetime.timezone(datetime.timedelta(hours=-4))
_RECUSADOS: set[int] = set()

CANDIDATOS = """
SELECT * FROM (
  SELECT DISTINCT ON (coalesce(j.card, q.id)) q.id, q.melhor_codigo, q.nota, q.remetente, q.enviada_em,
         right(regexp_replace(coalesce(q.remetente, ''), '\\D', '', 'g'), 8) AS quem
    FROM privado.grupo_pedido q
    LEFT JOIN privado.grupo_pedido_junto j ON j.pedido_id = q.id
   WHERE q.fonte = 'grupo' AND q.estado = 'novo' AND q.pontuado_em IS NOT NULL
     AND q.melhor_codigo IS NOT NULL AND q.nota > %(nota)s
     AND q.enviada_em > now() - make_interval(hours => %(janela)s)
     AND q.enviada_em >= %(desde)s::timestamptz
     AND nai_chave(q.remetente) IS NOT NULL
     AND NOT privado.grupo_e_nosso(q.grupo_id, q.grupo_nome)
     -- o card inteiro (cópias e partes): se alguém já enviou ou rejeitou, não vai
     AND NOT EXISTS (SELECT 1 FROM privado.grupo_pedido_junto jc JOIN privado.grupo_pedido c ON c.id = jc.pedido_id
                      WHERE jc.card = j.card AND c.estado IN ('enviado', 'rejeitado'))
     AND NOT EXISTS (SELECT 1 FROM nai_contato k WHERE k.chave = nai_chave(q.remetente) AND nai_e_da_equipe_contato(k.id))
     -- o mesmo imóvel nunca vai duas vezes ao mesmo corretor (ele pede o mesmo em vários grupos, em mensagens diferentes)
     AND NOT EXISTS (SELECT 1 FROM privado.grupo_pedido_oferta o
                      WHERE o.codigo = q.melhor_codigo AND nai_chave(o.telefone) = nai_chave(q.remetente))
     -- 20/10 (Júlio, 5516): o Tel mandou o 5725 à mão às 10:04 e às 10:48 o radar perguntou do mesmo imóvel. Imóvel
     -- que já saiu para ele por QUALQUER caminho nos últimos 30 dias (o card leva "Código: N") não é perguntado
     AND NOT EXISTS (SELECT 1 FROM mensagens m
                      WHERE right(regexp_replace(m.telefone, '\\D', '', 'g'), 8)
                            = right(regexp_replace(coalesce(q.remetente, ''), '\\D', '', 'g'), 8)
                        AND m.direcao <> 'recebida' AND m.criada_em > now() - interval '30 days'
                        AND m.texto ~ ('C[oó]digo:\\s*' || q.melhor_codigo || '\\M'))
   ORDER BY coalesce(j.card, q.id), q.nota DESC, q.enviada_em DESC) x
 ORDER BY x.enviada_em
"""

ENVIADOS_HOJE = """
SELECT count(*) AS n FROM privado.grupo_pedido_oferta
 WHERE quem = %(quem)s AND enviado_em >= date_trunc('day', now() AT TIME ZONE 'America/Manaus') AT TIME ZONE 'America/Manaus'
"""

CORRETOR_NA_ULTIMA_HORA = """
SELECT EXISTS (SELECT 1 FROM privado.grupo_pedido_oferta
                WHERE quem = %(quem)s AND nai_chave(telefone) = nai_chave(%(fone)s) AND enviado_em > now() - interval '1 hour') AS ja
"""


DADOS_DA_PERGUNTA = """
SELECT q.remetente_nome, q.texto, q.ficha, i.tipo, i.bairro, i.condominio_nome, i.quartos, i.mobilia,
       i.valor_aluguel, i.valor_venda
  FROM privado.grupo_pedido q JOIN imoveis i ON i.codigo = %(codigo)s
 WHERE q.id = %(id)s
"""

# a mobília do imóvel dita ao corretor (o "com modulados e ar" é o semimobiliado do cadastro)
COMO_E = {"mobiliado": "mobiliado", "semi": "com modulados e ar", "climatizado": "só climatizado",
          "vazio": "sem mobília"}


def _dinheiro(v: float) -> str:
    return "R$ " + f"{v:,.0f}".replace(",", ".")


# 20/10: "Oi, Corretora!" (o nome do WhatsApp dela é a profissão) e "uma casa no Casa, Flores" (o condomínio do 5613
# está escrito "Casa" no cadastro)
NAO_E_NOME = {"corretor", "corretora", "corretores", "imobiliaria", "imob", "imoveis", "creci", "consultor",
              "consultora", "dr", "dra", "sr", "sra"}
NAO_E_CONDOMINIO = {"casa", "apartamento", "apto", "ap", "condominio", "residencial", "edificio", "sem", "nao",
                    "nao tem", "n/a", "na", "-", "outro", "outros"}


def _primeiro_nome(nome: str | None) -> str | None:
    p = (nome or "").strip().split()
    if not p or not p[0].isalpha() or len(p[0]) < 2 or normal(p[0]) in NAO_E_NOME:
        return None
    return p[0].capitalize()


def _condominio(c: str | None) -> str:
    c = (c or "").strip()
    return "" if len(c) < 3 or normal(c) in NAO_E_CONDOMINIO else c


def pergunta(d: dict) -> str:
    """A pergunta da Nay Captação dos Grupos. Nunca leva "Código:": o card só sai quando ele disser que serve."""
    ficha = d.get("ficha") or {}
    nome = _primeiro_nome(d.get("remetente_nome"))
    casa = tipo_do(d.get("tipo")) == "casa"
    o_que, ele, mob = ("uma casa", "Ela", "mobiliada") if casa else ("um apartamento", "Ele", "mobiliado")
    onde = ", ".join(x for x in (_condominio(d.get("condominio_nome")), (d.get("bairro") or "").strip()) if x)
    venda = ficha.get("operacao") == "venda" or (ficha.get("operacao") != "aluguel" and not d.get("valor_aluguel"))
    valor = d.get("valor_venda") if venda else d.get("valor_aluguel")
    partes = []
    if d.get("quartos"):
        partes.append(f"{d['quartos']} {'quarto' if d['quartos'] == 1 else 'quartos'}")
    if valor:
        partes.append(f"à venda por {_dinheiro(float(valor))}" if venda else f"{_dinheiro(float(valor))} de aluguel")
    linha = f"Tenho {o_que}" + (f" no {onde}" if onde else "") + (": " + ", ".join(partes) if partes else "") + "."
    tem = mobilia_do(d.get("mobilia"))
    pediu = mobilia_pedida(ficha.get("trecho") or d.get("texto"), ficha.get("mobiliado"))
    if tem == "mobiliado" and pediu not in (None, "mobiliado"):
        serve = f"{ele} é {mob}. Serve {mob} para o seu cliente?"
    elif tem in COMO_E and pediu not in (None, "sem") and tem != pediu:
        serve = f"{ele} é {COMO_E[tem]}. Serve assim para o seu cliente?"
    elif tem in COMO_E:
        serve = f"{ele} é {COMO_E[tem]}. Serve para o seu cliente?"
    else:
        serve = "Serve para o seu cliente?"
    oi = f"Oi, {nome}! Vi seu pedido lá no grupo 😊" if nome else "Oi! Vi seu pedido lá no grupo 😊"
    return f"{oi}\n\n{linha} {serve} Se servir, te mando as fotos."


def no_horario(r: dict, agora: datetime.datetime | None = None) -> bool:
    h = (agora or datetime.datetime.now(MANAUS)).astimezone(MANAUS).hour
    return r["automatico_das"] <= h < r["automatico_ate"]


def ligado(r: dict) -> bool:
    return r.get("modo") == "ativo" and bool(r.get("envio_manual")) and bool(str(r.get("automatico_desde") or "").strip())


def automatico(conn, r: dict, linhas) -> int:
    """Uma passada do envio automático. `linhas` é a de grupos.banco. Devolve quantos saíram."""
    if not ligado(r) or not no_horario(r):
        return 0
    feitos_hoje = linhas(conn, ENVIADOS_HOJE, {"quem": QUEM})[0]["n"]
    sobra = r["automatico_max_dia"] - feitos_hoje
    if sobra <= 0:
        return 0
    candidatos = linhas(conn, CANDIDATOS, {"nota": r["nota_min_automatico"], "janela": r["janela_h"],
                                           "desde": r["automatico_desde"]})
    saiu, nesta_passada = 0, set()
    for c in candidatos:
        if saiu >= sobra:
            break
        if c["id"] in _RECUSADOS or c["quem"] in nesta_passada:
            continue
        if linhas(conn, CORRETOR_NA_ULTIMA_HORA, {"quem": QUEM, "fone": c["remetente"]})[0]["ja"]:
            continue
        dados = linhas(conn, DADOS_DA_PERGUNTA, {"id": c["id"], "codigo": c["melhor_codigo"]})
        if not dados:
            _RECUSADOS.add(c["id"])
            continue
        res = linhas(conn, "SELECT site_captacao_grupos_perguntar(%s, %s, %s, %s) AS r",
                     (c["id"], c["melhor_codigo"], pergunta(dados[0]), QUEM))[0]["r"] or {}
        conn.commit()
        if res.get("ok"):
            saiu += 1
            nesta_passada.add(c["quem"])
            log.info("envio automático: pedido %s, imóvel %s (nota %s) para ...%s: %s", c["id"], c["melhor_codigo"],
                     c["nota"], c["quem"][-4:], res.get("resumo"))
        else:
            _RECUSADOS.add(c["id"])
            log.warning("envio automático recusado: pedido %s, imóvel %s: %s", c["id"], c["melhor_codigo"], res.get("erro"))
    return saiu
