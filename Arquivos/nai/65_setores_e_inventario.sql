-- =====================================================================
-- NAI -- 65: O INVENTÁRIO POR SETOR. Que função é regra viva, e o que é resto.
--
-- Ele (19/09/2026): "essa ia já foi refeita muitas vezes então pode ter
-- arquivos antigos de regras antigas atrapalhando... quero dividir ela em
-- setores para ficar mais fácil identificar erros".
--
-- O PROBLEMA MEDIDO EM 19/09:
--   * 284 funções no banco: 148 `nai_` (a IA nova), 89 `nay_` (a antiga), 47 outras.
--   * 22 funções da NAI chamam funções da Nay ANTIGA -- decisão da IA nova
--     tomada com o cérebro da IA velha, moldado por bugs de um fluxo que não
--     existe mais.
--   * NENHUMA tabela de migração. Nenhum registro de qual `.sql` foi aplicado.
--     `nai_liberar_saida` foi corrigida em produção em 16/09 e nunca voltou ao
--     repositório -- e o próprio repositório sabe disso: o arquivo 37, linha 18,
--     diz com todas as letras "o banco estava a frente do repositorio".
--
--   Alguém já notou, anotou, e continuou acontecendo. Porque anotar não é
--   mecanismo. Este arquivo é o mecanismo.
--
-- O QUE ELE FAZ:
--   1. Classifica CADA função num dos 12 setores, por REGRA EDITÁVEL (tabela,
--      não CASE no código -- quem discordar corrige com UPDATE, sem deploy).
--   2. Tira uma FOTO do estado atual (nome, assinatura, md5 do corpo). A partir
--      dela, "o banco está à frente" para de ser folclore e vira uma lista de
--      nomes que divergiram, com data.
--   3. Mostra o ACOPLAMENTO `nai_` -> `nay_` como view viva, não como relatório
--      de uma tarde.
--   4. Mostra as ÓRFÃS -- e deixa registrado quem é chamado de fora do banco
--      (n8n, cron, painel), porque "nenhuma função chama" não é "morta".
--
-- SOMENTE LEITURA SOBRE O ATENDIMENTO: este arquivo não altera nenhuma função
-- `nai_*` nem `nay_*`. Só cria tabelas novas, views e funções de inspeção.
-- Rodar duas vezes é inofensivo.
-- =====================================================================


-- =====================================================================
-- 1. AS REGRAS DE CLASSIFICAÇÃO -- dado, não código
-- =====================================================================
-- Por que tabela e não um CASE gigante dentro de uma função: a classificação é
-- OPINIÃO, e vai mudar. Numa função, mudar de opinião é deploy. Numa tabela, é
-- UPDATE -- o mesmo princípio que já vale para o prompt e para `nai_config`.
--
-- A `ordem` decide: a primeira regra que casar ganha. Regra específica tem
-- número baixo; a genérica por prefixo fica no fim.
CREATE TABLE IF NOT EXISTS nai_setor_regra (
  id       serial PRIMARY KEY,
  ordem    int  NOT NULL,
  padrao   text NOT NULL,          -- regex, aplicado ao nome da função
  setor    text NOT NULL REFERENCES nai_setor(setor),
  porque   text
);
CREATE INDEX IF NOT EXISTS nai_setor_regra_ordem ON nai_setor_regra (ordem);

