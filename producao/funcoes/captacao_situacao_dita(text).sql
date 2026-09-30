CREATE OR REPLACE FUNCTION public.captacao_situacao_dita(p_texto text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE s text := lower(unaccent(coalesce(p_texto, '')));
BEGIN
  -- NEGACAO perto da palavra derruba tudo: "nao foi vendido", "ainda nao
  -- aluguei", "nao esta alugado". Preferimos nao gravar a gravar errado.
  IF s ~ ('\m(nao|ainda nao|nunca)\M[^.!?]{0,24}\m(vendid|vendi|alugad|locad|aluguei)') THEN
    RETURN NULL;
  END IF;
  IF s ~ ('\m(vendid[oa]|ja vendi|vendi (a|o|esse|este|meu)\M)') THEN
    RETURN 'vendido';
  END IF;
  IF s ~ ('\m(alugad[oa]|locad[oa]|ja aluguei|esta locado|esta alugado)\M') THEN
    RETURN 'alugado';
  END IF;
  RETURN NULL;
END;
$function$;
