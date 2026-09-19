-- =====================================================================
-- NAI -- 14: começar a conversa do zero, e o contexto que só vale DEPOIS
-- (Tel, 14/09/2026)
--
-- Ele: "sempre que eu for testar tem que vir zerado minha conversa como se fosse
-- um cliente, ela só vai ler contexto depois dela reconhecer o imóvel".
--
-- Antes disto, o "imóvel da conversa" olhava 48 horas para trás sem nenhum
-- marco: o teste de agora herdava o imóvel do teste anterior, e não dava para
-- testar a primeira mensagem de um cliente novo.
--
-- Agora existe um MARCO por contato (`nai_contato.zerado_em`). Tudo que é
-- contexto -- imóvel da conversa, "vocês já estão conversando", memória do
-- modelo -- só enxerga o que veio DEPOIS dele.
--
--   SELECT nai_zerar_conversa('5596991712835');   -- começa do zero
--
-- Nada é apagado: a memória antiga é ARQUIVADA (o session_id é renomeado) e as
-- mensagens continuam todas lá.
-- =====================================================================

ALTER TABLE nai_contato ADD COLUMN IF NOT EXISTS zerado_em timestamptz;
COMMENT ON COLUMN nai_contato.zerado_em IS
  'Marco do começo da conversa: nada anterior a isto conta como contexto (Tel, 14/09).';

CREATE OR REPLACE FUNCTION nai_zerar_conversa(p_telefone text)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_id bigint; v_chave text := nai_chave(p_telefone); n int; v_ts text;
BEGIN
  SELECT id INTO v_id FROM nai_contato WHERE chave = v_chave;
  IF v_id IS NULL THEN RETURN 'não achei esse número em nai_contato.'; END IF;
  v_ts := to_char(now(), 'YYYYMMDD-HH24MISS');

  UPDATE nai_contato
     SET zerado_em = now(),
         humano_assumiu_em = NULL, humano_motivo = NULL,
         visita_sugerida_em = NULL,
         liberado_em = NULL, liberado_motivo = NULL
   WHERE id = v_id;

  -- a memória do modelo é ARQUIVADA, nunca apagada
  UPDATE nai_memoria
     SET session_id = 'arquivo-' || v_ts || ':' || session_id
   WHERE session_id LIKE 'nai:%:' || v_id
      OR session_id LIKE 'nai:%:' || v_id || ':%';
  GET DIAGNOSTICS n = ROW_COUNT;

  RETURN 'conversa zerada: o contexto começa agora, ' || n || ' mensagens de memória arquivadas.';
END;
$$;

-- O IMÓVEL DA CONVERSA, agora respeitando o marco. Mesma ordem de antes:
-- 1) o código que ELE escreveu agora; 2) o nome do condomínio entre os que
-- estiveram na mesa; 3) o imóvel do último turno; 4) um único imóvel na mesa.
-- Tudo isso só olha o que veio DEPOIS de `zerado_em`.
CREATE OR REPLACE FUNCTION nai_imovel_da_conversa(p_contato bigint, p_texto text)
RETURNS int LANGUAGE plpgsql STABLE AS $$
DECLARE
  k       nai_contato;
  q       text := lower(unaccent(coalesce(p_texto, '')));
  v_cod   int;
  v_cods  int[];
  v_desde timestamptz;
  v_seis  timestamptz;
  v_fim8  text;
  n       int;
