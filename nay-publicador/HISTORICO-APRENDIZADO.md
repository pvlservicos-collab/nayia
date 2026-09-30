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

## 09/09 — "Manda a lista pro Sergio" mandaria em 13 grupos

**O que parecia ser:** só faltava reconhecer mais uma frase — o Tel pediu
`Nay dispara lista de apartamento para locação`, e a lista por categoria já
existia desde ontem.

**O que era de verdade:** o verbo novo colidia com duas gramáticas que já
existiam. `dispara`, `posta`, `manda` e `envia` são os mesmos verbos do envio
privado (`Nay manda o 5750 pro Sergio`) e do disparo de imóvel, e a regra que
separa os dois — cauda que parece pessoa vira recusa, nunca postagem — valia
para imóvel e não para lista. Sem parede, *"Nay envia a lista de apartamento
pro Sergio"* viraria disparo em 13 grupos, sem desfazer.

**Como foi descoberto:** rodando o parser contra as variações que o Tel usa de
verdade, antes de escrever o handler. O caso apareceu na terceira linha de
saída. É o mesmo padrão da Parte 4: gramática nova entra num terreno onde já
mora outra, e a colisão só aparece quando se listam as frases reais.

## 09/09 — A lista que ninguém receberia, por tamanho

**O que parecia ser:** montar o texto e mandar.

**O que era de verdade:** as listas não têm todas o mesmo tamanho. Apartamento
para locação — o que o Tel pediu — são 33 itens e 1.755 caracteres. Apartamento
para **venda** são 118 itens e **6.600**, acima do limite de 4.096 que várias
rotas de WhatsApp aplicam. E isso já valia para o `Nay lista de ...` que
responde no privado dele, que estava em produção desde ontem.

**Como foi descoberto:** medindo `length(texto_pronto)` de todas as 12
combinações de categoria e negócio contra o catálogo real, em vez de olhar só
a que ele pediu. Duas das doze estouram.

## 09/09 (tarde) — A fila que nunca esvaziaria

**O que parecia ser:** o `varrer_tipos.py` tinha funcionado — 63 imóveis
ganharam tipo, e o "sem tipo" foi a zero.

**O que era de verdade:** ele preencheu o tipo de 63 e a área de **um**. O
anúncio dos outros 62 diz, com todas as letras, `Área Construída: 0.0 m2` — o
cadastro está vazio na origem. Como a fila era "área igual a zero", os mesmos
62 seriam pedidos ao site de novo **a cada hora, para sempre**: ~1.500
requisições por dia que nunca trariam nada, contra a regra 5 do projeto (não
martelar o site). O mesmo valia, pior, para o caminho "o anúncio não diz
nada": ali o script não gravava coisa nenhuma.

**Como foi descoberto:** contando quantos AINDA casavam a busca depois da
varredura ter rodado. O número não caiu — 63 antes, 63 depois — e foi isso que
denunciou. Se eu tivesse olhado só o "sem tipo", que foi a zero, teria dado a
tarefa por pronta.

**O que segura:** "o anúncio não tem esse dado" fica gravado em
`extras -> 'area_no_anuncio'` e o imóvel sai da fila. O marcador só vale
enquanto a área continuar vazia — preencheu no admin, a varredura escreve o
valor e a condição de área tira o imóvel da fila sozinha, sem depender de
alguém lembrar de apagar marcador. `teste_varrer_tipos.py`.

## 09/09 — "Já tirei do site e ainda está aparecendo"

**O que parecia ser:** a varredura tinha falhado em ver que o Brisas do Lírio
saiu do site.

**O que era de verdade:** a varredura viu, e marcou `publicado_no_site = false`
nos sete apartamentos no mesmo dia. O erro estava do outro lado: das 17
funções da Nay que leem `imoveis`, **nenhuma** olhava essa coluna. 35 imóveis
fora do site seguiam sendo oferecidos pela lista, pela busca por perfil e pelo
condomínio.

**Como foi descoberto:** olhando as colunas do imóvel reclamado antes de
mexer em qualquer código — `publicado_no_site` era `false` e `disponivel` era
`true`, e aí a pergunta virou "quem lê essa coluna?". Um `SELECT` sobre
`pg_proc` respondeu: ninguém.

**O padrão, que já é velho aqui:** a condição "posso oferecer este imóvel"
existia em cinco cópias dentro de três funções — e o próprio
`buscar_por_perfil` trazia no comentário o aviso de que consultas iguais lado
a lado divergem na primeira edição. Acrescentar um quarto termo em cinco
lugares seria repetir o erro; virou uma função só,
`nay_esta_no_mercado`.

**O que quase passou batido:** tirar do site não pode fazer o condomínio virar
"esse condomínio não existe" (o bug 6). Reconhecer o nome e poder oferecer são
decisões diferentes, e o teste cobre as duas.

## 09/09 — O padrão que escondia metade do catálogo

**O que parecia ser:** um detalhe de conveniência — "Nay lista de
apartamentos" já respondia alguma coisa, afinal.

**O que era de verdade:** respondia a lista de LOCAÇÃO, sempre, calada. O Tel:
*"quando pedir para venda ela precisa mandar também que vou precisar"*. Como
ela nunca dizia que tinha escolhido por ele, não havia como descobrir que
faltava uma palavra — e a lista de venda (112 apartamentos contra 18 de
locação) simplesmente não existia para quem não soubesse a frase exata.

**Como foi descoberto:** ele reclamou. O padrão tinha sido escolha minha ao
montar a lista, justificada no código por três dos quatro exemplos que ele deu
dizerem "para locação" — mas exemplo não é regra, e um padrão silencioso não
tem como ser corrigido por quem o recebe.

**A regra que fica:** quando faltar um dado que muda o resultado, perguntar
com as opções prontas. Padrão calado só serve quando a escolha errada é
barata; aqui ela escondia 112 imóveis.

## 10/09 — A vaga que seria criada e nunca dispararia

**O que parecia ser:** guardar categoria e negócio na tabela `vagas` e deixar
o cron rodar.

**O que era de verdade:** o `vaga_deve_disparar` começa com
`if not vaga["codigos"]: return False` — vaga sem código é "vaga livre". A
vaga de lista não tem código **de propósito** (o CHECK do banco exige
`codigos` vazio). Ou seja: o comando confirmaria "Vaga #12 criada", o
`Nay VAGAS` mostraria a vaga, e a lista simplesmente nunca sairia. O pior tipo
de falha deste projeto — tudo diz que funcionou.

**Como foi descoberto:** o teste de ponta a ponta do `disparar_grade` acusou
`chamadas == []`. Sem ele, isso só apareceria no dia seguinte, quando o Tel
perguntasse por que a lista não saiu.

**E a segunda, no mesmo dia:** `CODIGO_RE` é `\b\d{1,6}\b`, não 3-5 dígitos.
Então "as 08:00" virava os códigos 08 e 00, a guarda de "código na frase"
disparava, e `dispara lista ... todo dia as 08:00` era descartado inteiro. A
correção é a que o caminho de imóvel já trazia escrita desde sempre: **tirar a
hora do texto antes de procurar código** — a hora é o único trecho com dígito
que não é código. Ler o comentário que já existia teria poupado a rodada.

## 11/09 — O comando que existia e não existia

**O que parecia ser:** o `agenda de visitas` subiu, o publicador respondia
certo quando chamado à mão, e no WhatsApp nada acontecia.

**O que era:** o nó `Comando do Tel` decide o que sai do n8n por uma regex
própria, e ela não tinha a palavra AGENDA. Comando novo não existe até estar
nas QUATRO cópias da gramática — o Python correto não basta.

**Como foi descoberto:** rodando `processar_comando` à mão no servidor (que
respondeu certo) e depois lendo o `jsCode` do nó exportado, em vez de supor
que o caminho era o mesmo.

---

## 11/09 — A visita de amanhã que aparecia como hoje

**O que parecia ser:** erro de cálculo de data na agenda de visitas.

**O que era:** o servidor roda em UTC e às 22h de Manaus já é o dia seguinte
lá. `datetime.date.today()` devolvia o dia errado, comparado contra um
`data_hora` que vinha COM fuso — os dois lados em relógios diferentes.

**Como foi descoberto:** imprimindo `date.today()` e `repr(data_hora)` lado a
lado no servidor. Só o `_agenda_de_visitas` tinha nascido com `date.today()`;
o resto do projeto já usava `FUSO_MANAUS`.

---

## 11/09 — A lista colada, e o diagnóstico que eu dei errado primeiro

**O que parecia ser:** testei `interpretar_comando` com o texto multilinha no
Mac e o `ENVIO_RE`, que é guloso e casa `\n`, engoliu a lista inteira dentro
do destinatário. Os dígitos de todas as linhas viravam um "telefone" de 25
dígitos cujo final não era o do Tel. **Eu relatei isso a ele como risco de
mandar a carteira para o corretor errado.**

**O que era:** em produção isso não acontece. O nó `Comando do Tel` faz
`split('\n')` ANTES e manda só a linha que casou — então o destino resolve
certo. O problema real era o oposto e mais fundo: **a lista nunca chegava ao
publicador**, e a resposta medida de ponta a ponta era "nao entendi qual
imovel mandar para Tel Sobreira".

