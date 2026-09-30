CREATE OR REPLACE FUNCTION public.crm_visita_editar(p_visita bigint, p_campo text, p_valor text, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v nai_visita;
  valor text := nullif(btrim(coalesce(p_valor, '')), '');
  antes text;
  quem text := coalesce(nullif(btrim(p_quem), ''), 'CRM');
  rotulo text;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL OR v.excluida_em IS NOT NULL THEN RETURN QUERY SELECT false, 'Não achei essa visita.'; RETURN; END IF;

  IF p_campo = 'codigo' THEN
    IF valor IS NULL OR valor !~ '^\d{2,6}$' THEN RETURN QUERY SELECT false, 'Código inválido.'; RETURN; END IF;
    IF NOT EXISTS (SELECT 1 FROM imoveis WHERE codigo = valor::int) THEN
      RETURN QUERY SELECT false, 'Esse código não está no catálogo.'; RETURN;
    END IF;
    antes := v.codigo::text;
    UPDATE nai_visita SET codigo = valor::int, atualizado_em = now() WHERE id = v.id;
    rotulo := 'imóvel';
  ELSIF p_campo = 'visitante_nome' THEN
    antes := v.visitante_nome;
    UPDATE nai_visita SET visitante_nome = valor, atualizado_em = now() WHERE id = v.id;
    rotulo := 'visitante';
  ELSIF p_campo = 'proprietario_nome' THEN
    antes := v.proprietario_nome;
    UPDATE nai_visita SET proprietario_nome = valor, atualizado_em = now() WHERE id = v.id;
    rotulo := 'proprietário';
  ELSIF p_campo = 'acesso' THEN
    IF valor IS NOT NULL AND valor NOT IN ('chave_conosco', 'buscar_chave', 'fechadura', 'proprietario_acompanha') THEN
      RETURN QUERY SELECT false, 'Acesso inválido.'; RETURN;
    END IF;
    antes := v.acesso;
    UPDATE nai_visita SET acesso = valor, atualizado_em = now() WHERE id = v.id;
    rotulo := 'acesso';
  ELSIF p_campo = 'acesso_detalhe' THEN
    antes := v.acesso_detalhe;
    UPDATE nai_visita SET acesso_detalhe = valor, atualizado_em = now() WHERE id = v.id;
    rotulo := 'detalhe do acesso';
  ELSE
    RETURN QUERY SELECT false, 'Esse campo não se edita por aqui.'; RETURN;
  END IF;

  IF antes IS NOT DISTINCT FROM valor THEN RETURN QUERY SELECT true, 'Já estava assim.'; RETURN; END IF;
  PERFORM nai_evento(v.id, 'editada_no_crm',
    rotulo || ': ' || coalesce(antes, '(vazio)') || ' → ' || coalesce(valor, '(vazio)') || ' (por ' || quem || ')');
  RETURN QUERY SELECT true, 'Salvo. Ninguém foi avisado.';
END $function$;
