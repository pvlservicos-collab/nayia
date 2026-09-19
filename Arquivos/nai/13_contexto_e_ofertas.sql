-- =====================================================================
-- NAI -- 13: o imovel da conversa, valor x codigo, e o formato das ofertas
-- (Tel, 13/09/2026, depois do teste completo)
--
-- O que ele viu, na ordem:
--  1. "Quero saber se e mobiliado" -> subiu ao Tel. A pergunta nao tinha codigo
--     e o sistema so olhava o codigo DAQUELE turno: o imovel da conversa (as
--     fotos que ela acabara de mandar) ficava de fora.
--  2. "3500" -> "nao achei nenhum imovel com o codigo 3500". Ela tinha ACABADO
--     de perguntar a faixa de preco, e o roteador manda todo numero de 3 a 5
--     digitos para o caminho de codigo puro.
--  3. A lista de imoveis saiu em uma linha corrida, sem formato.
--  4. "Me manda foto do arezzo" -> "as fotos estao vindo" e nenhuma foto, e
--     depois o loop "de qual imovel?". O envio de foto so olhava codigo escrito
--     na resposta dela ou na fala dele; "arezzo" nao vira codigo.
--
-- O que segura: as funcoes abaixo. O fio comum e o CONTEXTO -- qual imovel esta
-- em cima da mesa nesta conversa -- que passa a ser resolvido pelo banco, nao
-- pela cabeca do modelo.
-- =====================================================================

ALTER TABLE nai_turno ADD COLUMN IF NOT EXISTS codigo int;
COMMENT ON COLUMN nai_turno.codigo IS
  'O imovel que este turno tratou. E o fio da conversa: a mensagem seguinte "me manda as fotos dele" fala DESTE (14/09).';

-- ------------------------------------------------------------------ contexto
-- O IMOVEL DESTA CONVERSA. Na ordem: o codigo que ELE escreveu; o condominio
-- que ele citou pelo nome entre os que ELA mandou; e, se so houver um imovel
-- na mesa nas ultimas 48h, esse. Com dois ou mais e sem nome, devolve NULL --
-- perguntar e melhor que mandar o imovel errado.
CREATE OR REPLACE FUNCTION nai_imovel_da_conversa(p_contato bigint, p_texto text)
RETURNS int LANGUAGE plpgsql STABLE AS $$
DECLARE
  k       nai_contato;
  q       text := lower(unaccent(coalesce(p_texto, '')));
  v_cod   int;
  v_cods  int[];
  v_rec   int[];
  v_fim8  text;
  n       int;
