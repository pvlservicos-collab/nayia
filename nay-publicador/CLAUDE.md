# Varredura do catálogo Imob Easy

## LEIA ANTES DE MEXER: `REGRAS-E-BUGS.md`

Todas as regras que a Nay segue e **todos os bugs que já aconteceram**
moram em [`REGRAS-E-BUGS.md`](REGRAS-E-BUGS.md), num arquivo só. Antes de
mexer em qualquer coisa que fale com corretor, leia — principalmente a
Parte 2, que diz o que segura cada bug hoje. Se o que você está vendo
parece um daqueles, é provável que seja o mesmo problema de novo.

A Parte 1 (as regras) é **gerada** da tabela `regras`, que é a mesma fonte
do prompt da Nay: mudou a regra, rode `gerar_regras_e_bugs.py --escrever` e
depois `sincronizar_regras.py --escrever`. `./rodar_testes.sh --com-banco`
falha se o documento estiver diferente do banco.

A Parte 2 (os bugs) é escrita à mão e **cresce a cada conserto** — três
partes: o que o Tel viu, o que era de verdade, o que segura hoje, com o
arquivo de teste ao lado.


## Duas frentes nesta pasta

1. **Varredura do catálogo** (pronta) — lê o site público da Imob Easy e
   atualiza a tabela `imoveis`. É o que o resto deste arquivo descreve.
2. **Publicador de grupos** (a construir) — envia imóveis para os grupos
   de WhatsApp de corretores, no horário e grupos certos. Especificação
   completa em `28-Publicador-de-Grupos-Plano.md`. Reaproveita a lógica
   de extração de `extrair_pagina.py`, mas lê o anúncio individual
   (`/anuncios/<codigo>`), não a listagem.

## Objetivo
Ler o site público da Imob Easy e atualizar a tabela `imoveis` do banco `naydb`,
sem apagar nada. Modo COMPLEMENTAR, nunca substitutivo.

## Fonte
- Venda: https://imobeasy.com/anuncios?ad_type=Venda&page=N  (67 páginas)
- Aluguel: https://imobeasy.com/anuncios?ad_type=Aluguel&page=N (8 páginas)
- Anúncio: https://imobeasy.com/anuncios/<codigo>
- Sem login. 12 anúncios por página.

## Como identificar cada coisa
- Código: no link `/imoveis/<codigo>` de cada card
- Parceiro: o card contém o texto `Imóvel Parceiro` ou o ícone `partner-sm-`
- Valores: linhas `Venda: R$ ...` e `Aluguel: R$ ...`, podem aparecer as duas

## Banco
PostgreSQL 16 em container Docker `nay-postgres`, usuário `nay`, banco `naydb`.
Acesso no servidor: `docker exec nay-postgres psql -U nay -d naydb -c "QUERY"`

Colunas relevantes de `imoveis`: codigo, tipo, status, condominio_nome, bairro,
logradouro, complemento, area_util, area_total, quartos, suites, banheiros,
vagas, vagas_cobertas, sol, andar, valor_venda, valor_aluguel, taxa_condominio,
iptu, mobilia, descricao, caracteristicas, origem, publicado_no_site, disponivel,
bloqueado, motivo_bloqueio, sincronizado_em, criado_em, e_parceiro, travado,
travado_motivo, travado_em, extras, captado_por, captado_em

Fotos ficam em `imovel_fotos`: codigo, ordem, url, e_capa, e_fachada.

## Regras que não podem ser violadas
1. **Nunca apagar linha de `imoveis`.** Só atualizar ou marcar.
2. O que existe no banco e não aparece no site vira `publicado_no_site = false`.
   NÃO vira indisponível — pode estar disponível no admin sem anúncio.
3. Sempre gravar `sincronizado_em = now()` no que foi tocado.
4. Rodar em modo simulação por padrão. Só escrever no banco com flag explícita.
5. Pausa de 1 a 2 segundos entre requisições. Não martelar o site.
6. Nenhuma credencial em código. Tudo por variável de ambiente.

## Como trabalhar comigo
- Teste contra 3 páginas antes de propor rodar contra 75
- Não afirme que funciona sem ter rodado
- Uma etapa por vez, com commit ao fim de cada uma
- `./rodar_testes.sh` roda todas as suites; `--com-banco` inclui as de
  SQL (só no servidor, precisam do container)

## Operação: onde as coisas moram (levantado em 27/08/2026)

**Dois servidores, não confundir.** O da Nay é o **srv1894338**
(`179.198.121.171`), Hostinger. Roda os containers `nay-postgres`,
`n8n-viux-n8n-1` e `traefik`, mais o publicador em `/root/nay-publicador`
como systemd `nay-publicador`. O outro, **srv1877774**
(`179.197.239.148`), é a máquina antiga do Hermes: não tem Docker nem
publicador. Já se perdeu tempo confundindo os dois.

**DOIS CATÁLOGOS desde 29/09, e é a confusão mais nova.** O antigo é o
`imobeasy.com`, que a varredura raspa (códigos até 5765). O novo é o
`imobeasy.online`: HTML estático que lê de `api.imobeasy.online`, um Flask no
container `nay-site-api` que grava direto no naydb. Os códigos dele começam em
**9001**, as fotos ficam em `imovel_fotos` apontando para
`imobeasy.online/fotos-captacao/olx/<codigo>/NN.jpg`, e a `origem` é `'olx'`.

`buscar_imovel` tenta o site antigo e, quando a página não traz nada, monta o
mesmo dicionário do BANCO. O site antigo continua MANDANDO quando tem o anúncio
-- inverter isso traria de volta o post por cópia velha. A trava do "está no
ar", que ali era o site responder, aqui é
`nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site)`.
`teste_segundo_catalogo.py`.

**MAS LER DO BANCO É A QUEBRA em dois lugares**, e nos dois nada falha -- o
trabalho só deixa de ser feito. `_atualizar_valores_do_site` relê o preço no
site antes de disparar a lista; `varrer_fotos.conferir` troca nossas fotos
pelas do site. Com o fallback, os dois comparam banco com banco, nunca acham
diferença, e o segundo ainda CARIMBA `fotos_conferidas_em` -- um vigia que vira
carimbo. Os dois usam `buscar_no_site`, que não cai no banco.

**A VARREDURA IA APAGAR ISSO.** Ela despublica todo código que não acha na
listagem do site antigo, e nenhum 9xxx pode estar lá. Medido em simulação: ela
punha o 9001 e o 9003 na lista. Duas guardas hoje, e o que é poupado APARECE no
relato (corte silencioso viraria imóvel fora do ar sem rastro): `travado = true`
-- o sinal que o admin novo já gravava com o motivo na linha e que **nada lia**
-- e `origem` fora de `ORIGENS_DO_SITE_ANTIGO`.

**E JÁ EXISTEM TRÊS MONTADORES DE CARD**, não um: o `montar_mensagem.py` do
publicador (o único que o Tel vem moldando), o `/api/imovel-card/` da API nova e
`nai_card_do_banco` em SQL, servido à Nay por `nai_card_do_imovel`. Medido: os
três dão o mesmo card para o 9003 HOJE -- que é exatamente o que deixa de valer
amanhã. Ao mexer em card, mexer nos três ou aceitar a divergência de olhos
abertos.

**Duas fontes de dado, e é isso que confunde na hora do bug:**
- O **publicador** nunca lê banco para buscar imóvel. `buscar_imovel.py`
  abre `imobeasy.com/anuncios/<codigo>` e lê **ao vivo**. Imóvel
  cadastrado agora já pode ser postado agora. Não existe sincronização
  a fazer antes.
- O **cérebro da Nay** (agente de IA no n8n) lê a tabela `imoveis`. É dela
  que sai "não encontrei o imóvel pelo código X". Resolver isso é a
  varredura do doc 25, não o publicador.

**Onde o banco mora, e a cópia dele** (levantado em 02/09). O `naydb` é um
PostgreSQL 16 num container Docker (`nay-postgres`) no **srv1894338**
(179.198.121.171), volume `postgres_nay_pgdata`. A porta 5432 está publicada
só em `127.0.0.1` -- de fora não se alcança. 24 MB de banco, 90 GB livres no
disco (`96G` total, `6.1G` usados -- ler a coluna certa do `df`: eu já
confundi Used com Avail e disse ao Tel que sobravam 6,7 GB).

**Até 02/09 não havia backup nenhum do banco.** `/root/backups-n8n` guarda os
FLUXOS do n8n, em JSON -- nada do Postgres, nem dump, nem cron. Agora
`backup_banco.sh` roda às 03h05, guarda 14 dias em `/root/backups-banco` e
**confere o dump lendo de volta** (menos de 25 tabelas = descarta e mantém o
anterior). O batimento entra no `alarme_crons.py` com folga de 26h.

Provado em 02/09 restaurando num banco separado: 0 erros, 1.211 imóveis,
16.908 fotos, 5.612 proprietários, 3.656 mensagens, 2.750 linhas de memória,
70 funções. **O catálogo a varredura reconstrói; o resto não** -- conversa,
regras, pendências e corretores só existem aqui.

    docker exec -i nay-postgres pg_restore -U nay -d naydb --clean --if-exists \
      < /root/backups-banco/naydb-AAAAMMDD-HHMM.dump

