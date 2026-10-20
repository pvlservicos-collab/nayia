# Contexto: correção da Nay Mendes (Nay Parceria)

Este arquivo resume uma conversa de análise feita em outro chat. Leia tudo antes de agir.

## Quem sou e o que é a Nay

- Sou o Tel, dono da Imob Easy (T A Sobreira Imobiliária, CRECI PJ 482), em Manaus/AM. Hoje estou em São Paulo e me mudo para Manaus em 27/10/2026.
- A Imob Easy capta imóveis direto com proprietários e repassa para cerca de 200 corretores parceiros por grupos de WhatsApp.
- A **Nay Mendes** é a IA que atende esses corretores no WhatsApp ("Nay Parceria"). O código é a "Nay nova", chamada **nay-core**, em Python, rodando numa VPS da Hostinger.
- Equipe: Pedro (automações e CRM), Rayssa (atendimento, visitas e fechamento), motoboy (acompanha visitas).
- Meta da empresa: lucrar R$ 200 mil em contratos assinados até 27/12/2026. A Nay importa porque cada conversa travada pode ser um cliente de corretor que vai para outro imóvel.

## Como eu quero que você trabalhe

- Sou leigo em programação. Explique em linguagem simples e defina termos técnicos antes de usar.
- Passo a passo sempre completo, tudo de uma vez.
- Nunca afirme algo técnico sem conferir no código ou no servidor. Se não souber, diga que não sabe.
- Separe FATO (o que você viu no código ou nos dados) de HIPÓTESE (o que você deduziu).
- Não use travessão nos textos.

## Regras de segurança (obrigatórias)

1. **A Nay está atendendo corretores agora.** Qualquer erro seu derruba o atendimento.
2. **Etapa 1 é somente leitura**: não edite, não apague, não reinicie, não instale nada sem eu autorizar.
3. **Antes de qualquer correção**: faça uma cópia completa da pasta do nay-core com a data no nome, me diga onde ficou e como voltar para ela. O backup da Hostinger é só semanal.
4. Aplique uma correção de cada vez e me mostre o que mudou antes de reiniciar a Nay.
5. Se algum comando pedir senha, pare e me avise. Não peça e não use a senha root.
6. Nunca exponha telefone completo de corretor: use só os 4 últimos dígitos.

## Servidores (sem senhas aqui, de propósito)

- VPS 1: srv1877774.hstgr.cloud, IP 179.197.239.148, usuário root. A chave SSH do meu Mac (telmarioaraujo@Mac) está cadastrada nela.
- VPS 2: srv1894338.hstgr.cloud, IP 179.198.121.171, usuário root, KVM 2, com um contêiner de Postgres.
- Não sei com certeza em qual das duas está o nay-core. Descubra antes de qualquer coisa.

## O que já foi analisado

Existe um relatório chamado **"Roteiro da Nay Parceria"**, gerado a partir do código do nay-core e dos 1.092 turnos reais de 13/10 18h a 20/10 18h (Manaus). Os números abaixo são desse relatório. Os marcados com "~" foram contados à mão e são aproximados.

### Placar da semana (13/10 a 20/10)

| Item | Número | % |
|---|---|---|
| Conversas | 151 | 100% |
| Conversas escaladas para o Tel | 42 | 27,8% |
| Escaladas sem motivo forte | 31 de 51 | 60,8% das escaladas |
| Avisos "vou precisar confirmar" ao Tel | 141 | cerca de 20 por dia |
| Conversas sem nenhum erro | desconhecido | o relatório não informa |

### Erros por ordem de custo para o negócio

1. **Escalada indevida que cala o corretor por até 24 h.** 13 escaladas eram respostas curtas ("Cod 9045", "Sim", "Aluguel") e 18 eram frustração ou pedido de ligação ("Posso ligar?", "que robô chato").
2. **Visita com dado errado (~6).** Horário 10h inventado (…9502), "hoje às 18h" virou sábado (…5070), confirmou o imóvel 4239 quando era o 3078 (…5962), "cancela essa visita" recebeu a confirmação de novo (…5959).
3. **Informação errada de valor.** Mont Clair: disse que o condomínio estava incluído, mas o card mostrava "R$ 3.700/mês + condomínio R$ 1.000" (…8609).
4. **Busca errada.** Card de R$ 2,95 milhões para aluguel até R$ 2.800 (…7527); "450 500 3qts" lido como códigos 450 e 500 (…8525); lista vazia repetida 6 vezes sem perguntar valor nem região (…1282); vários clientes misturados numa ficha (…5642, …5962, …5337). FATO do relatório: o código usa faixa de 25% abaixo, mas a regra do Pedro (30/09) é 20% abaixo e 10% acima.
5. **Campo andar vazio no cadastro.** 30 dos 67 "vou precisar confirmar" eram sobre andar. Isso é dado faltando, não código.

Ficam para depois: "Combinado, fico no aguardo" em cima de pergunta (15 casos), "já te mandei, quer de novo?" para quem pediu (25), "Qual deles?" repetido (38), textos com cara de robô ("vaga(s)", "0 m²", "nenhum casa").

### Conflito de regra identificado

A regra "pergunta sai uma vez só; se não respondeu, vira tanto faz" é a origem do laço de lista vazia: valor e região viram "tanto faz", a ficha fica "completa" sem dado e a busca dá vazio. A correção 3 abaixo muda essa regra.

## Etapa 1: somente leitura (fazer primeiro)

