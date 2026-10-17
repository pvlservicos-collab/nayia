-- 401: a regra dos 60 dias das listas do disparo conta também quem NÓS contatamos
--
-- Pedro, 17/10/2026: "vê lá as listas da aba de mensagens para ver se está correto, se ainda faltam esses contatos mesmo,
-- revisando para remover todos que entramos em contato nos últimos 60 dias".
-- Medido antes: privado.falou_conosco (352) só juntava quem ESCREVEU para nós (mensagens recebidas, turnos da Nay, CRM
-- inbound, corretores.ultima_interacao). Nos últimos 60 dias contatamos 1.099 pessoas (mensagem, disparo, imóvel enviado)
-- e 447 delas não estavam lá: continuavam "para falar" nas listas e podiam receber disparo.
-- Agora entram também, por QUALQUER número: o que saiu pela Parceria (mensagens), pela captação e pela oficial
-- (captacao_mensagens, inclusive disparo; falhou/não entregue não conta), as saídas da Nay velha e da nova
-- (nai_saida, core_saida) e o envio de imóvel a pessoa (envios fora dos grupos). O que saiu pelo CRM já aparece nessas
-- tabelas (só 2 de 873 contatos de 60 dias não apareciam): o cron do CRM continua como está.
-- Vale para a tela das listas (site_publicos_disparo) e para o disparo automático (captacao_py_fila_do_disparo ->
-- nay_falou_conosco), que leem esta tabela. O nome da tabela fica; as origens novas terminam em "_saida".
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.nay_falou_conosco_atualizar()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int;
BEGIN
  DROP TABLE IF EXISTS _falou;   -- a função pode rodar duas vezes na mesma transação (o ensaio roda)
  CREATE TEMP TABLE _falou (chave text, ultima_em timestamptz, origem text) ON COMMIT DROP;
  INSERT INTO _falou
  SELECT nay_fone_chave(nay_fone_com_ddi(m.telefone)), max(m.criada_em), 'parceria'
    FROM mensagens m WHERE m.direcao = 'recebida' AND m.criada_em > now() - interval '120 days' GROUP BY 1
  UNION ALL
  SELECT nay_fone_chave(nay_fone_com_ddi(m.telefone)), max(m.criada_em), 'captacao'
    FROM captacao_mensagens m WHERE m.direcao = 'recebida' AND m.criada_em > now() - interval '120 days' GROUP BY 1
  UNION ALL
  SELECT nay_fone_chave(nay_fone_com_ddi(c.chave)), max(t.criado_em), 'nay'
    FROM nai_turno t JOIN nai_contato c ON c.id = t.contato_id
   WHERE t.criado_em > now() - interval '120 days' AND c.chave !~ '@' GROUP BY 1
  UNION ALL
  SELECT nay_fone_chave(nay_fone_com_ddi(c.telefone)), max(c.ultima_interacao), 'corretores'
    FROM corretores c WHERE c.ultima_interacao > now() - interval '120 days' AND coalesce(c.telefone, '') <> '' GROUP BY 1
  UNION ALL
  SELECT nay_fone_chave(nay_fone_com_ddi(f.telefone)), max(f.ultima_em), 'crm'
    FROM privado.falou_conosco_crm f WHERE f.ultima_em > now() - interval '120 days' GROUP BY 1
  -- 401: o que NÓS mandamos, por qualquer número
  UNION ALL
  SELECT nay_fone_chave(nay_fone_com_ddi(regexp_replace(m.telefone, '\D', '', 'g'))), max(m.criada_em), 'parceria_saida'
    FROM mensagens m
   WHERE m.direcao = 'enviada' AND m.criada_em > now() - interval '120 days' AND coalesce(m.telefone, '') !~ '@' GROUP BY 1
  UNION ALL
  SELECT nay_fone_chave(nay_fone_com_ddi(regexp_replace(m.telefone, '\D', '', 'g'))), max(m.criada_em), 'captacao_saida'
    FROM captacao_mensagens m
   WHERE m.direcao = 'enviada' AND m.criada_em > now() - interval '120 days'
     AND coalesce(m.status, '') !~* '^(falhou|nao entregue|não entregue)' GROUP BY 1
  UNION ALL
  SELECT nay_fone_chave(nay_fone_com_ddi(s.chave_destino)), max(s.enviado_em), 'nay_saida'
    FROM nai_saida s
   WHERE s.estado = 'enviado' AND s.enviado_em > now() - interval '120 days' AND s.chave_destino !~ '(lid|@)' GROUP BY 1
  UNION ALL
  SELECT nay_fone_chave(nay_fone_com_ddi(s.chave_destino)), max(s.enviado_em), 'core_saida'
    FROM core_saida s
   WHERE s.estado = 'enviado' AND s.enviado_em > now() - interval '120 days' AND s.chave_destino !~ '(lid|@)' GROUP BY 1
  UNION ALL
  SELECT nay_fone_chave(nay_fone_com_ddi(regexp_replace(e.telefone, '\D', '', 'g'))), max(e.enviado_em), 'envio_saida'
    FROM envios e
   WHERE e.destino <> 'grupo' AND e.enviado_em > now() - interval '120 days' AND coalesce(e.telefone, '') <> '' GROUP BY 1;
  DELETE FROM privado.falou_conosco;
  INSERT INTO privado.falou_conosco (chave, ultima_em, origens)
  SELECT chave, max(ultima_em), array_agg(DISTINCT origem ORDER BY origem) FROM _falou
   WHERE coalesce(chave, '') <> '' GROUP BY chave;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $function$;

-- a tabela já sai certa agora (o cron refaz de 10 em 10 min)
SELECT nay_falou_conosco_atualizar();
COMMIT;
