CREATE OR REPLACE FUNCTION public.nai_sincronizar_grupos(p_grupos jsonb, p_revogar boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_agora   timestamptz := now();
  v_novos   int; v_viram int; v_perderam int := 0; v_lids int;
  v_tel     text := nai_chave(nai_cfg('tel_telefone'));
BEGIN
  -- a) os grupos
  INSERT INTO nai_grupo_corretor (grupo_id, nome, membros, visto_em)
  SELECT g->>'grupo_id', g->>'nome', jsonb_array_length(coalesce(g->'membros', '[]')), v_agora
    FROM jsonb_array_elements(p_grupos) g
  ON CONFLICT (grupo_id) DO UPDATE
     SET nome = EXCLUDED.nome, membros = EXCLUDED.membros, visto_em = EXCLUDED.visto_em;

  -- os membros dos grupos incluidos, um por telefone
  CREATE TEMP TABLE _m ON COMMIT DROP AS
  -- UMA linha por pessoa (pela chave): a mesma pessoa em cinco grupos, ou
  -- com e sem o nono digito, nao pode virar dois corretores.
  SELECT nai_chave(m->>'phone')                             AS chave,
         max(regexp_replace(m->>'phone', '\D', '', 'g'))    AS telefone,
         max(nullif(m->>'lid', ''))                         AS lid,
         array_agg(DISTINCT g->>'nome')                     AS grupos
    FROM jsonb_array_elements(p_grupos) g
    JOIN nai_grupo_corretor gc ON gc.grupo_id = g->>'grupo_id' AND gc.incluir
    CROSS JOIN LATERAL jsonb_array_elements(coalesce(g->'membros', '[]')) m
   WHERE nai_chave(m->>'phone') IS NOT NULL
   GROUP BY 1;

  -- nunca: o proprio Tel, a equipe e quem manda comando
  DELETE FROM _m WHERE chave = v_tel
     OR EXISTS (SELECT 1 FROM equipe e WHERE nai_chave(e.telefone) = _m.chave)
     OR nai_pode_comandar(_m.chave)
     OR nai_e_motoboy(_m.chave);

  -- b) quem ja existe: atualiza (sem mexer em quem o Tel pos a mao)
  UPDATE corretores c
     SET grupos = m.grupos, no_grupo_em = v_agora,
         pode_falar = true, aprovado = true, ativo = true,
         fonte = coalesce(c.fonte, 'grupo')
    FROM _m m
   WHERE nai_chave(c.telefone) = m.chave;
  GET DIAGNOSTICS v_viram = ROW_COUNT;

  -- quem e novo: entra
  INSERT INTO corretores (telefone, origem, aprovado, ativo, pode_falar, fonte, grupos, no_grupo_em)
  SELECT m.telefone, 'grupo: ' || m.grupos[1], true, true, true, 'grupo', m.grupos, v_agora
    FROM _m m
   WHERE NOT EXISTS (SELECT 1 FROM corretores c WHERE nai_chave(c.telefone) = m.chave)
  ON CONFLICT (telefone) DO NOTHING;
  GET DIAGNOSTICS v_novos = ROW_COUNT;

  -- c) LID -> telefone
  INSERT INTO identidade_lid (lid, telefone, origem)
  SELECT m.lid, m.telefone, 'grupo'
    FROM _m m WHERE m.lid IS NOT NULL
  ON CONFLICT (lid) DO UPDATE SET telefone = EXCLUDED.telefone;
  GET DIAGNOSTICS v_lids = ROW_COUNT;

  -- d) quem saiu de todos os grupos -- so com leitura completa
  IF p_revogar THEN
    UPDATE corretores c
       SET pode_falar = false
     WHERE c.fonte = 'grupo' AND c.pode_falar
       AND (c.no_grupo_em IS NULL OR c.no_grupo_em < v_agora);
    GET DIAGNOSTICS v_perderam = ROW_COUNT;
  END IF;

  INSERT INTO nai_config (chave, valor, descricao, atualizado_em)
  VALUES ('grupos_sincronizados_em', to_char(v_agora AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI'),
          'Ultima vez que a lista de corretores foi refeita a partir dos grupos. Parou de avancar = o cron semanal morreu.',
          v_agora)
  ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor, atualizado_em = EXCLUDED.atualizado_em;

  RETURN jsonb_build_object(
    'membros_unicos', (SELECT count(*) FROM _m),
    'ja_eram_corretor', v_viram,
    'novos', v_novos,
    'lids_gravados', v_lids,
    'perderam_permissao', v_perderam,
    'revogou', p_revogar,
    'podem_falar_agora', (SELECT count(*) FROM corretores WHERE pode_falar AND ativo));
END;
$function$;
