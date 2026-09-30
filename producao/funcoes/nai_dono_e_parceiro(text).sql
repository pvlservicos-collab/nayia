CREATE OR REPLACE FUNCTION public.nai_dono_e_parceiro(p_nome text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT coalesce(p_nome, '') ~* '(\(|\[|-|/|\s)(parceiro|parceira|corretor|corretora|imobiliaria|imobiliária|assessoria|creci)'
      OR coalesce(p_nome, '') ~* '^(parceiro|corretor|imobiliaria|imobiliária)\M';
$function$;
