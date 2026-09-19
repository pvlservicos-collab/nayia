-- =====================================================================
-- Teste da NAI. Roda DENTRO de uma transacao que termina em ROLLBACK:
-- nada fica gravado. Uso (no servidor):
--   (echo BEGIN; cat 0*.sql teste_nai.sql; echo ROLLBACK;) | psql ...
-- Cada verificacao imprime OK ou FALHA; no fim, o total.
-- =====================================================================
SET client_min_messages = notice;
UPDATE nai_config SET valor = 'teste' WHERE chave = 'modo';
UPDATE nai_config SET valor = 'sim' WHERE chave = 'envio_simulado';
UPDATE nai_config SET valor = 'nao' WHERE chave = 'pausada';
UPDATE nai_config SET valor = '00:00' WHERE chave = 'janela_inicio';
UPDATE nai_config SET valor = '23:59' WHERE chave = 'janela_fim';

-- O teste roda contra o banco de verdade (dentro de BEGIN/ROLLBACK). Visita
-- aberta de um teste MANUAL anterior com o mesmo numero faria o cenario 1
-- cair em "ja existe visita em andamento" e derrubaria 20 verificacoes --
-- aconteceu em 12/09. Aqui elas sao encerradas, e o ROLLBACK devolve tudo.
UPDATE nai_visita SET estado = 'encerrada', encerrada_em = now()
 WHERE corretor_id IN (SELECT id FROM nai_contato WHERE chave = nay_fone_chave('5596991712835'))
   AND estado NOT IN ('encerrada', 'cancelada', 'expirada');

-- Pelo mesmo motivo, os CONTATOS de teste voltam ao estado de quem nunca
-- falou com a NAI. Sem isto, um teste manual anterior no numero do Tel deixa
-- o corretor com nome/CPF/CRECI gravados (ele deixa de ser "corretor novo" e
-- ela nao pede os dados), com `visita_sugerida_em` de hoje (a primeira
-- sugestao ja sai cortada) e com `humano_assumiu_em` preenchido -- 11
-- verificacoes caiam por isso em 12/09. O ROLLBACK devolve tudo.
UPDATE nai_contato SET nome_completo = NULL, cpf = NULL, creci = NULL,
       visita_sugerida_em = NULL, humano_assumiu_em = NULL, humano_motivo = NULL
 WHERE chave IN (SELECT nay_fone_chave(x) FROM unnest(ARRAY[
   '559291712835', '559294717316', '5592977776666', '5592988887777',
   '5592991712835', '5592991712836', '5592994209841', '5596991712835']) x);

-- Marco zero: tudo o que o teste cria tem id MAIOR que isto. Sem este filtro,
-- "a ultima visita do 5611" e "a ultima saida ao proprietario" podem ser de uma
-- rodada anterior que ficou no banco, e 8 verificacoes caem sem motivo.
-- Os message_id ficticios do teste ('TESTE-MSG-1', 'ECO-TESTE-1') sao unicos
-- POR RODADA: se uma rodada anterior ficou gravada, a busca por citacao acha
-- mais de uma linha e o turno do proprietario nao abre. Aqui os antigos saem
-- de cena; o ROLLBACK devolve.
UPDATE nai_saida SET message_id = NULL WHERE message_id IN ('TESTE-MSG-1', 'ECO-TESTE-1');

-- O acesso do imovel e APRENDIDO (nai_acesso_imovel): depois de um teste
-- manual o 5611 ja tem "fechadura" gravada, ela para de perguntar o acesso e
-- o cenario muda. Aqui os imoveis do teste voltam a "nao sei"; o ROLLBACK
-- devolve o aprendizado.
DELETE FROM nai_acesso_imovel WHERE codigo IN (5611, 4255, 2014);

-- A guarda "repetida" (03_saida.sql) barra texto igual ao mesmo contato dentro
-- de 10 minutos. Um teste manual recente com o mesmo numero faz o pedido ao
-- proprietario nascer BLOQUEADO e derruba 8 verificacoes -- foi o que
-- aconteceu em 12/09. Aqui as saidas recentes envelhecem; o ROLLBACK devolve.
UPDATE nai_saida SET enviado_em = enviado_em - interval '2 hours'
 WHERE enviado_em > now() - interval '30 minutes';

CREATE TEMP TABLE _base AS
  SELECT (SELECT coalesce(max(id), 0) FROM nai_visita) AS visita,
         (SELECT coalesce(max(id), 0) FROM nai_saida)  AS saida;

