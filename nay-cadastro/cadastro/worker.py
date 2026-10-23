"""O serviço: a cada 3 segundos lê o grupo, trata as respostas do privado, começa as conversas da fila e, a cada
minuto, cobra quem não respondeu. Tudo num laço só, uma coisa de cada vez (o volume é de poucos imóveis por dia).

`nai_config.cadastro_whats = 'nao'` para tudo na hora (o que chegou fica esperando; nada se perde).
"""
from __future__ import annotations

import logging
import pathlib
import time

from cadastro import autorizacao, banco, config, fluxo, modelo, no_grupo, no_privado

log = logging.getLogger("cadastro.worker")
PAUSA_DO_MODELO_S = 60
TENTATIVAS_DA_LEVA = 5


class Estado:
    def __init__(self) -> None:
        self.modelo_ate = 0.0
        self.cobrado_em = 0.0
        self.falhas: dict[str, int] = {}


def _levas(conn, est: Estado) -> None:
    for lv in no_grupo.levas_fechadas(conn):
        chave = lv.ids[0]
        try:
            no_grupo.tratar(conn, lv)
            est.falhas.pop(chave, None)
        except modelo.FalhaDoModelo as e:
            est.falhas[chave] = est.falhas.get(chave, 0) + 1
            log.warning("modelo fora ao ler a leva (%s/%s): %s", est.falhas[chave], TENTATIVAS_DA_LEVA, e)
            if est.falhas[chave] >= TENTATIVAS_DA_LEVA:
                banco.linhas(conn, banco.MARCAR_LIDAS, {"ids": lv.ids, "cadastro": None})
                fluxo.avisar_erro(conn, None, "Não consegui ler o imóvel que chegou no grupo (o modelo não respondeu)", e)
            est.modelo_ate = time.monotonic() + PAUSA_DO_MODELO_S
            return
        except Exception as e:  # noqa: BLE001
            log.exception("leva %s", chave)
            banco.linhas(conn, banco.MARCAR_LIDAS, {"ids": lv.ids, "cadastro": None})
            fluxo.avisar_erro(conn, None, "Não consegui tratar o imóvel que chegou no grupo", e)


def ciclo(conn, est: Estado) -> None:
    if not banco.uma(conn, banco.LIGADO)["ligado"]:
        return
    if time.monotonic() >= est.modelo_ate:
        _levas(conn, est)
        no_privado.do_chat_pausado(conn)
        try:
            for _ in range(5):
                if not no_privado.responder(conn):
                    break
        except modelo.FalhaDoModelo as e:
            log.warning("modelo fora ao ler a resposta: %s", e)
            est.modelo_ate = time.monotonic() + PAUSA_DO_MODELO_S
    autorizacao.pedir(conn)           # o pedido ao Tel no grupo sai a qualquer hora; o privado, só no horário
    no_privado.iniciar(conn)
    if time.monotonic() - est.cobrado_em >= 60:
        est.cobrado_em = time.monotonic()
        no_privado.cobrar(conn)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    logging.getLogger("urllib3").setLevel(logging.WARNING)      # a URL da Z-API leva o token: nunca no registro
    est = Estado()
    conn = None
    while True:
        try:
            if conn is None or conn.closed:
                conn = banco.conectar()
                banco.linhas(conn, banco.RECUPERAR)
            ciclo(conn, est)
            pathlib.Path(config.BATIMENTO).write_text(str(int(time.time())))
        except Exception:  # noqa: BLE001
            log.exception("o ciclo falhou; tento de novo")
            try:
                conn.close()
            except Exception:  # noqa: BLE001
                pass
            conn = None
            time.sleep(10)
        time.sleep(3)


if __name__ == "__main__":
    main()
