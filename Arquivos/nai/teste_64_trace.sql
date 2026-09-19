-- =====================================================================
-- Teste do TRACE (arquivo 64). Mesmo padrão do `teste_nai.sql`: roda DENTRO
-- de uma transação que termina em ROLLBACK -- nada fica gravado.
--
-- Uso no servidor, COM ponto e vírgula no BEGIN:
--   (echo 'BEGIN;'; cat teste_64_trace.sql; echo 'ROLLBACK;') \
--     | docker exec -i nay-postgres psql -U nay -d naydb
--
-- Cada verificação imprime OK ou FALHA; no fim, o total.
-- O teste é sobre COMPORTAMENTO, não sobre sintaxe: mascaramento que não
-- corrompe JSON, trace que não derruba o atendimento, veredito que classifica
-- certo, e a trilha em ordem de setor.
-- =====================================================================
SET client_min_messages = notice;

CREATE TEMP TABLE _r (ok boolean, msg text);
CREATE OR REPLACE FUNCTION pg_temp.ok(c boolean, m text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _r (ok, msg) VALUES (coalesce(c, false), m);
  RAISE NOTICE '% %', CASE WHEN coalesce(c, false) THEN 'OK   ' ELSE 'FALHA' END, m;
END $$;

UPDATE nai_config SET valor = 'completo' WHERE chave = 'trace_nivel';
UPDATE nai_config SET valor = 'sim'      WHERE chave = 'trace_payload';


-- =====================================================================
-- 1. MASCARAMENTO: protege sem corromper
-- =====================================================================
SELECT pg_temp.ok(
  nai_mascarar_texto('meu numero e 5592991712835 viu') = 'meu numero e 5592***35 viu',
  'mascara: telefone de 13 digitos vira 4 primeiros + *** + 2 ultimos');

SELECT pg_temp.ok(
  nai_mascarar_texto('cpf 52998224725') = 'cpf 5299***25',
  'mascara: CPF de 11 digitos tambem e mascarado');

-- A regra mais importante: o codigo do imovel NAO pode ser tocado, senao o
-- painel fica inutil justo no dado que mais importa.
SELECT pg_temp.ok(
  nai_mascarar_texto('Código: 5717 no Aleixo por 3500') = 'Código: 5717 no Aleixo por 3500',
  'mascara: codigo de imovel (4 digitos) e valor NAO sao mascarados');

SELECT pg_temp.ok(
  nai_mascarar_texto('area 120 m2, 3 quartos, 2 vagas') = 'area 120 m2, 3 quartos, 2 vagas',
  'mascara: numero pequeno passa intacto');

-- O bug que este desenho evita: mascarar o jsonb SERIALIZADO transformaria
-- {"id": 559299998888} em {"id": 5592***88}, que nao e JSON. Aqui o numero
-- e numero e fica em paz; so valor de TEXTO e mascarado.
SELECT pg_temp.ok(
  nai_mascarar('{"id": 559299998888, "tel": "559299998888"}'::jsonb)
    = '{"id": 559299998888, "tel": "5592***88"}'::jsonb,
  'mascara: numero fica intacto (JSON nao corrompe), string e mascarada');

SELECT pg_temp.ok(
  nai_mascarar('{"a":{"b":["5592991712835","ok"]}}'::jsonb)
    = '{"a":{"b":["5592***35","ok"]}}'::jsonb,
  'mascara: desce em objeto dentro de array dentro de objeto');

SELECT pg_temp.ok(nai_mascarar(NULL) IS NULL, 'mascara: NULL continua NULL');
SELECT pg_temp.ok(nai_mascarar('[]'::jsonb) = '[]'::jsonb, 'mascara: array vazio nao virou null');
SELECT pg_temp.ok(nai_mascarar('{}'::jsonb) = '{}'::jsonb, 'mascara: objeto vazio nao virou null');
SELECT pg_temp.ok(nai_mascarar('true'::jsonb) = 'true'::jsonb, 'mascara: booleano passa intacto');


-- =====================================================================
-- 2. O TRACE NUNCA DERRUBA O ATENDIMENTO
-- =====================================================================
DO $$
DECLARE v_turno bigint; v_contato bigint; v_id bigint; v_n int;
BEGIN
  -- um contato e um turno de mentira, so para este teste
  INSERT INTO nai_contato (chave, telefone, nome_whatsapp)
       VALUES ('999999999999', '999999999999', 'Teste do Trace')
  ON CONFLICT (chave) DO UPDATE SET nome_whatsapp = 'Teste do Trace'
  RETURNING id INTO v_contato;

  INSERT INTO nai_turno (contato_id, papel, texto, ferramentas)
       VALUES (v_contato, 'corretor', 'tem foto do 5717?', ARRAY['imovel_por_codigo'])
  RETURNING id INTO v_turno;

  -- 2.1 o caminho felizardo
  v_id := nai_tracar(v_turno, 'modelo', 'resposta_crua', 'ok',
                     NULL, '{"texto":"segue as fotos"}'::jsonb, 'teste', 120, 'exec-1');
  PERFORM pg_temp.ok(v_id IS NOT NULL, 'tracar: grava e devolve o id');

  -- 2.2 SETOR DESCONHECIDO nao pode recusar o evento: o trace precisa aceitar
  -- o que chega, senao perde justamente o caso estranho.
  v_id := nai_tracar(v_turno, 'setor_que_nao_existe', 'etapa', 'ok');
  PERFORM pg_temp.ok(v_id IS NOT NULL, 'tracar: setor fora da lista e aceito (nao recusa dado)');

  -- 2.3 RESULTADO fora do vocabulario vira 'erro' em vez de estourar o CHECK
  v_id := nai_tracar(v_turno, 'modelo', 'etapa', 'inventado');
  PERFORM pg_temp.ok(v_id IS NOT NULL, 'tracar: resultado desconhecido e aceito');
  PERFORM pg_temp.ok(
    (SELECT resultado FROM nai_evento WHERE id = v_id) = 'erro',
    'tracar: resultado desconhecido vira erro, e o detalhe guarda o que veio');
  PERFORM pg_temp.ok(
    (SELECT detalhe FROM nai_evento WHERE id = v_id) LIKE '%inventado%',
    'tracar: o valor original aparece no detalhe');

  -- 2.4 TURNO QUE NAO EXISTE: sem FK, isto grava (de proposito) e nao levanta
  v_id := nai_tracar(999999999, 'entrada', 'orfao', 'ok');
  PERFORM pg_temp.ok(v_id IS NOT NULL, 'tracar: turno inexistente grava (sem FK, de proposito)');

  -- 2.5 ETAPA sem nome nao quebra o NOT NULL
  v_id := nai_tracar(v_turno, 'modelo', NULL, 'ok');
  PERFORM pg_temp.ok(v_id IS NOT NULL, 'tracar: etapa NULL ganha nome padrao em vez de estourar');

  -- 2.6 DESLIGADO nao grava nada
  UPDATE nai_config SET valor = 'desligado' WHERE chave = 'trace_nivel';
  SELECT count(*) INTO v_n FROM nai_evento WHERE turno_id = v_turno;
  v_id := nai_tracar(v_turno, 'modelo', 'nao_deve_gravar', 'ok');
  PERFORM pg_temp.ok(v_id IS NULL, 'trace_nivel=desligado: devolve NULL');
  PERFORM pg_temp.ok((SELECT count(*) FROM nai_evento WHERE turno_id = v_turno) = v_n,
                     'trace_nivel=desligado: nao gravou linha nenhuma');

  -- 2.7 MODO PROBLEMA: grava so o que nao foi ok
  UPDATE nai_config SET valor = 'problema' WHERE chave = 'trace_nivel';
  PERFORM pg_temp.ok(nai_tracar(v_turno, 'modelo', 'um_ok', 'ok') IS NULL,
                     'trace_nivel=problema: etapa ok nao e gravada');
  PERFORM pg_temp.ok(nai_tracar(v_turno, 'modelo', 'um_erro', 'erro') IS NOT NULL,
                     'trace_nivel=problema: etapa com erro E gravada');
  UPDATE nai_config SET valor = 'completo' WHERE chave = 'trace_nivel';

  -- 2.8 SEM PAYLOAD: guarda a etapa, descarta o jsonb
  UPDATE nai_config SET valor = 'nao' WHERE chave = 'trace_payload';
  v_id := nai_tracar(v_turno, 'modelo', 'sem_payload', 'ok', '{"a":1}'::jsonb, '{"b":2}'::jsonb);
  PERFORM pg_temp.ok((SELECT entrada IS NULL AND saida IS NULL FROM nai_evento WHERE id = v_id),
                     'trace_payload=nao: grava a etapa e descarta o dado');
  UPDATE nai_config SET valor = 'sim' WHERE chave = 'trace_payload';

  -- 2.9 A SEQUENCIA anda sozinha
  PERFORM pg_temp.ok(
    (SELECT count(DISTINCT seq) FROM nai_evento WHERE turno_id = v_turno) > 1,
    'tracar: a sequencia do turno avanca a cada evento');

  -- 2.10 o payload gravado JA esta mascarado
  v_id := nai_tracar(v_turno, 'entrada', 'com_telefone', 'ok',
                     '{"phone":"5592991712835"}'::jsonb);
  PERFORM pg_temp.ok(
    (SELECT entrada->>'phone' FROM nai_evento WHERE id = v_id) = '5592***35',
    'tracar: o telefone ja entra mascarado na tabela');
END $$;


-- =====================================================================
-- 3. O CABEÇALHO ACUSA PROMPT VAZIO (o achado de 19/09)
-- =====================================================================
DO $$
DECLARE v_turno bigint; v_contato bigint; v_id bigint;
BEGIN
  SELECT id INTO v_contato FROM nai_contato WHERE chave = '999999999999';
  INSERT INTO nai_turno (contato_id, papel, texto) VALUES (v_contato, 'corretor', 'oi')
  RETURNING id INTO v_turno;

  -- prompt curto = o agente esta rodando com o texto de reserva do no
  v_id := nai_tracar_cabecalho(v_turno, 'corretor', 'oi', 'contexto qualquer');
  PERFORM pg_temp.ok((SELECT resultado FROM nai_evento WHERE id = v_id) = 'erro',
                     'cabecalho: prompt curto e ERRO (texto de reserva do no assumiu)');
  PERFORM pg_temp.ok((SELECT detalhe FROM nai_evento WHERE id = v_id) LIKE '%PROMPT VAZIO%',
                     'cabecalho: o detalhe diz o que aconteceu, em portugues');

  -- prompt de tamanho normal = ok
  v_id := nai_tracar_cabecalho(v_turno, 'corretor', repeat('x', 3000), 'contexto');
  PERFORM pg_temp.ok((SELECT resultado FROM nai_evento WHERE id = v_id) = 'ok',
                     'cabecalho: prompt de tamanho normal passa');

  -- o contexto (o "segundo prompt") fica registrado -- e o que hoje ninguem ve
  PERFORM pg_temp.ok(
    (SELECT saida->>'contexto' FROM nai_evento WHERE id = v_id) = 'contexto',
    'cabecalho: o contexto injetado fica gravado no trace');

  -- prompt NULL nao levanta excecao
  PERFORM pg_temp.ok(nai_tracar_cabecalho(v_turno, 'corretor', NULL, NULL) IS NOT NULL,
                     'cabecalho: prompt NULL e registrado como erro, sem estourar');
END $$;


-- =====================================================================
-- 4. A RESPOSTA CRUA DO MODELO
-- =====================================================================
DO $$
DECLARE v_turno bigint; v_contato bigint; v_id bigint;
BEGIN
  SELECT id INTO v_contato FROM nai_contato WHERE chave = '999999999999';
  INSERT INTO nai_turno (contato_id, papel, texto) VALUES (v_contato, 'corretor', 'e mobiliado?')
  RETURNING id INTO v_turno;

  v_id := nai_tracar_modelo(v_turno, 'O 5717 e semimobiliado.', 'o_que_sei_do_imovel',
                            'gpt-5.6-sol', 840, 'exec-99', 1200, 40);
  PERFORM pg_temp.ok((SELECT saida->>'texto_cru' FROM nai_evento WHERE id = v_id)
                       = 'O 5717 e semimobiliado.',
                     'modelo: o texto CRU fica guardado antes de qualquer conferencia');
  PERFORM pg_temp.ok((SELECT saida->'ferramentas'->>0 FROM nai_evento WHERE id = v_id)
                       = 'o_que_sei_do_imovel',
                     'modelo: as ferramentas chamadas ficam na lista');
  PERFORM pg_temp.ok((SELECT modelo FROM nai_turno WHERE id = v_turno) = 'gpt-5.6-sol',
                     'modelo: o nome do modelo fica carimbado no turno');
  PERFORM pg_temp.ok((SELECT exec_id FROM nai_turno WHERE id = v_turno) = 'exec-99',
                     'modelo: o id da execucao do n8n liga o painel ao n8n');

  -- modelo que nao devolveu nada e 'parou', nao 'ok'
  v_id := nai_tracar_modelo(v_turno, '', NULL, 'gpt-5.6-sol', 300, 'exec-99');
  PERFORM pg_temp.ok((SELECT resultado FROM nai_evento WHERE id = v_id) = 'parou',
                     'modelo: resposta vazia e registrada como PAROU');
END $$;


-- =====================================================================
-- 5. FERRAMENTA
-- =====================================================================
DO $$
DECLARE v_turno bigint; v_contato bigint; v_id bigint;
BEGIN
  SELECT id INTO v_contato FROM nai_contato WHERE chave = '999999999999';
  INSERT INTO nai_turno (contato_id, papel, texto) VALUES (v_contato, 'corretor', 'busca')
  RETURNING id INTO v_turno;

  v_id := nai_tracar_ferramenta(v_turno, 'buscar_por_perfil',
            '{"bairro":"Vieiralves","teto":3500,"negocio":""}'::jsonb,
            '{"texto_pronto":"achei 3"}'::jsonb, 55, 'exec-2');
  PERFORM pg_temp.ok((SELECT etapa FROM nai_evento WHERE id = v_id) = 'buscar_por_perfil',
                     'ferramenta: a etapa e o nome da ferramenta');
  -- este e o caso do bug do `negocio` vazio: com o argumento gravado, da para
  -- MEDIR quantas vezes o modelo omite, em vez de supor.
  PERFORM pg_temp.ok((SELECT entrada->>'negocio' FROM nai_evento WHERE id = v_id) = '',
                     'ferramenta: o argumento vazio fica visivel (o bug do negocio)');
  PERFORM pg_temp.ok((SELECT ms FROM nai_evento WHERE id = v_id) = 55,
                     'ferramenta: a duracao fica gravada');

  v_id := nai_tracar_ferramenta(v_turno, 'imovel_por_codigo', '{"codigo":9999}'::jsonb, NULL);
  PERFORM pg_temp.ok((SELECT resultado FROM nai_evento WHERE id = v_id) = 'parou',
                     'ferramenta: retorno vazio e PAROU (ela nao achou nada)');
END $$;


-- =====================================================================
-- 6. A TRILHA: as três fontes numa linha do tempo, em ordem de setor
-- =====================================================================
DO $$
DECLARE v_turno bigint; v_contato bigint; v_setores text;
BEGIN
  SELECT id INTO v_contato FROM nai_contato WHERE chave = '999999999999';
  INSERT INTO nai_turno (contato_id, papel, texto) VALUES (v_contato, 'corretor', 'trilha')
  RETURNING id INTO v_turno;

  -- de proposito FORA de ordem, para provar que a ordenacao e por setor
  PERFORM nai_tracar(v_turno, 'saida',     'zapi',      'ok');
  PERFORM nai_tracar(v_turno, 'modelo',    'crua',      'ok');
  PERFORM nai_tracar(v_turno, 'entrada',   'webhook',   'ok');
  PERFORM nai_tracar(v_turno, 'cabecalho', 'prompt',    'ok');
  -- a esteira que JA existia, escrita onde ela sempre escreve
  INSERT INTO nai_conferencia (turno_id, ordem, etapa, resultado, detalhe)
       VALUES (v_turno, 1, 'imovel_da_conversa', 'mudou', 'imovel 5717'),
              (v_turno, 6, 'silencio',           'passou', NULL);
  -- e uma saida de verdade
  INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo,
                         texto, ordem, motivo, estado)
       VALUES (v_turno, v_contato, 'turno', '', 'texto', 'Segue as fotos', 1, 'resposta', 'enviado');

  SELECT string_agg(DISTINCT setor, '>' ORDER BY setor) INTO v_setores FROM nai_trilha(v_turno);
  PERFORM pg_temp.ok(v_setores LIKE '%entrada%' AND v_setores LIKE '%conferencia%'
                       AND v_setores LIKE '%saida%',
                     'trilha: junta evento + conferencia + saida numa consulta so');

  -- a ordem tem que ser a do caminho da mensagem, nao a de insercao
  PERFORM pg_temp.ok(
    (SELECT string_agg(setor, '>') FROM (
       SELECT setor FROM nai_trilha(v_turno) ORDER BY setor_ordem, passo LIMIT 4) x)
      LIKE 'entrada>cabecalho>modelo%',
    'trilha: sai na ORDEM do caminho (entrada, cabecalho, modelo...), nao na de insercao');

  -- 'passou' da conferencia e traduzido para 'ok', para o painel ter um
  -- vocabulario so
  PERFORM pg_temp.ok(
    (SELECT resultado FROM nai_trilha(v_turno) WHERE etapa = 'silencio') = 'ok',
    'trilha: "passou" da conferencia vira "ok" (vocabulario unico)');

  PERFORM pg_temp.ok(
    (SELECT resultado FROM nai_trilha(v_turno) WHERE etapa = 'imovel_da_conversa') = 'mudou',
    'trilha: "mudou" da conferencia continua "mudou"');

  PERFORM pg_temp.ok(
    (SELECT count(*) FROM nai_trilha(v_turno) WHERE setor = 'saida' AND saida->>'texto' = 'Segue as fotos') = 1,
    'trilha: a mensagem que saiu aparece com o texto dela');

  -- O SETOR ENTRADA: o webhook roda ANTES do turno existir, entao o evento
  -- dele nao tem turno_id. Sem a ligacao por exec_id, o primeiro setor do
  -- painel apareceria sempre vazio -- justamente o que se olha primeiro
  -- quando ela nao respondeu.
  UPDATE nai_turno SET exec_id = 'exec-trilha-1' WHERE id = v_turno;
  PERFORM nai_tracar_entrada('{"phone":"5592991712835","text":"oi"}'::jsonb, 'exec-trilha-1');
  -- conta a ETAPA, nao o setor: este bloco ja gravou um 'webhook' proprio no
  -- setor entrada, com turno_id, e contar o setor inteiro daria 2.
  PERFORM pg_temp.ok(
    (SELECT count(*) FROM nai_trilha(v_turno) WHERE etapa = 'webhook_zapi') = 1,
    'trilha: o evento do webhook (sem turno_id) entra pelo exec_id');
  PERFORM pg_temp.ok(
    (SELECT entrada->>'phone' FROM nai_trilha(v_turno) WHERE etapa = 'webhook_zapi') = '5592***35',
    'trilha: e o telefone dele chega mascarado na tela');
  -- e o de OUTRA execucao nao pode vazar para esta trilha
  PERFORM nai_tracar_entrada('{"phone":"5592000000000"}'::jsonb, 'exec-de-outro');
  PERFORM pg_temp.ok(
    (SELECT count(*) FROM nai_trilha(v_turno) WHERE etapa = 'webhook_zapi') = 1,
    'trilha: evento de OUTRA execucao nao aparece nesta');

  -- 888888888, nao 999999999: o bloco 2.4 grava um evento orfao naquele de
  -- proposito, e usar o mesmo id aqui fazia este teste falhar sozinho.
  PERFORM pg_temp.ok((SELECT count(*) FROM nai_trilha(888888888)) = 0,
                     'trilha: turno sem nada devolve vazio, nao erro');