**Como foi descoberto:** lendo o `jsCode` do nó e rodando a lógica dele em
Node com o texto real, em vez de confiar no teste do parser isolado. **Testar
o módulo não é testar o caminho** — e o erro aqui foi anunciar uma causa raiz
antes de medir o caminho inteiro. A parede contra o destino guloso entrou
mesmo assim, porque a feature passa a mandar o texto inteiro e aí o risco
viraria real.

**A descoberta que resolveu:** as linhas que ele cola são saída LITERAL de
`nay_linha_da_lista` — ele devolve a lista que a própria Nay mandou. Então o
casamento é reverso e determinístico. E a função não é injetora: 5719 e 5728
rendem a mesma string, que é exatamente por que ele viu a linha duplicada.

---

## 10/09 — A suíte que ficou vermelha porque o produto foi usado

**O que parecia ser:** regressão introduzida pelo trabalho do dia.

**O que era:** `teste_lista_na_grade.sql` contava TODAS as vagas de lista da
tabela, inclusive as de produção. O Tel criou a primeira vaga de lista de
verdade em 10/09 e a asserção passou a acusar "5" onde esperava "4".

**Como foi descoberto:** rodando a suíte contra o commit anterior ao trabalho
e vendo a MESMA falha. E o pior estava escrito no próprio arquivo: a asserção
irmã já tinha aprendido a lição ("contou as de produção junto e acusou 3
imóvel onde eu esperava 1") — o conserto de então foi aplicado só nela.

**A lição:** asserção que conta tabela de produção tem prazo de validade.
Medir a DIFERENÇA contra uma linha de base não tem.

## 12/09 — A pergunta que induzia a resposta que ela não sabia ler

**O que parecia ser:** faltava a variação "os dois" na gramática.

**O que era:** a própria pergunta dela dizia *"ou os dois"* e ela não lia "os
dois". O texto que ela escreve faz parte da gramática — se ela oferece uma
frase, tem que entendê-la. Pergunta que não resolve na volta é laço fechado.

**Como foi descoberto:** ele reclamou em produção. E eu tinha instrução
explícita para listar as variações que ele usa de verdade, não só a forma
canônica — e mesmo assim ensinei uma forma canônica e não li a natural.

**A lição que passa da regex:** revisar toda frase que a Nay escreve
perguntando "se ele copiar isto, eu entendo?".

---

## 12/09 — Quatro armadilhas na correção, achadas antes de subir

**O que parecia ser:** bastava aceitar "os dois", "ambos", "todos".

**O que era:** as formas naturais não têm palavra-marca — são PREFIXO de
frases que já significam outra coisa. Medido: "manda todos os acquarelle para
locacao para o corretor Sergio" (frase citada no próprio código como forma
viva do envio) virava escolha com o destinatário DESCARTADO; as próprias
linhas da lista ("2 quartos sendo 1 suíte / 2.6k") viravam "manda dois", e o
nó percorre linha por linha; o dígito cru "2" virava quantidade enquanto "1"
dava "não entendi"; e "tudo sim" competia com o `DESCARTAR TUDO SIM`.

**Como foi descoberto:** rodando as frases contra o parser real e contra as
três gramáticas Node antes de subir, e lendo o dispatch inteiro em ordem.

**A lição:** gramática sem palavra-marca vai para o FIM do dispatch. Com marca
("codigo") pode ir cedo; sem marca, só depois de todos os que têm.

---

## 12/09 — Dois bugs de patch que o `node --check` não pega

**O que parecia ser:** o patch estava pronto, sintaxe validada.

**O que era:** (1) o `$'` dentro de uma regex é padrão especial de
substituição do `String.replace` do JS, e o literal entrou no nó truncado numa
string sem fechar; (2) aplicado sobre um nó que já tinha o bloco anterior, as
declarações duplicaram. Os dois derrubariam o nó INTEIRO em produção, e o
`--check` passa nos dois.

**Como foi descoberto:** `provar_nos_do_envio.js`, que executa a lógica real
do nó em vez de só checar sintaxe.

**A lição:** `() => texto` em todo `String.replace` cujo replacement seja
código; e bloco inserido por patch tem que ser DELIMITADO, para ser trocado
inteiro em vez de empilhado. Guarda por mudança não substitui delimitador.

---

## 12/09 — A suíte que ficava verde provando o código velho

**O que parecia ser:** falha intermitente no servidor.

**O que era:** `docker cp . <c>:/tmp/pasta` na segunda rodada copia DENTRO da
pasta existente, e o `cp -f pasta/*.js` passava a ler os arquivos da primeira
rodada. Verde provando código velho — e a pasta era do root, com o container
rodando como `node`, então nem dava para limpar de dentro. De passagem, `.`
levava o `.env` para o container.

**Como foi descoberto:** rodando a mesma suíte duas vezes seguidas.

**A lição:** copiar para dentro de container é lista explícita e caminho que o
usuário do container possa sobrescrever. Nunca a pasta inteira.

## 13/09 — A agenda que ninguém enchia, e a promessa que eu fiz

**O que parecia ser:** a Nay falhou em achar a visita que a Renata agendou.

**O que era:** nada no sistema escrevia na tabela `visita`. Só havia leitores.
Eu construí a tabela, o cron de alertas e o comando em 11/09, inseri duas
visitas À MÃO para demonstrar, e disse ao Tel "registradas, amanhã às 06:00 o
cron manda o briefing". O recurso parecia vivo porque eu o tinha alimentado à
mão.

**Como foi descoberto:** `grep 'INSERT INTO visita'` — zero resultados.

**A lição, que o projeto já tinha escrita e eu repeti mesmo assim:**
capacidade ausente vira promessa. E há um agravante próprio deste caso: dado
de demonstração inserido à mão faz o recurso parecer pronto, inclusive para
quem o construiu. Se eu preciso popular a tabela para mostrar que funciona, o
que eu mostrei não funciona.

---

## 13/09 — 67% do que um detector ingênuo pega não é o que ele procura

**O que parecia ser:** bastava procurar "palavra de visita + hora".

**O que era:** medido em 6.114 mensagens reais, esse detector casa 54 e 36
delas (67%) não são agendamento novo. E as quatro piores estavam fora do
universo óbvio: a PRÓPRIA saída do cron de alertas está na tabela e casa o
detector inteiro; o Tel escapa do filtro de telefone pelo `@lid` e os comandos
de grade dele casam; faixa de preço parece hora; e "As 2 visitas de sábado não
deram certo" virava visita fantasma às 02h00, porque ali o número é contagem.

**Como foi descoberto:** medindo antes de escrever, contra o corpus real, e
rodando o detector em SIMULAÇÃO contra os 34 dias de mensagens.

**A lição:** detector que escreve na agenda de alguém tem que rodar em seco
contra o dado real antes de subir — e o número que importa não é quantos ele
acha, é quantos ele acha ERRADO.

---

## 13/09 — Dado de teste que apaga dado de verdade

**O que aconteceu:** a prova de ponta a ponta inseriu uma mensagem fingida de
uma corretora REAL, e o detector — que trocava a visita aberta daquele
corretor — sobrescreveu a visita de segunda da Renata.

**O que era:** dois erros ao mesmo tempo. O de desenho: "remarcar" não pode
valer para qualquer visita aberta, só para a do mesmo dia — quem agenda dois
imóveis em dias diferentes tem duas visitas. E o de método: usei um telefone
de corretora real numa prova que ESCREVE.

**A lição:** prova que escreve usa identidade de teste, não a de alguém que
tem dado vivo na tabela. O defeito de desenho foi um presente; o risco não.

## 14/09 — "A regra não foi feita" quando a regra estava feita

**O que parecia ser:** o card não sabia imprimir "(incluso a tx)".

**O que era:** sabia, e sempre soube. O 3714 tem a marca no banco e sai com o
sufixo; o 5718 não tem a marca. E o histórico mostra que o comando
`5718 incluso a tx` nunca foi mandado. Faltava o DADO — em 50 dos 85 imóveis
de locação no mercado.

**Como foi descoberto:** medindo o card ao vivo contra um imóvel que TEM o
dado, antes de tocar no código.

**A lição:** quando alguém diz "essa regra não foi feita", o primeiro teste é
rodá-la contra um caso que tem o dado. Reescrever a formatação teria
"consertado" um bug inexistente e deixado os 50 imóveis sem taxa do mesmo
jeito. E o conserto certo não foi de código de formatação: foi fechar o laço
de aprendizado, avisando com o comando pronto quando o dado falta.

---

## 14/09 — Trabalho vivo em produção sem commit

**O que aconteceu:** ao fazer o deploy, o `git pull` recusou — o
`publicador.py` do servidor tinha 26 linhas a mais que o repositório.

**O que era:** a "metadinha" (mosaico de 4 fotos no disparo de grupo), de
outra frente de trabalho do mesmo dia. A tabela `imovel_colagem` já tem 1.039
linhas, ou seja o recurso está VIVO em produção — e o código dele existia só
no disco do servidor. Qualquer `git reset --hard`, que é passo rotineiro de
deploy, teria apagado.

**Como foi descoberto:** o `git pull` falhou e eu li o diff antes de forçar.

**A lição:** `git status` no servidor antes de puxar, e ler o diff antes de
qualquer coisa que sobrescreva. Mudança local no servidor não é lixo até se
provar que é — aqui era um recurso em produção. Guardei cópia em
`/root/backups-n8n/` e reapliquei por stash; o commit continua faltando, e
isso é dívida aberta.

