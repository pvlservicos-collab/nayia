CREATE OR REPLACE FUNCTION public.nay_codigos_da_conversa(p_telefone text, p_horas integer DEFAULT NULL::integer)
 RETURNS text[]
 LANGUAGE sql
 STABLE
AS $function$
  WITH janela AS (
    SELECT now() - (coalesce(p_horas,
             (SELECT NULLIF(regexp_replace(valor,'[^0-9]','','g'),'')::int
                FROM config WHERE chave = 'imovel_em_foco_horas'),
             24) || ' hours')::interval AS desde,
           right(regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g'), 8) AS tel
  ), achados AS (
    -- 1. o card que MANDAMOS para ele (inclui o caminho do codigo puro,
    --    que e justamente o que nao passa pelo agente)
    SELECT e.codigo AS cod
      FROM envios e, janela j
     WHERE e.destino = 'corretor'
       AND right(regexp_replace(coalesce(e.telefone,''),'[^0-9]','','g'), 8) = j.tel
       AND e.enviado_em >= j.desde
    UNION
    -- 2. o codigo que apareceu no texto, dos DOIS lados da conversa --
    --    inclusive quando o Tel responde pelo numero da Nay
    SELECT c AS cod
      FROM mensagens m, janela j,
           LATERAL unnest(coalesce(nay_codigos_citados(coalesce(m.texto,'')), ARRAY[]::text[])) c
     WHERE right(regexp_replace(coalesce(m.telefone,''),'[^0-9]','','g'), 8) = j.tel
       AND m.criada_em >= j.desde
    UNION
    -- 3. o texto que saiu por ela, quando nao virou linha em `envios`
    SELECT c AS cod
      FROM mensagem_saida s, janela j,
           LATERAL unnest(coalesce(nay_codigos_citados(coalesce(s.texto,'')), ARRAY[]::text[])) c
     WHERE right(regexp_replace(coalesce(s.telefone,''),'[^0-9]','','g'), 8) = j.tel
       AND s.enviado_em >= j.desde
  )
  -- Só código que é imóvel de verdade: número solto num texto pode ser
  -- qualquer coisa, e a faixa deste catálogo (45 a 5712) é a mesma de um
  -- valor de aluguel.
  SELECT array_agg(DISTINCT i.codigo::text ORDER BY i.codigo::text)
    FROM achados a JOIN imoveis i ON i.codigo::text = a.cod;
$function$;
