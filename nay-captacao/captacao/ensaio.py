"""Ensaio: uma conversa inteira com o lead de TESTE, com o modelo e o banco de verdade, sem enviar nada.

    python -m captacao.ensaio disponivel
    python -m captacao.ensaio alugado
    python -m captacao.ensaio alugado_desde  diz quando alugou: ela pergunta a duração, não "até quando vai" (325)
    python -m captacao.ensaio vendido
    python -m captacao.ensaio ja_temos      o imóvel dele já está no nosso cadastro (318), para LOCAÇÃO: só o valor, e segue
    python -m captacao.ensaio venda         o imóvel dele está no cadastro para VENDA: confirma o valor, nada de "locação"
    python -m captacao.ensaio venda_outro   idem, e ele diz outro valor
    python -m captacao.ensaio sem_imovel    lead sem imóvel ligado (planilha antiga): "é para venda ou para locação?"
    python -m captacao.ensaio sem_imovel_loc  idem, e ele diz que é para alugar
    python -m captacao.ensaio outro_tem     447: modelo outro_imovel_04 (lista 5, imóvel alugado), ele toca "Tenho outro imóvel"
    python -m captacao.ensaio outro_nao     idem, "Não tenho outro"
    python -m captacao.ensaio outro_qual    idem, ele pergunta qual é o imóvel e depois diz que tem

Tudo roda numa transação só, DESFEITA no fim. Nenhuma mensagem sai (o envio é pulado) e nada fica gravado.
É o simulador do fluxo (Arquivos/captacao_ficha/simular_captacao.js), agora no serviço em Python, e começa pelo
modelo oficial com os botões -- como a conversa de verdade vai começar.
"""
from __future__ import annotations

import sys
from datetime import datetime, timezone

from captacao import banco, config
from captacao.atender import atender
from captacao.disparo import ZERAR, vocativo

ABERTURA = ("Olá, {quem}! Este é o novo número da Imob Easy. Precisamos atualizar a situação do seu imóvel cadastrado "
            "conosco. Por favor, selecione a opção que corresponde à situação atual:")
CENARIOS = {
    "disponivel": ["Disponível", "2.800", "3 quartos, 1 suíte, 2 banheiros e 1 vaga", "não sei a metragem",
                   "condomínio 650 e o IPTU uns 120 por mês. o aluguel não inclui nada", "semimobiliado, tem armários e ar",
                   "depois eu mando as fotos", "não, só esse mesmo", "conheço sim, meu cunhado Carlos está vendendo uma casa no Tarumã",
                   "o número dele é 92 99999-0000", "obrigado"],
    "alugado": ["Alugado", "até março de 2027", "não tenho outro", "não conheço ninguém", "ok"],
    # 325: ele diz QUANDO alugou; a pergunta é a duração, e o fim do contrato é conta do sistema
    # 09/10: "onde conseguiu meu contato?" tem resposta pronta (prompt v7), sem escalar
    "contato": ["Disponível", "Onde vc conseguiu o meu contato?", "2.500", "não, só esse", "não conheço ninguém", "ok"],
    "alugado_desde": ["foi alugado em fevereiro", "contrato de dois anos", "não tenho outro", "não conheço ninguém", "ok"],
    "vendido": ["Vendido", "tenho sim, uma casa no Tarumã pra vender", "3 quartos, 2 banheiros e 4 vagas",
                "uns 300 metros de terreno", "quero 650 mil", "agora não posso mandar mais nada, depois falo", "ninguém, obrigado"],
    "pergunta": ["Disponível", "quanto vocês cobram de comissão?"],
    "ja_temos": ["Disponível", "3.200", "não, só esse mesmo", "não conheço ninguém", "obrigado"],
    "parar": ["não quero receber mensagem, me tira dessa lista"],
    # 12/10: imóvel que anunciamos para VENDA (venda.py) -- a pergunta é a confirmação do valor do cadastro
    "venda": ["Disponível", "sim, continua", "não, só esse mesmo", "não conheço ninguém", "sim, já está incluso", "obrigado"],
    "venda_outro": ["Disponível", "baixei, agora é 550 mil", "não tenho outro", "ninguém", "já está incluso sim"],
    # 12/10: lead sem imóvel ligado -- não presume locação, pergunta o negócio
    "sem_imovel": ["Disponível", "é para vender", "450 mil", "não, só esse", "não conheço ninguém", "já está incluso"],
    "sem_imovel_loc": ["Disponível", "pra alugar", "2.500", "agora não posso responder mais nada, depois falo"],
    # 447: a lista 5 (imóvel alugado por nós) com o outro_imovel_04 -- explica, e o "sim" segue para a ficha do imóvel novo
    "outro_tem": ["Tenho outro imóvel", "é uma casa no Parque das Laranjeiras, quero alugar", "3 quartos, 2 suítes, 3 banheiros e 2 vagas",
                  "uns 200 metros", "4.500", "não tem condomínio, o IPTU é uns 150", "sem móveis", "mando as fotos amanhã",
                  "não, só essa", "não conheço ninguém", "obrigado"],
    "outro_nao": ["Não tenho outro", "não conheço ninguém", "ok"],
    "outro_qual": ["qual imóvel?", "tenho sim, um apartamento no Adrianópolis pra vender", "agora não posso, depois falo"],
}
# 447: o texto do outro_imovel_04 (o CRM devolve este texto quando o modelo sai)
ABERTURA_OUTRO = "Cadastro de proprietário: {quem}, o(a) Sr.(a) possui outro imóvel disponível além do que já consta conosco?"
# de qual imóvel o lead de teste fica dono até o ROLLBACK: de locação (ja_temos) ou só de venda (venda, venda_outro)
EMPRESTADO = {"ja_temos": "coalesce(i.valor_aluguel, 0) > 0",
              "venda": "coalesce(i.valor_venda, 0) > 0 AND coalesce(i.valor_aluguel, 0) = 0",
              "venda_outro": "coalesce(i.valor_venda, 0) > 0 AND coalesce(i.valor_aluguel, 0) = 0"}


