CREATE OR REPLACE FUNCTION public.site_painel_internos()
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- os 8 últimos dígitos de quem é DE CASA: as três linhas, a equipe, o Tel e os números de teste
  SELECT coalesce(array_agg(DISTINCT x ORDER BY x) FILTER (WHERE length(x) = 8), '{}')
    FROM (SELECT right(regexp_replace(coalesce(t, ''), '\D', '', 'g'), 8) AS x
            FROM (SELECT unnest(ARRAY['94453618', '85956408', '84560874']) AS t   -- Parceria, Captação, Oficial
                  UNION ALL SELECT telefone FROM equipe
                  UNION ALL SELECT unnest(string_to_array(valor, ',')) FROM nai_config
                             WHERE chave IN ('tel_telefone', 'numeros_teste', 'comando_telefones')
                  UNION ALL SELECT unnest(string_to_array(valor, ',')) FROM captacao_config
                             WHERE chave IN ('telefone_teste', 'python_telefones')
                  UNION ALL SELECT unnest(string_to_array(valor, ',')) FROM privado.olx_config
                             WHERE chave = 'whatsapp_teste') a) b;
$function$;
