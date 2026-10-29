CREATE OR REPLACE FUNCTION public.crm_tel_duvidas()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH fila AS (
    SELECT 'fila'::text AS fonte, f.id, f.linha, f.estado, nullif(btrim(f.cliente), '') AS cliente, f.chave AS telefone,
           f.codigo, nullif(btrim(f.imovel), '') AS imovel, f.pergunta, nullif(btrim(f.detalhe), '') AS detalhe,
           f.criada_em,
           CASE WHEN f.linha = 'captacao' THEN (
             SELECT string_agg(x.texto, E'\n' ORDER BY x.criada_em) FROM (
               SELECT m.texto, m.criada_em FROM captacao_mensagens m
                WHERE right(regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g'), 8) = right(regexp_replace(f.chave, '\D', '', 'g'), 8)
                  AND m.direcao = 'recebida' AND coalesce(btrim(m.texto), '') <> ''
                  AND m.criada_em BETWEEN f.criada_em - interval '40 minutes' AND f.criada_em + interval '2 minutes'
                ORDER BY m.criada_em DESC LIMIT 4) x)
           ELSE (
             SELECT string_agg(x.texto, E'\n' ORDER BY x.criada_em) FROM (
               SELECT m.texto, m.criada_em FROM mensagens m
                WHERE nai_chave(m.telefone) = nai_chave(f.chave)
                  AND m.direcao = 'recebida' AND coalesce(btrim(m.texto), '') <> ''
                  AND m.criada_em BETWEEN f.criada_em - interval '40 minutes' AND f.criada_em + interval '2 minutes'
                ORDER BY m.criada_em DESC LIMIT 4) x)
           END AS cliente_disse
      FROM pergunta_fila f
     WHERE f.estado IN ('fila', 'perguntada', 'agente')
  ), duvidas AS (
    SELECT 'duvida'::text, d.id, d.linha, d.estado, nullif(btrim(d.cliente_nome), ''), d.cliente_tel, d.codigo,
           (SELECT nai_ref_imovel(d.codigo) WHERE d.codigo IS NOT NULL), d.pergunta, nullif(btrim(d.resumo), ''), d.criada_em,
           (SELECT string_agg(x.texto, E'\n' ORDER BY x.criada_em) FROM (
              SELECT m.texto, m.criada_em FROM mensagens m
               WHERE nai_chave(m.telefone) = nai_chave(d.cliente_tel)
                 AND m.direcao = 'recebida' AND coalesce(btrim(m.texto), '') <> ''
                 AND m.criada_em BETWEEN d.perguntada_em - interval '40 minutes' AND d.perguntada_em + interval '2 minutes'
               ORDER BY m.criada_em DESC LIMIT 4) x)
      FROM privado.duvida d
     WHERE d.estado = 'com_o_tel' AND d.linha = 'parceria'
  )
  SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.criada_em), '[]'::jsonb)
    FROM (SELECT * FROM fila UNION ALL SELECT * FROM duvidas) t
$function$;
