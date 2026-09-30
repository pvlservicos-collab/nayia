CREATE OR REPLACE FUNCTION public.nai_conferir_pagamento(p_texto text, p_alvo integer)
 RETURNS TABLE(texto text, trocas integer, sem_dado integer[])
 LANGUAGE plpgsql
 STABLE
AS $function$
-- Cada frase da resposta que afirma forma de pagamento é conferida com a
-- ficha do imóvel de que ela fala (código ou nome na frase; senão o imóvel
-- da conversa). As linhas do CARD ficam fora: o card sai da ficha.
DECLARE
  s      text;
  a      text;
  cods   int[];
  c      int;
  ver    text;
  certa  text;
BEGIN
  texto := p_texto; trocas := 0; sem_dado := '{}';
  FOR s IN SELECT m[1] FROM regexp_matches(coalesce(p_texto, ''), '([^.!?\n]+[.!?]*)', 'g') AS m LOOP
    CONTINUE WHEN btrim(s) = '' OR s ~ '^\s*(•|📍|Venda:|Locação:|C[óo]digo:|OBS:)';
    a := nai_afirmacao_de_pagamento(s);
    CONTINUE WHEN a IS NULL;
    SELECT coalesce(array_agg(DISTINCT x), '{}') INTO cods FROM (
      SELECT y::int AS x FROM unnest(coalesce(nay_codigos_citados(s), '{}'::text[])) y
       WHERE y ~ '^[0-9]{3,5}$' AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = y::int)
      UNION SELECT unnest(nai_imovel_pelo_condominio(s, ''))) z;
    IF coalesce(array_length(cods, 1), 0) = 0 AND p_alvo IS NOT NULL THEN cods := ARRAY[p_alvo]; END IF;
    IF coalesce(array_length(cods, 1), 0) = 0 THEN
      -- afirmou sem dizer de qual imóvel e não há imóvel na conversa: não dá
      -- para conferir, então não sai. O -1 marca "sem imóvel".
      texto := replace(texto, s, ''); sem_dado := sem_dado || (-1); CONTINUE;
    END IF;
    certa := NULL;
    FOREACH c IN ARRAY cods LOOP
      ver := nai_verdade_de_pagamento(c, a);
      IF ver = 'sem_dado' THEN
        sem_dado := sem_dado || c;
      ELSIF ver = 'contradiz' THEN
        certa := concat_ws(' ', certa, nai_frase_de_pagamento(c, a));
      END IF;
    END LOOP;
    IF certa IS NOT NULL THEN
      -- o espaço que vinha antes da frase fica (senão "financiado.O Living")
      texto := replace(texto, s, coalesce(substring(s FROM '^\s*'), '') || certa); trocas := trocas + 1;
    ELSIF EXISTS (SELECT 1 FROM unnest(cods) k WHERE k = ANY (sem_dado)) THEN
      texto := replace(texto, s, '');
    END IF;
  END LOOP;
  texto := btrim(regexp_replace(texto, '[ \t]{2,}', ' ', 'g'));
  RETURN NEXT;
END;
$function$
;
