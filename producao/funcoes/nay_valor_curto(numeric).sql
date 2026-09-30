CREATE OR REPLACE FUNCTION public.nay_valor_curto(p_valor numeric)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE v numeric;
BEGIN
  IF coalesce(p_valor,0) = 0 THEN RETURN NULL; END IF;
  -- Abaixo de mil o "k" atrapalha: 900 vira "0.9k", que ninguém lê como
  -- novecentos. Sai o número inteiro.
  IF p_valor < 1000 THEN
    RETURN to_char(round(p_valor), 'FM999990');
  END IF;
  -- A unidade sai do valor JÁ ARREDONDADO: senão 999.999 vira "1000k",
  -- tecnicamente certo e ilegível.
  IF round(p_valor / 1000, 2) >= 1000 THEN
    v := round(p_valor / 1000000, 2);
    RETURN btrim(to_char(v, 'FM999999990.99'), '.') || 'M';
  END IF;
  v := round(p_valor / 1000, 2);
  RETURN btrim(to_char(v, 'FM999999990.99'), '.') || 'k';
END;
$function$;
