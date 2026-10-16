CREATE OR REPLACE FUNCTION public.pergunta_fila_posicao(OUT k integer, OUT n integer)
 RETURNS record
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  WITH r AS (SELECT coalesce(nullif(nai_cfg('_pergunta_fila_rodada', ''), '')::timestamptz, '-infinity'::timestamptz) AS ini),
       feitas AS (SELECT count(*) AS c FROM pergunta_fila f, r
                   WHERE f.estado IN ('respondida', 'descartada') AND f.respondida_em >= r.ini),
       abertas AS (SELECT count(*) AS c FROM pergunta_fila WHERE estado IN ('fila', 'perguntada'))
  SELECT (feitas.c + 1)::int, greatest(feitas.c + abertas.c, feitas.c + 1)::int FROM feitas, abertas
$function$;
