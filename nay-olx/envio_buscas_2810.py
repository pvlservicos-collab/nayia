"""28/10/2026 (Pedro, depois da análise das buscas dos leads, 510): "lendo todo histórico de leads envia no pv algo como
Bom dia, encontrei essa opção caso ainda tenha interesse e envia os acima de 93, lembrando, checa se o lead não recebeu
esse já". Roda UMA vez, à mão:

    cd /root/nay-olx && set -a && . ./.env && set +a && TZ=America/Manaus .venv/bin/python envio_buscas_2810.py [--ensaio]

Sai pela Nay (whatsapp.mandar_texto / mandar_imovel: o eco não conta como gente da equipe), só o card, sem fotos (foto
só quando pedir). Na hora de mandar, o histórico é lido DE NOVO (analisar_leads.ja_foram: a Nay, os cards da equipe aqui
e pelo CRM, o link que ele colou, as ofertas da busca); a equipe que falou com ele na última meia hora segura o envio.
"""
import argparse
import time
from datetime import datetime

from olx import banco, whatsapp
from analisar_leads import ja_foram

NOTA = 93
ENTRE_LEADS_S = 20
FORA = {
    # 41: a 5742 (Sainte Marie) é a que ela perguntou, e a resposta da fila foi "Sim, mas já alugou" (28/10 09:05)
    41: "o 5742 é o Sainte Marie que ela perguntou, e a resposta da equipe foi \"já alugou\"",
}


def saudacao() -> str:
    h = datetime.now().hour
    return "Bom dia" if h < 12 else "Boa tarde" if h < 18 else "Boa noite"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ensaio", action="store_true")
    a = ap.parse_args()
    conn = banco.conectar()
    if not a.ensaio and not whatsapp.conectada():
        print("8595 desconectado: nada saiu")
        return
    linhas = banco.linhas(conn, """SELECT b.lead_id, x.codigo, x.nota FROM privado.lead_busca b
                                     JOIN privado.lead_busca_imovel x ON x.busca_id = b.id
                                    WHERE x.nota > %s ORDER BY b.lead_id, b.ordem, x.posicao""", (NOTA,))
    por_lead: dict[int, list[int]] = {}
    for r in linhas:
        if int(r["codigo"]) not in por_lead.setdefault(int(r["lead_id"]), []):
            por_lead[int(r["lead_id"])].append(int(r["codigo"]))
    primeiro = True
    for lid, cods in por_lead.items():
        if lid in FORA:
            print(f"lead {lid}: não saiu — {FORA[lid]}")
            continue
        lead = whatsapp._lead(conn, lid)
        equipe = banco.um(conn, """SELECT EXISTS (SELECT 1 FROM captacao_mensagens WHERE direcao = 'enviada'
                                      AND coalesce(origem, '') <> 'resposta' AND criada_em > now() - interval '30 minutes'
                                      AND right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = right(%s, 8))""",
                          (lead["telefone"],))
        if equipe or any(e["criada_em"] and (datetime.now(e["criada_em"].tzinfo) - e["criada_em"]).total_seconds() < 1800
                         for e in whatsapp.da_equipe_no_crm(whatsapp._so8(lead["telefone"]), limite=5)):
            print(f"lead {lid}: a equipe falou com ele na última meia hora; não saiu")
            continue
        ja = ja_foram(conn, lead)
        novos = [c for c in cods if c not in ja and whatsapp._ofertavel(conn, c, lead)]
        if not novos:
            print(f"lead {lid}: {cods} já foram ou não podem ir; nada saiu")
            continue
        texto = (f"{saudacao()}! Encontrei {'essa opção' if len(novos) == 1 else 'essas opções'} caso ainda tenha "
                 "interesse:")
        if a.ensaio:
            print(f"lead {lid} (…{lead['telefone'][-4:]}): {texto} + cards {novos}")
            continue
        if not primeiro:
            time.sleep(ENTRE_LEADS_S)
        primeiro = False
        mid = whatsapp.mandar_texto(conn, lead, texto)
        for c in novos:
            time.sleep(2)
            whatsapp.mandar_imovel(conn, lead, c, com_fotos=False)
        conn.commit()
        print(f"lead {lid} (…{lead['telefone'][-4:]}): texto {mid or 'segurado'} + cards {novos}")


if __name__ == "__main__":
    main()
