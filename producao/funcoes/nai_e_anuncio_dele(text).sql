CREATE OR REPLACE FUNCTION public.nai_e_anuncio_dele(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  WITH s AS (SELECT coalesce(p_texto, '') AS t)
  SELECT CASE
    -- 1. o verbo entrega sozinho
    -- (\M e FIM de palavra; \m e inicio. Trocar os dois faz a regra nunca
    --  casar, que foi o que aconteceu na primeira tentativa.)
    WHEN (SELECT t FROM s) ~* '(\mvend[eo]\s*-?\s*se\M|\maluga\s*-?\s*se\M|\m(vendo|alugo|repasso|passo)\s+(meu|minha)\M)'
      THEN true
    -- 2. sem verbo, sao as MARCAS DE CARTAZ, e precisa de tres
    ELSE (
      ((SELECT t FROM s) ~ '\*[^*]{3,}\*')::int                                    -- negrito de anuncio
    + ((SELECT t FROM s) ~ '[✅✔\U0001F3E0\U0001F3E1\U0001F3EC\U0001F4CD\U0001F4B0\U0001F6CF\U0001F6BF\U0001F511]')::int
    + ((SELECT t FROM s) ~* '(oportunidade|imperd[ií]vel|aceita financ|agende (sua |uma )?visita|documenta[çc][ãa]o ok|pronto para morar)')::int
    + ((SELECT t FROM s) ~* '\m(dormit[óo]rios?|su[ií]te|vagas? de garagem|[áa]rea de lazer|m²|metros quadrados)')::int
    + ((SELECT t FROM s) ~* '\m(valor|cond|condom[ií]nio|iptu)\s*:?\s*r?\$')::int
    ) >= 3
  END;
$function$;