def rodar(cenario: str) -> None:
    conn = banco.conectar(autocommit=False)
    try:
        lead = banco.linhas(conn, """
            SELECT l.id, l.telefone, l.nome, l.tratamento FROM captacao_leads l
             WHERE nay_fone_chave(l.telefone) = nay_fone_chave((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste'))""")[0]
        tel = lead["telefone"]
        banco.linhas(conn, ZERAR, (lead["id"],))
        banco.linhas(conn, "UPDATE captacao_leads SET canal = 'oficial' WHERE id = %s", (lead["id"],))
        banco.linhas(conn, "DELETE FROM captacao_cadastro WHERE lead_id = %s", (lead["id"],))
        banco.linhas(conn, "DELETE FROM captacao_imoveis_extra WHERE lead_id = %s", (lead["id"],))
        if cenario.startswith("sem_imovel"):
            banco.linhas(conn, """UPDATE captacao_leads SET codigo = NULL, imovel_desc = NULL, condominio = NULL, bairro = NULL,
                                         tipo_imovel = NULL, imoveis_prop = '[]'::jsonb WHERE id = %s""", (lead["id"],))
        if cenario in EMPRESTADO:
            # o imóvel de um lead da campanha (de preferência da fila), que existe no cadastro, emprestado ao lead de
            # teste até o ROLLBACK
            dele = banco.linhas(conn, """
                UPDATE captacao_leads t SET codigo = o.codigo, imovel_desc = o.imovel_desc, condominio = o.condominio,
                       bairro = o.bairro, tipo_imovel = o.tipo_imovel, imoveis_prop = o.imoveis_prop
                  FROM (SELECT l.* FROM captacao_leads l
                         WHERE l.id <> %s AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo::text = l.codigo AND """ + EMPRESTADO[cenario] + """)
                         ORDER BY (l.id IN (SELECT captacao_py_fila_do_disparo())) DESC, l.id LIMIT 1) o
                 WHERE t.id = %s RETURNING t.codigo, t.imovel_desc,
                       (SELECT i.valor_venda FROM imoveis i WHERE i.codigo::text = t.codigo) AS venda,
                       (SELECT i.valor_aluguel FROM imoveis i WHERE i.codigo::text = t.codigo) AS aluguel""", (lead["id"], lead["id"]))
            print("imóvel emprestado ao lead de teste:", dele[0] if dele else "NENHUM (não há lead com imóvel assim)")
        outro = cenario.startswith("outro_")
        if outro:
            # o imóvel alugado de um lead da lista 5, emprestado ao lead de teste até o ROLLBACK, com o modelo dele
            dele = banco.linhas(conn, """
                UPDATE captacao_leads t SET codigo = o.codigo, imovel_desc = o.imovel_desc, condominio = o.condominio,
                       bairro = o.bairro, tipo_imovel = o.tipo_imovel, imoveis_prop = o.imoveis_prop,
                       modelo_abertura = o.modelo_abertura, etapa = 'aguardando_outros', pergunta_pendente = o.pergunta_pendente
                  FROM (SELECT l.* FROM captacao_leads l WHERE l.id <> %s AND l.modelo_abertura LIKE 'outro\\_imovel%%'
                         ORDER BY l.id LIMIT 1) o
                 WHERE t.id = %s RETURNING t.codigo, t.tipo_imovel, t.imovel_desc, t.modelo_abertura""", (lead["id"], lead["id"]))
            print("imóvel emprestado ao lead de teste:", dele[0] if dele else "NENHUM (a 447 não está aplicada?)")
        config.AVISAR_TEL = False   # ensaio nunca avisa o Tel
        abertura = (ABERTURA_OUTRO if outro else ABERTURA).format(quem=vocativo(lead["tratamento"], lead["nome"]))
        banco.linhas(conn, banco.REGISTRAR_DISPARO, {"lead": lead["id"], "tel": tel, "mid": "ensaio", "texto": abertura})
        print(f"=== cenário {cenario} | modelo {config.MODELO} | lead de teste {lead['id']}\n")
        print("NAY (modelo oficial):", abertura,
              "[Tenho outro imóvel] [Não tenho outro]\n" if outro else "[Disponível] [Alugado] [Vendido]\n")
        for fala in CENARIOS[cenario]:
            # como o "Gravar na fila": a fala dele entra na caixa e o lead passa a 'respondendo'
            banco.linhas(conn, """
                INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status, criada_em)
                VALUES (%s, %s, 'recebida', 'texto', %s, 'Recebido py', now() - interval '30 seconds')""", (lead["id"], tel, fala))
            banco.linhas(conn, """
                UPDATE captacao_leads SET respondeu_em = coalesce(respondeu_em, now()),
                       status = CASE WHEN status IN ('enviado', 'reservado', 'erro') THEN 'respondendo' ELSE status END
                 WHERE id = %s""", (lead["id"],))
            print("DONO:", fala)
            f = atender(conn, tel, enviar=False, agora=datetime.now(timezone.utc), dormir=lambda s: None)
            for x in f.ferramentas:
                print(f"   -> {x['ferramenta']}({x['args']})")
                print("      <- " + " ".join(x["saida"].split())[:300])
            print("NAY: ", " / ".join(f.baloes) if f.baloes else f"({f.motivo})", "\n")
        fim = banco.linhas(conn, """
            SELECT situacao, contrato_ate, valor_locacao_pedido, valor_venda_pedido, etapa, tem_outro_imovel, quer_vender, motivo_fim, status,
                   humano_assumiu_em IS NOT NULL AS com_gente, opt_out,
                   (SELECT count(*) FROM privado.captacao_indicacao i WHERE i.lead_id = l.id) AS indicacoes,
                   (SELECT count(*) FROM captacao_escalacoes e WHERE e.lead_id = l.id AND e.criada_em > now() - interval '5 minutes') AS escaladas
              FROM captacao_leads l WHERE l.id = %s""", (lead["id"],))[0]
        print("=== LEAD no fim:", {k: v for k, v in fim.items() if v not in (None, False, 0)})
    finally:
        conn.rollback()
        conn.close()
        print("(tudo desfeito no banco; nenhuma mensagem saiu)")


if __name__ == "__main__":
    nome = sys.argv[1] if len(sys.argv) > 1 else "disponivel"
    if nome not in CENARIOS:
        raise SystemExit("cenários: " + ", ".join(CENARIOS))
    rodar(nome)
