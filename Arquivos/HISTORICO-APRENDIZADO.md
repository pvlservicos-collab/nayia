# 27 — Histórico completo do aprendizado: Projeto Nay

*Compilado em 22/08/2026, a partir de três fontes: a conversa fundacional
de 09/08 (planejamento e arquitetura), os documentos 00 a 19 do projeto
(construção do cérebro, 10 a 13/08), e a sessão corrida de 17 a 22/08
(release da escalação, transcrição de áudio, sincronização de catálogo,
e o bug do parceiro). Este documento existe para uma coisa só: **evitar
que o mesmo erro seja redescoberto**. Leia antes de mexer em qualquer
peça do sistema.*

---

## Como usar este documento

Ele não substitui os outros — é o índice e a memória de longo prazo.
Onde algo tem detalhe técnico completo em outro doc, este aponta para lá
em vez de repetir. O valor daqui está em três coisas que só aparecem
quando se olha o projeto inteiro de uma vez: **os bugs que se repetiram**,
**as decisões que foram revertidas**, e **os princípios que nasceram de
dor real**, não de teoria.

---

## Parte 1 — As três eras do projeto

### Era 0 — Hermes (antes da Nay)

Existiu um sistema anterior, `hermes-gateway-corretores`, rodando numa
VPS separada. Ele tinha um **bug que perseguiu o Tel por semanas** — a
natureza exata dele não está detalhada nos documentos, mas o fato de ele
ter motivado uma reconstrução inteira, do zero, numa arquitetura nova,
diz o tamanho do problema. Parte do desenho de hoje — decidir tudo no
banco, nunca deixar o modelo escrever número, isolar dado por tabela —
é resposta direta a esse histórico, não escolha arbitrária.

O corte do Hermes foi desenhado como migração controlada, não como
troca abrupta: parar o serviço antigo, ligar o novo, observar 48 horas,
só então desativar o pareamento antigo — com a VPS antiga preservada até
o banco estar migrado e com backup confirmado.

### Era 1 — Fundação e construção do cérebro (09 a 13/08)

Sessão de planejamento em 09/08: auditoria dos dados do admin (duas
planilhas, 1.173 imóveis), decisão de stack, 43 regras operacionais
aprovadas. Depois, entre 10 e 13/08, o cérebro foi construído e testado
isoladamente (workflow `Nay Cerebro`), a busca por condomínio ganhou
tolerância a erro de grafia, o modelo passou a receber hora de Manaus,
e uma sequência de bugs de execução foi caçada e corrigida — a maioria
documentada nos docs 06 a 10.

### Era 2 — Esta sessão: release da escalação e correções (17 a 22/08)

Cobre a auditoria dos docs 18/19, a construção do sub-workflow de
escalação, os comandos do Tel pelo WhatsApp, a transcrição de áudio, a
descoberta de que a base estava congelada há 11 dias, a varredura do
catálogo público via Claude Code, e o bug do imóvel de parceria sendo
enviado por completo — que expôs a maior lição de todas: a mesma regra
de negócio vivia em dois lugares diferentes do n8n sem que ninguém
soubesse do segundo. Detalhe completo nos docs 20 a 26.

---

## Parte 2 — Decisões de arquitetura já fechadas (não relitigar)

| Decisão | Por quê | Quando |
|---|---|---|
| Modelo nunca escreve número | Preço/metragem/quartos vêm de consulta ao banco; o texto do imóvel é montado por template, não gerado pelo LLM. Um valor inventado na frente de corretor destrói credibilidade de forma irrecuperável | 09/08, reafirmado o projeto inteiro |
| Dado de proprietário em tabela separada, sem acesso da ferramenta de corretor | "Regra no prompt é pedido; separação no banco é parede" | 09/08 |
| API oficial do WhatsApp descartada | Decisão explícita do Tel, não deve ser revisitada | 09/08 |
| n8n self-hosted + PostgreSQL + Z-API | Stack fechada, ver doc 00 para arquitetura completa | 09/08 |
| Fotos por URL, nunca armazenadas na VPS | Z-API aceita imagem por link; corretor recebe como foto real | 09/08 |
| Fotos enviadas sem limite, todas | Risco de banimento assumido conscientemente; por isso o chip reserva virou pré-requisito, não melhoria | ~12/08 |
| Três agentes por perfil (corretor / proprietário / lead), ferramentas disjuntas | Isolamento de dados é estrutural, não tonal | doc 00, reforçada em 21/08 |
| Publicação em grupos: whitelist controlada pelo Tel via comando | Nunca a Nay decide sozinha o que publicar | 21/08 |
| Migração para código (Claude Code/VS Code) é gradual, por peça, nunca big-bang | O fluxo principal de mensagens é a única peça de risco real; publicador e escalação foram feitos primeiro por não existirem ainda no n8n | doc 22, 21/08 |

## Parte 3 — Decisões que foram revertidas

Isso importa mais do que parece: quem só ler o resumo mais recente não
sabe que a resposta já foi outra antes.

**mem0 para memória de longo prazo.** Na sessão de 09/08, mem0 foi
**recomendado** como solução viável para memória de corretor e histórico
de imóveis mostrados, citando benchmarks de latência e custo de token.
Essa recomendação foi **revertida**: a decisão final, que vale até hoje,
é que memória de conversa vive inteiramente em `nay_memoria` no
PostgreSQL, e mem0 é explicitamente rejeitado. Se aparecer sugestão de
reintroduzir mem0 ou ferramenta parecida, é uma ideia já testada e
descartada — não é novidade.

**Fine-tuning.** Também considerado e descartado logo na sessão de
09/08, pelo mesmo motivo que vale até hoje: caro, lento, e o modelo
fica desatualizado a cada mudança de catálogo. RAG e regra em banco
resolvem melhor.

**"A Nay aprende sozinha".** Expectativa inicial do Tel, desmontada
explicitamente em 09/08: o agente não muda o próprio comportamento sem
supervisão. O "aprendizado" real é o Tel corrigindo, a correção virando
regra ou memória gravada, e o agente passando a usar essa regra. Deixar
o modelo reescrever as próprias regras sem revisão é receita para deriva.

## Parte 4 — Bugs que se repetiram (a parte mais importante deste documento)

Cada um destes apareceu **mais de uma vez**, em datas diferentes, sob
formas ligeiramente diferentes. Isso significa que a causa raiz é um
padrão do ambiente, não um evento isolado — e vai voltar a acontecer se
ninguém nomear o padrão.

### 4.1 — A palavra "null" ou "undefined" tratada como texto real

Toda vez que o n8n serializa um valor ausente, ele vira a **palavra**
`null` ou `undefined` — quatro ou nove letras de texto, não ausência de
verdade. Como string não-vazia é "verdadeira" em JavaScript, qualquer
checagem ingênua (`if (texto)`) passa a achar que existe conteúdo.

Apareceu em:
- **12/08** — mensagem sem texto (só áudio/imagem) gravava a palavra
  `null` na coluna `texto`; a Nay respondia como se aquilo fosse a fala
  do corretor. Corrigido com `NULLIF($4, 'null')` no `Gravar na fila`.
- **13/08** — doc 19 previu o mesmo problema no parâmetro `codigo` da
  ferramenta de escalação, chamando explicitamente de "o mesmo bug do
  `'null'` de quatro letras que já custou meio dia neste projeto".
- **21/08** — reapareceu de novo, agora como a **string literal**
  `"null"` sendo passada como parâmetro de função SQL pelo n8n (não o
  `NULL` de banco de verdade), quebrando `nay_comando` com
  `invalid input syntax for type integer: "null"`. Corrigido fazendo a
  função aceitar o id como texto e converter internamente, descartando
  qualquer coisa que não seja dígito.

**A lição:** toda vez que um valor pode vir ausente através do n8n,
trate a possibilidade de ele chegar como a **palavra** `null` ou
`undefined`, nunca assuma que ausência vira `NULL` de banco de verdade.

### 4.2 — Nó referenciado antes de ter rodado

`ExpressionError: nó não foi executado` — uma expressão em algum lugar
do fluxo referencia a saída de um nó que, naquela execução específica,
não chegou a rodar (porque um ramo anterior cortou o caminho).

Apareceu em:
- **12/08** — `Registrar envio` lia dados de `$('Buscar imovel')`, nó que
  só existe no caminho rápido (código puro). Toda mensagem em linguagem
  natural, que vai pelo caminho do agente, derrubava a execução.
  Corrigido criando um nó intermediário (`Preparar registro`) que tenta
  os dois caminhos com `try/catch` e sempre devolve algo, com `codigo: 0`
  quando não há imóvel.
- **21/08** — o mesmo padrão apareceu de novo quando o `Detectar audio`
  foi inserido no fluxo: ele rodava antes do `Juntar mensagens` e uma
  expressão dentro dele tentava ler `$('Juntar mensagens')`, que ainda
  não tinha executado naquele ponto. (Neste caso específico o disparo
  real foi uma queda de conexão do WhatsApp que gerou um payload
  incomum, mas a fragilidade estrutural — nó lendo de outro nó que pode
  não ter rodado — é a mesma.)

**A lição, que já virou princípio nomeado no projeto:** "fazer o nó não
poder falhar", em vez de proteger quem vem depois. Um nó que pode
receber entrada incompleta deve devolver um valor padrão seguro
(`codigo: 0`, lista vazia, etc.), nunca presumir que o nó anterior no
fluxo sempre rodou.

### 4.3 — A mesma regra de negócio decidida em mais de um lugar

**O caso mais caro de toda a sessão de 21-22/08.** A regra "imóvel de
parceria não recebe foto nem texto completo" foi corrigida no nó
`Montar mensagem` (JavaScript, caminho de código puro). Testada,
publicada, o bug continuou idêntico. A causa: existe uma **segunda
cópia inteira da mesma lógica**, em SQL puro, dentro da ferramenta
`imovel_por_codigo` que o agente de IA usa — um caminho completamente
diferente que ninguém tinha mapeado como duplicado.

Isso conecta com um padrão mais antigo: em 12/08, o problema do agente
"não chamar ferramenta e inventar resposta" foi resolvido fazendo a
**própria query SQL** decidir o que dizer (campo `texto_pronto`,
`instrucao_para_voce`) em vez de confiar no modelo para interpretar um
aviso solto. O bug do parceiro em 21/08 era exatamente o oposto disso
em miniatura: um aviso solto (`avisos.push('E DE PARCEIRO')`) que o
modelo podia ignorar, porque nada **obrigava** a decisão.

**A lição:** antes de declarar uma regra corrigida, perguntar — essa
decisão pode ser tomada em mais de um lugar do fluxo? No desenho atual,
qualquer coisa que sai para o corretor pode vir do caminho de código
puro (`Buscar imovel` → `Montar mensagem`) **ou** de uma ferramenta do
agente com query própria. Achar a execução real no histórico do n8n e
ver qual nó gerou a saída errada é mais confiável que supor onde a
lógica mora. E sempre que possível, a decisão deve travar o fluxo
(`return` cedo, `CASE WHEN` que substitui o resultado inteiro) em vez
de só sinalizar um aviso que outra camada pode escolher ignorar.

