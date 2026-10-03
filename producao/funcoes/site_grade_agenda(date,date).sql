CREATE OR REPLACE FUNCTION public.site_grade_agenda(p_de date, p_ate date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_de  date := greatest(coalesce(p_de, current_date), current_date - 180);
  v_ate date := least(coalesce(p_ate, coalesce(p_de, current_date) + 6), greatest(coalesce(p_de, current_date), current_date - 180) + 62);
  v_ini timestamptz;
  v_fim timestamptz;
  v_teste text[] := nai_chaves_teste();
  v jsonb;
BEGIN
  v_ini := v_de::timestamp AT TIME ZONE 'America/Manaus';
  v_fim := (v_ate + 1)::timestamp AT TIME ZONE 'America/Manaus';
  WITH gerais AS (   -- sem destino: os grupos ativos que recebem post de imóvel (todas_fotos é outro caminho)
    SELECT array_agg(id_grupo) AS ids FROM grupos WHERE ativo AND NOT coalesce(todas_fotos, false)
  ), vg AS (
    SELECT v.*,
           CASE WHEN EXISTS (SELECT 1 FROM grupos g WHERE g.ativo AND g.apelido = v.destino)
                THEN (SELECT array_agg(g.id_grupo) FROM grupos g WHERE g.ativo AND g.apelido = v.destino)
                ELSE (SELECT ids FROM gerais) END AS previstos
      FROM vagas v
  ), oc AS (
    SELECT vg.id AS vaga_id, ((d::date + vg.horario) AT TIME ZONE 'America/Manaus') AS quando
      FROM vg, generate_series(v_de::timestamp, v_ate::timestamp, interval '1 day') d
     WHERE (vg.tipo_recorrencia = 'diaria'
            OR (vg.tipo_recorrencia = 'semanal' AND extract(dow FROM d)::int = ANY (vg.dias_semana))
            OR (vg.tipo_recorrencia = 'unica' AND d::date = vg.data_unica))
       AND ((d::date + vg.horario) AT TIME ZONE 'America/Manaus') >= date_trunc('minute', vg.criado_em) - interval '1 minute'
  ), mesma_hora AS (   -- os códigos de imóvel postados no mesmo horário (para a vaga de LISTA não tomar os posts deles)
    SELECT oc.quando, array_agg(DISTINCT c) AS codigos
      FROM oc JOIN vagas v ON v.id = oc.vaga_id, unnest(v.codigos) c
     GROUP BY oc.quando
  ), env AS (
    SELECT oc.vaga_id, oc.quando,
           array_agg(DISTINCT e.grupo_nome) FILTER (WHERE e.grupo_nome IS NOT NULL) AS grupos,
           array_agg(DISTINCT e.message_id) FILTER (WHERE e.message_id IS NOT NULL) AS ids,
           array_agg(DISTINCT e.codigo) AS codigos,
           count(*) AS posts
      FROM oc JOIN vagas v ON v.id = oc.vaga_id
      JOIN envios e ON e.destino = 'grupo'
                   AND e.enviado_em >= oc.quando - interval '1 minute' AND e.enviado_em < oc.quando + interval '90 minutes'
                   AND (CASE WHEN cardinality(v.codigos) > 0 THEN e.codigo = ANY (v.codigos)
                             ELSE NOT (e.codigo = ANY (coalesce((SELECT mh.codigos FROM mesma_hora mh WHERE mh.quando = oc.quando), '{}'::text[]))) END)
     WHERE oc.quando <= now()
     GROUP BY oc.vaga_id, oc.quando
  ), msgs0 AS MATERIALIZED (   -- o que chegou ao número da Parceria no período (+6 h)
    SELECT nai_chave(m.telefone) AS chave, m.criada_em, m.citado_id, m.texto
      FROM mensagens m
     WHERE m.direcao = 'recebida' AND m.criada_em >= v_ini AND m.criada_em < v_fim + interval '6 hours'
  ), quem AS MATERIALIZED (    -- equipe e teste saem: uma conta por PESSOA, não por mensagem
    SELECT d.chave, k.criado_em AS desde,
           (d.chave = ANY (v_teste)) OR (k.id IS NOT NULL AND nai_e_da_equipe_contato(k.id)) AS fora
      FROM (SELECT DISTINCT chave FROM msgs0 WHERE chave IS NOT NULL) d
      LEFT JOIN nai_contato k ON k.chave = d.chave
  ), msgs AS MATERIALIZED (
    SELECT m.chave, m.criada_em, m.citado_id, m.texto, q.desde
      FROM msgs0 m JOIN quem q ON q.chave = m.chave
     WHERE NOT q.fora
  ), met AS (
    SELECT env.vaga_id, env.quando,
           count(DISTINCT s.chave) AS pessoas,
           count(DISTINCT s.chave) FILTER (WHERE s.desde >= env.quando) AS novos,
           count(DISTINCT s.chave) FILTER (WHERE s.citado_id = ANY (coalesce(env.ids, '{}'::text[]))
                                              OR s.texto ~ ('\m(' || array_to_string(env.codigos, '|') || ')\M')) AS pelo_imovel
      FROM env
      LEFT JOIN msgs s ON s.criada_em >= env.quando AND s.criada_em < env.quando + interval '6 hours'
     GROUP BY env.vaga_id, env.quando
  )
  SELECT jsonb_build_object(
    'de', v_de, 'ate', v_ate, 'agora', now(),
    'vagas', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'id', vg.id, 'horario', to_char(vg.horario, 'HH24:MI'), 'recorrencia', vg.tipo_recorrencia,
        'dias', to_jsonb(vg.dias_semana), 'data', vg.data_unica, 'destino', vg.destino,
        'categoria', vg.categoria, 'negocio', vg.negocio, 'criada_em', vg.criado_em,
        'previstos', to_jsonb(vg.previstos),
        'imoveis', (SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                        'codigo', c.cod, 'existe', i.codigo IS NOT NULL,
                        'titulo', coalesce(nullif(btrim(i.condominio_nome), ''), i.tipo), 'bairro', i.bairro,
                        'venda', nullif(i.valor_venda, 0), 'aluguel', nullif(i.valor_aluguel, 0),
                        'no_ar', CASE WHEN i.codigo IS NULL THEN NULL
                                      ELSE nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site) END,
                        'parceiro', coalesce(i.e_parceiro, false),
                        'foto', (SELECT f.url FROM imovel_fotos f WHERE f.codigo = i.codigo AND coalesce(f.url, '') <> ''
                                    AND NOT coalesce(f.e_mosaico, false)
                                  ORDER BY coalesce(f.e_capa, false) DESC, f.ordem NULLS LAST, f.id LIMIT 1)))
                        ORDER BY c.n)
                      FROM unnest(vg.codigos) WITH ORDINALITY c(cod, n)
                      LEFT JOIN imoveis i ON i.codigo::text = c.cod)))
        ORDER BY vg.horario, vg.id) FROM vg), '[]'::jsonb),
    'ocorrencias', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'vaga', oc.vaga_id, 'quando', oc.quando, 'passou', oc.quando <= now(),
        'janela_completa', oc.quando + interval '6 hours' <= now(),
        'posts', env.posts, 'grupos', to_jsonb(env.grupos),
        'pessoas', met.pessoas, 'novos', met.novos, 'pelo_imovel', met.pelo_imovel))
        ORDER BY oc.quando, oc.vaga_id)
      FROM oc
      LEFT JOIN env ON env.vaga_id = oc.vaga_id AND env.quando = oc.quando
      LEFT JOIN met ON met.vaga_id = oc.vaga_id AND met.quando = oc.quando), '[]'::jsonb)
  ) INTO v;
  RETURN v;
END;
$function$;
