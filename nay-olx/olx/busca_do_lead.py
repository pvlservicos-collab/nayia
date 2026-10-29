"""O CARD DA BUSCA DO LEAD SEGUE A CONVERSA (Pedro, 29/10/2026): "quero que o card de busca do lead esteja em mais
destaque no card do lead e que a Nay atualize a busca, ex.: Susi veio de um imóvel de 350, mas depois ela disse até 450,
cada mensagem do lead sobrescreve a antiga que ela supôs pela OLX".

O card do CRM (BuscasDoLead.tsx) lê privado.lead_busca, que a análise de 28/10 (analisar_leads.py, 510) gravou com os
pedidos tirados à mão: ficou parado no dia da análise (a Susi, 7640, em "até R$ 350.000 · Chapada" quando a Nay já tinha
"até R$ 450.000" e mais 5 bairros). Aqui, de 15 em 15 minutos, cada busca do lead (privado.busca_cliente, cujo perfil a
Nay atualiza a cada mensagem: buscas.garantir) que ficou diferente do card é analisada de novo com a MESMA régua
(analisar_leads.avaliar: a nota da Captação ativa, a faixa firme de valor, só o que ainda não foi a ele) e o card do lead
passa a ser o pedido de agora. Só perfil que dá para buscar (buscas.pronto); o que ainda não dá, fica o card de antes.
"""
from __future__ import annotations

import json
import logging
import time

from olx import banco, buscas

log = logging.getLogger("nay-olx.busca_do_lead")
A_CADA_S = 15 * 60
_ULTIMA = [0.0]

PENDENTES = """
SELECT b.lead, b.filtros, EXISTS (SELECT 1 FROM privado.lead_busca s WHERE s.lead_id = b.lead) AS tem_card
  FROM privado.busca_cliente b
 WHERE b.atualizado_em > now() - interval '10 days'
   AND NOT EXISTS (SELECT 1 FROM privado.lead_busca s
                    WHERE s.lead_id = b.lead AND s.ordem = 1 AND s.filtros = b.filtros
                      AND NOT EXISTS (SELECT 1 FROM privado.lead_busca o WHERE o.lead_id = b.lead AND o.ordem > 1))
 ORDER BY b.atualizado_em DESC
 LIMIT 40
"""


def disse(f: dict) -> str:
    """O pedido de agora em palavras, com o que ele exige (a Susi: "entrada de R$ 50.000 para simulação", "elevador")."""
    exige = [str(x).strip() for x in (f.get("exigencias") or []) if str(x).strip()]
    return buscas.resumo(f) + (f"; exige: {', '.join(exige)}" if exige else "")


def atualizar(conn, forcar: bool = False) -> int:
    if not forcar and time.time() - _ULTIMA[0] < A_CADA_S:
        return 0
    _ULTIMA[0] = time.time()
    # 29/10: o card da análise de 28/10 (pedido tirado à mão da conversa) só cede lugar a um pedido COM valor: os filtros
    # que a Nay ainda não completou ("VENDA · Apartamento · 2 quartos", sem teto) diziam menos do que ele
    pend = [p for p in banco.linhas(conn, PENDENTES)
            if buscas.pronto(p["filtros"] or {}) and ((p["filtros"] or {}).get("teto") or not p["tem_card"])]
    if not pend:
        return 0
    import analisar_leads as al                 # na raiz do nay-olx (o serviço roda com -m olx.worker de lá)
    from olx import busca_olx as bo, whatsapp
    c = buscas._cfg(conn)
    regras, _ = bo.gregras.carregar(bo.REGRAS_DOS_GRUPOS)
    so_nossos, vizinhos = bo.gcatalogo.carregar(conn, com_parceiro=False)
    feitas = 0
    for p in pend:
        lead = whatsapp._lead(conn, p["lead"])
        if not lead:
            continue
        f = dict(p["filtros"])
        try:
            fora = al.ja_foram(conn, lead)
            if buscas.abaixo_do_minimo(f, c):
                achados, motivo, situacao = [], buscas.texto_do_minimo(c), "abaixo_do_minimo"
            else:
                achados, motivo = al.avaliar(conn, lead, f, fora, regras, so_nossos, vizinhos)
                situacao = "com_opcoes" if achados else "sem_opcoes"
            banco.um(conn, "DELETE FROM privado.lead_busca WHERE lead_id = %s", (lead["id"],))
            bid = banco.um(conn, """INSERT INTO privado.lead_busca (lead_id, telefone, ordem, titulo, disse, filtros, situacao,
                                       motivo, ja_enviados) VALUES (%s, %s, 1, %s, %s, %s, %s, %s, %s) RETURNING id""",
                           (lead["id"], lead["telefone"], al.titulo(f), disse(f),
                            json.dumps(f, ensure_ascii=False), situacao, motivo, sorted(fora)))
            for pos, x in enumerate(achados, 1):
                banco.um(conn, """INSERT INTO privado.lead_busca_imovel (busca_id, posicao, codigo, nota, detalhe)
                                  VALUES (%s, %s, %s, %s, %s)""",
                         (bid, pos, x["codigo"], x["nota"], json.dumps(x["detalhe"], ensure_ascii=False)))
            conn.commit()
            feitas += 1
            log.info("card do lead %s: %s (%d opção/ões)", lead["id"], al.titulo(f), len(achados))
        except Exception:  # noqa: BLE001 -- um lead com erro não para os outros
            conn.rollback()
            log.exception("card do lead %s: não atualizei", p["lead"])
    return feitas
