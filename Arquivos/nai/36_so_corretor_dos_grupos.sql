-- =====================================================================
-- NAI -- 36: ela so fala com CORRETOR DOS GRUPOS (Tel, 18/09/2026)
--
-- Nas palavras dele: "pega todos os contatos dos grupos que eu estou e salva
-- como corretores ... voce so vai responder essas pessoas; se for uma pergunta
-- de imovel, de fotos, ela vai perguntar ao Tel se a pessoa e corretor, mas
-- isso vai acontecer poucas vezes. No geral so focar nos de grupo, e ela vai
-- atualizar semanalmente os contatos dos grupos como sendo os unicos contatos
-- que ela tem permissao para falar."
--
-- AS PECAS:
--   * `nai_grupo_corretor`   -- quais grupos contam. MOTO AGENTE nao conta:
--     la estao os motoboys, e marcar o Fernando como corretor quebraria o
--     papel dele. O Tel liga e desliga grupo pelo `incluir`.
--   * `corretores`           -- a tabela que a Nay JA usa para "corretor
--     aprovado". Ganha `pode_falar`, que e a lista de verdade.
--   * `nai_corretor_pergunta`-- quem ela ja perguntou ao Tel, e o que ele disse.
--   * `nai_sincronizar_grupos` -- recebe os membros lidos da Z-API (quem le e o
--     `sincronizar_grupos_corretores.py`, toda semana) e refaz a lista.
--   * a PORTA (`nai_deve_atender`, arquivo 36b) e os comandos CORRETOR /
--     NAO CORRETOR (36c).
--
-- A REGRA SO VALE PARA QUEM SERIA CORRETOR. Tel, equipe, motoboy e dono de
-- imovel com visita aberta passam direto: a porta roda para todo mundo, e sem
-- essa excecao a Nay pararia de confirmar visita com o proprietario.
--
-- DESLIGADA POR PADRAO: `nai_config.so_corretor_da_lista`. So liga depois da
-- primeira sincronizacao boa -- ligar com a lista vazia calaria a Nay inteira.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ---------------------------------------------------------------------
-- 1. QUAIS GRUPOS CONTAM
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nai_grupo_corretor (
  grupo_id   text PRIMARY KEY,
  nome       text,
  incluir    boolean NOT NULL DEFAULT true,
  membros    integer,
  visto_em   timestamptz,
  nota       text
);

COMMENT ON TABLE nai_grupo_corretor IS
  'Grupos de WhatsApp cujos membros viram corretores que a NAI pode atender. incluir=false tira o grupo da lista (ex.: MOTO AGENTE).';

-- ---------------------------------------------------------------------
-- 2. A LISTA -- colunas novas em `corretores`
--
-- `fonte` separa quem veio do grupo (a sincronizacao pode tirar, se a pessoa
-- saiu de todos) de quem o Tel pos a mao (a sincronizacao nunca tira).
-- ---------------------------------------------------------------------
ALTER TABLE corretores ADD COLUMN IF NOT EXISTS pode_falar  boolean NOT NULL DEFAULT false;
ALTER TABLE corretores ADD COLUMN IF NOT EXISTS fonte       text;
ALTER TABLE corretores ADD COLUMN IF NOT EXISTS grupos      text[];
ALTER TABLE corretores ADD COLUMN IF NOT EXISTS no_grupo_em timestamptz;

-- Quem ja estava na tabela: com origem de gente (Tel, ou sem origem) e a mao;
-- o resto veio da exportacao dos grupos de 13-14/09.
UPDATE corretores
   SET fonte = CASE WHEN origem IS NULL OR origem ~* '\mtel\M' THEN 'tel' ELSE 'grupo' END
 WHERE fonte IS NULL;

-- Os postos a mao ja podem falar desde agora: foram escolhidos pelo Tel.
UPDATE corretores SET pode_falar = true WHERE fonte = 'tel' AND aprovado AND ativo;

CREATE INDEX IF NOT EXISTS corretores_chave_idx ON corretores (nai_chave(telefone));

-- ---------------------------------------------------------------------
-- 3. O QUE ELA JA PERGUNTOU AO TEL
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nai_corretor_pergunta (
  chave         text PRIMARY KEY,
  telefone      text NOT NULL,
  nome          text,
  ultimo_texto  text,
  perguntado_em timestamptz NOT NULL DEFAULT now(),
  turno_id      bigint,
  decisao       text CHECK (decisao IN ('sim', 'nao')),
  decidido_em   timestamptz
);

COMMENT ON TABLE nai_corretor_pergunta IS
  'Quem escreveu para a NAI de fora da lista de corretores e ja foi perguntado ao Tel. decisao = resposta dele (CORRETOR / NAO CORRETOR).';

-- ---------------------------------------------------------------------
-- 4. O INTERRUPTOR -- desligado ate a primeira sincronizacao boa
-- ---------------------------------------------------------------------
INSERT INTO nai_config (chave, valor, descricao, atualizado_em)
VALUES ('so_corretor_da_lista', 'nao',
        'sim = a NAI so atende corretor dos grupos (corretores.pode_falar); fora da lista, se perguntar de imovel, ela pergunta ao Tel. Ligar so depois da 1a sincronizacao.',
        now())
