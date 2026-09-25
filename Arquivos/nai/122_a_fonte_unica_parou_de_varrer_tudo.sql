-- =====================================================================
-- NAI -- 122: a fonte unica parou de varrer o banco inteiro (25/09/2026)
--
-- O Tel: "esta demorando horas para sair um simples teste". Nao era idle,
-- nao era a janela (ja estava em 3s) e nao era o eco (fica no ramo do Tel
-- pelo celular). MEDIDO, com a maquina livre:
--
--     nai_pedido_do_turno ......... 124 s   <-- o fluxo chama em todo turno
--       nai_tipo_da_conversa ...... 64,7 s  <-- e a fonte unica chama DUAS vezes
--       nai_negocio_da_conversa ...  0,096 s
--       nai_imoveis_pedidos .......  1,2 s
--       todo o resto .............. milissegundos
--
-- Com 11 turnos em paralelo em 2 CPUs, isso empilhou: 16 consultas ativas,
-- uma delas ha 17 minutos, load average 38. Dos 50 turnos abertos, 15
-- responderam. O resto morreu em "nao estabilizou em 180s".
--
-- A CULPA E DA 120b, minha. Ao fazer a oferta dele parar de ensinar o tipo,
-- eu troquei um `ORDER BY id DESC LIMIT 1` por duas varreduras -- 30 dias de
-- turno e 60 dias de mensagem -- com `nai_tipo_pedido()` chamada em CADA
-- linha do WHERE. Em 20.114 mensagens, sem indice que sirva, porque
-- `nai_chave(telefone)` e funcao sobre a coluna.
--
-- TRES CONSERTOS, e nenhum muda o que ela responde:
--
-- 1. INDICE por `nai_chave(telefone)`. A funcao e IMMUTABLE, entao da para
--    indexar. E o que tira a varredura de 20 mil linhas.
--
-- 2. A VARREDURA VIRA JANELA. Em vez de filtrar 30/60 dias chamando a
--    funcao em cada linha, pega as ULTIMAS 30 falas por id (indice) e so
--    entao aplica a regra. Muda o resultado? So se o tipo estivesse dito ha
--    mais de 30 falas atras e em nenhuma depois -- e ai ele ja nao valia.
--
-- 3. A FONTE UNICA CHAMA UMA VEZ SO. `tipo` e `rotulo` sao a mesma leitura;
--    estavam sendo calculados duas vezes, custo dobrado por nada.
-- =====================================================================

\set ON_ERROR_STOP on

-- O indice fora da transacao (CONCURRENTLY nao roda dentro de BEGIN) --
-- a tabela esta em uso e nao quero travar o fluxo enquanto ele responde.
CREATE INDEX CONCURRENTLY IF NOT EXISTS mensagens_chave_recebida
    ON mensagens (nai_chave(telefone), id DESC)
    WHERE direcao = 'recebida';

BEGIN;

-- ---- 2. a janela das ultimas falas -----------------------------------
CREATE OR REPLACE FUNCTION public.nai_tipo_da_conversa(p_contato bigint, p_texto text)
 RETURNS text LANGUAGE sql STABLE AS $function$
  SELECT nai_tipo_das_falas(
    array[coalesce(p_texto, '')]
    -- os ultimos 30 turnos dele (indice por contato_id, id)
    || coalesce((SELECT array_agg(x.texto ORDER BY x.id DESC) FROM (
         SELECT t.id, t.texto FROM nai_turno t
          WHERE t.contato_id = p_contato AND t.criado_em > now() - interval '30 days'
          ORDER BY t.id DESC LIMIT 30) x), '{}'::text[])
    -- e as ultimas 30 mensagens (indice `mensagens_chave_recebida`).
    -- Conversa antiga nunca virou turno: era la que estava "a casa do nova
    -- cidade ainda esta disponivel?" -- o (92) 98523-2884, em 11/09.
    || coalesce((SELECT array_agg(y.texto ORDER BY y.id DESC) FROM (
         SELECT m.id, m.texto FROM mensagens m
          WHERE nai_chave(m.telefone) = ANY (
                  SELECT c.chave FROM nai_contato c WHERE c.id = ANY (nai_contato_irmaos(p_contato)))
            AND m.direcao = 'recebida' AND m.criada_em > now() - interval '60 days'
          ORDER BY m.id DESC LIMIT 30) y), '{}'::text[]));
$function$;

CREATE OR REPLACE FUNCTION public.nai_negocio_da_conversa(p_contato bigint, p_texto text)
 RETURNS text LANGUAGE sql STABLE AS $function$
  SELECT nai_negocio_das_falas(
    array[coalesce(p_texto, '')]
    || coalesce((SELECT array_agg(x.texto ORDER BY x.id DESC) FROM (
         SELECT t.id, t.texto FROM nai_turno t
          WHERE t.contato_id = p_contato AND t.criado_em > now() - interval '24 hours'
          ORDER BY t.id DESC LIMIT 30) x), '{}'::text[]));
$function$;

-- ---- 3. a fonte unica le o tipo UMA vez -------------------------------
CREATE OR REPLACE FUNCTION public.nai_pedido_do_turno(p_turno bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  t nai_turno; k nai_contato; v_texto text; v_tipo text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN '{}'::jsonb; END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  v_texto := coalesce(t.texto, '');

  -- UMA leitura so: `rotulo` e o mesmo `tipo` por extenso. Estava sendo
  -- calculado duas vezes, e essa leitura e a cara da funcao inteira.
  v_tipo := nai_tipo_da_conversa(t.contato_id, v_texto);

  RETURN jsonb_build_object(
    'turno',      p_turno,
    'texto',      v_texto,
    'tipo',       v_tipo,
    'rotulo',     nai_rotulo_do_tipo(v_tipo),
    'negocio',    nai_negocio_da_conversa(t.contato_id, v_texto),
    'teto',       nay_maior_valor(v_texto),
    'imoveis',    to_jsonb(nai_imoveis_pedidos(v_texto, coalesce(k.telefone, ''))),
    'cortesia',   nai_e_so_cortesia(v_texto),
    'oferta',     nai_oferece_imovel(v_texto),
    'link',       nai_e_link_de_produto(v_texto),
    'pede_lista', nai_pede_os_valores(v_texto),
    'sem_bairro', nai_sem_preferencia_de_bairro(v_texto) OR nai_e_a_cidade(v_texto),
    'de_imovel',  nai_e_assunto_de_locacao(v_texto)
  );
END;
$function$;

COMMIT;

\timing on
\echo '=== DEPOIS: a mesma medida de antes ==='
SELECT nai_tipo_da_conversa((SELECT contato_id FROM nai_turno ORDER BY id DESC LIMIT 1), 'tem casa no tarum') AS tipo;
SELECT nai_pedido_do_turno((SELECT max(id) FROM nai_turno)) -> 'tipo' AS pela_fonte_unica;
\timing off

SELECT count(*) FILTER (WHERE passou) || ' de ' || count(*) AS bateria FROM nai_rodar_casos();
SELECT regra, esperado, deu FROM nai_rodar_casos() WHERE NOT passou;

-- =====================================================================
-- COMO DESFAZER
--   DROP INDEX CONCURRENTLY mensagens_chave_recebida;
-- e reaplicar a 120b (nai_tipo_da_conversa / nai_negocio_da_conversa) e a
-- 116 (nai_pedido_do_turno). Mas ai a fonte unica volta aos 124 s.
-- =====================================================================
