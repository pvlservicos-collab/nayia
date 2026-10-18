-- 404: O RESULTADO DE CADA VISITA, marcado à mão no painel do Início
--
-- Pedro, 17/10/2026: "visitas, você colocou todas mas muitas não foram realizadas, e também não sei quantas se
-- converteram em negócios de verdade, então põe lá umas abas interativas, tipo a aba visitas vai ter as visitas
-- listadas e um botão de status, Desistiu, Realizada, Fechou negócio, e eu vou poder mudar e salvar manualmente visita
-- a visita".
--   privado.visita_resultado            o que a equipe marcou: (origem 'parceria' = nai_visita | 'olx' = olx_visita, id)
--   site_painel_visitas(de, ate)        as visitas do período (pelo dia DA VISITA), com o resultado marcado
--   site_painel_visita_marcar(...)      grava ou limpa o resultado de uma visita
--   site_painel_metricas                ganha visitas_realizadas / visitas_desistiu / visitas_fechou / visitas_sem_resultado
--                                       (pelo dia da visita; "fechou" também é realizada)
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.visita_resultado (
  origem      text NOT NULL CHECK (origem IN ('parceria', 'olx')),
  visita_id   bigint NOT NULL,
  resultado   text NOT NULL CHECK (resultado IN ('desistiu', 'realizada', 'fechou')),
  marcado_por text,
  marcado_em  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (origem, visita_id)
);

CREATE OR REPLACE FUNCTION public.site_painel_visitas(p_de date, p_ate date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH v AS (
    SELECT 'parceria'::text AS origem, v.id, v.quando, v.codigo, v.estado, v.criado_em,
           CASE WHEN v.criada_no_crm_por IS NULL THEN 'Nay' ELSE 'CRM' END AS marcada_por,
           nullif(split_part(btrim(coalesce(c.nome_completo, c.nome_whatsapp, '')), ' ', 1), '') AS corretor,
           nullif(split_part(btrim(coalesce(v.visitante_nome, '')), ' ', 1), '') AS cliente,
           nullif(btrim(coalesce(v.resultado, '')), '') AS nota_do_sistema
      FROM nai_visita v LEFT JOIN nai_contato c ON c.id = v.corretor_id
     WHERE v.excluida_em IS NULL AND v.quando IS NOT NULL
       AND v.quando >= p_de::timestamp AT TIME ZONE 'America/Manaus'
       AND v.quando < (p_ate + 1)::timestamp AT TIME ZONE 'America/Manaus'
    UNION ALL
    SELECT 'olx', ov.id, ov.quando, ov.codigo, ov.estado, ov.criado_em, 'Nay do WhatsApp (OLX)',
           nullif(split_part(btrim(coalesce(ov.corretor_nome, '')), ' ', 1), ''),
           nullif(split_part(btrim(coalesce(w.nome, '')), ' ', 1), ''), NULL
      FROM privado.olx_visita ov LEFT JOIN privado.olx_lead_whatsapp w ON w.id = ov.lead
     WHERE ov.quando IS NOT NULL
       AND ov.quando >= p_de::timestamp AT TIME ZONE 'America/Manaus'
       AND ov.quando < (p_ate + 1)::timestamp AT TIME ZONE 'America/Manaus'
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'origem', v.origem, 'id', v.id, 'quando', v.quando, 'codigo', v.codigo, 'estado', v.estado,
           'marcada_por', v.marcada_por, 'corretor', v.corretor, 'cliente', v.cliente, 'nota_do_sistema', v.nota_do_sistema,
           'passou', v.quando < now(),
           'imovel', concat_ws(' · ', nullif(i.condominio_nome, ''), nullif(i.tipo, ''), nullif(i.bairro, '')),
           'resultado', r.resultado, 'marcado_por', r.marcado_por, 'marcado_em', r.marcado_em)
         ORDER BY v.quando DESC, v.id DESC), '[]'::jsonb)
    FROM v
    LEFT JOIN imoveis i ON i.codigo = v.codigo
    LEFT JOIN privado.visita_resultado r ON r.origem = v.origem AND r.visita_id = v.id;
$function$;

