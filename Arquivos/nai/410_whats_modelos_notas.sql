-- 410: WHATSAPP › MENSAGENS — etiquetas e observação por modelo da Meta (18/10/2026)
--
-- Pedro: "quero uma aba whatsapp onde vai ficar os grupos e as mensagens aprovadas que tem lá em captação ... um panorama
-- geral de todas que foram aprovadas como uma lista filtrável por data e tipo, e aprovada ou não, e também tags, eu ponho
-- tags nela ... 2 colunas de cards e no card tem o mockup".
-- Os modelos em si vêm da Meta (admin/dados/modelos.json, cron nay-agentes a cada 10 min). O que é nosso e precisa durar
-- são as etiquetas e a observação que o Pedro põe em cada um: ficam aqui, pela chave da Meta (nome + idioma).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS whats_modelo_nota (
  nome          text NOT NULL,
  idioma        text NOT NULL DEFAULT 'pt_BR',
  etiquetas     text[] NOT NULL DEFAULT '{}',
  observacao    text,
  atualizado_por text,
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (nome, idioma)
);

CREATE OR REPLACE FUNCTION site_whats_modelos_notas()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
  SELECT jsonb_build_object(
    'notas', coalesce((SELECT jsonb_object_agg(nome || '|' || idioma, jsonb_build_object('etiquetas', to_jsonb(etiquetas), 'observacao', observacao, 'atualizado_em', atualizado_em))
                         FROM whats_modelo_nota), '{}'::jsonb),
    'etiquetas', (SELECT coalesce(jsonb_agg(e ORDER BY e), '[]'::jsonb) FROM (SELECT DISTINCT unnest(etiquetas) e FROM whats_modelo_nota) x)
  )
$function$;

-- p: {nome, idioma, etiquetas: [...], observacao}
CREATE OR REPLACE FUNCTION site_whats_modelo_nota_salvar(p jsonb, p_quem text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'pg_temp' AS $function$
DECLARE v_nome text := nullif(trim(p->>'nome'), ''); v_idioma text := coalesce(nullif(trim(p->>'idioma'), ''), 'pt_BR'); v_et text[];
BEGIN
  IF v_nome IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'sem o nome do modelo'); END IF;
  IF p ? 'etiquetas' THEN
    SELECT coalesce(array_agg(DISTINCT trim(e) ORDER BY trim(e)) FILTER (WHERE trim(e) <> ''), '{}') INTO v_et
      FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p->'etiquetas') = 'array' THEN p->'etiquetas' ELSE '[]'::jsonb END) e;
  END IF;
  INSERT INTO whats_modelo_nota (nome, idioma, etiquetas, observacao, atualizado_por)
  VALUES (v_nome, v_idioma, coalesce(v_et, '{}'), nullif(trim(p->>'observacao'), ''), p_quem)
  ON CONFLICT (nome, idioma) DO UPDATE SET
    etiquetas = coalesce(v_et, whats_modelo_nota.etiquetas),
    observacao = CASE WHEN p ? 'observacao' THEN nullif(trim(p->>'observacao'), '') ELSE whats_modelo_nota.observacao END,
    atualizado_por = p_quem, atualizado_em = now();
  RETURN jsonb_build_object('ok', true, 'nome', v_nome, 'idioma', v_idioma,
    'etiquetas', (SELECT to_jsonb(etiquetas) FROM whats_modelo_nota WHERE nome = v_nome AND idioma = v_idioma));
END
$function$;

REVOKE ALL ON FUNCTION public.site_whats_modelos_notas(), public.site_whats_modelo_nota_salvar(jsonb, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_whats_modelos_notas() TO nay_site_leitura, nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.site_whats_modelo_nota_salvar(jsonb, text) TO nay_site_escrita;
COMMIT;