END $$;


-- =====================================================================
-- 7. O VEREDITO -- classifica cada caso certo
-- =====================================================================
DO $$
DECLARE v_contato bigint; t_ok bigint; t_muda bigint; t_barr bigint; t_err bigint; t_corr bigint;
BEGIN
  SELECT id INTO v_contato FROM nai_contato WHERE chave = '999999999999';

  -- (a) OK: respondeu, nada mexeu
  INSERT INTO nai_turno (contato_id, papel, texto) VALUES (v_contato, 'corretor', 'ok')
  RETURNING id INTO t_ok;
  INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, texto, ordem, estado)
       VALUES (t_ok, v_contato, 'turno', '', 'texto', 'Claro!', 1, 'enviado');

  -- (b) MUDA: nao saiu nada, e nada foi barrado -- o bug 57
  INSERT INTO nai_turno (contato_id, papel, texto) VALUES (v_contato, 'corretor', 'boa noite')
  RETURNING id INTO t_muda;

  -- (c) BARRADA: só saída bloqueada
  INSERT INTO nai_turno (contato_id, papel, texto) VALUES (v_contato, 'corretor', 'oi')
  RETURNING id INTO t_barr;
  INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, texto, ordem,
                         estado, bloqueio)
       VALUES (t_barr, v_contato, 'turno', '', 'texto', 'oi', 1, 'bloqueado', 'repetida');

  -- (d) ERRO: um evento de erro ganha de tudo
  INSERT INTO nai_turno (contato_id, papel, texto) VALUES (v_contato, 'corretor', 'erro')
  RETURNING id INTO t_err;
  INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, texto, ordem, estado)
       VALUES (t_err, v_contato, 'turno', '', 'texto', 'saiu', 1, 'enviado');
  PERFORM nai_tracar_erro(t_err, 'modelo', 'agente', 'estourou o contexto', 'exec-3');

  -- (e) CORRIGIDA: respondeu, mas a esteira mexeu
  INSERT INTO nai_turno (contato_id, papel, texto) VALUES (v_contato, 'corretor', 'corr')
  RETURNING id INTO t_corr;
  INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, texto, ordem, estado)
       VALUES (t_corr, v_contato, 'turno', '', 'texto', 'segue as fotos', 1, 'enviado');
  INSERT INTO nai_conferencia (turno_id, ordem, etapa, resultado)
       VALUES (t_corr, 16, 'negou_foto_que_existe', 'mudou');

  PERFORM pg_temp.ok((SELECT veredito FROM vw_nai_execucoes WHERE turno = t_ok) = 'ok',
                     'veredito: respondeu e nada mexeu = ok');
  PERFORM pg_temp.ok((SELECT veredito FROM vw_nai_execucoes WHERE turno = t_muda) = 'muda',
                     'veredito: ninguem recebeu nada e nada foi barrado = MUDA (o bug 57)');
  PERFORM pg_temp.ok((SELECT veredito FROM vw_nai_execucoes WHERE turno = t_barr) = 'barrada',
                     'veredito: so saida bloqueada = barrada');
  PERFORM pg_temp.ok((SELECT veredito FROM vw_nai_execucoes WHERE turno = t_err) = 'erro',
                     'veredito: erro ganha de tudo, mesmo tendo respondido');
  PERFORM pg_temp.ok((SELECT veredito FROM vw_nai_execucoes WHERE turno = t_corr) = 'corrigida',
                     'veredito: respondeu mas a esteira mexeu = corrigida');
  PERFORM pg_temp.ok((SELECT motivos_barrada FROM vw_nai_execucoes WHERE turno = t_barr) = 'repetida',
                     'veredito: o motivo da barrada aparece na lista, sem precisar abrir');
  PERFORM pg_temp.ok((SELECT conf_agiram FROM vw_nai_execucoes WHERE turno = t_corr)
                       LIKE '%negou_foto_que_existe%',
                     'veredito: a lista ja diz QUAL conferencia agiu');
  PERFORM pg_temp.ok((SELECT setores_com_problema FROM vw_nai_execucoes WHERE turno = t_err)
                       LIKE '%modelo%',
                     'veredito: a lista ja diz em QUAL SETOR doeu');
