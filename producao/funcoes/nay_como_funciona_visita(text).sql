CREATE OR REPLACE FUNCTION public.nay_como_funciona_visita(p_codigo text)
 RETURNS TABLE(texto_pronto text, sabe boolean)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_cod int := NULLIF(regexp_replace(coalesce(p_codigo,''),'[^0-9]','','g'),'')::int;
  v_txt text;
  v_existe boolean;
BEGIN
  IF v_cod IS NULL THEN
    RETURN QUERY SELECT
      'nao entendi de qual imovel voce fala. peca o codigo ao corretor.'::text, false;
    RETURN;
  END IF;

  -- RASPADO. A ficha é texto livre que o Tel digita, e a coisa mais
  -- natural de escrever ali é "chave com o porteiro, apartamento 401" --
  -- que sairia direto ao corretor, furando por dentro a parede que a
  -- pergunta direta não fura. Ver unidade_nunca.sql. Hoje a tabela está
  -- vazia: o conserto é preventivo, e é agora que custa barato.
  SELECT true, btrim(coalesce(nay_descricao_segura(p.como_funciona_visita),''))
    INTO v_existe, v_txt
    FROM imovel_privado p WHERE p.codigo = v_cod;

  IF NOT coalesce(v_existe,false) THEN
    RETURN QUERY SELECT
      ('nao existe ficha privada do imovel ' || v_cod ||
       '. pergunte ao Tel como funciona a visita nesse imovel e guarde a resposta.')::text,
      false;
    RETURN;
  END IF;

  IF coalesce(v_txt,'') = '' THEN
    RETURN QUERY SELECT
      ('ainda nao esta registrado como funciona a visita no imovel ' || v_cod ||
       '. NAO invente e NAO diga ao corretor que tem chave nem que precisa agendar. ' ||
       'Pergunte ao Tel: como funciona a visita no ' || v_cod ||
       '? tem chave com a gente, e fechadura eletronica, precisa agendar com o proprietario? ' ||
       'Quando ele responder, chame guardar_como_funciona_a_visita na MESMA resposta.')::text,
      false;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    ('assim funciona a visita no imovel ' || v_cod || ': ' || v_txt ||
     ' -- use isso para conduzir, e nao repita ao corretor o que nao interessar a ele.')::text,
    true;
END;
$function$;