**A varredura agora é automática (01/09).** `sincronizar_catalogo.py`
faz o ciclo inteiro num comando -- lê o site, compara com o banco,
escreve -- e roda no cron aos 17 minutos de cada hora
(`sincronizar_catalogo.sh`). Antes eram três passos manuais com
exportação de CSV no meio, e por isso ficava dias parada. Simulação por
padrão; só escreve com `--escrever`.

Duas proteções que não podem ser afrouxadas: **despublicar só acontece
em varredura completa** (parcial "veria" 1.158 imóveis sumindo do site),
e o piso de anúncios é proporcional ao que se pediu, não fixo.

**O SITE PUBLICA MAIS DO QUE PARECIA -- o campo comentado (14/09).** Este
arquivo afirmava que "o site NÃO publica a taxa de condomínio -- conferido no
HTML inteiro do 5729". **Estava errado, e a frase guiou decisões por semanas.**
A conferência de então leu o TEXTO RENDERIZADO; o HTML traz o campo:

    <label class="form-control-label">Incluso no Aluguel</label>
    <span class="form-control">Água, Taxa de Gás, Taxa de Condomínio, IPTU</span>

só que o site envolve a seção inteira em `<!-- ... -->`. O BeautifulSoup trata
comentário como texto opaco, então `soup.find("label", ...)` nunca entrava ali.
O código já sabia disso para os VALORES (lê do `<meta name="description">` com
um comentário explicando), e ninguém estendeu a lição aos outros campos do
mesmo bloco.

Medido no 5718: ficam dentro do comentário "Valor de Aluguel", "Aceita
Financiamento?" e "Incluso no Aluguel". Hoje `_campo` procura também nos
comentários, e `Lances de Escada` -- que sempre foi rótulo VISÍVEL -- passou a
ser lido junto. Os dois entram no card. `teste_campo_comentado.py`.

**A lição que passa deste caso:** "conferi e o site não tem" precisa dizer
ONDE se conferiu. Texto renderizado e HTML servido são coisas diferentes, e a
afirmação errada é mais cara que a ausência de afirmação -- ela fecha a
investigação.

**As características marcadas entram no card (14/09).** `buscar_imovel` lê a
seção "Características do Imóvel" da página (só as marcadas aparecem) e o card
põe cada uma em minúsculo, depois dos quartos e antes das vagas. Entra TUDO da
seção -- inclusive "Varanda Gourmet" dos apartamentos, decisão do Tel. **A parede
é a seção**: logo abaixo vem "Características do Condomínio" com a mesma marcação,
e no 2665 ali estão "Piscina" e "Hidromassagem" -- sem cortar no título, o card
diria que o apartamento tem piscina. Semi-Mobiliado/Mobiliado saem na linha de
mobília, que agora lê a página antes do banco. `teste_caracteristicas_do_card.py`.

**A OBS do admin sai no card, logo acima do "Código:" (14/09).** `_observacao`
lê as seções "Observações" e "Descrição do Anúncio" e pega só as linhas que
COMEÇAM com "OBS" em MAIÚSCULO. Vale para o Easy e para os grupos de parceiro
(é o mesmo `montar_mensagem`). Três paredes: a seção "Observações" do 1885
guarda a descrição antiga inteira (pegar a seção publicaria mil caracteres);
dentro dela há "Obs :" de texto colado (medido: das 5 descrições com "obs:",
as 2 em maiúsculo são notas de publicar, as 3 em "Obs" são sobra); e o rodapé
"Tem uma observação sobre esse anúncio?" -- por isso a leitura é por seção.
**O que o Tel escrever depois de "OBS:" vai para os grupos**, sem filtro.
`teste_observacao_do_card.py`.

**Colunas que a varredura NÃO escreve, e o motivo é dado medido:**
`area_util` (a coluna "Área" do card mistura área útil e área de
terreno), `vagas` (a "Garagem" do card é o total; o banco separa
descoberta de coberta -- 39 de 39 imóveis batem com a soma), e zero em
quartos/suítes/banheiros/vagas (o extrator inventa `suites=0` quando não
acha a palavra "suíte"). Contagem de 3 dígitos ou maior que a área é
número de sala, não contagem -- o card do 2564 traz "1601 quartos".

**Se a varredura parar, o Tel é avisado** por `alarme_varredura.py`, que
lê `config.varredura_rodou_em` -- carimbo que a varredura grava ao
terminar sem abortar. **Não** `max(sincronizado_em)`: aquele só avança
nas linhas TOCADAS, e com catálogo estável (o estado normal) ele fica
parado enquanto a varredura roda perfeitamente. Foi assim que o alarme
acordou o Tel à toa às 3h20 de 01/09, depois de quatro varreduras
corretas. Um aviso por dia enquanto durar. Log ninguém lê: foi
assim que ela ficou de 28/08 a 31/08 parada e o sintoma que chegou ao
Tel foi outro, três dias depois ("não encontrei o imóvel pelo 5717").

**Cuidado com o "congelada em 10/08" do doc 25: está desatualizado.**
Medido em 27/08/2026: `imoveis` tem 1.201 linhas com `sincronizado_em`
de **21/08**, ou seja a varredura rodou de novo depois do que o doc
registra. Mas 6 dias de atraso já bastam para a Nay não conhecer imóvel
recente — conferido no mesmo dia: os códigos **2943 e 5750 não existem
na tabela**, e o 2943 está no site e é lido normalmente pelo publicador.
Antes de culpar a lógica por um "não encontrei", rodar:
`SELECT max(sincronizado_em) FROM imoveis;` e conferir se o código
específico está lá.

**O fluxo do n8n `Nay- recebe mensagem` (id `sQuiEjbEDMEbjX5U`).** O nó
`Juntar mensagens` se divide em **TRÊS ramos paralelos** que rodam ao
mesmo tempo:
- `Achar codigo` → caminho de código puro (só dispara para `^\d{3,5}$`)
- `Rotear para o agente` → cérebro
- `Comando do Tel` → publicador (`POST http://172.16.0.1:8080/comando`)

`return []` num ramo encerra **só aquele ramo**. Para um comando não
gerar resposta dupla, o `Rotear para o agente` precisa descartar também.

**As mensagens que SAEM ainda não chegam** (medido em 31/08: 2.956
recebidas, **zero** enviadas). O código do fluxo está certo — `fromMe` não
é mais descartado e grava com `direcao='enviada'` — mas a **Z-API não
dispara webhook de saída** nesta configuração. É opção no painel dela
("ao enviar"), não conserto de código. Enquanto isso, só se enxerga o
lado do corretor, e `nay_o_que_ficou_de_enviar` compensa cruzando
`mensagens` com `envios` em vez de depender do que ela disse.

**A pendência fecha o ciclo (01/09).** Quem pergunta a mesma coisa
depois do primeiro fica registrado em `pendencia_interessado` -- antes
ele ouvia "estou verificando" e sumia do registro, e quando o Tel
respondia só o primeiro recebia. Ao responder, os outros entram em
`resposta_a_entregar` e `ciclo_pendencias.py` (cron de minuto em minuto)
manda, com as mesmas paredes do lembrete. O primeiro continua recebendo
pelo sub-fluxo de sempre: **a assinatura de `nay_responder_pendencia` foi
preservada de propósito**, porque `nay_comando` faz `SELECT * INTO` dela
e mexer nas colunas quebraria o `RESPOSTA` do Tel.

O mesmo cron **cobra o Tel** das pendências esquecidas
(`nay_pendencias_esquecidas`), uma cobrança a cada 6 horas. O prazo mora
em `config.pendencia_horas_para_cobrar` (padrão 4h, escolhido por mim,
não pelo Tel) e muda com um UPDATE, sem deploy.

Uma ressalva honesta: o casamento de pendência aberta exige
`word_similarity >= 0.5`, então "aceita pet?" e "pode ter pet?" abrem
**duas** pendências e a lista de interessados não junta os dois. Baixar o
limiar juntaria perguntas diferentes, que é pior. A lista ajuda quando a
redação é próxima.

**`DESCARTAR <id>` também revoga resposta já gravada** (01/09). Antes ele
só agia em pendência aberta, e resposta errada ficava para sempre sendo
reusada naquele imóvel — não existia desfazer. Agora o mesmo comando
limpa a resposta e a pendência para de alimentar o reuso. A linha não é
apagada.

**O aprendizado da Nay pelas pendências.** Resposta que o Tel dá com
`RESPOSTA <id> <texto>` fica em `pendencias.resposta` e é **reusada**: na
próxima pergunta parecida, `nay_escalar` devolve "o Tel já respondeu isso
antes" e ela responde na hora, sem escalar. O casamento exige **o mesmo
imóvel** e assunto parecido (`word_similarity >= 0.5`) — antes de 31/08,
código nulo era curinga e casava com qualquer imóvel. Resposta gravada
sem código **não é reusada**, de propósito.

**O número da unidade NUNCA sai, e ela não promete verificar** (01/09).
O corretor que descobre o apartamento vai direto ao proprietário e o
negócio morre. A parede é `nay_pede_localizacao_da_unidade`, chamada
dentro do `nay_escalar`: a pergunta **nem vira pendência**, porque se
virasse o Tel responderia "ap 401" e o número ficaria em
`pendencias.resposta`, reusado naquele imóvel para sempre. O prompt já
proibia isso em quatro lugares e ela prometeu assim mesmo.