BEGIN
  SELECT * INTO k FROM nai_contato WHERE id = p_contato;
  IF k.id IS NULL THEN RETURN NULL; END IF;
  v_fim8 := right(regexp_replace(k.telefone, '\D', '', 'g'), 8);
  v_desde := greatest(coalesce(k.zerado_em, now() - interval '48 hours'), now() - interval '48 hours');
  v_seis  := greatest(coalesce(k.zerado_em, now() - interval '6 hours'), now() - interval '6 hours');

  -- 1. o que ELE escreveu agora vale mais que tudo
  SELECT x::int INTO v_cod
    FROM unnest(coalesce(nay_codigos_citados(coalesce(p_texto, '')), '{}'::text[])) x
   WHERE x ~ '^[0-9]{3,5}$' AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = x::int)
   LIMIT 1;
  IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;

  -- 2. o que esteve na mesa DESDE o marco: card que ela mandou, card que ele
  --    colou, código que ele escreveu antes, envio do publicador, e o imóvel
  --    que um turno já tratou.
  SELECT coalesce(array_agg(DISTINCT c), '{}') INTO v_cods FROM (
    SELECT s.codigo AS c FROM nai_saida s
     WHERE s.contato_id = p_contato AND s.codigo IS NOT NULL AND s.criado_em > v_desde
    UNION ALL
    SELECT (regexp_matches(s.texto, 'C[óo]digo:\s*(\d{3,5})', 'gi'))[1]::int FROM nai_saida s
     WHERE s.contato_id = p_contato AND s.texto IS NOT NULL AND s.criado_em > v_desde
    UNION ALL
    SELECT t.codigo FROM nai_turno t
     WHERE t.contato_id = p_contato AND t.codigo IS NOT NULL AND t.criado_em > v_desde
    UNION ALL
    SELECT x::int FROM mensagens m
      CROSS JOIN LATERAL unnest(coalesce(nay_codigos_citados(coalesce(m.texto, '')), '{}'::text[])) x
     WHERE right(regexp_replace(m.telefone, '\D', '', 'g'), 8) = v_fim8
       AND m.direcao = 'recebida' AND m.criada_em > v_desde AND x ~ '^[0-9]{3,5}$'
    UNION ALL
    SELECT e.codigo::int FROM envios e
     WHERE right(regexp_replace(coalesce(e.telefone, ''), '\D', '', 'g'), 8) = v_fim8
       AND e.enviado_em > v_desde AND e.codigo ~ '^[0-9]{3,5}$'
  ) y WHERE c IS NOT NULL AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = y.c);

  IF coalesce(array_length(v_cods, 1), 0) = 0 THEN RETURN NULL; END IF;

  -- 3. ele chamou pelo NOME ("me manda foto do arezzo")
  IF btrim(q) <> '' THEN
    SELECT i.codigo INTO v_cod FROM imoveis i
     WHERE i.codigo = ANY (v_cods)
       AND coalesce(nai_condominio_ok(i.condominio_nome), '') <> ''
       AND position(lower(unaccent(split_part(nai_condominio_ok(i.condominio_nome), ' ', 1))) IN q) > 0
     LIMIT 1;
    IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;
  END IF;

  -- 4. o imóvel do ÚLTIMO turno que tratou de um imóvel: é dele que ele fala
  --    quando diz "dele", "desse", "e as fotos?".
  SELECT t.codigo INTO v_cod FROM nai_turno t
   WHERE t.contato_id = p_contato AND t.codigo IS NOT NULL AND t.criado_em > v_seis
   ORDER BY t.id DESC LIMIT 1;
  IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;

  -- 5. um único imóvel na mesa desde o marco (até 6h)
  SELECT count(DISTINCT c), min(c) INTO n, v_cod FROM (
    SELECT s.codigo AS c FROM nai_saida s
     WHERE s.contato_id = p_contato AND s.codigo IS NOT NULL AND s.criado_em > v_seis
    UNION ALL
    SELECT (regexp_matches(s.texto, 'C[óo]digo:\s*(\d{3,5})', 'gi'))[1]::int FROM nai_saida s
     WHERE s.contato_id = p_contato AND s.texto IS NOT NULL AND s.criado_em > v_seis
    UNION ALL
    SELECT x::int FROM mensagens m
      CROSS JOIN LATERAL unnest(coalesce(nay_codigos_citados(coalesce(m.texto, '')), '{}'::text[])) x
     WHERE right(regexp_replace(m.telefone, '\D', '', 'g'), 8) = v_fim8
       AND m.direcao = 'recebida' AND m.criada_em > v_seis AND x ~ '^[0-9]{3,5}$'
  ) y WHERE c IS NOT NULL;
  IF n = 1 THEN RETURN v_cod; END IF;

  -- 6. dois ou mais e sem nome: NULL -- ela pergunta, que é o certo.
  RETURN NULL;
END;
$$;

-- =====================================================================
-- A CITAÇÃO PRECISA OLHAR TAMBÉM O QUE A **NAI** MANDOU (Tel, 14/09)
--
-- Ele marcou o card que a Nay tinha mandado no privado e ela respondeu "de qual
-- imóvel o Sr. está falando?". Motivo: `nay_imovel_da_citacao` olhava `envios`
-- (publicador), `grupo_mensagens` (grupo) e a saída da Nay antiga -- mas NÃO
-- olhava `nai_saida`, que é onde ficam o card e as fotos que a NAI manda, com
-- o `message_id` da Z-API e o código do imóvel. Medido: 143 linhas de
-- `nai_saida` têm ID e código, e nenhuma delas resolvia.
-- =====================================================================
CREATE OR REPLACE FUNCTION nay_imovel_da_citacao(p_message_id text)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_id   text := NULLIF(btrim(coalesce(p_message_id,'')), '');
  v_cod  text;
  v_cods text[];
