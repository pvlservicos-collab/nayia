CREATE OR REPLACE FUNCTION public.nai_imovel_pela_descricao(p_texto text, p_telefone text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  s        text := lower(unaccent(coalesce(p_texto, '')));
  s_lugar  text := nay_normalizar_lugar(coalesce(p_texto, ''), true);
  v_bairro text;
  v_tipo   text;   -- o padrao do LIKE contra imoveis.tipo
  v_rotulo text;   -- como ELE chamou, para a Nay repetir a palavra dele
  v_cods   int[];
BEGIN
  -- O BAIRRO. Mesmo criterio de nai_pedido_de_perfil: casa o nome inteiro e,
  -- para nome de tres palavras ou mais, as duas primeiras -- ninguem escreve
  -- "Parque 10 de Novembro" no WhatsApp.
  SELECT b.bairro INTO v_bairro FROM (
    SELECT DISTINCT i.bairro FROM imoveis i WHERE nullif(btrim(i.bairro), '') IS NOT NULL) b
   WHERE s_lugar LIKE '%' || nay_normalizar_lugar(b.bairro, true) || '%'
      OR (array_length(string_to_array(nay_normalizar_lugar(b.bairro, true), ' '), 1) >= 3
          AND s_lugar LIKE '%' ||
              array_to_string((string_to_array(nay_normalizar_lugar(b.bairro, true), ' '))[1:2], ' ') || '%')
   ORDER BY length(b.bairro) DESC LIMIT 1;

  -- SEM BAIRRO NAO HA BUSCA. "Tem casa?" sozinho traria o catalogo inteiro, e
  -- o resultado seria pior do que perguntar.
  IF v_bairro IS NULL THEN
    RETURN jsonb_build_object('achou', false);
  END IF;

  -- O TIPO, na palavra dele. A ordem importa: "casa de condominio" tem que ser
  -- lido antes de "condominio".
  IF    s ~ '\m(casa|casas|sobrado)\M'                       THEN v_tipo := 'Casa%';        v_rotulo := 'casa';
  ELSIF s ~ '\m(apartamento|apartamentos|apto|aptos|ap)\M'   THEN v_tipo := 'Apartamento%'; v_rotulo := 'apartamento';
  ELSIF s ~ '\m(cobertura|coberturas)\M'                     THEN v_tipo := 'Cobertura%';   v_rotulo := 'cobertura';
  ELSIF s ~ '\m(flat|flats)\M'                               THEN v_tipo := 'Flat%';        v_rotulo := 'flat';
  ELSIF s ~ '\m(sala|salas|andar)\M'                         THEN v_tipo := 'Sala%';        v_rotulo := 'sala';
  ELSIF s ~ '\m(loja|lojas|ponto)\M'                         THEN v_tipo := 'Loja%';        v_rotulo := 'loja';
  ELSIF s ~ '\m(galpao|galpoes|deposito)\M'                  THEN v_tipo := 'Galp%';        v_rotulo := 'galpão';
  ELSIF s ~ '\m(terreno|terrenos|lote|lotes)\M'              THEN v_tipo := 'Lote%';        v_rotulo := 'terreno';
  ELSIF s ~ '\m(chacara|chacaras|sitio)\M'                   THEN v_tipo := 'Ch%';          v_rotulo := 'chácara';
  ELSIF s ~ '\m(predio|predios)\M'                           THEN v_tipo := 'Pr%dio%';      v_rotulo := 'prédio';
  END IF;

  IF v_tipo IS NULL THEN
    RETURN jsonb_build_object('achou', false);
  END IF;

  -- O QUE ESTA DE PE. `nai_oferta_serve` e o mesmo crivo que a busca usa: o
  -- que ela nao ofereceria numa busca tambem nao serve para identificar aqui.
  SELECT coalesce(array_agg(z.c ORDER BY z.v), '{}') INTO v_cods FROM (
    SELECT i.codigo AS c, i.valor_aluguel AS v FROM imoveis i
     WHERE nay_normalizar_lugar(i.bairro, true) = nay_normalizar_lugar(v_bairro, true)
       AND i.tipo ILIKE v_tipo
       AND nai_oferta_serve(i, coalesce(p_telefone, ''), NULL, NULL, false, false)
     ORDER BY i.valor_aluguel LIMIT 9) z;

  IF coalesce(array_length(v_cods, 1), 0) = 0 THEN
    RETURN jsonb_build_object('achou', false, 'bairro', v_bairro, 'rotulo', v_rotulo, 'vazio', true);
  END IF;

  RETURN jsonb_build_object(
    'achou',   true,
    'bairro',  v_bairro,
    'rotulo',  v_rotulo,
    'quantos', array_length(v_cods, 1),
    'codigos', to_jsonb(v_cods));
END;
$function$
;
