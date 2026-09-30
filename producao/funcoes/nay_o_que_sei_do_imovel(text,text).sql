CREATE OR REPLACE FUNCTION public.nay_o_que_sei_do_imovel(p_codigo text, p_pergunta text DEFAULT NULL::text)
 RETURNS TABLE(texto_pronto text, sabe boolean, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_cod  text := NULLIF(regexp_replace(coalesce(p_codigo,''),'[^0-9]','','g'),'');
  v_ass  text := nay_assunto_do_imovel(p_pergunta);
  v_txt  text;
  v_tudo text;
BEGIN
  IF v_cod IS NULL THEN
    RETURN QUERY SELECT ''::text, false,
      'sem codigo nao da para consultar. Descubra o imovel primeiro.'::text;
    RETURN;
  END IF;

  -- O assunto exato, quando dá para reconhecer a pergunta.
  IF v_ass IS NOT NULL THEN
    SELECT c.texto INTO v_txt FROM imovel_conhecimento c
     WHERE c.codigo = v_cod AND c.assunto = v_ass;
    IF v_txt IS NOT NULL THEN
      RETURN QUERY SELECT v_txt, true,
        ('o Tel ja explicou isso deste imovel. Responda AGORA com essa '
         || 'informacao, no seu tom. NAO escale e NAO diga que vai '
         || 'verificar.')::text;
      RETURN;
    END IF;
  END IF;

  -- Não sabe o assunto perguntado, mas talvez saiba outras coisas do
  -- imóvel -- e isso vale para ela não escalar o que já está ali.
  SELECT string_agg('• ' || c.assunto || ': ' || c.texto, chr(10) ORDER BY c.assunto)
    INTO v_tudo FROM imovel_conhecimento c WHERE c.codigo = v_cod;

  IF v_tudo IS NULL THEN
    RETURN QUERY SELECT ''::text, false,
      ('nao sei nada alem da ficha sobre o imovel ' || v_cod || '. Se a '
       || 'pergunta nao e respondida pela ficha nem pela descricao, escale ao '
       || 'Tel COM o codigo -- a resposta dele fica gravada e serve para o '
       || 'proximo corretor.')::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT v_tudo, false,
    ('nao sei exatamente o que ele perguntou, mas sei isto do imovel ' || v_cod
     || '. Use se responder; se nao responder, escale COM o codigo.')::text;
END;
$function$;
