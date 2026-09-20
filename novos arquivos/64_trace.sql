-- =====================================================================
-- NAI -- 64: O TRACE. Cada execução, etapa por etapa, por SETOR.
--
-- Ele (19/09/2026): "quero um painel de logs para eu ver que caminho a ia
-- percorreu em cada execução para ficar fácil olhar os erros... quero dividir
-- ela em setores para ficar mais fácil identificar erros".
--
-- O QUE JÁ EXISTIA, e por que não bastava:
--   `nai_conferencia` (arquivo 15) grava as 17 conferências de cada turno. É
--   metade do caminho -- a metade DEPOIS do modelo falar. Não existe registro
--   de: o que chegou, o que foi mandado ao modelo, o que ele respondeu ANTES
--   da esteira, qual ferramenta ele chamou com quais argumentos, e quanto
--   tempo cada coisa levou. Quando o Tel diz "ela errou", essas quatro são
--   justamente as que respondem "onde".
--
-- O QUE ESTE ARQUIVO ACRESCENTA:
--   `nai_evento` -- uma linha por ETAPA de uma execução, com SETOR, resultado,
--   duração e o dado que entrou e saiu. Mais as views que o painel lê, e um
--   veredito por execução para a lista não precisar ser interpretada.
--
-- OS TRÊS PRINCÍPIOS (é por eles que isto pode ligar em produção):
--
--   1. O TRACE NUNCA DERRUBA O ATENDIMENTO. `nai_tracar` tem
--      `EXCEPTION WHEN others THEN RETURN NULL`. Se a tabela encher, se um
--      jsonb vier torto, se o disco acabar -- ela devolve NULL e a Nay
--      responde igual. Observabilidade que quebra produção é pior que
--      nenhuma.
--
--   2. SEM CHAVE ESTRANGEIRA para `nai_turno`, de propósito. Um FK aqui
--      criaria dois problemas: trace de etapa que roda ANTES do turno existir
--      (entrada, porta) não teria onde morar, e uma limpeza de `nai_turno`
--      passaria a travar ou a apagar o trace em cascata. O trace é um registro
--      histórico, não um dado relacional.
--
--   3. NADA DE CPF NEM TELEFONE INTEIRO. Todo jsonb passa por
--      `nai_mascarar`, que anda no documento e mexe SÓ em valor de texto --
--      número continua número, então o JSON nunca é corrompido.
--
-- ADITIVO: nenhuma função de atendimento é alterada aqui. Só CREATE
-- IF NOT EXISTS, CREATE OR REPLACE de coisa nova, ALTER ... ADD COLUMN
-- IF NOT EXISTS anulável, e GRANT. Rodar duas vezes é inofensivo.
--
-- ROLLBACK: `UPDATE nai_config SET valor='desligado' WHERE chave='trace_nivel';`
-- Isso apaga o trace na hora, sem deploy e sem reiniciar nada. As tabelas
-- podem ficar -- elas não são lidas por nenhuma função de atendimento.
-- =====================================================================


-- =====================================================================
-- 1. OS SETORES. É o vocabulário do painel inteiro.
-- =====================================================================
-- A ordem é a ordem em que uma mensagem atravessa o sistema. O painel
-- desenha a linha do tempo por ela, e o Tel lê "parou no setor X".
CREATE TABLE IF NOT EXISTS nai_setor (
  setor     text PRIMARY KEY,
  ordem     int  NOT NULL,
  titulo    text NOT NULL,
  descricao text
);

INSERT INTO nai_setor (setor, ordem, titulo, descricao) VALUES
 ('entrada',     10, 'Entrada',      'Webhook da Z-API, normalização, janela de espera, áudio e imagem viram texto.'),
 ('identidade',  20, 'Identidade',   'Quem é a pessoa: a chave (DDI+DDD+8), o @lid, juntar as duas linhas da mesma pessoa.'),
 ('porta',       30, 'Porta',        'Quem é atendido e quem não é. Corretor da lista, contato novo, Tel, proprietário.'),
 ('cabecalho',   40, 'Cabeçalho',    'Abre o turno: papel, visita, memória, PROMPT e o contexto que vai ao modelo.'),
 ('modelo',      50, 'Modelo',       'O agente decide. Aqui mora a resposta CRUA, antes de qualquer conferência.'),
 ('ferramenta',  60, 'Ferramentas',  'Que ferramenta ele chamou, com que argumentos, e o que ela devolveu.'),
 ('conferencia', 70, 'Conferência',  'A esteira das 17: o que passou, o que foi mudado, cortado ou parado.'),
 ('montagem',    80, 'Montagem',     'A resposta vira mensagem: card, fotos do card, as frases do sistema.'),
 ('saida',       90, 'Saída',        'A liberação e as travas: pausa, janela de horário, repetida, Tel assumiu, Z-API.'),
 ('agenda',     100, 'Agenda',       'Os ticks de minuto: cobranças, lembretes, visitas, senha, "como foi?".'),
 ('comando',    110, 'Comandos',     'Os comandos do Tel pelo WhatsApp: VISITAS, ACESSO, ASSUMIR, DEVOLVER.'),
 ('catalogo',   120, 'Catálogo',     'Imóveis, fotos e a varredura do site. Onde nasce o "não encontrei o imóvel".')