**A regra é por TIPO, decidida pelo Tel em 01/09:** apartamento pode
andar, torre e face solar, e o endereço do condomínio — o prédio é
público; nunca o número do apartamento. **Casa** pode rua e bairro,
**nunca o número dela** — o número é o que identifica a casa, igual ao
número do apartamento. Isso resolveu duas regras `endereco` ATIVAS e
contraditórias na tabela `regras` (a 1 liberava a rua, a 4 proibia a rua
de todo imóvel).

O card de imóvel administrado passa o logradouro por
`nay_endereco_sem_numero`: hoje o único com endereço é "Av. Curaçao", sem
número, mas 34 logradouros do catálogo têm número e a proteção não pode
depender da sorte do cadastro.

Para fechar ainda mais (andar e torre também):
`UPDATE config SET valor='tudo' WHERE chave='unidade_nivel';` — o mesmo
interruptor governa a recusa e a raspagem da descrição.

**O código do imóvel não pode vir da cabeça dela.** `nay_codigo_confirmado`
só aceita código que o corretor escreveu, ou o card único que ela mandou
na janela. Senão ela lista o que mandou e deixa ele escolher. Vale no
`nay_escalar` e no `nay_ficou_devendo` — sem isso o modelo inventa e a
resposta do Tel vira conhecimento permanente do imóvel errado.

**Todo portão deste projeto falha FECHADO.** Escrever "bloqueie se X"
abre quando X é desconhecido — foi assim que uma cliente não cadastrada
passou pelo porteiro em 30/08 (`Number(undefined) > 0` é falso, então a
condição inteira virava falsa). A forma correta é "só deixe passar se Y
for exatamente o esperado": `aprovado === true`, `msgs_antes === 0`,
`pausado !== false`, tudo dentro de `try/catch`. O padrão é negar, e o
dado precisa provar que pode.

**Antes de escrever regra no prompt, pergunte: com que ferramenta ela
faria isso?** Quatro bugs em dois dias tiveram a mesma causa —
**capacidade ausente vira promessa**. Fotos que ela não controlava
(o envio é de um nó), visita que não podia agendar (não fala com
ninguém), nome que não recebia (não vinha no input), busca por bairro
que não existia (as ferramentas exigiam condomínio). Em todos, o
resultado foi ela prometer e o corretor esperar. Sem a ferramenta, a
instrução não conserta: só muda o texto da promessa quebrada.

**As ferramentas dela hoje:** `imovel_por_codigo`, `resumo_do_condominio`,
`listar_no_condominio`, `buscar_por_perfil` (bairro+valor),
`avaliar_visita`, `como_funciona_a_visita`,
`guardar_como_funciona_a_visita`, `dados_do_corretor`,
`guardar_dados_do_corretor`, `responder_pendencia`, `escalar_ao_tel`.
Só a última e a `responder_pendencia` mandam mensagem para fora.

**O WhatsApp entrega `@lid` no lugar do telefone** (29/08). O WhatsApp
está migrando para LID, e a Z-API manda `phone` como
`219958210478302@lid` em parte das mensagens — a **mesma pessoa** chega
ora de um jeito, ora do outro, no mesmo dia. Isso quebrava o porteiro
(corretor vira desconhecido e recebe a cortesia dizendo que não é
parceiro) e até os comandos do Tel, que também aparece como `@lid`.

`nay_resolver_identidade(id, nome)` roda no `Gravar na fila` **antes de
gravar**, então tudo a jusante já vê o telefone canônico. Resolve pelo
`senderName`, que sobrevive nos dois formatos — a Z-API **não** manda o
telefone junto do `@lid` em mensagem direta (`participantPhone` vem
vazio). Aprende sozinho e grava em `identidade_lid`. **Nome que aponta
para dois telefones NÃO resolve** — atender uma pessoa achando que é
outra mostraria a conversa de um corretor a outro. Rodar
`saude.sql` mostra quem ficou sem resolver.

**A Z-API MANDA sim o sinal de citação, e o campo se chama
`referenceMessageId`** (corrigido em 01/09; até então este arquivo dizia
o contrário e isso custou um dia). O código procurava
`referencedMessage`, nome parecido e errado, então a citação nunca
chegava.

**A captura está em `imagem_estrutura`, não em `payload_estrutura`** — a
segunda foi criada para isso e tem ZERO linhas; o `$7` do `Gravar na
fila` vai para a primeira. As linhas 6 a 9 são as capturas de campo de
raiz: o campo aparece nas **2 marcadas** e falta nas 2 comuns, inclusive
numa do mesmo Gustavo sete segundos depois — 4 de 4.

**Ressalva honesta:** nessas 4 capturas, `referenceMessageId`,
`adContext` e `messageExpirationSeconds` aparecem e somem **juntos**. Com
n=4 a amostra não distingue qual dos três é o sinal de citação;
`referenceMessageId` é o nome semanticamente certo, e por isso ele só
liga um **aviso** para ela perguntar, nunca um bloqueio. Antes de virar
parede dura, ampliar a captura.

**Só o ID chega, nunca o texto — e por isso o outro lado precisa
existir.** Desde 01/09 `envios.message_id` guarda o ID de CADA card que
sai, pelos três caminhos: disparo de grupo e envio comandado (publicador,
via `id_da_mensagem`, que aceita `messageId`, `id` e `zaapId`) e o card
que a própria Nay manda (`Preparar registro` colhe do nó `Enviar Z-API`).
Com o ID na ponta e o ID guardado, `nay_imovel_da_citacao` resolve por
**igualdade** — não por semelhança, não por janela de tempo.

Quando não resolve devolve NULL, e NULL leva a **perguntar** com a lista
dos cards que ela mandou. Nunca a chutar. Os 86 envios anteriores a 01/09
não têm ID: a citação deles cai na pergunta, e é o certo.

**A citação só resolve se o ID tiver sido GUARDADO -- e até 01/09 ele não
era.** O `referenceMessageId` chega (isso estava certo), mas o outro lado
faltava em três pontos: o `postar_easy` postava sem registrar; o
`Registrar envio` só gravava quando a resposta tinha `Código: NNNN` (card
sim, conversa não); e o par que ele gravava estava ERRADO -- `.first()`,
dentro do laço do n8n, é o primeiro item da ÚLTIMA rodada, então casava o
código do PRIMEIRO card com o ID do QUARTO.

Hoje **toda** mensagem que sai vira linha em `mensagem_saida`, gravada
pelo nó `Registrar saida`, que fica DENTRO do laço (entre `Enviar Z-API` e
`Loop fotos`) -- ali o ID e o texto da mesma iteração andam juntos.
`nay_imovel_da_citacao` olha `envios` primeiro (registro explícito) e o
texto depois; dois códigos na mensagem citada devolve NULL, e NULL leva a
perguntar **com a lista** (`nay_opcoes_da_citacao`).

**Para ler o que um nó do n8n REALMENTE entregou**, sem supor: as
execuções ficam em `/home/node/.n8n/database.sqlite`, tabela
`execution_data`, no formato `flatted`. O `sqlite3` mora em
`/usr/local/lib/node_modules/n8n/node_modules/`. Foi assim que apareceu o
par trocado -- lendo código eu não teria achado.

**Bairro tem zona, e ela não oferece o outro lado da cidade.**
`bairro_zona` + `bairro_vizinho` alimentam `nay_bairros_proximos`, usada
pelo `buscar_por_perfil`: sem nada no bairro pedido, ela oferece só
VIZINHO, dizendo o bairro de cada um; sem nada nem perto, faz as três
perguntas (valor, quartos, bairros). O zoneamento é o administrativo de
Manaus e **precisa da conferência do Tel** -- é UPDATE, sem deploy.

**O turno carrega o que ficou pendente.** `negocioPedido='ambos'` (ele
falou de venda E locação) e `pedeVisita` viram avisos no `text` do agente,
como o `pedeUnidade` já fazia. São AVISOS, não paredes: não existe
ferramenta que force uma resposta a cobrir dois assuntos.

**NUNCA supor pelo último disparo.** O Tel foi explícito em 01/09: "são
disparados mais de 3 imóveis por dia nos grupos, concluir que foi o
último disparado é um tiro no pé para vários erros".

O que o corretor faz de verdade é colar ou encaminhar o card do grupo, e
aí o texto chega inteiro. O `Juntar mensagens` detecta isso (tem
`Código: NNNN` e `📍` ou `•`) e transforma em instrução, para ela **não
devolver o mesmo card** que ele acabou de mandar.

**Pausar e despausar a Nay** (29/08). Chave geral na tabela `config`:

```
-- pausar
UPDATE config SET valor='sim' WHERE chave='atendimento_pausado';
-- voltar a atender
UPDATE config SET valor='nao' WHERE chave='atendimento_pausado';
```

