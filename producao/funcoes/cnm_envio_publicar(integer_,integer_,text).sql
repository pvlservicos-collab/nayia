CREATE OR REPLACE FUNCTION public.cnm_envio_publicar(p_ids integer[], p_destaques integer[], p_quem text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE v_ids integer[]; v_dest integer[];
BEGIN
  SELECT coalesce(array_agg(c ORDER BY n), '{}') INTO v_ids
    FROM (SELECT c, min(n) AS n FROM unnest(coalesce(p_ids, '{}')) WITH ORDINALITY u(c, n)
           WHERE EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = u.c) GROUP BY c) x;
  SELECT coalesce(array_agg(c ORDER BY n), '{}') INTO v_dest
    FROM (SELECT c, min(n) AS n FROM unnest(coalesce(p_destaques, '{}')) WITH ORDINALITY u(c, n) WHERE c = ANY (v_ids) GROUP BY c) x;
  UPDATE cnm_envio_selecao SET ids = v_ids, destaques = v_dest, atualizado_em = now(), atualizado_por = left(p_quem, 120) WHERE id = 1;
  RETURN cnm_envio_selecao();
END
$function$;
