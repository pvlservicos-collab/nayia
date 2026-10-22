CREATE OR REPLACE FUNCTION public.site_ia_modelo_trocar(p_no text, p_modelo text, p_quem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_antes text;
  v_mod   text := btrim(coalesce(p_modelo, ''));
BEGIN
  SELECT modelo INTO v_antes FROM privado.ia_no_modelo WHERE no = p_no;
  IF v_antes IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Este nó não é trocável pela página (o modelo dele mora no código ou no n8n).');
  END IF;
  IF v_mod !~ '^[A-Za-z0-9][A-Za-z0-9._:/-]{2,79}$' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Nome de modelo inválido: use o nome exato da API (ex.: gpt-6-luna).');
  END IF;
  UPDATE privado.ia_no_modelo SET modelo = v_mod, trocado_por = left(coalesce(nullif(btrim(p_quem), ''), 'admin'), 80),
         trocado_em = now() WHERE no = p_no;
  RETURN jsonb_build_object('ok', true, 'no', p_no, 'antes', v_antes, 'modelo', v_mod,
                            'aviso', 'O serviço usa o modelo novo na próxima chamada (até 1 minuto).');
END $function$;