Vale na hora, sem import nem restart — o `Gravar na fila` lê a cada
mensagem. Pausada, **nenhum corretor recebe nada**, nem a cortesia do
porteiro (que diria a um parceiro de verdade que ele não é parceiro). As
mensagens continuam sendo gravadas em `mensagens`, para responder depois,
e os comandos do Tel seguem funcionando. Não desative o fluxo no n8n para
pausar: o webhook pararia e as mensagens do período seriam **perdidas**.

**`queryReplacement` do Postgres nunca em string separada por vírgula.**
O n8n avalia cada `{{ }}` e, se o resultado for texto, roda
`stringToArray`, que **divide por vírgula** — comendo o resto de qualquer
valor que contenha uma. Isso truncou TODA mensagem com vírgula desde o
início do projeto (descoberto em 29/08: 0 vírgulas em 1.885 mensagens).
Use sempre **uma expressão que devolva array**:
`={{ [$json.a, $json.b ?? null] }}`. O `?? null` não é enfeite:
`undefined` é pulado pelo n8n e desloca os parâmetros seguintes.

**A regra das 2 horas, e a tabela `equipe`** (29/08). O Fernando não é
corretor — está em `equipe` (papel `acompanhante`), não em `corretores`,
senão o porteiro passaria a atendê-lo como corretor. **O CPF dele mora só
no banco, nunca em arquivo do repositório.** `nay_e_da_equipe` casa o
telefone pelos **8 últimos dígitos**, porque a Z-API entrega número
brasileiro ora com o 9 na frente (13 dígitos) ora sem (12) — igualdade
crua não serve.

`nay_avaliar_visita(codigo, quando, nome)` concentra a decisão: menos de
2 horas **e** o proprietário acompanha → aciona o Tel e diz ao corretor
"está um pouco em cima"; menos de 2 horas sem o proprietário (chave ou
senha) → segue normal; não sabe como funciona → pergunta ao Tel em vez de
supor. O flag é `imovel_privado.proprietario_acompanha` (NULL = não sabe).
A ferramenta é `avaliar_visita`.

**Como funciona a visita, por imóvel** (29/08). Cada proprietário tem um
arranjo diferente — chave com a gente, fechadura eletrônica, agendar com o
dono — e isso não existe no cadastro público. Mora em
`imovel_privado.como_funciona_visita` (tabela privada, fora do alcance das
ferramentas de corretor). Duas ferramentas: `como_funciona_a_visita` (lê,
e quando está vazio manda ela perguntar ao Tel) e
`guardar_como_funciona_a_visita` (grava). **Só o Tel grava:** o telefone
vem do fluxo (`$('Juntar mensagens').first().json.telefone`), não do
modelo. É um laço de aprendizado: ela pergunta uma vez por imóvel e não
pergunta de novo. A varredura não apaga — só toca `imoveis`.

**Responder pendência conversando** (29/08). O Tel não precisa mais
digitar `RESPOSTA 17 pode ser 15h` — pode escrever "pode ser 15h" e a Nay
entende. Peças: função `nay_responder_conversando`, tabela
`pendencia_rascunho`, sub-fluxo `Nay - responder pendencia`
(`NayRespConv00001`) e a ferramenta `responder_pendencia`.
**A confirmação é parede, não pedido:** a função recebe `msg_id` vindo do
fluxo (`$('Gravar na fila').first().json.id`), que o modelo não consegue
forjar. Primeira chamada grava rascunho e devolve a frase de confirmação;
segunda chamada com o MESMO `msg_id` é recusada. Só um `msg_id` maior —
ou seja, uma mensagem nova do Tel — libera o envio. O comando
`RESPOSTA <id> <texto>` continua funcionando e é o caminho à prova de
tudo. Ferramenta de banco não envia mensagem: quem envia é sub-fluxo,
como o `escalar_ao_tel` já fazia.

**A Nay não fala com ninguém além do corretor.** As sete ferramentas dela
são de consulta — não existe nenhuma que mande mensagem a proprietário,
ao Fernando ou a terceiro. O único canal de saída é `escalar_ao_tel`.
Antes de escrever no prompt "pergunte ao proprietário" ou qualquer coisa
que exija ação fora da conversa, lembrar disso: em 29/08 essa exata
instrução fez ela prometer "vou verificar" numa visita e não escalar
nada. Vale a pergunta antes de toda regra nova: **quem executa isso?**

**O que o agente recebe.** O campo `text` do nó `AI Agent` — hora de
Manaus, **nome** do corretor, texto da mensagem, e desde 01/09 dois
avisos condicionais (pergunta de unidade, e citação não resolvida). Não
recebe telefone.

**MAS ele TEM histórico**, e este arquivo dizia que não: existe um nó
`Postgres Chat Memory` ligado ao agente, tabela `nay_memoria`, janela de
**15 mensagens**, chaveada pelo telefone. Foi dali que saiu o "5717" que
ele inventou na conversa do Gustavo em 01/09 — tinham falado desse imóvel
antes e o modelo preencheu o buraco com o que estava à mão. Ao investigar
"de onde ela tirou isso", `nay_memoria` é o primeiro lugar a olhar, e
`SELECT message FROM nay_memoria WHERE session_id LIKE '%<8 digitos>%'`
reconstrói a conversa inteira, inclusive as chamadas de ferramenta com os
argumentos.

**Quem a Nay atende: a tabela `corretores`.** Desde 29/08 a trava de
teste saiu. O `Gravar na fila` devolve `aprovado` (existe em `corretores`
com `aprovado AND ativo`) e `msgs_antes` (quantas mensagens aquele número
já mandou), e três nós leem isso: `Rotear para o agente` (corta o
desconhecido reincidente antes de gastar chamada de modelo), `Preparar
envio do agente` (cortesia + aviso ao Tel na primeira mensagem de
desconhecido) e `Preparar envio` (silêncio no caminho de código puro).
São **1.050 aprovados**, e o Tel está entre eles — tirá-lo da tabela
derruba os comandos dele junto. Para cadastrar alguém:
`INSERT INTO corretores (telefone, nome, aprovado, ativo) VALUES ('55929...', 'Nome', true, true);`
Reverter tudo: `/root/backups-n8n/bk_20260829_antes_porteiro.json`.

**O condomínio é identificado por FAIXA de precisão, não por parecença**
(01/09). `nay_disponibilidade_no_condominio` compara em cinco faixas --
nome inteiro, chave igual, palavras do cadastro contidas no que ele
escreveu, o que ele escreveu contido no cadastro, e só então parecença --
e **só a melhor faixa não vazia vira candidato**. A ambiguidade vale
dentro da faixa, nunca entre faixas. Sem isso, quanto mais preciso o
corretor, pior a resposta: "Liverpool" acertava e "Liverpool Reserva
Inglesa" -- o nome exato, e o que vem colado num anúncio -- caía em "temos
mais de um", porque `word_similarity` com o "London Reserva Inglesa" dá
0.615 contra o limiar de 0.6. 47 dos nomes do catálogo não se resolviam a
si mesmos, e o nome que ela oferecia na lista devolvia a mesma pergunta.

A faixa de parecença **não afirma nada**: devolve "você quis dizer X?",
igual ao `nay_bairro_parecido`. Negar com firmeza um condomínio que ele
nem perguntou é o dano sério deste funil, porque a instrução manda **não
escalar**.

**Imóvel sem anúncio no ar NÃO é oferecido** (09/09). O Tel tirou os sete
apartamentos do Brisas do Lírio do site, a varredura viu e marcou
`publicado_no_site = false` -- e eles continuaram saindo na lista. Das 17
funções da Nay que leem `imoveis`, **nenhuma** olhava essa coluna: **35
imóveis** fora do site seguiam sendo oferecidos.

Isso **não** contradiz a regra 2. Ela governa o que a VARREDURA escreve --
sumir do site não pode apagar cadastro nem marcar indisponível. O que mudou é
o que a Nay OFERECE. As duas convivem: o imóvel continua no banco, com toda a
sua história, e simplesmente não é mais oferecido enquanto não tiver anúncio.

A regra mora em `nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site)`
(`oferta_so_com_anuncio.sql`), UMA função chamada nos cinco pontos onde se
decide oferta: a busca por perfil (lista principal e vizinhos), o condomínio
(contadores e lista) e a lista por categoria. Repetir a condição em cinco
lugares era criar de novo a divergência que o próprio `buscar_por_perfil` já
avisa no comentário. `e_parceiro` fica de fora dela de propósito: não é sobre
o imóvel estar ativo, é sobre de quem ele é -- e o condomínio precisa contar
os de parceria à parte para poder dizer "no X o que eu tenho é imóvel de
parceria". Falha FECHADA: `publicado_no_site` nulo não é ofertável.
`teste_oferta_so_com_anuncio.sql`, 17 casos.

**Reconhecer o nome e poder oferecer o imóvel são decisões diferentes.**
Os candidatos saem de TODO o cadastro -- parceiro e indisponível
inclusive -- e a política de oferta entra depois. Antes os candidatos
saíam só do que é nosso e disponível, e por isso 177 de 387 condomínios
eram declarados INEXISTENTES (136 com anúncio no ar) e 51 resolviam para
o vizinho. Hoje "no X o que eu tenho é imóvel de parceria" e "no X não
tenho nada disponível no momento" são respostas próprias, distintas de
"esse condomínio não existe". `teste_disponibilidade_condominio.sql`
segura isso com uma asserção contra o catálogo inteiro: **todo condomínio
tem que se resolver a si mesmo** (387 de 387 hoje).

