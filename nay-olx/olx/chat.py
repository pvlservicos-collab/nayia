"""O chat da OLX, do jeito que a Nay da OLX vai usar.

Pedro, 13/10/2026: "futuramente vou criar uma nay só para responder na olx então já deixa as funções prontas".

A mensagem do cliente ENTRA pelo CRM (o webhook que a OLX chama grava em `privado.olx_chat`); a tela Chat OLX mostra.
Estas são as funções para RESPONDER SEM GENTE:

  fila(conn)                         as conversas que esperam resposta (o banco decide: olx_nay_fila)
  contexto(conn, chat)               quem escreveu, de qual anúncio, o imóvel e a conversa inteira
  responder(conn, chat, texto)       manda no chat da OLX e grava na conversa (aparece no CRM na hora)
  passar_para_gente(conn, chat, m)   a Nay não sabe ou não deve responder: a conversa fica com a equipe
  devolver(conn, chat)               a equipe devolve a conversa para a Nay
  atender_fila(conn, cfg)            o laço: pega a fila, pergunta à Nay (olx/nay.py) e responde

AS REGRAS (no banco, migração 364):
  · só entra na fila a conversa em que a ÚLTIMA mensagem é do cliente e já passaram `nay_silencio_s` segundos;
  · gente respondeu (pelo CRM ou pelo site da OLX), a Nay fica quieta naquela conversa por `humano_cala_horas`;
  · uma conversa é respondida por um de cada vez (olx_nay_reservar; a reserva vence em 5 minutos);
  · nada disso anda com `nay_responde = nao`, que é como nasce.

Pela linha de comando (no servidor, com o .env carregado):
  python -m olx.chat fila
  python -m olx.chat contexto 12
  python -m olx.chat responder 12 "Olá! Está disponível, sim."     manda DE VERDADE no chat da OLX
  python -m olx.chat gente 12 "pediu desconto"   |   python -m olx.chat devolver 12
"""
from __future__ import annotations

import json
import logging
import secrets
import sys
import time

from olx import api, banco, config, grupo, modelo, nay

log = logging.getLogger("olx.chat")


def fila(conn, limite: int = 10) -> list[dict]:
    return banco.linhas(conn, "SELECT * FROM olx_nay_fila(%s)", (limite,))


def contexto(conn, chat: int) -> dict | None:
    return banco.um(conn, "SELECT olx_nay_contexto(%s)", (chat,))


def responder(conn, chat: int, texto: str, quem: str | None = None) -> str:
    """Manda `texto` na conversa e grava. Devolve o id da mensagem. Se a OLX recusar, levanta ErroDaOlx e NADA é gravado."""
    texto = (texto or "").strip()
    if not texto:
        raise ValueError("resposta vazia")
    l = banco.linhas(conn, "SELECT conta, chat_id FROM privado.olx_chat WHERE id = %s", (chat,))
    if not l:
        raise ValueError(f"a conversa {chat} não existe")
    conta, chat_id = l[0]["conta"], l[0]["chat_id"]
    token = banco.token_da_conta(conn, conta)
    if not token:
        raise api.ErroDaOlx(f"a conta {conta} não está conectada à OLX")
    message_id = f"nay-{int(time.time() * 1000)}-{secrets.token_hex(6)}"
    saiu, motivo = api.enviar_no_chat(token, chat_id, texto[:2000], message_id)
    if not saiu:
        raise api.ErroDaOlx(f"a mensagem NÃO foi enviada: {motivo}")
    banco.um(conn, "SELECT crm_olx_chat_enviada(%s, %s, %s, %s, %s)", (conta, chat, message_id, texto[:2000], quem or config.QUEM_RESPONDE))
    return message_id


def passar_para_gente(conn, chat: int, motivo: str) -> None:
    banco.um(conn, "SELECT olx_nay_passar_para_gente(%s, %s)", (chat, motivo))


def devolver(conn, chat: int) -> None:
    banco.um(conn, "SELECT olx_nay_devolver(%s)", (chat,))


# a última mensagem do cliente que a Nay já leu sem ter o que dizer ("ok", "obrigado"): sem isto a conversa continua
# na fila (a última é do cliente) e o modelo seria chamado de novo a cada 5 s
_lida_sem_resposta: dict[int, str] = {}


def _avisar(texto: str) -> None:
    try:
        if not grupo.mandar_ao_grupo(texto):
            log.warning("o aviso não chegou ao grupo: nenhum número conectado")
    except Exception:  # noqa: BLE001 -- o aviso não pode derrubar o atendimento
        log.exception("o aviso ao grupo falhou")


def _avisar_tel(conn, texto: str) -> None:
    """16/10: o recado no WhatsApp do Tel (o número dele é o do banco, nai_cfg('tel_telefone'))."""
    try:
        if not grupo.mandar_ao_tel(banco.um(conn, "SELECT nai_cfg('tel_telefone')"), texto):
            log.warning("o recado ao Tel não chegou: nenhum número conectado")
    except Exception:  # noqa: BLE001 -- o recado não pode derrubar o atendimento
        log.exception("o recado ao Tel falhou")


