CREATE OR REPLACE FUNCTION public.nai_dono_disse_que_saiu(p_texto text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
-- 'alugado' | 'vendido' | 'indisponivel' | 'ocupado' (556) | NULL. Negação perto derruba ("ainda não aluguei", "não foi vendido").
DECLARE s text := lower(unaccent(coalesce(p_texto, '')));
BEGIN
  IF s ~ '\m(nao|n)\M\s+(esta|ta|estah|tah|fica)\s+mais\s+disponivel' OR s ~ '\mja\s+(nao\s+)?(esta|ta)\s+indisponivel' THEN
    RETURN 'indisponivel';
  END IF;
  -- 556 (a dona do 9030, 30/10: "Só vai estar liberado em janeiro"): ocupado até uma data, fora da oferta até lá
  IF s ~ '\mso\M' AND s ~ '\m(liberad|livre|disponivel|desocupad|libera|desocupa|vag[ao])'
     AND s ~ ('\m(janeiro|fevereiro|marco|abril|maio|junho|julho|agosto|setembro|outubro|novembro|dezembro'
              || '|ano que vem|mes que vem|semana que vem)\M|\m\d{1,2}/\d{1,2}\M|\mdia \d{1,2}\M') THEN
    RETURN 'ocupado';
  END IF;
  IF s ~ '\m(nao|ainda nao|nunca|ninguem|se)\M[^.!?]{0,24}\m(vend|alug|loc|loque)' THEN
    RETURN NULL;
  END IF;
  IF s ~ '\m(vendi|vendeu|vendemos|vendid[oa]s?)\M' THEN
    RETURN 'vendido';
  END IF;
  IF s ~ '\m(aluguei|alugou|alugamos|alugad[oa]s?|loquei|locou|locamos|locad[oa]s?)\M' THEN
    RETURN 'alugado';
  END IF;
  RETURN NULL;
END
$function$;
