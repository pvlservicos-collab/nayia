CREATE OR REPLACE FUNCTION public.nay_captacao_do_link(p_link text)
 RETURNS SETOF captacoes
 LANGUAGE sql
 STABLE
AS $function$
  SELECT c.* FROM captacoes c
   WHERE nay_chave_do_link(p_link) IS NOT NULL
     AND nay_chave_do_link(c.link_olx) = nay_chave_do_link(p_link)
   -- O índice único já garante uma só. O ORDER BY + LIMIT é para o dia em que
   -- alguém dropar o índice: aí a mais antiga é a canônica, e a resposta
   -- continua sendo UMA, não uma sorteada.
   ORDER BY c.id
   LIMIT 1;
$function$;
