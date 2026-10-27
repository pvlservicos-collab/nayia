CREATE OR REPLACE FUNCTION public.nay_separar_sigilo(p_texto text, p_registro boolean, OUT publico text, OUT interno text)
 RETURNS record
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  linha text; frase text; pub text[] := '{}'; int_ text[] := '{}'; resto text[]; marcado boolean;
BEGIN
  IF p_texto IS NULL THEN RETURN; END IF;
  FOREACH linha IN ARRAY regexp_split_to_array(p_texto, E'\n') LOOP
    marcado := CASE WHEN p_registro THEN nay_e_registro_interno(linha) ELSE nay_e_sigilo(linha) END;
    IF marcado THEN
      resto := '{}';
      FOREACH frase IN ARRAY regexp_split_to_array(linha, '(?<=[.!?;])\s+|\s+/\s+') LOOP
        marcado := CASE WHEN p_registro THEN nay_e_registro_interno(frase) ELSE nay_e_sigilo(frase) END;
        IF marcado THEN
          int_ := int_ || btrim(regexp_replace(frase, '^\s*OBS:\s*', ''));
        ELSE
          resto := resto || frase;
        END IF;
      END LOOP;
      linha := btrim(array_to_string(resto, ' '));
      IF linha <> '' AND linha !~* '^OBS:\s*$' THEN pub := pub || linha; END IF;
    ELSE
      pub := pub || linha;
    END IF;
  END LOOP;
  publico := nullif(btrim(array_to_string(pub, E'\n')), '');
  interno := nullif(btrim(array_to_string(int_, ' ')), '');
END $function$;
