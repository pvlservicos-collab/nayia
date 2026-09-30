CREATE OR REPLACE FUNCTION public.nai_negocio_antes_do_card(p_contato bigint, p_codigo integer, p_escreveu text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE i imoveis;
BEGIN
  -- 225 (Pedro, 30/09: "perguntar se é venda ou locação antes de mandar o card
  -- ou imóvel, para não confundir"). Só quando o imóvel serve aos dois E a
  -- conversa ainda não disse: imóvel de uma finalidade só, o card já diz.
  -- Uma vez em 24 h.
  IF p_codigo IS NULL OR nai_finalidade_do_imovel(p_codigo) <> 'ambos' THEN RETURN NULL; END IF;
  IF nai_negocio_da_conversa(p_contato, coalesce(p_escreveu, '')) IS NOT NULL THEN RETURN NULL; END IF;
  IF nai_filtro_ja_perguntado(p_contato, 'negocio') THEN RETURN NULL; END IF;
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  RETURN 'O ' || coalesce(nai_condominio_ok(i.condominio_nome), 'imóvel ' || p_codigo)
         || ' está disponível para locação e para venda. O seu cliente quer alugar ou comprar?';
END;
$function$;