## Parte 5 — Descobertas de segurança e qualidade de dado

**`raise_for_status()` vaza credencial quando ela mora na URL.** A
Z-API embute instância e token no caminho da URL, não só no header. No
primeiro teste real de `enviar_zapi.py` (22/08), um 403 subiu via
`resp.raise_for_status()`, que inclui a URL inteira na mensagem de
erro -- token exposto em texto puro na conversa. Corrigido lançando
`RuntimeError` com só status + rota + corpo da resposta, nunca a URL.
Token tratado como comprometido e recomendada a rotação, independente
do conserto de código. Lição geral: qualquer API que carrega segredo na
URL (não só em header) exige atenção extra em qualquer lugar que loga
ou relança erro de request sem revisar o que está sendo incluído.

**Vazamento de PII no admin.** Toda página de edição de imóvel no
`imobeasy.com/admin` entrega, no próprio código-fonte da página, os
**5.612 proprietários com nome, telefone, e-mail, RG e CPF** — visível
por qualquer usuário logado com um Ctrl+U, sem deixar rastro. Isso não
foi corrigido; é uma pendência de segurança para levar ao fornecedor
(CodeFarm), com exposição tanto de negócio (carteira de proprietários
inteira levada por qualquer corretor com acesso) quanto jurídica (CPF e
RG são dado pessoal sob a LGPD).

**Zero não é a mesma coisa que "não tem".** Descoberto duas vezes
independentes — na importação do catálogo (doc 08) e na especificação
da API pedida ao fornecedor (doc 17): campos como vagas, área, banheiros
e quartos frequentemente vêm com `0` quando na verdade significam "não
preenchido". Isso fez a Nay dizer a um corretor que um apartamento não
tinha vaga de garagem, quando o dado real era ausência de preenchimento.
A regra do importador (`zero_e_nulo`) grava `NULL` nesses casos.

**Marcação de parceiro migrou de lugar.** Na importação original do
catálogo (doc 08), "é de parceiro" não era um campo — vivia escondido
no **nome do proprietário**, com padrões como "(Parceiro)" ou "Corretor
parceiro" (1.394 dos 5.612 proprietários). O importador extraiu isso
para a coluna `e_parceiro` da tabela `imoveis`, que é a fonte usada
hoje. Isso significa que, se algum dia a base for reimportada do zero, a
lógica de extração desse padrão de texto precisa ser preservada — não é
óbvio que "parceiro" é um campo de primeira classe no sistema de origem.

**A base ficou 11 dias sem sincronizar sem que ninguém percebesse.**
A cópia local (`naydb`) foi feita uma única vez, em 10/08, e nunca
mais — sem alarme, sem aviso, sem nada indicando isso até uma
comparação manual em 21/08 revelar 334 imóveis desatualizados. Não
existe hoje mecanismo de verificação de idade dos dados; a varredura via
site público (doc 25) é solução manual, não automática ainda.

**"Vagas" pode ser só a parte descoberta, não o total.** Na página
individual do anúncio (`/anuncios/<codigo>`), quando os rótulos "Vagas"
e "Vagas Cobertas" aparecem juntos, "Vagas" é a parcela sem cobertura —
o total é a soma dos dois, não um substituindo o outro. Descoberto no
código 5644 (`buscar_imovel.py` devolvia vagas=2, quando o valor
correto, confirmado por três caminhos independentes, é 4) e provado com
o código 5615, que tem o total confirmado em texto livre nas
observações ("4 vagas amplas sendo 2 cobertas", com Vagas=2 e Vagas
Cobertas=2 na página).

**Checar-depois-gravar tem janela de corrida real, mesmo parecendo
instantâneo.** `postar_easy` fazia SELECT (já foi postado?) → busca +
envia fotos (pode levar minutos) → INSERT (grava). O Tel mandou o
mesmo comando duas vezes com ~90s de intervalo em produção (25/08); as
duas passaram pelo SELECT antes de qualquer uma gravar, e as duas
postaram. Só existir 1 linha na tabela depois (PRIMARY KEY) não prova
nada — é consistente com as duas tentativas terem rodado. Corrigido
invertendo a ordem: `INSERT ... ON CONFLICT DO NOTHING ... RETURNING`
primeiro, de forma atômica, commitado antes de buscar/enviar — o
Postgres serializa INSERTs concorrentes na mesma chave primária, então
não sobra janela entre checar e gravar quando é a mesma operação.

**A cadência de "não distinguir vendido de apagado" segue sem solução
definitiva.** O admin não tem status "Suspenso" — só Disponível,
Alugado, Vendido, Rascunho, Arquivado, Removido, Revisão. Isso já
apareceu como bloqueio para "suspender propriedades de parceiro em
lotes controlados", que continua pendente.

**Relatar "zero" quando na verdade já saiu parcial arrisca reenvio
duplicado.** `_postar_codigo` (publicador.py) zerava `grupos_atingidos`
sempre que o envio pra vários grupos falhava no meio (grupo 3 de 9,
por exemplo) — mesmo os grupos anteriores já tendo recebido de
verdade. Reportar 0 nesse caso é dado errado: um reenvio manual
baseado nesse relatório mandaria a mesma mensagem de novo pra quem já
recebeu. Achado na revisão de `disparar_grade.py` (25/08), antes de
aprovar o código. Corrigido contando os envios reais feitos antes da
exceção e devolvendo sucesso parcial (contagem certa + o erro do que
faltou).

**Checagem de configuração obrigatória depois de um "nada a fazer,
retorna" só aparece na primeira execução real.** `disparar_grade.py`
checava `TEL_WHATSAPP` só depois de decidir que alguma vaga disparava
— rodar o script sem essa variável configurada, num minuto sem vaga
devida, não acusava nada; o erro só apareceria na primeira vez que uma
vaga de verdade disparasse, silenciosamente até lá. Achado na mesma
revisão (25/08). Corrigido movendo a checagem pro topo da função,
antes de qualquer outra coisa — mesmo padrão de falha cedo que
`db.conectar()` e `enviar_zapi._credenciais()` já usam.

**Testar um script de deploy Linux numa máquina Mac pode aprovar algo
que quebra no servidor de verdade.** A primeira versão de
`disparar_grade.sh` (wrapper de cron, doc 29 Etapa B) usava `date -Is`
pra gerar o timestamp do log -- flag só do GNU `date`. Rodando o
wrapper localmente (macOS, `date` do BSD) pra testar antes de propor,
ele quebrou: `date: invalid argument 's' for -I`. O servidor de
produção é Linux/GNU, então `-Is` funcionaria lá -- mas isso não dá
pra confirmar rodando só na máquina de desenvolvimento. Corrigido
trocando para `date "+%Y-%m-%dT%H:%M:%S%z"` -- sintaxe `+FORMATO`,
idêntica em BSD e GNU `date`, testável (e testada) nos dois ambientes.
**A lição:** ao escrever shell script que vai rodar num servidor
Linux, testar numa máquina Mac só serve de confiança real se o
comando usado for POSIX/portável dos dois lados -- senão o teste local
pode aprovar algo que nunca rodou no ambiente de verdade.

**O vocativo "Nay" matava todo comando, e tirá-lo ia armar uma
armadilha pior.** Em 27/08 o Tel mandou "Nay posta o 2943" e recebeu
"não encontrei o imóvel pelo código 2943". Duas coisas erradas de uma
vez. A resposta não veio do publicador -- essa frase não existe no
código; veio do cérebro da Nay no n8n, que consulta a tabela `imoveis`
congelada em 10/08 e não tem o 2943. O comando nunca chegou ao
publicador, porque o n8n ainda não roteia `posta` (Elo A do doc 29). E
mesmo se tivesse chegado, teria falhado: `interpretar_comando` exigia
que o texto COMEÇASSE com o verbo, e "Nay" na frente derrubava cinco
dos seis caminhos (posta, VENDEU, tira, VAGAS e criar vaga). Só o Easy
escapava, porque `EASY_RE` usa `search` em vez de âncora -- uma
inconsistência que ninguém tinha notado porque nada testava vocativo.

O conserto óbvio era descartar o "Nay" e pronto. Uma auditoria
adversarial antes de aplicar mostrou que isso, sozinho, seria pior que
o bug: `tl.startswith(VERBOS_POSTAR)` casa PREFIXO, sem fronteira de
palavra, então "publicamos", "postaram", "postado", "postagem",
"soltaram" e até "disparate" já contavam como verbo de postar. Isso era
inofensivo justamente porque o vocativo travava a frase inteira em
`nao_reconhecido`. Descartado o "Nay", a pergunta "Nay, publicamos o
5750 ontem?" viraria `postar_agora` e sairia de verdade em 9 grupos de
corretor -- e mensagem de WhatsApp não tem desfazer. **O vocativo
estava funcionando como trava acidental contra frase conversacional.**
Corrigido no mesmo commit: `POSTAR_RE = ^(verbos)\b` no lugar do
`startswith`, e os 14 casos negativos entraram na suíte antes da
mudança ser considerada pronta.

**A lição:** quando uma condição que sempre falhou passa a poder
passar, o que estava depois dela nunca foi exercitado de verdade.
Antes de afrouxar uma trava, olhar o que ela estava segurando sem
ninguém saber -- inclusive proteção acidental que ninguém projetou.
Corolário: `startswith` com tupla de verbos é falso amigo em parser de
linguagem natural; a fronteira de palavra não é preciosismo, é o que
separa ordem de pergunta.

**Três ramos paralelos, e `return []` só mata o próprio.** Em 27/08,
mapeando o fluxo `Nay- recebe mensagem` pela primeira vez (o doc 29 já
registrava que isso nunca tinha sido feito), apareceu que `Juntar
mensagens` se divide em TRÊS ramos que rodam ao mesmo tempo: `Achar
codigo` (código puro), `Rotear para o agente` (cérebro) e `Comando do
Tel` (publicador). O `return []` do `Comando do Tel` encerra só o ramo
dele. Sintoma visível: `Nay vagas` devolveu duas respostas -- a grade,
do publicador, e "vagas de qual imóvel ou condomínio?", do cérebro.

Três bugs distintos saíram desse mesmo mapeamento:

1. **Um `_` solto no fim da linha 14 do `Comando do Tel`** derrubava o
   nó inteiro antes da linha 16, que é onde mora a chamada ao
   publicador. `ReferenceError: _ is not defined`. Passava no
   `node --check` -- é JavaScript válido, só quebra em execução --, por
   isso ninguém viu ao salvar. Uma ocorrência em duas semanas de log:
   só a mensagem do Tel alcançava aquela linha.

2. **A gramática de comando existia em três cópias**: o
   `interpretar_comando.py`, a regex do `Comando do Tel` e a do
   `Rotear para o agente`. As três divergiam (`RETIRA`/`VAGA` existem no
   n8n e não no Python; o vocativo "Nay" foi corrigido no Python de
   manhã e as outras duas não sabiam). É a Parte 4.3 outra vez, agora
   com três cópias em vez de duas.

