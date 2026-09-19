#!/usr/bin/env python3
"""A RETOMADA DE SABADO -- roda UMA vez, 19/09/2026 08:45 Manaus (12:45 UTC).

Tel, 18/09 23h: "a partir de amanha sabado 19 de setembro as 8:45 da manha vai
comecar a responder quem nao foi respondido sobre imoveis, mas esta na lista de
corretores". E: "mesmo se a pessoa estiver na lista, se ela recebeu uma mensagem
do Tel nas ultimas 16 horas a Nay vai ignorar tambem -- essa regra so para amanha".

O QUE ELE FAZ, nesta ordem:
  1. tira a NAI da pausa (`nai_config.pausada = 'nao'`) -- e o "ligamento";
  2. reconfere CADA candidato AGORA (a lista, o gap do Tel, as 16 horas, e se
     alguem ja respondeu no meio tempo);
  3. reinjeta a ultima mensagem da pessoa no webhook de entrada, com o nome
     real dela, e a NAI responde pelo caminho normal;
  4. marca a linha e escreve o resumo no log.

POR QUE REINJETAR em vez de enfileirar um texto pronto: a resposta tem que ser
a resposta DELA, com o imovel e o contexto daquela conversa. Enfileirar texto
pronto mandaria uma frase generica para quem perguntou "semi mobiliado?".

O PRECO, e ele e sabido: a mensagem da pessoa entra de novo em `mensagens` como
recebida. Fica um eco no historico dela. E o custo de usar a porta de entrada
de verdade em vez de uma porta paralela que ninguem testou.

Espacamento de 60s entre pessoas: sao 11, entao termina por volta das 8:56.
"""
import json, subprocess, sys, time, urllib.request
from datetime import datetime, timezone

WEBHOOK = "https://n8n.imobeasy.online/webhook/13d4116a-9e50-4f0f-b036-8d9585c33a80"
ESPACO  = 60
PSQL    = ["docker", "exec", "-i", "nay-postgres", "psql", "-U", "nay", "-d", "naydb", "-At", "-c"]


def log(msg):
    print(f"[{datetime.now(timezone.utc):%Y-%m-%d %H:%M:%S} UTC] {msg}", flush=True)


def psql(sql):
    r = subprocess.run(PSQL + [sql], capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"psql falhou: {r.stderr.strip()}")
    return r.stdout.strip()


def linhas(sql):
    """Devolve lista de dicts. Passa por JSON porque os textos tem quebra de
    linha e emoji -- separar por tab quebraria na primeira mensagem com \n."""
    out = psql(f"SELECT coalesce(json_agg(t), '[]') FROM ({sql}) t")
    return json.loads(out)


# --- 1. o ligamento -----------------------------------------------------
pend = psql("SELECT count(*) FROM nai_retomada WHERE responder AND estado = 'pendente'")
if pend == "0":
    log("nada pendente em nai_retomada -- nao faco nada e nao ligo a NAI.")
    sys.exit(0)

psql("UPDATE nai_config SET valor = 'nao', atualizado_em = now() WHERE chave = 'pausada'")
log(f"NAI despausada. {pend} candidatos na fila.")

# --- 2. quem ainda vale, AGORA -----------------------------------------
# Cada condicao aqui ja foi conferida ontem a noite. E conferida de novo porque
# a noite inteira passou: chegou mensagem, o Tel pode ter assumido conversa, e
# a janela de 16 horas anda junto com o relogio.
alvos = linhas("""
  SELECT r.chave, r.telefone, coalesce(r.nome, '') AS nome, r.texto
    FROM nai_retomada r
    LEFT JOIN nai_contato k ON k.chave = r.chave
   WHERE r.responder AND r.estado = 'pendente'
     AND nai_pode_falar(r.chave, r.telefone)
     AND NOT nai_tel_com_a_conversa(k.id)
     AND coalesce(k.humano_assumiu_em, '-infinity') <= now() - interval '16 hours'
     AND NOT EXISTS (SELECT 1 FROM mensagens m
                      WHERE nai_chave(m.telefone) = r.chave
                        AND m.direcao = 'enviada'
                        AND m.criada_em > r.recebida_em)
   ORDER BY r.recebida_em
""")
log(f"{len(alvos)} passaram na reconferencia.")

# --- 3. reinjetar -------------------------------------------------------
ok = 0
for i, a in enumerate(alvos):
    corpo = {
        "type": "ReceivedCallback", "phone": a["telefone"], "fromMe": False, "fromApi": False,
        "isGroup": False, "isNewsletter": False, "broadcast": False,
        "senderName": a["nome"] or "Corretor", "chatName": a["nome"] or "Corretor",
        "messageId": f"RETOMADA-{int(time.time()*1000)}-{i}", "momment": 0,
        "status": "RECEIVED", "text": {"message": a["texto"]},
    }
    req = urllib.request.Request(WEBHOOK, data=json.dumps(corpo).encode(),
                                 headers={"Content-Type": "application/json"})
    chave = a["chave"].replace("'", "''")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            codigo = resp.status
        estado, pulo = ("enviado", None) if codigo < 300 else ("erro", f"HTTP {codigo}")
        ok += estado == "enviado"
    except Exception as e:
        estado, pulo = "erro", str(e)[:200]
    pulo_sql = "NULL" if pulo is None else "'" + pulo.replace("'", "''") + "'"
    psql(f"UPDATE nai_retomada SET estado = '{estado}', pulo = {pulo_sql}, "
         f"rodado_em = now() WHERE chave = '{chave}'")
    log(f"  {a['nome'] or a['telefone']}: {estado}{' -- ' + pulo if pulo else ''}")
    if i < len(alvos) - 1:
        time.sleep(ESPACO)

# --- 4. os que nao passaram --------------------------------------------
psql("""UPDATE nai_retomada SET estado = 'pulado', rodado_em = now(),
        pulo = 'nao passou na reconferencia das 8:45 (lista, Tel na conversa,
        regra das 16h, ou ja respondido)'
        WHERE responder AND estado = 'pendente'""")

log(f"FIM. {ok} reinjetados de {len(alvos)}.")
log(psql("""SELECT string_agg(estado || ': ' || n, ' | ')
              FROM (SELECT estado, count(*)::text n FROM nai_retomada GROUP BY 1) x"""))
