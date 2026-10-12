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
    FROM privado.falou_conosco_crm f WHERE f.ultima_em > now() - interval '120 days' GROUP BY 1;
  DELETE FROM privado.falou_conosco;
  INSERT INTO privado.falou_conosco (chave, ultima_em, origens)
  SELECT chave, max(ultima_em), array_agg(DISTINCT origem ORDER BY origem) FROM _falou
   WHERE coalesce(chave, '') <> '' GROUP BY chave;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $function$;
