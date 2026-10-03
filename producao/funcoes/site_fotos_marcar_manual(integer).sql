CREATE OR REPLACE FUNCTION public.site_fotos_marcar_manual(p_codigo integer)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  INSERT INTO imovel_fotos_manual (codigo, editado_em, acoes) VALUES (p_codigo, now(), 1)
  ON CONFLICT (codigo) DO UPDATE SET editado_em = now(), acoes = imovel_fotos_manual.acoes + 1;
$function$;