-- Semente. Tirada da leitura dos 84 arquivos de `Arquivos/nai/` e do mapa dos
-- 69 nós do fluxo. Onde eu não tinha certeza, mandei para o setor mais ao
-- LADO DO ERRO -- é melhor o Tel achar a função procurando no lugar onde o
-- sintoma aparece do que no lugar tecnicamente correto.
DELETE FROM nai_setor_regra WHERE porque = 'semente 19/09';
INSERT INTO nai_setor_regra (ordem, padrao, setor, porque) VALUES
 -- ---------- identidade: quem é a pessoa
 ( 10, '_(chave|fone_chave|fone_fmt|fone_br)$',              'identidade', 'semente 19/09'),
 ( 11, '_contato(_de|_irmaos)?$',                            'identidade', 'semente 19/09'),
 ( 12, '(identidade|_lid|resolver_identidade)',              'identidade', 'semente 19/09'),
 ( 13, '(nome_de_pessoa|primeiro_nome|tratamento_por_nome|vocativo|sincronizar_nome)', 'identidade', 'semente 19/09'),
 ( 14, '_cpf',                                               'identidade', 'semente 19/09'),
 -- ---------- porta: quem é atendido
 ( 20, '(quem_atende|deve_atender|perguntar_se_e_corretor)',  'porta',      'semente 19/09'),
 ( 21, '(e_comando|_e_motoboy|e_da_equipe|acompanhante)',     'porta',      'semente 19/09'),
 ( 22, '(tel_assumiu|tel_com_a_conversa|parar_chat|regra_publico)', 'porta','semente 19/09'),
 -- ---------- cabeçalho: turno, papel, prompt, contexto
 ( 30, '_(abrir|fechar)_turno$',                              'cabecalho',  'semente 19/09'),
 ( 31, '_contexto',                                           'cabecalho',  'semente 19/09'),
 ( 32, '_prompt',                                             'cabecalho',  'semente 19/09'),
 ( 33, '(status_humano|esperando_valor|quando_humano|hora_exata|lista_pt)', 'cabecalho', 'semente 19/09'),
 -- ---------- conferência: a esteira (vem ANTES de ferramenta, senão
 --            `nai_conferir_resposta` cairia em "resposta" genérico)
 ( 40, '(conferir_resposta|_anotar$|tirar_frase|limpar_markdown)', 'conferencia', 'semente 19/09'),
 ( 41, '_re_(promessa|nega_|frase_de_visita|sugere_visita|assunto_imovel|promete_foto)', 'conferencia', 'semente 19/09'),
 ( 42, '(uma_pergunta|pergunta_qual_imovel|so_anuncia_fotos|sem_emoji)', 'conferencia', 'semente 19/09'),
 ( 43, 'deve_mandar_fotos',                                   'conferencia', 'semente 19/09'),
 -- ---------- montagem
 ( 50, '_enfileirar',                                         'montagem',   'semente 19/09'),
 ( 51, '(depois_das_fotos|imagens_do_envio|card_do_imovel)',   'montagem',   'semente 19/09'),
 -- ---------- saída
 ( 60, '(liberar_saida|saida_validar|saida_imutavel|avisar_tel)', 'saida',   'semente 19/09'),
 ( 61, '_saida',                                              'saida',      'semente 19/09'),
 -- ---------- comandos do Tel
 ( 70, '_comando',                                            'comando',    'semente 19/09'),
 ( 71, '(assumir|devolver|responder_pendencia|responder_conversando)', 'comando', 'semente 19/09'),
 -- ---------- agenda e visita
 ( 80, '_visita',                                             'agenda',     'semente 19/09'),
 ( 81, '(agenda|lembrete|cobran|entregas_devidas|pendencias_esquecidas|retomada)', 'agenda', 'semente 19/09'),
 ( 82, '(acesso|senha|motoboy)',                              'agenda',     'semente 19/09'),
 ( 83, '_horario',                                            'agenda',     'semente 19/09'),
 -- ---------- catálogo
 ( 90, '(esta_no_mercado|imovel_fotos|fotos_do_site|gravar_fotos|varredura|sincronizar_catalogo)', 'catalogo', 'semente 19/09'),
 ( 91, '(normalizar_lugar|bairro|zona|condominio|sem_acento)', 'catalogo',   'semente 19/09'),
 ( 92, '(descricao_segura|endereco_sem_numero|valor_em_reais)','catalogo',   'semente 19/09'),
 ( 93, '(grupo|disparo|postar|publicar|colagem)',              'catalogo',   'semente 19/09'),
 -- ---------- ferramentas (genérico: o que sobra e fala de imóvel)
 (100, '(o_que_sei|imovel_por_codigo|buscar_por_perfil|resumo_do|listar_no|disponibilidade)', 'ferramenta', 'semente 19/09'),
 (101, '(escalar|resposta_da_base|ficou_devendo|conhecimento)','ferramenta',  'semente 19/09'),
 (102, '(dados_corretor|dados_do_corretor|guardar_)',          'ferramenta',  'semente 19/09'),
 (103, '_imovel',                                              'ferramenta',  'semente 19/09'),
 (104, '(codigo|citac|citad)',                                 'ferramenta',  'semente 19/09'),
 -- ---------- rede de segurança: nada fica sem setor
 (900, '^nai_',                                                'cabecalho',   'semente 19/09'),
 (901, '^nay_',                                                'ferramenta',  'semente 19/09'),
 (999, '.',                                                    'entrada',     'semente 19/09');

