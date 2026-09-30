CREATE OR REPLACE FUNCTION public.nay_sem_acento(txt text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT translate(
    lower(coalesce(txt, '')),
    'áàâãäéèêëíìîïóòôõöúùûüçñýÿ',
    'aaaaaeeeeiiiiooooouuuucny'
  );
$function$;
