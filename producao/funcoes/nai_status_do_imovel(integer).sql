CREATE OR REPLACE FUNCTION public.nai_status_do_imovel(p_codigo integer)
 RETURNS TABLE(texto_pronto text, disponivel boolean, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  i      record;
  v_card text;
  v_cond text;
  v_alt  text;
  v_n    int;
  v_situ text;
BEGIN
  SELECT im.codigo, im.status, im.bairro, nai_condominio_ok(im.condominio_nome) AS cond,
         im.valor_aluguel, im.valor_venda
    INTO i FROM imoveis im WHERE im.codigo = p_codigo;
  IF i.codigo IS NULL THEN
    RETURN QUERY SELECT ('Não achei o imóvel ' || p_codigo || '. Confere o código pra mim?')::text, false,
                        'mande o texto_pronto exatamente como veio.'::text;
    RETURN;
  END IF;

  IF nai_imovel_disponivel(p_codigo) THEN
    SELECT c.texto_pronto INTO v_card FROM nai_card_do_imovel(p_codigo) c;
    RETURN QUERY SELECT ('📌 Status: Disponível' || E'\n\n' || v_card)::text, true,
      ('mande o texto_pronto EXATAMENTE como veio: a linha de status e o card, com as quebras de linha. '
       || 'A pergunta sai sozinha atrás; foto só sai se ele pedir. Não escale.')::text;
    RETURN;
  END IF;

  v_situ := CASE WHEN i.status = 'Alugado' THEN 'está alugado' ELSE 'está indisponível' END;
  v_cond := nullif(btrim(coalesce(i.cond, '')), '');
  -- 214: "Casa" é o condomínio de toda casa de rua -- não é condomínio
  IF lower(unaccent(coalesce(v_cond, ''))) ~ '^(casas?|apartamentos?|apto|salas?( comerciais| comercial)?|terrenos?|lotes?|galpao|galpoes|ponto comercial|imove(l|is)|residencia|kitnet|studio|flat|chacaras?|sitios?|cobertura)$' THEN
    v_cond := NULL;
  END IF;

  IF v_cond IS NOT NULL THEN
    SELECT count(*),
           string_agg('• ' || y.codigo || ' — ' || coalesce(y.tipo, 'Imóvel')
                      || CASE WHEN coalesce(y.quartos, 0) > 0
                              THEN ', ' || y.quartos || CASE WHEN y.quartos = 1 THEN ' quarto' ELSE ' quartos' END ELSE '' END
                      || CASE WHEN coalesce(i.valor_aluguel, 0) > 0 AND coalesce(y.valor_aluguel, 0) > 0
                              THEN ', aluguel R$ ' || replace(to_char(y.valor_aluguel, 'FM999,999,990'), ',', '.')
                              WHEN coalesce(y.valor_venda, 0) > 0
                              THEN ', venda R$ ' || replace(to_char(y.valor_venda, 'FM999,999,990'), ',', '.')
                              WHEN coalesce(y.valor_aluguel, 0) > 0
                              THEN ', aluguel R$ ' || replace(to_char(y.valor_aluguel, 'FM999,999,990'), ',', '.') ELSE '' END,
                      E'\n' ORDER BY y.v)
      INTO v_n, v_alt
      FROM (SELECT x.*, CASE WHEN coalesce(i.valor_aluguel, 0) > 0 THEN x.valor_aluguel ELSE x.valor_venda END AS v
              FROM imoveis x
             WHERE x.codigo <> p_codigo
               AND NOT coalesce(x.e_parceiro, false)
               AND nai_condominio_ok(x.condominio_nome) = v_cond
               AND nai_imovel_disponivel(x.codigo)
               -- 214: o mesmo negócio do imóvel que ele perguntou
               AND CASE WHEN coalesce(i.valor_aluguel, 0) > 0 THEN coalesce(x.valor_aluguel, 0) > 0
                        WHEN coalesce(i.valor_venda, 0) > 0 THEN coalesce(x.valor_venda, 0) > 0
                        ELSE true END
             ORDER BY 2 LIMIT 8) y;
  END IF;

  IF coalesce(v_n, 0) > 0 THEN
    RETURN QUERY SELECT
      ('Hmmm, vi aqui que o ' || p_codigo || ' ' || v_situ || ' no momento. Mas no ' || v_cond
       || ' eu tenho ' || CASE WHEN v_n = 1 THEN 'este disponível' ELSE 'estes disponíveis' END || ':'
       || E'\n' || v_alt || E'\n\n'
       || CASE WHEN v_n = 1 THEN 'Quer que eu te mande as fotos dele?'
               ELSE 'Qual deles te interessa? Te mando as fotos.' END)::text,
      false,
      'mande o texto_pronto EXATAMENTE como veio. Não mande card nem fotos agora: elas saem quando ele escolher.'::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    ('Hmmm, vi aqui que o ' || p_codigo || ' ' || v_situ || ' no momento, quer que eu veja mais opções perto '
     || 'para o seu cliente? Basta me informar os bairros, ou a faixa de preço que eu já vejo aqui, ok?')::text,
    false,
    'mande o texto_pronto EXATAMENTE como veio. Não mande card nem fotos.'::text;
END;
$function$;
