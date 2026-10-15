"""Ensaio da Nay proprietários da OLX: uma conversa inteira com o lead de TESTE, modelo e banco de verdade, nada sai.

    python -m captacao.ensaio_olx pedro             o lead do Pedro como está (9038, venda, sem condomínio nem elevador)
    python -m captacao.ensaio_olx elevador_locacao  apartamento de elevador para LOCAÇÃO (9035), e ele indica alguém
    python -m captacao.ensaio_olx casa_cond_venda   casa de condomínio para VENDA (9025), e pergunta de onde veio o contato
    python -m captacao.ensaio_olx casa_rua_locacao  casa de via pública para LOCAÇÃO
    python -m captacao.ensaio_olx honorarios_4      VENDA, ele só paga 4%: escala ao Tel e cala
    python -m captacao.ensaio_olx metade_locacao    LOCAÇÃO, ele quer pagar metade dos honorários: o texto do Pedro; insiste = escala
    python -m captacao.ensaio_olx pergunta          ele pergunta quanto o imóvel vale: escala e cala
    python -m captacao.ensaio_olx escreveu_primeiro o modelo não saiu e ele manda "oi": ela se apresenta e pergunta
    python -m captacao.ensaio_olx parar             ele pede para sair da lista
    python -m captacao.ensaio_olx todos

O "dono" do ensaio responde o campo que o roteiro está perguntando (como a pessoa de verdade faria); as falas especiais
de cada cenário entram no turno marcado. Tudo numa transação só, DESFEITA no fim.
"""
from __future__ import annotations

import sys
from datetime import datetime, timezone

from captacao import banco, config
from captacao.atender import atender
from captacao.disparo import ZERAR, vocativo

ABERTURA = ("Olá, {quem}! Aqui é a Nay, da Imob Easy. Conversamos na OLX sobre o seu imóvel e gostaria de tirar uma "
            "dúvida com o(a) Sr.(a).")
CASA_VENDA = "(SELECT codigo FROM imoveis WHERE tipo = 'Casa' AND coalesce(valor_venda,0) > 0 ORDER BY codigo DESC LIMIT 1)"
CASA_LOC = "(SELECT codigo FROM imoveis WHERE tipo = 'Casa' AND coalesce(valor_aluguel,0) > 0 ORDER BY codigo DESC LIMIT 1)"
PADRAO = {"condominio_nome": "Residencial Vila Verde", "elevador": "é de escada", "taxa_condominio": "450 reais",
          "iptu": "uns 120 por mês", "lances_escada": "3 lances", "bloco": "bloco C", "andar": "8º andar", "torre": "torre 2",
          "metragem_terreno": "300 metros", "numero_casa": "casa 12", "endereco": "Rua das Flores, 120, Japiim",
          "sol": "sol da manhã", "honorarios": "sim, já está incluso", "condominio_incluso": "não, a taxa é à parte",
          "outros": "não, só esse", "indicacao": "não conheço ninguém"}
CENARIOS = {
    "pedro": {"codigo": None, "resp": {"honorarios": "não, tem que acrescentar", "outros": "tenho uma casa no Tarumã também",
                                       "outros_detalhe": "casa de 3 quartos no Tarumã, pra vender por 600 mil"}},
    "elevador_locacao": {"codigo": "9035", "negocio": "locacao", "resp": {
        "elevador": "tem elevador", "indicacao": "conheço sim, minha vizinha Ana quer vender o apartamento dela, 92 99111-2222"}},
    "casa_cond_venda": {"codigo": "9025", "negocio": "venda", "falas": {2: "onde vc conseguiu meu contato?"}},
    "casa_rua_locacao": {"codigo": CASA_LOC, "negocio": "locacao"},
    "honorarios_4": {"codigo": "9012", "negocio": "venda", "resp": {"honorarios": "eu só pago 4%"}},
    "metade_locacao": {"codigo": "9035", "negocio": "locacao", "resp": {"elevador": "tem elevador"},
                       "falas": {3: "a comissão da locação eu só pago metade, tá?", 4: "não, só metade mesmo"}},
    "pergunta": {"codigo": "9038", "negocio": "venda", "falas": {1: "quanto vocês acham que vale o meu apartamento?"}},
    # os modelos ainda não aprovados: o Pedro escreve primeiro no número oficial e ela se apresenta
    "escreveu_primeiro": {"codigo": None, "escreveu_primeiro": True, "falas": {0: "oi"}},
    "parar": {"codigo": "9038", "negocio": "venda", "falas": {0: "não tenho interesse, me tira dessa lista"}},
}


