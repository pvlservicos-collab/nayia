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

### Como registrar (o mesmo lugar: a agenda do CRM)
Pedro, 21/10: "tudo é bom passar pelo mesmo lugar ... atualiza o que fez para não perdermos dados". Visita que só
existe na conversa vai para a agenda pelas MESMAS funções que a tela do CRM usa; nunca INSERT/UPDATE direto em
`nai_visita`. Na vps1, como o usuário nay:
`ssh -i /root/.ssh/agente_claude_vps1 root@100.86.114.74 "docker exec -i nay-postgres psql -U nay -d naydb -X -A"`
e mande o SELECT pela entrada. Quem = `'Agente Visitas'`. Hora sempre com o fuso de Manaus (`'2026-10-21 13:00-04'`).
- **Faltou na agenda:** `SELECT * FROM crm_visita_agendar(<código>, '<telefone do corretor, só dígitos>', '<nome>',
  '<AAAA-MM-DD HH:MI-04>', 60, 'Agente Visitas');`. Se a Nay já tinha um pedido daquele corretor + imóvel, a função
  assume a mesma linha (não duplica). Nasce `com_rayssa` e não manda nada a ninguém. Efeito: o corretor vai para a etapa
  Visitas do CRM e a Nay fica calada com ele até 2 h depois do horário (é o mesmo de quando a Rayssa agenda).
- **Cancelada:** `SELECT * FROM crm_visita_excluir(<id>, 'Agente Visitas: <quem cancelou, quando>');`. Ninguém é avisado.
- **Remarcada (dia e hora já fechados):** `SELECT * FROM crm_visita_mudar_horario(<id>, '<AAAA-MM-DD HH:MI-04>',
  'Agente Visitas');`. Só aceita horário futuro. Remarcação sem hora fechada = pendência, não mexa.
- **NÃO use** `crm_visita_realizada`: ela manda ao corretor "como foi a visita?" pelo WhatsApp. Visita que aconteceu
  fica para a equipe marcar; você só diz qual foi.
- Só registre o que a conversa prova (a equipe confirmou o horário, o corretor ou o dono cancelou). Dúvida = liste, não
  registre. Imóvel: pelo código do card na conversa (`Código: 5731`); sem código, procure em `imoveis` e diga como achou.
- Toda função devolve `ok` e `mensagem`: copie a mensagem no relato. Desfazer: agendada por engano =
  `crm_visita_excluir`; excluída por engano = agendar de novo; horário = mudar de volta.

### A conferência (6 vezes por dia)
Às 07, 09, 11, 13, 15 e 17 h de Manaus chega a pergunta "veja se todas as visitas estão no sistema", com o arquivo
`dados/conferencia/AAAA-MM-DD/HHMM.txt`: as visitas da agenda (de ontem até daqui a 7 dias) e as conversas de ontem e
de hoje em que se falou de visita (telefone só com os 4 últimos dígitos; o card longo da Nay vem cortado). Compare,
registre como acima e relate. Para o telefone inteiro do corretor, a conversa mais antiga ou a fala inteira, consulte
`mensagens` / `nai_contato` no banco.

### O card padrão da visita (464, 22/10)
Pedro: "quero que elas sejam organizadas em um card padrão a partir de agora no bd, que facilite o agente visitas a ler".
- `SELECT visita_card(<id>)`: um JSON com tudo da visita (dia e hora, imóvel com condomínio e código, corretor, cliente,
  proprietário, motoboy, de onde veio, estado) e `texto`, o card pronto. O CHECKLIST vem nele:
  - ✅/❌ Proprietário: saiu mensagem nossa (da Nay ou da equipe) para o telefone do dono desde a criação da visita;
    "(respondeu)" quando ele escreveu depois.
  - ✅/❌ Motoboy: saiu mensagem para o acompanhante que cita o código, o condomínio ou o dia DESTA visita.
- `SELECT visitas_cards(<de>, <até>)`: os cards das visitas abertas no intervalo (ex.: `now()`, `now() + interval '2 days'`).
- Toda visita nova (da agenda do CRM ou que a Nay passou à equipe) chega aqui com o card. Confira o checklist.

### O lembrete de 1 hora antes, no grupo
Pedro: "no dia da visita 1 hora antes ele vai lembrar a gente no grupo". A rotina manda o card aqui uma hora antes (entre
45 e 65 min). Mande o lembrete no grupo **Altarquia Imobeasy** (o grupo da equipe onde já sai o checklist da visita), na
vps1, como o projeto Nay faz:
- o id do grupo (uma vez; guarde em ./dados/grupo_altarquia.txt):
  `scp -q -i /root/.ssh/agente_claude_vps1 /opt/agente-claude/projetos/nay/dados/achar_grupo.py root@100.86.114.74:/docker/nay-core/scripts/achar_grupo.py && ssh -i /root/.ssh/agente_claude_vps1 root@100.86.114.74 'cd /docker/nay-core && docker compose run --rm --no-deps -v /docker/nay-core/scripts/achar_grupo.py:/app/scripts/achar_grupo.py:ro nay-core python scripts/achar_grupo.py Altarquia'`
- o envio (o texto vai por arquivo, como o projeto Nay faz): grave o texto em /tmp/lembrete.txt e rode
  `scp -q -i /root/.ssh/agente_claude_vps1 /tmp/lembrete.txt root@100.86.114.74:/docker/nay-core/relatorios/lembrete.txt && ssh -i /root/.ssh/agente_claude_vps1 root@100.86.114.74 'cd /docker/nay-core && docker compose run --rm --no-deps -v /docker/nay-core/scripts/mandar.py:/app/scripts/mandar.py:ro -v /docker/nay-core/relatorios:/app/relatorios:ro nay-core python scripts/mandar.py --grupo <id> --arquivo --texto relatorios/lembrete.txt --confirmar'`
O lembrete leva o card; se houver ❌, diga o que falta (falar com o proprietário, avisar o motoboy) e quem resolve.
Nada de mandar mensagem a corretor, cliente ou proprietário por conta própria: o lembrete é para a equipe, no grupo.