CREATE TEMP TABLE _r (n serial, ok boolean, msg text);
CREATE OR REPLACE FUNCTION pg_temp.ok(c boolean, m text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO _r (ok, msg) VALUES (coalesce(c, false), m);
  RAISE NOTICE '% %', CASE WHEN coalesce(c, false) THEN 'OK   ' ELSE 'FALHA' END, m;
END $$;

-- ------------------------------------------------------------- auxiliares
SELECT pg_temp.ok(nai_chave('5592991712835') = nai_chave('559291712835'), 'chave: com e sem o 9 sao a mesma pessoa');
SELECT pg_temp.ok(nai_chave('5592991712835') <> nai_chave('5592991712836'), 'chave: numeros diferentes, chaves diferentes');
SELECT pg_temp.ok(nai_chave('(92) 99420-9841') = nai_chave('5592994209841'), 'chave: telefone do cadastro formatado casa com o da Z-API');
SELECT pg_temp.ok(nai_chave('219958210478302@lid') = 'lid:219958210478302', 'chave: @lid vira chave propria (nao e resolvido pelo nome)');
SELECT pg_temp.ok(nai_cpf_valido('529.982.247-25') = '52998224725', 'cpf valido');
SELECT pg_temp.ok(nai_cpf_valido('111.111.111-11') IS NULL AND nai_cpf_valido('123') IS NULL, 'cpf invalido recusado');
SELECT pg_temp.ok(nai_quando_humano(now() + interval '1 day' - (extract(hour FROM now() AT TIME ZONE 'America/Manaus') || ' hours')::interval
                  + interval '15 hours' - (extract(minute FROM now() AT TIME ZONE 'America/Manaus') || ' minutes')::interval) = 'amanhã à tarde, às 15h',
                  'quando humano: amanha a tarde, as 15h');
SELECT pg_temp.ok(nai_quem_atende('5596991712835', false) = 'nai', 'roteador: numero de teste cai na NAI');
SELECT pg_temp.ok(nai_quem_atende('559294717316', false) = 'nay', 'roteador: o resto continua na Nay antiga');
SELECT pg_temp.ok(nai_quem_atende('5596991712835', true) = 'nay', 'roteador: grupo nunca vai para a NAI');
SELECT pg_temp.ok((SELECT motivo FROM nai_proprietario_do_imovel(1327)) = 'tratar_com_outra_pessoa', 'proprietario "tratar com a Imob Easy" nao e contatado');
SELECT pg_temp.ok((SELECT motivo FROM nai_proprietario_do_imovel(5611)) IS NULL, 'proprietario do 5611 tem telefone');

-- ------------------------------------------------------ o corretor pede
INSERT INTO mensagens (telefone, nome, direcao, origem, texto, status, fluxo)
VALUES ('5596991712835', 'Tel Teste', 'recebida', 'texto', 'quero visitar o 5611 amanha 15h', 'Processando', 'nai');

DO $$
DECLARE cab jsonb; r record; amanha text;
BEGIN
  amanha := to_char((now() AT TIME ZONE 'America/Manaus')::date + 1, 'YYYY-MM-DD') || ' 15:00';
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'quero visitar o 5611 amanha 15h', NULL,
                         ARRAY[(SELECT max(id) FROM mensagens)]::bigint[]);
  PERFORM pg_temp.ok(cab->>'papel' = 'corretor' AND (cab->>'aprovado')::boolean, 'turno 1: corretor de teste aprovado');
  PERFORM pg_temp.ok(cab->>'memoria' LIKE 'nai:corretor:%', 'turno 1: memoria chaveada por contato, nao por telefone');

  SELECT * INTO r FROM nai_pedir_visita((cab->>'turno_id')::bigint, '5611', amanha, 'nao');
  PERFORM pg_temp.ok(coalesce(r.texto_pronto, '') NOT LIKE '%renda%',
                     'pedir visita: NAO pergunta renda -- isso nao esta no fluxo do Tel');
  SELECT * INTO r FROM nai_pedir_visita((cab->>'turno_id')::bigint, '5611', '2020-01-01 10:00', 'sim');
  PERFORM pg_temp.ok(r.texto_pronto LIKE 'Esse horário já passou 😅 Qual outro horário%', 'pedir visita: horario passado');
  SELECT * INTO r FROM nai_pedir_visita((cab->>'turno_id')::bigint, '9999', amanha, 'sim');
  PERFORM pg_temp.ok(r.instrucao_para_voce LIKE '%nao foi dito por ele%', 'pedir visita: codigo que ele nao disse e recusado');
  SELECT * INTO r FROM nai_pedir_visita((cab->>'turno_id')::bigint, '5611', amanha, 'sim');
  PERFORM pg_temp.ok(r.texto_pronto LIKE 'Vou confirmar aqui a visita%me passa o seu nome completo%', 'pedir visita: corretor novo, pede os dados dele');
  PERFORM pg_temp.ok((SELECT estado FROM nai_visita WHERE codigo = 5611 AND id > (SELECT visita FROM _base) ORDER BY id DESC LIMIT 1) = 'coletando', 'visita criada em coletando');

  SELECT * INTO r FROM nai_guardar_dados_visita((cab->>'turno_id')::bigint, NULL, 'Maria', '123', 'Tel Sobreira Teste', '529.982.247-25', 'CRECI 1234');
  PERFORM pg_temp.ok(r.texto_pronto LIKE '%CPF do visitante não confere%' AND r.texto_pronto LIKE '%nome COMPLETO do visitante%', 'dados: CPF e nome do visitante invalidos sao apontados');
  SELECT * INTO r FROM nai_guardar_dados_visita((cab->>'turno_id')::bigint, NULL, 'Maria da Silva', '390.533.447-05', NULL, NULL, NULL);
  PERFORM pg_temp.ok(r.texto_pronto LIKE 'Anotado! Já pedi a confirmação%', 'dados completos: pede ao proprietario');
  PERFORM pg_temp.ok((SELECT estado FROM nai_visita WHERE codigo = 5611 AND id > (SELECT visita FROM _base) ORDER BY id DESC LIMIT 1) = 'aguardando_proprietario', 'visita aguardando proprietario');

  PERFORM * FROM nai_liberar_saida((cab->>'turno_id')::bigint);
  SELECT * INTO r FROM nai_saida WHERE papel_destino = 'proprietario' AND id > (SELECT saida FROM _base) ORDER BY id DESC LIMIT 1;
  PERFORM pg_temp.ok(r.estado = 'simulado' AND r.redirecionado AND nai_chave(r.telefone_final) = nai_chave('5596991712835'),
                     'TESTE: pedido ao proprietario foi REDIRECIONADO ao numero de teste');
  PERFORM pg_temp.ok(r.resposta->>'texto_final' LIKE '🧪 TESTE · iria para o PROPRIETÁRIO%Tem como receber a visita nesse horário?',
                     'pedido ao proprietario com etiqueta e texto humanizado');
  PERFORM pg_temp.ok(r.resposta->>'texto_final' NOT LIKE '%/0%' AND r.resposta->>'texto_final' LIKE '%amanhã à tarde, às 15h%',
                     'pedido ao proprietario sem data numerica');
