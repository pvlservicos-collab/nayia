CREATE OR REPLACE FUNCTION public.nai_giria_explica(p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce(
    ' COMO ELE FALA: ' || string_agg('"' || g.exemplo_curto || '" = ' || g.significado, ' ' ORDER BY g.id),
    '')
    FROM (
      SELECT id, significado,
             -- a expressao inteira que ele escreveu: a regex vai entre
             -- parenteses para o grupo 1 ser o casamento todo, e nao o
             -- primeiro pedaco dela ("ta" em vez de "ta valendo").
             coalesce((regexp_match(lower(unaccent(coalesce(p_texto, ''))), '(' || expressao || ')'))[1],
                      expressao) AS exemplo_curto
        FROM nai_giria
       WHERE ativo
         AND lower(unaccent(coalesce(p_texto, ''))) ~ expressao
       LIMIT 6            -- teto: gíria e ajuda, nao um dicionario no contexto
    ) g;
$function$
;
