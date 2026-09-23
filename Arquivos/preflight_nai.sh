#!/bin/sh
# PRE-VOO DA NAI (Tel, 14/09/2026: "custa estruturar o negocio direitinho?").
#
# Roda os cenarios que ele testa de verdade, no numero de teste, com
# `envio_simulado = sim`: NADA e enviado no WhatsApp. No fim mostra, cenario por
# cenario, qual imovel foi identificado e o que ela responderia -- e devolve a
# configuracao ao normal, com a conversa zerada.
#
# Uso:  sh /root/preflight_nai.sh
set -e
PSQL="docker exec nay-postgres psql -U nay -d naydb"
TEL=5596991712835
WEBHOOK=https://n8n.imobeasy.online/webhook/13d4116a-9e50-4f0f-b036-8d9585c33a80

# O VALOR DE ANTES e o que volta no fim (22/09). Antes o fim ligava o envio
# real sempre -- escrito quando o normal era a Nay no ar. Com ela em treino,
# rodar o pre-voo soltava a Nay no WhatsApp sem ninguem pedir.
ENVIO_ANTES=$($PSQL -tAc "SELECT valor FROM nai_config WHERE chave='envio_simulado'" | tr -d '[:space:]')
[ -n "$ENVIO_ANTES" ] || { echo "nao consegui ler envio_simulado -- parei"; exit 1; }
$PSQL -q -c "UPDATE nai_config SET valor='sim' WHERE chave='envio_simulado'"
$PSQL -tAc "SELECT nai_zerar_conversa('$TEL')" >/dev/null
INI=$($PSQL -tAc "SELECT coalesce(max(id),0) FROM nai_turno")

manda() { # $1 texto  $2 messageId  $3 referenceMessageId (opcional)  $4 rotulo
  python3 - "$1" "$2" "$3" <<'PY' > /tmp/pf.json
import json, sys
txt, mid, ref = sys.argv[1], sys.argv[2], sys.argv[3]
p = {"type": "ReceivedCallback", "phone": "559691712835", "fromMe": False, "fromApi": False,
     "isGroup": False, "isNewsletter": False, "broadcast": False, "senderName": "Pedro",
     "chatName": "Pedro", "messageId": mid, "momment": 0, "status": "RECEIVED",
     "text": {"message": txt}}
if ref:
    p["referenceMessageId"] = ref
print(json.dumps(p))
PY
  curl -s -o /dev/null -X POST -H 'Content-Type: application/json' --data @/tmp/pf.json "$WEBHOOK"
  printf '  %s\n' "$4"
  sleep 42
}

CARD="📍 Grand Prix
* Bairro: Parque 10 de Novembro
* 2 quartos sendo 1 suíte
Código: 4159"

echo "== pre-voo (nada e enviado; envio_simulado = sim)"
manda "Bom dia"                                      "PF-1" ""       "1/7 saudacao, sem imovel nenhum"
manda "$CARD"                                        "PF-2" ""       "2/7 ele cola o card do 4159"
manda "É mobiliado?"                                 "PF-3" ""       "3/7 pergunta sem codigo (contexto)"
manda "E tem garagem?"                               "PF-4" "PF-2"   "4/7 marcando o card que ele colou"
manda "Me manda as fotos dele"                       "PF-5" ""       "5/7 pede as fotos"
manda "quero outros no mesmo bairro ate 3500"        "PF-6" ""       "6/7 busca por perfil"
manda "quero agendar uma visita amanha as 10h"       "PF-7" ""       "7/7 pede visita"

echo
echo "================ O QUE ELA RESPONDERIA ================"
$PSQL -P pager=off -c "
SELECT t.id AS turno,
       coalesce(t.codigo::text, '-') AS imovel,
       left(replace(coalesce(t.texto,''), chr(10), ' / '), 34) AS ele_disse,
       coalesce((SELECT count(*) FROM nai_saida s WHERE s.turno_id = t.id AND s.tipo = 'imagem'), 0) AS fotos,
       coalesce((SELECT string_agg(
                          CASE WHEN s.estado = 'bloqueado' THEN '[BLOQUEADA: ' || coalesce(s.bloqueio, '?') || '] ' ELSE '' END ||
                          left(replace(s.texto, chr(10), ' / '), 90), '  ||  ' ORDER BY s.ordem)
                   FROM nai_saida s WHERE s.turno_id = t.id AND s.tipo = 'texto'), '(calada)') AS resposta,
       -- 14/09: o pre-voo mostrava a mensagem CRIADA sem dizer se ela foi
       -- barrada na saida. Assim passou uma frase que nunca chegou ao Tel.
       (SELECT count(*) FROM nai_saida s WHERE s.turno_id = t.id AND s.estado = 'bloqueado') AS barradas
  FROM nai_turno t
 WHERE t.id > $INI
 ORDER BY t.id;"

echo "================ A ESTEIRA QUE AGIU ================"
$PSQL -P pager=off -c "
SELECT c.turno_id, string_agg(c.ordem || '. ' || c.etapa || ' -> ' || c.resultado, ' | ' ORDER BY c.ordem) AS agiram
  FROM nai_conferencia c
 WHERE c.turno_id > $INI AND c.resultado <> 'passou'
 GROUP BY c.turno_id ORDER BY c.turno_id;"

echo "================ PARA ONDE IRIA CADA MENSAGEM ================"
$PSQL -P pager=off -c "
SELECT papel_destino, count(*), string_agg(DISTINCT motivo, ', ') AS motivos
  FROM nai_saida WHERE turno_id > $INI GROUP BY 1 ORDER BY 2 DESC;"

# O pre-voo limpa o que ELE mesmo criou: a visita de teste nao pode ficar
# aberta, senao o teste seguinte comeca sujo (ela para de sugerir visita e
# fica perguntando como foi a visita que nunca houve).
$PSQL -q -c "UPDATE nai_visita SET estado='cancelada', encerrada_em=now(), atualizado_em=now()
              WHERE corretor_id=(SELECT id FROM nai_contato WHERE chave=nai_chave('$TEL'))
                AND criado_em > now() - interval '30 minutes' AND nai_visita_aberta(estado)"
$PSQL -q -c "UPDATE nai_config SET valor='$ENVIO_ANTES' WHERE chave='envio_simulado'"
$PSQL -tAc "SELECT nai_zerar_conversa('$TEL')" >/dev/null
echo
echo "== fim do pre-voo. envio devolvido ao que estava antes ($ENVIO_ANTES) e conversa zerada:"
$PSQL -tAc "SELECT chave || ' = ' || valor FROM nai_config WHERE chave IN ('envio_simulado','modo','pausada','numeros_teste')"
