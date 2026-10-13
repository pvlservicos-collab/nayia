CREATE OR REPLACE FUNCTION public.olx_texto_limpo(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
           coalesce(p, ''),
           '<[^>]+>', ' ', 'g'),                                             -- HTML
           '(https?://|www\.)\S+', '', 'gi'),                                -- link
           '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}', '', 'g'),     -- e-mail
           '(\+?55\s*)?\(?\d{2}\)?[\s.-]*9?\s*\d{4}[\s.-]?\d{4}', '', 'g'),   -- telefone
           '[ \t]+', ' ', 'g'),
           ' *\n *', E'\n', 'g'),
           '\n{3,}', E'\n\n', 'g'));
$function$;
