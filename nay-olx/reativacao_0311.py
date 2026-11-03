"""03/11/2026 (Pedro, 02/11: "resgate de clientes ... amanhã em horário comercial umas 9h de Manaus ... analisa conversa
a conversa ... só garante que não fique repetitivo, nem tenha conversa com outro contato"). Roda UMA vez, à mão, depois
de uma ensaio:

    cd /root/nay-olx && set -a && . ./.env && set +a && TZ=America/Manaus nohup .venv/bin/python reativacao_0311.py \\
        > /root/reativacao_0311.log 2>&1 &            (--ensaio: só mostra o que sairia, sem esperar e sem mandar)

Cada texto foi escrito para UMA conversa, lida inteira. Sai pela Nay (whatsapp.mandar_texto), 5 a 9 min entre um e
outro, das 8h30 às 12h de Manaus (Pedro, 02/11: durante o dia a Nay e o Lucas cuidam das visitas). Na hora de mandar, cada lead é conferido DE NOVO e só sai se:
  - o telefone do lead é o esperado (últimos 8 dígitos): conversa com outro contato não existe;
  - a Nay não está parada nele (humano, fechamento, finalizado) e a conversa continua valendo;
  - ele não escreveu e a equipe não falou nas últimas 24 h (se escreveu, a Nay responde a ele, não reativa);
  - nenhum texto parecido (0,8) foi para ele nos últimos 30 dias e nada saiu por este número nas últimas 36 h.
  - nenhuma visita dele na agenda (nay_agenda_de_visitas, de hoje a +30 dias) e nada sobre visita na conversa de hoje.
Parar: touch /root/reativacao_0311.parar
"""
import argparse
import os
import random
import time
from datetime import datetime
from zoneinfo import ZoneInfo

from olx import banco, whatsapp

MANAUS = ZoneInfo("America/Manaus")
INICIO_H, FIM_H = 8.5, 12.0
PARAR = "/root/reativacao_0311.parar"
DIA_INICIO = datetime(2026, 11, 3, 8, 30, tzinfo=MANAUS)

# (olx_lead_whatsapp.id, últimos 8 dígitos esperados, texto)
ITENS = [
    (54, "82020539", "Bom dia, Sr. Wellington! Ficou alguma das casas de condomínio para locação que conversamos? "
                     "Se quiser, vejo outras opções com energia solar ou já alinho uma visita."),
    (4, "91468187", "Bom dia, Sr. Carlos! O apartamento do Conquista Rio Negro, na Ponta Negra (2 quartos, mobiliado, "
                    "R$ 2.600 com a taxa), combinou com o que o senhor procura? Posso marcar uma visita ou buscar outras opções."),
    (14, "88416383", "Bom dia, Sr. José! O que o senhor achou da casa do Villa Suíça, no Tarumã? Se preferir algo mais "
                     "perto da região da Barreira, me diga o valor e eu busco."),
    (53, "81130048", "Bom dia, Sr. Charalambos! Conseguiu ver a casa do Reserva das Flores que mandei? Se quiser "
                     "conhecer, me diga o melhor dia e horário que eu alinho."),
    (74, "91583096", "Bom dia! Ainda quer visitar o apartamento do Flex Parque Dez? Se preferir ver outros na "
                     "região, é só me dizer o valor que procura."),
    (67, "81784805", "Bom dia! Você chegou a fechar a casa que tinha encontrado? Se ainda estiver procurando, me diz "
                     "o valor máximo que eu separo as melhores opções em condomínio."),
    (63, "82517640", "Bom dia! Chegou a ver os apartamentos que te mandei na semana passada? Se algum combinou, "
                     "eu marco a visita."),
    (83, "84011447", "Bom dia! Viu o que respondi sobre o quintal da casa? Se ela atende o que você procura, posso "
                     "agendar uma visita."),
    (65, "85960606", "Bom dia! Conseguiu conversar com a sua esposa sobre a casa do Morada dos Pássaros? Se quiserem "
                     "conhecer, é só me dizer o dia."),
    (58, "92364525", "Bom dia, Aline! Chegou a ver as opções de locação que te enviei? Se alguma combinar, marco a visita."),
    (3, "91761866", "Bom dia, Sra. Claudia! Faz um tempinho que conversamos sobre apartamento para comprar (o do "
                    "Kopenhagen e o do Plaza del Rey). A senhora ainda está procurando? Se sim, me diga até que valor "
                    "e eu separo as melhores opções."),
    (9, "82508556", "Bom dia, Sra. Isabela! Tudo bem? Ainda está atrás de um apartamento perto da UFAM, até R$ 300 mil? "
                    "Se sim, posso ver novas opções para a senhora."),
    (51, "91900698", "Bom dia! Você achou a casa para morar? Se ainda estiver procurando, posso ficar de olho em casas "
                     "de até R$ 150 mil e te aviso quando surgir uma."),
    (64, "45335053", "Bom dia, Sr. David! Queria saber como foi a sua visita ao Mont Clair. Se não era bem o que "
                     "procurava, me diga o que faltou que eu busco outras opções."),
    (6, "94756680", "Bom dia, Sra. Josy! Viu as casas que te mandei? Alguma agradou? Posso agendar uma visita."),
]


