"""O serviço: atende quem escreveu e, quando ligado, dispara o modelo que abre a conversa.

DUAS COISAS, no mesmo processo:

1. ATENDER. A cada 2 segundos vê quem escreveu e já ficou em silêncio (a janela de 20 s), e atende. Só existe
   mensagem para ele quando o telefone é do Python (captacao_e_do_python: a lista de teste e quem recebeu o modelo).
   Até 4 conversas ao mesmo tempo, nunca duas vezes a mesma pessoa.
2. DISPARAR. Com `captacao_config.python_disparo = sim`, manda UM modelo por vez para a fila
   (captacao_py_fila_do_disparo), com intervalo sorteado entre python_disparo_seg_min e _seg_max (45 a 75 s: um por
   minuto em média). Quem decide se pode sair é o banco (horário, intervalo, disjuntor, duplicata).

Se um turno falha (modelo fora do ar, banco), o lote volta para a fila e é tentado de novo; na terceira falha
seguida fica em 'Processando' e o erro vai para o registro -- fila parada e visível é melhor que laço infinito.
"""
from __future__ import annotations

import logging
import pathlib
import random
import threading
import time
from concurrent.futures import ThreadPoolExecutor

from captacao import banco, cadastro, config, disparo, olx
from captacao.atender import atender

log = logging.getLogger("captacao.worker")
TENTATIVAS = 3
AO_MESMO_TEMPO = 4
DEVOLVER = """
UPDATE captacao_mensagens SET status = 'Recebido py'
 WHERE nay_fone_chave(telefone) = nay_fone_chave(%s) AND direcao = 'recebida' AND status = 'Processando'
   AND criada_em > now() - interval '30 minutes'
   AND id > coalesce((SELECT max(e.id) FROM captacao_mensagens e
                       WHERE nay_fone_chave(e.telefone) = nay_fone_chave(%s) AND e.direcao = 'enviada'), 0)
"""
# o serviço reiniciou no meio de um turno: o que ficou reservado e sem resposta nos últimos 10 minutos volta à fila
RECUPERAR = """
UPDATE captacao_mensagens m SET status = 'Recebido py'
 WHERE m.direcao = 'recebida' AND m.status = 'Processando' AND m.criada_em > now() - interval '10 minutes'
   AND captacao_e_do_python(m.telefone)
   AND m.id > coalesce((SELECT max(e.id) FROM captacao_mensagens e
                         WHERE nay_fone_chave(e.telefone) = nay_fone_chave(m.telefone) AND e.direcao = 'enviada'), 0)
RETURNING m.id
"""
RITMO = """
SELECT coalesce((SELECT nullif(btrim(valor), '')::numeric FROM captacao_config WHERE chave = 'python_disparo_seg_min'), 45) AS menor,
       coalesce((SELECT nullif(btrim(valor), '')::numeric FROM captacao_config WHERE chave = 'python_disparo_seg_max'), 75) AS maior
"""

_trava = threading.Lock()
_ocupados: set[str] = set()
_falhas: dict[str, int] = {}


def _chave(telefone: str) -> str:
    d = "".join(c for c in telefone if c.isdigit())
    return d[:4] + d[-8:] if len(d) >= 12 else d


def _uma_conversa(telefone: str) -> None:
    """Atende um proprietário, com a sua própria ligação ao banco (roda em linha separada)."""
    conn = None
    try:
        conn = banco.conectar()
        feito = atender(conn, telefone)
        with _trava:
            _falhas.pop(telefone, None)
        log.info("…%s | %s | ferramentas: %s | balões: %d%s", telefone[-4:], feito.motivo or "respondeu",
                 ", ".join(f["ferramenta"] for f in feito.ferramentas) or "-", len(feito.baloes),
                 f" | {feito.falhou_envio} NÃO saíram" if feito.falhou_envio else "")
    except Exception:  # noqa: BLE001 -- um turno ruim não derruba o serviço
        with _trava:
            _falhas[telefone] = n = _falhas.get(telefone, 0) + 1
        log.exception("falhou o turno de …%s (tentativa %d de %d)", telefone[-4:], n, TENTATIVAS)
        try:
            if n < TENTATIVAS:
                outra = banco.conectar()   # a ligação do turno pode ter sido a causa da falha
                try:
                    banco.linhas(outra, DEVOLVER, (telefone, telefone))
                finally:
                    outra.close()
            else:
                with _trava:
                    _falhas.pop(telefone, None)
                log.error("…%s ficou SEM RESPOSTA depois de %d tentativas", telefone[-4:], TENTATIVAS)
        except Exception:  # noqa: BLE001
            log.exception("não consegui devolver o lote de …%s à fila", telefone[-4:])
    finally:
        with _trava:
            _ocupados.discard(_chave(telefone))
        try:
            if conn is not None:
                conn.close()
        except Exception:  # noqa: BLE001
            pass