END $$;

-- ------------------------------------------------------ o proprietario responde
DO $$
DECLARE cab jsonb; r record; v bigint;
BEGIN
  SELECT id INTO v FROM nai_visita WHERE codigo = 5611 AND id > (SELECT visita FROM _base) ORDER BY id DESC LIMIT 1;
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'P: pode sim', NULL, '{}');
  PERFORM pg_temp.ok(cab->>'papel' = 'proprietario' AND (cab->>'visita_id')::bigint = v AND cab->>'texto' = 'pode sim',
                     'prefixo P: vira proprietario da visita certa, e o prefixo sai do texto');
  PERFORM pg_temp.ok(cab->>'memoria' LIKE 'nai:proprietario:%:v' || v, 'memoria do proprietario e separada, por visita');
  SELECT * INTO r FROM nai_resposta_proprietario((cab->>'turno_id')::bigint, 'aceita', NULL, NULL, NULL, NULL);
  -- O acesso do 5611 pode ja ter sido aprendido numa simulacao anterior: ai
  -- ela nao pergunta de novo, confirma direto.
  PERFORM pg_temp.ok(CASE WHEN (SELECT fonte FROM nai_acesso_imovel WHERE codigo = 5611) IS NULL
                          THEN r.texto_pronto LIKE '%como fica o acesso%'
                          ELSE r.texto_pronto LIKE 'Combinado, então: visita confirmada%' END,
                     'aceitou: pergunta o acesso (ou, se ja aprendido, confirma direto)');
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'P: fechadura eletronica, senha 4455', NULL, '{}');
  SELECT * INTO r FROM nai_resposta_proprietario((cab->>'turno_id')::bigint, 'acesso', NULL, 'fechadura eletrônica', NULL, '4455');
  PERFORM pg_temp.ok(r.texto_pronto LIKE 'Combinado, então: visita confirmada amanhã à tarde, às 15h%Maria da Silva%', 'acesso completo: confirma com o proprietario');
  PERFORM pg_temp.ok((SELECT estado FROM nai_visita WHERE id = v) = 'aguardando_motoboy', 'visita aguardando o Fernando');
  PERFORM pg_temp.ok((SELECT acesso FROM nai_acesso_imovel WHERE codigo = 5611) = 'fechadura', 'acesso aprendido para a proxima visita (sem a senha)');
  PERFORM pg_temp.ok((SELECT detalhe FROM nai_acesso_imovel WHERE codigo = 5611) IS DISTINCT FROM '4455', 'a senha NAO fica no aprendizado');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND papel_destino = 'motoboy' AND texto LIKE 'Oi, Fernando!%Posso confirmar%'
                             AND texto NOT LIKE '%4455%'), 'Fernando chamado, sem a senha antes da hora');
END $$;

