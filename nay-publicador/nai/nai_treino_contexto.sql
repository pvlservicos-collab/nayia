CREATE OR REPLACE FUNCTION public.nai_treino_contexto(p_contato bigint, p_ate timestamp with time zone, p_quantos integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'quando', u.quando, 'lado', u.lado, 'texto', u.texto)
         ORDER BY u.quando, u.ord), '[]'::jsonb)
    FROM (
      SELECT m.quando, m.ord, m.lado, m.texto FROM (
        SELECT t.criado_em AS quando, 0 AS ord, 'dele'::text AS lado, t.texto
          FROM nai_turno t
         WHERE t.contato_id = p_contato AND t.criado_em < p_ate AND t.texto IS NOT NULL
        UNION ALL
        SELECT t.criado_em, 1, 'dela'::text,
               (SELECT string_agg(x.texto, E'\n' ORDER BY x.ordem, x.id)
                  FROM nai_saida x WHERE x.turno_id = t.id AND x.tipo = 'texto')
          FROM nai_turno t
         WHERE t.contato_id = p_contato AND t.criado_em < p_ate
      ) m
       WHERE m.texto IS NOT NULL
       ORDER BY m.quando DESC, m.ord DESC
       LIMIT p_quantos
    ) u;
$function$
;