END $$;


-- =====================================================================
-- 8. O SEMÁFORO POR SETOR
-- =====================================================================
DO $$
DECLARE v_sem text;
BEGIN
  -- o setor 'modelo' levou um erro no bloco 7
  SELECT semaforo INTO v_sem FROM vw_nai_setor_saude WHERE setor = 'modelo';
  PERFORM pg_temp.ok(v_sem = 'vermelho', 'semaforo: setor com erro fica VERMELHO');

  -- setor por onde nada passou fica cinza, nao verde: "sem dado" nao e "tudo bem"
  SELECT semaforo INTO v_sem FROM vw_nai_setor_saude WHERE setor = 'agenda';
  PERFORM pg_temp.ok(v_sem = 'cinza', 'semaforo: setor sem passagem fica CINZA, nunca verde');

  PERFORM pg_temp.ok((SELECT count(*) FROM vw_nai_setor_saude) = 12,
                     'semaforo: os 12 setores aparecem sempre, mesmo vazios');
  PERFORM pg_temp.ok(
    (SELECT setor FROM vw_nai_setor_saude ORDER BY ordem LIMIT 1) = 'entrada',
    'semaforo: a ordem e a do caminho da mensagem');
  PERFORM pg_temp.ok(
    (SELECT titulo FROM vw_nai_setor_saude WHERE setor = 'catalogo') = 'Catálogo',
    'semaforo: cada setor tem titulo em portugues para a tela');
