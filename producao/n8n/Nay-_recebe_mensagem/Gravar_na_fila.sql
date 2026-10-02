-- Resolve o identificador ANTES de tudo: o WhatsApp entrega ora o numero,
-- ora um `@lid`, para a MESMA pessoa. Sem isso o corretor que chega por
-- @lid nao casa com `corretores`, vira desconhecido e recebe a cortesia
-- dizendo que nao e parceiro -- e ate os comandos do Tel morriam, porque
-- ele tambem aparece como @lid. Ver identidade_lid.sql.
WITH ident AS (
  SELECT nay_resolver_identidade($1, $2) AS telefone
), antes AS (
  -- So o que o CORRETOR mandou. Desde 31/08 a tabela guarda tambem o que
  -- sai, e contar isso faria o porteiro achar que quem a Nay abordou
  -- primeiro ja era conhecido -- `msgs_antes = 0` significa primeiro
  -- contato DELE, nao primeira linha na tabela.
  SELECT count(*) AS n FROM mensagens
   WHERE telefone = (SELECT telefone FROM ident) AND direcao = 'recebida'
), dbgimg AS (
  -- TEMPORARIO: so a ESTRUTURA da imagem, nunca a URL nem o conteudo.
  INSERT INTO imagem_estrutura (estrutura)
  SELECT $7 WHERE NULLIF($7,'') IS NOT NULL
  RETURNING 1
), nomeia AS (
  -- Copia o nome do WhatsApp para `corretores` a cada mensagem. O Enio
  -- recebeu dois imoveis e a confirmacao saiu como "mandei para
  -- [telefone …0556]" porque o nome estava so em `mensagens`. Nunca pisa em
  -- nome que o Tel digitou (nome_origem='manual'). Ver nome_do_whatsapp.sql.
  SELECT nay_sincronizar_nome((SELECT telefone FROM ident), $2)
), congela AS (
  -- Qualquer mensagem do corretor congela os lembretes dele NA HORA. Nao
  -- tenta entender se e resposta: silencio de verdade e ausencia de linha
  -- em `mensagens`, e se a morte dependesse da leitura o sistema cobraria
  -- justamente quem respondeu por audio ou colando card. Ver lembrete.sql.
  SELECT nay_congelar_lembretes((SELECT telefone FROM ident)) AS n
  WHERE NOT $6::boolean
), ins AS (
  -- O ID DA MENSAGEM QUE CHEGA (14/09): e ele que permite resolver quando o
  -- corretor MARCA a propria mensagem -- o card que ele colou, por exemplo.
  -- Sem isso, `nay_imovel_da_citacao` so conhecia o que NOS mandamos.
  INSERT INTO mensagens (telefone, nome, direcao, origem, texto, status, citado, citado_id, message_id)
  VALUES ((SELECT telefone FROM ident), $2,
          CASE WHEN $6::boolean THEN 'enviada' ELSE 'recebida' END, $3,
          NULLIF($4, 'null'),
          -- 'Enviado' mantem a mensagem fora do `Reservar mensagens`,
          -- que so pega 'Recebido': o fluxo para sozinho.
          CASE WHEN $6::boolean THEN 'Enviado' ELSE 'Recebido' END,
          NULLIF($5, 'null'), NULLIF($9, 'null'), NULLIF($10, 'null'))
  RETURNING id, telefone, origem, criada_em, direcao
)
SELECT ins.id, ins.telefone, ins.origem, ins.criada_em,
       EXISTS (SELECT 1 FROM corretores c
               WHERE c.telefone = ins.telefone AND c.aprovado AND c.ativo) AS aprovado,
       (SELECT n FROM antes) AS msgs_antes,
       COALESCE((SELECT valor = 'sim' FROM config
                  WHERE chave = 'atendimento_pausado'), false) AS pausado,
       -- A pergunta pede o numero do apartamento? A regra mora em
       -- unidade_nunca.sql; aqui so vem o resultado, para nao existir
       -- uma segunda copia dela em JavaScript.
       nay_pede_localizacao_da_unidade(NULLIF($4,'null')) AS pede_unidade,
       -- Os codigos que ELE escreveu, com os VALORES ja tirados: "paga
       -- ate 4000" nao e o imovel 4000. A regra mora em
       -- valor_nao_e_codigo.sql e aqui so vem o resultado.
       nay_codigos_citados(coalesce(NULLIF($4,'null'),'')) AS codigos_citados,
       -- OBRIGA os CTEs de efeito colateral a rodar. O Postgres nao
       -- executa CTE de SELECT que ninguem referencia, e por isso a
       -- sincronizacao de nome e o congelamento de lembrete NUNCA
       -- rodaram -- 967 corretores ficaram sem nome. Subconsulta
       -- escalar forca a execucao sem poder mudar o numero de linhas;
       -- por os CTEs no FROM zeraria o resultado quando um voltasse
       -- vazio, e ai TODA mensagem morreria aqui.
       (SELECT count(*) FROM nomeia) + (SELECT count(*) FROM congela)
         AS efeitos_colaterais
FROM ins
-- O ECO PARA AQUI (27/09/2026): o que a propria Nay manda fica gravado
-- acima, mas nao segue para a janela de 25s -- ali ele so segurava uma das
-- 5 vagas do n8n para, no fim, a reserva nao achar nada.
WHERE ins.direcao = 'recebida';
