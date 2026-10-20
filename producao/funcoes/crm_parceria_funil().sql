CREATE OR REPLACE FUNCTION public.crm_parceria_funil()
 RETURNS TABLE(telefone text, lid text, etapa text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH cadastro AS (
    -- 431: quem a Nay do cadastro está perguntando (ou vai perguntar), pelo contato da ficha e as linhas irmãs dele
    SELECT DISTINCT k.id AS contato_id
      FROM privado.cadastro_whats c
      JOIN nai_contato k ON k.chave = nai_chave(c.contato_tel)
     WHERE c.estado IN ('na_fila', 'perguntando') AND c.contato_tel IS NOT NULL
  ), em_cadastro AS (
    SELECT DISTINCT i.id FROM cadastro c CROSS JOIN LATERAL unnest(coalesce(nai_contato_irmaos(c.contato_id), ARRAY[c.contato_id])) AS i(id)
  ), linhas AS (
    SELECT e.contato_id,
           CASE e.etapa WHEN 'identificacao' THEN 'Identificação'
                        WHEN 'recebeu_imovel' THEN 'Recebeu imóvel'
                        WHEN 'agendamento_visita' THEN 'Agendamento de visita' END AS etapa
      FROM nai_etapa_contato e
     WHERE e.etapa IN ('identificacao', 'recebeu_imovel', 'agendamento_visita')
       AND e.contato_id NOT IN (SELECT id FROM em_cadastro)
    UNION ALL
    SELECT c.contato_id, 'Cadastrando' FROM cadastro c
  )
  SELECT (SELECT nai_fone_br(c2.telefone) FROM nai_contato c2
           WHERE c2.id = ANY (nai_contato_irmaos(l.contato_id)) AND c2.chave !~ '^lid:' AND coalesce(c2.telefone, '') <> ''
           ORDER BY c2.id LIMIT 1),
         (SELECT regexp_replace(c3.chave, '\D', '', 'g') FROM nai_contato c3
           WHERE c3.id = ANY (nai_contato_irmaos(l.contato_id)) AND c3.chave ~ '^lid:'
           ORDER BY c3.id LIMIT 1),
         l.etapa
    FROM linhas l
$function$;