**O portão de fotos lê `textoCru`, não `texto`** (01/09). Para áudio, o
`Juntar mensagens` troca a fala do corretor por um envelope de sistema, e
ele terminava em "Antes de mandar imovel ou **fotos**" -- então
`nay_deve_mandar_fotos` devolvia `true` para 100% dos áudios, qualquer que
fosse o conteúdo. O envelope continua indo ao modelo, que é para quem foi
escrito; ao portão vai a fala dele. **Texto que o próprio fluxo escreve
nunca pode entrar num detector.** O `escreveu` do guarda de comando
continua lendo o texto INTEIRO de propósito -- se `textoCru` faltasse, ele
voltaria a deixar "Nay envia as fotos do 5750 pro Sergio" mandar fotos
para o chat do Tel.

E "já tenho as fotos" virou parede no caminho 0 da função, com a negação
exigida COLADA à palavra de foto (mesma oração) e escape para pedido
explícito -- sem o escape, "já recebi o card mas não recebi as fotos,
manda por favor" seria bloqueado, que é o caso André de novo.

**`RESPOSTA <id>` também vira conhecimento do imóvel** (01/09). Era o
buraco do laço de aprendizado: `imovel_conhecimento` só era escrita pela
ferramenta do agente, e o `Rotear para o agente` DESCARTA comando -- então
o caminho que o Tel mais usa nunca chegava ao agente. Agora
`nay_responder_pendencia` grava por assunto canônico, nunca sem código e
nunca com número de unidade. E `nay_esquecer_imovel` (o VENDEU/ALUGOU)
limpa os **dois** lugares: antes esquecia `imovel_conhecimento` e deixava
`pendencias.resposta` viva, que é onde a mesma informação estava.

**Nome de empresa não é nome de gente.** `nay_nome_de_pessoa` roda no
`Reservar mensagens` e o modelo passa a ver `nomePessoa`, não o
`senderName` cru -- "OPEN SERVIÇOS" vira NULL, e NULL já cai no "nao sei o
nome dele" que manda perguntar. O critério é estreito de propósito:
medido, 5 de 185 nomes reais viram pergunta. E `guardar_dados_do_corretor`
grava `nome_origem='manual'`, senão o `nay_sincronizar_nome` do `Gravar na
fila` apaga na mensagem seguinte e ela pergunta o nome para sempre.

**`RESPOSTA <id> descartar` é um DESCARTAR**, não uma resposta com a
palavra dentro (01/09). O Tel escreveu isso e o corretor recebeu a palavra
"descartar" como resposta sobre as vagas de garagem do 5035. O ramo é
estreito de propósito -- só quando o texto INTEIRO é o verbo; "pode
descartar aquela proposta" continua sendo resposta.


**`comando_descartar_resposta.sql` é GERADO da produção**, não editado à
mão. Ele se declara "o corpo inteiro de `nay_comando`" e traz o passo de
deploy no cabeçalho -- um arquivo velho, rodado por quem for fazer o
ajuste seguinte, apaga a correção anterior em silêncio. `rodar_testes.sh
--com-banco` compara o arquivo com o `prosrc` vivo e falha na divergência.

**Quem manda as fotos não é a Nay.** O nó `Achar codigo na resposta`
roda uma regex na resposta **dela** e, se achar `Código: NNNN`, busca as
fotos e envia. O modelo não tem ferramenta de foto e não decide nada
disso — escrever no prompt "não mande fotos" é instrução morta. Desde
29/08 o gatilho exige que o corretor **tenha pedido**
(`foto|fotos|imagem|imagens|fachada|frente|vídeo`), e o código é lido da
resposta dela ou da pergunta. Ao mexer nisso, testar a regex no Node do
container antes do import.

**A busca por bairro normaliza os dois lados (01/09).** `taruma` acha
`Tarumã` e `pq dez` acha `Parque 10 de Novembro`, por
`nay_normalizar_lugar` (acento, pontuação, abreviação, número por
extenso). Antes era `ILIKE` cru, e 394 dos 1.172 imóveis moram em bairro
com acento ou número — um terço do catálogo respondia "não temos imóvel
disponível nesse perfil". E o vazio agora tem **três** respostas
diferentes, porque tinha três causas: bairro que bate mas o perfil não
(escala ao Tel), nome escrito diferente ("você quis dizer Ponta Negra?"),
e bairro fora da nossa área (**não** escala — não é demanda não atendida).

**Valor não é código.** Os códigos deste catálogo vão de 45 a 5712, a
mesma faixa de um orçamento de aluguel: "Paga até 4000" virava dívida do
imóvel 4000, que existe. `nay_codigos_citados` tira os valores antes de
procurar código (`valor_nao_e_codigo.sql`), e os 25 casos vivem em
`teste_valor_nao_e_codigo.sql`. Ao mexer ali, medir contra as mensagens
reais: a primeira versão limpava os valores e comia o `Código: 1327` do
card junto, porque o vão da regex atravessava a quebra de linha.

**`CREATE OR REPLACE` com assinatura diferente NÃO substitui: cria uma
sobrecarga.** Em 31/08 havia duas `nay_responder_conversando` — a de 4
argumentos com a parede de identidade e a antiga de 3 **sem parede
nenhuma**, ainda chamável. Ao mudar a assinatura de uma função, `DROP` a
antiga, e conferir depois com
`SELECT proname, pg_get_function_identity_arguments(oid) FROM pg_proc WHERE proname LIKE 'nay_%';`

**A gramática de comando existe em SETE cópias, em DOIS fluxos** (medido em
23/09; este arquivo dizia QUATRO e a conta estava velha — faltava o fluxo
inteiro da NAI, que é quem atende os comandos do Tel hoje):

| onde | qual | o que faz |
|---|---|---|
| repo | `interpretar_comando.py` | o publicador |
| Nay antiga | `Comando do Tel` | manda ao publicador |
| Nay antiga | `Rotear para o agente` | **DESCARTA**, senão o Tel recebe resposta dupla |
| Nay antiga | `Achar codigo na resposta` | não deixa o texto DELE virar foto |
| NAI | `Comando do Tel` | idem ao segundo |
| NAI | `Rotear pelo cabeçalho` | roteia para `tel_antigo` — **é o decisivo** |
| NAI | `Achar codigo na resposta` | idem ao quarto |

Sem a do `Achar codigo na resposta`, "Nay envia as **fotos** do 5750 pro
Sergio" faz o gatilho de fotos ler o texto do próprio Tel e mandar as fotos
para o chat **dele**.