BEGIN
  SELECT * INTO k FROM nai_contato WHERE id = p_contato;
  IF k.id IS NULL THEN RETURN NULL; END IF;
  v_fim8 := right(regexp_replace(k.telefone, '\D', '', 'g'), 8);

  -- 1. o que ELE escreveu agora vale mais que tudo
  SELECT x::int INTO v_cod
    FROM unnest(coalesce(nay_codigos_citados(coalesce(p_texto, '')), '{}'::text[])) x
   WHERE x ~ '^[0-9]{3,5}$' AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = x::int)
   LIMIT 1;
  IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;

  -- 2. TUDO o que esteve na mesa nas ultimas 48h, venha de onde vier:
  --    o card que ELA mandou, o card que ELE colou, o codigo que ele escreveu
  --    antes, o que o publicador enviou e o imovel que o turno anterior tratou.
  --    (14/09: ela perguntava "de qual imovel?" logo depois de responder sobre
  --    o card que o proprio corretor tinha colado -- isto faltava.)
  SELECT coalesce(array_agg(DISTINCT c), '{}') INTO v_cods FROM (
    SELECT s.codigo AS c FROM nai_saida s
     WHERE s.contato_id = p_contato AND s.codigo IS NOT NULL
       AND s.criado_em > now() - interval '48 hours'
    UNION ALL
    SELECT (regexp_matches(s.texto, 'C[óo]digo:\s*(\d{3,5})', 'gi'))[1]::int FROM nai_saida s
     WHERE s.contato_id = p_contato AND s.texto IS NOT NULL
       AND s.criado_em > now() - interval '48 hours'
    UNION ALL
    SELECT t.codigo FROM nai_turno t
     WHERE t.contato_id = p_contato AND t.codigo IS NOT NULL
       AND t.criado_em > now() - interval '48 hours'
    UNION ALL
    SELECT x::int FROM mensagens m
      CROSS JOIN LATERAL unnest(coalesce(nay_codigos_citados(coalesce(m.texto, '')), '{}'::text[])) x
     WHERE right(regexp_replace(m.telefone, '\D', '', 'g'), 8) = v_fim8
       AND m.direcao = 'recebida' AND m.criada_em > now() - interval '48 hours'
       AND x ~ '^[0-9]{3,5}$'
    UNION ALL
    SELECT e.codigo::int FROM envios e
     WHERE right(regexp_replace(coalesce(e.telefone, ''), '\D', '', 'g'), 8) = v_fim8
       AND e.enviado_em > now() - interval '48 hours' AND e.codigo ~ '^[0-9]{3,5}$'
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

  -- 4. o imovel do ULTIMO turno que tratou de um imovel: e dele que ele fala
  --    quando diz "dele", "desse", "e as fotos?".
  SELECT t.codigo INTO v_cod FROM nai_turno t
   WHERE t.contato_id = p_contato AND t.codigo IS NOT NULL
     AND t.criado_em > now() - interval '6 hours'
   ORDER BY t.id DESC LIMIT 1;
  IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;

  -- 5. so um imovel na mesa nas ultimas 6h: e esse
  SELECT count(DISTINCT c), min(c) INTO n, v_cod FROM (
    SELECT s.codigo AS c FROM nai_saida s
     WHERE s.contato_id = p_contato AND s.codigo IS NOT NULL
       AND s.criado_em > now() - interval '6 hours'
    UNION ALL
    SELECT (regexp_matches(s.texto, 'C[óo]digo:\s*(\d{3,5})', 'gi'))[1]::int FROM nai_saida s
     WHERE s.contato_id = p_contato AND s.texto IS NOT NULL
       AND s.criado_em > now() - interval '6 hours'
    UNION ALL
    SELECT x::int FROM mensagens m
      CROSS JOIN LATERAL unnest(coalesce(nay_codigos_citados(coalesce(m.texto, '')), '{}'::text[])) x
     WHERE right(regexp_replace(m.telefone, '\D', '', 'g'), 8) = v_fim8
       AND m.direcao = 'recebida' AND m.criada_em > now() - interval '6 hours'
       AND x ~ '^[0-9]{3,5}$'
  ) y WHERE c IS NOT NULL;
  IF n = 1 THEN RETURN v_cod; END IF;

  -- 6. dois ou mais e sem nome: NULL -- ela pergunta, que e o certo.
  RETURN NULL;
END;
$$;

-- ------------------------------------------------------------------ valor x codigo
-- "3500" depois de "qual a faixa de preco?" e FAIXA DE PRECO, nao codigo. Isto
-- diz ao roteador que a ultima coisa que ela perguntou foi o valor.
CREATE OR REPLACE FUNCTION nai_esperando_valor(p_contato bigint)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM nai_saida s
     WHERE s.contato_id = p_contato AND s.tipo = 'texto'
       AND s.criado_em > now() - interval '2 hours'
       AND s.texto ~* '(faixa de pre|qual (o )?valor|ate quanto|teto de valor)'
       AND s.id = (SELECT max(s2.id) FROM nai_saida s2
                    WHERE s2.contato_id = p_contato AND s2.tipo = 'texto'));
$$;