3. **`Rotear para o agente` filtrava por texto e não por identidade.**
   Qualquer mensagem começando com `Vaga`, `Vagas`, `Tira`, `Posta`,
   `Solta`... era descartada ali, viesse de quem viesse. Para um
   CORRETOR isso significava silêncio absoluto: o ramo do cérebro
   descartava pelo texto, o `Comando do Tel` descartava pelo telefone, e
   o `Achar codigo` só aceita número puro. Nenhuma resposta, nenhum
   erro, nenhum alarme. E "Vaga de garagem?" é vocabulário normal do
   negócio. Corrigido com `const ehTel = String(j.telefone) === TEL` nos
   dois testes de descarte.

**A lição:** num fluxo com ramos paralelos, "meu nó retornou vazio" não
é o mesmo que "o fluxo parou" -- é preciso saber quem mais está rodando
ao lado. E um filtro que decide por CONTEÚDO sem checar QUEM FALOU
silencia a pessoa errada; o dano aparece justamente em quem não tem como
reclamar, porque não recebe nem erro.

**Corolário de método:** o alarme de erro (`Nay - alarme de erro`)
respondeu `Workflow: ? / No: ? / Erro: ?` -- os três campos vazios. Um
alarme que não sabe dizer o que falhou custa exatamente o tempo que ele
deveria economizar. Quando o payload não bate com o esperado, o alarme
tem que despejar o payload cru em vez de imprimir `'?'`.

**O parser tratava a frase de CADÊNCIA como se fosse código de imóvel.**
Em 27/08, ao desenhar a grade de horários alternados, uma auditoria pediu
para medir o que o parser fazia HOJE com as frases que o Tel usaria. O
resultado, contra produção:

    "posta o 5750 a cada 15 dias"   -> postar_agora, codigos ['5750', '15']
    "posta o 5750 de 15 em 15 dias" -> postar_agora, codigos ['5750','15','15']

Ou seja: postava o 5750 **e tentava o imóvel 15**, na hora, em 14 grupos
reais, sem desfazer. O 15 da frase "a cada 15 dias" é colhido por
`CODIGO_RE = \b\d{1,6}\b`, que roda sobre o texto inteiro e não sabe
distinguir código de número de cadência. Duas outras frases mentiam em
silêncio: "segunda sim segunda não às 13h30" e "toda segunda quinzenal às
13h30" viravam vaga SEMANAL — o Tel pediria para pular uma semana e o
imóvel sairia em todas.

Nada disso tinha teste, porque a alternância ainda não existia: ninguém
escreve teste para uma frase que o produto não suporta. Mas o parser não
recusava essas frases — ele as interpretava errado.

Corrigido com uma guarda que recusa explicitamente o vocabulário de
alternância enquanto a gramática não existir (15 casos positivos e 3 de
falso positivo fixados em teste), e o regex teve que ser preciso:
`\balternad` não casa "alternando" (é *alternan-do*), e `\baltern` casaria
"alternativa". A forma certa é `\balterna[dnr]` mais `\baltern[aâ]ncia`.

**A lição:** antes de implementar uma funcionalidade nova, medir o que o
sistema faz HOJE com a entrada que ela vai receber. O perigo não é o
recurso que falta — é o recurso que falta e mesmo assim aceita a frase,
interpretando-a como outra coisa. Enquanto a gramática não existe, recusar
é uma decisão de produto, não um buraco: adivinhar "toda semana" quando o
usuário escreveu "semana sim, semana não" é adivinhação com custo
irreversível.

**O alarme lia o nó errado, e dependia do Telegram para existir.** O fluxo
`Nay - alarme de erro` mandou ao Tel, em 27/08, exatamente isto:

    🚨 A Nay falhou
    Workflow: ?   No: ?   Erro: ?

Os três campos vazios. A causa não estava nas expressões — elas liam
`$json.workflow` e `$json.execution`, que são os campos certos do Error
Trigger. Estava nas **ligações**:

    'Quando a Nay falhar' -> 'Avisar no Telegram' -> 'Avisar o Tel'

Em série. E no n8n `$json` é a saída do nó **anterior**, não a do gatilho.
Como o aviso de WhatsApp vinha depois do Telegram, ele lia a resposta da
API do Telegram — onde não existe `workflow` nem `execution` — e caía nos
`'?'`. O aviso do Telegram, esse, saía correto: ele era o primeiro da fila.

O mesmo desenho tinha um segundo defeito, mais grave e invisível: **o
alarme do canal que o Tel usa dependia de outro serviço ter funcionado
antes.** Telegram fora do ar, credencial vencida ou chat bloqueado e o
WhatsApp não recebia nada — falha silenciosa no único mecanismo cuja
função é não falhar em silêncio.

Corrigido com um nó `Montar aviso` que lê do gatilho pelo nome
(`$('Quando a Nay falhar')`, seguro porque o gatilho sempre roda) e monta
o texto UMA vez; os dois envios passam a usar `$json.mensagem`. E o
WhatsApp passou a vir antes do Telegram na cadeia, para que a falha do
canal secundário não engula o principal. O texto ganhou o id da execução
e, quando não reconhece o formato do payload, despeja o payload cru — a
próxima falha se explica sozinha.

**A lição:** `$json` é o nó anterior, não o gatilho — num fluxo de um nó
só a diferença não aparece, e ela morde quando alguém acrescenta o
segundo. E o alarme é o último lugar onde se pode aceitar dependência em
série: se ele precisa de outro serviço para falar, ele tem um modo de
falha que ninguém vai ver.

**A idade do catálogo voltou a passar despercebida — e o diagnóstico
errado durou o dia inteiro.** A Parte 5 já registra "a base ficou 11 dias
sem sincronizar sem que ninguém percebesse" e que "não existe hoje
mecanismo de verificação de idade dos dados". Em 28/08 isso cobrou de
novo, de duas formas.

A primeira é de método. O doc 25 diz que a base está congelada em
10/08, e essa frase foi repetida o dia todo — por mim, inclusive dentro
do CLAUDE.md — sem ninguém consultar o banco. O banco dizia
`sincronizado_em = 21/08`: a varredura tinha rodado de novo e o doc
estava velho. Seis dias de atraso, não dezessete. **Documento sobre
estado de dado envelhece; o dado responde na hora.** `SELECT
max(sincronizado_em) FROM imoveis` custa um segundo.

A segunda é o que a varredura de verdade encontrou, e nenhuma das duas
formas era a que a narrativa previa:

- **5 códigos existiam no site e não no banco** — 887, 2014, 2943, 5711,
  5712. O 2943 é o que abriu o dia com "não encontrei o imóvel pelo
  código 2943". Não era base parada no tempo: era ausência específica.
- **5 imóveis com valor divergente**, e um deles grave: o código 5122
  (Le Village Blanc) estava a R$ 3.700.000 no banco e R$ 2.500.000 no
  site. A Nay cotaria 48% acima do anunciado a qualquer corretor que
  pedisse aquele imóvel. Nenhum alarme existia para isso, porque desvio
  de valor não quebra nada — só perde negócio, em silêncio.

**A lição:** ausência e divergência são modos de falha diferentes de
"base parada", e nenhum dos dois dispara erro. O que protege contra os
três é a mesma coisa que ainda não existe: alguém (ou algo) olhando a
idade e o delta do catálogo com regularidade. Enquanto for manual, vai
voltar a acontecer — é a terceira vez que este documento registra a
mesma família de problema.

**Caução calculada com valor desatualizado virou informação errada para
a corretora.** Em 28/08, na conversa com a Samira sobre o 1327, o Tel
montou o bloco de condições da locação e escreveu "para entrar no
imóvel é o valor de 4.600 sendo 2 caução". O aluguel é R$ 2.500, e
2 × 2.500 = 5.000, não 4.600. O 4.600 veio de 2 × 2.300, o valor
**anterior** que o card do grupo ainda mostrava. A Samira estranhou e
perguntou se era R$ 5.000. A causa raiz é o dado velho no card, mas o
efeito multiplicou: a conta manual saiu do valor errado e foi parar na
ponta. O Tel confirmou em 29/08 que o número de cauções **varia por
imóvel**, então a Nay não pode calcular automaticamente. Virou regra: ela
responde que vai verificar e escala ao Tel.

**As fotos não eram decisão da Nay, e a instrução que eu escrevi para ela
era inerte.** Em 29/08 o Tel reclamou de dois comportamentos no mesmo
teste: ela despejou o card inteiro quando ele só perguntou o endereço, e
mandou todas as fotos junto. Escrevi na descrição da ferramenta "nunca
envie fotos a menos que o corretor peça" — e essa frase não fazia nada,
porque **a Nay não controla o envio de foto**. Quem controla é o nó
`Achar codigo na resposta`, que roda uma regex na resposta **dela**:
achou `Código: NNNN`, busca as fotos e manda. Card = fotos, acoplado no
fluxo, longe do modelo.

Isso explicava os dois casos de uma vez: "qual o valor do 4098?" não
mandou foto porque ela respondeu em prosa, sem a linha `Código:`; "me
fala do 1327" mandou porque ela repetiu o card. O gatilho nunca foi
intenção — foi formato de texto.

**A lição, que é a Parte 4.2 outra vez:** antes de escrever regra no
prompt, achar quem executa de verdade. Instrução para o modelo sobre
algo que o modelo não controla não é regra fraca, é regra **morta** — e
pior que não escrever nada, porque parece resolvido. Corrigido
condicionando o gatilho ao pedido do corretor (`\b(foto|fotos|imagem|
imagens|fachada|frente|v[ií]deo)\b`), com o código lido da resposta dela
ou da pergunta, e 15 casos testados no Node do próprio container antes
do import.

**A Nay prometeu verificar uma visita e não tinha como — a mesma família
do bug das fotos, no primeiro dia de atendimento real.** Em 29/08, hora e
meia depois de sair a trava de teste, o corretor Leonan pediu para ver a
casa do Nova Cidade e perguntou "que horas daria pra ver?". A Nay
respondeu "vou verificar para você", depois "ainda estou verificando" —
e **nenhuma pendência foi criada**. O Tel nunca soube. O corretor esperou
40 minutos e perguntou "confirmou?".

A causa estava escrita no próprio prompt, na seção VISITA NO MESMO DIA:
*"você pode perguntar direto ao proprietário — isso é agenda, não precisa
de autorização"*. **Ela não tem ferramenta que mande mensagem para
ninguém**; as sete são de consulta. O prompt mandava fazer o impossível,
então ela fez a única coisa disponível: prometeu.

O doc 30 (Parte 7) já tinha registrado a ausência dessa ferramenta —
citando **esse mesmo corretor**, numa visita anterior em que ela ao menos
escalou. Ou seja: o fato estava documentado e a instrução contraditória
continuou no prompt.

No mesmo episódio ela chamou a corretora de "amiga" duas vezes. O nome
estava em `mensagens.nome` ("Leonan Ribeiro (Léo)"), vindo do
`senderName` do WhatsApp — mas o input do agente passava **só o texto**:
`mensagem do corretor: {{ ...json.texto }}`. Ela não sabia com quem
falava, e a seção de voz pedia "tom informal e caloroso" sem dizer para
usar o nome. "amiga" foi o preenchimento natural do vazio.

