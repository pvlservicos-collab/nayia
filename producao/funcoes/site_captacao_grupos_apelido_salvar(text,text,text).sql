CREATE OR REPLACE FUNCTION public.site_captacao_grupos_apelido_salvar(p_apelido text, p_tipo text, p_oficial text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_chave   text := site_captacao_chave(p_apelido);
  v_tipo    text := lower(coalesce(p_tipo, ''));
  v_oficial text;
BEGIN
  IF length(v_chave) < 2 THEN RETURN jsonb_build_object('erro', 'Escreva o apelido.'); END IF;
  IF v_tipo NOT IN ('bairro', 'condominio') THEN RETURN jsonb_build_object('erro', 'O apelido é de bairro ou de condomínio?'); END IF;
  -- o nome oficial tem de existir no cadastro (senão o apelido leva a lugar nenhum)
  IF v_tipo = 'bairro' THEN
    SELECT btrim(i.bairro) INTO v_oficial FROM imoveis i
     WHERE site_captacao_chave(i.bairro) = site_captacao_chave(p_oficial) GROUP BY 1 ORDER BY count(*) DESC LIMIT 1;
  ELSE
    SELECT btrim(c.nome) INTO v_oficial FROM condominios c
     WHERE site_captacao_chave(c.nome) = site_captacao_chave(p_oficial) LIMIT 1;
  END IF;
  IF v_oficial IS NULL THEN
    RETURN jsonb_build_object('erro', 'Não achei "' || coalesce(btrim(p_oficial), '') || '" no cadastro de '
                                      || CASE v_tipo WHEN 'bairro' THEN 'bairros' ELSE 'condomínios' END || '.');
  END IF;
  INSERT INTO privado.grupo_apelido (apelido, tipo, oficial) VALUES (v_chave, v_tipo, v_oficial)
  ON CONFLICT (apelido) DO UPDATE SET tipo = excluded.tipo, oficial = excluded.oficial, obs = NULL, criado_em = now();
  UPDATE privado.grupo_captacao_estado SET repontuar = true WHERE id = 1;   -- o serviço refaz a conta da janela
  RETURN jsonb_build_object('ok', true, 'apelido', v_chave, 'oficial', v_oficial);
END
$function$;
