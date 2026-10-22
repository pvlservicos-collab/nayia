CREATE OR REPLACE FUNCTION public.busca_nossos_numeros()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT array_agg(DISTINCT right(d, 8)) FROM (
    SELECT unnest(ARRAY['9294453618', '9285956408', '9284560874']) AS d
    UNION ALL SELECT regexp_replace(telefone, '\D', '', 'g') FROM equipe
    UNION ALL SELECT regexp_replace(x, '\D', '', 'g')
      FROM privado.olx_config, regexp_split_to_table(valor, '[,;\s]+') x WHERE chave = 'whatsapp_nunca'
  ) n WHERE length(d) >= 8;
$function$;
