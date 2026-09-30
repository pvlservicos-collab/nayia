CREATE OR REPLACE FUNCTION public.nai_giria_explica(p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce(
    ' COMO ELE FALA: ' || string_agg('"' || g.exemplo_curto || '" = ' || g.significado, ' ' ORDER BY g.id),
    '')
    -- 206: conjuntos e avenidas (Pedro, 30/09)
    || coalesce((SELECT ' LUGARES: ' || string_agg(
         CASE WHEN l.tipo = 'conjunto'
              THEN '"' || l.nome || '" é um conjunto do bairro ' || l.bairros[1]
                   || ': quem pede imóvel lá quer imóvel desse bairro.'
              ELSE '"' || l.nome || '" passa ' || CASE WHEN cardinality(l.bairros) = 1 THEN 'pelo bairro ' ELSE 'pelos bairros ' END
                   || nai_lista_pt(l.bairros) || ': quem pede imóvel nessa avenida quer imóvel '
                   || CASE WHEN cardinality(l.bairros) = 1 THEN 'desse bairro.' ELSE 'desses bairros.' END END
         || ' Não pergunte o bairro: chame buscar_por_perfil com bairro "' || l.nome || '" (a busca já procura lá).',
         ' ' ORDER BY l.tipo, l.nome)
       FROM (SELECT * FROM nai_lugar_citado(p_texto) LIMIT 4) l), '')
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
$function$;
