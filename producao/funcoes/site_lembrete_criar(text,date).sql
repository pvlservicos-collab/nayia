CREATE OR REPLACE FUNCTION public.site_lembrete_criar(p_texto text, p_dia date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE v_texto text := btrim(coalesce(p_texto, '')); v_id bigint;
BEGIN
  IF v_texto = '' THEN RETURN jsonb_build_object('erro', 'Escreva o lembrete.'); END IF;
  IF length(v_texto) > 1000 THEN RETURN jsonb_build_object('erro', 'O lembrete passou de 1.000 caracteres.'); END IF;
  IF p_dia IS NULL THEN RETURN jsonb_build_object('erro', 'Escolha o dia.'); END IF;
  INSERT INTO privado.lembrete_equipe (texto, dia) VALUES (v_texto, p_dia) RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END
$function$;
