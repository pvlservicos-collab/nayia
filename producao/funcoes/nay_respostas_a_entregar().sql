CREATE OR REPLACE FUNCTION public.nay_respostas_a_entregar()
 RETURNS TABLE(telefone text, ids bigint[], texto text)
 LANGUAGE sql
 STABLE
AS $function$
  WITH ok AS (
    SELECT NOT COALESCE((SELECT valor = 'sim' FROM config
                          WHERE chave = 'atendimento_pausado'), true) AS pode
  )
  SELECT r.telefone,
         array_agg(r.id ORDER BY r.criado_em),
         string_agg(r.texto, chr(10) ORDER BY r.criado_em)
    FROM resposta_a_entregar r
   WHERE r.estado = 'devendo'
     AND (SELECT pode FROM ok)
     AND nay_pode_falar(r.telefone)
   GROUP BY r.telefone;
$function$;