-- ------------------------------------------------------ o Fernando confirma
DO $$
DECLARE cab jsonb; r record; v bigint;
BEGIN
  SELECT id INTO v FROM nai_visita WHERE codigo = 5611 AND id > (SELECT visita FROM _base) ORDER BY id DESC LIMIT 1;
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'M: confirmo', NULL, '{}');
  PERFORM pg_temp.ok(cab->>'papel' = 'motoboy' AND (cab->>'visita_id')::bigint = v, 'prefixo M: vira o Fernando na visita certa');
  SELECT * INTO r FROM nai_resposta_motoboy((cab->>'turno_id')::bigint, NULL, 'confirma', NULL);
  PERFORM pg_temp.ok((SELECT estado FROM nai_visita WHERE id = v) = 'confirmada', 'visita CONFIRMADA');
  PERFORM pg_temp.ok(r.texto_pronto LIKE 'Fechado, Fernando, agendei aqui:%fechadura eletrônica: te mando a senha%' AND r.texto_pronto NOT LIKE '%4455%',
                     'fluxo v10: Fernando confirmou -> agenda e avisa o acesso (sem a senha antes da hora)');
  SELECT * INTO r FROM nai_saida WHERE visita_id = v AND motivo = 'visita_confirmada';
  PERFORM pg_temp.ok(r.papel_destino = 'corretor' AND r.texto LIKE 'Visita confirmada%Fernando, (92)%fechadura eletrônica%'
                     AND r.texto NOT LIKE '%4455%' AND r.texto NOT LIKE '%Yuri%', 'confirmacao ao corretor: com o Fernando, sem senha, sem nome do proprietario');
END $$;

-- ------------------------------------------------------ a agenda
DO $$
DECLARE v bigint; n int;
BEGIN
  SELECT id INTO v FROM nai_visita WHERE codigo = 5611 AND id > (SELECT visita FROM _base) ORDER BY id DESC LIMIT 1;
  UPDATE nai_visita SET quando = now() + interval '50 minutes', confirmada_em = now() - interval '3 hours' WHERE id = v;
  n := nai_agenda_tick();
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND motivo = 'lembrete_1h'), 'agenda: lembrete de 1h ao corretor');
  UPDATE nai_visita SET quando = now() + interval '20 minutes' WHERE id = v;
  n := nai_agenda_tick();
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND motivo = 'aviso_motoboy' AND texto LIKE '%4455%'),
                     'agenda: senha vai ao Fernando 30 min antes');
  n := nai_agenda_tick();
  PERFORM pg_temp.ok((SELECT count(*) FROM nai_saida WHERE visita_id = v AND motivo IN ('lembrete_1h', 'aviso_motoboy')) = 2,
                     'agenda: rodar de novo nao repete nada');
  UPDATE nai_visita SET quando = now() - interval '70 minutes' WHERE id = v;
  n := nai_agenda_tick();
  PERFORM pg_temp.ok((SELECT estado FROM nai_visita WHERE id = v) = 'realizada' AND (SELECT senha FROM nai_visita WHERE id = v) IS NULL,
                     'agenda: depois da visita pergunta como foi e APAGA a senha');
END $$;

-- ------------------------------------------------------ as paredes
DO $$
DECLARE v bigint; outro bigint; falhou boolean;
BEGIN
  SELECT id INTO v FROM nai_visita WHERE codigo = 5611 AND id > (SELECT visita FROM _base) ORDER BY id DESC LIMIT 1;
  outro := nai_contato_de('5592988887777', 'Outro Corretor');
  falhou := false;
  BEGIN
    PERFORM nai_enfileirar_texto(NULL, v, outro, 'corretor', 'isso nao pode sair', 'teste');
  EXCEPTION WHEN others THEN falhou := true; END;
  PERFORM pg_temp.ok(falhou, 'PAREDE: mensagem da visita de um corretor para OUTRO corretor e recusada');
  falhou := false;
  BEGIN
    INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, imagem_url, codigo)
    SELECT (SELECT max(id) FROM nai_turno WHERE papel = 'corretor'), (SELECT contato_id FROM nai_turno WHERE papel = 'corretor' ORDER BY id DESC LIMIT 1),
           'turno', '', 'imagem', (SELECT url FROM imovel_fotos WHERE codigo = 2014 LIMIT 1), 5611;
  EXCEPTION WHEN others THEN falhou := true; END;
  PERFORM pg_temp.ok(falhou, 'PAREDE: foto do 2014 declarada como do 5611 e recusada');
  falhou := false;
  BEGIN
    PERFORM nai_enfileirar_texto((SELECT max(id) FROM nai_turno WHERE papel = 'corretor'), NULL, outro, 'turno', 'resposta para quem nao perguntou', 'teste');
  EXCEPTION WHEN others THEN falhou := true; END;
  PERFORM pg_temp.ok(falhou, 'PAREDE: resposta de um turno para quem nao escreveu e recusada');
  falhou := false;
  BEGIN
    UPDATE nai_saida SET contato_id = outro WHERE id = (SELECT max(id) FROM nai_saida);
  EXCEPTION WHEN others THEN falhou := true; END;
  PERFORM pg_temp.ok(falhou, 'PAREDE: destino de mensagem enfileirada nao muda');
END $$;

