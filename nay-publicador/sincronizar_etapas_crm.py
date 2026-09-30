"""
A etapa da conversa com a Nay vira TAG do lead no CRM (Tel, 28/09/2026).

O PEDIDO: "cria setores etapas, o cliente fica na etapa identificação, ou na
etapa recebeu o imóvel, ou na agendamento de visita" -- e, sobre onde ver: "põe
no CRM em tags cada pessoa, mas isso é mais internamente na IA para fazer ela
funcionar melhor e classificar sem ela bugar do que para nós".

A etapa é calculada no banco da Nay (`nai_etapa_contato`, migração 141) a cada
turno. Este script, de minuto em minuto, leva a etapa que mudou para o lead do
mesmo telefone no CRM: uma tag só, e tira as outras duas da Nay.

OS NOMES TÊM O PREFIXO "Nay:" DE PROPÓSITO. No CRM, uma tag com o MESMO nome de
uma coluna do funil move o card para ela (rota de tags). "Nay: Agendamento de
visita" nunca bate com "Agendou visita": a etapa da Nay informa, não mexe no
funil de ninguém.

Roda silencioso quando não há nada. Uso:
    .venv/bin/python sincronizar_etapas_crm.py
"""
import os
import re

import psycopg2

ORG = "a47991bb-80e3-43ad-9838-02258ebac5d2"
TAGS = {
    "identificacao": ("Nay: Identificação", "#94a3b8"),
    "recebeu_imovel": ("Nay: Recebeu o imóvel", "#0ea5e9"),
    "agendamento_visita": ("Nay: Agendamento de visita", "#f97316"),
}


def _dsn(banco):
    dsn = os.environ["DATABASE_URL"]
    return re.sub(r"/[^/?]+(\?|$)", "/" + banco + r"\1", dsn, count=1)


def telefone_do_crm(telefone):
    """O CRM guarda 55 + DDD + 9 + 8 dígitos. A Nay guarda sem o 9."""
    d = re.sub(r"\D", "", telefone or "")
    if len(d) == 12 and d.startswith("55"):
        d = d[:4] + "9" + d[4:]
    return d if len(d) == 13 else None


def sincronizar():
    nay = psycopg2.connect(_dsn("naydb"))
    crm = psycopg2.connect(_dsn("crmdb"))
    feitos = 0
    try:
        with nay.cursor() as cur:
            # o telefone da pessoa: a linha do telefone, nunca a do @lid
            cur.execute("""
                SELECT e.contato_id, e.etapa,
                       (SELECT c.telefone FROM nai_contato c
                         WHERE c.id = ANY (nai_contato_irmaos(e.contato_id))
                           AND c.chave !~ '^lid:' ORDER BY c.id LIMIT 1) AS telefone
                  FROM nai_etapa_contato e
                 WHERE e.crm_em IS NULL OR e.crm_em < e.atualizado_em
                 ORDER BY e.atualizado_em
                 LIMIT 200""")
            pendentes = cur.fetchall()
        if not pendentes:
            return 0

        with crm.cursor() as cur:
            ids = {}
            for chave, (nome, cor) in TAGS.items():
                cur.execute("SELECT id FROM tags WHERE organization_id = %s AND name = %s", (ORG, nome))
                linha = cur.fetchone()
                if linha is None:
                    cur.execute("INSERT INTO tags (organization_id, name, color) VALUES (%s, %s, %s) RETURNING id",
                                (ORG, nome, cor))
                    linha = cur.fetchone()
                ids[chave] = linha[0]
        crm.commit()

        for contato_id, etapa, telefone in pendentes:
            fone = telefone_do_crm(telefone)
            if fone and etapa in ids:
                with crm.cursor() as cur:
                    cur.execute("SELECT id FROM leads WHERE organization_id = %s AND phone = %s AND deleted_at IS NULL",
                                (ORG, fone))
                    leads = [r[0] for r in cur.fetchall()]
                    for lead in leads:
                        cur.execute("DELETE FROM lead_tags WHERE lead_id = %s AND tag_id = ANY (%s::uuid[]) AND tag_id <> %s",
                                    (lead, [str(v) for v in ids.values()], ids[etapa]))
                        cur.execute("INSERT INTO lead_tags (lead_id, tag_id, organization_id) VALUES (%s, %s, %s) "
                                    "ON CONFLICT DO NOTHING", (lead, ids[etapa], ORG))
                        feitos += 1
                crm.commit()
            with nay.cursor() as cur:
                cur.execute("UPDATE nai_etapa_contato SET crm_em = now() WHERE contato_id = %s", (contato_id,))
            nay.commit()
    finally:
        nay.close()
        crm.close()
    return feitos


if __name__ == "__main__":
    n = sincronizar()
    if n:
        print(f"{n} lead(s) com a etapa da Nay atualizada")