-- ------------------------------------------------------------------ emoji
-- Tira o emoji da FALA dela (Tel, 13/09), mas preserva os simbolos que sao
-- formato nosso: o card do imovel e a lista de ofertas. Sem esta excecao, o
-- 🏢 e o 🏠 da lista sumiam junto com o 😉.
CREATE OR REPLACE FUNCTION nai_sem_emoji_resposta(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT btrim(translate(
           regexp_replace(regexp_replace(regexp_replace(
             translate(coalesce(p, ''), '🏢🏠📍🛏🚗💰📐🔑🔐', chr(1) || chr(2) || chr(3) || chr(4) || chr(5) || chr(6) || chr(7) || chr(14) || chr(15)),
             '[🀀-🫿☀-➿️‍]', '', 'g'),
             '[ \t]{2,}', ' ', 'g'),
             '[ \t]+$', '', 'gn'),
           chr(1) || chr(2) || chr(3) || chr(4) || chr(5) || chr(6) || chr(7) || chr(14) || chr(15), '🏢🏠📍🛏🚗💰📐🔑🔐'));
$$;

-- ------------------------------------------------------------------ oferta
-- UM imovel no formato que o Tel escreveu (13/09):
--   🏢 *Arezzo Residencial — Flores #5718*
--   • 2 quartos
--   • R$ 2.500/mês
--   • Mobiliado
-- (no WhatsApp o negrito e *assim*, com um asterisco so)
CREATE OR REPLACE FUNCTION nai_bloco_oferta(p_codigo int)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE i imoveis; v_tit text; v_ico text; v_mob text; v_l text[] := '{}';
BEGIN
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.codigo IS NULL THEN RETURN NULL; END IF;
  v_ico := CASE WHEN lower(coalesce(i.tipo, '')) ~ 'casa' THEN '🏠' ELSE '🏢' END;
  v_tit := CASE
    WHEN coalesce(nai_condominio_ok(i.condominio_nome), '') <> ''
      THEN nai_condominio_ok(i.condominio_nome) || coalesce(' — ' || nullif(i.bairro, ''), '')
    ELSE initcap(coalesce(nullif(i.tipo, ''), 'Imóvel')) || coalesce(' no bairro ' || nullif(i.bairro, ''), '') END;
  IF coalesce(i.quartos, 0) > 0 THEN
    v_l := v_l || ('• ' || i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END ||
                   CASE WHEN coalesce(i.suites, 0) > 0 THEN ', sendo ' || i.suites || CASE WHEN i.suites = 1 THEN ' suíte' ELSE ' suítes' END ELSE '' END);
  END IF;
  IF coalesce(i.valor_aluguel, 0) > 0 THEN
    v_l := v_l || ('• R$ ' || replace(to_char(i.valor_aluguel, 'FM999,999,990'), ',', '.') || '/mês');
  END IF;
  v_mob := CASE
    WHEN lower(coalesce(i.mobilia, '')) ~ '^semi' THEN 'Semimobiliado'
    WHEN lower(coalesce(i.mobilia, '')) ~ '^mobiliad' THEN 'Mobiliado'
    WHEN lower(coalesce(i.mobilia, '')) ~ 'ar.condicionado' THEN 'Com ar-condicionado'
    WHEN lower(unaccent(coalesce(array_to_string(i.caracteristicas, ', '), ''))) ~ 'semi.?mobiliad' THEN 'Semimobiliado'
    WHEN lower(unaccent(coalesce(array_to_string(i.caracteristicas, ', '), ''))) ~ 'mobiliad' THEN 'Mobiliado' END;
  IF v_mob IS NOT NULL THEN v_l := v_l || ('• ' || v_mob); END IF;
  RETURN v_ico || ' *' || v_tit || ' #' || i.codigo || '*' ||
         CASE WHEN array_length(v_l, 1) > 0 THEN E'\n' || array_to_string(v_l, E'\n') ELSE '' END;
END;
$$;
