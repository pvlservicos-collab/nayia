CREATE OR REPLACE FUNCTION public.site_grade_metricas(p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_ate date := least(coalesce(p_ate, current_date), current_date);
  v_de  date := greatest(coalesce(p_de, v_ate - 29), v_ate - 92);
  v_ini timestamptz;
  v_fim timestamptz;
  v_teste text[] := nai_chaves_teste();
  v jsonb;
BEGIN
  v_ini := v_de::timestamp AT TIME ZONE 'America/Manaus';
  v_fim := least((v_ate + 1)::timestamp AT TIME ZONE 'America/Manaus', now());
  WITH posts AS MATERIALIZED (   -- cada post de IMÓVEL num grupo, com o DISPARO a que pertence (posts do mesmo
                                 -- código a menos de 45 min um do outro são a mesma saída, grupo por grupo)
    SELECT x.*, sum(x.novo) OVER (PARTITION BY x.codigo ORDER BY x.enviado_em, x.id) AS ilha
      FROM (SELECT e.id, e.codigo, e.message_id, e.grupo_nome, e.enviado_em,
                   CASE WHEN e.enviado_em - lag(e.enviado_em) OVER (PARTITION BY e.codigo ORDER BY e.enviado_em, e.id)
                             <= interval '45 minutes' THEN 0 ELSE 1 END AS novo
              FROM envios e
             WHERE e.destino = 'grupo' AND e.enviado_em >= v_ini AND e.enviado_em < v_fim AND e.codigo ~ '^\d{2,6}$') x
  ), disp AS MATERIALIZED (      -- um disparo de imóvel: quando começou, quando acabou, em quantos grupos
    SELECT codigo, ilha, min(enviado_em) AS quando, max(enviado_em) AS ate, count(*) AS posts,
           array_agg(DISTINCT grupo_nome) FILTER (WHERE grupo_nome IS NOT NULL) AS grupos
      FROM posts GROUP BY codigo, ilha
  ), listas AS MATERIALIZED (    -- cada lista que saiu, com os ids e os códigos dela (existem desde a 281)
    SELECT l.id, l.categoria, l.negocio, l.destino, l.enviado_em AS quando, l.grupos, l.quantos,
           (SELECT array_agg(DISTINCT x.message_id) FROM envios_lista_grupo x
             WHERE x.categoria = l.categoria AND x.negocio = l.negocio
               AND x.enviado_em >= l.enviado_em - interval '1 minute' AND x.enviado_em < l.enviado_em + interval '60 minutes') AS ids,
           (SELECT array_agg(DISTINCT x.codigo::text) FROM envios_lista_grupo x
             WHERE x.categoria = l.categoria AND x.negocio = l.negocio
               AND x.enviado_em >= l.enviado_em - interval '1 minute' AND x.enviado_em < l.enviado_em + interval '60 minutes') AS codigos
      FROM lista_disparada l
     WHERE l.enviado_em >= v_ini AND l.enviado_em < v_fim AND coalesce(cardinality(l.grupos), 0) > 0
  ), msgs0 AS MATERIALIZED (     -- o que chegou ao número da Parceria (a marcação vale até 7 dias depois do post)
    SELECT nai_chave(m.telefone) AS chave, m.criada_em, m.citado_id, m.texto
      FROM mensagens m
     WHERE m.direcao = 'recebida' AND m.criada_em >= v_ini AND m.criada_em < v_fim + interval '7 days'
  ), quem AS MATERIALIZED (      -- equipe e teste saem
    SELECT d.chave, (d.chave = ANY (v_teste)) OR (k.id IS NOT NULL AND nai_e_da_equipe_contato(k.id)) AS fora
      FROM (SELECT DISTINCT chave FROM msgs0 WHERE chave IS NOT NULL) d
      LEFT JOIN nai_contato k ON k.chave = d.chave
  ), msgs AS MATERIALIZED (
    SELECT m.chave, m.criada_em, m.citado_id, m.texto
      FROM msgs0 m JOIN quem q ON q.chave = m.chave WHERE NOT q.fora
  ), marc AS MATERIALIZED (      -- quem MARCOU o post do grupo no privado
    SELECT DISTINCT p.codigo, p.ilha, s.chave
      FROM posts p JOIN msgs s ON s.citado_id = p.message_id
     WHERE p.message_id IS NOT NULL
  ), msgs_cod AS MATERIALIZED (  -- só as mensagens que trazem um número com cara de código (a maioria não traz)
    SELECT chave, criada_em, texto FROM msgs WHERE texto ~ '\d{3,5}'
  ), perg AS MATERIALIZED (      -- quem ESCREVEU O CÓDIGO até 6 h depois do disparo. O CASE garante a ordem: o
                                 -- horário é conferido antes do texto (sem ele, 30 dias levavam 9 s)
    SELECT DISTINCT d.codigo, d.ilha, s.chave
      FROM disp d CROSS JOIN msgs_cod s
     WHERE CASE WHEN s.criada_em >= d.quando AND s.criada_em < d.ate + interval '6 hours'
                THEN s.texto ~ ('\m' || d.codigo || '\M') ELSE false END
  ), gente AS MATERIALIZED (     -- por disparo de imóvel: a pessoa e como chegou (marcar vence escrever)
    SELECT codigo, ilha, chave, bool_or(marcou) AS marcou
      FROM (SELECT codigo, ilha, chave, true AS marcou FROM marc
            UNION ALL SELECT codigo, ilha, chave, false FROM perg) u
     GROUP BY codigo, ilha, chave
  ), lgente AS MATERIALIZED (    -- o mesmo para as listas
    SELECT l.id, s.chave, bool_or(s.citado_id = ANY (coalesce(l.ids, '{}'::text[]))) AS marcou
      FROM listas l JOIN msgs s
        ON s.citado_id = ANY (coalesce(l.ids, '{}'::text[]))
        OR (cardinality(coalesce(l.codigos, '{}'::text[])) > 0
            AND s.criada_em >= l.quando AND s.criada_em < l.quando + interval '6 hours'
            AND s.texto ~ ('\m(' || array_to_string(l.codigos, '|') || ')\M'))
     GROUP BY l.id, s.chave
  ), vd AS MATERIALIZED (        -- o disparo de imóvel é de qual mensagem da grade? (código, horário e dia batem)
    SELECT v.id AS vaga_id, d.codigo, d.ilha, d.quando, d.posts, d.grupos
      FROM vagas v JOIN disp d ON d.codigo = ANY (v.codigos)
     WHERE v.categoria IS NULL
       AND d.quando >= date_trunc('minute', v.criado_em) - interval '1 minute'
       AND (d.quando AT TIME ZONE 'America/Manaus')::time >= v.horario - interval '1 minute'
       AND (d.quando AT TIME ZONE 'America/Manaus')::time <  v.horario + interval '90 minutes'
       AND (v.tipo_recorrencia = 'diaria'
            OR (v.tipo_recorrencia = 'semanal' AND extract(dow FROM d.quando AT TIME ZONE 'America/Manaus')::int = ANY (v.dias_semana))
            OR (v.tipo_recorrencia = 'unica' AND (d.quando AT TIME ZONE 'America/Manaus')::date = v.data_unica))
  ), vl AS MATERIALIZED (        -- a lista disparada é de qual mensagem da grade?
    SELECT v.id AS vaga_id, l.id AS lista_id, l.quando, l.grupos
      FROM vagas v JOIN listas l ON l.categoria = v.categoria AND l.negocio = v.negocio AND l.destino = v.destino
     WHERE v.categoria IS NOT NULL
       AND (l.quando AT TIME ZONE 'America/Manaus')::time >= v.horario - interval '1 minute'
       AND (l.quando AT TIME ZONE 'America/Manaus')::time <  v.horario + interval '30 minutes'
  ), por_vaga AS (
    SELECT v.id, v.horario, v.tipo_recorrencia, v.dias_semana, v.data_unica, v.destino, v.categoria, v.negocio, v.codigos,
           (v.texto_fixo IS NOT NULL) AS texto_fixo,
           -- as vezes: cada dia+horário em que saiu (a vaga de vários imóveis conta uma vez por horário)
           CASE WHEN v.categoria IS NULL
                THEN (SELECT count(DISTINCT (vd.quando AT TIME ZONE 'America/Manaus')::date) FROM vd WHERE vd.vaga_id = v.id)
                ELSE (SELECT count(*) FROM vl WHERE vl.vaga_id = v.id) END AS vezes,
           CASE WHEN v.categoria IS NULL
                THEN (SELECT coalesce(sum(vd.posts), 0) FROM vd WHERE vd.vaga_id = v.id)
                ELSE (SELECT coalesce(sum(cardinality(vl.grupos)), 0) FROM vl WHERE vl.vaga_id = v.id) END AS posts,
           CASE WHEN v.categoria IS NULL
                THEN (SELECT max(vd.quando) FROM vd WHERE vd.vaga_id = v.id)
                ELSE (SELECT max(vl.quando) FROM vl WHERE vl.vaga_id = v.id) END AS ultima,
           CASE WHEN v.categoria IS NULL
                THEN (SELECT count(DISTINCT g.chave) FILTER (WHERE g.marcou) FROM vd JOIN gente g ON g.codigo = vd.codigo AND g.ilha = vd.ilha WHERE vd.vaga_id = v.id)
                ELSE (SELECT count(DISTINCT g.chave) FILTER (WHERE g.marcou) FROM vl JOIN lgente g ON g.id = vl.lista_id WHERE vl.vaga_id = v.id) END AS marcaram,
           CASE WHEN v.categoria IS NULL
                THEN (SELECT count(DISTINCT g.chave) FROM vd JOIN gente g ON g.codigo = vd.codigo AND g.ilha = vd.ilha WHERE vd.vaga_id = v.id)
                ELSE (SELECT count(DISTINCT g.chave) FROM vl JOIN lgente g ON g.id = vl.lista_id WHERE vl.vaga_id = v.id) END AS pessoas
      FROM vagas v
  ), por_imovel AS (
    SELECT d.codigo, count(*) AS vezes, sum(d.posts) AS posts, max(d.quando) AS ultima,
           (SELECT count(DISTINCT g.chave) FILTER (WHERE g.marcou) FROM gente g WHERE g.codigo = d.codigo) AS marcaram,
           (SELECT count(DISTINCT g.chave) FROM gente g WHERE g.codigo = d.codigo) AS pessoas
      FROM disp d GROUP BY d.codigo
  )
  SELECT jsonb_build_object(
    'de', v_de, 'ate', v_ate,
    'total', jsonb_build_object(
      'disparos', (SELECT count(*) FROM disp) + (SELECT count(*) FROM listas),
      'posts', (SELECT coalesce(sum(posts), 0) FROM disp) + (SELECT coalesce(sum(cardinality(grupos)), 0) FROM listas),
      'marcaram', (SELECT count(DISTINCT chave) FROM (SELECT chave FROM gente WHERE marcou UNION SELECT chave FROM lgente WHERE marcou) u),
      'pessoas', (SELECT count(DISTINCT chave) FROM (SELECT chave FROM gente UNION SELECT chave FROM lgente) u)),
    'mensagens', coalesce((SELECT jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
        'vaga', pv.id, 'horario', to_char(pv.horario, 'HH24:MI'), 'recorrencia', pv.tipo_recorrencia,
        'dias', to_jsonb(pv.dias_semana), 'data', pv.data_unica, 'destino', pv.destino,
        'categoria', pv.categoria, 'negocio', pv.negocio, 'texto_fixo', pv.texto_fixo,
        'imoveis', (SELECT jsonb_agg(jsonb_build_object('codigo', c.cod,
                                     'titulo', coalesce(nullif(btrim(i.condominio_nome), ''), i.tipo)) ORDER BY c.n)
                      FROM unnest(pv.codigos) WITH ORDINALITY c(cod, n) LEFT JOIN imoveis i ON i.codigo::text = c.cod),
        'vezes', pv.vezes, 'posts', pv.posts, 'ultima', pv.ultima,
        'marcaram', pv.marcaram, 'perguntaram', pv.pessoas - pv.marcaram, 'pessoas', pv.pessoas))
        ORDER BY pv.pessoas DESC, pv.vezes DESC, pv.horario, pv.id) FROM por_vaga pv), '[]'::jsonb),
    'imoveis', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'codigo', pi.codigo, 'titulo', coalesce(nullif(btrim(i.condominio_nome), ''), i.tipo), 'bairro', i.bairro,
        'vezes', pi.vezes, 'posts', pi.posts, 'ultima', pi.ultima,
        'marcaram', pi.marcaram, 'perguntaram', pi.pessoas - pi.marcaram, 'pessoas', pi.pessoas)
        ORDER BY pi.pessoas DESC, pi.vezes DESC, pi.codigo)
      FROM por_imovel pi LEFT JOIN imoveis i ON i.codigo::text = pi.codigo), '[]'::jsonb),
    'listas_com_id_desde', (SELECT min(enviado_em) FROM envios_lista_grupo)
  ) INTO v;
  RETURN v;
END;
$function$;
