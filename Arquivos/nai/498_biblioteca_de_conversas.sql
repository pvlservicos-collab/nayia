-- 498: A BIBLIOTECA DE CONVERSAS (Pedro, 25/10/2026: "crie um registro de conversas que deram certo x conversas com
-- erro e salvar, isso vai ficar lá na aba inteligência no site também ... vamos usar futuramente para treino ...
-- começando somente com as conversas desse mês outubro ... já fiz diversas rodadas de correção da nay parceria e preciso
-- que você cheque isso profundamente para pegar esses registros").
--
-- privado.conversa_biblioteca: uma linha por conversa (ou por caso, quando a conversa não foi achada), com o resultado
-- (certo | erro), a confiança (humano = o Pedro ou o Tel disseram; revisão = o agente de revisão, o Gemini ou um commit
-- de correção; nota automática = scripts/notas_nay.py) e TODAS as marcas (de onde veio cada julgamento, os erros, o que
-- devia, a correção). Fica no schema privado: tem nome e telefone de corretor e cliente (a regra das candidaturas).
-- A página admin › Inteligência lê por site_biblioteca(filtros) e site_biblioteca_conversa(id); a carga é
-- privado.biblioteca_gravar(jsonb) (uma linha; repetir a mesma nay+ref atualiza).
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';

CREATE TABLE IF NOT EXISTS privado.conversa_biblioteca (
  id           bigserial PRIMARY KEY,
  nay          text NOT NULL,                       -- parceria, leads, olx, captacao, corretores, cadastro, velha
  ref          text NOT NULL,                       -- 'AAAA-MM-DD/<tel4>-<id>' (a conversa do dia) ou 'treino/...' ou 'caso/...'
  dia          date,
  tel4         text,
  pessoa       text,
  resultado    text NOT NULL CHECK (resultado IN ('certo', 'erro')),
  confianca    text NOT NULL,                       -- humano | revisão | nota automática
  nota         integer,
  fontes       text[] NOT NULL DEFAULT '{}',
  tipos        text[] NOT NULL DEFAULT '{}',        -- os tipos de erro das marcas (para filtrar)
  resumo       text,
  marcas       jsonb NOT NULL DEFAULT '[]'::jsonb,
  texto        text,
  usar_no_treino boolean NOT NULL DEFAULT true,
  criado_em    timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  UNIQUE (nay, ref)
);
CREATE INDEX IF NOT EXISTS conversa_biblioteca_dia ON privado.conversa_biblioteca (dia DESC);
COMMENT ON TABLE privado.conversa_biblioteca IS
  '498: a biblioteca de conversas (certo × erro) da aba Inteligência; base do treino futuro.';

CREATE OR REPLACE FUNCTION privado.biblioteca_gravar(p jsonb) RETURNS bigint
LANGUAGE sql SET search_path TO 'privado', 'public' AS $$
  INSERT INTO privado.conversa_biblioteca AS b (nay, ref, dia, tel4, pessoa, resultado, confianca, nota, fontes, tipos,
                                                resumo, marcas, texto)
  SELECT p->>'nay', p->>'ref', nullif(p->>'dia', '')::date, nullif(p->>'tel4', ''), nullif(p->>'pessoa', ''),
         p->>'resultado', p->>'confianca', (p->>'nota')::integer,
         ARRAY(SELECT jsonb_array_elements_text(coalesce(p->'fontes', '[]'::jsonb))),
         ARRAY(SELECT DISTINCT e->>'tipo' FROM jsonb_array_elements(coalesce(p->'marcas', '[]'::jsonb)) m,
                    jsonb_array_elements(coalesce(m->'erros', '[]'::jsonb)) e WHERE m->>'resultado' = 'erro' AND e->>'tipo' IS NOT NULL),
         coalesce((SELECT coalesce(m->>'resumo', e->>'o_que_aconteceu')
                     FROM jsonb_array_elements(coalesce(p->'marcas', '[]'::jsonb)) WITH ORDINALITY AS mm(m, i)
                     LEFT JOIN LATERAL jsonb_array_elements(coalesce(m->'erros', '[]'::jsonb)) e ON true
                    WHERE m->>'resultado' = p->>'resultado' AND coalesce(m->>'resumo', e->>'o_que_aconteceu', '') <> ''
                    ORDER BY CASE m->>'fonte' WHEN 'pedro_chat' THEN 0 WHEN 'pedido_ao_agente' THEN 0 WHEN 'treino_pedro' THEN 0
                                              WHEN 'agente_revisao' THEN 1 WHEN 'revisao_gemini' THEN 1 WHEN 'commit_core' THEN 2
                                              ELSE 3 END, i LIMIT 1), ''),
         coalesce(p->'marcas', '[]'::jsonb), nullif(p->>'texto', '')
  ON CONFLICT (nay, ref) DO UPDATE SET dia = EXCLUDED.dia, tel4 = EXCLUDED.tel4, pessoa = EXCLUDED.pessoa,
    resultado = EXCLUDED.resultado, confianca = EXCLUDED.confianca, nota = EXCLUDED.nota, fontes = EXCLUDED.fontes,
    tipos = EXCLUDED.tipos, resumo = EXCLUDED.resumo, marcas = EXCLUDED.marcas, texto = EXCLUDED.texto, atualizado_em = now()
  RETURNING b.id
$$;

-- a lista da página (sem o texto): filtros nay, resultado, confianca, fonte, tipo, busca, de, ate; limite e pagina
CREATE OR REPLACE FUNCTION public.site_biblioteca(p jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'privado', 'public' AS $$
  WITH f AS (
    SELECT nullif(p->>'nay', '') AS nay, nullif(p->>'resultado', '') AS res, nullif(p->>'confianca', '') AS conf,
           nullif(p->>'fonte', '') AS fonte, nullif(p->>'tipo', '') AS tipo,
           nullif(btrim(coalesce(p->>'busca', '')), '') AS busca,
           nullif(p->>'de', '')::date AS de, nullif(p->>'ate', '')::date AS ate,
           greatest(1, least(coalesce((p->>'limite')::int, 50), 200)) AS lim,
           greatest(0, coalesce((p->>'pagina')::int, 0)) AS pag),
  b AS (
    SELECT x.* FROM privado.conversa_biblioteca x, f
     WHERE (f.nay IS NULL OR x.nay = f.nay) AND (f.res IS NULL OR x.resultado = f.res)
       AND (f.conf IS NULL OR x.confianca = f.conf) AND (f.fonte IS NULL OR f.fonte = ANY (x.fontes))
       AND (f.tipo IS NULL OR f.tipo = ANY (x.tipos))
       AND (f.de IS NULL OR x.dia >= f.de) AND (f.ate IS NULL OR x.dia <= f.ate)
       AND (f.busca IS NULL OR x.tel4 = f.busca OR x.resumo ILIKE '%' || f.busca || '%' OR x.texto ILIKE '%' || f.busca || '%'
            OR x.pessoa ILIKE '%' || f.busca || '%'))
  SELECT jsonb_build_object(
    'total', (SELECT count(*) FROM b),
    'por_nay', (SELECT coalesce(jsonb_object_agg(nay, j), '{}'::jsonb) FROM (
                  SELECT nay, jsonb_build_object('certo', count(*) FILTER (WHERE resultado = 'certo'),
                                                 'erro', count(*) FILTER (WHERE resultado = 'erro')) j
                    FROM privado.conversa_biblioteca GROUP BY nay) z),
    'por_tipo', (SELECT coalesce(jsonb_object_agg(t, n), '{}'::jsonb) FROM (
                  SELECT t, count(*) n FROM b, unnest(b.tipos) t GROUP BY t ORDER BY n DESC) z),
    'por_confianca', (SELECT coalesce(jsonb_object_agg(k, n), '{}'::jsonb) FROM (
                  SELECT confianca || ' · ' || resultado AS k, count(*) n FROM b GROUP BY 1) z),
    'linhas', coalesce((SELECT jsonb_agg(jsonb_build_object('id', id, 'nay', nay, 'ref', ref, 'dia', dia, 'tel4', tel4,
                         'pessoa', pessoa, 'resultado', resultado, 'confianca', confianca, 'nota', nota, 'fontes', fontes,
                         'tipos', tipos, 'resumo', resumo, 'tem_texto', texto IS NOT NULL) ORDER BY dia DESC NULLS LAST, id DESC)
                        FROM (SELECT * FROM b ORDER BY dia DESC NULLS LAST, id DESC
                               LIMIT (SELECT lim FROM f) OFFSET (SELECT lim * pag FROM f)) y), '[]'::jsonb))
$$;

CREATE OR REPLACE FUNCTION public.site_biblioteca_conversa(p_id bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'privado', 'public' AS $$
  SELECT to_jsonb(x) FROM privado.conversa_biblioteca x WHERE x.id = p_id
$$;

GRANT EXECUTE ON FUNCTION public.site_biblioteca(jsonb), public.site_biblioteca_conversa(bigint)
  TO nay, nay_site_leitura, nay_site_escrita;

COMMIT;