**A lição, agora pela terceira vez:** antes de escrever instrução no
prompt, achar quem executa. Fotos, visita e agora nome — três casos em
dois dias em que a regra falava de algo que o modelo não controlava ou
não recebia. Instrução para capacidade inexistente não é regra fraca, é
**promessa que o sistema quebra sozinho**. Corrigido nos quatro pontos:
o nome entra no input, a voz proíbe "amiga", a seção de visita manda
escalar, e `escalar_ao_tel` passou a listar visita entre os gatilhos —
mais duas linhas na tabela `regras`, para sobreviver a reescrita futura
do prompt.

**Toda mensagem com vírgula chegava truncada — desde o início do
projeto, em silêncio.** Em 29/08 o Tel reclamou que o corretor João Luiz
pediu apartamento "até 1.500" para locação e a Nay tratou como 1 milhão.
Parecia erro de interpretação do modelo. Não era: a mensagem chegou ao
banco como **"Essa cliente está procurando apartamento ate 1"**. Ele
escreveu com vírgula decimal e o resto sumiu antes de a Nay ver.

A prova é de uma linha: `SELECT count(*) FROM mensagens WHERE texto LIKE
'%,%'` devolveu **0 em 1.885 mensagens**, contra 215 com ponto. Zero
vírgula em mil e oitocentas mensagens de WhatsApp em português é
impossível.

A causa está no nó Postgres do n8n. O campo `queryReplacement` era
`{{ $json.telefone }},{{ $json.nome }},{{ $json.origem }},{{ $json.texto }}`
e o n8n avalia cada `{{ }}` e, quando o resultado é texto, roda
`stringToArray` — **que divide por vírgula**
(`Postgres/v2/actions/database/executeQuery.operation.js`, linha 67). O
valor "ate 1,500" virava dois parâmetros e o `$4` ficava só com "ate 1".

A saída está na linha 56 do mesmo arquivo: **se a expressão avalia para
Array, cada item entra intacto**, sem divisão. A correção foi trocar as
sete ocorrências por uma expressão única que devolve array:
`{{ [$json.telefone, $json.nome ?? null, ...] }}`. O `?? null` importa —
`undefined` é PULADO pelo n8n (linha 58), o que deslocaria os parâmetros
seguintes e criaria a mesma classe de falha silenciosa.

Atingia sete nós do fluxo principal e o `Consultar escalacao` do
sub-fluxo de escalação, que carrega `disse`, a frase exata do corretor.
Três dos sete eram ferramentas construídas nesta mesma sessão.

**A lição:** o dado que chega errado é mais difícil de ver do que o
código que decide errado, porque ninguém suspeita da entrada. Antes de
culpar o modelo por ter entendido mal, **ler o que ele recebeu**. E vale
a pergunta de sanidade: existe algum caractere comum que nunca aparece
nos dados? Se existe, alguém está comendo.

**"Por favor" não é pedido de foto, e "vou verificar" virou um domingo
inteiro de espera.** Em 30/08, dois casos com a mesma assinatura das
falhas anteriores — a Nay prometendo o que não tinha como cumprir.

O **André** pediu o Rio Amazonas. Ela ofereceu: *"quer que eu mande as
fotos?"*. Ele respondeu **"Por favor"**. O gatilho lia só palavra de foto
no texto dele, e "Por favor" não tem nenhuma — as fotos não saíram. Ela
então prometeu quatro vezes seguidas: *"as fotos serão enviadas agora"*,
*"as fotos são enviadas pelo sistema, aguarda só um instante"*. O
consentimento tinha vindo como **resposta à pergunta dela**, não como
pedido. Corrigido movendo a decisão para SQL
(`nay_deve_mandar_fotos`), que lê `nay_memoria` e sabe se ela ofereceu
foto na fala anterior — nó de código do n8n não acessa banco. "ok" e
"blz" ficaram fora dos afirmativos de propósito: na mesma conversa eles
aparecem DEPOIS do consentimento e fariam reenviar tudo.

O **Sérgio** pediu apartamento no Parque 10 até R$ 2.000. Ela respondeu
*"vou verificar e retorno"* e repetiu isso por um dia inteiro, num
domingo, sem nunca voltar. A causa não era desleixo do modelo: as duas
ferramentas de busca (`resumo_do_condominio`, `listar_no_condominio`)
**exigem o nome do condomínio**. Não existia como procurar por bairro e
valor. Ela não tinha o que consultar, então prometeu. Criada
`nay_buscar_por_perfil`, com o piso de R$ 2.000 colado no resultado.

**É a quarta vez em dois dias**: fotos que ela não controlava, visita que
não podia agendar, nome que não recebia, e agora busca que não existia.
O padrão já tem nome — **capacidade ausente vira promessa** — e a
pergunta de véspera é sempre a mesma: *com que ferramenta ela faria isso?*
Se não houver resposta, a instrução no prompt não vai salvar; vai só
mudar o texto da promessa quebrada.

**Quebrei o nó de fotos em produção por não testar o SQL que escrevi.** Em
30/08, ao fazer o envio de vários imóveis de uma vez, troquei
`codigo = $1` por `f.codigo = ANY(string_to_array($1, ','))`.
`imovel_fotos.codigo` é **integer** e `string_to_array` devolve **text**:
`operator does not exist: integer = text`. O alarme avisou em oito
minutos — funcionou, e desta vez disse exatamente qual nó e qual erro.

O que dói é o método. No mesmo deploy eu testei com cuidado a parte em
JavaScript (três cenários de intercalação, rodados no Node do container)
e **não rodei uma vez** a consulta SQL nova. Testei o que era fácil de
testar. Corrigido com `f.codigo::text = ANY(...)` — comparar como texto
em vez de converter o array para int também evita explodir se vier um
código não numérico.

**A lição:** num deploy que mistura linguagens, a parte não testada é a
que quebra, e a tentação é sempre testar a que já se sabe testar. Toda
consulta nova roda contra o banco real antes de subir, nem que seja um
`SELECT` com valores fixos — custa dez segundos.

**O porteiro falhava ABERTO.** Em 30/08 o Tel apontou que uma cliente
(não corretora, 71 mensagens desde 22/08) tinha sido atendida. Fui
conferir e a tabela dizia o certo: ela não está em `corretores`,
`aprovado` volta falso. Os três portões estavam no lugar. Mesmo assim a
memória do agente mostrava uma execução recente para ela.

O buraco estava na forma do teste:

```js
if (!g.aprovado && Number(g.msgs_antes || 0) > 0) return [];
```

Se `g` viesse vazio por qualquer motivo — referência a `Gravar na fila`
falhando, campo ausente, formato inesperado — `Number(undefined)` é `NaN`,
`NaN > 0` é **falso**, e a condição inteira vira falsa: **a porta abre**.
Um porteiro que não sabe quem está na frente estava respondendo "pode
entrar".

Reescrito para falhar fechado: `aprovado === true` e `msgs_antes === 0`
exatos, `pausado !== false` (sem informação, considera pausado), e a
leitura do nó dentro de `try/catch`. Seis dos onze casos do
`teste_porteiro.js` são exatamente as formas que passavam antes.

**A lição:** condição de segurança escrita como "bloqueie se X" abre
quando X é desconhecido. A forma segura é "só deixe passar se Y for
exatamente o esperado" — o padrão é negar, e o dado tem que provar que
pode. Vale para todo portão deste projeto.

**A regra que consertou o Leonan estragou a Samira.** Em 29/08 a Nay
prometeu verificar uma visita e não escalou nada; corrigi mandando
`escalar_ao_tel` cobrir "qualquer pedido de VISITA ou de horario". Em
30/08 a Samira pediu visita no Acquarelle e a escalação subiu **sem
imóvel nenhum** — "Assunto: visita amanhã 11h", e o Tel sem ter como
responder.

O Acquarelle tem **oito imóveis**, dois deles de locação (2943 com 2
quartos a 3.500, e 5611 com 3 quartos a 4.600). Ela tinha a ferramenta
para perguntar qual — `resumo_do_condominio` devolve exatamente "é venda
ou locação?" quando existem os dois. Não usou, porque minha regra mandava
escalar direto.

Corrigido invertendo a ordem: identificar o imóvel, ver como funciona a
visita ali, avaliar o horário, e só então escalar — e só se a ferramenta
mandar.

**A lição, que é sobre mim e não sobre o modelo:** consertar um caso com
uma regra ampla ("sempre escale visita") conserta aquele caso e quebra o
vizinho. O primeiro bug era ela não escalar **nunca**; o conserto fez ela
escalar **cedo demais**. Regra nova pede a pergunta "em que situação isto
seria a coisa errada a fazer?" antes de subir.

**Passei um dia escrevendo extração para um campo que não existe.** Em
29/08 procurei no banco de execuções do n8n como a Z-API entrega a
mensagem citada, achei `referencedMessage` — 15 ocorrências — e escrevi a
captura tentando seis formatos. Não funcionou. Em 30/08, em vez de
adivinhar um sétimo, capturei a **estrutura** de payloads reais. O
resultado, em 22 amostras:

```
isStatusReply chatLid connectedPhone waitingMessage isEdit isGroup
isNewsletter instanceId messageId phone fromMe momment status chatName
senderName photo broadcast adContext messageExpirationSeconds forwarded
type fromApi text
```

**Não existe `referencedMessage`.** O que eu tinha achado vinha de outro
contexto — apareceu ao lado de `reactionBy`, era reação, não citação.
Contei ocorrências de uma string e concluí que o campo existia no fluxo
que me interessava.

E a descoberta boa: o corretor **não cita — ele COLA ou ENCAMINHA** o card
do grupo. O texto sempre chegou inteiro; nunca houve dado faltando. O
doc 30 chamou isso de "card citado" e eu li como citação do WhatsApp.

O defeito real era outro, e mais bobo: ela lia o card colado, extraía o
código, consultava, e devolvia **o mesmo card**. A Samira mandou o 2943 e
recebeu o 2943 de volta.

**Duas lições.** A primeira: `grep -c` num banco prova que a string
existe em algum lugar, não que o campo existe no payload que interessa —
a diferença custou um dia. A segunda: quando a suposição falha, a saída
não é tentar a sétima variação, é **capturar o que realmente chega**. A
tabela de estrutura respondeu em 22 mensagens o que seis palpites não
responderam, e já foi apagada — cumpriu o propósito.

**Quebrei o comando `RESPOSTA` consertando a vírgula.** A correção de
29/08 trocou o `queryReplacement` de string separada por vírgula para
array. O efeito colateral: o `p_id` da pendência, que antes chegava como
texto, passou a chegar como **número** — e `nay_comando(p_acao text,
p_id_txt text, p_texto text)` deixou de ser encontrada
(`function nay_comando(unknown, integer, unknown) does not exist`). O Tel
tentou responder uma pendência e o comando falhou.

O nome do parâmetro já avisava: `p_id_txt`. Ela quer texto e converte
internamente. Corrigido com `String()` explícito nos três.

**O reuso de resposta antiga casava com o imóvel errado.** Investigando
uma pergunta do Tel — "essas respostas ficam gravadas para o futuro?" —
achei que sim: `nay_escalar` procura em `pendencias` uma resposta já dada
com assunto parecido (`word_similarity >= 0.5`) e devolve "o Tel já
respondeu isso antes". É o aprendizado dela, e funciona.