-- no teste, nada sai para numero fora da lista
DO $$
DECLARE outro bigint; t bigint; r record;
BEGIN
  outro := nai_contato_de('5592988887777', 'Outro Corretor');
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (outro, 'corretor', false) RETURNING id INTO t;
  PERFORM nai_enfileirar_texto(t, NULL, outro, 'turno', 'oi', 'teste');
  PERFORM * FROM nai_liberar_saida(t);
  SELECT * INTO r FROM nai_saida WHERE turno_id = t;
  PERFORM pg_temp.ok(r.estado = 'bloqueado' AND r.bloqueio = 'teste_fora_da_lista', 'PAREDE DO TESTE: numero fora da lista nao recebe nada');
END $$;

-- ------------------------------------------------------ fotos
DO $$
DECLARE cab jsonb; j jsonb; n int;
BEGIN
  INSERT INTO mensagens (telefone, nome, direcao, origem, texto, status, fluxo)
  VALUES ('5596991712835', 'Tel Teste', 'recebida', 'texto', 'tem imagens do 2014?', 'Processando', 'nai');
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'tem imagens do 2014?', NULL, ARRAY[(SELECT max(id) FROM mensagens)]::bigint[]);
  j := nai_enfileirar_resposta((cab->>'turno_id')::bigint, 'boa tarde! desse imóvel não temos imagens cadastradas no momento.',
                               '["2014"]', 'tem imagens do 2014?', '[]');
  SELECT count(*) INTO n FROM nai_saida WHERE turno_id = (cab->>'turno_id')::bigint AND tipo = 'imagem' AND codigo = 2014;
  -- A conta e contra nai_imagens_do_envio, nao contra imovel_fotos: desde
  -- 12/09 sai tambem a COLAGEM, na frente das fotos (pedido do Tel).
  PERFORM pg_temp.ok(j->>'guarda' = 'negacao_corrigida' AND n = (SELECT count(*) FROM nai_imagens_do_envio(2014)),
                     'FOTOS: o caso Regiane -- ela nega, a guarda corrige e as ' || n || ' imagens saem');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM imovel_colagem WHERE codigo = 2014)
                     OR (SELECT motivo FROM nai_saida WHERE turno_id = (cab->>'turno_id')::bigint
                          AND tipo = 'imagem' ORDER BY ordem LIMIT 1) = 'colagem',
                     'COLAGEM: quando existe, vai na FRENTE das fotos');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = (cab->>'turno_id')::bigint AND tipo = 'texto'
                                  AND texto ~* 'n[ãa]o temos imagens'), 'FOTOS: a frase de negacao nao sai');

  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'tem imagens do 2014?', NULL, '{}');
  j := nai_enfileirar_resposta((cab->>'turno_id')::bigint, 'entendi, sem fotos então. o valor é 4.300.', '["2014"]', 'so quero o valor, ja tenho as fotos', '[]');
  PERFORM pg_temp.ok(coalesce((j->>'fotos')::int, 0) = 0 AND j->>'guarda' IS NULL, 'FOTOS: quem disse que ja tem as fotos nao recebe de novo');
END $$;

SELECT pg_temp.ok(nai_fotos_faltando(ARRAY[2014, 5611]) = '{}', 'FOTOS: 2014 e 5611 tem foto na tabela');

