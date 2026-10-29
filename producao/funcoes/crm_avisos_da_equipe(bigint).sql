CREATE OR REPLACE FUNCTION public.crm_avisos_da_equipe(p_depois bigint)
 RETURNS TABLE(id bigint, fonte text, tipo text, titulo text, texto text, telefone text, criado_em timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT a.id, a.fonte, a.tipo, a.titulo, a.texto, a.telefone, a.criado_em
    FROM privado.aviso_equipe a
   WHERE a.id > coalesce(p_depois, 0) AND a.tipo <> 'nota'
   ORDER BY a.id
   LIMIT 200
$function$;
