-- "4 mil" é R$ 4.000, não R$ 4.
--
-- O BUG (auditoria de 01/09): `nay_buscar_por_perfil` lia o teto com
-- `regexp_replace(p_teto,'[^0-9]','','g')`, então "4 mil" virava 4 --
-- abaixo do piso de locação de R$ 2.000. A Nay respondia "não temos
-- imóvel para locação nesse perfil, o valor está abaixo do que
-- trabalhamos" a quem tinha orçamento de quatro mil reais, e ainda
-- escalava ao Tel como demanda não atendida que nunca existiu.
--
-- As formas são as que o corretor escreve: "4000", "4.000", "R$ 4.000",
-- "4 mil", "4mil", "4k", "4,5 mil", "600 mil", "1,2 milhão", "1.2 mi".
--
--   docker cp valor_em_reais.sql nay-postgres:/tmp/vr.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/vr.sql

CREATE OR REPLACE FUNCTION nay_valor_em_reais(p_texto text)
RETURNS numeric
LANGUAGE plpgsql IMMUTABLE AS $fn$
DECLARE
  t     text := lower(unaccent(btrim(coalesce(p_texto,''))));
  m     text[];
  num   numeric;
  mult  numeric := 1;
BEGIN
  IF t = '' THEN RETURN NULL; END IF;

  -- Por extenso, o que aparece: o corretor escreve numero quase sempre,
  -- mas "um milhao" e "meio milhao" acontecem.
  t := regexp_replace(t, '\mum milhao\M', '1 milhao', 'g');
  t := regexp_replace(t, '\mmeio milhao\M', '0,5 milhao', 'g');

  -- Primeiro numero do texto, com virgula ou ponto decimal.
  m := regexp_match(t, '([0-9]+(?:[.,][0-9]+)?)');
  IF m IS NULL THEN RETURN NULL; END IF;

  -- Separador de MILHAR ("4.000", "1,200") vira nada; separador DECIMAL
  -- ("4,5") vira ponto. A diferenca e quantos digitos vem depois: tres
  -- digitos e milhar, um ou dois e decimal.
  IF m[1] ~ '[.,][0-9]{3}$' THEN
    num := replace(replace(m[1], '.', ''), ',', '')::numeric;
  ELSE
    num := replace(m[1], ',', '.')::numeric;
  END IF;

  -- O multiplicador vem DEPOIS do numero, e so conta se estiver colado
  -- ou logo em seguida: "4 mil", "4mil", "4k".
  IF t ~ ('\m' || regexp_replace(m[1],'[.,]','[.,]','g') || '\s*(mi|milhao|milhoes|milhões)\M') THEN
    mult := 1000000;
  ELSIF t ~ ('\m' || regexp_replace(m[1],'[.,]','[.,]','g') || '\s*(mil|k)\M') THEN
    mult := 1000;
  END IF;

  RETURN num * mult;
END;
$fn$;
