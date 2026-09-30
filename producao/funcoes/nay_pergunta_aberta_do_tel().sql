CREATE OR REPLACE FUNCTION public.nay_pergunta_aberta_do_tel()
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce((
    SELECT true FROM pergunta_ao_tel p
     WHERE p.respondida_em IS NULL
       AND p.criada_em > now() - (coalesce(
             (SELECT valor FROM config WHERE chave = 'pergunta_ao_tel_minutos'),
             '30') || ' minutes')::interval
       AND NOT EXISTS (SELECT 1 FROM pendencia_rascunho)
     LIMIT 1), false);
$function$;
