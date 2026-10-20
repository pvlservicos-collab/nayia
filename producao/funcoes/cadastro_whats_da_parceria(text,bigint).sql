CREATE OR REPLACE FUNCTION public.cadastro_whats_da_parceria(p_tel text, p_contato bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT c.id FROM privado.cadastro_whats c
   WHERE c.estado = 'perguntando' AND c.contato_tel IS NOT NULL
     AND (nai_chave(c.contato_tel) = nai_chave(p_tel)
          OR nai_chave(c.contato_tel) IN (SELECT nai_chave(k.telefone) FROM nai_contato k
                                           WHERE k.id = ANY (coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]))))
   ORDER BY c.pergunta_em DESC NULLS LAST, c.id DESC
   LIMIT 1
$function$;