## 14/09 — O pedido que eu atendia à mão, e o que ele escondia

**O que parecia ser:** ensinar à Nay três formas de frase.

**O que era:** medido antes de escrever, uma das formas era PERIGOSA hoje
mesmo — "até 4.200" virava os imóveis 4 e 200, e o site devolve página vazia
que o envio aceitava. E as regras que eu aplicava de cabeça ao atender à mão
(nosso e no ar, dinheiro perto não é dinheiro igual, só os que servem) não
estavam escritas em lugar nenhum: tiveram que virar código uma a uma.

**Como foi descoberto:** rodando as três mensagens literais pelo parser e pela
lógica do nó ANTES de construir, e depois contra o catálogo real. A prova real
pegou o que os testes não pegam: frase descrita no casador errado, nome de
condomínio casando por pedaço — e a própria prova gravando uma pendência viva.

**A lição:** quando o pedido é "faz sozinha o que você fez à mão", o que precisa
virar código não é a frase — é o julgamento que eu fazia sem dizer.

---

## 14/09 — O nome da própria conta gravado por cima dos corretores

**O que parecia ser:** a Flávia cadastrada com o nome errado.

**O que era:** desde 12/09 as mensagens enviadas são gravadas com o `senderName`
da nossa conta, e a sincronização de nome não olhava a direção. 8 corretores
viraram "Nay Mendes". O arquivo que "conserta" nomes tinha o mesmo defeito e,
rodado de novo, renomearia todos.

**Como foi descoberto:** a prova do envio mostrou "mandei 2 para Nay Mendes".
E a simulação do conserto mostrou que ele apagaria o rótulo dos números de
teste — medido antes de aplicar.

**A lição:** quando uma fonte de dado nova passa a entrar (as mensagens
enviadas), todo detector e toda sincronização que lê aquela tabela precisa ser
revisto — foi o mesmo formato do bug do portão de fotos lendo o envelope de
áudio.

### 23/09/2026 — "envia 92 99462-9241 codigo 150" morreu em três consertos seguidos

**O que parecia ser:** a regex do envio não aceitava a palavra "codigo".
Verdade, mas incompleto — e foi por acreditar nisso que o conserto falhou
duas vezes antes.

**O que era de verdade:** a gramática vive em **sete** cópias, em **dois**
fluxos do n8n, e o CLAUDE.md contava quatro. A conta velha não incluía o fluxo
da NAI — que é justamente quem atende os comandos do Tel hoje. Consertei o
Python (1/7), depois os nós da Nay antiga (3/7), e o comando continuou morto,
porque quem decide se a frase vai ao publicador ou ao modelo é o
`Rotear pelo cabeçalho` **da NAI**.

**Como foi descoberto:** listando, nos dois workflows exportados, todo nó cujo
código contém o literal do verbo de envio. Quatro viraram sete na hora. Lendo
código eu não teria achado: o nome do nó é o mesmo nos dois fluxos.

**O sintoma que chegou ao Tel** foi a Nay respondendo a ele *sobre ele
mesmo* — "o corretor Tel Sobreira pediu fotos do 150 e não achei foto" —
porque, não sendo reconhecida como comando, a frase seguiu para o agente da
NAI, que tratou o Tel como um corretor qualquer.

**O que segura hoje:** `casos_telefone_na_frente.json` é fonte única do Python
e do Node; `provar_nos_da_nai.js` prova a ROTA dos nós da NAI, que nenhum
teste cobria; e o CLAUDE.md traz a tabela das sete cópias em vez de um número.

**A parede dos dois dígitos:** o catálogo tem um imóvel de dois dígitos (o 45)
e 14 de três, então "até 2 números" é real. Mas dois dígitos livres fariam
"os 2" — a escolha da lista, medida em 12/09 — virar o imóvel 2. Por isso dois
dígitos só valem com a palavra `codigo` escrita: o marcador é o que paga a
licença de descer para dois.

### 24/09/2026 — o título do card perdeu o condomínio, e o conserto quase virou uma piora

**O que parecia ser:** a varredura gravou o condomínio errado no 5749.

**O que era de verdade:** duas fontes para o mesmo dado. O card lê a página AO
VIVO, e a página do 5749 não publica o campo de condomínio (`condominio:
None`). Quem sabe o nome é a TABELA, que a varredura preenche lendo a
LISTAGEM — e a listagem traz "Soberane  Work". O título caiu no genérico
"Sala bairro Adrianópolis" e foi assim para 16 grupos.

**A armadilha, achada medindo antes de escrever:** cair no banco sem filtro
seria uma piora. Amostrei 14 imóveis cuja tabela tem `condominio_nome` e
conferi cada um contra a página ao vivo: DOIS não tinham o campo na página, e
nos DOIS o valor da tabela era **"Casa"** — o tipo, não um condomínio. No
catálogo são 77 linhas assim. O card teria caído de "Casa bairro Flores" para
"📍 Casa", que identifica menos, em 55 imóveis ofertáveis.