def agora():
    return datetime.now(MANAUS)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ensaio", action="store_true")
    a = ap.parse_args()
    conn = banco.conectar()
    cfg = banco.chaves(conn)
    if not a.ensaio:
        # só em 03/11/2026, a partir das 9h de Manaus (rodar antes espera; depois das 12h30 de 03/11 não manda nada)
        while agora() < DIA_INICIO:
            if os.path.exists(PARAR):
                print("parado")
                return
            time.sleep(30)
    primeiro = True
    for lid, f8, texto in ITENS:
        if os.path.exists(PARAR):
            print("parado")
            return
        if not a.ensaio and (agora().date() != DIA_INICIO.date() or agora().hour + agora().minute / 60 >= FIM_H):
            print(f"lead {lid}: passou das 12h; não saiu")
            continue
        lead = whatsapp._lead(conn, lid)
        motivo = None
        if not lead:
            motivo = "não existe"
        elif whatsapp._so8(lead["telefone"]) != f8:
            motivo = f"telefone não confere (…{lead['telefone'][-8:]} ≠ …{f8})"
        elif lead.get("humano_em") or lead.get("etapa") in ("fechamento", "finalizado"):
            motivo = f"parada/etapa ({lead.get('etapa')}, humano_em={lead.get('humano_em')})"
        elif not whatsapp._pode(cfg, lead["telefone"]):
            motivo = "a Nay não pode falar com este número (config)"
        else:
            tel8 = whatsapp._so8(lead["telefone"])
            if banco.um(conn, """SELECT EXISTS (SELECT 1 FROM captacao_mensagens WHERE direcao = 'recebida'
                                   AND criada_em > now() - interval '24 hours'
                                   AND right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %s)""", (tel8,)):
                motivo = "ele escreveu nas últimas 24 h (a Nay responde, não reativa)"
            elif whatsapp._gente_escreveu(conn, lead, banco.um(conn, "SELECT now() - interval '24 hours'")):
                motivo = "a equipe falou com ele nas últimas 24 h"
            elif banco.um(conn, """SELECT EXISTS (SELECT 1 FROM nay_agenda_de_visitas(
                                      date_trunc('day', now() AT TIME ZONE 'America/Manaus') AT TIME ZONE 'America/Manaus',
                                      now() + interval '30 days') a WHERE a.chave = nai_chave(%s))""", (lead["telefone"],)):
                motivo = "tem visita na agenda (hoje ou nos próximos dias)"
            elif banco.um(conn, """SELECT EXISTS (SELECT 1 FROM captacao_mensagens
                                   WHERE criada_em >= date_trunc('day', now() AT TIME ZONE 'America/Manaus') AT TIME ZONE 'America/Manaus'
                                   AND texto ~* 'visit|agend|hor[aá]rio'
                                   AND right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %s)""", (tel8,)):
                motivo = "a conversa de hoje fala de visita"
            elif banco.um(conn, """SELECT EXISTS (SELECT 1 FROM captacao_mensagens WHERE direcao = 'enviada'
                                   AND criada_em > now() - interval '36 hours'
                                   AND right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = %s)""", (tel8,)):
                motivo = "já saiu mensagem para ele nas últimas 36 h"
            elif any(whatsapp.parecida(texto, x, 0.8) for x in whatsapp.ja_mandou(conn, lead, horas=720)):
                motivo = "texto parecido com um que já foi para ele"
            elif not a.ensaio and not whatsapp.conectada():
                motivo = "8595 desconectado"
        if motivo:
            print(f"lead {lid} (…{f8}): NÃO SAIU — {motivo}")
            continue
        if a.ensaio:
            print(f"lead {lid} (…{f8}) {lead.get('nome') or ''}: sairia: {texto}")
            continue
        if not primeiro:
            time.sleep(random.randint(6 * 60, 10 * 60))
        primeiro = False
        try:
            mid = whatsapp.mandar_texto(conn, lead, texto)
            conn.commit()
            print(f"{agora():%H:%M:%S} lead {lid} (…{f8}): {'enviado ' + mid if mid else 'segurado (repetido)'}", flush=True)
        except Exception as e:  # noqa: BLE001
            conn.rollback()
            print(f"{agora():%H:%M:%S} lead {lid} (…{f8}): FALHOU — {e}", flush=True)
    print("fim")


if __name__ == "__main__":
    main()