**A da NAI é a que mais escapa**, e escapou duas vezes em 23/09: consertei o
Python, depois os nós da Nay antiga, e o comando continuou morto — porque quem
decide se a frase vai ao publicador ou ao modelo é o `Rotear pelo cabeçalho`
da NAI. O sintoma foi ele receber resposta **sobre si mesmo** ("o corretor Tel
Sobreira pediu fotos do 150").

Ao acrescentar ou mudar um verbo, mexer nas sete. Duas fontes únicas:
`casos_comando_envio.json` (o `ENVIO_RE`, com preposição) e
`casos_telefone_na_frente.json` (o telefone antes do código) — lidas pelo
Python e pelo Node do container, então divergência vira teste vermelho em vez
de comando morto.

**E `provar_nos_do_envio.js` só cobre a NAY ANTIGA.** Ele monta um `$` de
mentira com `Juntar mensagens` e `Rotear para o agente`, que na NAI não
existem — rodá-lo contra o fluxo dela falha na topologia, não na lógica. Os
nós da NAI se provam com `provar_nos_da_nai.js`, que alimenta o `cab` de
`Abrir turno` e afirma a **rota**: `tel_antigo` vai ao publicador,
`tel_nai` fica na NAI, e qualquer outra coisa vai ao modelo.

**Os sete crons no servidor** (13/09). Todos com `flock` e todos
silenciosos quando não há nada — o log só cresce quando algo aconteceu:

| quando | o quê |
|---|---|
| todo minuto | `disparar_grade.sh` — a grade de postagem |
| todo minuto | `disparar_lembretes.sh` — cobra retorno do corretor |
| todo minuto | `entregar_pendentes.sh` — manda o imóvel que ficou de mandar |
| todo minuto | `ciclo_pendencias.sh` — entrega resposta e cobra o Tel |
| todo minuto | `alertar_visitas.sh` — os 5 alertas da agenda de visitas |
| todo minuto | `detectar_visitas.sh` — põe na grade o que o corretor pediu |
| :17 de cada hora | `sincronizar_catalogo.sh` — varredura + alarme |

**Deploy do publicador** (só código Python):
```
# no Mac
.venv/bin/python teste_interpretar_comando.py   # e as outras suites
git commit && git push && git rev-parse HEAD    # ANOTE o hash
# no servidor
cd /root/nay-publicador && git pull origin main
git rev-parse HEAD                              # tem que bater
systemctl restart nay-publicador                # SEM ISSO NADA MUDA
```
`git pull` sozinho não aplica nada: o systemd segura o código velho em
memória e o `systemctl status` continua "active (running)". O cron da
grade (`disparar_grade.sh`) sobe Python novo a cada execução, então
pega a mudança sem restart — só o serviço HTTP precisa.

**Deploy de um nó do n8n** (ordem obrigatória, as quatro juntas):
```
docker exec n8n-viux-n8n-1 n8n export:workflow --id=<id> --output=/tmp/bk.json   # backup ANTES
docker exec -i n8n-viux-n8n-1 sh -c 'cat > /tmp/p.json' < /tmp/patched.json
docker exec n8n-viux-n8n-1 n8n import:workflow --input=/tmp/p.json
docker exec n8n-viux-n8n-1 n8n update:workflow --id=<id> --active=true
docker stop -t 40 n8n-viux-n8n-1 && docker start n8n-viux-n8n-1
```

**`docker stop -t 40`, nunca `docker restart`.** A carência padrão do
restart é de 10 segundos e o nó `Janela de 25s` espera 25 — então toda
mensagem que estiver na janela naquele instante é MORTA. O n8n reporta
"Workflow did not finish, possible out-of-memory issue", que é literal
fixo do caminho de recuperação e **não mede memória nenhuma**: em 01/09
gastei tempo olhando `docker stats` por causa dessa frase, e o container
usava 5% da RAM. Foi assim que o comando "publica no nosso grupo anunciar
easy código 5664" do Tel sumiu sem ninguém saber.

Antes de reiniciar, conferir que a fila está vazia:
`SELECT count(*) FROM mensagens WHERE status='Recebido';`
O `import` **desativa o fluxo** ("Deactivating workflow") e só o
`restart` reativa. Parar no meio deixa a Nay fora do ar. Backups em
`/root/backups-n8n/`. Conferir depois com
`docker logs --since 2m n8n-viux-n8n-1 | grep "Activated workflow"`.

**`node --check` NÃO BASTA, e isso foi medido duas vezes em 12/09.** Ele passa
em `$'` dentro de uma regex (padrão especial de substituição do
`String.replace` do JS, que truncou o literal numa string sem fechar) e passa
em declaração duplicada quando os escopos parecem diferentes -- os dois
derrubariam o nó INTEIRO. Quem pegou foi `provar_nos_do_envio.js`, que EXECUTA
a lógica do nó contra o workflow exportado. Duas regras que saem daí:
`() => texto` em todo `String.replace` cujo replacement seja código, e bloco
inserido por patch tem que ser DELIMITADO por marcadores, para ser trocado
inteiro em vez de empilhado (guarda por mudança não substitui delimitador).

**Antes de importar, sempre validar no Node do próprio container:**
`node --check` para sintaxe e um teste das regex com os casos reais.
JavaScript sintaticamente válido quebra em execução — um `_` solto no
fim de uma linha passou no `--check` e derrubou o nó inteiro em produção.

**Números que mudam e já enganaram:** os grupos ativos eram 10, depois 14;
em 15/09 são **19** -- 18 de parceiro e o do Easy (`todas_fotos`).

**Grupo pode ter regra de VALOR (15/09).** `grupos.aluguel_minimo`,
`venda_minima` e `so_condominio` (nulo/false = sem regra). O "🟢 Alto Padrão -
OFERTA e BUSCA 🔍" usa 6.500 / 1.000.000 / condomínio, com o piso ENTRANDO. A
regra mora em `montar_destinos.negocios_do_grupo`, que decide três coisas: se o
imóvel entra no grupo, que valor o card mostra lá (o Alto Padrão não vê o
aluguel de 5 mil de um imóvel que entrou pela venda) e que lista o grupo recebe
(`nay_lista_de_imoveis(categoria, negocio, piso, so_condominio)` -- filtrada,
título recalculado, e NADA quando nenhum passa). O "🟢 Locação OFERTA e BUSCA
🔍 - CREDENCIADOS" é só locação, sem piso.

**Grupo pode ser SÓ COMERCIAL (15/09).** `grupos.so_comercial`: o "🟢 Comercial -
OFERTA e BUSCA 🔍" recebe só Sala, Sala/Andar, Loja/Ponto, Galpão/Depósito e
Prédio (`montar_destinos.e_comercial`, pelo tipo). **Prédio entra por decisão do
Tel**, sabendo que o cadastro não separa prédio comercial de residencial (o 3957
é unidade de 2 dormitórios cadastrada como Prédio). Nas listas, só a de sala
comercial chega nele; apartamento, casa e lote pulam o grupo e a resposta diz.

O "📍CREDENCIADOS" | Corretores Performance" (venda e locação, uma
foto), com o ID tirado da própria Z-API (`GET groups`) e conferido antes em
`group-metadata` que `adminOnlyMessage` é falso -- grupo só-admin faria todo
disparo falhar para ele sem aviso. Para um grupo novo, o caminho é esse: o
ID sai da Z-API, e a tabela `grupos` é a fonte (o `grupos.csv` é só
pré-visualização). Um `posta` leva ~50-60s pela cadência anti-banimento
(`enviar_zapi.py`), não 35s. Não reenviar no meio: `postar_agora` **não
tem proteção contra repetição** (só `postar_easy` tem reserva atômica),
então reenviar posta duas vezes em 14 grupos, sem desfazer.

**Fuso.** `disparar_grade.py` dispara em `America/Manaus` (UTC-4). O
celular do Tel está em horário de Brasília (UTC-3), uma hora à frente.
Decisão do Tel em 27/08: **deixar como está**. Ao ler log ou comparar
carimbo de WhatsApp com hora de servidor, lembrar da diferença de 3h
para UTC.

## Comandos que a Nay entende hoje

**Enviar imóvel para um corretor** (31/08). `Nay manda o 5750 pro Sergio`,
`Nay envia os acquarelle pra Samira`, `manda o 5750 p/ 92 99999-8888`.
Vai o card e **todas** as fotos. Não conta no teto de uma mensagem por
dia — quem pediu foi o Tel.

A **preposição é obrigatória** e é ela que separa isto de `posta`, que vai
para os 14 grupos. `Nay posta o 5750 pro Rogério` é **recusado** com
explicação, nunca postado. Cauda que menciona grupo/easy/grade cai no
caminho antigo.

Número não cadastrado **não recebe**: ela avisa e pede o nome para
cadastrar. Nome ambíguo também não resolve — mandar a carteira para o
corretor errado não tem desfazer.

O vocativo "Nay" no começo é aceito desde 27/08, em todos os caminhos
(`@Nay`, `Nay,`, `Nay:` também). O que **não** é aceito, de propósito:
vocativo fora do começo (`oi Nay posta...`), e nome parecido (`Nayara`).

| Comando | O que faz |
|---|---|
| `Nay posta o 5750` | posta agora nos grupos elegíveis |
| `Nay posta o 5750 todo dia às 14h` | cria vaga diária |
| `Nay posta 5750 e 5751 terça e quinta às 9h` | cria vaga semanal |
| `Nay VENDEU 5750` / `ALUGOU 5750` | tira das vagas **e da oferta** — imóvel saiu do mercado |
| `Nay tira o 5750` / `remove o 5750` | tira das vagas **sem** dizer que vendeu |
| `Nay VAGAS` | lista a grade |
| `Nay publica no anunciar easy o 5750` | grupo Easy, com todas as fotos -- já postado, ela PERGUNTA se posta de novo |
| `sim` / `pode postar novamente` / `não` | responde a pergunta dela (só vale com pergunta aberta, 30 min) |
| `Nay posta no anunciar easy de novo o 5750` | posta de novo sem perguntar -- a frase já confirma |
| `Nay lista de apartamento para locação` | mostra a lista da categoria **para ele**, no privado |
| `Nay dispara lista de apartamento para locação` | manda essa mesma lista **nos grupos de parceiro** |
| `Nay dispara lista de sala comercial para locação no anunciar easy` | manda **só** no grupo de todas as fotos |
| `dispara apartamentos para locação todo dia às 9h` | põe a lista **na grade** — sai sozinha |
| `Nay tira a lista de apartamento para locação` | tira a lista da grade |
| `Nay agenda de visitas` | as visitas FUTURAS, com dia e hora |

**A grade de visitas se enche sozinha (13/09).** `detectar_visitas.py` varre as
mensagens dos corretores de minuto em minuto e escreve na tabela `visita`.
Antes disso **nada escrevia nela** -- a tabela, o cron de alertas e o comando
subiram em 11/09 e o mecanismo de ENTRADA, não; as visitas que apareciam
tinham sido inseridas à mão.

CRON e não ferramenta do agente, porque a Nay está PAUSADA para corretores.
SEPARADO do `alertar_visitas.py` porque aquele é o APAGADOR -- escritor no
mesmo processo escreve e apaga no mesmo minuto, sem deixar rastro.

**As exclusões são medidas em 6.114 mensagens reais:** um detector ingênuo
casa 54 e 67% delas não são agendamento. As quatro que menos se enxergam: a
PRÓPRIA saída do alertador está na tabela e casa o detector inteiro (por isso o
`direcao = 'recebida'` não é detalhe); o Tel escapa pelo `@lid` e os comandos
de grade dele casam; faixa de preço parece hora; e "As 2 visitas de sábado não
deram certo" virava visita fantasma às 02h00.