-- ------------------------------------ cenario 2: proprietario pede outro horario
INSERT INTO mensagens (telefone, nome, direcao, origem, texto, status, fluxo)
VALUES ('5596991712835', 'Tel Teste', 'recebida', 'texto', 'visita no 4255 depois de amanha 10h', 'Processando', 'nai');
DO $$
DECLARE cab jsonb; r record; v bigint; q text; n int;
BEGIN
  q := to_char((now() AT TIME ZONE 'America/Manaus')::date + 2, 'YYYY-MM-DD') || ' 10:00';
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'visita no 4255', NULL, ARRAY[(SELECT max(id) FROM mensagens)]::bigint[]);
  SELECT * INTO r FROM nai_pedir_visita((cab->>'turno_id')::bigint, '4255', q, 'sim');
  PERFORM pg_temp.ok(r.texto_pronto LIKE '%nome completo e o CPF do visitante%', 'cenario 2: corretor ja conhecido so pede o visitante');
  SELECT * INTO r FROM nai_guardar_dados_visita((cab->>'turno_id')::bigint, '4255', 'Joao Pereira Lima', '390.533.447-05', NULL, NULL, NULL);
  SELECT id INTO v FROM nai_visita WHERE codigo = 4255 AND id > (SELECT visita FROM _base) ORDER BY id DESC LIMIT 1;
  PERFORM * FROM nai_liberar_saida((cab->>'turno_id')::bigint);

  -- proprietario nao responde: a agenda manda de novo depois de 30 min
  UPDATE nai_visita SET ult_msg_prop_em = now() - interval '31 minutes' WHERE id = v;
  n := nai_agenda_tick();
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND motivo = 'p_lembrete'), 'agenda: 30 min sem resposta, manda de novo ao proprietario');
  PERFORM * FROM nai_liberar_saida(NULL);
  UPDATE nai_visita SET ult_msg_prop_em = now() - interval '31 minutes' WHERE id = v;
  n := nai_agenda_tick();
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND motivo = 'p_avisa' AND papel_destino = 'corretor'),
                     'agenda: continua sem resposta, avisa o corretor da demora');

  -- agora ele responde com outro horario (marcando a mensagem redirecionada)
  PERFORM * FROM nai_liberar_saida(NULL);
  UPDATE nai_saida SET message_id = 'TESTE-MSG-1' WHERE id = (SELECT max(id) FROM nai_saida WHERE visita_id = v AND papel_destino = 'proprietario' AND estado = 'simulado');
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'amanha nao, so as 16h', 'TESTE-MSG-1', '{}');
  PERFORM pg_temp.ok(cab->>'papel' = 'proprietario' AND (cab->>'visita_id')::bigint = v, 'MARCAR a mensagem redirecionada vira proprietario daquela visita');
  q := to_char((now() AT TIME ZONE 'America/Manaus')::date + 2, 'YYYY-MM-DD') || ' 16:00';
  SELECT * INTO r FROM nai_resposta_proprietario((cab->>'turno_id')::bigint, 'outro_horario', q, NULL, NULL, NULL);
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND motivo = 'proprietario_sugeriu' AND texto LIKE '%mas sugeriu%às 16h%Funciona pro seu cliente?'),
                     'proprietario sugeriu: o corretor recebe a proposta');

  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'pode ser', NULL, '{}');
  PERFORM pg_temp.ok(cab->>'papel' = 'corretor', 'sem prefixo e sem marcar: e o corretor');
  SELECT * INTO r FROM nai_responder_horario((cab->>'turno_id')::bigint, '4255', 'sim', NULL);
  PERFORM pg_temp.ok((SELECT extract(hour FROM quando AT TIME ZONE 'America/Manaus') FROM nai_visita WHERE id = v) = 16
                     AND (SELECT prop_ok_em FROM nai_visita WHERE id = v) IS NOT NULL, 'corretor aceitou: horario do proprietario vale como aceite dele');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND motivo = 'fecha_novo_horario' AND papel_destino = 'proprietario'
                             AND texto LIKE 'Fechado! O corretor confirmou%às 16h.%'),
                     'fluxo v10: card "Fecha o novo horario" vai ao proprietario');

  -- comandos do Tel
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'T: VISITAS', NULL, '{}');
  PERFORM pg_temp.ok(cab->>'papel' = 'tel' AND nai_e_comando_tel(cab->>'texto'), 'prefixo T: vira o Tel, e VISITAS e comando');
  SELECT * INTO r FROM nai_comando_tel((cab->>'turno_id')::bigint, cab->>'texto');
  PERFORM pg_temp.ok(r.msg_tel LIKE 'Visitas em andamento:%#' || v || '%', 'VISITAS lista as visitas');
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'T: visita ' || v || ' cancela', NULL, '{}');
  SELECT * INTO r FROM nai_comando_tel((cab->>'turno_id')::bigint, cab->>'texto');
  PERFORM pg_temp.ok((SELECT estado FROM nai_visita WHERE id = v) = 'cancelada'
                     AND EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND motivo = 'cancelada_pelo_tel'), 'VISITA N CANCELA cancela e avisa o corretor');
END $$;

-- ------------------------------------------------ visita urgente (3h)
DO $$
DECLARE cab jsonb; r record; v bigint; q text;
BEGIN
  INSERT INTO mensagens (telefone, nome, direcao, origem, texto, status, fluxo)
  VALUES ('5596991712835', 'Tel Teste', 'recebida', 'texto', 'quero visitar o 4255 daqui a pouco', 'Processando', 'nai');
  q := to_char((now() + interval '90 minutes') AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI');
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'quero visitar o 4255 daqui a pouco', NULL, ARRAY[(SELECT max(id) FROM mensagens)]::bigint[]);
  SELECT * INTO r FROM nai_pedir_visita((cab->>'turno_id')::bigint, '4255', q, 'sim');
  SELECT id INTO v FROM nai_visita WHERE codigo = 4255 AND id > (SELECT visita FROM _base) ORDER BY id DESC LIMIT 1;
  PERFORM pg_temp.ok(r.texto_pronto IS NULL AND r.instrucao_para_voce LIKE '%SILENCIO%',
                     'URGENTE: o corretor NAO e avisado (so o Tel)');
  PERFORM pg_temp.ok((SELECT estado FROM nai_visita WHERE id = v) = 'com_tel'
                     AND (SELECT aguardando FROM nai_visita WHERE id = v) = 'tel'
                     AND (SELECT urgente FROM nai_visita WHERE id = v), 'URGENTE: a visita fica com o Tel, a IA para');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND papel_destino = 'tel'
                             AND texto LIKE '%VISITA URGENTE%' AND texto LIKE '%parei aqui%'),
                     'URGENTE: o Tel recebe o pedido inteiro e sabe que a IA parou');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND papel_destino IN ('proprietario', 'motoboy', 'corretor')),
                     'URGENTE: nada saiu para proprietario, Fernando nem corretor');
  PERFORM pg_temp.ok((SELECT nai_linha_acesso_corretor('chave_conosco')) LIKE '%providencio%'
                     AND (SELECT nai_linha_acesso_corretor('chave_conosco')) NOT LIKE '%Fernando leva%',
                     'CHAVE CONOSCO: ao corretor ela so diz que providencia');
  -- a agenda nao manda "nao consegui fechar" numa visita que estava com o Tel
  UPDATE nai_visita SET quando = now() - interval '5 minutes' WHERE id = v;
  PERFORM nai_agenda_tick();
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND motivo = 'expirada' AND papel_destino = 'corretor'),
                     'URGENTE: visita com o Tel nao leva "nao consegui fechar" ao corretor');