1. Descubra em qual VPS e em qual pasta está o nay-core.
2. Me explique em linguagem simples: como a Nay roda (serviço, docker, outro), onde ficam as conversas salvas, e onde fica a regra de faixa de valor de 25%.
3. Exporte as conversas da Nay Parceria de 20/10 num arquivo .txt (se estiver rodando no meu Mac, salve na pasta Downloads; se estiver rodando na VPS, mostre na tela em partes para eu copiar), com:
   - telefone só com os 4 últimos dígitos
   - todos os turnos com horário, quem falou e o texto, incluindo cards e quantas fotos foram
   - no fim de cada conversa: RESULTADO visita marcada (sim/não), escalada (sim/não, motivo), corretor sumiu (sim/não)
   - no topo: total de conversas, visitas marcadas pela Nay, total de escaladas
   - **não classifique erros, só exporte** (a análise será feita em outro chat, com olho de fora)

## Etapa 2: correções (só depois que eu autorizar)

Antes de mudar, faça a cópia de segurança e me diga quais regras atuais cada mudança altera.

### Bloco A (prioridade)

**1. Escalada**
- Se no turno anterior a Nay fez uma pergunta, e a resposta do corretor tem até 4 palavras, ou é um número de 3 a 5 dígitos, ou é "sim", "não", "aluguel", "locação", "venda", "compra", trate como resposta e siga o atendimento. Nunca escale esses casos.
- Irritação ("que robô chato", "não é isso", "já falei"): não escale. Responda em uma frase corrigindo a última resposta. Exemplo: pediu mais fotos e todas já foram, responda "Essas são todas as fotos que eu tenho desse imóvel."
- Continue escalando: negociação, proposta, conta de entrada, documentos, contrato, resultado de visita, corretor oferecendo imóvel, pedido explícito para falar com uma pessoa.
- Gere um relatório diário de escaladas: telefone (4 últimos dígitos), texto que causou, motivo.
- Conflito: restringe a regra atual "escala quando não entendeu duas vezes seguidas".

**2. Visita**
- Nunca preencha dia ou hora que o corretor não escreveu. Se faltar, pergunte só o que falta.
- Passe em todo turno a data e hora atual de Manaus (fuso America/Manaus) e resolva "hoje", "amanhã" e dia da semana a partir dela.
- Na confirmação, mostre a data com dia da semana. Exemplo: "📅 Data: terça, 21/10".
- O imóvel da visita é o último que o corretor citou ou escolheu. Se citou mais de um nos últimos turnos, pergunte qual.
- "cancela", "desmarca", "não vai dar", "remarcar": nunca reenvie a confirmação. Cancele, responda "Combinado, vou cancelar a visita de [dia]." e avise Rayssa e Tel.
- Conflito: muda o modelo fixo da confirmação de visita (entra o dia da semana).

**3. Busca**
- Faixa de valor: 20% abaixo e 10% acima do valor dito (regra do Pedro de 30/09).
- Um número só é código se existir no catálogo. Se não existir, nunca trate como código. Se existir e puder ser valor, pergunte: "Você quer o imóvel de código 450 ou imóveis até R$ 450 mil?"
- Finalidade é filtro obrigatório: ficha de locação nunca retorna imóvel só de venda. Antes de enviar um card, confira se valor e finalidade batem com a ficha. Se não baterem, não envie.
- Finalidade, valor e região nunca viram "tanto faz". Só tipo e mobília podem.
- "Na região que você pediu" só sai se a ficha tiver região. Lista vazia sai uma vez por busca; se a próxima também der vazio, diga de outro jeito, avise o Tel como demanda não atendida e pare.
- Concordância: "nenhuma casa", "nenhum apartamento".
- Conflito: muda a regra atual "pergunta sai uma vez só".

### Bloco B (depois de 2 dias de teste do Bloco A)

**4. Taxa de condomínio e dados da ficha**
- Condomínio incluso: responda só pelo campo estruturado da taxa. Se o card mostra "+ condomínio", a resposta é "Não está incluso. O condomínio é R$ X à parte."
- Campo vazio ou zero (área, andar, vagas): não cite; trate como "não sei".
- Plural certo: "1 vaga", "2 vagas", "3 quartos, sendo 2 suítes". Nunca "vaga(s)".

**5. Recado**
- Antes de responder "Combinado, fico no aguardo", confira se a mensagem tem pergunta ("qual", "quanto", "quando", "onde", "tem", "pode", "como", "?") ou pedido de informação. Se tiver, responda a pergunta.

**6. Reenvio**
- Pedido explícito ("manda de novo", "reenvia", "manda as fotos", "fotos"): reenvie direto, sem perguntar.
- Pediu mais fotos e todas já foram: responda "Essas são todas as fotos que eu tenho desse imóvel." e não reenvie.

## Decisões ainda abertas (são minhas, não implemente sem eu confirmar)

1. **Silêncio de escalada**: hoje a conversa fica com o Tel até ele mandar DEVOLVER ou por 24 h. Proposta: se o Tel não responder em 60 min no horário comercial, a Nay volta a atender busca, fotos e disponibilidade, e deixa com ele só o assunto escalado.
2. **Quem recebe a escalada**: proposta de mandar "posso ligar?", dúvida de ficha e documentos para a Rayssa, e para o Tel só negociação e proposta. A Nay continua dizendo "Já te respondo por aqui" para o corretor.

## Pendências fora do código

- Trocar a senha root da VPS 2 (foi exposta em texto num chat).
- Conferir a data de validade 10/09/2026 que aparece na VPS 2 (renovação automática está ativa, mas a data já passou).
- Rayssa preencher o campo andar (baixo, médio, alto ou lances de escada) dos 67 imóveis que saíram em card na semana.