**Sem o dia ela PERGUNTA** -- 64% das mensagens com hora não dizem o dia, e
assumir "hoje" acerta só 69%. **"amanhã" é relativo à MENSAGEM**, não ao
relógio. E **a primeira rodada não processa histórico**: o carimbo
(`config.visita_detector_ate_id`) nasce no fim da fila.

**Remarcar troca só a visita do MESMO dia** -- quem agenda dois imóveis em dias
diferentes tem duas visitas, e a versão que trocava sempre apagou uma de
verdade na prova de ponta a ponta.
| `Nay envia esses imóveis para <nome ou número>` + a lista | manda os imóveis da lista colada ao corretor |
| `os dois` / `ambos` / `todos` / `o primeiro` / `codigo 5719` | desempata a lista que ficou esperando |
| `envia toda as casas de locação até 4.200 para <nome> <telefone>` | pedido DESCRITO: resolve no catálogo e manda |
| `manda para Ana <telefone> os dois acquarelle de 2 e 3 quartos para locação` | idem, com quantidade e quartos |

**O pedido descrito (14/09).** O Tel pede do jeito que fala e a Nay resolve
no catálogo (`pedido_de_imoveis.py`). **O telefone é o destino** onde quer que
esteja na frase -- no meio ("para Ana 92 9396-5797 os imóveis que...") ou no
fim. **A política é a da lista oficial**: nosso e no ar; o que fica de fora
(fora do site, parceiro) é dito. Lê condomínio CONTIDO na frase ("morada do
pássaros" casa "Morada dos Pássaros"), casa/apartamento ("casa" sozinha são as
duas), "2 e 3 quartos", locação/venda, teto ("até 4.200"), "os dois", "todas".

**E BAIRRO, desde 15/09** (`casar_bairros`). "flores, paz, parque dez, compensa,
parque das laranjeiras" resolve os cinco -- a normalização vem do BANCO
(`nay_normalizar_lugar`), que sabe que "parque dez" é "Parque 10 de Novembro".
Duas faixas: nome inteiro escrito, ou METADE das palavras e NUNCA UMA SÓ --
com uma só, "parque dez" arrastaria "Parque das Laranjeiras" junto.

**O BAIRRO GANHA DO CONDOMÍNIO** quando o nome dele está dentro do bairro:
"parque das laranjeiras" fazia casar os condomínios "Laranjeiras", a consulta
virava bairro E condomínio e não sobrava nada. E "locações" no plural passou a
contar como locação (`\bloca[çc][ãaoõ]\w*\b`) -- antes o pedido ficava sem
negócio. As duas coisas juntas eram por que o pedido do Tel em 15/09 devolveu
"não achei imóvel para ...".

**A recusa diz o que ela ENTENDEU**: "(entendi: casa em condomínio, casa em via
pública; locação; no bairro Parque 10 de Novembro; até 4.000)" -- ele vê na hora
que ela leu CASA e que ali só existe apartamento.