def rodar(nome: str) -> None:
    c = CENARIOS[nome]
    conn = banco.conectar(autocommit=False)
    try:
        lead = banco.linhas(conn, """
            SELECT l.id, l.telefone, l.nome, l.tratamento FROM captacao_leads l
             WHERE nay_fone_chave(l.telefone) = nay_fone_chave((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste'))""")[0]
        tel = lead["telefone"]
        if c.get("codigo"):
            banco.linhas(conn, f"SELECT captacao_olx_novo({c['codigo']}, %s, %s)", (tel, lead["nome"]))
            banco.linhas(conn, "UPDATE captacao_olx SET anuncio = anuncio || jsonb_build_object('negocio', %s::text) WHERE lead_id = %s",
                         (c["negocio"], lead["id"]))
        banco.linhas(conn, ZERAR, (lead["id"],))
        banco.linhas(conn, "UPDATE captacao_leads SET canal = 'oficial', opt_out = false WHERE id = %s", (lead["id"],))
        banco.linhas(conn, "UPDATE captacao_olx SET respostas = '{}'::jsonb, aberto_em = %s WHERE lead_id = %s",
                     (None if c.get("escreveu_primeiro") else datetime.now(timezone.utc), lead["id"]))
        config.AVISAR_TEL = False   # ensaio nunca avisa o Tel
        abertura = ABERTURA.format(quem=vocativo(lead["tratamento"], lead["nome"]))
        if not c.get("escreveu_primeiro"):
            banco.linhas(conn, """
                INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status, message_id, criada_em)
                VALUES (%s, %s, 'enviada', 'disparo', %s, 'Enviado', 'ensaio', now() - interval '10 minutes')""", (lead["id"], tel, abertura))
        banco.linhas(conn, "UPDATE captacao_leads SET status = 'enviado' WHERE id = %s", (lead["id"],))
        d = banco.linhas(conn, "SELECT codigo, captacao_olx_perfil(lead_id) AS perfil FROM captacao_olx WHERE lead_id = %s", (lead["id"],))[0]
        print(f"=== {nome} | imóvel {d['codigo']} | perfil {d['perfil']} | modelo {config.MODELO}\n")
        print("(o modelo NÃO saiu: ele escreve primeiro)\n" if c.get("escreveu_primeiro") else f"NAY (modelo oficial): {abertura}\n")
        resp = {**PADRAO, **c.get("resp", {})}
        falas = c.get("falas", {})
        acabou = 0
        for i in range(18):
            prox = banco.linhas(conn, "SELECT captacao_olx_proxima(%s) AS p", (tel,))[0]["p"] or {}
            if i in falas:
                fala = falas[i]
            elif i == 0:
                fala = "oi, boa tarde. pode falar"
            elif prox.get("fim"):
                fala, acabou = "obrigado", acabou + 1
            else:
                fala = resp.get(prox.get("campo"), "não sei")
            banco.linhas(conn, """
                INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status, criada_em)
                VALUES (%s, %s, 'recebida', 'texto', %s, 'Recebido py', now() - interval '30 seconds');
                UPDATE captacao_leads SET respondeu_em = coalesce(respondeu_em, now()),
                       status = CASE WHEN status IN ('enviado', 'reservado', 'erro') THEN 'respondendo' ELSE status END
                 WHERE id = %s""", (lead["id"], tel, fala, lead["id"]))
            print("DONO:", fala)
            f = atender(conn, tel, enviar=False, agora=datetime.now(timezone.utc), dormir=lambda s: None)
            for x in f.ferramentas:
                print(f"   -> {x['ferramenta']}({x['args']})")
                print("      <- " + " ".join(str(x["saida"]).split())[:300])
            print("NAY: ", " / ".join(f.baloes) if f.baloes else f"({f.motivo})", "\n")
            estado = banco.linhas(conn, "SELECT humano_assumiu_em IS NOT NULL AS gente, opt_out, motivo_fim FROM captacao_leads WHERE id = %s",
                                  (lead["id"],))[0]
            if estado["gente"] or estado["opt_out"] or acabou >= 1:
                break
        fim = banco.linhas(conn, """
            SELECT l.status, l.motivo_fim, l.humano_assumiu_em IS NOT NULL AS com_gente, l.opt_out, o.respostas,
                   (SELECT count(*) FROM privado.captacao_indicacao i WHERE i.lead_id = l.id) AS indicacoes,
                   (SELECT string_agg(e.assunto, ' | ') FROM captacao_escalacoes e WHERE e.lead_id = l.id AND e.criada_em > now() - interval '5 minutes') AS escaladas
              FROM captacao_leads l JOIN captacao_olx o ON o.lead_id = l.id WHERE l.id = %s""", (lead["id"],))[0]
        print("=== LEAD no fim:", {k: v for k, v in fim.items() if v not in (None, False, 0)})
    finally:
        conn.rollback()
        conn.close()
        print("(tudo desfeito no banco; nenhuma mensagem saiu)\n")


if __name__ == "__main__":
    nome = sys.argv[1] if len(sys.argv) > 1 else "pedro"
    if nome == "todos":
        for n in CENARIOS:
            rodar(n)
    elif nome in CENARIOS:
        rodar(nome)
    else:
        raise SystemExit("cenários: " + ", ".join(CENARIOS) + ", todos")