ON CONFLICT (setor) DO UPDATE
   SET ordem = EXCLUDED.ordem, titulo = EXCLUDED.titulo, descricao = EXCLUDED.descricao;

COMMENT ON TABLE nai_setor IS
  'Os 12 setores do caminho de uma mensagem, na ordem. Vocabulário do painel (Tel, 19/09).';

-- Usada na ordenação da trilha. STABLE e não IMMUTABLE porque lê tabela.
CREATE OR REPLACE FUNCTION nai_setor_ordem(p_setor text)
RETURNS int LANGUAGE sql STABLE AS $$
  SELECT coalesce((SELECT s.ordem FROM nai_setor s WHERE s.setor = p_setor), 999);
$$;


-- =====================================================================
-- 2. MASCARAMENTO. Anda no jsonb e mexe SÓ em texto.
-- =====================================================================
-- Por que não um regexp no jsonb inteiro serializado: `{"id": 559299998888}`
-- viraria `{"id": 5592***88}`, que NÃO é JSON válido -- o cast de volta
-- falharia e o payload inteiro se perderia. Então anda no documento.
--
-- A regra: qualquer corrida de 9+ dígitos vira os 4 primeiros + *** + os 2
-- últimos. Isso cobre telefone (12-13), CPF (11) e deixa em paz código de
-- imóvel (3-5), valor, hora e data (que têm separador).
CREATE OR REPLACE FUNCTION nai_mascarar_texto(p_texto text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT regexp_replace(coalesce(p_texto, ''), '(\d{4})\d{3,}(\d{2})', '\1***\2', 'g');
$$;

CREATE OR REPLACE FUNCTION nai_mascarar(p_j jsonb)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
BEGIN
  IF p_j IS NULL THEN RETURN NULL; END IF;
  RETURN CASE jsonb_typeof(p_j)
    WHEN 'string' THEN to_jsonb(nai_mascarar_texto(p_j #>> '{}'))
    WHEN 'object' THEN (SELECT coalesce(jsonb_object_agg(e.k, nai_mascarar(e.v)), '{}'::jsonb)
                          FROM jsonb_each(p_j) AS e(k, v))
    WHEN 'array'  THEN (SELECT coalesce(jsonb_agg(nai_mascarar(a.v) ORDER BY a.i), '[]'::jsonb)
                          FROM jsonb_array_elements(p_j) WITH ORDINALITY AS a(v, i))
    ELSE p_j END;
EXCEPTION WHEN others THEN
  -- Mascarar é proteção, não função de negócio: se falhar, devolve o original
  -- em vez de perder o trace. O risco é dado sensível no painel, não perda.
  RETURN p_j;
END;
$$;


-- =====================================================================
-- 3. A TABELA DE EVENTOS
-- =====================================================================
CREATE TABLE IF NOT EXISTS nai_evento (
  id        bigserial PRIMARY KEY,
  -- SEM FK para nai_turno (ver principio 2 no cabecalho). NULL = etapa que
  -- rodou antes do turno existir.
  turno_id  bigint,
  -- O id da execucao do n8n. E o fio que liga o painel ao n8n: com ele o Tel
  -- (ou quem investiga) abre a execucao exata la dentro.
  exec_id   text,
  seq       int  NOT NULL DEFAULT 0,
  setor     text NOT NULL,
  etapa     text NOT NULL,
  -- ok      = passou, nada a ver aqui
  -- mudou   = a etapa alterou o que estava passando
  -- cortou  = tirou parte
  -- parou   = interrompeu o caminho (ninguem recebe nada dali)
  -- erro    = quebrou
  resultado text NOT NULL DEFAULT 'ok'
              CHECK (resultado IN ('ok','mudou','cortou','parou','erro')),
  ms        int,
  entrada   jsonb,
  saida     jsonb,
  detalhe   text,
  criado_em timestamptz NOT NULL DEFAULT now()
);

-- A trilha de uma execucao (a consulta que o painel mais faz).
CREATE INDEX IF NOT EXISTS nai_evento_turno ON nai_evento (turno_id, seq, id);
-- A lista de execucoes, mais recentes primeiro.
CREATE INDEX IF NOT EXISTS nai_evento_quando ON nai_evento (criado_em DESC);
-- A saude por setor. PARCIAL: so o que nao esta ok -- e o que o painel
-- pergunta, e o indice fica uma fracao do tamanho.
CREATE INDEX IF NOT EXISTS nai_evento_problema
  ON nai_evento (setor, criado_em DESC) WHERE resultado <> 'ok';
CREATE INDEX IF NOT EXISTS nai_evento_exec
  ON nai_evento (exec_id) WHERE exec_id IS NOT NULL;

COMMENT ON TABLE nai_evento IS
  'Uma linha por etapa de uma execucao da NAI, com setor e duracao. O painel de trace le daqui (Tel, 19/09).';


-- =====================================================================
-- 4. O CARIMBO NO TURNO
-- =====================================================================
-- Aditivo e anulavel: o INSERT de `nai_abrir_turno` lista as colunas, entao
-- ele nem enxerga as novas e nada quebra se este arquivo rodar antes do
-- fluxo ser atualizado.
ALTER TABLE nai_turno ADD COLUMN IF NOT EXISTS exec_id       text;
ALTER TABLE nai_turno ADD COLUMN IF NOT EXISTS prompt_versao int;
ALTER TABLE nai_turno ADD COLUMN IF NOT EXISTS modelo        text;
ALTER TABLE nai_turno ADD COLUMN IF NOT EXISTS ms_total      int;

COMMENT ON COLUMN nai_turno.prompt_versao IS
  'Versao de nai_prompt usada NESTE turno. Sem isto, "ela errou" nao diz qual prompt errou.';
COMMENT ON COLUMN nai_turno.modelo IS
  'Modelo que respondeu este turno. Trocar de modelo passa a ser mensuravel em vez de opinavel.';


-- =====================================================================
-- 5. CONFIGURAÇÃO (os interruptores, sem deploy)
-- =====================================================================
INSERT INTO nai_config (chave, valor, descricao) VALUES
 ('trace_nivel', 'completo',
  'TRACE. completo = grava toda etapa | problema = grava so o que nao foi ok (barato) | desligado = nao grava nada. Vale na hora.'),
 ('trace_dias', '30',
  'TRACE: por quantos dias o evento fica guardado. `nai_trace_limpar()` apaga o que passou disso.'),
 ('trace_payload', 'sim',
  'TRACE: sim = guarda o dado que entrou e saiu de cada etapa (jsonb). nao = guarda so setor/etapa/resultado/tempo.')
ON CONFLICT (chave) DO NOTHING;


-- =====================================================================
-- 6. nai_tracar -- O ÚNICO JEITO DE ESCREVER NO TRACE
-- =====================================================================
-- Nunca levanta exceção. Nunca. É chamada de dentro do caminho de resposta,
-- e um erro aqui calaria a Nay -- que é exatamente o problema que este
-- arquivo existe para diagnosticar.
CREATE OR REPLACE FUNCTION nai_tracar(
  p_turno     bigint,
  p_setor     text,
  p_etapa     text,
  p_resultado text    DEFAULT 'ok',
  p_entrada   jsonb   DEFAULT NULL,
  p_saida     jsonb   DEFAULT NULL,
  p_detalhe   text    DEFAULT NULL,
  p_ms        int     DEFAULT NULL,
  p_exec      text    DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
  v_nivel   text;
  v_res     text := coalesce(nullif(btrim(p_resultado), ''), 'ok');
  v_seq     int;
  v_payload boolean;
  v_id      bigint;
BEGIN
  v_nivel := nai_cfg('trace_nivel', 'completo');
  IF v_nivel = 'desligado' THEN RETURN NULL; END IF;
  -- Modo barato: só o que deu problema. Serve para deixar ligado para sempre
  -- sem a tabela crescer.
  IF v_nivel = 'problema' AND v_res = 'ok' THEN RETURN NULL; END IF;
  -- Resultado fora do vocabulário não recusa o evento: vira 'erro' e o
  -- detalhe guarda o que veio. Trace que recusa dado é trace que mente.
  IF v_res NOT IN ('ok','mudou','cortou','parou','erro') THEN
    p_detalhe := coalesce(p_detalhe || ' | ', '') || 'resultado recebido: ' || v_res;
    v_res := 'erro';
  END IF;

  v_payload := nai_cfg('trace_payload', 'sim') = 'sim';

  -- A sequência é por turno. Duas inserções no MESMO turno em paralelo podem
  -- repetir o número -- na prática um turno é serial, e o `id` desempata na
  -- ordenação, então não vale travar linha por isso.
  IF p_turno IS NULL THEN
    v_seq := 0;
  ELSE
    SELECT coalesce(max(e.seq), 0) + 1 INTO v_seq FROM nai_evento e WHERE e.turno_id = p_turno;
  END IF;

  INSERT INTO nai_evento (turno_id, exec_id, seq, setor, etapa, resultado, ms,
                          entrada, saida, detalhe)
  VALUES (p_turno,
          nullif(btrim(coalesce(p_exec, '')), ''),
          v_seq,
          left(coalesce(nullif(btrim(p_setor), ''), 'entrada'), 40),
          left(coalesce(nullif(btrim(p_etapa), ''), '(sem nome)'), 120),
          v_res,
          p_ms,
          CASE WHEN v_payload THEN nai_mascarar(p_entrada) END,
          CASE WHEN v_payload THEN nai_mascarar(p_saida) END,
          left(p_detalhe, 2000))
  RETURNING id INTO v_id;
  RETURN v_id;
EXCEPTION WHEN others THEN
  -- O atendimento continua. Sempre.
  RETURN NULL;
END;
$$;

COMMENT ON FUNCTION nai_tracar(bigint,text,text,text,jsonb,jsonb,text,int,text) IS
  'Grava uma etapa no trace. NUNCA levanta excecao -- falha em silencio para nao derrubar o atendimento.';


-- =====================================================================
-- 7. OS ATALHOS QUE O FLUXO DO n8n CHAMA
-- =====================================================================
-- Um nó do n8n não deve montar jsonb à mão: o `queryReplacement` do Postgres
-- divide texto por vírgula (o CLAUDE.md documenta isso mordendo o projeto
-- inteiro). Então cada nó chama uma função com argumentos simples, e é o
-- Postgres que monta o jsonb.

-- 7.1 A RESPOSTA CRUA DO MODELO, antes da esteira. O buraco mais importante:
-- hoje `nai_conferir_resposta` recebe o texto do modelo, usa, e não guarda.
-- Quando a resposta sai errada, ninguém sabe se foi o modelo ou a esteira.
CREATE OR REPLACE FUNCTION nai_tracar_modelo(
  p_turno       bigint,
  p_texto_cru   text,
  p_ferramentas text    DEFAULT NULL,   -- nomes separados por vírgula
  p_modelo      text    DEFAULT NULL,
  p_ms          int     DEFAULT NULL,
  p_exec        text    DEFAULT NULL,
  p_tokens_in   int     DEFAULT NULL,
  p_tokens_out  int     DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_id bigint;
BEGIN
  UPDATE nai_turno
     SET modelo  = coalesce(p_modelo, modelo),
         exec_id = coalesce(nullif(btrim(coalesce(p_exec,'')),''), exec_id)
   WHERE id = p_turno;

  v_id := nai_tracar(
    p_turno, 'modelo', 'resposta_crua',
    CASE WHEN coalesce(btrim(p_texto_cru), '') = '' THEN 'parou' ELSE 'ok' END,
    NULL,
    jsonb_build_object(
      'texto_cru',   p_texto_cru,
      'ferramentas', string_to_array(coalesce(p_ferramentas, ''), ','),
      'tokens_entrada', p_tokens_in,
      'tokens_saida',   p_tokens_out),
    CASE WHEN coalesce(btrim(p_texto_cru), '') = ''
         THEN 'o modelo nao devolveu texto'
         ELSE length(p_texto_cru) || ' caracteres' END,
    p_ms, p_exec);
  RETURN v_id;
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$$;

-- 7.2 O CABEÇALHO: o prompt e o contexto EXATOS que foram ao modelo.
-- Guarda o tamanho e um resumo, não o prompt inteiro em cada turno -- ele tem
-- 9,5 KB e repetir isso em 400 turnos por dia é 3,8 MB/dia de nada. A VERSÃO
-- é o que importa: com ela se sabe qual texto era, porque `nai_prompt_historico`
-- guarda todos.
CREATE OR REPLACE FUNCTION nai_tracar_cabecalho(
  p_turno    bigint,
  p_papel    text,
  p_prompt   text,
  p_contexto text,
  p_exec     text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_ver int; v_vazio boolean;
BEGIN
  v_vazio := coalesce(length(btrim(coalesce(p_prompt, ''))), 0) < 500;
  SELECT versao INTO v_ver FROM nai_prompt WHERE papel = p_papel;

  UPDATE nai_turno
     SET prompt_versao = v_ver,
         exec_id = coalesce(nullif(btrim(coalesce(p_exec,'')),''), exec_id)
   WHERE id = p_turno;

  RETURN nai_tracar(
    p_turno, 'cabecalho', 'prompt_e_contexto',
    -- Prompt curto ou ausente é ERRO, não aviso: significa que o agente está
    -- rodando com o texto de reserva de dentro do nó -- uma cópia velha, que
    -- ninguém versionou. É o achado de 19/09.
    CASE WHEN v_vazio THEN 'erro' ELSE 'ok' END,
    NULL,
    jsonb_build_object(
      'papel',            p_papel,
      'prompt_versao',    v_ver,
      'prompt_caracteres', length(coalesce(p_prompt, '')),
      'contexto',         p_contexto),
    CASE WHEN v_vazio
         THEN 'PROMPT VAZIO OU CURTO: o agente pode estar usando o texto de reserva do no'
         ELSE 'prompt v' || coalesce(v_ver::text, '?') || ', ' ||
              length(coalesce(p_prompt,'')) || ' chars' END,
    NULL, p_exec);
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$$;

-- 7.3 A ENTRADA: o que a Z-API entregou.
CREATE OR REPLACE FUNCTION nai_tracar_entrada(
  p_payload jsonb,
  p_exec    text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql AS $$
BEGIN
  RETURN nai_tracar(
    NULL, 'entrada', 'webhook_zapi', 'ok',
    p_payload, NULL,
    'chegou da Z-API', NULL, p_exec);
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$$;

-- 7.4 UMA FERRAMENTA: o que o modelo pediu e o que voltou.
CREATE OR REPLACE FUNCTION nai_tracar_ferramenta(
  p_turno       bigint,
  p_ferramenta  text,
  p_argumentos  jsonb,
  p_resultado   jsonb,
  p_ms          int  DEFAULT NULL,
  p_exec        text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql AS $$
BEGIN
  RETURN nai_tracar(
    p_turno, 'ferramenta', p_ferramenta,
    CASE WHEN p_resultado IS NULL OR p_resultado = 'null'::jsonb THEN 'parou' ELSE 'ok' END,
    p_argumentos, p_resultado,
    CASE WHEN p_resultado IS NULL OR p_resultado = 'null'::jsonb
         THEN 'a ferramenta nao devolveu nada' END,
    p_ms, p_exec);
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$$;

-- 7.5 UM ERRO de nó do n8n.
CREATE OR REPLACE FUNCTION nai_tracar_erro(
  p_turno bigint,
  p_setor text,
  p_etapa text,
  p_erro  text,
  p_exec  text DEFAULT NULL)
RETURNS bigint LANGUAGE plpgsql AS $$
BEGIN
  RETURN nai_tracar(p_turno, p_setor, p_etapa, 'erro', NULL, NULL,
                    left(coalesce(p_erro, 'erro sem mensagem'), 2000), NULL, p_exec);
EXCEPTION WHEN others THEN
  RETURN NULL;
END;
$$;


-- =====================================================================
-- 8. A TRILHA DE UMA EXECUÇÃO -- a consulta central do painel
-- =====================================================================
-- Junta as TRÊS fontes numa linha do tempo só:
--   * nai_evento      -- as etapas novas (entrada, cabeçalho, modelo, ferramentas)
--   * nai_conferencia -- as 17 conferências, que JÁ eram gravadas (arquivo 15)
--   * nai_saida       -- o que virou mensagem, e o que foi barrado
--
-- Não duplica nada e não exige migrar o que já existe: a conferência continua
-- escrevendo onde escreve, e aqui ela aparece no lugar certo da linha.
CREATE OR REPLACE FUNCTION nai_trilha(p_turno bigint)
RETURNS TABLE (
  setor       text,
  setor_ordem int,
  passo       int,
  etapa       text,
  resultado   text,
  ms          int,
  detalhe     text,
  entrada     jsonb,
  saida       jsonb,
  quando      timestamptz)
LANGUAGE sql STABLE AS $$
  WITH tudo AS (
    -- as etapas novas
    SELECT e.setor,
           e.seq                  AS passo,
           e.etapa,
           e.resultado,
           e.ms,
           e.detalhe,
           e.entrada,
           e.saida,
           e.criado_em            AS quando,
           e.id                   AS desempate
      FROM nai_evento e
     WHERE e.turno_id = p_turno

    UNION ALL

    -- AS ETAPAS QUE RODARAM ANTES DO TURNO EXISTIR.
    -- O webhook e a porta acontecem antes de `nai_abrir_turno`, então não têm
    -- turno para apontar -- e sem este trecho o setor "Entrada" apareceria
    -- SEMPRE VAZIO no painel, que é justamente a primeira coisa que alguém
    -- abre quando a Nay não respondeu. O fio é o `exec_id` do n8n.
    SELECT e.setor,
           e.seq                  AS passo,
           e.etapa,
           e.resultado,
           e.ms,
           e.detalhe,
           e.entrada,
           e.saida,
           e.criado_em            AS quando,
           e.id                   AS desempate
      FROM nai_evento e
     WHERE e.turno_id IS NULL
       AND e.exec_id IS NOT NULL
       AND e.exec_id = (SELECT t.exec_id FROM nai_turno t WHERE t.id = p_turno)

    UNION ALL

    -- a esteira que ja existia (arquivo 15)
    SELECT 'conferencia'          AS setor,
           c.ordem                AS passo,
           c.etapa,
           CASE c.resultado WHEN 'passou' THEN 'ok' ELSE c.resultado END AS resultado,
           NULL::int              AS ms,
           c.detalhe,
           NULL::jsonb            AS entrada,
           NULL::jsonb            AS saida,
           c.criado_em            AS quando,
           c.id                   AS desempate
      FROM nai_conferencia c
     WHERE c.turno_id = p_turno

    UNION ALL

    -- o que saiu (ou nao saiu)
    SELECT 'saida'                AS setor,
           s.ordem                AS passo,
           s.tipo || coalesce(' · ' || s.motivo, '') AS etapa,
           CASE s.estado
             WHEN 'bloqueado' THEN 'parou'
             WHEN 'erro'      THEN 'erro'
             ELSE 'ok' END       AS resultado,
           NULL::int              AS ms,
           CASE WHEN s.estado = 'bloqueado'
                THEN 'BARRADA: ' || coalesce(s.bloqueio, 'sem motivo gravado')
                ELSE s.estado || coalesce(' · imovel ' || s.codigo, '') END AS detalhe,
           NULL::jsonb            AS entrada,
           jsonb_build_object('texto', s.texto, 'imagem', s.imagem_url,
                              'estado', s.estado, 'destino', s.papel_destino) AS saida,
           coalesce(s.enviado_em, s.criado_em) AS quando,
           s.id                   AS desempate
      FROM nai_saida s
     WHERE s.turno_id = p_turno
  )
  SELECT t.setor,
         nai_setor_ordem(t.setor) AS setor_ordem,
         t.passo,
         t.etapa,
         t.resultado,
         t.ms,
         t.detalhe,
         nai_mascarar(t.entrada),
         nai_mascarar(t.saida),
         t.quando
    FROM tudo t
   ORDER BY nai_setor_ordem(t.setor), t.passo, t.desempate;
$$;

COMMENT ON FUNCTION nai_trilha(bigint) IS
  'A linha do tempo de UMA execucao, por setor: evento + conferencia + saida numa consulta (Tel, 19/09).';


-- =====================================================================
-- 9. A LISTA DE EXECUÇÕES, com VEREDITO
-- =====================================================================
-- O veredito existe para a lista não precisar ser interpretada. O Tel abre o
-- painel e vê "muda", "barrada", "erro" -- e clica só nessas.
--
-- A ordem dos CASE é a ordem de gravidade: erro ganha de muda, muda ganha de
-- barrada, barrada ganha de corrigida.
CREATE OR REPLACE VIEW vw_nai_execucoes AS
WITH ev AS (
  SELECT turno_id,
         count(*) FILTER (WHERE resultado = 'erro')  AS erros,
         count(*) FILTER (WHERE resultado = 'parou') AS paradas,
         max(CASE WHEN resultado = 'erro' THEN detalhe END) AS primeiro_erro,
         sum(ms)                                     AS ms_soma,
         max(exec_id)                                AS exec_id,
         string_agg(DISTINCT setor, ',') FILTER (WHERE resultado <> 'ok') AS setores_com_problema
    FROM nai_evento GROUP BY turno_id
),
sd AS (
  SELECT turno_id,
         count(*) FILTER (WHERE tipo = 'texto'  AND estado IN ('enviado','simulado')) AS textos,
         count(*) FILTER (WHERE tipo = 'imagem' AND estado IN ('enviado','simulado')) AS fotos,
         count(*) FILTER (WHERE estado = 'bloqueado')                                AS barradas,
         count(*) FILTER (WHERE estado = 'erro')                                     AS erros_envio,
         string_agg(DISTINCT bloqueio, ', ') FILTER (WHERE estado = 'bloqueado')      AS motivos_barrada,
         min(enviado_em)                                                             AS primeira_saida
    FROM nai_saida GROUP BY turno_id
),
cf AS (
  SELECT turno_id,
         count(*) FILTER (WHERE resultado = 'parou')              AS conf_parou,
         count(*) FILTER (WHERE resultado IN ('mudou','cortou'))  AS conf_mexeu,
         string_agg(etapa, ', ' ORDER BY ordem) FILTER (WHERE resultado <> 'passou') AS conf_agiram
    FROM nai_conferencia GROUP BY turno_id
)
SELECT t.id                                        AS turno,
       t.criado_em                                 AS quando,
       t.papel,
       t.porta,
       t.codigo                                    AS imovel,
       t.teste,
       t.modelo,
       t.prompt_versao,
       coalesce(t.exec_id, ev.exec_id)             AS exec_id,
       k.nome_whatsapp                             AS quem,
       left(coalesce(t.texto, ''), 160)            AS ele_disse,
       coalesce(t.ferramentas, '{}')               AS ferramentas,
       coalesce(sd.textos, 0)                      AS textos,
       coalesce(sd.fotos, 0)                       AS fotos,
       coalesce(sd.barradas, 0)                    AS barradas,
       sd.motivos_barrada,
       cf.conf_agiram,
       ev.setores_com_problema,
       ev.primeiro_erro,
       coalesce(t.ms_total, ev.ms_soma)            AS ms_total,
       EXTRACT(epoch FROM (sd.primeira_saida - t.criado_em))::int AS seg_ate_responder,
       -- ------------------------------------------------ o veredito
       CASE
         WHEN coalesce(ev.erros, 0) > 0 OR coalesce(sd.erros_envio, 0) > 0 THEN 'erro'
         WHEN coalesce(sd.textos, 0) = 0 AND coalesce(sd.fotos, 0) = 0
              AND coalesce(sd.barradas, 0) = 0                             THEN 'muda'
         WHEN coalesce(sd.barradas, 0) > 0 AND coalesce(sd.textos, 0) = 0   THEN 'barrada'
         WHEN coalesce(cf.conf_parou, 0) > 0                               THEN 'parada'
         WHEN coalesce(cf.conf_mexeu, 0) > 0                               THEN 'corrigida'
         ELSE 'ok'
       END                                         AS veredito
  FROM nai_turno t
  LEFT JOIN nai_contato k ON k.id = t.contato_id
  LEFT JOIN ev ON ev.turno_id = t.id
  LEFT JOIN sd ON sd.turno_id = t.id
  LEFT JOIN cf ON cf.turno_id = t.id;

COMMENT ON VIEW vw_nai_execucoes IS
  'Uma linha por execucao, com veredito (ok/corrigida/parada/barrada/muda/erro). A lista do painel (Tel, 19/09).';


-- =====================================================================
-- 10. A SAÚDE POR SETOR -- "identificar os setores para corrigir"
-- =====================================================================
-- Esta é a tela que o Tel pediu em uma frase: qual setor está doendo.
-- Cruza as três fontes de novo, mas agregado por setor e por dia.
CREATE OR REPLACE VIEW vw_nai_setor_saude AS
WITH base AS (
  SELECT setor, resultado, criado_em FROM nai_evento
  UNION ALL
  SELECT 'conferencia',
         CASE resultado WHEN 'passou' THEN 'ok' ELSE resultado END,
         criado_em
    FROM nai_conferencia
  UNION ALL
  SELECT 'saida',
         CASE estado WHEN 'bloqueado' THEN 'parou' WHEN 'erro' THEN 'erro' ELSE 'ok' END,
         coalesce(enviado_em, criado_em)
    FROM nai_saida
)
SELECT s.setor,
       s.ordem,
       s.titulo,
       s.descricao,
       count(b.*)                                             AS passagens,
       count(b.*) FILTER (WHERE b.resultado = 'erro')          AS erros,
       count(b.*) FILTER (WHERE b.resultado = 'parou')         AS paradas,
       count(b.*) FILTER (WHERE b.resultado IN ('mudou','cortou')) AS correcoes,
       round(100.0 * count(b.*) FILTER (WHERE b.resultado <> 'ok')
             / greatest(count(b.*), 1), 1)                     AS pct_problema,
       max(b.criado_em) FILTER (WHERE b.resultado <> 'ok')      AS ultimo_problema,
       -- Semáforo, com o critério explícito para ninguém adivinhar:
       --   vermelho = qualquer erro   | amarelo = >10% de nao-ok
       --   verde    = tudo ok         | cinza   = nunca passou nada por aqui
       CASE
         WHEN count(b.*) = 0 THEN 'cinza'
         WHEN count(b.*) FILTER (WHERE b.resultado = 'erro') > 0 THEN 'vermelho'
         WHEN 100.0 * count(b.*) FILTER (WHERE b.resultado <> 'ok')
              / greatest(count(b.*), 1) > 10 THEN 'amarelo'
         ELSE 'verde'
       END                                                     AS semaforo
  FROM nai_setor s
  LEFT JOIN base b ON b.setor = s.setor AND b.criado_em > now() - interval '7 days'
 GROUP BY s.setor, s.ordem, s.titulo, s.descricao
 ORDER BY s.ordem;

COMMENT ON VIEW vw_nai_setor_saude IS
  'Semaforo por setor nos ultimos 7 dias: onde esta doendo (Tel, 19/09).';


-- O detalhe de UM setor: as etapas dele, ordenadas pelo que mais dá problema.
CREATE OR REPLACE VIEW vw_nai_setor_etapas AS
WITH base AS (
  SELECT setor, etapa, resultado, detalhe, criado_em, turno_id FROM nai_evento
  UNION ALL
  SELECT 'conferencia', etapa,
         CASE resultado WHEN 'passou' THEN 'ok' ELSE resultado END,
         detalhe, criado_em, turno_id
    FROM nai_conferencia
)
SELECT setor,
       etapa,
       count(*)                                              AS passagens,
       count(*) FILTER (WHERE resultado <> 'ok')             AS agiu,
       count(*) FILTER (WHERE resultado = 'erro')            AS erros,
       count(*) FILTER (WHERE resultado = 'parou')           AS paradas,
       round(100.0 * count(*) FILTER (WHERE resultado <> 'ok')
             / greatest(count(*), 1), 1)                      AS pct_agiu,
       max(criado_em)                                         AS ultima_vez,
       max(criado_em) FILTER (WHERE resultado <> 'ok')         AS ultimo_problema,
       (array_agg(turno_id ORDER BY criado_em DESC)
          FILTER (WHERE resultado <> 'ok'))[1:5]              AS ultimos_turnos
  FROM base
 WHERE criado_em > now() - interval '30 days'
 GROUP BY setor, etapa
 ORDER BY setor, agiu DESC, passagens DESC;

COMMENT ON VIEW vw_nai_setor_etapas IS
  'Cada etapa de cada setor, com quantas vezes agiu e os ultimos turnos com problema (Tel, 19/09).';


-- =====================================================================
-- 11. LIMPEZA -- o trace não pode crescer para sempre
-- =====================================================================
-- Sem isto, `nai_evento` com payload cresce ~1 MB/dia no volume medido
-- (40 pessoas/dia) e ninguém percebe até o disco reclamar. Chamada pelo
-- mesmo cron de sempre; a retenção mora em `nai_config`.
CREATE OR REPLACE FUNCTION nai_trace_limpar(p_dias int DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_dias int; v_ev int; v_cf int;
BEGIN
  v_dias := coalesce(p_dias, nai_cfg_int('trace_dias', 30));
  IF v_dias < 2 THEN v_dias := 2; END IF;  -- piso: nunca apagar o dia de hoje

  DELETE FROM nai_evento WHERE criado_em < now() - (v_dias || ' days')::interval;
  GET DIAGNOSTICS v_ev = ROW_COUNT;
  -- A conferência é mais leve (não tem payload) e vale guardar mais tempo:
  -- é o histórico que mostra regra morta. 3x a retenção do evento.
  DELETE FROM nai_conferencia WHERE criado_em < now() - ((v_dias * 3) || ' days')::interval;
  GET DIAGNOSTICS v_cf = ROW_COUNT;

  RETURN jsonb_build_object('dias', v_dias, 'eventos_apagados', v_ev,
                            'conferencias_apagadas', v_cf);
END;
$$;


-- =====================================================================
-- 12. GRANTS -- o painel lê, e só lê
-- =====================================================================
-- Mesma role estreita do arquivo 17. Ela ganha SELECT nas views novas e nada
-- mais: não enxerga `nai_evento` cru (que tem payload), só o que as views
-- expõem já mascarado.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nay_site_nai') THEN
    EXECUTE 'GRANT SELECT ON vw_nai_execucoes, vw_nai_setor_saude, vw_nai_setor_etapas TO nay_site_nai';
    EXECUTE 'GRANT SELECT ON nai_setor TO nay_site_nai';
    EXECUTE 'GRANT EXECUTE ON FUNCTION nai_trilha(bigint) TO nay_site_nai';
    EXECUTE 'GRANT EXECUTE ON FUNCTION nai_setor_ordem(text) TO nay_site_nai';
    EXECUTE 'GRANT EXECUTE ON FUNCTION nai_mascarar(jsonb) TO nay_site_nai';
    EXECUTE 'GRANT EXECUTE ON FUNCTION nai_mascarar_texto(text) TO nay_site_nai';
  END IF;
END $$;
