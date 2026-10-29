CREATE OR REPLACE FUNCTION public.crm_notas_da_nay(p_dias integer DEFAULT 3)
 RETURNS TABLE(id bigint, fonte text, titulo text, texto text, telefone text, criado_em timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT a.id, a.fonte, a.titulo, a.texto, a.telefone, a.criado_em
    FROM privado.aviso_equipe a
   WHERE a.tipo = 'nota' AND a.telefone IS NOT NULL
     AND a.criado_em > now() - make_interval(days => greatest(1, least(coalesce(p_dias, 3), 30)))
   ORDER BY a.id
   LIMIT 500
$function$;
