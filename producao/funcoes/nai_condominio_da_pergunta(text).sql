CREATE OR REPLACE FUNCTION public.nai_condominio_da_pergunta(p_texto text)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  SELECT c.id
    FROM crm_condominio_pelo_texto(p_texto) c
   WHERE NOT EXISTS (SELECT 1 FROM bairro_normal b
                      WHERE b.normal = nay_normalizar_lugar(nai_condominio_nucleo(c.nome), true))
     AND NOT EXISTS (SELECT 1 FROM nai_lugar_avenida a
                      WHERE nay_sem_acento(lower(a.nome)) LIKE '%' || nay_sem_acento(lower(nai_condominio_nucleo(c.nome))) || '%')
   LIMIT 1;
$function$;
