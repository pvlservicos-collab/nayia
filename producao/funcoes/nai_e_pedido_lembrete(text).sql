CREATE OR REPLACE FUNCTION public.nai_e_pedido_lembrete(p text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT lower(unaccent(btrim(coalesce(p, '')))) ~
         ('^(@?nay[\s,:;.!-]*)?((me|nos)\s+(lembr\w*|avis\w*)\M|lembr\w*-me\M|(agenda\s+(um\s+)?|cria\s+(um\s+)?)?lembrete\M'
          || '|meus\s+lembretes\M|cancel\w*\s+(o\s+)?lembrete\M)');
$function$;
