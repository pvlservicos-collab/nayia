"""Ensaio: uma conversa inteira com o lead de TESTE, com o modelo e o banco de verdade, sem enviar nada.

    python -m captacao.ensaio disponivel
    python -m captacao.ensaio alugado
    python -m captacao.ensaio vendido
    python -m captacao.ensaio ja_temos      o imóvel dele já está no nosso cadastro (318): só o valor, e segue

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
    "vendido": ["Vendido", "tenho sim, uma casa no Tarumã pra vender", "3 quartos, 2 banheiros e 4 vagas",
                "uns 300 metros de terreno", "quero 650 mil", "agora não posso mandar mais nada, depois falo", "ninguém, obrigado"],
    "pergunta": ["Disponível", "quanto vocês cobram de comissão?"],
    "ja_temos": ["Disponível", "3.200", "não, só esse mesmo", "não conheço ninguém", "obrigado"],
    "parar": ["não quero receber mensagem, me tira dessa lista"],
}


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
        if cenario == "ja_temos":
            # o imóvel de um lead da fila, que existe no cadastro, emprestado ao lead de teste até o ROLLBACK
            dele = banco.linhas(conn, """
                UPDATE captacao_leads t SET codigo = o.codigo, imovel_desc = o.imovel_desc, condominio = o.condominio,
                       bairro = o.bairro, tipo_imovel = o.tipo_imovel, imoveis_prop = o.imoveis_prop
                  FROM (SELECT l.* FROM captacao_leads l
                         WHERE l.id IN (SELECT captacao_py_fila_do_disparo())
                           AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo::text = l.codigo)
                         ORDER BY l.id LIMIT 1) o
                 WHERE t.id = %s RETURNING t.codigo, t.imovel_desc""", (lead["id"],))
            print("imóvel emprestado ao lead de teste:", dele[0] if dele else "NENHUM (a fila está vazia?)")
        config.AVISAR_TEL = False   # ensaio nunca avisa o Tel
        abertura = ABERTURA.format(quem=vocativo(lead["tratamento"], lead["nome"]))
        banco.linhas(conn, banco.REGISTRAR_DISPARO, {"lead": lead["id"], "tel": tel, "mid": "ensaio", "texto": abertura})
        print(f"=== cenário {cenario} | modelo {config.MODELO} | lead de teste {lead['id']}\n")
        print("NAY (modelo oficial):", abertura, "[Disponível] [Alugado] [Vendido]\n")
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
            SELECT situacao, contrato_ate, valor_locacao_pedido, etapa, tem_outro_imovel, quer_vender, motivo_fim, status,
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