COMMENT ON TABLE nai_setor_regra IS
  'Como cada funcao e classificada num setor. A primeira regra (menor ordem) que casar ganha. Editavel por UPDATE (Tel, 19/09).';

-- O classificador. Devolve o setor de uma função pelo nome.
CREATE OR REPLACE FUNCTION nai_setor_de_funcao(p_nome text)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT r.setor FROM nai_setor_regra r
   WHERE p_nome ~ r.padrao
   ORDER BY r.ordem LIMIT 1;
$$;

-- Exceções nominais: quando a regra por padrão erra numa função específica,
-- corrige aqui em vez de distorcer o padrão (que mexeria em dezenas).
CREATE TABLE IF NOT EXISTS nai_setor_excecao (
  funcao text PRIMARY KEY,
  setor  text NOT NULL REFERENCES nai_setor(setor),
  porque text,
  criado_em timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION nai_setor_final(p_nome text)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT coalesce(
    (SELECT e.setor FROM nai_setor_excecao e WHERE e.funcao = p_nome),
    nai_setor_de_funcao(p_nome));
$$;


-- =====================================================================
-- 2. A FOTO: o que o banco tinha quando alguém olhou
-- =====================================================================
-- Sem isto não existe a pergunta "o que mudou desde ontem?". Com isto, ela é
-- uma consulta. O `md5(prosrc)` é o que detecta mudança de corpo sem mudança
-- de assinatura -- exatamente o caso do `nai_liberar_saida` de 16/09.
-- DUAS tabelas, e não uma: uma foto É um conjunto de linhas que dividem o
-- mesmo número. Com `id` sendo a chave primária de uma tabela só, a segunda
-- função da mesma foto seria recusada -- e a numeração por `max(id)+1` ainda
-- corria risco de duas fotos simultâneas pegarem o mesmo número. Aqui o
-- cabeçalho tem a sequência e as linhas apontam para ele.
CREATE TABLE IF NOT EXISTS nai_foto (
  id        bigserial PRIMARY KEY,
  tirada_em timestamptz NOT NULL DEFAULT now(),
  rotulo    text
);
CREATE INDEX IF NOT EXISTS nai_foto_quando ON nai_foto (tirada_em DESC);

CREATE TABLE IF NOT EXISTS nai_funcao_foto (
  foto_id   bigint NOT NULL REFERENCES nai_foto(id) ON DELETE CASCADE,
  funcao    text NOT NULL,
  args      text NOT NULL,
  setor     text,
  familia   text,          -- nai | nay | outra
  tamanho   int,
  hash      text NOT NULL,
  PRIMARY KEY (foto_id, funcao, args)
);
CREATE INDEX IF NOT EXISTS nai_funcao_foto_busca ON nai_funcao_foto (funcao, args);

COMMENT ON TABLE nai_foto IS
  'Cabecalho de cada foto do banco: quando e com que rotulo (Tel, 19/09).';
COMMENT ON TABLE nai_funcao_foto IS
  'Corpo de cada funcao (md5) numa foto. E o que permite dizer o que mudou, e quando (Tel, 19/09).';

-- O estado VIVO, classificado por setor.
-- ---------------------------------------------------------------------
-- DROP antes de criar, e não só `CREATE OR REPLACE`.
-- Motivo concreto: `CREATE OR REPLACE VIEW` NÃO consegue mudar o tipo de uma
-- coluna existente ("cannot change data type of view column"). Sem estes
-- DROPs, reaplicar este arquivo depois de qualquer ajuste de tipo falha na
-- metade -- e falhar na metade é o modo de erro que este projeto já conhece.
-- Sem CASCADE de propósito: se algo passar a depender de uma destas views, é
-- melhor o erro aparecer do que a dependência ser derrubada em silêncio.
DROP VIEW IF EXISTS vw_nai_setor_mapa;
DROP VIEW IF EXISTS vw_nai_acoplamento;
DROP VIEW IF EXISTS vw_nai_funcao_orfa;
DROP VIEW IF EXISTS vw_nai_sobrecarga;
DROP VIEW IF EXISTS vw_nai_funcao_viva;

CREATE VIEW vw_nai_funcao_viva AS
-- `proname` e do tipo `name`, nao `text`. Sem o cast, qualquer RETURNS TABLE
-- que use esta coluna falha com "structure of query does not match".
SELECT p.proname::text                               AS funcao,
       pg_get_function_identity_arguments(p.oid)      AS args,
       nai_setor_final(p.proname)                     AS setor,
       CASE WHEN p.proname LIKE 'nai\_%' THEN 'nai'
            WHEN p.proname LIKE 'nay\_%' THEN 'nay'
            ELSE 'outra' END                          AS familia,
       length(p.prosrc)                               AS tamanho,
       md5(p.prosrc)                                  AS hash,
       p.oid
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.prokind = 'f'
   AND p.proname ~ '^(nai|nay|captacao)_'
   -- As funcoes do PROPRIO trace e do proprio inventario ficam FORA da
   -- contagem: elas nao decidem nada no atendimento, e contar 20 funcoes de
   -- observabilidade dentro de um setor faria o Tel ler um numero que nao
   -- significa nada sobre a Nay.
   AND p.proname !~ '^nai_(tracar|mascarar|trilha|evento|foto|setor|sobrecarga|funcao|trace|inventario)';

COMMENT ON VIEW vw_nai_funcao_viva IS
  'Toda funcao nai_/nay_/captacao_ viva no banco, com o setor dela.';

-- Tira a foto. Chamar antes de mexer em qualquer coisa, e depois de mexer.
CREATE OR REPLACE FUNCTION nai_foto_tirar(p_rotulo text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_id bigint; v_n int; v_rot text;
BEGIN
  v_rot := coalesce(nullif(btrim(coalesce(p_rotulo, '')), ''),
                    'foto de ' || to_char(now() AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI'));
  -- A sequência do cabeçalho dá o número: sem `max(id)+1`, sem corrida.
  INSERT INTO nai_foto (rotulo) VALUES (v_rot) RETURNING id INTO v_id;
  INSERT INTO nai_funcao_foto (foto_id, funcao, args, setor, familia, tamanho, hash)
  SELECT v_id, v.funcao, v.args, v.setor, v.familia, v.tamanho, v.hash
    FROM vw_nai_funcao_viva v;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN jsonb_build_object('foto', v_id, 'rotulo', v_rot, 'funcoes', v_n);
END;
$$;

-- O QUE MUDOU entre a última foto e agora. É a resposta para "o banco está à
-- frente do repositório?" -- agora com nome, setor e tipo de mudança.
CREATE OR REPLACE FUNCTION nai_foto_diferenca(p_foto bigint DEFAULT NULL)
RETURNS TABLE (
  mudanca text,          -- nova | apagada | corpo_mudou | assinatura_mudou
  setor   text,
  funcao  text,
  args    text,
  detalhe text)
LANGUAGE plpgsql STABLE AS $$
DECLARE v_foto bigint;
BEGIN
  v_foto := coalesce(p_foto, (SELECT max(id) FROM nai_foto));
  IF v_foto IS NULL THEN
    RETURN QUERY SELECT 'sem_foto'::text, NULL::text, NULL::text, NULL::text,
                        'nenhuma foto tirada ainda: rode nai_foto_tirar()'::text;
    RETURN;
  END IF;

  RETURN QUERY
  WITH antes AS (SELECT * FROM nai_funcao_foto WHERE foto_id = v_foto),
       agora AS (SELECT * FROM vw_nai_funcao_viva)
  -- corpo mudou: mesma assinatura, hash diferente. É o caso silencioso.
  SELECT 'corpo_mudou'::text, g.setor, g.funcao, g.args,
         ('era ' || a.tamanho || ' chars, agora ' || g.tamanho ||
          ' -- corrigida em producao e provavelmente nao voltou ao repositorio')::text
    FROM agora g JOIN antes a ON a.funcao = g.funcao AND a.args = g.args
   WHERE a.hash <> g.hash
  UNION ALL
  SELECT 'nova'::text, g.setor, g.funcao, g.args, 'nao existia na foto'::text
    FROM agora g
   WHERE NOT EXISTS (SELECT 1 FROM antes a WHERE a.funcao = g.funcao AND a.args = g.args)
  UNION ALL
  SELECT 'apagada'::text, a.setor, a.funcao, a.args, 'existia na foto e nao existe mais'::text
    FROM antes a
   WHERE NOT EXISTS (SELECT 1 FROM agora g WHERE g.funcao = a.funcao AND g.args = a.args)
  ORDER BY 1, 2, 3;
END;
$$;


-- =====================================================================
-- 3. O ACOPLAMENTO nai_ -> nay_ (a IA nova usando o cérebro velho)
-- =====================================================================
-- Medido em 19/09: 22 funções da NAI dependem de 28 funções da Nay antiga.
-- As mais críticas: `nay_codigos_citados` (5 chamadoras), `nay_esta_no_mercado`
-- (4, inclusive `nai_resposta_da_base`), `nay_nome_de_pessoa` (4).
--
-- Isto não é ruim por si: reusar código é certo. É ruim quando a função velha
-- carrega uma regra que valia no fluxo antigo e não vale mais -- e ninguém
-- percebe porque a chamada está enterrada num `prosrc`.
CREATE VIEW vw_nai_acoplamento AS
WITH nova AS (
  SELECT p.proname::text AS proname, p.prosrc, nai_setor_final(p.proname) AS setor
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname LIKE 'nai\_%' AND p.prokind = 'f'),
antiga AS (
  SELECT DISTINCT p.proname::text AS proname, nai_setor_final(p.proname) AS setor
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname LIKE 'nay\_%' AND p.prokind = 'f')
SELECT a.proname::text                                  AS funcao_antiga,
       a.setor                                          AS setor_da_antiga,
       count(DISTINCT v.proname)                         AS quantas_nai_chamam,
       string_agg(DISTINCT v.proname, ', ' ORDER BY v.proname) AS chamada_por,
       string_agg(DISTINCT v.setor,   ', ' ORDER BY v.setor)   AS setores_afetados
  FROM antiga a
  JOIN nova v ON v.prosrc ~ ('\m' || a.proname || '\M')
 GROUP BY a.proname, a.setor
 ORDER BY count(DISTINCT v.proname) DESC, a.proname;

COMMENT ON VIEW vw_nai_acoplamento IS
  'Funcoes da Nay ANTIGA que a NAI nova chama, e quais setores dependem delas (Tel, 19/09).';


-- =====================================================================
-- 4. AS ÓRFÃS -- e por que "órfã" não é "morta"
-- =====================================================================
-- Em 19/09 a varredura achou 35 funções que nenhuma OUTRA função chama. Ao
-- cruzar com o fluxo do n8n, os crons e o painel, 19 delas estavam VIVAS --
-- chamadas de fora do banco. Sobraram 16 candidatas.
--
-- Por isso existe a tabela abaixo: o cruzamento com o mundo de fora precisa
-- ficar GRAVADO, senão cada auditoria refaz o trabalho e alguém eventualmente
-- apaga uma função viva.
CREATE TABLE IF NOT EXISTS nai_funcao_chamador (
  funcao    text NOT NULL,
  chamador  text NOT NULL,     -- 'n8n:<no>' | 'cron:<script>' | 'painel:<rota>' | 'humano'
  anotado_em timestamptz NOT NULL DEFAULT now(),
  anotado_por text,
  PRIMARY KEY (funcao, chamador)
);
COMMENT ON TABLE nai_funcao_chamador IS
  'Quem chama cada funcao DE FORA do banco (n8n, cron, painel). Sem isto, "orfa" e confundida com "morta" (Tel, 19/09).';

-- Semente com o cruzamento de 19/09, para nenhuma delas ser apagada por engano.
INSERT INTO nai_funcao_chamador (funcao, chamador, anotado_por) VALUES
 ('nai_agenda_tick',                  'n8n:Agenda da NAI',              'auditoria 19/09'),
 ('nai_liberar_saida',                'n8n:Liberar saida',              'auditoria 19/09'),
 ('nai_comando_tel',                  'n8n:Comando do Tel',             'auditoria 19/09'),
 ('nai_comando_tel',                  'n8n:Comando de visita (Tel)',    'auditoria 19/09'),
 ('nai_tel_assumiu',                  'n8n:O Tel assumiu a conversa',   'auditoria 19/09'),
 ('nai_enfileirar_card',              'n8n:Enfileirar card do codigo',  'auditoria 19/09'),
 ('nai_abrir_turno',                  'n8n:Abrir turno',                'auditoria 19/09'),
 ('nai_enfileirar_resposta',          'n8n:Enfileirar resposta',        'auditoria 19/09'),
 ('nai_fechar_turno',                 'n8n:Fechar turno',               'auditoria 19/09'),
 ('nai_pedir_visita',                 'n8n:ferramenta pedir_visita',    'auditoria 19/09'),
 ('nai_escalar',                      'n8n:ferramenta escalar_ao_tel',  'auditoria 19/09'),
 ('nai_guardar_dados_visita',         'n8n:ferramenta guardar_dados_da_visita', 'auditoria 19/09'),
 ('nai_responder_horario',            'n8n:ferramenta responder_horario_do_proprietario', 'auditoria 19/09'),
 ('nai_mudar_horario',                'n8n:ferramenta mudar_horario_da_visita', 'auditoria 19/09'),
 ('nai_resultado_visita',             'n8n:ferramenta resultado_da_visita', 'auditoria 19/09'),
 ('nai_resposta_proprietario',        'n8n:ferramenta resposta_do_proprietario', 'auditoria 19/09'),
 ('nai_resposta_motoboy',             'n8n:ferramenta resposta_do_motoboy', 'auditoria 19/09'),
 ('nai_o_que_sei_do_imovel',          'n8n:ferramenta o_que_sei_do_imovel', 'auditoria 19/09'),
 ('nai_buscar_por_perfil',            'n8n:ferramenta buscar_por_perfil', 'auditoria 19/09'),
 ('nai_dados_do_corretor_tool',       'n8n:ferramenta dados_do_corretor', 'auditoria 19/09'),
 ('nay_disponibilidade_no_condominio','n8n:ferramenta disponibilidade_no_condominio', 'auditoria 19/09'),
 ('nay_guardar_do_imovel',            'n8n:ferramenta guardar_do_imovel', 'auditoria 19/09'),
 ('nay_qual_imovel',                  'n8n:ferramenta imovel_do_disparo', 'auditoria 19/09'),
 ('nai_sincronizar_grupos',           'cron:sincronizar_grupos_corretores.sh (seg 10:10)', 'auditoria 19/09'),
 ('nai_salvar_prompt',                'painel:/api/nai/prompt',         'auditoria 19/09'),
 ('nai_quem_atende',                  'n8n:NAI ou Nay? (no fluxo antigo sQuiEjbEDMEbjX5U)', 'auditoria 19/09')
ON CONFLICT (funcao, chamador) DO NOTHING;

-- As candidatas de verdade: nenhuma função chama, e ninguém anotou chamador
-- de fora. AINDA NÃO SÃO "mortas" -- faltam 7 fluxos do n8n e 11 crons no
-- cruzamento. A coluna `confianca` diz exatamente isso.
CREATE VIEW vw_nai_funcao_orfa AS
WITH f AS (
  SELECT p.oid, p.proname::text AS proname, p.prosrc, nai_setor_final(p.proname) AS setor,
         CASE WHEN p.proname LIKE 'nai\_%' THEN 'nai' ELSE 'nay' END AS familia,
         length(p.prosrc) AS tamanho
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.proname ~ '^(nai|nay)_'
     -- O MESMO filtro da vw_nai_funcao_viva. Sem ele, as funcoes do proprio
     -- trace e do proprio inventario aparecem como "candidatas a entulho" --
     -- e a primeira coisa que o painel faria era sugerir apagar a si mesmo.
     AND p.proname !~ '^nai_(tracar|mascarar|trilha|evento|foto|setor|sobrecarga|funcao|trace|inventario)')
SELECT f.proname::text                             AS funcao,
       f.setor,
       f.familia,
       f.tamanho,
       (SELECT string_agg(c.chamador, ', ' ORDER BY c.chamador)
          FROM nai_funcao_chamador c WHERE c.funcao = f.proname) AS chamador_de_fora,
       CASE
         WHEN EXISTS (SELECT 1 FROM nai_funcao_chamador c WHERE c.funcao = f.proname)
           THEN 'viva: chamada de fora do banco'
         ELSE 'CANDIDATA: nenhuma funcao chama e nenhum chamador anotado -- conferir os 7 fluxos e os 11 crons ANTES de apagar'
       END                                          AS confianca
  FROM f
 WHERE NOT EXISTS (
   SELECT 1 FROM f g WHERE g.oid <> f.oid AND g.prosrc ~ ('\m' || f.proname || '\M'))
 ORDER BY (EXISTS (SELECT 1 FROM nai_funcao_chamador c WHERE c.funcao = f.proname)),
          f.familia DESC, f.tamanho DESC;

COMMENT ON VIEW vw_nai_funcao_orfa IS
  'Funcoes que nenhuma outra chama. `confianca` separa as que tem chamador de fora anotado das candidatas de verdade (Tel, 19/09).';


-- =====================================================================
-- 5. SOBRECARGAS -- e a nota de que as duas de hoje são DE PROPÓSITO
-- =====================================================================
-- O `CLAUDE.md` avisa, com razão, que `CREATE OR REPLACE` com assinatura
-- diferente cria uma SOBRECARGA em vez de substituir, e que a versão velha
-- (sem as paredes novas) continua chamável. Mordeu em 31/08.
--
-- MAS: em 19/09 as duas sobrecargas existentes são intencionais e
-- DOCUMENTADAS no repositório --
--   * `nai_quem_atende`: a de 3 argumentos CHAMA a de 2 (arquivo 10, linha 39).
--     Derrubar a de 2 quebra a de 3 e para o porteiro nº 1.
--   * `nay_normalizar_lugar`: as duas nascem no mesmo arquivo
--     (`bairro_sem_acento.sql`, linhas 29 e 45) -- base e variante.
--
-- Por isso a view marca as conhecidas em vez de gritar. Sobrecarga NOVA, que
-- não esteja nesta lista, é que merece investigação.
CREATE TABLE IF NOT EXISTS nai_sobrecarga_esperada (
  funcao text PRIMARY KEY,
  porque text NOT NULL
);
INSERT INTO nai_sobrecarga_esperada (funcao, porque) VALUES
 ('nai_quem_atende',
  'De proposito: a de 3 args (com o texto) CHAMA a de 2. Arquivo nai/10_rota_numero_tel.sql linha 39. NAO derrubar a de 2 args.'),
 ('nay_normalizar_lugar',
  'De proposito: base (1 arg) e variante com p_fundo (2 args), as duas em bairro_sem_acento.sql linhas 29 e 45.')
ON CONFLICT (funcao) DO UPDATE SET porque = EXCLUDED.porque;

CREATE VIEW vw_nai_sobrecarga AS
SELECT p.proname::text                                      AS funcao,
       nai_setor_final(p.proname)                            AS setor,
       count(*)                                              AS versoes,
       string_agg('(' || pg_get_function_identity_arguments(p.oid) || ')',
                  '  ||  ' ORDER BY p.oid)                   AS assinaturas,
       e.porque                                              AS esperada_porque,
       CASE WHEN e.funcao IS NOT NULL THEN 'conhecida: de proposito'
            ELSE 'NOVA: investigar -- pode ser versao velha ainda chamavel' END AS veredito
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  LEFT JOIN nai_sobrecarga_esperada e ON e.funcao = p.proname
 WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.proname ~ '^(nai|nay|captacao)_'
 GROUP BY p.proname, e.funcao, e.porque
HAVING count(*) > 1
 ORDER BY (e.funcao IS NOT NULL), p.proname;

COMMENT ON VIEW vw_nai_sobrecarga IS
  'Funcoes com mais de uma assinatura. As de proposito estao marcadas; sobrecarga NOVA e que precisa de olhar (Tel, 19/09).';


-- =====================================================================
-- 6. O RESUMO POR SETOR -- a tela "onde está o entulho"
-- =====================================================================
-- Junta as duas metades: quantas funções cada setor tem (e quantas são da IA
-- velha) COM o semáforo de runtime do arquivo 64. É o que responde a pergunta
-- do Tel numa linha por setor: "onde eu mexo primeiro?"
CREATE VIEW vw_nai_setor_mapa AS
SELECT s.setor,
       s.ordem,
       s.titulo,
       s.descricao,
       count(v.*)                                          AS funcoes,
       count(v.*) FILTER (WHERE v.familia = 'nai')         AS da_ia_nova,
       count(v.*) FILTER (WHERE v.familia = 'nay')         AS da_ia_antiga,
       sum(v.tamanho)                                      AS chars_de_codigo,
       (SELECT count(*) FROM vw_nai_funcao_orfa o
         WHERE o.setor = s.setor AND o.chamador_de_fora IS NULL) AS candidatas_a_entulho,
       (SELECT count(*) FROM vw_nai_acoplamento a
         WHERE a.setores_afetados LIKE '%' || s.setor || '%') AS dependencias_da_antiga
  FROM nai_setor s
  LEFT JOIN vw_nai_funcao_viva v ON v.setor = s.setor
 GROUP BY s.setor, s.ordem, s.titulo, s.descricao
 ORDER BY s.ordem;

COMMENT ON VIEW vw_nai_setor_mapa IS
  'Um setor por linha: quantas funcoes, quantas da IA antiga, e quantas candidatas a entulho (Tel, 19/09).';


-- =====================================================================
-- 7. GRANTS
-- =====================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nay_site_nai') THEN
    EXECUTE 'GRANT SELECT ON vw_nai_setor_mapa, vw_nai_acoplamento, vw_nai_funcao_orfa,
                              vw_nai_sobrecarga, vw_nai_funcao_viva TO nay_site_nai';
    EXECUTE 'GRANT SELECT ON nai_setor_regra, nai_setor_excecao, nai_funcao_chamador,
                              nai_sobrecarga_esperada TO nay_site_nai';
    EXECUTE 'GRANT EXECUTE ON FUNCTION nai_setor_de_funcao(text) TO nay_site_nai';
    EXECUTE 'GRANT EXECUTE ON FUNCTION nai_setor_final(text) TO nay_site_nai';
    EXECUTE 'GRANT EXECUTE ON FUNCTION nai_foto_diferenca(bigint) TO nay_site_nai';
  END IF;
END $$;


-- =====================================================================
-- 8. A PRIMEIRA FOTO. Tirar AGORA, antes de qualquer conserto.
-- =====================================================================
-- É o marco zero. A partir daqui, `SELECT * FROM nai_foto_diferenca()` responde
-- "o que mudou desde então" com nome, setor e tipo de mudança.
--
-- SÓ se ainda não existir nenhuma: reaplicar este arquivo não pode tirar uma
-- foto nova, senão o marco zero se move para depois das mudanças e o desvio
-- que ele existia para mostrar desaparece. Foto nova é ato deliberado:
--   SELECT nai_foto_tirar('depois do conserto X');
DO $$
DECLARE r jsonb;
BEGIN
  IF EXISTS (SELECT 1 FROM nai_foto) THEN
    RAISE NOTICE 'ja existe foto (a mais recente e a de %) -- nenhuma nova foi tirada. Para tirar: SELECT nai_foto_tirar(''rotulo'');',
      (SELECT to_char(max(tirada_em) AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') FROM nai_foto);
  ELSE
    r := nai_foto_tirar('marco zero -- antes dos consertos de 19/09');
    RAISE NOTICE 'MARCO ZERO tirado: foto % com % funcoes', r->>'foto', r->>'funcoes';
  END IF;
END $$;
