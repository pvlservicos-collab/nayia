"""
Doc 29, Etapa A do cron da grade: dispara as vagas que devem rodar
agora. Ainda NÃO está no crontab -- é pra rodar manualmente por
enquanto, pra observar o comportamento antes de qualquer automação:

    .venv/bin/python disparar_grade.py

Reaproveita _postar_codigo (publicador.py) -- a mesma lógica que
processar_comando("posta ...") usa por código -- pra não duplicar
buscar + decidir destinos + montar mensagem por grupo + enviar (doc 27,
Parte 4.3). Também reaproveita vagas_para_disparar (agendador.py, já
testado) pra decidir o que dispara agora.

Timezone: America/Manaus. Não existia nenhum tratamento de timezone
neste projeto antes deste script (conferido: zero menção em todo o
código Python) -- é decisão nova, não uma convenção que já existia.
Faz sentido porque é onde o Tel e a audiência dos grupos estão, e o
histórico registra que o resto do sistema (Nay/n8n) já opera na hora de
Manaus.

Silêncio quando não há nada a fazer: se nenhuma vaga deve disparar no
minuto atual, o script não manda mensagem nenhuma pro Tel -- só
termina. Isso importa porque, uma vez no cron, ele vai rodar a cada
minuto; gerar ruído toda vez que não há nada pra fazer inviabilizaria
o uso real.
"""
import datetime
import os
from zoneinfo import ZoneInfo

import db
from agendador import vagas_para_disparar
from enviar_zapi import enviar_texto
from liberar_vaga import descrever_vaga
from montar_destinos import carregar_grupos_db
from publicador import _postar_codigo

FUSO_MANAUS = ZoneInfo("America/Manaus")

QUERY_VAGAS = (
    "SELECT id, horario, tipo_recorrencia, dias_semana, data_unica, codigos "
    "FROM vagas"
)


def _montar_confirmacao(vaga, resultados):
    linhas = [f"Vaga de {descrever_vaga(vaga)} disparou:"]
    for r in resultados:
        if r["sucesso"]:
            linhas.append(f"- {r['codigo']} ({r['nome_imovel']}): {r['grupos_atingidos']} grupo(s)")
            linhas.extend(f"  {aviso}" for aviso in r["avisos"])
        elif r["grupos_atingidos"] > 0:
            linhas.append(
                f"- {r['codigo']} ({r['nome_imovel']}): postou em {r['grupos_atingidos']} "
                f"grupo(s) antes de falhar -- {r['erro']}"
            )
        else:
            linhas.append(f"- {r['codigo']}: FALHOU -- {r['erro']}")
    return "\n".join(linhas)


def disparar_grade(conexao=None, agora=None, tel_whatsapp=None):
    # falha cedo e claro, antes de qualquer outra coisa -- mesmo padrão
    # do resto do projeto (db.conectar, enviar_zapi._credenciais). Se
    # isso ficasse depois do "sem vaga devida, retorna", uma
    # configuração errada só apareceria na primeira vez que uma vaga
    # de verdade disparasse.
    destino = tel_whatsapp or os.environ.get("TEL_WHATSAPP")
    if not destino:
        raise RuntimeError(
            "TEL_WHATSAPP não configurada no ambiente. Copie .env.example "
            "para .env, preencha o valor, e carregue no ambiente antes de "
            "rodar."
        )

    fechar_ao_sair = conexao is None
    conn = conexao or db.conectar()
    try:
        momento = agora or datetime.datetime.now(FUSO_MANAUS)

        with conn.cursor() as cur:
            cur.execute(QUERY_VAGAS)
            vagas = cur.fetchall()

        devidas = vagas_para_disparar(vagas, momento)
        if not devidas:
            return  # silêncio total -- roda de novo no minuto que vem

        grupos = carregar_grupos_db(conn)
        for vaga in devidas:
            resultados = [_postar_codigo(codigo, grupos, conn) for codigo in vaga["codigos"]]
            confirmacao = _montar_confirmacao(vaga, resultados)
            enviar_texto(destino, confirmacao)
    finally:
        if fechar_ao_sair:
            conn.close()


if __name__ == "__main__":
    disparar_grade()
