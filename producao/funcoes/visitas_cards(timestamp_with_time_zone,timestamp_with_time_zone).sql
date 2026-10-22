CREATE OR REPLACE FUNCTION public.visitas_cards(p_de timestamp with time zone, p_ate timestamp with time zone)
 RETURNS SETOF jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT visita_card(v.id) FROM nai_visita v
   WHERE v.excluida_em IS NULL AND v.estado NOT IN ('cancelada', 'expirada')
     AND v.quando >= p_de AND v.quando < p_ate
   ORDER BY v.quando, v.id
$function$;