END $$;


-- =====================================================================
-- 9. AS ETAPAS DE UM SETOR (a tela de detalhe)
-- =====================================================================
DO $$
BEGIN
  PERFORM pg_temp.ok(
    (SELECT count(*) FROM vw_nai_setor_etapas WHERE setor = 'conferencia') >= 1,
    'etapas: as conferencias aparecem agrupadas por nome');
  PERFORM pg_temp.ok(
    (SELECT agiu FROM vw_nai_setor_etapas
      WHERE setor = 'conferencia' AND etapa = 'negou_foto_que_existe') = 1,
    'etapas: conta quantas vezes a etapa AGIU (nao so quantas passou)');
  PERFORM pg_temp.ok(
    (SELECT array_length(ultimos_turnos, 1) FROM vw_nai_setor_etapas
      WHERE setor = 'conferencia' AND etapa = 'negou_foto_que_existe') >= 1,
    'etapas: traz os ultimos turnos com problema, para clicar e ver');
END $$;


-- =====================================================================
-- 10. LIMPEZA
-- =====================================================================
DO $$
DECLARE r jsonb; v_contato bigint; v_turno bigint;
BEGIN
  SELECT id INTO v_contato FROM nai_contato WHERE chave = '999999999999';
  INSERT INTO nai_turno (contato_id, papel, texto) VALUES (v_contato, 'corretor', 'velho')
  RETURNING id INTO v_turno;
  INSERT INTO nai_evento (turno_id, setor, etapa, resultado, criado_em)
       VALUES (v_turno, 'modelo', 'antigo', 'ok', now() - interval '90 days');

  r := nai_trace_limpar(30);
  PERFORM pg_temp.ok((r->>'eventos_apagados')::int >= 1, 'limpeza: apaga evento mais velho que a retencao');
  PERFORM pg_temp.ok(
    NOT EXISTS (SELECT 1 FROM nai_evento WHERE turno_id = v_turno AND etapa = 'antigo'),
    'limpeza: o evento antigo realmente saiu');

  -- o piso existe para ninguem apagar o dia de hoje com um zero digitado errado
  r := nai_trace_limpar(0);
  PERFORM pg_temp.ok((r->>'dias')::int = 2, 'limpeza: piso de 2 dias -- zero nao apaga o dia de hoje');
  PERFORM pg_temp.ok(
    EXISTS (SELECT 1 FROM nai_evento WHERE criado_em > now() - interval '1 hour'),
    'limpeza: os eventos de hoje continuam la depois de um limpar(0)');
END $$;


-- =====================================================================
SELECT count(*) FILTER (WHERE ok) AS passaram,
       count(*) FILTER (WHERE NOT ok) AS falharam
  FROM _r;
SELECT msg AS "AS QUE FALHARAM" FROM _r WHERE NOT ok;
