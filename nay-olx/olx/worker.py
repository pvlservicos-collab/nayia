"""O serviço: de tempos em tempos cuida dos anúncios e, quando a Nay da OLX existir, do chat.

TRÊS RELÓGIOS, no mesmo laço:
  a cada 5 s      o chat: quem espera resposta (só com `nay_responde = sim`; nasce em `nao`)
                  e o aviso no grupo da equipe de quem escreveu na OLX (só com `avisar_grupo = sim`; olx/grupo.py)
  a cada 5 min    os anúncios: a rodada (só com `publicar = sim`; nasce em `nao`) e a conferência do que foi mandado
  a cada 1 h      a situação de cada anúncio nosso na lista da OLX (expirou, apagaram pelo site)

As chaves são relidas do banco a cada volta: ligar ou desligar pela tela do CRM vale na volta seguinte, sem reiniciar.

QUANDO A OLX DIZ NÃO (sem permissão, sem vaga, bloqueada), o serviço não insiste a cada 5 minutos: espera 6 horas e,
se o motivo era permissão, pergunta com a SONDA (que não publica nada) antes de mandar anúncio de verdade.
"""
from __future__ import annotations

import logging
import pathlib
import time

from olx import anuncios, api, banco, chat, config, grupo, visitas_parceria, whatsapp

log = logging.getLogger("olx.worker")


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
    if not config.DATABASE_URL:
        raise SystemExit("falta no .env: DATABASE_URL")
    # 16/10 (385): a Nay do WhatsApp dos clientes da OLX (8595-6408) numa linha própria: o envio de card e fotos leva
    # minutos e não pode segurar o chat da OLX. Ela só fala com `whatsapp_responde` = teste | sim.
    whatsapp.iniciar()
    # 416 (19/10): a busca de imóvel de parceiro na OLX, noutra linha (abre página no Chrome do PC, leva minutos). Sem o
    # código da aba Grupos (/root/nay-grupos) ou o websocket, só ela fica parada: o resto do serviço segue.
    try:
        from olx import parceiro
        parceiro.iniciar()
    except Exception:  # noqa: BLE001
        log.exception("a busca de parceiro na OLX não iniciou")
    # 475 (22/10): o fluxo de busca do cliente (grupos, base de scrap da OLX, Nay dos corretores), noutra linha
    try:
        from olx import buscas
        buscas.iniciar()
    except Exception:  # noqa: BLE001
        log.exception("o fluxo de busca do cliente não iniciou")
    # 595 (04/11): as campanhas que o Pedro libera à mão (parceiros, donos parados, feedback) e o aviso de baixa, noutra linha
    try:
        from olx import campanhas
        campanhas.iniciar()
    except Exception:  # noqa: BLE001
        log.exception("as campanhas não iniciaram")
    conn = None
    proxima_rodada = 0.0        # a conferência do que foi mandado e a rodada, juntas, a cada 5 min
    espera_ate = 0.0            # a OLX disse não: até aqui a rodada não manda nada (a conferência continua)
    proxima_situacao = 0.0
    proxima_retirada = 0.0      # 24/10: o vendido/alugado sai da OLX a cada minuto, com ou sem `publicar`
    espera_retirada = 0.0
    ultimo_estado = ""
    while True:
        try:
            if conn is None or conn.closed:
                conn = banco.conectar()
            cfg = banco.chaves(conn)
            estado = (f"publicar={cfg.get('publicar')} conta={cfg.get('conta_que_publica') or '-'} teto={cfg.get('teto')} "
                      f"permissao={cfg.get('permissao') or '?'} nay_responde={cfg.get('nay_responde')}")
            if estado != ultimo_estado:
                log.info("nay-olx | %s", estado)
                # alguém mexeu numa chave (ligou, trocou a conta, subiu o teto): a espera do "não" deixa de valer
                if ultimo_estado and estado.split(" permissao=")[0] != ultimo_estado.split(" permissao=")[0]:
                    espera_ate = 0.0
                ultimo_estado = estado

            chat.atender_fila(conn, cfg)
            # 396: o anúncio pedido no popup do editar imóvel sai na hora
            try:
                anuncios.publicar_pedidos(conn)
            except Exception:  # noqa: BLE001 -- o pedido não pode parar o chat nem os anúncios
                log.exception("o pedido de anúncio falhou")
            # 15/10: quem escreve na OLX aparece no grupo da equipe (avisar_grupo = sim)
            try:
                grupo.avisar(conn, cfg)
            except Exception:  # noqa: BLE001 -- o aviso não pode parar o chat nem os anúncios
                log.exception("o aviso ao grupo falhou")
            # 20/10 (444): o checklist da visita da Parceria e os avisos do proprietário no grupo da equipe
            try:
                visitas_parceria.atender(conn, cfg)
            except Exception:  # noqa: BLE001 -- o checklist não pode parar o chat nem os anúncios
                conn.rollback()
                log.exception("o checklist das visitas falhou")

            agora = time.time()
            if agora >= proxima_retirada and agora >= espera_retirada:
                proxima_retirada = agora + config.RETIRADA_A_CADA_S
                try:
                    if anuncios.retirar_encerrados(conn, cfg).get("nao"):
                        espera_retirada = agora + 1800     # a OLX disse não: tenta de novo em meia hora
                except api.ErroDaOlx as e:
                    log.warning("retirada: %s", e)
                except Exception:  # noqa: BLE001 -- a retirada não pode parar o chat
                    conn.rollback()
                    log.exception("a retirada dos anúncios falhou")
            if agora >= proxima_rodada:
                proxima_rodada = agora + config.ANUNCIOS_A_CADA_S
                try:
                    anuncios.conferir(conn)
                    if cfg.get("publicar") == "sim" and agora >= espera_ate:
                        # a última resposta foi "sem permissão": pergunta com a sonda antes de mandar anúncio de verdade
                        if cfg.get("permissao") == "sem_permissao" and cfg.get("conta_que_publica"):
                            r = anuncios.sondar(conn, cfg["conta_que_publica"])
                            log.info("sonda: %s", r.mensagem)
                            resultado = {"nao": True} if r.permissao != "ok" else anuncios.rodada(conn, banco.chaves(conn))
                        else:
                            resultado = anuncios.rodada(conn, cfg)
                        if resultado.get("nao"):
                            espera_ate = agora + config.ESPERA_DEPOIS_DO_NAO_S
                            log.warning("a OLX disse não; a próxima tentativa é em %d h", config.ESPERA_DEPOIS_DO_NAO_S // 3600)
                except api.ErroDaOlx as e:
                    log.warning("anúncios: %s", e)
            if agora >= proxima_situacao:
                proxima_situacao = agora + config.SITUACAO_A_CADA_S
                try:
                    vistos = anuncios.situacao(conn)
                    if vistos:
                        log.info("situação: %d anúncio(s) nossos na lista da OLX", vistos)
                except api.ErroDaOlx as e:
                    log.warning("situação: %s", e)
            pathlib.Path(config.BATIMENTO).touch()
        except Exception:  # noqa: BLE001 -- banco fora do ar ou erro inesperado: espera e reconecta
            log.exception("o ciclo falhou; reconecto em 30 s")
            try:
                if conn is not None:
                    conn.close()
            except Exception:  # noqa: BLE001
                pass
            conn = None
            time.sleep(30)
        time.sleep(config.CHAT_A_CADA_S)


if __name__ == "__main__":
    main()
