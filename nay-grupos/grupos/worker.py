"""O serviço: a cada passada lê o que chegou dos grupos, extrai os pedidos, pontua e grava. NUNCA envia.

    python -m grupos.worker              o serviço (systemd: nay-grupos.service)
    python -m grupos.worker --uma-vez    uma passada só, e sai (para conferir depois de publicar)

Pedro, 09/10/2026: modo TREINO -- "lê as solicitações de TODOS os grupos das últimas 48h, extrai, pontua e
mostra na tela. NUNCA envia mensagem." O envio não está neste arquivo nem em lugar nenhum: ver envio.py.

A cada passada:
  1. relê config.json (pesos, cortes, janela) e publica na tabela de estado, para a tela mostrar;
  2. pega as mensagens ainda não lidas (do grupo e as coladas na tela) e passa cada uma pela IA;
  3. pontua os pedidos sem conta; refaz a conta da janela inteira quando um apelido muda, quando o arquivo
     de regras muda e de 10 em 10 minutos (o catálogo muda: imóvel sai, valor muda).
"""
from __future__ import annotations

import datetime
import logging
from concurrent.futures import ThreadPoolExecutor
import os
import pathlib
import sys
import time

from grupos import banco, catalogo, config, extrair, lugares, pontuar, regras

log = logging.getLogger("grupos")


def _ler_uma(texto: str):
    """A chamada à IA de uma mensagem, para rodar em paralelo: devolve as fichas ou o erro (nunca levanta)."""
    try:
        return extrair.extrair(texto)
    except Exception as e:                     # noqa: BLE001 - o erro volta como valor, para a linha ser anotada
        return e


def ler_mensagens(conn, r: dict, turma: ThreadPoolExecutor) -> int:
    """Passo 1 em cada mensagem pendente. Devolve quantos pedidos novos entraram.

    A IA lê várias ao mesmo tempo (a conversa exportada de 2 dias traz centenas de mensagens); a gravação é
    uma de cada vez. Mensagem que a IA não conseguiu ler fica anotada com o erro e volta à fila em 10 minutos
    (até 5 vezes).
    """
    pendentes = banco.linhas(conn, banco.PENDENTES, {"janela": r["janela_h"], "limite": config.POR_CICLO})
    # o teto do dia: cada leitura custa. Passou, a mensagem de grupo espera na fila; o teste colado na tela não conta.
    sobra = r["limite_de_leituras_por_dia"] - banco.linhas(conn, banco.LEITURAS_DE_HOJE)[0]["n"]
    conn.rollback()                            # a leitura acabou: nada fica aberto enquanto a IA trabalha
    motivos = {m["ref"]: extrair.nao_precisa_ler(m["texto"]) for m in pendentes}
    dentro = []
    for m in pendentes:
        if m["fonte"] == "grupo" and not motivos[m["ref"]]:
            if sobra <= 0:
                continue                       # fica na fila para amanhã
            sobra -= 1
        dentro.append(m)
    pendentes = dentro
    leituras = {m["ref"]: turma.submit(_ler_uma, m["texto"]) for m in pendentes if not motivos[m["ref"]]}
    novos = 0
    for m in pendentes:
        try:
            if motivos[m["ref"]]:
                banco.marcar_lida(conn, m, 0, motivo=motivos[m["ref"]], pela_ia=False)
            else:
                fichas = leituras[m["ref"]].result()
                if isinstance(fichas, Exception):
                    log.warning("a IA não leu %s %s: %s", m["fonte"], m["ref"], fichas)
                    banco.marcar_lida(conn, m, 0, erro=str(fichas)[:300])
                else:
                    novos += banco.gravar_pedidos(conn, m, fichas)
                    banco.marcar_lida(conn, m, len(fichas), motivo=None if fichas else "a IA leu e não é pedido de imóvel")
            conn.commit()
        except Exception:                      # noqa: BLE001 - uma mensagem torta não para as outras
            conn.rollback()
            log.exception("erro ao gravar a leitura de %s %s", m["fonte"], m["ref"])
            banco.marcar_lida(conn, m, 0, erro="erro ao gravar a leitura")
            conn.commit()
    return novos