**E a regra já existia.** Ao escrever a validação em Python, o guarda do patch
(`"condominio_de_verdade" not in c`) casou com uma chamada de
`nay_condominio_de_verdade` que já estava no arquivo — a função SQL que a
busca da Nay já usava, com os mesmos rótulos e mais um caso ("não
identificado"). O guarda por SUBSTRING de identificador escondeu que eu estava
escrevendo a sexta cópia de uma regra. O nome certo estava no arquivo o tempo
todo, dizendo que a regra existia.

**Como foi descoberto:** o card continuou saindo errado depois do patch, e o
`except Exception: pass` engoliu o `NameError` do import que nunca entrou.
Desmontar o helper linha a linha mostrou que cada peça funcionava sozinha —
o que só sobra se o que roda não for o que eu acho que roda.

**O que segura hoje:** quem julga o nome é `nay_condominio_de_verdade`, no
banco, uma vez. O teste do card não testa uma cópia da regra: ele afirma que o
helper PERGUNTA ao banco (`assert` na query) e obedece à resposta.

### 24/09/2026 — declarar sem usar: o patch que passou no `node --check` e não fazia nada

**O que parecia ser:** acrescentar a segunda forma de comando ao n8n foi só
somar uma regex ao bloco.

**O que era de verdade:** o patch tinha dois caminhos — "bloco não existe,
insere e liga" e "bloco existe, troca o literal". O segundo trocava só as
DECLARAÇÕES. Os seis nós passaram a declarar `ENVIO_TEL_ANTES` e **nenhum o
usava**. Sintaticamente válido, semanticamente morto.

Ao consertar com uma função nomeada (`EH_ENVIO_TEL`), a contagem de usos
`/EH_ENVIO_TEL\(/` não casava com a definição `const EH_ENVIO_TEL = (x) =>` —
espaço antes do parêntese. O patch achou "sem uso", religou um nó já ligado e
**duplicou `const mTelFrente`**, que derruba o nó inteiro e passa no
`node --check` (é a lição de 12/09, de novo).

**Como foi descoberto:** `provar_seis.js`, que conta declarações e usos e
executa cada literal. Os dois defeitos foram pegos antes do import — e o
segundo só porque o provador afirma também o que NÃO pode existir.

**A lição que passa:** patch idempotente precisa de duas asserções, não uma.
"O que eu queria inserir está lá" não basta; falta "e está sendo USADO, uma
vez só".

### 25/09/2026 — "Mirante das Flores" morreu porque o nome dele contém um bairro

**O que parecia ser:** o imóvel não existia, ou o condomínio não casava.

**O que era de verdade:** casava bem demais. O casador de condomínio achou
"Mirante Das Flores" e o casador de bairro achou "Flores" — palavra que está
dentro do nome do condomínio. A consulta virou condomínio **E** bairro, e o
5727 fica em **Ponta Negra**, não em Flores. Não sobrou nada.

**Como foi descoberto:** a própria recusa dizia, porque ela informa o que
entendeu: *"(entendi: locação; no Mirante Das Flores; no bairro Flores)"*. Sem
esse resumo eu teria procurado o defeito no casamento de nome.

**É a mesma falha de 15/09, no sentido oposto.** Lá "parque das laranjeiras"
era BAIRRO e o casador de condomínio achou "Condomínio Laranjeiras"; a guarda
escrita então derruba o condomínio cujas palavras cabem no bairro. Ninguém
escreveu a simétrica, e ela faltou por dez dias.

**O que segura hoje:** `desempatar_condominio_e_bairro`, uma função pura com
os dois sentidos, extraída de dentro do `imoveis_do_pedido` — onde não tinha
teste nenhum. Quem contém o outro perde; quem é mais específico fica. O
segundo passo só olha os nomes que sobraram do primeiro, senão um caso em que
os dois se contêm derrubaria os dois e o pedido ficaria sem lugar nenhum — o
mesmo "não achei" por outro caminho.

**Um caso que meu próprio teste corrigiu:** eu esperava que "Residencial Ponta
Negra I" + bairro "Ponta Negra" mantivesse os dois. Está errado — o bairro cabe
inteiro no nome do condomínio e deve cair, pelo mesmo motivo do Mirante: o
condomínio pode não ficar no bairro que o nome dele sugere, e quem manda é o
condomínio. Se ficar, o filtro de bairro não acrescentava nada mesmo.

### 25/09/2026 — o comando do grupo novo nascia morto no `Comando do Tel`

**O que parecia ser:** acrescentar um comando é escrever a regex no Python.

**O que era de verdade:** `Nay envia para o grupo alto padrão 4567` — a frase
que o Tel deu — passava no Python e no `Rotear pelo cabeçalho` da NAI (que a
mandava para `tel_antigo`), e **morria no `Comando do Tel`**. O
`NAO_PESSOA_RE` contém `grupos?`, então o ramo de envio descarta de propósito
— é a parede que impede "envia o 5750 pro grupo" de virar disparo em 17
grupos — e o ramo de POSTA não casa com "envia". O sintoma seria mais um
"mandei e ela não fez nada".

**Como foi descoberto:** executando a lógica real dos nós contra o workflow
exportado, antes de qualquer deploy. As formas com "posta"/"publica" passavam;
só a forma com "envia", que é a que ele usa, falhava. Um teste que só olhasse o
Python teria ficado verde.

**O que segura hoje:** o literal entrou no BLOCO compartilhado do patch e é
ORado dentro de `EH_ENVIO_TEL` — a função nomeada criada em 24/09 justamente
para que forma nova custasse UMA edição em vez de seis. E
`casos_alto_padrao.json` é a terceira fonte única lida pelos dois lados.

**A lição que passa:** quando uma gramática tem uma parede (aqui,
`NAO_PESSOA_RE`), a forma nova pode ser exatamente o que a parede existe para
barrar. Não basta perguntar "a regex casa?" — tem que perguntar "e o que vem
depois dela deixa passar?".

### 25/09/2026 — o comando novo virou resposta em dobro, e o aviso de ALUGOU saiu no grupo errado

**O que o Tel viu:** mandou "Posta no grupo alto padrão easy 5748" e recebeu
frases sem nexo — "ok, não postei o 5035 de novo", "entendido, tel. sem fotos".
Achou que nada tinha funcionado e repetiu o comando três vezes. E o aviso de
"ALUGOU 2943" saiu **nos dois** grupos, quando devia sair só no IMÓVEIS PARA
ANUNCIAR EASY.

**O que era de verdade, e são dois estragos meus:**

**1. Duplicação.** O literal que eu acrescentei ao nó incluía os verbos
`post|public` — que o nó **já** tratava num ramo próprio, o das palavras em
caixa alta. Então `Posta no grupo alto padrão easy 5035` casava **os dois
ramos** e o publicador era chamado **duas vezes**. A reserva atômica fazia a
segunda chamada virar "já foi postado, quer que eu poste de novo?" — e ele
recebeu isso em cadeia, sobre códigos de comandos anteriores, porque as
respostas chegavam fora de ordem.

**2. Três lugares, consertei um.** `todas_fotos` selecionava o grupo em TRÊS
pontos: o comando do Easy, o aviso de ALUGOU/VENDEU e o disparo de lista.
Quando o segundo grupo com `todas_fotos` nasceu, eu parametrizei só o comando.
O aviso passou a sair nos dois — foi o que ele viu — e o disparo de lista
tinha o mesmo defeito, ainda sem ninguém ter visto.

**Como foi descoberto:** o primeiro, lendo a conversa dele no banco em ordem de
id — as respostas apareciam **em pares idênticos**, e par idêntico é assinatura
de execução dupla, não de modelo confuso. O segundo, ele mesmo relatou; eu
confirmei procurando `todas_fotos` no arquivo inteiro em vez de só no lugar que
eu tinha mexido.

**O que segura hoje:** `grupos_com_apelido(conn, apelido)` é uma função só,
usada nos três pontos. O literal do nó não tem mais `post|public`, e
`casos_alto_padrao.json` ganhou uma **terceira coluna** marcando o que o ramo
de POSTA já pega — o teste do Node afirma que o literal **não** casa essas, e o
do Python afirma que o dispatch casa todas.

**A lição que passa:** ao somar um reconhecedor a um nó que já tem outros,
perguntar quantos ramos a frase acende. Um a mais não é redundância inofensiva
— em envio de WhatsApp, é a mensagem saindo duas vezes. E ao dar a um dado uma
segunda instância (aqui, o segundo grupo `todas_fotos`), procurar TODOS os
lugares que assumiam haver um só.

### 25/09/2026 — "de 2750" virou o código 2750

**O que o Tel viu:** "envia o parque imperial de 2750 para locação" devolveu
"2750: nao achei esse codigo no site".

**O que era de verdade:** o 2750 caiu na faixa dos códigos do catálogo (45 a
5755) e foi lido como imóvel. A regra que decide isso é deliberada e boa — só
conta como dinheiro o que **tem cara de dinheiro** ("3.5k", "2.750", "4 mil"),
*"senão 'o 5718' viraria preço"*. Um `2750` seco não tem ponto nem sufixo.

**O que separa os dois casos é o ARTIGO.** Ele chama o imóvel de "o 5750",
nunca de "de 5750". Quando escreve "de", está dizendo o valor — e em geral já
nomeou o condomínio antes, como aqui.

**Medido antes de escrever:** no corpus inteiro, **zero** mensagens — dele ou
de qualquer corretor — trazem "de <número de 3 a 5 dígitos>". Nenhum falso
positivo possível no histórico. Não é prova de que nunca haverá, mas é a melhor
evidência disponível, e foi o que autorizou mexer no caminho de envio.

**Um defeito que o próprio teste pegou:** "de 700 mil" casava nas DUAS regras e
o valor entrava duplicado — `['700 mil', '700']` —, abrindo a porta para casar
um imóvel de R$ 700. Quando há sufixo de dinheiro, a regra antiga já leu o
valor inteiro e a nova não tem nada a acrescentar.

**O que segura hoje:** a cauda de unidade e de sufixo fica de fora nas duas
pontas ("área de 250m2" não é preço de 250; "de 3 suítes" não é preço de 3), e
os quartos já saem do texto antes de ler valor.

### 27/09/2026 — o "sim" da repostagem postava sempre no Easy

**O que parecia ser:** nada. Ninguém tinha visto. Apareceu ao ligar o terceiro
grupo de apelido (o Comercial), procurando quem mais assumia que o apelido era
sempre o Easy.

**O que era de verdade:** `_responder_pergunta` chamava
`_postar_easy(codigo, conn, de_novo=True)` **sem parâmetro nenhum**. Quando ele
mandava "posta no grupo alto padrão 4567", recebia "já foi postado, quer de
novo?" — e o "sim" postava no **Easy**. Grupo errado, e postagem em grupo não
desfaz. Estava lá desde 25/09, à espera de alguém responder "sim" a uma
pergunta que não fosse do Easy.

**Como foi descoberto:** não por sintoma. A tabela e o rótulo do grupo viviam
soltos em cada `if` do dispatch, e ao escrever o terceiro `if` a pergunta
natural foi "quem mais chama isto?". O único que chamava sem os parâmetros era
o "sim". É o padrão 4.3 de novo — regra repetida diverge — só que aqui a
divergência não estava entre cópias, estava entre a chamada com parâmetros e a
chamada sem.

**O que segura hoje:** `GRUPOS_DE_APELIDO`, um dicionário com os três valores
(tabela, rótulo, regra de foto), e o apelido viajando na pergunta pela coluna
`nome`. `coalesce(nome,'easy')` preserva as 15 perguntas antigas, que eram do
Easy mesmo. `teste_grupo_comercial.py`.

### 27/09/2026 — o horário pedido era engolido, e o imóvel saía na hora

**O que o Tel pediu:** "posta no grupo comercial 5763 / posta todo dia as 08h /
posta segunda, quarta e sabado as 07h", como uma família de comandos.

**O que era de verdade:** "posta no grupo comercial 5763 todo dia as 08h" casava
o roteador do grupo, que só procura código, e virava postagem **imediata** — o
"todo dia as 08h" sumia sem uma palavra. Ele pediria programação e receberia
post na hora, sem desfazer. O Alto Padrão tinha o mesmo furo desde 25/09.

**Por que não dá para simplesmente agendar:** quem diz não é o código, é o
banco. O CHECK `vagas_imovel_ou_lista` exige `destino IS NULL` na vaga de
imóvel — destino de grupo só existe na vaga de LISTA. Agendar um imóvel para um
grupo escolhido é mudança de esquema.

**O que segura hoje:** `_agenda_que_o_grupo_nao_tem` recusa e ensina os
caminhos que existem. E a recusa do Alto Padrão **não** oferece a frase de
lista: ele não é destino de lista, e oferecê-la mandaria a lista para os 13
grupos de parceiro todo dia. Recusa que ensina o comando errado é pior que
recusa seca.

### 27/09/2026 — a linha do cron da varredura, comentada de novo

**O que se viu:** a Nay só conseguia oferecer **269** imóveis. O site serve
~855.

**O que era de verdade:** `#17 * * * * ... sincronizar_catalogo.sh` — a linha do
crontab começa com `#`. É **a mesma causa** dos cinco dias parados de 18 a
23/09, já registrada neste arquivo. A varredura em simulação, rodada à mão,
viu 4 novos (entre eles o 5763) e 575 alterados.

**Por que o batimento não pegou:** ele existe e funciona — `varredura_rodou_em`
marcava 17:20 do mesmo dia, porque alguém tinha rodado **à mão**. Execução
manual satisfaz um vigia que só pergunta "rodou?". A pergunta que faltava é
"rodou **pelo cron**?".

**A lição que passa:** vigia de frequência precisa medir a frequência, não a
última ocorrência. Duas execuções manuais por dia parecem saudáveis para quem
só olha o carimbo mais recente.

### 27/09/2026 — parceria não saía por lugar nenhum, menos pelos grupos

**O que o Tel pediu:** "não quero imóvel de parceiro, só nosso direto, pode
retirar o de parceiro da lista" — depois de descobrir que 565 dos imóveis que
voltaram ao catálogo eram de parceria.

**O que era de verdade: não havia nada para tirar das listas.** Medido antes
de escrever uma linha: as quatro funções da Nay que leem `imoveis`
(`nay_lista_de_imoveis`, `nay_buscar_por_perfil`,
`nay_disponibilidade_no_condominio` e a do envio) já traziam
`AND NOT coalesce(i.e_parceiro, false)`. Os 252 itens de todas as listas
somadas são nossos. O envio a corretor por código ganhou a mesma parede horas
antes, na revisão da manhã.

**Onde faltava:** a POSTAGEM EM GRUPO. `_postar_codigo` lê o site ao vivo e
nunca consultou `e_parceiro` — 561 imóveis de parceria no ar, qualquer um
saindo nos 17 grupos com um `Nay posta o NNNN`, sem desfazer. O Easy, o Alto
Padrão e o Comercial tinham o mesmo buraco.

**A decisão desconfortável: este portão NÃO falha fechado**, contra a regra
geral do projeto, e é consciente. O caso comum de "não sei" aqui é imóvel
RECÉM-CADASTRADO, que ainda não tem linha na tabela — o 5763 passou o dia
inteiro assim. Fechar transformaria a varredura em pré-requisito do comando
que ele mais usa, e o CLAUDE.md é explícito no contrário ("imóvel cadastrado
agora já pode ser postado agora"). Então só recusa com PROVA: linha existe e
`e_parceiro` é verdadeiro. Medido: `e_parceiro` não é nulo em nenhuma das
5.665 linhas, então "tem linha" já decide.

**A lição de método:** a pergunta "onde isso já está certo?" veio antes de
"como eu implemento". Se eu tivesse começado escrevendo, teria posto a quinta
cópia de um filtro que já existia em quatro lugares — e o furo real, que era o
único caminho sem ele, continuaria aberto.

**E o dublê genérico errou pela terceira vez.** A fila de cursores do
`FakeConn` é posicional, e uma consulta nova ANTES da reserva entregava à
parceria o cursor que era de outra pergunta. Agora `CursorQuePeek` olha a
consulta antes de consumir da fila. `teste_parceria_nao_posta.py`.

### 27/09/2026 — "de segunda a sexta" agendava só segunda e sexta

**O que era:** ao abrir o agendamento de imóvel por grupo, testei as variantes
que o Tel usaria. `de segunda a sexta as 9h` devolveu **seg, sex** — as duas
pontas, três dias a menos.

**Por quê:** `_recorrencia_do_trecho` percorria os nomes de dia procurando
cada um solto. "de segunda a sexta" contém "segunda" e "sexta", e a palavra
"a" do meio não significava nada para ele. Não é caso novo: a leitura de
intervalo nunca existiu, e ninguém tinha escrito a frase.

**Por que é o pior tipo de defeito:** não dá erro. A Nay confirma "Vaga #N
criada: toda segunda e sexta às 09:00", ele lê, e nada denuncia que faltam
três dias. Recusa teria sido melhor que isso.

**O que segura hoje:** `_INTERVALO_DIAS_RE` roda ANTES do laço e retira o
trecho casado do texto — senão o laço acharia as duas pontas de novo e o
resultado seria o mesmo. Dá a volta na semana: "de sexta a segunda" é
sexta, sábado, domingo e segunda. `teste_grupo_comercial.py`.

**A lição de método:** o bug não apareceu no que ele pediu — apareceu porque
escrevi quinze variantes plausíveis antes de dizer que estava pronto. "Coloca
várias variantes" é, na prática, um pedido de teste de mesa.

### 27/09/2026 — a hora escrita como 08:00 matava o comando de grupo

**O que se viu:** `posta no grupo comercial o 5763 as 08:00 segunda, quarta e
sexta` caía em "não reconheci", enquanto a mesma frase com `as 08h` funcionava.

**O que era:** `CODIGO_RE` aceita 2 dígitos, então `08:00` vira os "códigos"
08 e 00. O interpretador do grupo conta os códigos ANTES de olhar o
agendamento, achava três e desistia. **É literalmente a mesma armadilha já
registrada** no caminho da vaga de lista — "a hora sai do texto ANTES de
procurar código" — e eu a reintroduzi num caminho novo no mesmo dia em que o
CLAUDE.md a descreve.

**O que segura hoje:** a leitura da vaga vem antes da contagem de códigos nos
três interpretadores de grupo, e `_interpretar_posta` (que já tira a hora
primeiro) é quem faz o trabalho.

### 27/09/2026 — o Soberane saía duas vezes, e o sistema achava normal

**O que o Tel viu:** na grade, `segunda, quarta e sábado às 17h: 5749 soberane
work 6.5k` — **duas vezes**, em linhas seguidas. "a Nay está repetindo ... se
ela fizer duas postagens assim já não permite isso, foi algum erro que eu fiz".

**O que era de verdade:** as vagas 489 e 490, o mesmo código, mesmo horário,
mesmos dias. O grupo recebia o imóvel duas vezes em cada um desses dias, desde
que a segunda foi criada. Não foi erro dele: ele mandou o comando duas vezes,
quase certamente porque o primeiro pareceu não pegar, e o banco aceitou os
dois sem uma palavra.

**O que torna isto instrutivo:** o CLAUDE.md JÁ DESCREVIA este risco, com
estas palavras — *"Um índice único impede a mesma lista duas vezes no mesmo
horário — ele repetiria o comando achando que não pegou, e os grupos
receberiam duas vezes por dia para sempre"*. A frase foi escrita para a vaga
de LISTA, em 10/09. A vaga de IMÓVEL, que é mais antiga e muito mais usada,
nunca ganhou a mesma proteção. **O raciocínio estava certo e documentado, e
não foi aplicado ao caso vizinho.**

E quando eu criei o índice da vaga de grupo, horas antes, escolhi de propósito
cobrir só a vaga COM destino, para não mexer na grade antiga. Vi a duplicata,
escrevi sobre ela no comentário do arquivo, e deixei. Ele teve que pedir.

**O que segura hoje:** `vagas_imovel_unica` cobre TODA vaga de imóvel com
código, com ou sem destino — `coalesce(destino,'')` porque NULL nunca é igual
a NULL num índice único, e sem isso o índice existiria sem proteger o caso
real. Vaga LIVRE fica de fora de propósito (não posta nada, e as 3 e 4 são
duas legítimas às 08h). O publicador traduz a violação em frase que diz onde
conferir, porque o motivo de repetir o comando é achar que não pegou.

**A lição que passa:** ao escrever "isto protege contra X", perguntar quais
outras tabelas ou caminhos têm o mesmo X. Nos dois casos deste dia — a
parceria e a vaga repetida — a regra certa já existia a um passo de distância.

### 27/09/2026 — a lista mostrava o valor da última varredura, não o do site

**O que o Tel viu:** "o 3210 do morada dos passaros não atualizou na lista de
disparo de casas de condomínio".

**O que era de verdade:** duas fontes, e ele conhece só uma. O CARD lê o site
ao vivo (`buscar_imovel`); a LISTA lê a tabela `imoveis`, que a varredura
alimenta. Com a varredura desligada — a linha do cron estava comentada desde
26/09 — a tabela parou no tempo e a lista foi junto. Conferido depois de
religar: banco e site batem nos dois valores do 3210 (900k / 9k).

**Por que o conserto do cron não bastava:** de hora em hora não é "sempre".
Ele muda um preço no admin e dispara a lista em seguida — a janela é de
minutos, não de uma hora.

**O que segura hoje:** o disparo relê no site o valor dos imóveis DAQUELA
lista, antes de montar o texto, e grava só o que mudou. Quatro paredes, todas
por motivo medido: anúncio fora do ar não zera valor (o dict truthy com tudo
None poria o imóvel de graça em 13 grupos), `None` do site não é zero (imóvel
só de locação não tem venda), falha isolada por anúncio, e a pausa de 1,5s.

**A peça que evitou a armadilha de sempre:** para reler "os imóveis da lista"
era preciso saber quais são, e `nay_lista_de_imoveis` só devolve texto. Copiar
o WHERE de seis condições teria criado a sétima cópia de uma regra — o padrão
4.3. `nay_codigos_da_lista` foi extraída e as duas passaram a ler dela. **E o
teste rodou enquanto as duas ainda eram independentes**: as 12 combinações
bateram, e item por item em casa_condominio/venda. Extrair depois de provar
que a cópia nova concorda com a original é diferente de extrair e torcer.

**O que fica em aberto, dito:** o comando `Nay lista de ...` (o que mostra na
tela) continua lendo só a tabela, para não virar uma espera de dois minutos.
Quem confere na tela e dispara em seguida pode ver o valor mudar entre um e
outro — hoje, a favor do correto.

### 27/09/2026 — o primeiro apelido com mais de um grupo, e a trava do banco

**O pedido:** quatro grupos de maior movimento sob um nome só ("grupo lotado").

**O que eu esperava ser trabalho:** nenhum. `grupos_com_apelido` sempre
devolveu LISTA e `_postar_easy` sempre percorreu — o código já suportava N
grupos por apelido sem saber.

**O que travou:** o BANCO. `grupos_apelido_unico`, um índice único parcial
sobre `apelido`, recusou o segundo UPDATE. A garantia é boa e tem motivo — um
segundo grupo marcado 'easy' faria o comando do Easy postar nos dois sem
ninguém pedir — mas ela codifica "um apelido = um grupo", que deixou de ser
verdade.

**O que segura hoje:** o índice passou a excluir a lista de apelidos
COLETIVOS, hoje só `('lotado')`, escrita à vista no arquivo. Quem quiser o
segundo coletivo tem que passar por aquela linha e decidir de propósito, em
vez de descobrir que a trava sumiu.

**A lição:** invariante de banco é mais difícil de rever que código, porque
ninguém a lê até ela recusar um INSERT. Ao escrever uma, vale perguntar se o
"um" dela é da natureza do problema ou só do caso de hoje.

### 27/09/2026 — dois grupos com o mesmo nome, e o comando ia para o errado

**O pedido:** comandos para o "🟢 Alto Padrão - OFERTA e BUSCA 🔍", com cinco
frases de exemplo.

**O que eu medi antes de escrever qualquer coisa:** existem DOIS grupos
chamados Alto Padrão. O comando `posta no grupo alto padrão 4567`, vivo desde
25/09, ia para o outro — "IMÓVEIS ALTO PADRÃO PARA ANUNCIAR EASY". E quatro
das cinco frases dele diziam "no grupo padrão", sem o "alto", que não casava
nada e **caía no POSTAR_RE: postagem nos dezessete grupos**.

**Por que parei e perguntei:** as duas leituras eram plausíveis — ele escreveu
"alto padrão" numa frase e "padrão" em quatro — e postagem em grupo não
desfaz. Escolher sozinho aqui seria apostar com o dinheiro dele. Ele decidiu:
"alto padrão" passa a ser o OFERTA e BUSCA, e o de Anunciar Easy exige dizer
"anunciar easy".

**O cuidado que não se vê:** trocar só o apelido teria movido
`alto_padrao_publicacoes` junto — a tabela que guarda o que JÁ foi postado no
de Anunciar Easy desde 25/09 — e todo código já postado lá cairia em "já foi
postado" num grupo que nunca o recebeu. **A reserva pertence ao grupo, não ao
nome.** Cada um ficou com a sua.

**E a fonte única quase virou mentira.** `casos_alto_padrao.json` é lida pelo
Python e pelo Node do container. A coluna 2 significava "esta frase é comando
de alto padrão", e no Python isso passou a ser a UNIÃO de duas regexes em vez
de uma. O que salvou foi reler como o JS deriva a expectativa dele —
`esp && !posta` —, e ver que a coluna continuava dizendo a mesma coisa para os
dois lados. Ao mexer numa fixture compartilhada, reler o consumidor do outro
lado antes de mudar o valor.

**A lição de método, de novo:** a pergunta "quantos grupos se chamam assim?"
veio antes de "como implemento". Um `SELECT` de dez segundos evitou um comando
que postaria em dezessete grupos.

### 28/09/2026 — a resposta automática da corretora virou visita na grade

**O que o Tel viu:** "☀️ Visitas de HOJE (28/09): ⏳ 08h00 — Nancy Souza
Corretora agradece seu contato. / Atendemos de segunda a sexta das 8h às 17h
..." — e escreveu: "essa mensagem não é de visita, como pode ver é o horário
dela de atendimento".

**O que era de verdade:** o WhatsApp Business dela respondendo sozinho quando a
Nay mandou mensagem. O texto trazia, por acaso, as três coisas que o detector
procura: a palavra VISITA ("Realizamos visitas com horário marcado"), uma HORA
("das 8h") e um DIA ("de segunda a sexta"). Nenhuma das exclusões medidas em
13/09 previa este caso — elas foram tiradas de mensagens de corretor, e esta
não foi escrita por gente.

**O sinal que resolve é estrutural, não vocabular:** compromisso tem UMA hora,
horário de funcionamento tem FAIXA. É a mesma família do "faixa de preço não é
hora" que já morava em `quando_da_visita` — número com outro significado sai
antes, nunca depois. O segundo sinal é a redação de automática (atendemos,
retornaremos, agradece seu contato, mensagem automática, domingo fechado).

**Medido antes de afirmar:** 10.172 mensagens recebidas, 178 com dia e hora
entendidos (as candidatas a virar visita), e a guarda barra EXATAMENTE 3 — as
três cópias da resposta dela. Zero falso positivo no corpus inteiro.

**A guarda vem antes do cancelamento, e isso não é ordem à toa:** "Domingo
fechado" casa o `_CANCELA_RE`. Se ela entrasse depois, a mesma mensagem
APAGARIA da grade uma visita de verdade — dano maior que o de hoje.

**A lição que passa:** o corpus de onde saem as exclusões de um detector é o
que ele já viu. Texto gerado por máquina — assinatura, autoresposta, rodapé,
card colado — é outra distribuição, e vale perguntar por ela ao desenhar, não
depois de a grade amanhecer errada.

### 28/09/2026 — o código na linha matou a ambiguidade que forçava a pergunta

**O pedido era de formato:** "a Nay envia o imóvel dessa forma, porém quero com
o código também" — `✅Conquista rio negro cod 3304 / 2 quartos / ...`.

**O que o pedido de formato mexeu por baixo:** `nay_linha_da_lista` é a
IDENTIDADE que o casamento reverso regenera para entender a lista que ele cola.
E o CLAUDE.md já registrava que ela **não é injetora** — o 5719 e o 5728 eram os
dois "2 quartos sendo 1 suíte / 2.6k" e rendiam a MESMA string, e por isso a Nay
tinha de perguntar qual dos dois. Com o código dentro, a ambiguidade some da
origem: medido, **250 linhas no catálogo, 250 distintas, zero ambíguas**.

**E virou um ganho de desempenho grande, por acidente e depois de propósito.**
A primeira versão pôs o código como mais uma faixa do funil, e a suíte pesada
passou de 11 minutos para... mais. Medindo a função contra uma cópia da versão
antiga: **~2 segundos por chamada, e quase tudo era
`nay_condominios_candidatos` comparando o nome contra os 387 condomínios em
cinco faixas** — custo que já existia, e que a colagem de 24 linhas pagava 24
vezes (48 segundos só de casamento).

Com o código na linha não há nome a adivinhar. A função virou plpgsql para
poder **RETORNAR CEDO**: código que resolve pula o funil inteiro. Medido:
**8,9 ms contra ~2.000 ms**, e a suíte `teste_envio_por_descricao.sql` caiu de
11+ minutos para 25 segundos.

**A lição de método:** eu ia aceitar os 2 segundos como "assim é" porque o
teste só ficou lento DEPOIS da minha mudança — a suspeita natural era a
regressão. Reconstruir a versão antiga com outro nome e cronometrar as duas
lado a lado mostrou que a lentidão era velha, e foi isso que virou a conversa
de "desfazer o que eu fiz" para "usar o que eu fiz para consertar o que já
estava lá".

**E o risco que o próprio CLAUDE.md descreve quase me pegou:** as definições
novas foram aplicadas por um arquivo de migração, enquanto `lista_de_imoveis.sql`
e `envio_por_descricao.sql` seguiam com as antigas. Quem rodasse um daqueles no
ajuste seguinte desfaria tudo **em silêncio**. Os três arquivos agora carregam a
mesma definição.

### 28/09/2026 — a identidade do Tel estava espalhada em treze lugares

**O pedido:** "todo comando que o Tel tem, você repassa também para este número
como se fosse ele 92 98595-6408 ... nestes dois números".

**O que a busca revelou antes de escrever uma linha:** quem é o Tel estava
escrito em **treze lugares** — seis nós do n8n (cada um com sua redação:
`TESTE`, `TEL_DO_TEL`, `TEL`, e três comparações cruas), quatro pontos do
`nai_abrir_turno`, a variável `TEL_WHATSAPP`, o `TEL_FINAL` do detector de
visitas e a tabela `corretores`. Nenhum deles sabia dos outros.

**O que já existia e ninguém tinha estendido:** `nai_config.comando_telefones`
e `nai_pode_comandar()`, de 15/09, feitas para "quero que o tel e eu quando
digitar no pv dela Agenda de visitas". Valiam só para um conjunto restrito de
comandos. A estrutura estava certa; faltava largura. Medido antes de alargar:
a lista continha só o número do próprio Tel, então ninguém ganhou poder por
tabela.

**As duas armadilhas que a pressa teria criado:**

*A reserva de identidade não é a mesma coisa que a identidade.* Nos nós, o
número aparece como PERGUNTA ("é o Tel?") e como VALOR (`tel_tel` para o
banco, `phone` da cortesia). Só a pergunta vira leque. Trocar o valor mandaria
`tel_tel` errado para uma função que identifica o Tel no banco.

*O chat assumido.* O número novo precisou entrar em `escala_sem_parar` — sem
isso ele manda uma imagem, o `nai_parar_chat` marca o chat como "humano
assumiu", e os comandos dele passam a morrer em silêncio. Foi exatamente o que
aconteceu com o Tel em 25/09 e custou dois dias para achar. Aplicar a lição
antes do sintoma foi possível só porque estava escrita.

**A comparação é pelos 8 últimos dígitos, nunca pelo número inteiro** — a
Z-API entrega brasileiro ora com o 9 na frente (13 dígitos) ora sem (12). É o
mesmo critério do `nay_e_da_equipe`, de 29/08, e o teste cobre as duas formas.

**E a prova rodou contra o fluxo ANTES de importar:** os dois números
comandam, um corretor continua sem comandar, e a única falha do
`provar_nos_do_envio.js` é idêntica antes e depois do patch — ou seja,
pré-existente, não minha. Comparar o número de falhas dos dois lados é mais
barato que investigar a falha.

### 28/09/2026 — a marca que ele acabara de criar bloqueou o comando dele

**O que o Tel viu:** mandou `92 8464-8446 envia o 5739` do número da Imob Easy,
recém-promovido à voz dele, e "não foi enviado esta opção para a corretora".

**A cronologia, que é a explicação inteira:**

- 12h35 — o número da Imob Easy ganha a voz do Tel.
- 08h40:36 — esse número escreve. A Nay entende **"o Tel escreveu pelo
  celular"** e carimba o chat, para recuar por 30 minutos.
- 08h41:30 — o comando chega **desse mesmo número** e morre em "Com o Tel".

Dar a voz do Tel a um número fez a Nay tratá-lo como "o Tel assumiu este
chat" — e "o Tel assumiu" só quer dizer alguma coisa no chat de OUTRA pessoa.
No dele mesmo é uma frase sem sentido: não se toma de si próprio uma conversa.

**O veneno estava no irmão `@lid`.** Existe um `escala_sem_parar` justamente
para impedir esse carimbo, e eu tinha posto o número novo nele horas antes. Não
adiantou: a marca ficou no contato `lid:5124097359973`, irmão do número, e
aquela lista compara por **telefone** — um `@lid` nunca casa um telefone.

**A lição de onde pôr a parede:** a escrita enxerga uma face da identidade; a
LEITURA enxerga as duas, porque percorre os irmãos. Guarda de identidade que
vale por telefone é meia guarda enquanto o WhatsApp entregar `@lid`. A exceção
agora mora em `nai_tel_com_a_conversa`, que é a função que todo mundo consulta
— inclusive o `nai_deve_atender`.

**E a lição sobre o próprio conserto:** o teste falhou no caso em que a marca
está no contato do próprio Tel, e a causa era o teste — ele inseria a chave sem
normalizar, coisa que `nai_contato_de` nunca faz. Em vez de só consertar o
teste, a guarda passou a normalizar de novo (`nai_chave` é idempotente,
conferido): num portão cujo erro faz comando morrer **calado**, aceitar a linha
mal formada é mais barato que confiar em quem a escreveu.

### 28/09/2026 — um "n" a menos, e a Nay mandou o imóvel de volta para ele

**O que o Tel viu:** mandou `92 8192-5962 evia o 964` do número da Imob Easy e
recebeu **ele mesmo** o card e as 13 fotos: *"Bom dia, Imob! Claro, já te
mando!"*. A corretora não recebeu nada.

**O que era de verdade:** ele escreveu **"evia"**, sem o "n". Nenhuma das
gramáticas casou, a frase seguiu para o agente, e o agente fez o que faz com
corretor que pede imóvel — mandou o card para quem pediu. Nas mensagens de
minutos antes, `92 9321-4318 envia o 5757` e `92 9246-6604 envia o 5717`
funcionaram: o verbo estava inteiro.

**O que torna isto perigoso, e não só chato:** a falha de reconhecimento não
vira "não entendi". Vira uma CONVERSA — e conversa com o dono da empresa é a
Nay tratando-o como cliente, com card, fotos e "quer fazer uma visita?".
Errar calado seria melhor.

**A regra que ele pediu, e por que ela é segura:** "toda vez que vier mensagem
da imob easy e do Tel é um comando para enviar o imóvel e não para receber".
Só mensagem dos números DELE chega ao publicador — o nó que chama o
`POST /comando` já conferiu quem escreveu. Então "telefone na frente + um
código" não é palpite sobre um estranho: é ele dando um destino.

**As três exigências saíram de falsos positivos MEDIDOS**, não imaginados. Com
a regra ingênua, o histórico dele de 22 e 23/09 quebrava em três lugares:
`DEVOLVER (92) 99511-8525 ...` e `NAO CORRETOR (92) 98427-1973` (por isso
**começa** com o telefone), `temos uma casa de 4 mil` (por isso o código tem
**3 a 5 dígitos** — senão o "4" virava o imóvel 4), e
`92 9951-9275 posta o 5737` (por isso **outro comando fecha a porta** —
postar em grupo e mandar para uma pessoa nunca se misturam, regra de 31/08).

**A terceira eu não teria achado sozinho:** foi um teste existente que pegou,
com o comentário já escrito — *"posta vai para grupo: nunca entra pela porta
do envio privado"*. A suíte não só acusou a regressão, ela explicou por que
era uma.

**E a mudança valeu para os TRÊS nós que compartilham `EH_ENVIO_TEL`**, cada
um usando-a para uma coisa diferente: mandar ao publicador, descartar do
agente, e impedir que o texto dele vire gatilho de fotos. Era o terceiro que
teria devolvido o álbum a ele.

### 28/09/2026 — o filtro certo lendo a fonte errada

**O que ele disse:** "quando eu coloco mobiliado ou semi-mobiliado a Nay
precisa olhar no sistema para saber se está marcado na caixa esta opção para
poder enviar o correto".

**Eu tinha acabado de entregar o filtro de mobília, lendo a coluna
`imoveis.mobilia`.** Ele apontou a fonte antes de eu perceber que ela estava
errada. Medido no pedido dele: dos 20 candidatos, **seis divergiam** — todos
com a coluna VAZIA no banco e a caixa marcada no anúncio. "só semi-mobiliado"
devolvia 5 imóveis; os certos eram 9. Quatro que ele deveria receber ficavam
de fora, **calados**.

**Por que o banco atrasa, e são dois motivos somados:**
`preencher_do_anuncio` só olha imóvel de LOCAÇÃO (`valor_aluguel > 0` no
escopo padrão), então imóvel de venda nunca ganha mobília; e ele só grava onde
a coluna está VAZIA, nunca atualiza — o que veio da importação de agosto nunca
muda, mesmo que a caixa mude no admin.

**A parte do desenho que quase escapou:** não bastava conferir os candidatos
no site. Com o filtro no SQL, o candidato de coluna vazia **nunca entrava na
lista para ser conferido** — a correção teria removido falsos positivos e
deixado os falsos negativos, que eram justamente o caso dele. Então a consulta
saiu LARGA e a mobília passou a ser decidida depois, em Python, contra o site.
É o mesmo desenho do filtro de perfil, que já morava ali pelo mesmo motivo.

**E grava o que aprende**, por cima do que existia: o site é a autoridade nesse
campo. Assim a lista, o card e a próxima busca passam a ver o mesmo, e o banco
converge em vez de envelhecer.

**A lição que passa:** quando alguém aponta a FONTE de um dado e não o
resultado, é sinal de que ele conhece o sistema por fora e viu algo que o
código não conta. Medir a divergência antes de discutir o desenho transformou
"acho que está certo" em "seis de vinte".

### 28/09/2026 — o preenchedor que só preenche vazio, três vezes no mesmo dia

**Os três casos, em ordem de aparecimento:**

- **Mobília** — a coluna vinha da importação de agosto e nunca era atualizada;
  `preencher_do_anuncio` só grava onde está vazio. Seis de vinte candidatos
  divergiam do site.
- **Lances de escada** — ninguém coletava; o card salvava porque lê a página
  ao vivo, e a tabela ficou para trás.
- **Fotos** — `varrer_fotos` só visita imóvel com ZERO foto. O 964 tinha 5
  fotos velhas na tabela e 4 novas no site; numa amostra de 6, TRÊS estavam
  desatualizados.

**É o mesmo defeito escrito três vezes**, por três autores diferentes, em
momentos diferentes: `IF campo IS NULL THEN preencher`. Cada um deles resolve
o problema do primeiro dia (a coluna vazia) e cria o do segundo mês (a coluna
velha), e o segundo é pior — dado ausente se vê, dado errado não.

**A cura é sempre a mesma e cabe numa frase:** guardar QUANDO foi conferido e
percorrer por rodízio. O carimbo é o que permite reler sem martelar: cada
rodada pega os mais antigos, o catálogo converge em horas, e nenhuma hora tem
pico. Reler tudo sempre seria violar a regra 5; reler só o vazio é o que já
tínhamos.

**O detalhe que quase passou:** carimbar TAMBÉM quando nada muda. Sem isso o
rodízio volta eternamente aos mesmos e o resto nunca é visitado — o carimbo é
de "conferido", não de "alterado".

**E a parede que vale para todos:** site que devolve vazio NÃO apaga o que
temos. É a armadilha do dict truthy já registrada, e aqui o custo seria um
imóvel indo ao disparo sem foto nenhuma.

### 29/09/2026 — "tá dizendo aí só 1": a Nay contradisse o próprio card

**O que o corretor viu:** a Nay respondeu "Sim! Tem 2 vagas de garagem" e ele
rebateu — *"Esse Life tem 2 vagas? Tá dizendo aí só 1"*. O card que ele tinha
na mão dizia 1 vaga.

**Os dois estavam lendo fontes diferentes.** O CARD sai de `buscar_imovel`, que
lê a página do anúncio ao vivo, e dizia 1 — certo. A RESPOSTA sai de
`nai_resposta_da_base`, que lê a tabela, e dizia 2 — a coluna guardava 2 desde
a importação de agosto e nunca foi atualizada.

**O quarto campo com o mesmo defeito em dois dias:** mobília, lances de escada,
fotos e agora vagas. Em todos, `preencher se estiver vazio` — que resolve o
primeiro dia e apodrece no segundo mês.

**O que a medição corrigiu no meu entendimento, duas vezes:**

Primeiro medi comparando o `vagas` do banco com o `vagas` de `buscar_imovel` e
achei 2 divergências em 15. Fui olhar: `buscar_imovel` SOMA cobertas e
descobertas, e a página traz os dois campos separados. O 2973 (2 e 2) e o 2947
(3 e 1) **batiam perfeitamente** — a divergência era do meu método, não do
dado. Só o 5739 divergia de verdade.

Segundo: eu ia "consertar" a leitura do agente achando que ela subcontava as
275 linhas com vaga coberta. `nai_resposta_da_base` já trata os dois campos, e
bem — diz "tem 3 vagas, sendo 1 coberta". Mexer ali teria quebrado algo certo
para consertar algo que não estava errado.

**A lição:** quando a medição acusa uma divergência larga, desconfiar do
medidor antes de mudar o medido. As duas vezes em que quase mexi no lugar
errado foram as duas vezes em que a amostra parecia pior do que era.

**O que segura hoje:** `preencher_do_anuncio` corrige `vagas` e
`vagas_cobertas` quando a página discorda, não só quando a coluna está vazia.
A página já foi baixada -- corrigir não custa requisição nenhuma.

---

## 30/09 — Em plpgsql não existe curto-circuito

**O que parecia ser:** um alarme repetido da NAI, ruído a corrigir.

**O que era:** a agenda dela morta havia seis horas. A `nai_agenda_tick` é uma
transação só, então o erro desfazia a rodada inteira -- inclusive o carimbo que
diz que ela rodou. Nenhum lembrete, expiração ou aviso saiu. A sequência de
`nai_saida` pulou 363 ids, um por rodada perdida.

**A causa, e a lição que passa do caso:** o trigger lia `t.papel` em
`NEW.papel_destino = 'turno' AND t.papel = 'corretor'`, contando com
curto-circuito do AND. **Não existe.** E a razão é mais funda que "o Postgres
avalia tudo": o plpgsql precisa do descritor de tupla para PLANEJAR a
expressão, então o erro acontece antes de a lógica booleana rodar. Medido:
`false AND t.id IS NULL` estoura, e `true OR t.id IS NULL` também. Reordenar
operandos não salva.

**Como foi descoberto:** reproduzindo com `BEGIN; SELECT nai_agenda_tick(); ROLLBACK;`
-- o `CONTEXT` do erro entregou a cadeia inteira em quatro níveis, da linha 203
da agenda até a linha 124 do trigger.

**O corolário prático:** `record` cru só perdoa depois de atribuído. Tipo de
tabela (`v nai_visita`) e `%ROWTYPE` nascem com estrutura e devolvem NULL;
`SELECT INTO` que não acha linha ATRIBUI com tudo NULL. Então a forma segura é
o `SELECT INTO` sempre rodar, sem `IF` em volta -- e aí os `IS NULL` voltam a
significar o que quem escreveu quis dizer.

---

## 30/09 — Consertar o sintoma teria trazido a queda de volta

**O que aconteceu:** o erro apontava a linha 124. Consertar ali seria o
caminho óbvio.

**O que era:** a linha 216 tinha a MESMA forma, e nunca havia disparado só
porque a 124 estourava primeiro na mesma execução. Mais quatro ramos
('turno', 'entrega', 'corretor', 'proprietario', 'motoboy') com o mesmo defeito,
esperando um `visita_id` nulo. Seis bugs, um sintoma.

**Como foi descoberto:** listando TODOS os pontos de leitura da variável em vez
de ir à linha que o erro citou.

**A lição:** quando o erro nomeia uma linha, a pergunta não é "como conserto
esta linha" -- é "onde mais esta variável é lida, e o que garante que ali ela
existe". Consertar a linha citada é tratar o sintoma; o que fecha é a
atribuição virar incondicional.

---

## 30/09 — 306 funções sem fonte nenhuma

**O que parecia ser:** um arquivo esquecido.

**O que era:** das 309 funções `nai*` em produção, **306 não têm a definição em
nenhum `.sql` do repositório**. O sistema inteiro de atendimento de locação --
inclusive o porteiro que decide tudo que sai para o WhatsApp -- existe só no
banco. Foi por isso que o bug de hoje sobreviveu: não havia como ler, revisar,
testar nem comparar.

**Como foi descoberto:** o conserto precisou começar por
`pg_get_functiondef`, porque `grep` no projeto não achava a função.

**O que atenua:** o `pg_dump -Fc` guarda as 309, com cópia fora da VPS. Não
estão a um acidente de sumir.

**O que não atenua:** dump não se revisa, não se testa e não se compara. Código
que só existe em produção não tem quem o leia antes de quebrar.

**E a armadilha da medição:** a primeira contagem disse "309 de 309 sem fonte",
o que estava errado -- `grep -rqs -- "$f" --include='*.sql' .` faz o `--`
transformar o `--include` em nome de arquivo, e o `-s` engole o erro. Número
que confirma a hipótese com força suspeita merece uma segunda conferência.

---

## 30/09 — `name || text` trunca em 63 bytes e perde arquivo em silêncio

**O que parecia ser:** a extração das 309 funções tinha dado certo.

**O que era:** 309 escritas, **308 arquivos no disco**. Duas sobrecargas de
`nai_oferta_serve` receberam o mesmo nome e uma sobrescreveu a outra. A causa é
o tipo: `proname` é `name`, e `name || text` devolve `name`, que **trunca em 63
bytes sem avisar** -- o slug da assinatura passava disso e os dois nomes
viraram o mesmo.

**Como foi descoberto:** comparando o que foi escrito com o que existe no
diretório. O número de saída (309) batia; o do disco não.

**A lição, e é a mesma família do bug do `record` no mesmo dia:** truncagem
silenciosa e record sem estrutura são os dois o Postgres fazendo algo razoável
para o tipo e desastroso para a intenção. O remédio é o mesmo nos dois casos --
não confiar no tipo implícito: `proname::text` ali, `SELECT INTO` sempre lá.

E o que fecha de verdade: a extração ganhou uma **asserção de unicidade**.
Colisão agora falha alto em vez de perder função. Contar o que entrou e
comparar com o que saiu é mais barato que descobrir depois qual função não está
lá.

---

## 30/09 — Onde ler do banco é a quebra, não o conserto

**O que parecia ser:** dar a `buscar_imovel` um caminho pelo banco resolvia o
segundo catálogo e pronto.

**O que era:** dois trabalhos do projeto têm o site como a PRÓPRIA garantia, e
para eles o fallback é uma quebra que não avisa.

`_atualizar_valores_do_site` relê o preço no site na hora de disparar a lista,
porque o Tel muda o valor no admin e dispara em seguida. Com o fallback ela
compara o banco com o banco, nunca acha diferença, e a promessa morre calada.

`varrer_fotos.conferir` existe para dizer "as fotos do site são a verdade,
troque as nossas". Com o fallback a comparação dá sempre igual, ela carimba
`fotos_conferidas_em` e declara conferido sem ter olhado — um vigia que vira
carimbo.

**Como foi descoberto:** varrendo TODOS os chamadores de `buscar_imovel` depois
de implementar, não antes. As duas já aceitavam `buscar=`, o que mostra que
quem as escreveu previu a necessidade de trocar a fonte.

**A lição:** ao alargar uma função de leitura, a pergunta não é "quem chama" —
é "para quem a fonte ERA a garantia". Nesses casos o alargamento é silencioso
nos dois sentidos: nada falha, e o trabalho simplesmente deixa de ser feito.
`buscar_no_site` existe para quem precisa do site pedir o site pelo nome.

---

## 30/09 — O sinal que já existia e ninguém lia

**O que parecia ser:** precisava inventar uma marca para distinguir os dois
catálogos.

**O que era:** a coluna `travado` já estava lá, e o admin novo já a gravava com
o motivo escrito na linha ("mudado à mão no admin novo") — criada justamente
para que "a leitura diária do site antigo não desfaça". **Nada a lia**: nem o
Python, nem trigger. Medido: 4 linhas travadas, entre elas os dois imóveis que
a varredura ia despublicar.

**Como foi descoberto:** procurando uma marca de origem antes de criar uma. E
antes disso eu tinha lido `extras->>'origem'` achando que era a coluna
`origem` — que existe e está preenchida em todas as 5.674 linhas.

**A lição:** antes de inventar um sinal, procurar o que já foi escrito para
essa exata finalidade. Intenção morta no schema é comum em sistema que cresceu
rápido, e honrá-la é mais barato e mais fiel que criar a sua.
