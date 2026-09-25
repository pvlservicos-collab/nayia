-- =====================================================================
-- NAI -- 122b: as chaves do irmao, uma vez so (25/09/2026)
--
-- A 122 nao resolveu, e o EXPLAIN disse por que. O plano de
-- `nai_tipo_da_conversa`:
--
--   Index Scan Backward on mensagens ......... 11.721 linhas
--     -> Memoize (442 misses)
--        -> Index Scan on nai_contato
--           Filter: (id = ANY (nai_contato_irmaos($0)))   <-- AQUI
--           actual time=185 ms  loops=442
--
--   Execution Time: 84.307 ms  -> 84 SEGUNDOS
--
-- O Postgres empurrou `nai_contato_irmaos` para DENTRO do filtro, e a
-- chamou 442 vezes -- uma por telefone distinto varrido -- a 185 ms cada.
-- 442 x 185 ms = 82 s. O indice da 122 nao ajudava porque o lado direito
-- da comparacao nao era constante.
--
-- O CONSERTO: calcular as chaves do contato UMA vez, guardar num array, e
-- comparar com esse array. Ai o lado direito e constante, o indice
-- `mensagens_chave_recebida` serve, e a varredura de 11.721 linhas vira
-- busca direta.
--
-- Por isso a funcao vira plpgsql: em SQL puro o planejador inlina de novo
-- e volta tudo ao que era.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION public.nai_tipo_da_conversa(p_contato bigint, p_texto text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_chaves text[];
  v_falas  text[] := array[coalesce(p_texto, '')];
BEGIN
  -- as chaves do contato e dos irmaos dele (telefone e @lid), de uma vez
  SELECT coalesce(array_agg(c.chave), '{}'::text[]) INTO v_chaves
    FROM nai_contato c
   WHERE c.id = ANY (nai_contato_irmaos(p_contato)) AND c.chave IS NOT NULL;

  -- os ultimos 30 turnos dele
  v_falas := v_falas || coalesce((
    SELECT array_agg(x.texto ORDER BY x.id DESC) FROM (
      SELECT t.id, t.texto FROM nai_turno t
       WHERE t.contato_id = p_contato AND t.criado_em > now() - interval '30 days'
       ORDER BY t.id DESC LIMIT 30) x), '{}'::text[]);

  -- e as ultimas 30 mensagens. Conversa antiga nunca virou turno: era la
  -- que estava "a casa do nova cidade ainda esta disponivel?" -- o
  -- (92) 98523-2884, em 11/09.
  v_falas := v_falas || coalesce((
    SELECT array_agg(y.texto ORDER BY y.id DESC) FROM (
      SELECT m.id, m.texto FROM mensagens m
       WHERE nai_chave(m.telefone) = ANY (v_chaves)
         AND m.direcao = 'recebida'
         AND m.criada_em > now() - interval '60 days'
       ORDER BY m.id DESC LIMIT 30) y), '{}'::text[]);

  RETURN nai_tipo_das_falas(v_falas);
END;
$function$;

COMMIT;

\timing on
\echo '=== DEPOIS: era 84 s ==='
SELECT nai_tipo_da_conversa((SELECT contato_id FROM nai_turno ORDER BY id DESC LIMIT 1), 'tem casa no tarum') AS tipo;
\echo '=== e a fonte unica inteira: era 124 s ==='
SELECT nai_pedido_do_turno((SELECT max(id) FROM nai_turno)) -> 'tipo' AS pela_fonte_unica;
\timing off

SELECT count(*) FILTER (WHERE passou) || ' de ' || count(*) AS bateria FROM nai_rodar_casos();
SELECT regra, esperado, deu FROM nai_rodar_casos() WHERE NOT passou;

-- =====================================================================
-- COMO DESFAZER: reaplicar a 122 (versao em SQL puro). Volta aos 84 s.
-- =====================================================================
