CREATE OR REPLACE FUNCTION public.nai_rodar_casos()
 RETURNS TABLE(passou boolean, regra text, frase text, esperado text, deu text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE c record; v text;
BEGIN
  FOR c IN SELECT * FROM nai_caso WHERE ativo ORDER BY id LOOP
    v := CASE c.pergunta
      WHEN 'tipo'       THEN coalesce(nai_tipo_pedido(c.frase), '-')
      WHEN 'tipo_canon' THEN coalesce(nai_tipo_canonico(c.frase), '-')
      WHEN 'negocio'    THEN coalesce(nay_negocio_pedido(c.frase), '-')
      WHEN 'cortesia'   THEN nai_e_so_cortesia(c.frase)::text
      WHEN 'oferta'     THEN nai_oferece_imovel(c.frase)::text
      WHEN 'anuncio'    THEN nai_e_anuncio_dele(c.frase)::text
      WHEN 'catalogo'   THEN nai_pergunta_de_catalogo(c.frase)::text
      WHEN 'link'       THEN nai_e_link_de_produto(c.frase)::text
      WHEN 'pede_lista' THEN nai_pede_os_valores(c.frase)::text
      WHEN 'sem_bairro' THEN nai_sem_preferencia_de_bairro(c.frase)::text
      WHEN 'de_imovel'  THEN nai_e_assunto_de_locacao(c.frase)::text
      WHEN 'imoveis'    THEN nai_imoveis_pedidos(c.frase, '')::text
      WHEN 'passe'      THEN nai_passe_do_citado(nai_imoveis_pedidos(c.frase, ''))::text
      WHEN 'texto_limpo' THEN nai_texto_sem_os_barrados(c.frase)
      WHEN 'nomes'      THEN nai_corrigir_nomes(c.frase)
      WHEN 'valor'      THEN coalesce(nay_maior_valor(c.frase)::text, '-')
      WHEN 'pelo_nome'  THEN nai_imovel_pelo_condominio(c.frase, '')::text  -- 190
      WHEN 'afirma_pagamento' THEN coalesce(nai_afirmacao_de_pagamento(c.frase), '-')  -- 191
      WHEN 'assunto_sensivel' THEN coalesce(nai_assunto_sensivel(c.frase), '-')  -- 191
      WHEN 'negocio_valor' THEN coalesce(nai_negocio_pelo_valor(c.frase), '-')  -- 190
      WHEN 'tipo_conversa'    THEN coalesce(nai_tipo_das_falas(string_to_array(c.frase, ' || ')), '-')
      WHEN 'negocio_conversa' THEN coalesce(nai_negocio_das_falas(string_to_array(c.frase, ' || ')), '-')
      ELSE '(pergunta desconhecida: ' || c.pergunta || ')'
    END;
    passou := (v = c.esperado);
    regra := c.regra; frase := c.frase; esperado := c.esperado; deu := v;
    RETURN NEXT;
  END LOOP;
END;
$function$
;
