CREATE OR REPLACE FUNCTION public.nai_negocio_do_que_recebeu(p_contato bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- O que ela já mandou para ele nos últimos 3 dias (card ou foto). Se tudo
  -- é de uma finalidade só, a conversa é dessa finalidade. Misturado: NULL.
  WITH cods AS (
    SELECT DISTINCT coalesce(s.codigo, (regexp_match(s.texto, 'C[óo]digo:\s*(\d{3,5})', 'i'))[1]::int) AS c
      FROM nai_saida s
     WHERE s.contato_id = ANY (nai_contato_irmaos(p_contato))
       AND s.estado = 'enviado' AND s.criado_em > now() - interval '3 days'
       AND (s.codigo IS NOT NULL OR (s.tipo = 'texto' AND position('📍' IN coalesce(s.texto, '')) > 0))
  ), f AS (SELECT nai_finalidade_do_imovel(c) AS fin FROM cods WHERE c IS NOT NULL)
  SELECT CASE WHEN count(*) FILTER (WHERE fin = 'locacao') > 0 AND count(*) FILTER (WHERE fin = 'venda') = 0 THEN 'locacao'
              WHEN count(*) FILTER (WHERE fin = 'venda') > 0 AND count(*) FILTER (WHERE fin = 'locacao') = 0 THEN 'venda' END
    FROM f;
$function$
;
