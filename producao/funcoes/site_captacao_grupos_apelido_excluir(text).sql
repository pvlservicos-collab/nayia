CREATE OR REPLACE FUNCTION public.site_captacao_grupos_apelido_excluir(p_apelido text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
BEGIN
  DELETE FROM privado.grupo_apelido WHERE apelido = site_captacao_chave(p_apelido);
  IF NOT FOUND THEN RETURN jsonb_build_object('erro', 'Não achei esse apelido.'); END IF;
  UPDATE privado.grupo_captacao_estado SET repontuar = true WHERE id = 1;
  RETURN jsonb_build_object('ok', true);
END
$function$;