CREATE OR REPLACE FUNCTION public.site_painel_visita_marcar(p_origem text, p_id bigint, p_resultado text, p_quem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_res text := nullif(lower(btrim(coalesce(p_resultado, ''))), '');
BEGIN
  IF p_origem NOT IN ('parceria', 'olx') THEN RETURN jsonb_build_object('ok', false, 'erro', 'origem inválida'); END IF;
  IF p_origem = 'parceria' AND NOT EXISTS (SELECT 1 FROM nai_visita WHERE id = p_id) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'visita não encontrada');
  END IF;
  IF p_origem = 'olx' AND NOT EXISTS (SELECT 1 FROM privado.olx_visita WHERE id = p_id) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'visita não encontrada');
  END IF;
  IF v_res IS NULL THEN
    DELETE FROM privado.visita_resultado WHERE origem = p_origem AND visita_id = p_id;
    RETURN jsonb_build_object('ok', true, 'resultado', NULL);
  END IF;
  IF v_res NOT IN ('desistiu', 'realizada', 'fechou') THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'resultado é desistiu, realizada ou fechou');
  END IF;
  INSERT INTO privado.visita_resultado (origem, visita_id, resultado, marcado_por, marcado_em)
  VALUES (p_origem, p_id, v_res, left(coalesce(p_quem, ''), 80), now())
  ON CONFLICT (origem, visita_id) DO UPDATE SET resultado = EXCLUDED.resultado, marcado_por = EXCLUDED.marcado_por,
                                                marcado_em = now();
  RETURN jsonb_build_object('ok', true, 'resultado', v_res);
END
$function$;

-- os números do resultado no painel (pelo dia da visita)
DO $do$
DECLARE d text;
BEGIN
  d := pg_get_functiondef('public.site_painel_metricas(date,date,text)'::regprocedure);
  d := replace(d, $a$    'visitas_olx', 'visitas_olx_confirmadas',$a$,
                  $b$    'visitas_olx', 'visitas_olx_confirmadas',
    'visitas_realizadas', 'visitas_desistiu', 'visitas_fechou', 'visitas_sem_resultado',$b$);
  d := replace(d, $a$  -- PARCERIA: imóvel que saiu (card ou foto) para alguém$a$,
    $b$  -- 404: o resultado que a equipe marcou, pelo dia da VISITA (as que já passaram); fechou também é realizada
  UNION ALL
  SELECT x.m, vv.quando, vv.k
    FROM (SELECT 'parceria' AS origem, id, quando FROM nai_visita WHERE excluida_em IS NULL AND quando IS NOT NULL
          UNION ALL SELECT 'olx', id, quando FROM privado.olx_visita WHERE quando IS NOT NULL) vv0
   CROSS JOIN LATERAL (SELECT vv0.quando, vv0.origem || vv0.id AS k) vv
    LEFT JOIN privado.visita_resultado r ON r.origem = vv0.origem AND r.visita_id = vv0.id
   CROSS JOIN LATERAL (VALUES (CASE WHEN r.resultado IN ('realizada', 'fechou') THEN 'visitas_realizadas' END),
                              (CASE WHEN r.resultado = 'fechou' THEN 'visitas_fechou' END),
                              (CASE WHEN r.resultado = 'desistiu' THEN 'visitas_desistiu' END),
                              (CASE WHEN r.resultado IS NULL THEN 'visitas_sem_resultado' END)) x(m)
   WHERE x.m IS NOT NULL AND vv.quando >= v_ini AND vv.quando < least(v_fim, now())
  -- PARCERIA: imóvel que saiu (card ou foto) para alguém$b$);
  IF position('visitas_sem_resultado' IN d) = 0 OR position('404: o resultado' IN d) = 0 THEN
    RAISE EXCEPTION 'site_painel_metricas: as âncoras não bateram';
  END IF;
  EXECUTE d;
END
$do$;

REVOKE ALL ON FUNCTION public.site_painel_visitas(date, date), public.site_painel_visita_marcar(text, bigint, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_painel_visitas(date, date), public.site_painel_visita_marcar(text, bigint, text, text)
  TO nay_site_escrita;
COMMIT;
