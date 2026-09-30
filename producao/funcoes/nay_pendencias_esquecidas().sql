CREATE OR REPLACE FUNCTION public.nay_pendencias_esquecidas()
 RETURNS TABLE(quantas integer, texto text)
 LANGUAGE sql
 STABLE
AS $function$
  WITH horas AS (
    SELECT coalesce((SELECT NULLIF(valor,'')::numeric FROM config
                      WHERE chave = 'pendencia_horas_para_cobrar'), 4) AS h
  ), atrasadas AS (
    SELECT p.id, p.codigo, p.o_que_falta, p.criada_em,
           (SELECT count(*) FROM pendencia_interessado i
             WHERE i.pendencia_id = p.id) AS esperando
      FROM pendencias p
     WHERE p.status = 'aberta'
       AND p.criada_em < now() - make_interval(hours => (SELECT h FROM horas)::int)
  )
  SELECT count(*)::int,
         'Ficaram sem resposta:' || chr(10) ||
         string_agg('• ' || a.id || ' — ' ||
                    -- O NOME do imóvel, não só o código: o Tel não decora
                    -- 1.208 números. Achado na auditoria de 01/09.
                    coalesce('imóvel ' || a.codigo ||
                             coalesce(' (' || (SELECT coalesce(NULLIF(i.condominio_nome,''), i.tipo)
                                                 FROM imoveis i WHERE i.codigo::text = a.codigo) || ')', '')
                             || ' — ', '') || a.o_que_falta ||
                    ' (há ' || floor(extract(epoch FROM now() - a.criada_em)/3600)::int || 'h' ||
                    CASE WHEN a.esperando > 1
                         THEN ', ' || a.esperando || ' corretores esperando' ELSE '' END || ')',
                    chr(10) ORDER BY a.criada_em)
         || chr(10) || 'Responda com RESPOSTA <número> <texto>.'
    FROM atrasadas a
   HAVING count(*) > 0;
$function$;