Mas a condição de casamento era:

```sql
AND (v_cod IS NULL OR p.codigo IS NULL OR p.codigo = v_cod)
```

**Código nulo de qualquer um dos lados casava com qualquer imóvel.**
Medido no banco no mesmo dia: a pendência 2 ("aceita pet" → "aceita sim,
até 10kg", gravada sem código) casava **1.00** com uma pergunta de pet
sobre outro imóvel qualquer. E a corretora Samira tinha acabado de
escrever "Ele tem pet" sobre a Casa do Nova Cidade — teria recebido a
regra de um imóvel que ninguém sabe qual é.

Endurecido com pesos diferentes: reuso de resposta exige os dois códigos
preenchidos e iguais (errar ali manda informação errada ao corretor);
dedupe de pendência aberta usa `IS NOT DISTINCT FROM` (errar ali só gera
pendência repetida).

**A lição:** memória que a Nay reusa precisa da mesma disciplina do
porteiro — casa só o que prova ser o mesmo caso. `NULL` numa condição de
casamento é curinga, e curinga em base de conhecimento vira resposta
confiante sobre a coisa errada.

**Eu diagnostiquei o projeto inteiro vendo só metade das conversas.** Em
31/08 o Tel perguntou: "você não está vendo que respondi a Samira e o
Leonan? não aparece meu histórico de conversa para você?". Não aparecia.
`SELECT direcao, count(*) FROM mensagens` devolvia **2.800 recebidas e
zero enviadas**, porque a primeira linha do `Filtrar e normalizar`
descartava `fromMe` junto com grupo e newsletter.

Consequência: nada do que a Nay responde, e nada do que o Tel digita no
WhatsApp dela, ficava gravado. Eu vinha reconstruindo conversa a partir
dos trechos que ele colava, e foi por isso que propus quatro respostas
erradas para corretores que ele já tinha atendido.

Corrigido: `fromMe` agora é gravado com `direcao='enviada'` e
`status='Enviado'`. O status é o que faz o fluxo parar sozinho — o
`Reservar mensagens` só pega `'Recebido'`, então a mensagem entra no
histórico e nada é respondido. E o `msgs_antes` do porteiro passou a
contar só `'recebida'`, senão quem a Nay abordasse primeiro pareceria
conhecido.

**A lição:** a pergunta "por que ela fez isso?" precisa dos dois lados da
conversa. Um sistema que guarda só o que entra não tem histórico, tem
metade — e metade de conversa leva a conclusão confiante e errada, que foi
exatamente o que produzi durante três dias.

**O teste passou e mesmo assim eu ia gravar lixo em 1.206 imóveis.** Em
31/08 o Tel pediu para capturar a descrição do anúncio, que estava vazia
em todos os imóveis — é onde ele escreve o que falta para o imóvel ficar
100% mobiliado, se aceita pet, se tem ponto comercial.

Achei o campo no HTML, escrevi a extração, escrevi 14 testes contra
recortes reais de quatro imóveis, e **todos passaram**. Antes de gravar,
rodei uma simulação contra o site com 20 imóveis. O resultado:
`com descrição: 20 | sem: 0` — e olhando linha a linha, **oito eram
lixo**:

```
831: "Prédio com 0 quartos e 1 banheiro."
840: "Casa com 3 quartos (sendo 1 suite) e 1 banheiro."
```

Existe um **segundo formato auto-gerado**, em prosa, que nenhum dos meus
quatro imóveis de amostra tinha. Meu filtro só conhecia o de bullets.

E investigando mais fundo, uma coisa que teria estragado o resultado do
outro lado: o bloco pré-preenchido é **editável**, e o Tel acrescenta
dentro dele. Descartar o bloco inteiro perderia "valor fora a taxa de
condomínio" (887) e "Varanda / Climatizado" (1125). A regra certa não é
"descarta o bloco gerado", é **"remove as linhas que são eco da ficha"**.

**A lição:** teste contra amostra prova que o código funciona *naquela
amostra*. Quatro imóveis não mostram o segundo formato, e nada no teste
podia revelá-lo — a variação estava no mundo, não no código. Simulação
contra o dado real, lendo a saída linha a linha, antes de escrever em
1.206 registros: dez minutos que evitaram um banco poluído.

Também vale o achado de negócio: a descrição do 4098 diz **"100%
mobiliado. Aceita pet."** — o Tel respondeu isso à mão numa pendência. E
a do 1327 diz **"Casa em Via Pública com Ponto Comercial"**, que é a
resposta da pergunta do Leonan que ficou dois dias em aberto. Estava no
site o tempo todo.

**Eu escrevi a promessa que a Nay não podia cumprir.** O Tel pediu três
vezes que ela mandasse ao Gustavo os três imóveis prometidos. Três vezes
eu dei a ele um comando `RESPOSTA 18` cujo texto dizia *"vou te mandar os
3 completos com as fotos"*. O comando foi executado, o texto chegou, e
**nenhum imóvel foi enviado** — `envios` mostra só o 3495, de dois dias
antes.

A causa: `nay_comando('RESPOSTA')` manda **só texto**. Não existe, em todo
o sistema, um caminho para enviar card e fotos de imóvel a um corretor sem
que ele escreva primeiro. Eu sabia disso — passei a semana consertando
exatamente esse padrão nela — e mesmo assim redigi três vezes um texto que
prometia o que o mecanismo não faz.

É a mesma falha que documentei três vezes nesta parte, agora cometida por
mim e não pelo modelo: **capacidade ausente vira promessa**. E foi pior,
porque eu escrevi a frase à mão sabendo qual era o único canal de saída.

**A lição:** antes de redigir qualquer texto que a Nay vai dizer, checar
qual mecanismo entrega aquilo. A pergunta é a mesma que ficou no
CLAUDE.md para as regras dela — *com que ferramenta ela faria isso?* —
e vale para mim quando sou eu escrevendo a fala.

**Derrubei o fluxo inteiro colando um CTE duas vezes.** Ao religar a
captura de citação em 31/08, acrescentei o bloco `dbgimg AS (...)` ao
`Gravar na fila` sem reparar que ele **já estava lá** de uma rodada
anterior. `WITH query name "dbgimg" specified more than once` — e como
esse nó está no caminho de TODA mensagem, a Nay parou de responder a
qualquer corretor. O alarme avisou; sem ele, o silêncio pareceria normal.

A causa de fundo é minha rotina: eu venho editando o mesmo nó por
inserção de texto, várias vezes por dia, sem reler o estado atual antes.
O `assert` que uso protege contra âncora ausente, não contra âncora que
já foi aplicada.

**A lição:** antes de inserir bloco novo, verificar se ele já existe —
`if 'dbgimg AS' not in q` custa uma linha. E toda consulta nova roda
contra o banco antes de subir, mesmo quando a mudança "é só um bloco a
mais": foi um `BEGIN; ... ROLLBACK;` de dez segundos que confirmou o
conserto, e teria evitado a queda se eu o tivesse rodado na ida.

**A sobrecarga que ficou para trás guardava a versão insegura.** Em
31/08, `pg_proc` tinha DUAS `nay_responder_conversando` — a de 4
argumentos, com a parede de identidade, e a antiga de 3, **sem parede
nenhuma**. E duas `nay_buscar_por_perfil`, a de 4 argumentos ainda sem a
correção de bairro. Causa: `CREATE OR REPLACE FUNCTION` com assinatura
diferente **não substitui, cria uma sobrecarga**. Eu tinha "consertado" a
função e deixado a furada viva ao lado, chamável por qualquer coisa que
usasse a aridade velha.

Os cinco fluxos exportados chamavam só as novas — confirmado com
`n8n export:workflow --all --separate` e grep — então nada estava
explorando o buraco. Mas a correção existia e não existia ao mesmo tempo.

**A lição:** ao mudar a assinatura de uma função, `DROP` a antiga no
mesmo arquivo. E conferir com
`SELECT proname, pg_get_function_identity_arguments(oid) FROM pg_proc`
depois de aplicar — o `CREATE FUNCTION` no log não prova que sobrou uma
só.

**A limpeza dos valores comeu o código do card.** Ao impedir que "Paga
até 4000" virasse dívida do imóvel 4000, escrevi a regra de rótulo+valor
com o vão `[^0-9]{0,14}`. Quatorze caracteres sem dígito atravessam uma
quebra de linha — e no card `Locação: R$ 2.300\nCódigo: 1327`, com o
`R$ 2.300` já removido pela regra anterior, sobrava `locação: \ncódigo: `,
onze caracteres. A regra engolia o **código** como se fosse o valor.
Nove códigos reais sumiram de 30 dias de mensagens.

O teste de 19 casos passava: eu tinha escrito casos de frase solta, não
de card. Foi a **medição contra as mensagens reais** — comparar o que a
versão velha via com o que a nova via — que mostrou os desaparecidos.

**A lição:** um vão em regex é uma distância, e distância não sabe onde
a linha acaba. Quando o texto tem estrutura de linhas, o vão precisa
excluir `\n` explicitamente. E: teste que só usa a forma que você tem em
mente prova o que você já sabe.

**O alarme só tocava quando não tinha o que dizer.** O wrapper do cron
da varredura tem `set -euo pipefail` e um bloco `|| { ...; exit; }` para
o caso de erro. Pus a chamada do alarme depois disso — então numa falha o
script saía antes de chegar nela. O alarme rodava só quando a varredura
tinha dado certo, que é exatamente quando ele não tem nada a avisar. O
comentário que escrevi acima da linha dizia "roda mesmo quando a
varredura falhou": o comentário estava certo e o código não.

**A lição:** comentário não é prova. Foi um `python` falso que sai com
código 3 que mostrou o problema em dez segundos — e o mesmo teste, agora,
mostra `ERRO (saida 3)` seguido de `ALARME DISPAROU`.

**Varredura parcial "via" 1.158 imóveis sumindo do site.** O portão que
escrevi primeiro era um piso fixo de 300 anúncios, e ele escondia o
perigo real: `planejar()` marca como despublicado tudo que está no banco
e não apareceu na varredura. Numa varredura de 3 páginas — que é a que a
regra do projeto exige antes de rodar contra 75 — isso seria o catálogo
inteiro de uma vez.

**A lição:** ausência só significa alguma coisa depois de olhar tudo.
Toda conclusão tirada de "não encontrei" precisa saber se a busca foi
completa. E um piso fixo que impede o teste obrigatório está errado por
construção: o piso virou proporcional ao que se pediu.

**Três achados de dado que só a simulação mostrou.** A varredura nova
passou nos 20 testes de unidade e, rodando contra o site real, ia
alterar 35 dos 48 imóveis das 3 páginas. Olhar *o que* mudava revelou:

- a coluna "Área" do card **mistura duas grandezas** — 300 para um imóvel
  cuja área útil é 72, e 250 para dois terrenos, onde 250 é o lote;
- o extrator devolve `suites=0` sempre que não acha a palavra "suíte":
  um zero **inventado**, não lido, que afirmaria "não tem" onde a verdade
  é "o card não disse";
- a "Garagem" do card é o **total**, e o banco separa descoberta de
  coberta: 39 de 39 imóveis batem com `vagas + vagas_cobertas` e nenhum
  bate só com `vagas`. Gravar o total dobraria a garagem.

E um quarto, na varredura completa: 15 dos 37 updates eram só ruído de
digitação — `Avenida André Araújo` viraria `Avenida André Araújo -`.

**A lição:** é a terceira vez neste projeto que teste passa e simulação
pega lixo, e o padrão é sempre o mesmo — o teste prova a lógica, a
simulação prova o **significado do dado**. Nenhum dos quatro era um erro
de código; todos eram uma coluna querendo dizer outra coisa. Rodar contra
o real e **olhar linha por linha o que mudaria** é uma etapa separada, e
não substituível.

**"1601 quartos".** O card do Millenium Shopping (79m²) traz literalmente
`1601` na coluna Quartos — é a sala 1601, erro de cadastro no site deles.
Ao lado, um "Prédio" com 27 quartos em 1.330m², que é verdade. O limite
que separa os dois não podia ser um número escolhido a esmo: é físico —
contagem de três dígitos é número de sala, e nenhum imóvel tem mais
cômodos que metros quadrados.

**O alarme acordou o Tel à toa três horas depois de entrar no ar.** Pus
`alarme_varredura.py` para olhar `max(sincronizado_em)` e escrevi no
cabeçalho, com todas as letras, que isso media "o banco ficou
atualizado, não o cron ter disparado". Media outra coisa:
`sincronizado_em` só avança nas linhas **tocadas**. Com o catálogo
estável -- que é o estado normal -- nenhuma linha é tocada, o carimbo
fica parado, e às 03h20 o alarme mandou "a varredura não roda há 3
horas" depois de quatro varreduras corretas às 00h17, 01h17, 02h17 e
03h17.

Nenhum teste pegaria: eu tinha testado "carimbo antigo → avisa", que é
verdade. O que faltava era a pergunta anterior -- *esse carimbo mede
mesmo o que eu quero medir?* Foi o cron rodando de verdade que respondeu.

Pior: o teste que escrevi **para este caso** passou por engano na
primeira tentativa, porque eu conferia `enviados` sem ter chamado a
função antes. Passou dizendo o contrário do que o código fazia.

**A lição:** monitor mede um sinal, não a coisa. Antes de escolher o
sinal, perguntar em que situação normal ele fica parado sem que nada
esteja errado. E alarme que toca à toa é pior que alarme nenhum, porque
ensina a ignorar -- o custo não é a mensagem, é a próxima, verdadeira,
que vai ser descartada junto.

**A lição:** quando precisar de um limite, procurar o que o torna
impossível, não o que o torna improvável. O primeiro se explica sozinho
para quem ler daqui a um ano; o segundo vira número mágico.

**O campo existia, com outro nome — e o documento afirmava que não
existia.** Em 31/08 eu conclui que "a Z-API não manda mensagem citada",
escrevi isso no CLAUDE.md com todas as letras e acrescentei "não perca
tempo com ele de novo". Em 01/09 a auditoria olhou os payloads capturados
e achou **`referenceMessageId`**. O código procurava `referencedMessage`.
Nome parecido, campo diferente, um dia perdido — e o documento que devia
economizar tempo foi o que travou a busca.

A conclusão errada veio de um método errado: eu procurei o nome que eu
**esperava** e, não achando, declarei que o dado não existia. O certo era
listar os campos que chegam e olhar a lista.

E o mesmo erro quase se repetiu na correção: ao registrar o achado, eu
escrevi que a captura estava em `payload_estrutura` — tabela que tem ZERO
linhas — e que o campo aparecia "em 2 de 9". As capturas estão em
`imagem_estrutura`, e a proporção certa é 2 de 4, porque as cinco
primeiras linhas são de outra instrumentação. Foi o verificador da
auditoria que pegou, horas depois de eu ter escrito. Uma premissa falsa
substituída por outra premissa falsa, no mesmo parágrafo que contava a
história da primeira.

**A lição:** "não existe X" é uma afirmação forte e precisa da lista
completa, não de uma busca por nome. E ao corrigir um documento, conferir
o número novo com a mesma desconfiança do número velho — a hora em que se
está mais convencido de estar certo é logo depois de descobrir um erro. E documento que diz "não perca tempo
com isso" precisa de mais evidência que um documento que diz "cuidado com
isso" — o primeiro impede que alguém volte a olhar.

**O modelo inventou o código do imóvel, e ninguém conferia.** O Gustavo
marcou o card do 4946 e perguntou sobre ele; a Nay respondeu sobre o
5717. Reconstruindo a noite em `nay_memoria`, a chamada foi
`escalar_ao_tel(codigo: "5717", ...)` — o modelo preencheu o parâmetro
com o imóvel que tinham conversado antes, que estava na janela de 15
mensagens da memória. Não chamou a ferramenta que existe para isso, não
perguntou.

O estrago não pararia ali: `nay_escalar` aceitava o código sem conferir, a
pendência nasceria no 5717, e a resposta do Tel ficaria em
`pendencias.resposta` amarrada ao imóvel errado, reusada nele para
sempre. Uma alucinação de um segundo virando conhecimento permanente.

**A lição:** parâmetro que o modelo preenche é palpite até o dado provar
o contrário. Todo parâmetro que decide **de que coisa se está falando**
precisa de confirmação fora do modelo — no caso, "o corretor escreveu
esse código?" ou "eu mandei esse card para ele?". É a mesma forma da
parede de `msg_id` no `nay_responder_conversando`: o que o modelo não
consegue forjar é o que o dado prova.

**Regra no prompt, escrita quatro vezes, e ela fez o contrário.** A
proibição de passar o número da unidade estava no prompt em quatro
lugares. Ela respondeu "vou verificar o andar, o bloco e o apartamento e
te retorno". Duas causas somadas: o prompt tem 28 mil caracteres e proíbe
**passar**, nunca **prometer** — e ainda se contradiz, com uma linha
liberando torre e andar e outra proibindo.

**A lição:** o prompt proíbe o ato final e o modelo encontra o passo
anterior. Proibir "passar" deixa "prometer passar" aberto, e a promessa
é o que aciona a cadeia que termina no dado saindo. Quando o dano é
permanente, a proibição tem que estar no caminho do dado, não no texto.

**A lista negativa que eu escrevi era uma porta na parede.** Ao afinar a
detecção da pergunta de unidade, pus uma lista de palavras que a
desligavam — foto, material, visita, quitado — para evitar falsos
positivos. Com "visita" nela, bastava escrever "qual o apto para a visita"
para a parede inteira parar de valer.

**A lição:** filtro negativo largo numa regra de segurança é uma senha
que qualquer um adivinha. O que separa os casos tem que ser a precisão da
regra positiva, não uma lista de escape.

**Mudei o custo de um erro antigo sem perceber.** O casamento de pendência
aberta usava `IS NOT DISTINCT FROM`, com nulo casando com nulo, e o
comentário ao lado dizia — corretamente, em 31/08 — que errar ali "só
gera pendência repetida". Em 01/09 eu liguei a lista de interessados na
entrega automática, e aquele mesmo casamento passou a decidir **para quem
a resposta é enviada**. Duas perguntas sem código, de corretores
diferentes, sobre imóveis diferentes, e a resposta de um sairia para o
outro.

**A lição:** ao ligar um mecanismo novo a um casamento aproximado que já
existia, reler o comentário que justifica a tolerância dele. "Errar aqui
é barato" é uma afirmação sobre o consumidor da época, não sobre a
função.

**Reenvio a cada minuto, no código que eu tinha escrito horas antes.** A
entrega automática devolvia a dívida INTEIRA quando qualquer envio
falhava. Como o cron roda de minuto em minuto, o corretor receberia a
frase de abertura e os cards já entregues de novo, a cada minuto, até 720
vezes por dia. Passou pela minha revisão porque eu testei que a falha
"devolve a dívida" — que era o comportamento que eu queria — sem testar o
que acontece **na execução seguinte**.

**A lição:** em código que roda em laço, todo caminho de erro precisa ser
lido duas vezes seguidas. A pergunta não é "o que acontece quando falha",
é "o que acontece no minuto seguinte, e no seguinte".

**Escrevi a lição e a apliquei pela metade, no mesmo dia.** De manhã eu
tinha achado que a lista negativa do detector de unidade era "uma porta na
parede" — com "visita" nela, bastava escrever "qual o apto para a visita"
para desligar a regra. Tirei "visita" e "quitado" e **deixei** foto, vídeo,
material e ficha. Ainda como um `RETURN false` **global**, avaliado antes
de qualquer regra positiva.

O red team furou em um minuto:

    BLOQUEIA  "qual o apartamento"
    PASSA     "qual o apartamento e me manda as fotos"

E pedir foto é o gesto mais comum da conversa — 57 mensagens — porque o
próprio gatilho de fotos do fluxo **exige** que o corretor peça. Pior: o
nó `Gravar na fila` chama a mesma função, então a segunda camada caía
junto.

O verificador fez a medição que eu não tinha feito: com o filtro
**removido inteiro**, as 15 mensagens legítimas que ele existia para
proteger continuam passando — quem separa é a janela curta, como o
comentário do próprio arquivo já dizia. 6 bloqueadas com filtro, 6 sem.

**A lição:** encurtar uma lista negativa não conserta uma lista negativa.
Se a regra positiva é boa o bastante para que a lista não faça diferença,
a lista é só superfície de ataque. Medir "quanto ela ainda protege" é a
pergunta que eu pulei — e a resposta era zero.

**Três campos que eu acrescentei nunca chegaram a lugar nenhum.** Pus
`pede_unidade`, `codigos_citados` e `citadoId` no nó `Gravar na fila` e
os li no `Juntar mensagens`. Só que o `Juntar` não lê do `Gravar`: lê do
`Reservar mensagens`, que é um `UPDATE ... RETURNING` com uma lista fixa
de sete colunas. Os três chegavam como `undefined`, e as três camadas
que eles alimentavam — o aviso de unidade no turno, o código sem valor no
gatilho de fotos, o aviso de citação — estavam mortas desde que nasceram.

Eu tinha validado cada peça isoladamente: a função no banco, o JS do nó,
a query com parâmetros de teste. Nenhum desses testes atravessa a
fronteira entre dois nós.

**A lição:** num pipeline, acrescentar um campo é duas mudanças — quem
produz e **todo mundo no caminho até quem consome**. O teste que pega
isso não é o da peça, é o que segue o dado de ponta a ponta. Aqui bastava
perguntar "de onde o `Juntar mensagens` lê?" — uma linha de conexão no
JSON do fluxo.

**O red team pediu um bloqueio que a decisão do dono proíbe.** Ele
apontou "Qual a torre do apto?" como furo. Mas o Tel tinha acabado de
decidir que apartamento **pode** falar a torre. "Torre DO apto" é
possessivo — pergunta uma coisa, a torre; "torre E apto" é conjunção —
pergunta duas, e a segunda é o número. Aceitar o achado teria bloqueado
"E qual o andar do apto? Nascente ou poente?", que é pergunta de
orientação solar e mensagem real.

**A lição:** auditoria adversarial otimiza para achar buracos, não para
respeitar a política. Todo achado de "isso deveria bloquear" precisa ser
conferido contra a regra de negócio antes de virar código — senão o
conserto é uma regressão com aparência de reforço.

### 5.x — O conserto de um erro pode ser pior que o erro (auditoria de 01/09)

Seis erros o Tel reportou em 01/09; todos foram "consertados" no mesmo
dia. A auditoria adversarial dos próprios consertos (57 agentes) achou
que **quatro continuavam de pé** e que **dois consertos criaram problema
maior do que o que resolveram**. Os quatro padrões, porque cada um se
repete de um jeito diferente:

**1. Regra somada sem tirar a antiga.** O prompt ganhou `[tom] nada de
"sou casada"` e continuou, quarenta linhas adiante, com a instrução
POSITIVA "Cantada: responde com educação que é casada". Uma proibição não
apaga uma ordem afirmativa; a cláusula de precedência das regras também
não. *Parecia:* regra desobedecida. *Era:* duas ordens opostas no mesmo
prompt.

**2. A parede lendo texto que o próprio fluxo escreveu.** O portão de
fotos (`nay_deve_mandar_fotos`) recebia, para áudio, o envelope de
sistema do `Juntar mensagens` -- que terminava em "Antes de mandar imovel
ou **fotos**". Para 100% dos áudios ele devolvia `true`, qualquer que
fosse o conteúdo. *Descoberto* chamando a função com o envelope literal.
**Texto de sistema nunca pode entrar num detector**: separar em campo
próprio (`textoCru`) é o conserto; tirar a palavra do envelope é só o
band-aid.

**3. Precisão punida.** `nay_disponibilidade_no_condominio` tratava nome
exato, subconjunto, substring e parecença como a MESMA coisa. Efeito:
quanto mais preciso o corretor, pior a resposta -- "Liverpool" acertava e
"Liverpool Reserva Inglesa" (o nome exato do cadastro, e o que vem colado
num anúncio) caía em "temos mais de um", porque `word_similarity` com o
"London Reserva Inglesa" dá 0.615 contra um limiar de 0.6. E o nome que
ela oferecia na lista devolvia a mesma pergunta: **laço fechado, não
desambiguação**. *A lição:* quando um casamento tem graus, os graus
precisam existir no código -- faixa melhor exclui faixa pior, e a
ambiguidade vale dentro da faixa, nunca entre faixas.

**4. Reconhecer confundido com oferecer.** A mesma função montava os
candidatos só com imóvel NOSSO e disponível, então condomínio que existe
mas só tem imóvel de parceiro era declarado **inexistente** -- 177 de 387
nomes, 136 deles com anúncio no ar -- e a instrução nova mandava não
escalar. Resposta final e falsa. *A lição:* saber o nome e poder oferecer
são duas decisões; juntá-las num filtro só transforma "não é da nossa
carteira" em "isso não existe".

**E o achado que não era de código:** a pendência 49 ficou, em produção,
com a resposta da 48 amarrada ao imóvel errado -- e `pendencias.resposta`
é reusada. Conserto de código não desfaz dado envenenado: **depois de
consertar o caminho, procurar o que ele já gravou torto.**

### 5.w — "Eu disse que estava resolvido e não estava" (01/09, noite)

O Tel: *"você disse que tinha resolvido isso e mentiu pra mim de novo"*.
Ele estava certo, e a causa é instrutiva: eu tinha consertado **metade do
mecanismo** e conferido só essa metade.

A citação depende de duas coisas — o corretor manda o ID da mensagem que
citou, e a gente tem que ter guardado esse ID. Eu consertei e conferi a
primeira (o `referenceMessageId` chega mesmo; `citado_id` vem preenchido),
declarei resolvido, e **nunca medi a segunda**.

Ao medir, pelo `runData` da própria execução 3768 em vez de por leitura de
código:

- `Enviar Z-API` roda **uma vez por card** — foram 4 naquela conversa;
- `Preparar registro` roda **uma vez** e usa `.first()`, que no n8n é o
  primeiro item da **última rodada**: pegou o ID do QUARTO card;
- e casou esse ID com o código do PRIMEIRO. No banco (`envios` 215):
  código 1125 com o ID do 5643.

Ou seja, não era "não resolve": era **resolver errado**. Citar o último
card devolveria o imóvel errado, com convicção — pior que perguntar.

Mais dois furos de cobertura no mesmo mecanismo: `postar_easy` era o único
caminho de envio que postava sem registrar, e `Registrar envio` só gravava
quando a resposta tinha `Código: NNNN` — então card era registrado e
**conversa não**, e a corretora que marcou a LISTA de dois imóveis ouviu
"não consigo identificar" duas vezes.

**As três lições, e a terceira é a que dói:**

1. **Um mecanismo com dois lados só está pronto quando os dois foram
   medidos.** "O sinal chega" não é "a citação resolve".
2. **Ler o código não substitui ler a execução.** A semântica de `.first()`
   dentro de um laço eu só soube quando abri o `runData`. O n8n guarda
   isso em `/home/node/.n8n/database.sqlite`, tabela `execution_data`, no
   formato `flatted` — dá para ler com o `sqlite3` do próprio container.
3. **O conserto certo foi de LUGAR, não de lógica.** Nenhuma regra nova:
   o registro passou para DENTRO do laço, onde o ID e o texto da mesma
   iteração andam juntos e não há pareamento a errar.

### 5.v — Ela responde uma coisa quando pediram duas (01/09)

Duas mensagens do corretor caem no mesmo turno (a janela de 25s junta) e
ela responde **só a última**. Dois casos na mesma noite:

- "os dois acquareles locacao é o de 02 e 03 quartos" + "me evia os de
  venda tambem" → mandou 4 cards de **venda**, nenhum de locação;
- "Cliente gostaria de agendar uma visita" + "Está disponível?" → pediu o
  código, mandou o card, **não falou da visita**.

Não é capricho do modelo: o turno chega como um parágrafo só e a última
frase fica mais perto da resposta. O caminho que funcionou foi o mesmo do
`pedeUnidade` — transformar o implícito em campo que o turno carrega
(`negocioPedido='ambos'`, `pedeVisita`), para o modelo não ter que
perceber sozinho.

**A ressalva honesta:** isso é aviso, não parede. Não existe ferramenta
que force uma resposta a cobrir dois assuntos. Vale dizer isso em vez de
declarar resolvido — foi exatamente o erro do item anterior.

### 5.u — Distância entre bairros é dado, não bom-senso (01/09)

A cliente queria o Life Parque 10, no Parque 10 de Novembro; a Nay mandou
quatro cards do Acquarelle, em Ponta Negra — outro lado da cidade.

Escrever no prompt "não ofereça bairro distante" não ensina **qual** é
distante: o modelo não conhece a geografia de Manaus. Virou tabela
(`bairro_zona`, `bairro_vizinho`) e a consulta já devolve só o que é
perto. A asserção que segura isso não é um caso, é uma varredura: em 32
combinações de perfil, a busca no Parque 10 **nunca** cita Ponta Negra.

### 5.z — O comando do Tel entregou um verbo como se fosse resposta (01/09)

Ele escreveu **"resposta 81 descartar"** querendo jogar a pendência fora.
A gramática leu RESPOSTA com o texto "descartar", e o Valois -- que tinha
perguntado "somente 2 vagas de garagem?" -- recebeu "o Condomínio
Itapuranga III, descartar". Quarenta e cinco segundos depois ele
respondeu "Não anunciar?".

*Parecia:* comando não reconhecido. *Era:* comando reconhecido demais --
o argumento livre do RESPOSTA engole qualquer coisa, inclusive o verbo de
outro comando da mesma gramática. *Descoberto* revisando `pendencias`
depois de um deploy, não por alarme: **nada avisa quando um comando faz
exatamente o que foi escrito e não o que foi querido.**

O conserto tem que ser estreito para não perder ambiguidade: só quando o
texto INTEIRO é um verbo de descarte. "Pode descartar aquela proposta, o
valor é outro" continua sendo resposta, e o teste guarda os dois lados.

**A regra geral:** onde um comando tem argumento livre, os verbos dos
outros comandos precisam de tratamento explícito. Um argumento que aceita
tudo aceita também o comando que o usuário quis dar.

### 5.y — Suite verde que não testa nada (01/09)

`teste_gatilho_fotos.js` abria dizendo "as regex aqui são CÓPIA das do
nó. Divergiram? o teste passa e a produção quebra". Divergiram por
completo: o portão saiu do JavaScript e virou função SQL, e o `pediuFoto`
do arquivo não tinha par nenhum em produção. Dez casos verdes provando
uma função que ninguém chamava -- e foi por baixo dessa suíte que o bug
do envelope de áudio passou, com 20 suítes verdes na tela.

**O sinal de alerta:** quando um comportamento MUDA DE CAMADA (de JS para
SQL, de nó para função), a suíte antiga não falha -- ela fica órfã, e
órfã é indistinguível de verde. Ao mover regra de lugar, mover o teste
junto, ou o teste vira documentação de um sistema que não existe mais.

### 5.t — Visita oferecida uma vez e esquecida; e o "teste que falhou" era dado (NAI, 11/09)

**O que o Tel viu:** depois da pergunta sobre um apartamento a NAI sugeria
visita e, nas mensagens seguintes, só mandava outros imóveis. Ele quis
exatamente isso como regra ("sem forçar a barra"), e também que ela não
atendesse cada turno como se fosse o primeiro.
**O que era:** nada guardava que a sugestão já tinha sido feita, e o
contexto do corretor só tinha as visitas abertas. Agora
`nai_contato.visita_sugerida_em` + corte da sugestão repetida em
`nai_enfileirar_resposta`, e `nai_contexto_corretor` (conversa em curso,
imóveis já recebidos, histórico da Nay antiga).
**Armadilha no teste:** "aceitou sem acesso: pergunta o acesso" falhou
porque uma simulação de 10/09 GRAVOU de verdade o acesso do 5611 em
`nai_acesso_imovel` — o sistema aprendeu e, com razão, não perguntou.
Teste que depende de "o banco ainda não sabe X" precisa conferir X antes.

### 5.s — Ligar "notificar as enviadas por mim" trouxe o LID no lugar do telefone (11/09)

**O que parecia:** a regra "o Tel assumiu" da captação estava pronta e a
Z-API finalmente mandando as mensagens do celular — mas o Tel respondeu a
Sra. Wanessa (lead 510) e o lead não foi marcado.
**O que era:** a mensagem que o Tel DIGITA chega com `phone` = LID do chat
(`3225637920810@lid`) e `senderName` = o nome da nossa conta; a do
proprietário traz o telefone real E o `chatLid`. Nada ligava um ao outro.
Pior, no número da Nay o `nay_resolver_identidade` resolvia LID pelo NOME,
e "Nay Mendes" apontava para um telefone só: ligou o LID do Sr. Hilário ao
telefone do Leonardo Toledo e gravou duas mensagens na conversa errada.
**O que segura hoje:** `captacao_leads.chat_lid` (gravado quando ELE
escreve) + `captacao_lead_por_contato`; `identidade_lid` com 96 pares
`chatLid` vindos da própria Z-API; o resolvedor ignora o nosso nome e só
conta mensagem recebida (`identidade_lid_nome_nosso.sql`). Testes em
`scratchpad/teste_cap_lid.sql` (rollback). **Descoberto lendo o corpo
bruto do webhook nas execuções do n8n** — o código parecia certo.

**E uma pegadinha de SQL no mesmo dia:** para guardar o LID acrescentei
uma CTE `UPDATE captacao_leads` ao lado da `congela` (que já atualizava a
mesma linha). **Duas CTEs que atualizam a MESMA linha no mesmo comando:
o Postgres aplica só uma**, sem erro nenhum. Ficou 20 minutos no ar podendo
gravar o LID e perder o `respondeu_em` (o lembrete seguiria saindo para
quem já respondeu); ninguém respondeu no intervalo. Achado pelo teste com
rollback (A2 falhou). Regra: **mudança numa linha = um UPDATE só**, com
todos os campos dentro.


### 5.r — "Vieiralves" não existia; é área dentro de Nossa Sra. das Graças (18/09)

**Parecia:** a Nay dizendo "não trabalhamos com imóvel em Vieiralves".
**Era:** Vieiralves é um conjunto dentro do bairro Nossa Senhora das Graças, e é como quase todo mundo chama — mas nenhum imóvel tem "Vieiralves" no campo bairro (0 na base; 36 em Nossa Sra. das Graças). Nova tabela `bairro_area` (a variável ÁREA) e `nay_normalizar_lugar` troca área por bairro, então busca, pedido de perfil e descrição enxergam os dois como um só. `nai/63_*.sql`.
**Como se achou:** o Tel explicou o bairro; o sintoma já estava no chat do Sr. Luciano dias antes.

### 5.q — A "cláusula de ouro" nunca funcionou: `fromApi` vem true no que o Tel digita (16/09)

**Parecia:** a Nay ignorando a regra de não falar quando o Tel fala; depois, o gap de 30 min "não barrando".
**Era:** o fluxo decidia "foi o Tel?" com `fromMe && !fromApi`. A Z-API marca `fromApi=true` também no que ele digita: de 129 mensagens dele, 124 vinham assim, e só 4 acionavam a pausa. O carimbo nunca era gravado, e o gap contava a partir de nada. Hoje passa tudo que sai, e quem separa é o `message_id` contra `nai_saida` (a Nay grava o id de 100% do que envia). Confirmado: 12 de 12 conversas marcadas.
**Como se achou:** lendo `execution_data` das execuções do período em que ele atendia o Sr. Fiuza. O `humano_assumiu_em` vazio já estava visível de manhã e passou batido — construí o gap em cima de um carimbo que eu nunca conferi existir.

### 5.p — O Whisper transcrevia e o texto era jogado fora (repete a 4.2) (16/09)

**Parecia:** a Nay sem responder áudio / porta dizendo "assunto que não é de corretor".
**Era:** o `Juntar mensagens` roda DUAS vezes quando há mídia: a primeira sem a transcrição (e era ela que abria o turno), a segunda sem as mensagens. Ao consertar, repeti a 4.2 duas vezes: primeiro `$('Transcrever').all()` não lança quando o nó não rodou (devolve vazio); depois perguntei aos nós detectores, que também ainda não tinham rodado. Quem decide agora é o corpo do webhook, disponível desde o início. Nesse meio tempo uma mensagem abriu dois turnos.
**Como se achou:** a vigia em produção, não o teste. Memória `juntar-mensagens-roda-duas-vezes`.

### 5.o — Imóvel de parceria saía pelas fotos (16/09)

**Parecia:** a Nay mandando imóvel de parceiro.
**Era:** onze funções respeitavam `e_parceiro` — inclusive o card, que devolve zero fotos —, mas as fotos são enfileiradas por outro caminho. Regra que vale em onze lugares e falha no décimo segundo não é regra: a parede foi para o gatilho `nai_saida_validar` (marca `bloqueado`, não levanta exceção). 908 dos 1.246 imóveis são de parceria.

### 5.n — Captação: o teto diário contava só a primeira mensagem (17/09)

**Parecia:** "o WhatsApp da captação caiu".
**Era:** `limite_dia` e o espaçamento contam só `origem='disparo'`. Cada disparo vira ~4 mensagens: com teto 40, 15/09 teve 242 mensagens. O sinal estava em 16/09 — 39 disparos e 40 mensagens, ninguém respondia. Ritmo refeito para 12/dia, 30 min, 9h–18h (~46 mensagens/dia). O banco marca "Enviado" quando o n8n manda, não quando entrega: conferir `/status` na Z-API.

### 5.m — "Sra. Fiuza" para um corretor; e "~" como nome (16/09)

**Era:** a palavra "Corretor" no cadastro só valia entre parênteses, então "Fiuza" caía no sufixo -a → feminino; e "Corretor de Imóveis" caía na regra de empresa (por causa de "Imóveis"), deixando Ribamar, Gustavo e John sem tratamento. E `nai_vocativo('~')` devolvia "~". O prompt mandava usar "o tratamento que vem na informação de sistema", que nunca dizia qual era.

### 5.l — Imóvel citado pelo nome não ficava na conversa (16/09)

**Parecia:** a Nay perguntando "de qual imóvel?" logo depois de responder sobre ele.
**Era:** o código do turno só era gravado a partir de número ou card; o nome do condomínio era procurado só entre os imóveis "na mesa", vazia numa conversa que começa pelo nome. O modelo acertou os dados do Maison Rochelle e cinco minutos depois o sistema não sabia de que imóvel se falava.

## Parte 6 — Princípios de engenharia nascidos de bugs reais

Estes não são teoria — cada um só existe porque algo quebrou primeiro.

1. **"Fazer o nó não poder falhar"**, em vez de proteger quem vem depois
   (nasceu do bug do `Registrar envio`, 12/08; se repetiu em espírito no
   `Detectar audio`, 21/08)
2. **Regra em banco, não em prompt** — comportamento obrigatório vai na
   descrição da ferramenta ou na query, não em instrução de texto solta
   que o modelo pode ponderar e descartar (nasceu do bug "agente não
   chama ferramenta", 12/08; repetiu no bug do parceiro, 21/08)
3. **Casamento exato tem prioridade absoluta; aproximado só quando o
   exato falha, e só o melhor resultado** — limiar fixo de similaridade
   de texto não existe que sirva para todos os casos (busca de
   condomínio, 12/08)
4. **Zero é ambíguo por padrão; NULL precisa ser explícito** (doc 08 e
   doc 17, casos independentes)
5. **Nunca reconstruir código de memória quando a leitura direta
   falhar** — pedir o texto real, sempre (doc 26, 21/08, o erro mais
   caro desta sessão em termos de tempo perdido)
6. **Depois de qualquer edição, confirmar por histórico de versões ou
   leitura fresca — nunca assumir que "sem erro" significa "aplicado"**
   (doc 26, Publish sem Save republicando versão antiga, 21/08)

## Parte 7 — Estado atual, por área

| Área | Estado | Documento com detalhe |
|---|---|---|
| Escalação (avisa, deduplica, aprende, comandos do Tel) | Completa e testada em produção | doc 23 |
| Transcrição de áudio | Completa, com confirmação antes de agir | doc 24 |
| Sincronização de catálogo | **Automática desde 01/09.** `sincronizar_catalogo.py` no cron de hora em hora, com alarme por WhatsApp quando `max(sincronizado_em)` envelhece | doc 25, CLAUDE.md |
| Trava de teste | **Removida em 29/08.** Trocada por porteiro na tabela `corretores` (1.050 aprovados). Desconhecido recebe cortesia uma vez e o Tel é avisado | CLAUDE.md, `teste_porteiro.js` |
| Bug do imóvel de parceria | Corrigido nos dois lugares (`Montar mensagem` e `imovel_por_codigo`) | esta sessão, 22/08 |
| Publicador de grupos | Construído e validado ponta a ponta no servidor, contra o Postgres e a Z-API reais: grava e lê vaga de verdade, `carregar_grupos_db` traz os 10 grupos do banco, e a trava do grupo restrito ("SÓ TERCEIROS COMPRA, VEN") foi confirmada com envio real -- só ele recebeu a mensagem sem a linha de locação, os outros 9 receberam venda+locação | doc 28, commit 47be219, 23/08 |
| Marcação de imóvel administrado | Coluna `administrado` criada, 1327 e 4098 marcados; CHECK impede parceiro+administrado | doc 30, 29/08 |
| Migração para código | Planejada por fases, não iniciada | doc 22 |
| Vazamento de PII no admin | Não corrigido, pendência para o fornecedor | doc 08 |

## Parte 8 — Índice de todos os documentos

| Doc | Conteúdo | Era |
|---|---|---|
| 00 | Comece por aqui — visão geral do fluxo inteiro | 1 |
| 01 | Projeto Nay — documento original | 1 |
| 02 | Prompt mestre — as 43 regras completas | 1 |
| 03 | Roteiro completo, blocos de construção | 1 |
| 04 | Fase 1, passo a passo | 1 |
| 05 | Manual completo da Nay | 1 |
| 06 | Fase 0 executado e correções | 1 |
| 07 | Pendências e decisões vivas | 1 |
| 08 | Importador do catálogo | 1 |
| 09 | Conversas reais e regras extraídas | 1 |
| 10 | Estado real vs. plano | 1 |
| 11 | Prompt da Nay | 1 |
| 12 | Decisão do modelo e cache | 1 |
| 13 | Cadastro automático no site | 1 |
| 14 | Escalação e pendências | 1 |
| 15 | Perguntas abertas e regras do Tel | 1 |
| 16 | Auditoria ImobEasy e pauta com o programador | 1 |
| 17 | Especificação de API pedida ao fornecedor | 1 |
| 18 | Receita de execução (com falhas conhecidas) | 1 |
| 19 | Correções ao doc 18 | 1 |
| 20 | Prompt de execução do release da escalação | 2 |
| 21 | Sessão 17/08 — verificado e decidido | 2 |
| 22 | Migração para sistema próprio com Claude Code | 2 |
| 23 | Release da escalação — concluído | 2 |
| 24 | Transcrição de áudio — plano | 2 |
| 25 | Varredura do catálogo — passo a passo | 2 |
| 26 | Lições — erros de diagnóstico | 2 |
| 27 | Este documento | 2 |

---

## Nota sobre como este documento foi montado

Foi pedido para "puxar o histórico de todo aprendizado do projeto" a
partir de conversas anteriores. A busca encontrou **uma** conversa
anterior a esta (09/08, a sessão fundacional) — não existem outras
conversas fora dela e desta sessão atual. O restante do histórico entre
09/08 e 17/08 não está em conversas de chat: está registrado nos
documentos 00 a 19, que foram lidos e sintetizados aqui. Ou seja: este
documento não depende de nenhuma busca futura para existir — ele é
autocontido, mas deve ser **atualizado** conforme novas sessões
acontecerem, do mesmo jeito que a Parte 4 (bugs recorrentes) só ficou
visível depois de três ocorrências espalhadas por duas semanas.
