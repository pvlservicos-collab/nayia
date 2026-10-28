CREATE OR REPLACE FUNCTION public.nay_aviso_equipe(p_fonte text, p_tipo text, p_titulo text, p_texto text, p_telefone text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  INSERT INTO privado.aviso_equipe (fonte, tipo, titulo, texto, telefone)
  VALUES (left(coalesce(nullif(btrim(p_fonte), ''), 'desconhecida'), 40),
          CASE WHEN p_tipo IN ('escalada', 'duvida', 'midia', 'relatorio', 'lead', 'outro') THEN p_tipo ELSE 'outro' END,
          left(coalesce(nullif(btrim(p_titulo), ''), 'Aviso da Nay'), 200),
          left(coalesce(nullif(btrim(p_texto), ''), coalesce(nullif(btrim(p_titulo), ''), 'Aviso da Nay')), 20000),
          nullif(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), ''))
  RETURNING id
$function$;
