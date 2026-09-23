#!/usr/bin/env python3
"""
Re-executa os casos de treino pelo FLUXO REAL do n8n.

Tel (19/09/2026): "nao quero que vc refaca o fluxo, quero que rode o fluxo
real -- so vai substituir o whatsapp por informacoes que vc mesmo vai mandar,
as conversas que ja tivemos e a ia ja atendeu".

Entao este script NAO reimplementa o agente. Ele so faz o que o WhatsApp
fazia: entrega uma mensagem no webhook do n8n. Prompt, modelo, ferramentas,
memoria, conferencias e caixa de saida sao os mesmos da producao.

    WhatsApp  ->  webhook  ->  [ fluxo NAI, intocado ]  ->  nai_saida
    este .py  ->  webhook  ->  [       o mesmo        ]  ->  nai_saida

NADA SAI PARA O WHATSAPP. A trava e `nai_config.envio_simulado='sim'`:
`nai_liberar_saida` marca a linha como 'simulado', guarda o texto final e
nao devolve nada para o no "Enviar Z-API". O script SE RECUSA A RODAR se
essa chave nao estiver ligada -- a verificacao esta em `conferir_travas()`
e nao tem bandeira para pular.

Uso, no servidor:
    python3 nai_treino_rodar.py --ciclo 1
    python3 nai_treino_rodar.py --ciclo 1 --limite 5      # experimenta em 5
    python3 nai_treino_rodar.py --listar                  # so mostra o pool
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

import psycopg2
import psycopg2.extras

# O n8n NAO publica porta no host: ele existe so dentro da rede
# `n8n-viux_default`. Do host, o endereco e o IP do container na bridge --
# `127.0.0.1:5678` nao responde, e foi o primeiro chute errado. Confirme com
#   docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' n8n-viux-n8n-1
# se um dia o container for recriado e mudar de IP.
WEBHOOK_PADRAO = "http://172.16.0.2:5678/webhook/nai-atendimento-locacao"

# O numero do espelho. NAO e de ninguem: prefixo 5599 9 + 0000 + sufixo, fora
# de qualquer faixa real de Manaus (92) ou Macapa (96). Ele existe para que a
# memoria, o contato e a visita da simulacao nunca encostem na conversa de uma
# pessoa de verdade -- e para que, se alguma coisa escapar, escape para um
# numero que nao toca em lugar nenhum.
ESPELHO_PADRAO = "559990000001"
ESPELHO_NOME = "Treino (espelho)"

# Quanto esperar o fluxo. A "Janela de 25s" do n8n segura a mensagem para
# juntar as que vem coladas; depois vem o modelo e as ferramentas. Nao e
# sleep fixo: poll ate o turno fechar, com teto.
ESPERA_TETO_S = 180
ESPERA_PASSO_S = 3


# ---------------------------------------------------------------- banco --
def conectar():
    url = os.environ.get("DATABASE_URL") or os.environ.get("NAI_DATABASE_URL")
    if not url:
        sys.exit("faltou DATABASE_URL no ambiente")
    c = psycopg2.connect(url)
    c.autocommit = True
    return c


def um(conn, sql, params=None):
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, params or ())
        return cur.fetchone()


def varios(conn, sql, params=None):
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, params or ())
        return cur.fetchall()


def executar(conn, sql, params=None):
    with conn.cursor() as cur:
        cur.execute(sql, params or ())


# ---------------------------------------------------------------- travas --
def conferir_travas(conn, espelho):
    """A porta de seguranca. Sem isto o fluxo mandaria mensagem de verdade.

    Nao existe --forcar. Se uma destas nao estiver do jeito certo, a unica
    saida e arrumar a configuracao -- de proposito.
    """
    cfg = {r["chave"]: r["valor"] for r in
           varios(conn, "SELECT chave, valor FROM nai_config")}

    problemas = []
    # A TRAVA PODE VIR DO DESTINO (92): com a Nay no ar, `envio_simulado` fica
    # 'nao' -- liga-la calaria os corretores de verdade. Entao vale tambem a
    # protecao do espelho dentro da caixa de saida: tudo que vai para ele fica
    # em 'simulado' de qualquer jeito. Uma das duas basta; nenhuma, nao roda.
    espelho_protegido = um(conn,
        "SELECT pg_get_functiondef('nai_liberar_saida'::regproc) ~ 'ESPELHO DO TREINO NUNCA SAI' AS ok")["ok"]
    if cfg.get("envio_simulado") != "sim" and not espelho_protegido:
        problemas.append(
            "nai_config.envio_simulado = %r, precisa ser 'sim'.\n"
            "    Sem isso a Z-API E CHAMADA DE VERDADE e o corretor recebe a\n"
            "    mensagem da simulacao. Ligue com:\n"
            "      UPDATE nai_config SET valor='sim' WHERE chave='envio_simulado';"
            % cfg.get("envio_simulado"))

    if cfg.get("modo") not in ("teste", "todos"):
        problemas.append("nai_config.modo = %r -- a NAI esta desligada e o "
                         "turno nem abre." % cfg.get("modo"))

    if cfg.get("pausada") != "nao":
        problemas.append("nai_config.pausada = %r -- nada vai ser montado."
                         % cfg.get("pausada"))

    # O espelho precisa passar o porteiro. Em modo teste, quem nao esta em
    # numeros_teste leva 'fora_do_teste' e o turno nao abre.
    if cfg.get("modo") == "teste":
        lista = [x.strip() for x in (cfg.get("numeros_teste") or "").split(",")]
        chave_esp = um(conn, "SELECT nai_chave(%s) AS k", (espelho,))["k"]
        chaves = [um(conn, "SELECT nai_chave(%s) AS k", (x,))["k"]
                  for x in lista if x]
        if chave_esp not in chaves:
            problemas.append(
                "o espelho %s nao esta em nai_config.numeros_teste.\n"
                "    O porteiro devolveria 'fora_do_teste'. Acrescente com:\n"
                "      UPDATE nai_config SET valor = valor || ',%s'\n"
                "       WHERE chave='numeros_teste';" % (espelho, espelho))

    if problemas:
        print("\nNAO VOU RODAR. Conserte isto primeiro:\n", file=sys.stderr)
        for p in problemas:
            print("  * " + p + "\n", file=sys.stderr)
        sys.exit(1)

    print("travas conferidas: %s, modo=%s, espelho na lista de teste"
          % ("envio_simulado=sim" if cfg.get("envio_simulado") == "sim"
             else "espelho protegido na caixa de saida", cfg.get("modo")))


# --------------------------------------------------------------- espelho --
def espelho_id(conn, espelho):
    r = um(conn, "SELECT id FROM nai_contato WHERE chave = nai_chave(%s)", (espelho,))
    if r:
        return r["id"]
    # `nai_contato_do_cadastro` e a mesma porta que o fluxo usa -- nao crio
    # contato na mao para nao inventar um formato de chave diferente do dele.
    return um(conn, "SELECT nai_contato_do_cadastro(%s, %s) AS id",
              (espelho, ESPELHO_NOME))["id"]


def garantir_corretor(conn, espelho):
    """O espelho tem que passar a PORTA, nao so o modo teste.

    Existe um segundo porteiro depois do modo teste: `nai_porta` so deixa ela
    atender quem esta em `corretores` com pode_falar. Quem nao esta recebe
    silencio e o Tel recebe um aviso "Chegou mensagem de quem NAO esta nos
    grupos de corretores".

    Foi exatamente o que aconteceu na primeira tentativa do ciclo 1: os
    turnos abriram, o agente NUNCA rodou (`ferramentas` vazio) e a unica
    coisa na caixa de saida era o aviso ao Tel. Julgar aquilo seria julgar o
    porteiro, nao a Nay.

    O INSERT e o mesmo que o comando `CORRETOR <telefone>` do Tel faz --
    mesma tabela, mesmas colunas, mesma marca de origem.
    """
    dig = um(conn, "SELECT regexp_replace(%s, '\\D', '', 'g') AS d", (espelho,))["d"]
    r = um(conn, "SELECT telefone, pode_falar, aprovado, ativo FROM corretores "
                 " WHERE nai_chave(telefone) = nai_chave(%s)", (espelho,))
    if r and r["pode_falar"] and r["aprovado"] and r["ativo"]:
        return False
    executar(conn, """
        INSERT INTO corretores (telefone, nome, origem, aprovado, ativo, pode_falar, fonte)
        VALUES (%s, %s, %s, true, true, true, 'tel')
        ON CONFLICT (telefone) DO UPDATE
           SET pode_falar = true, aprovado = true, ativo = true
    """, (dig, ESPELHO_NOME, "espelho do treino, criado em " +
          datetime.now(timezone.utc).strftime("%d/%m")))
    return True


def limpar_conversa(conn, contato_id, sessao):
    """Zera a conversa do espelho entre um caso e outro.

    A memoria antiga nao e apagada: ganha prefixo de arquivo, igual ao que o
    proprio sistema ja faz ao zerar uma conversa. Assim da para voltar e ler
    o que o caso anterior tinha de contexto, se um julgamento ficar estranho.
    """
    marca = "arquivo-treino-%s:" % datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%f")
    executar(conn, "UPDATE nai_memoria SET session_id = %s || session_id "
                   " WHERE session_id = %s", (marca, sessao))
    # `zerado_em` e o marco que a trava de "repetida" usa: sem ele, a segunda
    # vez que ela mandar a mesma sugestao de visita sairia barrada como
    # repeticao -- que foi um bug real de 14/09, nao hipotese.
    executar(conn, "UPDATE nai_contato SET zerado_em = now(), "
                   "humano_assumiu_em = NULL, humano_motivo = NULL "
                   " WHERE id = %s", (contato_id,))
    # FOTO DO CASO ANTERIOR NAO PODE TRAVAR A DO PROXIMO (21/09). Todo caso
    # passa pelo mesmo espelho, e `nai_fotos_ja_mandadas` bloqueia a mesma
    # foto para o mesmo contato por 24h -- sem olhar `zerado_em`. Resultado:
    # o segundo corretor que perguntasse de um imovel ja pedido por outro
    # ficava sem foto, o que em producao nao acontece (sao pessoas
    # diferentes). Foi o que zerou as fotos da rodada 3. As linhas nao sao
    # apagadas: so recuam 2 dias, e a contagem de fotos de cada caso (que e
    # por turno) continua certa.
    executar(conn, "UPDATE nai_saida SET criado_em = criado_em - interval '2 days' "
                   " WHERE contato_id = %s AND tipo = 'imagem' AND estado = 'simulado' "
                   "   AND criado_em > now() - interval '2 days'", (contato_id,))
    # Visita aberta do caso anterior faria o proximo cair em outro ramo.
    executar(conn, "UPDATE nai_visita SET estado='encerrada', encerrada_em=now(), "
                   "motivo='treino: caso anterior' "
                   " WHERE corretor_id = %s AND nai_visita_aberta(estado)", (contato_id,))


# --------------------------------------------------------------- webhook --
def entregar(webhook, telefone, nome, texto, citado_id=None, timeout=30):
    """Faz o que a Z-API faria: entrega a mensagem no webhook.

    O corpo imita o `ReceivedCallback` que o no "Filtrar e normalizar" espera.
    Os campos sao os mesmos que ele le -- nada a mais, para nao ensinar o
    fluxo a depender de algo que o WhatsApp nao manda.

    A CITACAO (Tel, 21/09). Quando o corretor MARCA uma mensagem -- um card
    que a gente postou num grupo -- a Z-API manda `referenceMessageId`, e e
    por ele que `nay_imovel_da_citacao` descobre de qual imovel ele fala.
    A primeira versao deste script nao mandava esse campo, entao todo caso de
    mensagem marcada rodava como se ele tivesse escrito "quanto e o aluguel
    desse?" do nada -- e a Nay, certissima, perguntava de qual imovel era.
    Foi o caso 1 do ciclo 1: julgado como erro dela, e era do simulador.
    """
    corpo = {
        "type": "ReceivedCallback",
        "instanceId": "treino",
        "messageId": "TREINO%d" % int(time.time() * 1000),
        "phone": telefone,
        "senderName": nome,
        "chatName": nome,
        "fromMe": False,
        "fromApi": False,
        "isGroup": False,
        "isNewsletter": False,
        "broadcast": False,
        "isStatusReply": False,
        "momment": int(time.time() * 1000),
        "status": "RECEIVED",
        "text": {"message": texto},
    }
    if citado_id:
        corpo["referenceMessageId"] = citado_id
    req = urllib.request.Request(
        webhook, data=json.dumps(corpo).encode("utf-8"),
        headers={"Content-Type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.status, r.read(400).decode("utf-8", "replace")


def esperar_turno(conn, contato_id, desde_turno, teto=ESPERA_TETO_S):
    """Espera o fluxo terminar de responder o turno do espelho.

    NAO espera `fechado_em`. Essa foi a primeira versao e estava errada:
    medido na base, so 325 dos 419 turnos de corretor ja respondidos tem
    `fechado_em` preenchido -- 78%. O no "Fechar turno" nao roda em todos os
    ramos, entao esperar por ele dava tempo esgotado em resposta que tinha
    saido perfeita.

    O sinal confiavel e a CAIXA DE SAIDA parar de crescer: a resposta dela
    sai em varias mensagens (card, fotos, sugestao de visita), e colher no
    meio pegaria so a primeira. Entao espera a contagem ficar ESTAVEL por
    duas leituras seguidas. `fechado_em` ainda serve como atalho quando
    aparece, mas nunca como exigencia.
    """
    fim = time.time() + teto
    turno = None
    anterior = -1
    estaveis = 0
    TERMINAIS = ("simulado", "enviado", "bloqueado", "erro")

    while time.time() < fim:
        if turno is None:
            r = um(conn, "SELECT id FROM nai_turno WHERE contato_id = %s AND id > %s "
                         " ORDER BY id DESC LIMIT 1", (contato_id, desde_turno))
            if r:
                turno = r["id"]
        if turno is not None:
            s = um(conn, "SELECT count(*) AS n, "
                         "       count(*) FILTER (WHERE estado = ANY(%s)) AS prontas "
                         "  FROM nai_saida WHERE turno_id = %s", (list(TERMINAIS), turno))
            t = um(conn, "SELECT fechado_em FROM nai_turno WHERE id = %s", (turno,))
            # ja ha resposta e ela parou de crescer?
            if s["n"] > 0 and s["n"] == s["prontas"]:
                if s["n"] == anterior:
                    estaveis += 1
                    if estaveis >= 2:
                        return turno, None
                else:
                    estaveis = 0
                anterior = s["n"]
            elif t["fechado_em"] is not None and s["n"] == 0:
                # o fluxo fechou sem mandar nada -- ela ficou calada de
                # proposito (SILENCIO). E um resultado valido de julgar.
                return turno, None
        time.sleep(ESPERA_PASSO_S)

    if turno:
        return turno, ("o turno %d abriu mas a resposta nao estabilizou em %ds"
                       % (turno, teto))
    return None, "o fluxo nao abriu turno nenhum em %ds" % teto


# ------------------------------------------------------------------ caso --
def vestir_espelho(conn, contato_esp, caso):
    """Poe no espelho o NOME que o corretor original tinha.

    Metade do prompt dela e sobre tratamento ("Sr. Carlos", "Sra. Marcia",
    perguntar o nome quando nao souber). Com o espelho chamado "Treino
    (espelho)" ela respondia "Ola, Sr. Treino!" -- e julgar isso seria
    julgar uma conversa que nunca existiu. Pior: o caminho muda, porque
    `nay_nome_de_pessoa` decide se ha nome de gente ou se e para perguntar.

    O nome vai pelos dois lados: na coluna do contato (que o fluxo le) e no
    `senderName` do payload (que e por onde a Z-API entrega).
    """
    executar(conn, "UPDATE nai_contato SET nome_whatsapp = %s, nome_completo = %s "
                   " WHERE id = %s",
             (caso.get("nome_whatsapp") or ESPELHO_NOME,
              caso.get("nome_completo"), contato_esp))
    return caso.get("nome_whatsapp") or ESPELHO_NOME


def rodar_caso(conn, caso, webhook, espelho, contato_esp, sessao, pausa):
    cid = caso["id"]
    print("\n[caso %d] turno original %s  (%s)" % (cid, caso["turno_origem"] or "-",
          (caso["ele_disse"] or "")[:70].replace("\n", " ")))

    executar(conn, "UPDATE nai_treino_caso SET estado='rodando', erro=NULL WHERE id=%s", (cid,))

    try:
        nome = vestir_espelho(conn, contato_esp, caso)
        limpar_conversa(conn, contato_esp, sessao)
        n = um(conn, "SELECT nai_treino_semear_memoria(%s, %s) AS n", (cid, sessao))["n"]
        print("        memoria semeada com %d falas anteriores" % n)

        ultimo = um(conn, "SELECT coalesce(max(id),0) AS id FROM nai_turno "
                          " WHERE contato_id = %s", (contato_esp,))["id"]

        status, corpo = entregar(webhook, espelho, nome, caso["ele_disse"],
                                 citado_id=caso.get("citado_id"))
        print("        webhook respondeu %s  (como \"%s\")" % (status, nome))

        turno, erro = esperar_turno(conn, contato_esp, ultimo)
        if erro:
            executar(conn, "UPDATE nai_treino_caso SET estado='erro', erro=%s WHERE id=%s",
                     (erro, cid))
            print("        ERRO: %s" % erro)
            return False

        texto = um(conn, "SELECT nai_treino_colher(%s, %s) AS t", (cid, turno))["t"]
        print("        ela respondeu: %s" % ((texto or "(calada)")[:110].replace("\n", " ")))
        return True

    except Exception as e:                      # noqa: BLE001
        executar(conn, "UPDATE nai_treino_caso SET estado='erro', erro=%s WHERE id=%s",
                 (str(e)[:900], cid))
        print("        ERRO: %s" % e)
        return False
    finally:
        time.sleep(pausa)


# ------------------------------------------------------------------ main --
def main():
    p = argparse.ArgumentParser(description="Re-executa casos de treino pelo fluxo real do n8n")
    p.add_argument("--ciclo", type=int, help="id do ciclo a rodar")
    p.add_argument("--montar", type=int, metavar="N",
                   help="monta um ciclo novo com os N turnos mais recentes ainda nao usados")
    p.add_argument("--limite", type=int, help="roda so os N primeiros casos pendentes")
    p.add_argument("--listar", action="store_true", help="mostra o tamanho do pool e sai")
    p.add_argument("--webhook", default=os.environ.get("NAI_WEBHOOK", WEBHOOK_PADRAO))
    p.add_argument("--espelho", default=os.environ.get("NAI_ESPELHO", ESPELHO_PADRAO))
    p.add_argument("--pausa", type=float, default=2.0,
                   help="segundos entre um caso e outro")
    args = p.parse_args()

    conn = conectar()

    if args.listar:
        r = um(conn, "SELECT count(*) AS n FROM nai_treino_pool")
        j = um(conn, "SELECT count(*) AS n FROM nai_treino_caso")
        print("pool disponivel (nunca usados): %d turnos" % r["n"])
        print("ja viraram caso em algum ciclo: %d" % j["n"])
        for c in varios(conn, "SELECT c.id, c.rotulo, c.tamanho, c.criado_em, "
                              " count(*) FILTER (WHERE k.estado='rodado') AS rodados, "
                              " count(*) FILTER (WHERE j.caso_id IS NOT NULL) AS julgados "
                              " FROM nai_treino_ciclo c "
                              " LEFT JOIN nai_treino_caso k ON k.ciclo_id=c.id "
                              " LEFT JOIN nai_treino_julgamento j ON j.caso_id=k.id "
                              " GROUP BY c.id ORDER BY c.id"):
            print("  ciclo %d  %s  %d casos  %d rodados  %d julgados"
                  % (c["id"], c["rotulo"], c["tamanho"], c["rodados"], c["julgados"]))
        return

    if args.montar:
        ciclo = um(conn, "SELECT nai_treino_montar_ciclo(%s) AS id", (args.montar,))["id"]
        n = um(conn, "SELECT count(*) AS n FROM nai_treino_caso WHERE ciclo_id=%s", (ciclo,))["n"]
        print("ciclo %d criado com %d casos" % (ciclo, n))
        if not args.ciclo:
            args.ciclo = ciclo

    if not args.ciclo:
        sys.exit("diga qual ciclo rodar (--ciclo N) ou monte um (--montar 50)")

    conferir_travas(conn, args.espelho)

    contato_esp = espelho_id(conn, args.espelho)
    if garantir_corretor(conn, args.espelho):
        print("espelho registrado em `corretores` (sem isso a porta o barra)")
    sessao = "nai:corretor:%d" % contato_esp
    print("espelho: %s  contato #%d  sessao %s" % (args.espelho, contato_esp, sessao))

    # `citado_id` vem da mensagem ORIGINAL daquele turno: e o que o corretor
    # marcou no WhatsApp. Sem ele, caso de mensagem marcada roda torto.
    sql = ("SELECT k.id, k.turno_origem, k.ele_disse, "
           "       c.nome_whatsapp, c.nome_completo, "
           "       (SELECT m.citado_id FROM mensagens m "
           "         WHERE m.id = ANY ((SELECT t.msg_ids FROM nai_turno t "
           "                             WHERE t.id = k.turno_origem)::int[]) "
           "           AND m.citado_id IS NOT NULL LIMIT 1) AS citado_id "
           "  FROM nai_treino_caso k JOIN nai_contato c ON c.id = k.contato_origem "
           " WHERE k.ciclo_id = %s AND k.estado IN ('pendente','erro') ORDER BY k.id")
    params = [args.ciclo]
    if args.limite:
        sql += " LIMIT %s"
        params.append(args.limite)
    casos = varios(conn, sql, params)

    if not casos:
        print("nao ha caso pendente no ciclo %d" % args.ciclo)
        return

    print("vou rodar %d casos do ciclo %d" % (len(casos), args.ciclo))
    t0 = time.time()
    ok = 0
    for i, caso in enumerate(casos, 1):
        print("--- %d/%d ---" % (i, len(casos)), end="")
        if rodar_caso(conn, caso, args.webhook, args.espelho, contato_esp, sessao, args.pausa):
            ok += 1

    print("\nterminou: %d de %d rodaram, em %.1f min"
          % (ok, len(casos), (time.time() - t0) / 60))
    print("agora e julgar no painel: Cerebro da Nay -> aba Treino")


if __name__ == "__main__":
    main()
