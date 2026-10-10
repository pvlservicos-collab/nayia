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
import os
import pathlib
import sys
import time

from grupos import banco, catalogo, config, extrair, lugares, pontuar, regras

log = logging.getLogger("grupos")


def ler_mensagens(conn, r: dict) -> int:
    """Passo 1 em cada mensagem pendente. Devolve quantos pedidos novos entraram."""
    novos = 0
    for m in banco.linhas(conn, banco.PENDENTES, {"janela": r["janela_h"], "limite": config.POR_CICLO}):
        motivo = extrair.nao_precisa_ler(m["texto"])
        try:
            if motivo:
                banco.marcar_lida(conn, m, 0, motivo=motivo)
            else:
                fichas = extrair.extrair(m["texto"])
                n = banco.gravar_pedidos(conn, m, fichas)
                banco.marcar_lida(conn, m, len(fichas), motivo=None if fichas else "a IA leu e não é pedido de imóvel")
                novos += n
            conn.commit()
        except extrair.FalhaDoModelo as e:
            conn.rollback()
            log.warning("a IA não respondeu para %s %s: %s", m["fonte"], m["ref"], e)
            # fica anotada com o erro e volta à fila em 10 minutos (até 5 vezes); o resto espera a próxima passada
            banco.marcar_lida(conn, m, 0, erro=str(e)[:300])
            conn.commit()
            break
        except Exception:                      # noqa: BLE001 - uma mensagem torta não para as outras
            conn.rollback()
            log.exception("erro ao ler %s %s", m["fonte"], m["ref"])
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
    ultima_conta_geral = 0.0
    regras_de_antes = None
    log.info("nay-grupos no ar: modelo %s, regras em %s", config.MODELO, config.ARQUIVO_DE_REGRAS)
    while True:
        try:
            r, avisos = regras.carregar(config.ARQUIVO_DE_REGRAS)
            refazer = banco.publicar_estado(conn, r, " | ".join(avisos) or None)
            if regras_de_antes is not None and r != regras_de_antes:
                refazer = True                                     # mudou peso, corte ou janela: a conta é outra
            regras_de_antes = r
            if time.time() - ultima_conta_geral > config.REPONTUAR_A_CADA_S:
                refazer = True
            novos = ler_mensagens(conn, r)
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
        time.sleep(config.CICLO_S)


if __name__ == "__main__":
    os.environ.setdefault("TZ", "America/Manaus")
    main()