ON CONFLICT (chave) DO NOTHING;

-- ---------------------------------------------------------------------
-- 5. PODE FALAR?
--
-- Resolve @lid pelo `identidade_lid` -- a sincronizacao grava o LID de cada
-- membro, justamente para a mensagem que chega so com LID casar. A decisao do
-- Tel vale mais que o grupo: NAO CORRETOR cala mesmo quem esta num grupo.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_pode_falar(p_chave text, p_telefone text)
RETURNS boolean LANGUAGE sql STABLE AS $$
  WITH alvo AS (
    SELECT coalesce(
             (SELECT nai_chave(i.telefone) FROM identidade_lid i
               WHERE p_chave ~ '^lid:' AND i.lid = p_telefone LIMIT 1),
             p_chave) AS chave
  )
  SELECT NOT EXISTS (SELECT 1 FROM nai_corretor_pergunta q, alvo
                      WHERE q.chave = alvo.chave AND q.decisao = 'nao')
     AND EXISTS (SELECT 1 FROM corretores c, alvo
                  WHERE nai_chave(c.telefone) = alvo.chave
                    AND c.pode_falar AND c.ativo);
$$;

-- ---------------------------------------------------------------------
-- 6. A LISTA GOVERNA ESTA PESSOA?
--
-- So quem seria tratado como corretor. Repete as mesmas perguntas que o
-- `nai_abrir_turno` faz para dar outro papel -- e na duvida, isenta: deixar
-- passar um proprietario e barato, calar um proprietario no meio de uma
-- visita nao e.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_lista_governa(p_chave text, p_contato bigint)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT NOT (
       p_chave = nai_chave(nai_cfg('tel_telefone'))
    OR nai_pode_comandar(p_chave)
    OR nai_e_motoboy(p_chave)
    OR EXISTS (SELECT 1 FROM equipe e WHERE nai_chave(e.telefone) = p_chave)
    OR (p_contato IS NOT NULL AND EXISTS (
          SELECT 1 FROM nai_visita x
           WHERE x.proprietario_id = p_contato AND nai_visita_aberta(x.estado)))
    -- quem ela ja tratou como proprietario, motoboy ou Tel nao e corretor
    OR (p_contato IS NOT NULL AND EXISTS (
          SELECT 1 FROM nai_saida s
           WHERE s.contato_id = p_contato
             AND s.papel_destino IN ('proprietario', 'motoboy', 'tel')))
  );
$$;

-- ---------------------------------------------------------------------
-- 7. A PERGUNTA E DE IMOVEL?
--
-- As mesmas pistas que a porta ja usa para abrir conversa -- nenhuma nova.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_pergunta_de_imovel(p_texto text, p_telefone text, p_codigo_citado integer)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT p_codigo_citado IS NOT NULL
      OR nai_assunto_de_corretor(p_texto)
      OR coalesce((nai_pedido_de_perfil(p_texto)->>'e_pedido')::boolean, false)
      OR nai_pede_foto(p_texto)
      OR coalesce(array_length(nai_imovel_pelo_condominio(p_texto, p_telefone), 1), 0) > 0
      OR EXISTS (SELECT 1 FROM unnest(coalesce(nay_codigos_citados(coalesce(p_texto, '')), '{}'::text[])) x
                  WHERE x ~ '^[0-9]{3,5}$');
$$;

-- ---------------------------------------------------------------------
-- 8. A SINCRONIZACAO
--
-- Recebe [{grupo_id, nome, membros:[{phone, lid}]}] e:
--   a) grava o grupo (novo grupo entra com incluir = true, menos os que
--      claramente nao sao de corretor, que ja vem marcados);
--   b) quem esta num grupo INCLUIDO vira corretor aprovado, pode_falar;
--   c) grava LID -> telefone para a mensagem que chega so com LID;
--   d) SO SE p_revogar: quem veio de grupo e nao apareceu em nenhum perde o
--      pode_falar. O script so pede revogar quando TODOS os grupos foram
--      lidos sem erro -- uma leitura pela metade nao pode calar metade da lista.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_sincronizar_grupos(p_grupos jsonb, p_revogar boolean)
RETURNS jsonb LANGUAGE plpgsql AS $$
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
$$;

-- ---------------------------------------------------------------------
-- 9. OS GRUPOS QUE NAO SAO DE CORRETOR -- ja entram desligados
--
-- MOTO AGENTE sao os motoboys. Os outros tres tem cara de grupo interno ou de
-- teste. O Tel liga qualquer um com UPDATE ... SET incluir = true.
-- ---------------------------------------------------------------------
INSERT INTO nai_grupo_corretor (grupo_id, nome, incluir, nota) VALUES
  ('120363419289053320-group', 'MOTO AGENTE', false, 'motoboys, nao corretores'),
  ('120363423961336890-group', '39234t7', false, 'parece grupo de teste'),
  ('120363410110464366-group', 'Altarquia Imob easy AI a sinistra do mercado', false, 'parece grupo interno'),
  ('120363404836314828-group', 'Catálogo de imóveis', false, 'parece catalogo interno, nao grupo de corretor')
ON CONFLICT (grupo_id) DO UPDATE SET incluir = EXCLUDED.incluir, nota = EXCLUDED.nota;

COMMIT;