BEGIN
  IF v_id IS NULL THEN RETURN NULL; END IF;

  -- 1. o que o publicador mandou (grupo ou corretor)
  SELECT e.codigo INTO v_cod
    FROM envios e
   WHERE e.message_id = v_id
   ORDER BY e.enviado_em DESC
   LIMIT 1;
  IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;

  -- 2. o que a NAI mandou no privado: card, foto ou colagem
  SELECT s.codigo::text INTO v_cod
    FROM nai_saida s
   WHERE s.message_id = v_id AND s.codigo IS NOT NULL
   ORDER BY s.id DESC LIMIT 1;
  IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;

  -- 2b. card em texto da NAI: o código está dentro da mensagem. Dois códigos no
  --     mesmo texto não escolhem nada -- ela pergunta, com a lista.
  SELECT array_agg(DISTINCT m[1]) INTO v_cods
    FROM nai_saida s
    CROSS JOIN LATERAL regexp_matches(coalesce(s.texto, ''), 'C[óo]digo:\s*(\d{3,5})', 'gi') AS m
   WHERE s.message_id = v_id;
  IF coalesce(array_length(v_cods, 1), 0) = 1 THEN
    SELECT i.codigo::text INTO v_cod FROM imoveis i WHERE i.codigo::text = v_cods[1];
    IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;
  END IF;

  -- 3. card visto em grupo (inclusive o que o Tel posta pelo celular dele)
  SELECT g.codigo::text INTO v_cod
    FROM grupo_mensagens g
   WHERE g.message_id = v_id AND g.codigo IS NOT NULL
   LIMIT 1;
  IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;

  -- 4. a saída da Nay antiga
  v_cods := nay_codigos_da_saida(v_id);
  IF coalesce(array_length(v_cods,1),0) = 1 THEN
    SELECT i.codigo::text INTO v_cod FROM imoveis i WHERE i.codigo::text = v_cods[1];
    RETURN v_cod;
  END IF;

  RETURN NULL;
END;
$$;

-- =====================================================================
-- O ID DA MENSAGEM QUE CHEGA (Tel, 14/09)
--
-- Ele marcou uma mensagem e ouviu "de qual imóvel o Sr. está falando?". A
-- esteira mostrou "imovel_da_conversa -> nenhum imóvel identificado" com o
-- `citado_id` preenchido: o ID existia, mas não era de nada que a gente
-- conhecesse. Medido: 338 de 338 mensagens que a NAI manda guardam o ID, e a
-- tabela `mensagens` não tinha sequer coluna para o ID das que CHEGAM. Marcar
-- a própria mensagem -- o card que ele mesmo colou -- nunca teve como resolver.
-- =====================================================================
ALTER TABLE mensagens ADD COLUMN IF NOT EXISTS message_id text;
CREATE INDEX IF NOT EXISTS mensagens_message_id ON mensagens (message_id) WHERE message_id IS NOT NULL;
COMMENT ON COLUMN mensagens.message_id IS
  'ID da mensagem na Z-API. Guardado desde 14/09 para a citação resolver quando ele marca a própria mensagem.';

CREATE OR REPLACE FUNCTION nay_imovel_da_citacao(p_message_id text)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_id   text := NULLIF(btrim(coalesce(p_message_id,'')), '');
  v_cod  text;
  v_cods text[];
BEGIN
  IF v_id IS NULL THEN RETURN NULL; END IF;

  -- 1. o que o publicador mandou (grupo ou corretor)
  SELECT e.codigo INTO v_cod FROM envios e
   WHERE e.message_id = v_id ORDER BY e.enviado_em DESC LIMIT 1;
  IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;

  -- 2. o que a NAI mandou no privado: card, foto ou colagem
  SELECT s.codigo::text INTO v_cod FROM nai_saida s
   WHERE s.message_id = v_id AND s.codigo IS NOT NULL ORDER BY s.id DESC LIMIT 1;
  IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;

  -- 2b. card em texto da NAI: o código está dentro da mensagem
  SELECT array_agg(DISTINCT m[1]) INTO v_cods
    FROM nai_saida s
    CROSS JOIN LATERAL regexp_matches(coalesce(s.texto, ''), 'C[óo]digo:\s*(\d{3,5})', 'gi') AS m
   WHERE s.message_id = v_id;
  IF coalesce(array_length(v_cods, 1), 0) = 1 THEN
    SELECT i.codigo::text INTO v_cod FROM imoveis i WHERE i.codigo::text = v_cods[1];
    IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;
  END IF;

  -- 3. A MENSAGEM DELE (14/09): ele marcou o card que ele mesmo colou, ou uma
  --    mensagem dele que citava o código. Dois códigos no mesmo texto não
  --    escolhem nada -- ela pergunta, com a lista.
  SELECT array_agg(DISTINCT x) INTO v_cods
    FROM mensagens m
    CROSS JOIN LATERAL unnest(coalesce(nay_codigos_citados(coalesce(m.texto, '') || ' ' || coalesce(m.citado, '')), '{}'::text[])) x
   WHERE m.message_id = v_id AND x ~ '^[0-9]{3,5}$';
  IF coalesce(array_length(v_cods, 1), 0) = 1 THEN
    SELECT i.codigo::text INTO v_cod FROM imoveis i WHERE i.codigo::text = v_cods[1];
    IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;
  END IF;

  -- 4. card visto em grupo (inclusive o que o Tel posta pelo celular dele)
  SELECT g.codigo::text INTO v_cod FROM grupo_mensagens g
   WHERE g.message_id = v_id AND g.codigo IS NOT NULL LIMIT 1;
  IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;

  -- 5. a saída da Nay antiga
  v_cods := nay_codigos_da_saida(v_id);
  IF coalesce(array_length(v_cods,1),0) = 1 THEN
    SELECT i.codigo::text INTO v_cod FROM imoveis i WHERE i.codigo::text = v_cods[1];
    RETURN v_cod;
  END IF;

  RETURN NULL;
END;
$$;
