CREATE OR REPLACE FUNCTION public.nay_pode_falar(p_telefone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT NOT EXISTS (
    SELECT 1 FROM contato_corretor c
     WHERE c.telefone = p_telefone
       AND c.quando >= date_trunc('day', now() AT TIME ZONE 'America/Manaus')
                        AT TIME ZONE 'America/Manaus'
  );
$function$;
