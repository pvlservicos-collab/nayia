-- A NAI grava na MESMA tabela `mensagens` (a historia do corretor continua
-- uma so), marcando fluxo='nai'. O telefone e gravado COMO CHEGOU: o @lid
-- NAO e trocado por um telefone adivinhado pelo nome.
WITH ins AS (
  -- O ID DA MENSAGEM QUE CHEGA (14/09): e ele que faz a MARCACAO resolver
  -- quando o corretor marca a propria mensagem (o card que ele colou). O fluxo
  -- antigo ja guardava; este, que atende o numero em teste, nao guardava -- e
  -- foi por isso que "marquei o imovel e ela nao identificou" continuou
  -- acontecendo depois do conserto do dia 14.
  INSERT INTO mensagens (telefone, nome, direcao, origem, texto, status, citado, citado_id, fluxo, message_id, midia_url)
  VALUES ($1, $2, CASE WHEN $6::boolean THEN 'enviada' ELSE 'recebida' END, $3,
          NULLIF($4, 'null'), CASE WHEN $6::boolean THEN 'Enviado' ELSE 'Recebido' END,
          NULLIF($5, 'null'), NULLIF($7, 'null'), 'nai', NULLIF($8, 'null'), NULLIF($9, 'null'))
  RETURNING id, telefone, origem, criada_em, direcao
), nomeia AS (
  SELECT nay_sincronizar_nome((SELECT telefone FROM ins), $2)
), congela AS (
  SELECT nay_congelar_lembretes((SELECT telefone FROM ins)) AS n WHERE NOT $6::boolean
)
SELECT ins.id, ins.telefone, ins.origem, ins.criada_em, ins.direcao,
       -- quanto esperar antes de responder, para juntar as mensagens que ele
       -- ainda esta digitando (Tel, 15/09). Muda por UPDATE, sem deploy.
       -- POR PESSOA desde 28/09 (147): 20 s para todo mundo, os testes
       -- internos a parte -- a mesma conta da trava da rajada no banco.
       nai_janela_segundos(ins.telefone) AS janela,
       (SELECT count(*) FROM nomeia) + (SELECT count(*) FROM congela) AS efeitos_colaterais
FROM ins
-- O ECO PARA AQUI (27/09/2026): gravado acima, mas sem ocupar vaga do n8n
-- na janela -- a reserva so pega 'Recebido', entao ele nunca tinha o que
-- fazer la. O ramo "Foi o Tel pelo celular?" e outro e continua igual.
WHERE ins.direcao = 'recebida';