END $$;

SELECT pg_temp.ok(nai_ler_hora_tel('HORARIO 13/09 16h', now()) IS NOT NULL AND nai_ler_hora_tel('avisa 10h30', now()) IS NOT NULL, 'hora do comando do Tel');
SELECT pg_temp.ok(nai_acesso_normalizar('a chave fica com a gente') = 'chave_conosco' AND nai_acesso_normalizar('pega a chave na portaria') = 'buscar_chave'
                  AND nai_acesso_normalizar('eu abro') = 'proprietario_acompanha', 'tipos de acesso');

-- ------------------------------------------------------ fluxo v10 (11/09)
DO $$
DECLARE cab jsonb; k bigint; t1 bigint; t2 bigint; t3 bigint; j jsonb; r record; x text;
BEGIN
  -- CONTEXTO: segunda mensagem do dia nao e atendida como a primeira
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'e esse outro?', NULL, '{}');
  PERFORM pg_temp.ok(cab->>'contexto' LIKE '%JA ESTAO CONVERSANDO%', 'CONTEXTO: ela sabe que ja estao conversando');
  PERFORM pg_temp.ok(cab->>'contexto' LIKE '%visitas em andamento%' OR cab->>'contexto' LIKE '%nao tem visita em andamento%', 'CONTEXTO: visitas continuam no contexto');

  -- VISITA SEM FORCAR A BARRA
  k := nai_contato_de('5592977776666', 'Corretor Guarda');
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t1;
  j := nai_enfileirar_resposta(t1, 'Sobre isso: fica 4.300 😉 Quer que eu já veja um horário de visita pro seu cliente?', '[]', 'qual o valor do 5611?', '[]');
  PERFORM pg_temp.ok((SELECT visita_sugerida_em FROM nai_contato WHERE id = k) IS NOT NULL
                     AND EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t1 AND texto LIKE '%Quer que eu já veja um horário de visita%'),
                     'VISITA: a primeira sugestao sai e fica registrada');
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t2;
  j := nai_enfileirar_resposta(t2, 'Tenho também esse no Aleixo por 3.900. Quer agendar uma visita?', '[]', 'tem outro?', '[]');
  SELECT texto INTO x FROM nai_saida WHERE turno_id = t2 AND tipo = 'texto';
  PERFORM pg_temp.ok(j->>'guarda' = 'visita_repetida_cortada' AND x = 'Tenho também esse no Aleixo por 3.900.',
                     'VISITA: a segunda sugestao e cortada (sobrou: ' || coalesce(x, 'nada') || ')');
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t3;
  j := nai_enfileirar_resposta(t3, 'Claro! Quer agendar a visita pra quando?', '[]', 'quero visitar esse', '[]');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t3 AND texto LIKE '%agendar a visita%'),
                     'VISITA: quando ELE pede visita, ela fala de visita normalmente');

  -- uma pergunta por mensagem: duas da sequencia viram so a primeira
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t3;
  j := nai_enfileirar_resposta(t3, 'Tem sim! Qual bairro o Sr. está buscando e qual a faixa de preço?', '[]', 'tem outras opcoes?', '[]');
  SELECT texto INTO x FROM nai_saida WHERE turno_id = t3 AND tipo = 'texto';
  PERFORM pg_temp.ok(x LIKE '%em qual bairro?' AND x NOT LIKE '%faixa de preço%',
                     'SEQUENCIA: duas perguntas numa mensagem viram so a do bairro (' || coalesce(left(x, 45), 'nada') || ')');
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t3;
  j := nai_enfileirar_resposta(t3, '📍 Condomínio Acquarelle' || chr(10) || '• Bairro: Ponta Negra' || chr(10) || '• mobiliado' || chr(10) || 'Código: 5611', '[]', 'manda o 5611', '[]');
  SELECT texto INTO x FROM nai_saida WHERE turno_id = t3 AND tipo = 'texto';
  PERFORM pg_temp.ok(x LIKE '%Código: 5611%', 'SEQUENCIA: card de imovel com bairro e mobilia NAO e trocado por pergunta');

  -- O TEL ASSUMIU
  PERFORM nai_confirmar_envio((SELECT id FROM nai_saida WHERE turno_id = t1 LIMIT 1), '{}'::jsonb);
  UPDATE nai_saida SET estado = 'enviado', message_id = 'ECO-TESTE-1', enviado_em = now() WHERE turno_id = t1;
  j := nai_tel_assumiu('5592977776666', 'ECO-TESTE-1', 'qualquer');
  PERFORM pg_temp.ok((j->>'eco_nosso')::boolean AND (SELECT humano_assumiu_em FROM nai_contato WHERE id = k) IS NULL,
                     'TEL ASSUMIU: o eco da propria NAI (mesmo ID) nao conta como o Tel');
  j := nai_tel_assumiu('5592977776666', 'CEL-TESTE-1', 'oi, aqui é o Tel, deixa comigo');
  PERFORM pg_temp.ok((j->>'tel_assumiu')::boolean AND (SELECT humano_assumiu_em FROM nai_contato WHERE id = k) IS NOT NULL,
                     'TEL ASSUMIU: mensagem do Tel pelo celular desliga a NAI nesse chat');
  PERFORM nai_enfileirar_texto(t2, NULL, k, 'turno', 'isso nao pode sair', 'teste');
  PERFORM * FROM nai_liberar_saida(t2);
  PERFORM pg_temp.ok((SELECT bloqueio FROM nai_saida WHERE turno_id = t2 AND texto = 'isso nao pode sair') = 'tel_assumiu',
                     'TEL ASSUMIU: nada mais sai para essa pessoa');

  UPDATE nai_contato SET humano_assumiu_em = now() WHERE chave = nai_chave('5596991712835');
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'oi', NULL, '{}');
  PERFORM pg_temp.ok(cab->>'ok' = 'false' AND cab->>'motivo' = 'tel_assumiu', 'TEL ASSUMIU: a NAI nao abre turno nesse chat');
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'T: DEVOLVER 96991712835', NULL, '{}');
  PERFORM pg_temp.ok(cab->>'papel' = 'tel' AND nai_e_comando_tel(cab->>'texto'), 'DEVOLVER e comando do Tel e passa mesmo com o chat assumido');
  SELECT * INTO r FROM nai_comando_tel((cab->>'turno_id')::bigint, cab->>'texto');
  PERFORM pg_temp.ok((SELECT humano_assumiu_em FROM nai_contato WHERE chave = nai_chave('5596991712835')) IS NULL AND r.msg_tel LIKE 'Feito: a NAI volta%',
                     'DEVOLVER: a NAI volta a atender');
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'T: ASSUMIR 92 97777-6666', NULL, '{}');
  SELECT * INTO r FROM nai_comando_tel((cab->>'turno_id')::bigint, cab->>'texto');
  PERFORM pg_temp.ok(r.msg_tel LIKE 'Feito: a conversa com%é sua%', 'ASSUMIR: o Tel pega a conversa pelo comando');

  -- BAIRRO + BAIRROS AO REDOR
  -- a SEQUENCIA do fluxo mora na ferramenta: uma pergunta por vez
  SELECT * INTO r FROM nai_buscar_por_perfil(t1, NULL, NULL, NULL, NULL);
  PERFORM pg_temp.ok(r.texto_pronto LIKE '%em qual bairro?' AND r.texto_pronto NOT LIKE '%preço%',
                     'SEQUENCIA 1/3: sem nada, pergunta SO o bairro');
  SELECT * INTO r FROM nai_buscar_por_perfil(t1, 'Ponta Negra', NULL, NULL, NULL);
  PERFORM pg_temp.ok(r.texto_pronto LIKE 'E qual a faixa de preço%' AND r.texto_pronto NOT LIKE '%bairro%',
                     'SEQUENCIA 2/3: com bairro, pergunta SO a faixa de preco');
  SELECT * INTO r FROM nai_buscar_por_perfil(t1, 'Ponta Negra', '8000', NULL, NULL);
  PERFORM pg_temp.ok(r.texto_pronto LIKE 'E eles têm preferência%',
                     'SEQUENCIA 3/3: com bairro e preco, pergunta SO a mobilia');
  SELECT * INTO r FROM nai_buscar_por_perfil(t1, 'Ponta Negra', '8000', NULL, 'semimobiliado');
  PERFORM pg_temp.ok(r.texto_pronto LIKE 'Encontrei %', 'BUSCA: bairro com resultado responde a lista (' || left(coalesce(r.texto_pronto, 'nada'), 40) || ')');
  PERFORM pg_temp.ok(nai_lista_pt(ARRAY['seu nome completo', 'CPF', 'CRECI']) = 'seu nome completo, CPF e CRECI', 'lista em portugues');
END $$;

SELECT count(*) FILTER (WHERE ok) AS passaram, count(*) FILTER (WHERE NOT ok) AS falharam FROM _r;