Paredes que custaram erro para descobrir: **valor não é código** ("4.200"
virava os imóveis 4 e 200); **valor solto é exato** ("3.5k" não manda o de 4k);
**só categoria não basta** (nome errado não vira "todas as casas"); **nome de
condomínio de uma palavra colado a palavra desconhecida não casa** ("xanadu
imperial" não é o Parque Imperial); **frase descrita não passa pelo casamento
reverso**, que não lê negócio -- só linha com " / " vai por ali; **teto de 15
por leva**; **card vazio nunca sai**. Número fora do cadastro que **já
conversou** com a Nay é cadastrado (o nome digitado vira `manual`); sem
histórico continua recusado; desativado nunca é reativado.

Limite conhecido: o ramo de lista do nó `Comando do Tel` ainda usa
`/\b\d{1,6}\b/` no cabeçalho -- lista de várias linhas com VALOR no cabeçalho
("envia os acquarelle até 4k para ... \n linha") vai só a primeira linha.

**O nome da nossa conta nunca é nome de corretor** (14/09). As mensagens que a
Nay envia chegam com `senderName` "Nay Mendes", e `nay_sincronizar_nome`
gravava isso por cima do corretor -- 8 renomeados. A parede mora na função
(`config.nome_da_conta_whatsapp`); a causa raiz no nó (`$6` não lido) continua
aberta.

**A lista COLADA vira envio (11/09).** Ele cola o que a própria Nay mandou:

    Nay envia esses imóveis para o número 92994717316
    Arezzo Residencial / 2 quartos / 2.5k
    Estilo Golf / 2 quartos sendo 1 suíte / 2.6k

A descoberta que define o desenho: **essas linhas são saída literal de
`nay_linha_da_lista`** -- a mesma que responde `Nay lista de apartamento para
locação`. Conferido caractere por caractere. Então o casamento é REVERSO
(`nay_imoveis_da_linha`, em `envio_por_descricao.sql`), não parecença: gera-se
a linha de cada candidato e compara-se.

E é o casamento reverso que explica a ambiguidade: **a função não é injetora.**
O 5719 e o 5728 são os dois 2 quartos / 1 suíte / 2.6k no Estilo Golf e rendem
a MESMA string -- por isso a linha aparece duplicada na colagem dele. Medido:
é a única linha ambígua da locação, mas na venda são 769 imóveis para 745
linhas.

**Três decisões dele, de 11/09, que mudam o comportamento:** SEGURA TUDO até
ele responder (nada sai enquanto a lista inteira não resolver, para o corretor
receber uma leva só); imóvel fora do site é recusa DITA nomeando o código,
nunca sumiço; linha repetida gera UMA pergunta que aceita os dois códigos.

**A RESPOSTA NATURAL VEM PRIMEIRO NA PERGUNTA (12/09).** Ela perguntava
*"qual? ... ou os dois"*, ele respondeu **"os dois"** e a frase caiu no agente.
A causa raiz não era a regex faltando: era a pergunta oferecer uma frase que o
parser não lia. **Toda frase que a Nay escreve faz parte da gramática** --
revisar perguntando "se ele copiar isto, eu entendo?".

Hoje valem `os dois`, `os 2`, `ambos`, `todos`, `o primeiro`, `o último`,
`5719 e 5728` e `codigo 5719`, com os prefixos que ele usa (`manda`, `quero`,
`pode mandar`, `sim,`). As opções saem NUMERADAS e ela pergunta **uma linha por
vez** -- com duas ambíguas, toda resposta curta seria "dois de qual linha?".

**O que NÃO é escolha, e cada um por um motivo medido:** `sim`/`isso` sozinhos
(é a palavra que libera a confirmação do `nay_responder_conversando`, e os três
ramos do fluxo rodam em PARALELO -- um "sim" dispararia dois envios
irreversíveis); `tudo` (compete com o `DESCARTAR TUDO SIM`); `me manda os dois`
(o "me" nomeia OUTRO destinatário -- é como ele pede o card para si);
dígito cru como `2` (o artigo é obrigatório: `os 2` sim, `2` não -- e "2" quer
dizer "o segundo", não "dois deles"); qualquer coisa com destinatário
(`manda os dois pro Sergio` é ENVIO); e as PRÓPRIAS LINHAS da lista
(`2 quartos sendo 1 suíte / 2.6k` virava "manda dois", e o nó percorre linha
por linha -- uma linha de PREÇO disparava o envio).

**A gramática natural mora no FIM do dispatch**, e isso é estrutural:
`codigo NNNN` pode ir cedo porque "codigo" é uma MARCA que nenhuma outra
gramática usa; as formas naturais não têm marca, são PREFIXO de frases que já
significam outra coisa. Rodando cedo, `manda todos os acquarelle para locacao
para o corretor Sergio` -- frase citada no próprio código como forma viva do
envio -- virava escolha com o "Sergio" descartado.

**`5719` puro continua fora**: cai no ramo `Achar codigo`, que manda card e
TODAS as fotos para o chat do próprio Tel, e é a mensagem que ele mais escreve
(medido: "5611" 13 vezes). Pelo mesmo motivo a resposta de desambiguação
**nunca escreve "Código: NNNN"** -- link puro não dispara o gatilho de fotos, e
isso foi medido.

**O nó `Comando do Tel` faz `split('\n')` e manda só a linha que casou.** Para
a lista isso entregava um comando sem imóvel nenhum, e a resposta real era
"nao entendi qual imovel mandar". O ramo da lista manda o texto INTEIRO, com
timeout de 10 minutos -- o envio roda dentro da requisição e leva ~50-60s por
imóvel com fotos. `provar_nos_do_envio.js` roda a lógica REAL dos dois nós
contra o workflow exportado; não se chama `teste_*.js` porque precisa do JSON
exportado, que não mora no repositório.

**As cinco faixas de casamento de nome saíram para
`nay_condominios_candidatos`** e o `nay_disponibilidade_no_condominio` passou a
chamá-la. Estavam dentro do plpgsql dele, e copiá-las seria a sexta cópia de
uma regra de casamento -- o padrão 4.3 do HISTORICO. A rede é o teste dos 387
condomínios.

**A grade guarda LISTA, não só imóvel** (10/09). A mesma tabela `vagas`, o
mesmo cron de minuto em minuto, o mesmo `Nay VAGAS`. A linha é uma coisa ou
outra e o **banco** garante: ou `codigos` preenchido e `categoria` nula, ou as
três colunas de lista preenchidas e `codigos` vazio (`vagas_imovel_ou_lista`).
Um índice único impede a mesma lista duas vezes no mesmo horário — ele
repetiria o comando achando que não pegou, e os grupos receberiam duas vezes
por dia para sempre.

Duas armadilhas que já custaram o conserto: `vaga_deve_disparar` descartava
vaga sem código como "vaga livre" (a de lista não tem código **de propósito**),
e `CODIGO_RE` aceita 2 dígitos, então `as 08:00` virava os "códigos" 08 e 00 e
a frase inteira era descartada — a hora sai do texto **antes** de procurar
código, que é a mesma lição que o caminho de imóvel já trazia escrita.

A vaga de lista dispara pelo **mesmo** `_disparar_lista` do comando na mão —
inclusive a trava de repetição, o corte por `aceita_locacao` e a quebra em
pedaços.

**O formato da lista (15/09, pedido do Tel):** título entre 🔥, uma linha em
branco, e ✅ COLADO na frente de cada imóvel. O ✅ entra na montagem
(`nay_lista_de_imoveis`), nunca em `nay_linha_da_lista` -- aquela é a identidade
que o casamento reverso regenera. **Quem lê a lista de volta separa título de
imóvel pelo " / "** (`pedido_de_imoveis.e_titulo_ou_recado`, uma regra só, usada
também pelo "envia esses imóveis"): a regra antiga, "começa com emoji é título",
descartaria todos os imóveis de uma lista colada. Caixa alta não serve de
critério -- 12 das 858 linhas reais começam com palavra em caixa alta.

**Sem dizer venda ou locação, ela PERGUNTA** (09/09). `Nay lista de
apartamentos` devolvia a de locação calada, e a de venda -- que o Tel também
usa -- nunca chegava; ele não tinha como saber que faltava uma palavra. Agora
volta a pergunta com as **duas frases prontas**, já com a categoria que ele
escreveu, para a resposta ser copiar e colar. Vale nos dois caminhos, e no
disparo é parede: supor ali custaria a lista errada em 13 grupos.

A preposição é opcional -- "para locação" e "locação" valem igual, porque são
as duas formas que ele usa. "aluguel"/"alugar" contam como locação e
"compra"/"comprar" como venda. Os dois negócios na mesma frase também
perguntam: são duas listas diferentes.

**O disparo de lista tem quatro paredes**, porque postar em grupo não
desfaz. **Sem categoria não dispara** — a frase que o Tel deu de exemplo
("dispara lista no imóveis para anunciar easy") não diz qual lista, e ela
pergunta em vez de escolher. **Lista vazia não sai.** **Repetir trava**
por 30 minutos (`config.lista_repete_minutos`, muda com UPDATE), com
escape se ele escrever "de novo" — reserva atômica em
`nay_reservar_disparo_de_lista`, mesma lição do `postar_easy`. E o
`aceita_locacao` é respeitado: a lista de locação **não** vai para o
grupo "SÓ TERCEIROS COMPRA, VEN".

E **cauda que parece pessoa é recusa, nunca disparo**: "Nay envia a lista
de apartamento pro Sergio" recebe explicação, não vai para 13 grupos.

**Lista grande vai em pedaços.** Medido em 09/09: apartamento para venda
são 118 itens e **6.600 caracteres**. `_pedacos_da_lista` quebra em linha
inteira, com o título repetido, tanto no disparo quanto na resposta ao
Tel (`_avisar_tel`). O teto real da Z-API não foi medido — 3.500 é
conservador de propósito.

**O aviso de ALUGOU/VENDEU no Easy é um card resumido (15/09).** Antes era
`🛑 acquarelle alugado cod: 5611`; hoje é `montar_aviso_de_saida` -- título do
card em minúsculo + a palavra, Bairro, "apto nascente", metragem, quartos, o
valor DO NEGÓCIO QUE ACABOU ("locação: 4.600 (incluso a TX)" -- TX maiúsculo
como ele escreveu; "vendido" mostra a venda) e "Código:". Dados do banco com o
site por cima (`_imovel_para_o_aviso`): o banco garante o aviso quando o anúncio
já saiu do ar, o site faz o aviso bater com o card. Continua saindo UMA vez só,
amarrado ao UPDATE de `disponivel`.

`tira` e `VENDEU` **não fazem mais a mesma escrita** (01/09). `VENDEU` e
`ALUGOU` marcam `imoveis.disponivel = false`, cancelam os lembretes e as
entregas pendentes daquele imóvel; `tira`/`remove` continua sendo só
reorganização de horário e o imóvel segue à venda. Antes os dois faziam
a mesma coisa e só a frase mudava -- então a busca continuava oferecendo
o que o Tel tinha dado por vendido, porque ela olha
`coalesce(disponivel, true)`.

**OS GRUPOS DE APELIDO, e o que cada nome significa hoje (27/09).** Cinco
apelidos, e `GRUPOS_DE_APELIDO` no `publicador.py` é a fonte deles -- cada um
com sua TABELA DE RESERVA própria, porque a reserva pertence ao grupo e não ao
nome:

| o que o Tel escreve | grupo | fotos | tabela de reserva |
|---|---|---|---|
| `no anunciar easy` | IMÓVEIS PARA ANUNCIAR EASY | todas | `easy_publicacoes` |
| `no alto padrão anunciar easy` | IMÓVEIS ALTO PADRÃO PARA ANUNCIAR EASY | todas | `alto_padrao_publicacoes` |
| `no grupo alto padrão`, `no grupo padrão` | 🟢 Alto Padrão - OFERTA e BUSCA 🔍 | metadinha | `alto_padrao_busca_publicacoes` |
| `no grupo comercial` | 🟢 Comercial - OFERTA e BUSCA 🔍 | metadinha | `comercial_publicacoes` |
| `no grupo lotado` | **QUATRO** grupos de maior movimento | metadinha | `lotado_publicacoes` |

**"ALTO PADRÃO" MUDOU DE DONO em 27/09**, por decisão do Tel: até então ia
para o de ANUNCIAR EASY, e o de OFERTA e BUSCA não tinha comando. Hoje o de
Anunciar Easy exige dizer "anunciar" ou "easy" na frase. Ao ler código ou
conversa anterior a essa data, lembrar da troca.

**"lotado" é o primeiro apelido COLETIVO** -- quatro grupos. O índice
`grupos_apelido_unico` continua exigindo um grupo por apelido para os outros
quatro, e traz a lista de exceções escrita (`grupo_lotado.sql`).

**Todo grupo de apelido também agenda**: `posta no grupo X o NNNN segunda,
quarta e sexta as 08h` cria vaga com `vagas.destino`, e `_postar_da_vaga`
dispara pelo mesmo `_postar_easy` do comando na mão, com `de_novo=True` (sem
ele o segundo dia diria "já foi postado"). O CHECK `vagas_imovel_ou_lista`
precisou afrouxar para a vaga de imóvel poder ter destino
(`vaga_de_grupo.sql`), e `vagas_imovel_unica` impede a mesma vaga duas vezes
-- o 5749 estava duplicado e postava dobrado.

**A lista de disparo relê os valores no site antes de sair** (27/09). Ela lê a
TABELA, e quem põe o site ali é a varredura; com a varredura parada a lista
envelhece junto. `nay_codigos_da_lista` diz quais imóveis entram (extraída de
dentro do `nay_lista_de_imoveis`, para a regra não ter duas cópias) e o
publicador relê o valor de cada um. O `Nay lista de ...` da TELA continua
lendo só a tabela, para não virar espera de dois minutos.


## Onde mora o aprendizado da Nay

Três lugares, e confundir os três já custou caro:

| onde | o que vai ali | quem lê |
|---|---|---|
| `30-Padroes-de-Atendimento.md` | observação, padrão, decisão, pergunta em aberto | pessoas |
| tabela `regras` | a regra já decidida, em uma frase | a Nay, via `sincronizar_regras.py` |
| query da ferramenta | a regra que governa um dado, colada nele | a Nay, sempre |

O caminho é sempre: observa no doc 30 → decide → vira linha em `regras` →
`sincronizar_regras.py --escrever` → import do fluxo. Escrever direto na
tabela sem revisar contra conversa real foi como o projeto ficou com
cinco regras nunca exercitadas, três delas contradizendo a prática
(28/08, doc 30 Parte 4). **Regra escrita e nunca usada não é regra, é
intenção.**

## Antes de mexer em regra de negócio ou bug estranho

Leia HISTORICO-APRENDIZADO.md, especialmente a Parte 4 (bugs que já se
repetiram). Se o que você está vendo parece um desses padrões, é
provável que seja o mesmo problema de novo, não um novo.

## Regra de auto-registro

Sempre que corrigir um bug real (não erro de digitação, um bug de
lógica ou de dado), antes de considerar a tarefa terminada, acrescente
uma entrada curta em HISTORICO-APRENDIZADO.md: o que parecia ser, o que
era de verdade, e como foi descoberto. Três linhas bastam.

## Commits

Sempre explique o porquê no commit, não só o quê. Se corrigiu um bug,
diga qual era a causa raiz.