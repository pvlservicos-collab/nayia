"""Manda o MODELO oficial que abre a conversa (situacao_imovel_cadastrado_1) para UM lead da captação.

    python -m captacao.disparo --lead 835            manda o modelo e registra o disparo
    python -m captacao.disparo --lead 835 --zerar    antes, limpa o que o lead de TESTE já respondeu

TRAVA do comando: só manda para telefone que já é do Python (a lista captacao_config.python_telefones, ou quem já
recebeu o modelo por aqui).

O DISPARO DA FILA (Pedro, 08/10: "prepare tudo para começarmos a disparar ... um a um por minuto em média") é o
`proximo`, chamado pelo serviço: o banco reserva UM lead por vez (captacao_py_reservar_disparo) e só quando
`captacao_config.python_disparo = sim`, dentro do horário e sem duplicata. Desligado, ninguém recebe nada.

O modelo: "Olá, {{1}}! Este é o novo número da Imob Easy. Precisamos atualizar a situação do seu imóvel cadastrado
conosco. Por favor, selecione a opção que corresponde à situação atual:" + botões Disponível / Alugado / Vendido.
{{1}} é o tratamento e o primeiro nome ("Sr. Pedro"), ou só o nome quando não há tratamento.
"""
from __future__ import annotations

import argparse
import sys

from captacao import banco, config, envio
from captacao.turno import primeiro_nome

LEAD = """
SELECT l.id, l.telefone, l.nome, l.tratamento, l.opt_out, l.humano_assumiu_em IS NOT NULL AS com_gente,
       captacao_e_do_python(l.telefone) AS do_python,
       nay_fone_chave(l.telefone) = nay_fone_chave((SELECT valor FROM captacao_config WHERE chave = 'telefone_teste')) AS de_teste
  FROM captacao_leads l WHERE l.id = %s
"""
# o mesmo que o simulador do fluxo faz com o lead de teste antes de cada conversa
ZERAR = """
UPDATE captacao_leads SET situacao = NULL, contrato_ate = NULL, valor_locacao_pedido = NULL, etapa = 'aguardando_situacao',
       tem_outro_imovel = false, quer_vender = false, valor_venda_pedido = NULL, motivo_fim = NULL, fechado_em = NULL,
       pergunta_pendente = NULL, status = 'novo', respondeu_em = NULL, humano_assumiu_em = NULL, humano_motivo = NULL
 WHERE id = %s
"""


NAO_REPETIR = """
INSERT INTO captacao_nao_disparar (telefone_chave, motivo)
SELECT telefone_chave, 'envio sem confirmação do CRM em ' || to_char(now() AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI')
                       || ': conferir na aba Oficial antes de mandar de novo'
  FROM captacao_leads WHERE id = %s
ON CONFLICT (telefone_chave) DO NOTHING
"""


def vocativo(tratamento: str | None, nome: str | None) -> str:
    n = primeiro_nome(nome)
    return " ".join(x for x in ((tratamento or "").strip(), n) if x)


def disparar(conn, lead_id: int, zerar: bool = False) -> str:
    r = banco.linhas(conn, LEAD, (lead_id,))
    if not r:
        return f"não achei o lead {lead_id}"
    lead = r[0]
    if not lead["do_python"]:
        return "RECUSADO: este telefone não está na lista do Python (captacao_config.python_telefones)."
    if lead["opt_out"]:
        return "RECUSADO: este lead pediu para não receber mensagem."
    quem = vocativo(lead["tratamento"], lead["nome"])
    if not quem:
        return "RECUSADO: o lead não tem nome nem tratamento; o modelo sairia 'Olá, !'."
    if zerar:
        if not lead["de_teste"]:
            return "RECUSADO: --zerar só vale para o lead do telefone de teste."
        banco.linhas(conn, ZERAR, (lead_id,))
        banco.linhas(conn, "DELETE FROM captacao_cadastro WHERE lead_id = %s", (lead_id,))
        banco.linhas(conn, "DELETE FROM captacao_imoveis_extra WHERE lead_id = %s", (lead_id,))
    elif lead["com_gente"]:
        return "RECUSADO: alguém da equipe assumiu esta conversa."
    mid, texto, erro = envio.modelo(lead["telefone"], config.MODELO_DE_ABERTURA, config.IDIOMA_DO_MODELO, [quem])
    gravado = banco.linhas(conn, banco.REGISTRAR_DISPARO, {"lead": lead_id, "tel": lead["telefone"], "mid": mid or "",
                                                           "texto": texto or f"[modelo {config.MODELO_DE_ABERTURA}]"})
    if not mid:
        return f"NÃO SAIU: {erro}. O lead ficou como '{gravado[0]['status'] if gravado else '?'}'."
    return f"modelo enviado para …{lead['telefone'][-4:]} ({quem}). Texto: {texto}"


def proximo(conn) -> str | None:
    """Manda o modelo ao próximo da fila, se o banco deixar (captacao_py_reservar_disparo). None = nada a fazer agora."""
    r = banco.linhas(conn, "SELECT * FROM captacao_py_reservar_disparo()")
    if not r:
        return None
    lead = r[0]
    quem = vocativo(lead["tratamento"], lead["nome"])
    if not quem:
        # sem nome o modelo sairia "Olá, !": o lead volta ao que era e sai desta fila, com o motivo
        banco.linhas(conn, """
            WITH v AS (UPDATE captacao_leads SET status = 'novo', atualizado_em = now() WHERE id = %s AND status = 'reservado'
                       RETURNING telefone_chave)
            INSERT INTO captacao_nao_disparar (telefone_chave, motivo) SELECT telefone_chave, 'sem nome para o modelo' FROM v
            ON CONFLICT (telefone_chave) DO NOTHING""", (lead["lead_id"],))
        return f"lead {lead['lead_id']} pulado: sem nome para o modelo"
    mid, texto, erro = envio.modelo(lead["telefone"], config.MODELO_DE_ABERTURA, config.IDIOMA_DO_MODELO, [quem])
    banco.linhas(conn, banco.REGISTRAR_DISPARO, {"lead": lead["lead_id"], "tel": lead["telefone"], "mid": mid or "",
                                                 "texto": texto or f"[modelo {config.MODELO_DE_ABERTURA}]"})
    if not mid:
        if (erro or "").startswith(envio.INCERTO):
            # pode ter saído: este não volta sozinho para a fila (mandar duas vezes é pior que deixar um para conferir)
            banco.linhas(conn, NAO_REPETIR, (lead["lead_id"],))
        return f"NÃO SAIU para o lead {lead['lead_id']} (…{lead['telefone'][-4:]}): {erro}"
    return f"modelo para o lead {lead['lead_id']} (…{lead['telefone'][-4:]}, {quem})"


def main() -> None:
    a = argparse.ArgumentParser(description="Manda o modelo oficial da captação para um lead.")
    a.add_argument("--lead", type=int, required=True)
    a.add_argument("--zerar", action="store_true", help="limpa as respostas do lead de TESTE antes")
    args = a.parse_args()
    conn = banco.conectar()
    try:
        saida = disparar(conn, args.lead, args.zerar)
    finally:
        conn.close()
    print(saida)
    sys.exit(0 if saida.startswith("modelo enviado") else 1)


if __name__ == "__main__":
    main()