def pontuar_pedidos(conn, r: dict, todos: bool) -> int:
    """Passos 2 a 4 nos pedidos da janela. Devolve quantos foram pontuados."""
    pedidos = banco.linhas(conn, banco.A_PONTUAR, {"janela": r["janela_h"], "todos": todos})
    if not pedidos:
        return 0
    imoveis, vizinhos = catalogo.carregar(conn)
    nomes = lugares.Lugares(conn)
    limite = datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=r["confirmado_dias"])
    for q in pedidos:
        pedido, local, duvidosos = lugares.resolver(q["ficha"], q["grupo_nome"], nomes)
        resultado = pontuar.melhores(pedido, imoveis, r, vizinhos, limite)
        pares = [{**p, "imovel": catalogo.para_a_tela(p["imovel"])} for p in resultado["pares"]]
        faixa = pontuar.faixa_da(pares[0]["nota"], r) if pares else None
        local["passaram"] = resultado.get("passaram", 0)
        banco.gravar_conta(conn, q["id"], local, duvidosos, resultado, faixa, pares)
    conn.commit()
    return len(pedidos)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    uma_vez = "--uma-vez" in sys.argv
    if not config.DATABASE_URL or not config.OPENAI_API_KEY:
        raise SystemExit("faltam DATABASE_URL e OPENAI_API_KEY no ambiente (.env)")
    conn = banco.conectar()
    turma = ThreadPoolExecutor(max_workers=config.AO_MESMO_TEMPO, thread_name_prefix="ia")
    ultima_conta_geral = 0.0
    regras_de_antes = None
    log.info("nay-grupos no ar: modelo %s, regras em %s", config.MODELO, config.ARQUIVO_DE_REGRAS)
    while True:
        tem_fila = novos_ou_lidos = False
        try:
            r, avisos = regras.carregar(config.ARQUIVO_DE_REGRAS)
            lidas_hoje = banco.linhas(conn, banco.LEITURAS_DE_HOJE)[0]["n"]
            if lidas_hoje >= r["limite_de_leituras_por_dia"]:
                avisos.append(f"a IA já leu {lidas_hoje} mensagens de grupo hoje, que é o teto do dia: as novas esperam na fila "
                              "até amanhã (ou até o teto subir em config.json)")
            refazer = banco.publicar_estado(conn, r, " | ".join(avisos) or None)
            if regras_de_antes is not None and r != regras_de_antes:
                refazer = True                                     # mudou peso, corte ou janela: a conta é outra
            regras_de_antes = r
            if time.time() - ultima_conta_geral > config.REPONTUAR_A_CADA_S:
                refazer = True
            antes = banco.linhas(conn, "SELECT count(*) AS n FROM privado.grupo_mensagem_lida")[0]["n"]
            novos = ler_mensagens(conn, r, turma)
            novos_ou_lidos = banco.linhas(conn, "SELECT count(*) AS n FROM privado.grupo_mensagem_lida")[0]["n"] > antes
            # com fila (e andando), a passada seguinte começa logo (não espera os 10 s)
            tem_fila = bool(banco.linhas(conn, "SELECT 1 FROM (" + banco.PENDENTES + ") f LIMIT 1",
                                         {"janela": r["janela_h"], "limite": 1}))
            feitos = pontuar_pedidos(conn, r, todos=refazer)
            if refazer:
                ultima_conta_geral = time.time()
            if novos or (feitos and not refazer):
                log.info("pedidos novos: %s; pontuados: %s", novos, feitos)
            conn.rollback()        # fecha a transação das leituras: o serviço não dorme com transação aberta
            pathlib.Path(config.BATIMENTO).touch()
        except Exception:                      # noqa: BLE001 - o laço não morre; reconecta e segue
            log.exception("erro no ciclo")
            try:
                conn.close()
            except Exception:                  # noqa: BLE001
                pass
            time.sleep(10)
            conn = banco.conectar()
        if uma_vez:
            break
        time.sleep(1 if (tem_fila and novos_ou_lidos) else config.CICLO_S)


if __name__ == "__main__":
    os.environ.setdefault("TZ", "America/Manaus")
    main()
