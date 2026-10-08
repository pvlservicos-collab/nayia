"""O serviço: a cada 2 segundos vê quem escreveu e já ficou em silêncio, e atende.

Só existe mensagem para ele quando o telefone está na lista do Python (captacao_config.python_telefones, migração
315): o resto continua sendo do fluxo do n8n. Um proprietário de cada vez, como o laço de balões do fluxo.

Se um turno falha (modelo fora do ar, banco), o lote volta para a fila e é tentado de novo; na terceira falha
seguida fica em 'Processando' e o erro vai para o registro -- fila parada e visível é melhor que laço infinito.
"""
from __future__ import annotations

import logging
import pathlib
import time

from captacao import banco, config
from captacao.atender import atender

log = logging.getLogger("captacao.worker")
TENTATIVAS = 3
DEVOLVER = """
UPDATE captacao_mensagens SET status = 'Recebido py'
 WHERE nay_fone_chave(telefone) = nay_fone_chave(%s) AND direcao = 'recebida' AND status = 'Processando'
   AND criada_em > now() - interval '30 minutes'
   AND id > coalesce((SELECT max(e.id) FROM captacao_mensagens e
                       WHERE nay_fone_chave(e.telefone) = nay_fone_chave(%s) AND e.direcao = 'enviada'), 0)
"""


def ciclo(conn, falhas: dict[str, int]) -> None:
    for linha in banco.linhas(conn, banco.FILA, (config.SILENCIO_S,)):
        tel = linha["telefone"]
        try:
            feito = atender(conn, tel)
            falhas.pop(tel, None)
            log.info("…%s | %s | ferramentas: %s | balões: %d%s", tel[-4:], feito.motivo or "respondeu",
                     ", ".join(f["ferramenta"] for f in feito.ferramentas) or "-", len(feito.baloes),
                     f" | {feito.falhou_envio} NÃO saíram" if feito.falhou_envio else "")
        except Exception:  # noqa: BLE001 -- um turno ruim não derruba o serviço
            falhas[tel] = falhas.get(tel, 0) + 1
            log.exception("falhou o turno de …%s (tentativa %d de %d)", tel[-4:], falhas[tel], TENTATIVAS)
            if falhas[tel] < TENTATIVAS:
                banco.linhas(conn, DEVOLVER, (tel, tel))
            else:
                falhas.pop(tel, None)
                log.error("…%s ficou SEM RESPOSTA depois de %d tentativas", tel[-4:], TENTATIVAS)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
    faltam = [n for n, v in (("DATABASE_URL", config.DATABASE_URL), ("OPENAI_API_KEY", config.OPENAI_API_KEY),
                             ("CAPTACAO_OFICIAL_SEGREDO", config.SEGREDO)) if not v]
    if faltam:
        raise SystemExit("faltam no .env: " + ", ".join(faltam))
    log.info("nay-captacao no ar | modelo %s | silêncio %ds | avisa o Tel: %s", config.MODELO, config.SILENCIO_S,
             "sim" if config.AVISAR_TEL else "não")
    conn, falhas = None, {}
    while True:
        try:
            if conn is None or conn.closed:
                conn = banco.conectar()
            ciclo(conn, falhas)
            pathlib.Path(config.BATIMENTO).touch()
        except Exception:  # noqa: BLE001 -- banco fora do ar: espera e reconecta
            log.exception("o ciclo falhou; reconecto em 10 s")
            try:
                if conn is not None:
                    conn.close()
            except Exception:  # noqa: BLE001
                pass
            conn = None
            time.sleep(10)
        time.sleep(2)


if __name__ == "__main__":
    main()
