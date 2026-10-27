"""27/10/2026 (Pedro, sobre os leads que a Nay Leads deixou sem resposta: "agenda a resposta para amanhã em horário
comercial"). Roda UMA vez, às 09:00 de Manaus de 27/10, pelo /etc/cron.d/nay-leads-resposta-2710
(scripts/agendar_resposta_2710.sh instala e o cron se apaga depois).

Cada resposta sai pela Nay (whatsapp.mandar_texto: o eco não conta como gente da equipe). Não sai quando a pessoa já
recebeu alguma coisa por este número depois do pedido do Pedro (a Nay ou a equipe já respondeu) ou quando a equipe
está com a conversa (humano_em).

    cd /root/nay-olx && set -a && . ./.env && set +a && TZ=America/Manaus .venv/bin/python resposta_2710.py
"""
from olx import banco, whatsapp

PEDIDO = "2026-10-27 03:30:00+00"          # 26/10 23:30 de Manaus, quando o Pedro pediu

RESPOSTAS = {
    # 69 9204-7936: "Poderia informar o nome da rua?" / "a localização mais aproximada no bairro" (casa #2683)
    61: ("Bom dia! Sobre a casa #2683 no Dom Pedro: ela fica no bairro Dom Pedro, na região da Av. Pedro Teixeira, "
         "da Av. Dom Pedro e da Av. Jacira Reis. Se quiser conhecer, agendo uma visita para você."),
    # Sr. Karis, 92 98181-9145: "Tem alguma outra casa pra aluguel no condomínio?" (só no Ponta Negra Village, até 7 mil)
    60: ("Bom dia, Sr. Karis! Conferi as casas do Ponta Negra Village: as que estão com a gente lá hoje são para venda. "
         "Já pedi aos nossos parceiros uma casa para alugar no condomínio, até R$ 7.000, com modulados e ar, e aviso o "
         "senhor assim que aparecer."),
}


def main() -> None:
    conn = banco.conectar()
    if not whatsapp.conectada():
        print("8595 desconectado: nada saiu")
        return
    for lid, texto in RESPOSTAS.items():
        lead = whatsapp._lead(conn, lid)
        if not lead:
            print(f"lead {lid}: não existe")
            continue
        if lead.get("humano_em"):
            print(f"lead {lid}: a equipe está com a conversa; não saiu")
            continue
        ja = banco.um(conn, """SELECT EXISTS (SELECT 1 FROM captacao_mensagens WHERE direcao = 'enviada'
                                  AND criada_em > %s::timestamptz
                                  AND right(regexp_replace(coalesce(telefone, ''), '\\D', '', 'g'), 8) = right(%s, 8))""",
                      (PEDIDO, lead["telefone"]))
        if ja:
            print(f"lead {lid}: já recebeu resposta depois do pedido; não saiu")
            continue
        mid = whatsapp.mandar_texto(conn, lead, texto)
        print(f"lead {lid}: {'mandada ' + mid if mid else 'segurada (repetida)'}")


if __name__ == "__main__":
    main()
