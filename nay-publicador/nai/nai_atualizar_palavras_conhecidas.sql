CREATE OR REPLACE FUNCTION public.nai_atualizar_palavras_conhecidas()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int;
BEGIN
  TRUNCATE nai_palavra_conhecida;
  INSERT INTO nai_palavra_conhecida (palavra, mensagens)
  SELECT w, count(DISTINCT id)
    FROM (SELECT m.id, regexp_split_to_table(lower(unaccent(coalesce(m.texto, ''))), '[^a-z0-9]+') AS w
            FROM mensagens m
           WHERE m.direcao = 'recebida' AND m.criada_em > now() - interval '180 days'
             AND length(coalesce(m.texto, '')) < 2000) x
   WHERE length(w) >= 3 AND w ~ '^[a-z]+$'
   GROUP BY w
  HAVING count(DISTINCT id) >= 3;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$function$
;
