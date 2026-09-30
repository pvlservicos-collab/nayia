#!/bin/bash
# Wrapper de cron para sincronizar_catalogo.py, no mesmo molde dos outros:
# cron nao carrega .env sozinho, e "set -a" faz o que o arquivo define
# virar variavel exportada.
#
# Roda de hora em hora, nao de minuto em minuto: a varredura leva uns 4
# minutos e sao 75 requisicoes ao site. A regra do projeto e nao martelar
# o site, e imovel cadastrado agora ficar conhecido em ate uma hora ja
# resolve o problema que motivou isto (a Nay dizer "nao encontrei o
# imovel" de um imovel que esta no ar).
#
# O flock do cron impede duas varreduras ao mesmo tempo.
set -euo pipefail

PROJETO=/root/nay-publicador

cd "$PROJETO"
set -a
. ./.env
set +a

export TZ='America/Manaus'
CARIMBO='+%Y-%m-%dT%H:%M:%S%z'

# O alarme roda SEMPRE, e principalmente quando a varredura falhou -- e
# esse o caso em que ele importa. Ele e quem avisa o Tel, porque log
# ninguem le: foi assim que a varredura ficou tres dias parada. Mede o
# carimbo no banco, nao "o cron disparou", entao tambem pega o caso de
# rodar e nao escrever nada. Nunca derruba o wrapper.
alarmar() {
    "$PROJETO/.venv/bin/python" "$PROJETO/alarme_varredura.py" --enviar || \
        echo "[$(date "$CARIMBO")] ERRO no alarme de varredura" >&2
    # E OS CRONS DE MINUTO, que ninguem vigiava. Em 02/09 a grade
    # ficou 18 horas parada com "Permission denied" a cada minuto --
    # 754 linhas no log, e log ninguem le. Roda aqui porque este
    # wrapper ja e o de hora em hora; nunca derruba nada.
    "$PROJETO/.venv/bin/python" "$PROJETO/alarme_crons.py" --enviar || \
        echo "[$(date "$CARIMBO")] ERRO no alarme de crons" >&2
}

codigo=0
SAIDA="$("$PROJETO/.venv/bin/python" "$PROJETO/sincronizar_catalogo.py" \
         --escrever --silencioso 2>&1)" || codigo=$?

if [ "$codigo" -ne 0 ]; then
    echo "[$(date "$CARIMBO")] ERRO (saida $codigo)" >&2
    echo "$SAIDA" >&2
    alarmar
    exit "$codigo"
fi

# So escreve no log quando mudou alguma coisa. 24 execucoes por dia com
# "nada mudou" tornariam o log ilegivel, e e nele que se procura quando a
# Nay nao conhece um codigo.
if [ -n "$SAIDA" ]; then
    echo "[$(date "$CARIMBO")] $SAIDA"
fi

# AS FOTOS DO QUE ENTROU. `imovel_fotos` alimenta a resposta da Nay sobre
# imagem, e ela le a TABELA -- nao o site. Imovel novo entra sem foto, e
# ate 01/09 ninguem preenchia: a Regiane perguntou "tem imagens?" do 2014
# e ouviu que nao tinha, com 24 fotos no anuncio. Roda depois da varredura
# porque e ela que traz os codigos novos, pede so o que FALTA, e fica
# silencioso quando nao falta nada.
"$PROJETO/.venv/bin/python" "$PROJETO/varrer_fotos.py" --escrever --silencioso || \
    echo "[$(date "$CARIMBO")] ERRO no varredor de fotos" >&2

# O TIPO E A ÁREA do que entrou. A varredura lê a LISTAGEM, e o card dela não
# traz o tipo -- ele está no `h5` da página do anúncio. Em 09/09, ao montar as
# listas por categoria, 17 dos 54 imóveis de locação estavam sem tipo e
# ficariam de fora de toda lista, calados. Roda depois da varredura porque é
# ela que traz os códigos novos, pede só o que FALTA, e fica silencioso quando
# não falta nada.
"$PROJETO/.venv/bin/python" "$PROJETO/varrer_tipos.py" --escrever --silencioso || \
    echo "[$(date "$CARIMBO")] ERRO no varredor de tipos" >&2

# OS DADOS DO ANUNCIO que a listagem nao traz (14/09): vagas, sol, andar, taxa
# de condominio, IPTU, incluso no aluguel, caracteristicas e mobilia -- lidos na
# pagina do anuncio, gravados SO onde a tabela esta vazia. O Tel perguntou "tem
# garagem?" e "e mobiliado?" e a Nay subiu as duas para ele com o dado no site.
python3 "$PROJETO/preencher_do_anuncio.py" --escrever >/dev/null 2>&1 ||     echo "[$(date "$CARIMBO")] ERRO no preenchedor do anuncio" >&2

# BATIMENTO (23/09). O `alarme_crons.py` olha a data deste arquivo.
#
# A varredura ficou CINCO DIAS parada (18/09 a 23/09) e ninguem soube -- a
# linha do cron tinha sido comentada. Os dois alarmes que deveriam avisar
# (`alarme_varredura` e `alarme_crons`) sao chamados AQUI DENTRO, entao
# pararam junto com ela: vigia que mora dentro do vigiado nao avisa quando o
# vigiado morre.
#
# Com o batimento, quem vigia passa a ser o `alarme_crons` dos OUTROS crons,
# que rodam de minuto em minuto e sao independentes deste arquivo.
mkdir -p "$PROJETO/logs" && touch "$PROJETO/logs/.batimento_sincronizar_catalogo"

alarmar