def _guardar_lead(conn, chat: int, decisao) -> None:
    """16/10 (384): quem deu o WhatsApp fica guardado com a leitura de perfil, para a Nay do WhatsApp (número de
    captação) continuar de onde a da OLX parou. Falhar aqui não derruba o atendimento."""
    if not (decisao and decisao.lead):
        return
    try:
        l = decisao.lead
        banco.um(conn, "SELECT olx_nay_lead_whatsapp(%s, %s, %s, %s, %s::jsonb)",
                 (chat, l.get("nome") or None, l["telefone"], bool(l.get("quer_visita")),
                  json.dumps(l.get("perfil") or {}, ensure_ascii=False)))
    except Exception:  # noqa: BLE001
        log.exception("conversa %s: o perfil do lead não foi guardado", chat)


def atender_fila(conn, cfg: dict[str, str]) -> int:
    """Uma passada pela fila. Devolve quantas conversas foram respondidas ou passadas para gente."""
    if cfg.get("nay_responde") != "sim":
        return 0
    feitas = 0
    for c in fila(conn):
        chat = int(c["chat"])
        marca = f"{c.get('ultima_em')}"
        if _lida_sem_resposta.get(chat) == marca:
            continue
        if not banco.um(conn, "SELECT olx_nay_reservar(%s, %s)", (chat, "nay-olx")):
            continue                                    # outro já pegou
        ctx = None
        decisao = None
        try:
            ctx = contexto(conn, chat)

            # o catálogo ajuda o modelo: a MESMA `nai_resposta_da_base` que responde o corretor no WhatsApp
            def responder_duvida(codigo: int, pergunta: str) -> str | None:
                return banco.um(conn, "SELECT nai_resposta_da_base(%s, %s)", (codigo, pergunta))

            decisao = nay.decidir(ctx, responder_duvida, modelo.chamar) if ctx else None
            if decisao is None:
                _lida_sem_resposta[chat] = marca        # nada a dizer: espera a próxima mensagem do cliente
                continue
            for n, balao in enumerate(decisao.baloes):
                if n:
                    time.sleep(1.5)
                responder(conn, chat, balao)
            if decisao.baloes:
                log.info("conversa %s respondida (%d balão/ões)", chat, len(decisao.baloes))
            if decisao.passar_para_gente:
                passar_para_gente(conn, chat, decisao.passar_para_gente)
                log.info("conversa %s passada para gente: %s", chat, decisao.passar_para_gente)
            _guardar_lead(conn, chat, decisao)
            # 16/10: a pessoa não quer o WhatsApp -> nada sai para ela, e o Tel fica sabendo
            if decisao.aviso_tel:
                _avisar_tel(conn, decisao.aviso_tel)
            # no grupo vai SÓ o nome e o número de quem mandou o contato (Pedro, 15/10); o resto fica no CRM
            if decisao.aviso_grupo:
                _avisar(decisao.aviso_grupo)
            feitas += 1
        except (api.ErroDaOlx, modelo.FalhaDoModelo) as e:
            # A NAY NÃO CONSEGUIU FALAR -> A CONVERSA VAI PARA A EQUIPE, NA HORA (aparece no CRM).
            # Sem isto ela volta para a fila e é tentada de novo a cada 5 s, para sempre: em 14/10 a OLX devolveu
            # 403 (embrulhado num 500) e foram 8 tentativas em 20 segundos antes de alguém ver.
            quem = "a OLX recusou o envio" if isinstance(e, api.ErroDaOlx) else "o modelo não respondeu"
            log.warning("conversa %s: %s: %s", chat, quem, e)
            try:
                passar_para_gente(conn, chat, f"{quem}: {e}")
            except Exception:                      # noqa: BLE001
                log.exception("conversa %s: não consegui nem passar para gente", chat)
            # o lead já tinha dado o contato: o nome e o número vão ao grupo assim mesmo, e o perfil fica guardado
            if decisao and decisao.aviso_grupo:
                _avisar(decisao.aviso_grupo)
            _guardar_lead(conn, chat, decisao)
        finally:
            banco.um(conn, "SELECT olx_nay_soltar(%s)", (chat,))
    return feitas


def main(argv: list[str]) -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
    comando = argv[0] if argv else "fila"
    conn = banco.conectar()
    try:
        if comando == "fila":
            cfg = banco.chaves(conn)
            itens = fila(conn, 50)
            print(f"nay_responde = {cfg.get('nay_responde')} | {len(itens)} conversa(s) esperando resposta")
            for c in itens:
                print(f"  {c['chat']:>5} {c['conta']:14} anúncio {c['list_id'] or '?':12} {c['nome'] or 'sem nome'}: {(c['ultima_texto'] or '')[:80]}")
        elif comando == "contexto":
            print(json.dumps(contexto(conn, int(argv[1])), ensure_ascii=False, indent=2, default=str))
        elif comando == "ensaio":
            # o que a Nay diria agora nessa conversa, com o modelo de verdade, SEM mandar nada nem mudar a conversa
            ctx = contexto(conn, int(argv[1]))
            d = nay.decidir(ctx, lambda cod, p: banco.um(conn, "SELECT nai_resposta_da_base(%s, %s)", (cod, p)),
                            modelo.chamar) if ctx else None
            print(json.dumps(d.__dict__ if d else None, ensure_ascii=False, indent=2))
        elif comando == "responder":
            print("enviada:", responder(conn, int(argv[1]), argv[2], argv[3] if len(argv) > 3 else None))
        elif comando == "gente":
            passar_para_gente(conn, int(argv[1]), argv[2] if len(argv) > 2 else "pela linha de comando")
            print("a conversa ficou com a equipe")
        elif comando == "devolver":
            devolver(conn, int(argv[1]))
            print("a conversa voltou para a Nay")
        else:
            print(__doc__)
            return 2
        return 0
    finally:
        conn.close()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
