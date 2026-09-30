CREATE OR REPLACE FUNCTION public.nai_marcar_imovel(p_verbo text, p_resto text, p_quem text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_volta   boolean := lower(unaccent(coalesce(p_verbo, ''))) ~ '^(disponivel|disponibiliza|liber|voltou)';
  v_status  text;
  v_cods    int[];
  c         int;
  i         imoveis;
  v_ok      text[] := '{}';
  v_nao     text[] := '{}';
  v_ja      text[] := '{}';
BEGIN
  v_status := CASE
    WHEN v_volta THEN 'Disponível'
    WHEN lower(unaccent(coalesce(p_verbo, ''))) ~ '^(vend)' THEN 'Vendido'
    WHEN lower(unaccent(coalesce(p_verbo, ''))) ~ '^(alug)' THEN 'Alugado'
    ELSE 'Indisponível' END;

  -- os codigos da mensagem: "5727", "5727 e 5733", "#5727, 5733"
  SELECT coalesce(array_agg(DISTINCT (m.x)[1]::int), '{}') INTO v_cods
    FROM regexp_matches(coalesce(p_resto, ''), '(\d{3,5})', 'g') AS m(x);

  IF coalesce(array_length(v_cods, 1), 0) = 0 THEN
    RETURN 'Me diz o código do imóvel: ' || upper(p_verbo) || ' 5727.';
  END IF;

  FOREACH c IN ARRAY v_cods LOOP
    SELECT * INTO i FROM imoveis WHERE codigo = c;
    IF i.codigo IS NULL THEN
      v_nao := v_nao || c::text;
    ELSIF coalesce(i.disponivel, true) = v_volta THEN
      v_ja := v_ja || (c::text || ' (' || coalesce(i.status, CASE WHEN v_volta THEN 'disponível' ELSE 'indisponível' END) || ')');
    ELSE
      INSERT INTO imovel_situacao_log (codigo, de_disponivel, para_disponivel, status_antes, status_depois, quem, comando)
      VALUES (c, i.disponivel, v_volta, i.status, v_status, p_quem, upper(p_verbo) || ' ' || p_resto);
      -- a tabela `imoveis` nao tem carimbo de atualizacao; quem guarda o
      -- quando e o `imovel_situacao_log` logo acima.
      UPDATE imoveis SET disponivel = v_volta, status = v_status WHERE codigo = c;
      v_ok := v_ok || (c::text || ' — ' || coalesce(nai_condominio_ok(i.condominio_nome), coalesce(nullif(i.tipo,''), 'imóvel')) ||
                       coalesce(' (' || nullif(i.bairro, '') || ')', ''));
    END IF;
  END LOOP;

  RETURN btrim(  -- btrim so tira espaco por padrao; a quebra de linha vai junto
    CASE WHEN array_length(v_ok, 1) > 0 THEN
      CASE WHEN v_volta THEN 'Voltou para o ar: ' ELSE 'Tirei do ar (' || lower(v_status) || '): ' END
      || array_to_string(v_ok, '; ')
      || CASE WHEN v_volta THEN '. Já volto a oferecer.' ELSE '. Não ofereço mais nem no site.' END
    ELSE '' END ||
    CASE WHEN array_length(v_ja, 1) > 0 THEN
      E'\n' || 'Já estava assim: ' || array_to_string(v_ja, '; ') || '.' ELSE '' END ||
    CASE WHEN array_length(v_nao, 1) > 0 THEN
      E'\n' || 'Não achei no cadastro: ' || array_to_string(v_nao, ', ') || '.' ELSE '' END, E' 
');
END;
$function$
;
