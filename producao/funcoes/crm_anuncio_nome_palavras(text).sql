CREATE OR REPLACE FUNCTION public.crm_anuncio_nome_palavras(p text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- sem acento, sem tratamento (sr, dra, dona) e sem as palavras de duas letras
  SELECT coalesce(array_agg(t.w ORDER BY t.n), '{}')
    FROM regexp_split_to_table(nay_sem_acento(lower(coalesce(p, ''))), '[^a-z]+') WITH ORDINALITY t(w, n)
   WHERE length(t.w) >= 3
     AND t.w <> ALL (ARRAY['sra', 'dra', 'dona', 'dos', 'das', 'prop', 'proprietario', 'proprietaria',
                           'senhor', 'senhora', 'doutor', 'doutora']);
$function$;
