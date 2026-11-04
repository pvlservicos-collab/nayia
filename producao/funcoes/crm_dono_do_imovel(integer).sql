CREATE OR REPLACE FUNCTION public.crm_dono_do_imovel(p_codigo integer)
 RETURNS TABLE(codigo integer, imovel text, status text, e_parceiro boolean, nome text, telefone text, motivo text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT i.codigo,
         nullif(btrim(concat_ws(' · ', nullif(btrim(i.tipo), ''), coalesce(nullif(btrim(i.condominio_nome), ''), nullif(btrim(i.bairro), '')))), ''),
         i.status, coalesce(i.e_parceiro, false), d.nome, d.telefone, d.motivo
    FROM imoveis i
    LEFT JOIN LATERAL (SELECT * FROM nai_proprietario_do_imovel(i.codigo) LIMIT 1) d ON true
   WHERE i.codigo = p_codigo;
$function$;
