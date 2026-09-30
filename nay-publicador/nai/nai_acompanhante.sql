CREATE OR REPLACE FUNCTION public.nai_acompanhante()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce(
    (SELECT split_part(btrim(e.nome), ' ', 1)
       FROM equipe e
      WHERE e.papel = 'acompanhante' AND e.ativo
      ORDER BY e.criado_em DESC LIMIT 1),
    'a nossa equipe');
$function$
;