def ciclo(conn, turma: ThreadPoolExecutor) -> None:
    for linha in banco.linhas(conn, banco.FILA, (config.SILENCIO_S,)):
        tel = linha["telefone"]
        with _trava:
            if _chave(tel) in _ocupados or len(_ocupados) >= AO_MESMO_TEMPO:
                continue
            _ocupados.add(_chave(tel))
        turma.submit(_uma_conversa, tel)


def disparador(parar: threading.Event) -> None:
    """O laço do disparo do modelo. Quem diz se pode sair é o banco; aqui só o ritmo."""
    conn = None
    aprovados_em = 0.0
    while not parar.is_set():
        espera = 10.0
        try:
            if conn is None or conn.closed:
                conn = banco.conectar()
            # 447: o que a Meta aprovou, para o banco soltar o lead que tem modelo próprio (no máximo uma vez por minuto)
            if time.monotonic() - aprovados_em >= 60:
                aprovados_em = time.monotonic()
                novos = disparo.atualizar_aprovados(conn)
                if novos is not None:
                    log.info("modelos aprovados na Meta: %s", novos)
            # a primeira mensagem da Nay proprietários da OLX (370), para quem está liberado em olx_telefones
            try:
                for linha in olx.abridor(conn):
                    log.info("olx: %s", linha)
            except Exception:  # noqa: BLE001 -- a abertura da OLX não para o disparo da captação
                log.exception("a abertura da OLX falhou; tento de novo na próxima volta")
            saida = disparo.proximo(conn)
            if saida:
                ritmo = banco.linhas(conn, RITMO)[0]
                espera = random.uniform(float(ritmo["menor"]), max(float(ritmo["menor"]), float(ritmo["maior"])))
                log.info("disparo: %s | próximo em %.0f s", saida, espera)
        except Exception:  # noqa: BLE001
            log.exception("o disparo falhou; tento de novo em 20 s")
            try:
                if conn is not None:
                    conn.close()
            except Exception:  # noqa: BLE001
                pass
            conn, espera = None, 20.0
        parar.wait(espera)


def atualizador(parar: threading.Event) -> None:
    """O laço que leva a resposta dos donos ao cadastro do imóvel e puxa as fotos da conversa (migração 321)."""
    parar.wait(30)
    while not parar.is_set():
        conn = None
        try:
            conn = banco.conectar()
            for linha in cadastro.rodada(conn):
                log.info("cadastro: %s", linha)
        except Exception:  # noqa: BLE001
            log.exception("a atualização do cadastro falhou; tento de novo na próxima rodada")
        finally:
            try:
                if conn is not None:
                    conn.close()
            except Exception:  # noqa: BLE001
                pass
        parar.wait(config.CADASTRO_A_CADA_S)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
    faltam = [n for n, v in (("DATABASE_URL", config.DATABASE_URL), ("OPENAI_API_KEY", config.OPENAI_API_KEY),
                             ("CAPTACAO_OFICIAL_SEGREDO", config.SEGREDO)) if not v]
    if faltam:
        raise SystemExit("faltam no .env: " + ", ".join(faltam))
    log.info("nay-captacao no ar | modelo %s | silêncio %ds | avisa o Tel: %s | modelo de abertura: %s", config.MODELO,
             config.SILENCIO_S, "sim" if config.AVISAR_TEL else "não", config.MODELO_DE_ABERTURA)
    try:
        inicio = banco.conectar()
        voltaram = banco.linhas(inicio, RECUPERAR)
        placar = banco.linhas(inicio, "SELECT * FROM captacao_py_disparo_placar()")
        inicio.close()
        if voltaram:
            log.warning("%d mensagem(ns) ficaram sem resposta na parada do serviço e voltaram à fila", len(voltaram))
        log.info("disparo do modelo: %s", placar[0] if placar else "?")
    except Exception:  # noqa: BLE001 -- o laço abaixo reconecta
        log.exception("não consegui conferir a fila na partida")
    parar = threading.Event()
    threading.Thread(target=disparador, args=(parar,), name="disparo", daemon=True).start()
    threading.Thread(target=atualizador, args=(parar,), name="cadastro", daemon=True).start()
    conn = None
    with ThreadPoolExecutor(max_workers=AO_MESMO_TEMPO, thread_name_prefix="conversa") as turma:
        while True:
            try:
                if conn is None or conn.closed:
                    conn = banco.conectar()
                ciclo(conn, turma)
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
