CREATE OR REPLACE FUNCTION public.nai_giria_explica(p_texto text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce(
    ' COMO ELE FALA: ' || string_agg('"' || g.exemplo_curto || '" = ' || g.significado, ' ' ORDER BY g.id),
    '')
    -- 206/215: conjuntos e avenidas -- só quando a mensagem é PEDIDO de imóvel
    || CASE WHEN coalesce((nai_pedido_de_perfil(p_texto)->>'e_pedido')::boolean, false) THEN
         coalesce((SELECT ' LUGARES (referência; citar lugar não é pedir imóvel): ' || string_agg(
           CASE WHEN l.tipo = 'conjunto'
                THEN '"' || l.nome || '" é um conjunto do bairro ' || l.bairros[1] || '.'
                ELSE '"' || l.nome || '" passa ' || CASE WHEN cardinality(l.bairros) = 1 THEN 'pelo bairro ' ELSE 'pelos bairros ' END
                     || nai_lista_pt(l.bairros) || '.' END
           || ' Se ele está pedindo imóvel lá, ao chamar buscar_por_perfil passe bairro "' || l.nome
           || '" em vez de perguntar o bairro; o resto do filtro segue igual.',
           ' ' ORDER BY l.tipo, l.nome)
         FROM (SELECT * FROM nai_lugar_citado(p_texto) LIMIT 4) l), '')
       ELSE '' END
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
