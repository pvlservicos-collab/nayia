## Onde estão as visitas (leia antes de dizer que uma visita "não existe")

Em 21/10 este projeto disse ao Tel que 4 visitas e cancelamentos "não estavam em nenhum sistema". Estavam: nas
conversas da tabela `mensagens`, que não foi aberta. Visita é combinada em conversa; a agenda só tem parte delas.

1. **As conversas (a fonte principal): tabela `mensagens` do naydb.** Todo o WhatsApp da Nay Parceria: o que o
   corretor ou o proprietário escreve (`direcao = 'recebida'`) e o que sai pelo número da Nay (`'enviada'`).
   - A equipe (Tel, Rayssa) combina visita À MÃO por esse número: fala com o corretor, pergunta ao proprietário,
     confirma, cancela, remarca. Isso sai com `nome = 'Nay Mendes'`, igual à Nay. Ninguém digita na agenda depois.
   - O proprietário conversa pela mesma linha (ex.: "seu José ela cancelou").
   - Colunas: id, telefone, nome, direcao, origem (texto, audio, imagem, documento, reacao...), texto, criada_em
     (timestamptz; converta com `AT TIME ZONE 'America/Manaus'`). Áudio e imagem vêm sem texto.
   - Achar a pessoa: `telefone LIKE '%' || <8 últimos dígitos>` (o 9 da frente some: 92 9333-4125 =
     559293334125). Algumas mensagens vêm com `telefone` terminado em `@lid`: procure também pelo `nome`.
   - Achar o assunto: `texto ~* '(visit|agend|remarc|cancel|desmarc|portaria|chave|\d{1,2}h)'`.
   - `core_mensagem` NÃO serve para isso: só tem o que chegou à Nay nova, e quem está com visita aberta não chega lá.
     `integration_message_logs` é só o que o CRM disparou.
2. **A agenda (o "sistema"): tabela `nai_visita` do naydb.** Uma linha por visita: codigo, quando, estado, corretor_id
   e proprietario_id (→ `nai_contato.id`), proprietario_nome, criada_no_crm_por (quem pôs na Agenda do CRM; nulo =
   pedido da Nay, que não aparece na Agenda), motivo, resultado, excluida_em. Histórico em `nai_visita_evento`.
   - `com_rayssa` = visita entregue à equipe (aberta). `encerrada` com motivo "Fechada sozinha: o dia da visita
     passou" = ninguém registrou resultado; não quer dizer que aconteceu.
   - `nai_ref_imovel(codigo)` dá o nome do imóvel. Imóvel de locação: `imoveis.valor_aluguel`; o card que o corretor
     reenvia na conversa traz o código.
3. **Visita no sistema** = linha em `nai_visita`, não excluída, com o dia e a hora certos. Combinada na conversa e sem
   essa linha = fora do sistema: é o que a conferência procura.

### A conferência (6 vezes por dia)
Às 07, 09, 11, 13, 15 e 17 h de Manaus chega a pergunta "veja se todas as visitas estão no sistema", com o arquivo
`dados/conferencia/AAAA-MM-DD/HHMM.txt`: as visitas da agenda (de ontem até daqui a 7 dias) e as conversas de ontem e
de hoje em que se falou de visita (telefone só com os 4 últimos dígitos; o card longo da Nay vem cortado). Responda
pelo arquivo; se faltar algo (conversa mais antiga, a fala inteira), consulte `mensagens` no banco.
