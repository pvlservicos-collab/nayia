CREATE OR REPLACE FUNCTION public.crm_imoveis_nomes(p_codigos integer[])
 RETURNS TABLE(codigo integer, nome text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT i.codigo,
         coalesce(nullif(btrim(CASE WHEN i.condominio_nome ~* 'n[aã]o identificad' OR i.condominio_nome ~ '^[—–-]+$' THEN ''
                                    ELSE i.condominio_nome END), ''),
                  nullif(btrim(concat_ws(' ', i.tipo, i.bairro)), ''))
    FROM imoveis i
   WHERE i.codigo = ANY (coalesce(p_codigos, '{}'))
   LIMIT 500;
$function$;
