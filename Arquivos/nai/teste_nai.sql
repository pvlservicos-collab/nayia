-- =====================================================================
-- Teste da NAI. Roda DENTRO de uma transacao que termina em ROLLBACK:
-- nada fica gravado. Uso (no servidor), COM ponto e virgula no BEGIN:
--   (echo 'BEGIN;'; cat teste_nai.sql; echo 'ROLLBACK;') | psql ...
-- Cada verificacao imprime OK ou FALHA; no fim, o total.
--
-- 13/09/2026: reescrito para o fluxo v17/v18 do site -- o pedido de horario
-- vai direto ao proprietario, os dados so depois da visita confirmada, e todo
-- final do fluxo sobe para o Tel e PARA o chat (sem "vou ver e te aviso").
-- =====================================================================
SET client_min_messages = notice;
UPDATE nai_config SET valor = 'teste' WHERE chave = 'modo';
UPDATE nai_config SET valor = 'sim' WHERE chave = 'envio_simulado';
UPDATE nai_config SET valor = 'nao' WHERE chave = 'pausada';
UPDATE nai_config SET valor = '00:00' WHERE chave = 'janela_inicio';
UPDATE nai_config SET valor = '23:59' WHERE chave = 'janela_fim';
-- A lista de teste de VERDADE muda (13/09 entrou o numero do Tel); o teste parte
-- da lista so com o numero de teste e o bloco "numero do Tel" poe o dele.
UPDATE nai_config SET valor = '5596991712835' WHERE chave = 'numeros_teste';
-- O numero de teste escala SEM parar o chat na vida real (13/09); os cenarios
-- abaixo testam o comportamento normal -- a excecao tem teste proprio.
UPDATE nai_config SET valor = '' WHERE chave = 'escala_sem_parar';
-- A regra de quem a Nay atende nasce DESLIGADA e os testes dela ligam sozinhos.
UPDATE nai_config SET valor = 'nao' WHERE chave = 'regra_publico';

-- O teste roda contra o banco de verdade (dentro de BEGIN/ROLLBACK). Visita
-- aberta de um teste MANUAL anterior com o mesmo numero faria o cenario 1
-- cair em "ja existe visita em andamento" e derrubaria 20 verificacoes --
-- aconteceu em 12/09. Aqui elas sao encerradas, e o ROLLBACK devolve tudo.
UPDATE nai_visita SET estado = 'encerrada', encerrada_em = now()
 WHERE corretor_id IN (SELECT id FROM nai_contato WHERE chave = nay_fone_chave('5596991712835'))
   AND estado NOT IN ('encerrada', 'cancelada', 'expirada');

-- Pelo mesmo motivo, os CONTATOS de teste voltam ao estado de quem nunca
-- falou com a NAI (dados do corretor, sugestao de visita de hoje e chat
-- parado). O ROLLBACK devolve tudo.
UPDATE nai_contato SET nome_completo = NULL, cpf = NULL, creci = NULL,
       visita_sugerida_em = NULL, humano_assumiu_em = NULL, humano_motivo = NULL
 WHERE chave IN (SELECT nay_fone_chave(x) FROM unnest(ARRAY[
   '559291712835', '559294717316', '5592977776666', '5592988887777',
   '5592991712835', '5592991712836', '5592994209841', '5596991712835']) x);
-- Chat do proprietario/Fernando parado por teste manual anterior tambem volta.
UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE humano_motivo LIKE 'visita #%';

-- Os message_id ficticios do teste sao unicos POR RODADA.
UPDATE nai_saida SET message_id = NULL WHERE message_id IN ('TESTE-MSG-1', 'ECO-TESTE-1');

-- O acesso do imovel e APRENDIDO (nai_acesso_imovel): os imoveis do teste
-- voltam a "nao sei"; o ROLLBACK devolve o aprendizado.
DELETE FROM nai_acesso_imovel WHERE codigo IN (5611, 4255, 2014);

-- A guarda "repetida" (03_saida.sql) barra texto igual ao mesmo contato em 10
-- minutos: as saidas recentes envelhecem; o ROLLBACK devolve.
UPDATE nai_saida SET enviado_em = enviado_em - interval '2 hours'
 WHERE enviado_em > now() - interval '30 minutes';

-- O CENARIO E DO TESTE, NAO DO CATALOGO (15/09/2026). A bateria usa imoveis
-- reais pelo codigo, e em 15/09 o Tel mandou "alugado 5611": o Acquarelle saiu
-- do mercado de verdade, `nai_pedir_visita` passou a responder "esse imovel
-- saiu do mercado" e 51 testes cairam em cascata -- sem que nada no codigo
-- tivesse mudado. Um dia normal de trabalho do Tel nao pode quebrar a bateria.
--
-- Aqui os imoveis que o teste usa sao postos de pe DENTRO da transacao. O
-- ROLLBACK do fim desfaz, entao o catalogo real continua dizendo a verdade.
UPDATE imoveis SET disponivel = true, bloqueado = false
 WHERE codigo IN (5611, 5717, 4159, 4255, 5729, 5718, 2014) AND NOT coalesce(disponivel, true);

-- Marco zero: tudo o que o teste cria tem id MAIOR que isto.
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
-- CPF pela CONTAGEM dos digitos (Tel, 15/09: "ela tem que aceitar o cpf mesmo
-- errado so conferir os digitos mesmo"). O 97065110234 e o numero do teste
-- dele, que a conta da Receita recusava e deixava a visita em loop.
SELECT pg_temp.ok(nai_cpf_valido('529.982.247-25') = '52998224725', 'cpf: pontuacao sai e sobram os 11 numeros');
SELECT pg_temp.ok(nai_cpf_valido('97065110234') = '97065110234', 'cpf: digito verificador errado PASSA (ordem do Tel, 15/09)');
SELECT pg_temp.ok(nai_cpf_valido('970 651 102 34') = '97065110234', 'cpf: escrito com espacos tambem passa');
SELECT pg_temp.ok(nai_cpf_valido('9706511023') IS NULL AND nai_cpf_valido('970651102345') IS NULL AND nai_cpf_valido('123') IS NULL,
                  'cpf: quantidade errada de digitos continua sendo pedido de novo');
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
DECLARE cab jsonb; r record; amanha text; v bigint;
BEGIN
  amanha := to_char((now() AT TIME ZONE 'America/Manaus')::date + 1, 'YYYY-MM-DD') || ' 15:00';
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'quero visitar o 5611 amanha 15h', NULL,
                         ARRAY[(SELECT max(id) FROM mensagens)]::bigint[]);
  PERFORM pg_temp.ok(cab->>'papel' = 'corretor' AND (cab->>'aprovado')::boolean, 'turno 1: corretor de teste aprovado');
  PERFORM pg_temp.ok(cab->>'memoria' LIKE 'nai:corretor:%', 'turno 1: memoria chaveada por contato, nao por telefone');

  SELECT * INTO r FROM nai_pedir_visita((cab->>'turno_id')::bigint, '5611', '2020-01-01 10:00', '');
  PERFORM pg_temp.ok(r.texto_pronto LIKE 'Esse horário já passou. Qual outro horário%', 'pedir visita: horario passado');
  SELECT * INTO r FROM nai_pedir_visita((cab->>'turno_id')::bigint, '9999', amanha, '');
  PERFORM pg_temp.ok(r.instrucao_para_voce LIKE '%nao foi dito por ele%', 'pedir visita: codigo que ele nao disse e recusado');

  SELECT * INTO r FROM nai_pedir_visita((cab->>'turno_id')::bigint, '5611', amanha, '');
  SELECT id INTO v FROM nai_visita WHERE codigo = 5611 AND id > (SELECT visita FROM _base) ORDER BY id DESC LIMIT 1;
  PERFORM pg_temp.ok(r.texto_pronto IS NULL AND r.instrucao_para_voce LIKE '%SILENCIO%',
                     'FLUXO v17: pediu o horario -> o corretor NAO recebe nada (fica calada)');
  PERFORM pg_temp.ok(coalesce(r.instrucao_para_voce, '') NOT LIKE '%renda%'
                     AND NOT EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND papel_destino IN ('corretor', 'turno')),
                     'FLUXO v17: nao pede dado nenhum antes do proprietario (nem renda, nem CPF)');
  PERFORM pg_temp.ok((SELECT estado FROM nai_visita WHERE id = v) = 'aguardando_proprietario', 'FLUXO v17: foi DIRETO ao proprietario');

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
  PERFORM pg_temp.ok(r.texto_pronto = 'E como é para entrar? precisa de chave?', 'aceitou: pergunta o acesso, curto (Tel 13/09)');
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'P: fechadura eletronica, senha 4455', NULL, '{}');
  SELECT * INTO r FROM nai_resposta_proprietario((cab->>'turno_id')::bigint, 'acesso', NULL, 'fechadura eletrônica', NULL, '4455');
  PERFORM pg_temp.ok(r.texto_pronto LIKE 'Combinado, então: visita confirmada amanhã à tarde, às 15h. O ' || nai_acompanhante() || ', da nossa equipe, acompanha a visita.%',
                     'acesso completo: confirma com o proprietario (card c_prop)');
  PERFORM pg_temp.ok(r.texto_pronto NOT LIKE '%CPF%' AND r.texto_pronto NOT LIKE '%visitante%',
                     'FLUXO v17: a confirmacao ao proprietario vai SEM os dados do visitante');
  PERFORM pg_temp.ok((SELECT estado FROM nai_visita WHERE id = v) = 'aguardando_motoboy', 'visita aguardando o Fernando');
  PERFORM pg_temp.ok((SELECT acesso FROM nai_acesso_imovel WHERE codigo = 5611) = 'fechadura', 'acesso aprendido para a proxima visita (sem a senha)');
  PERFORM pg_temp.ok((SELECT detalhe FROM nai_acesso_imovel WHERE codigo = 5611) IS DISTINCT FROM '4455', 'a senha NAO fica no aprendizado');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND papel_destino = 'motoboy' AND texto LIKE 'Olá, reservamos uma visita ao imóvel%Posso confirmar que você vai acompanhar?' AND texto NOT LIKE '%fechadura%'
                             AND texto NOT LIKE '%4455%'), 'acompanhante chamado, sem a senha antes da hora');
END $$;

-- ------------------------------------------------------ o Fernando confirma, e SO ENTAO os dados
DO $$
DECLARE cab jsonb; r record; v bigint; n int;
BEGIN
  SELECT id INTO v FROM nai_visita WHERE codigo = 5611 AND id > (SELECT visita FROM _base) ORDER BY id DESC LIMIT 1;
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'M: confirmo', NULL, '{}');
  PERFORM pg_temp.ok(cab->>'papel' = 'motoboy' AND (cab->>'visita_id')::bigint = v, 'prefixo M: vira o Fernando na visita certa');
  SELECT * INTO r FROM nai_resposta_motoboy((cab->>'turno_id')::bigint, NULL, 'confirma', NULL);
  PERFORM pg_temp.ok((SELECT estado FROM nai_visita WHERE id = v) = 'confirmada', 'visita CONFIRMADA');
  PERFORM pg_temp.ok(r.texto_pronto LIKE 'Fechado, ' || nai_acompanhante() || ', agendei aqui:%fechadura eletrônica: te mando a senha%' AND r.texto_pronto NOT LIKE '%4455%',
                     'Fernando confirmou -> agenda e avisa o acesso (sem a senha antes da hora)');
  SELECT * INTO r FROM nai_saida WHERE visita_id = v AND motivo = 'visita_confirmada';
  PERFORM pg_temp.ok(r.papel_destino = 'corretor' AND r.texto LIKE 'Visita confirmada%' || nai_acompanhante() || ', (92)%fechadura eletrônica%'
                     AND r.texto NOT LIKE '%4455%' AND r.texto NOT LIKE '%Yuri%', 'confirmacao ao corretor: com o acompanhante, sem senha, sem nome do proprietario');
  SELECT * INTO r FROM nai_saida WHERE visita_id = v AND motivo = 'pedir_dados';
  PERFORM pg_temp.ok(r.papel_destino = 'corretor' AND r.texto = 'Me passa o seu nome completo, o CPF e o CRECI?'
                     AND r.ordem > (SELECT ordem FROM nai_saida WHERE visita_id = v AND motivo = 'visita_confirmada'),
                     'FLUXO v17: DEPOIS da confirmacao pede os dados (corretor novo: os dele) (' || coalesce(r.texto, 'nada') || ')');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND texto ~* 'vou confirmar aqui|j[áa] te retorno'),
                     'FLUXO v17: sem "vou confirmar aqui a visita e ja te retorno"');

  -- Revisao: sem resposta, a agenda cobra o que falta
  UPDATE nai_visita SET proximo_lembrete_dados_em = now() - interval '1 minute' WHERE id = v;
  n := nai_agenda_tick();
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND motivo = 'dados_falta' AND texto LIKE 'Só falta %pra eu fechar a visita%'),
                     'Revisao: a agenda cobra os dados que faltam na visita confirmada');

  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'Maria 123, eu sou Tel Sobreira Teste', NULL, '{}');
  PERFORM pg_temp.ok(cab->>'papel' = 'corretor', 'dados: quem manda e o corretor');
  SELECT * INTO r FROM nai_guardar_dados_visita((cab->>'turno_id')::bigint, NULL, 'Maria', '123', 'Tel Sobreira Teste', '529.982.247-25', 'CRECI 1234');
  PERFORM pg_temp.ok(r.texto_pronto LIKE '%CPF do visitante não confere%' AND r.texto_pronto LIKE '%nome COMPLETO do visitante%', 'dados: CPF e nome do visitante invalidos sao apontados');
  SELECT * INTO r FROM nai_guardar_dados_visita((cab->>'turno_id')::bigint, NULL, NULL, NULL, NULL, NULL, NULL);
  PERFORM pg_temp.ok(r.texto_pronto = 'Anotado! Agora pode passar o nome completo e o CPF do visitante?', 'CORRETOR NOVO: gravou os dados dele, agora pede os do visitante');
  SELECT * INTO r FROM nai_guardar_dados_visita((cab->>'turno_id')::bigint, NULL, 'Maria da Silva', '390.533.447-05', NULL, NULL, NULL);
  PERFORM pg_temp.ok(r.texto_pronto IS NULL AND r.instrucao_para_voce LIKE '%SILENCIO%', 'FLUXO v17: mandou os dados -> o corretor NAO recebe nada');
  SELECT * INTO r FROM nai_saida WHERE visita_id = v AND motivo = 'dados_visitante';
  PERFORM pg_temp.ok(r.papel_destino = 'proprietario' AND r.texto LIKE 'O visitante é Maria da Silva, CPF 390.533.447-05, com o corretor %',
                     'FLUXO v17: os dados do visitante vao ao proprietario DEPOIS (' || coalesce(r.texto, 'nada') || ')');
  SELECT * INTO r FROM nai_guardar_dados_visita((cab->>'turno_id')::bigint, NULL, 'Maria da Silva', '390.533.447-05', NULL, NULL, NULL);
  PERFORM pg_temp.ok((SELECT count(*) FROM nai_saida WHERE visita_id = v AND motivo = 'dados_visitante') = 1, 'dados: mandar de novo nao repete ao proprietario');
  PERFORM pg_temp.ok((SELECT proximo_lembrete_dados_em FROM nai_visita WHERE id = v) IS NULL, 'dados completos: a agenda para de cobrar');
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

-- ------------------------------------------------------ FIM: resultado da visita
DO $$
DECLARE cab jsonb; r record; v bigint; k bigint;
BEGIN
  SELECT id INTO v FROM nai_visita WHERE codigo = 5611 AND id > (SELECT visita FROM _base) ORDER BY id DESC LIMIT 1;
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'o cliente amou, quer alugar', NULL, '{}');
  k := (cab->>'contato_id')::bigint;
  IF k IS NULL THEN k := nai_contato_de('5596991712835', 'Tel Teste'); END IF;
  SELECT * INTO r FROM nai_resultado_visita((cab->>'turno_id')::bigint, '5611', 'quer_alugar', 'o cliente amou');
  PERFORM pg_temp.ok(r.texto_pronto IS NULL AND r.instrucao_para_voce LIKE '%SILENCIO%', 'FIM quer alugar: o corretor NAO recebe nada (sem "Que noticia boa")');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND papel_destino = 'tel' AND motivo = 'quer_alugar'
                             AND texto LIKE '%QUER ALUGAR%Parei de responder esse corretor%'), 'FIM quer alugar: o Tel recebe e sabe que a Nay parou');
  PERFORM pg_temp.ok((SELECT humano_motivo FROM nai_contato WHERE chave = nai_chave('5596991712835')) LIKE 'visita #' || v || ':%',
                     'FIM quer alugar: a Nay PARA naquele chat');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE chave = nai_chave('5596991712835');
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
  -- 13/09: em vez de morrer bloqueada, a mensagem vem REDIRECIONADA para o chat
  -- de teste (o Tel quer ver tudo). A parede e a mesma: nada sai para o numero de fora.
  PERFORM pg_temp.ok(r.estado <> 'bloqueado' AND r.redirecionado
                     AND nai_chave(r.telefone_final) = nai_chave('5596991712835')
                     AND nai_chave(r.telefone_final) <> nai_chave('5592988887777'),
                     'PAREDE DO TESTE: numero fora da lista nao recebe nada -- a mensagem vem para o chat de teste');
END $$;

-- ------------------------------------------------------ FIM: duvida fora da base
DO $$
DECLARE k bigint; t bigint; r record; j jsonb;
BEGIN
  k := nai_contato_de('5592991712836', 'Corretor Duvida');
  INSERT INTO mensagens (telefone, nome, direcao, origem, texto, status, fluxo)
  VALUES ('5592991712836', 'Corretor Duvida', 'recebida', 'texto', 'o 5611 tem gerador de energia no subsolo?', 'Processando', 'nai');
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  SELECT * INTO r FROM nai_escalar(t, '5611', 'gerador de energia no subsolo', 'o 5611 tem gerador de energia no subsolo?');
  PERFORM pg_temp.ok(r.texto_pronto = 'SILENCIO', 'FIM duvida fora da base: a ferramenta devolve SILENCIO (' || coalesce(left(r.texto_pronto, 60), 'nada') || ')');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE papel_destino = 'tel' AND motivo = 'duvida_fora_da_base' AND id > (SELECT saida FROM _base)
                             AND texto LIKE 'Tel, o corretor %perguntou sobre o %: "o 5611 tem gerador de energia no subsolo?". Não achei na base, você sabe?%DEVOLVER%'),
                     'FIM duvida fora da base: o Tel recebe o card "Pergunta ao responsavel"');
  PERFORM pg_temp.ok((SELECT humano_assumiu_em FROM nai_contato WHERE id = k) IS NOT NULL, 'FIM duvida fora da base: a Nay PARA naquele chat');
  j := nai_enfileirar_resposta(t, 'SILENCIO', '[]', 'o 5611 tem gerador de energia no subsolo?', '[]');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND papel_destino = 'turno'),
                     'FIM duvida fora da base: nada sai ao corretor (nao existe "vou ver e te aviso")');
END $$;

-- ------------------------------------------------------ a Nay NAO escalou: a saida escala
-- Teste ao vivo de 13/09: a ferramenta disse "nao sei, escale ao Tel", ela
-- respondeu SILENCIO sem chamar escalar_ao_tel, e depois inventou "o Tel esta
-- verificando, assim que tiver resposta eu te aviso".
DO $$
DECLARE k bigint; t bigint; j jsonb;
BEGIN
  k := nai_contato_de('5592991712835', 'Corretor Promessa');
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  j := nai_enfileirar_resposta(t, 'SILENCIO', '[]', 'e o condomínio do 5718 tem gerador de energia?', '[]');
  PERFORM pg_temp.ok(j->>'guarda' = 'sem_resposta_foi_ao_tel'
                     AND EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND papel_destino = 'tel' AND motivo = 'duvida_fora_da_base'
                                 AND texto LIKE '%Arezzo%gerador de energia%Não achei na base%')
                     AND (SELECT humano_assumiu_em FROM nai_contato WHERE id = k) IS NOT NULL,
                     'PERGUNTA SEM RESPOSTA: SILENCIO sem escalar vai ao Tel (com o imovel que ele citou) e para o chat');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = k;

  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  j := nai_enfileirar_resposta(t, 'Sr. Pedro, o Tel está verificando isso pra gente. Assim que tiver resposta eu te aviso!', '[]', 'oi? conseguiu ver?', '[]');
  PERFORM pg_temp.ok(j->>'guarda' = 'sem_resposta_foi_ao_tel'
                     AND NOT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND papel_destino = 'turno'),
                     'PROMESSA: "assim que tiver resposta eu te aviso" nao sai ao corretor, vai ao Tel');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = k;

  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  PERFORM nai_usou_ferramenta(t, 'visita');
  j := nai_enfileirar_resposta(t, 'Certo, vou ver esse horário com o proprietário e já te retorno 😉', '[]', 'nao da, pode ser 17h?', '[]');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND texto LIKE 'Certo, vou ver esse horário%'),
                     'PROMESSA: o card do laco de horario (ferramenta de visita rodou) continua saindo');

  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  j := nai_enfileirar_resposta(t, 'Imagina! Qualquer coisa me chama por aqui.', '[]', 'beleza, obrigado', '[]');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND texto LIKE 'Imagina!%')
                     AND (SELECT humano_assumiu_em FROM nai_contato WHERE id = k) IS NULL,
                     'SEM PERGUNTA E SEM PROMESSA: conversa normal sai normal');

  -- RESPOSTA SEM CONSULTA (teste ao vivo de 13/09: "o 5611 e semimobiliado", sem ferramenta)
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  j := nai_enfileirar_resposta_ferramentas(t, 'Sobre isso: o 5611 é semimobiliado 😉', '[]', 'o 5611 é mobiliado?', '[]', '[]');
  PERFORM pg_temp.ok(j->>'guarda' LIKE 'respondido_pela_base%'
                     AND EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND papel_destino = 'turno' AND texto LIKE 'Sim! É mobiliado.%')
                     AND NOT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND texto LIKE '%semimobiliado%')
                     AND NOT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND papel_destino = 'tel'),
                     'SEM CONSULTA: a resposta inventada ("semimobiliado") nao sai; sai a da FICHA (mobiliado), sem escalar');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = k;
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  -- 14/09: mobilia deixou de servir de exemplo "sem dado" -- o site preencheu 17
  -- imoveis de locacao. O IPTU do 5611 continua nao existindo em lugar nenhum.
  j := nai_enfileirar_resposta_ferramentas(t, 'Sobre isso: o IPTU do 5611 é R$ 300 😉', '[]', 'qual o IPTU do 5611?', '[]', '[]');
  PERFORM pg_temp.ok(j->>'guarda' = 'resposta_sem_consulta_foi_ao_tel'
                     AND NOT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND papel_destino = 'turno')
                     AND EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND papel_destino = 'tel' AND motivo = 'duvida_fora_da_base'),
                     'SEM CONSULTA: sem ferramenta e SEM o dado na ficha -> nao sai, vai ao Tel');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = k;

  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  j := nai_enfileirar_resposta_ferramentas(t, 'Sobre isso: o 5611 é mobiliado 😉', '[]', 'o 5611 é mobiliado?', '[]', '["imovel_por_codigo"]');
  -- 13/09 (noite): a resposta sai, mas no formato do Tel -- o texto da ficha
  -- substitui a frase do modelo (trava 'formato_da_base').
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND texto LIKE 'Sim! É mobiliado.%'),
                     'SEM CONSULTA: com a ferramenta de consulta chamada, a resposta sai');

  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  j := nai_enfileirar_resposta_ferramentas(t, 'Boa noite, Sr. Pedro! Tudo ótimo 😉', '[]', 'boa noite, tudo bem?', '[]', '[]');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND texto LIKE 'Boa noite, Sr. Pedro!%')
                     AND (SELECT humano_assumiu_em FROM nai_contato WHERE id = k) IS NULL,
                     'SEM CONSULTA: conversa social sem assunto de imovel sai normal');

  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  j := nai_enfileirar_resposta_ferramentas(t, 'Sobre isso: o 5611 é mobiliado 😉', '[]', 'o 5611 é mobiliado?', '[]', NULL);
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND texto LIKE 'Sim! É mobiliado.%'),
                     'SEM CONSULTA: sem a lista de ferramentas (caminho que nao sabe), a trava nao age');

  -- VISITA SEM FERRAMENTA (teste ao vivo de 13/09): "Esse horario ja passou" de
  -- cabeca, sem pedir_visita. Antes saia so o que sobrava ("Boa noite, Sr. Pedro.").
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  j := nai_enfileirar_resposta(t, 'Boa noite, Sr. Pedro. Esse horário já passou 😅 Qual outro horário fica bom pro seu cliente?', '[]',
                               'preciso visitar o 4255 hoje às 02h30', '[]');
  PERFORM pg_temp.ok(j->>'guarda' LIKE '%visita_sem_ferramenta%'
                     AND NOT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND papel_destino = 'turno')
                     AND EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND papel_destino = 'tel' AND motivo = 'visita_sem_ferramenta'
                                 AND texto LIKE '%hoje às 02h30%parei de responder esse chat%')
                     AND (SELECT humano_assumiu_em FROM nai_contato WHERE id = k) IS NOT NULL,
                     'VISITA SEM FERRAMENTA: nada sai ao corretor (nem o "Boa noite" que sobrava), o pedido vai ao Tel e o chat para');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = k;
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
  -- A conta e contra nai_imagens_do_envio: desde 12/09 sai tambem a COLAGEM, na frente das fotos.
  PERFORM pg_temp.ok(j->>'guarda' = 'negacao_corrigida' AND n = (SELECT count(*) FROM nai_imagens_do_envio(2014)),
                     'FOTOS: o caso Regiane -- ela nega, a guarda corrige e as ' || n || ' imagens saem');
  -- 14/09: a metadinha e SO do disparo de grupo. No privado vao todas as fotos.
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = (cab->>'turno_id')::bigint AND motivo = 'colagem')
                     AND n = (SELECT count(*) FROM imovel_fotos WHERE codigo = 2014),
                     'COLAGEM: no privado NAO vai a metadinha -- vao as ' || n || ' fotos do imovel');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = (cab->>'turno_id')::bigint AND tipo = 'texto'
                                  AND texto ~* 'n[ãa]o temos imagens'), 'FOTOS: a frase de negacao nao sai');
  PERFORM pg_temp.ok((SELECT string_agg(texto, ' || ' ORDER BY ordem) FROM nai_saida WHERE turno_id = (cab->>'turno_id')::bigint AND tipo = 'texto')
                     = 'Aqui as fotos, quer fazer uma visita? Só me informar um horário || Ou se tiver alguma dúvida ou quiser mais imóveis me fala o que está procurando, que já vejo aqui para você, ok?'
                     AND (SELECT max(ordem) FROM nai_saida WHERE turno_id = (cab->>'turno_id')::bigint AND tipo = 'imagem')
                       < (SELECT min(ordem) FROM nai_saida WHERE turno_id = (cab->>'turno_id')::bigint AND tipo = 'texto'),
                     'FOTOS: depois das fotos, as duas mensagens do Tel (visita / duvida ou mais imoveis), sem "as fotos estao vindo"');
  PERFORM pg_temp.ok(nai_so_anuncia_fotos('As fotos já estão sendo enviadas.') AND NOT nai_so_anuncia_fotos('Sobre isso: tem 2 vagas, segue as fotos'),
                     'FOTOS: "As fotos ja estao sendo enviadas" e aviso; resposta com informacao nao e');

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
  SELECT * INTO r FROM nai_pedir_visita((cab->>'turno_id')::bigint, '4255', q, '');
  PERFORM pg_temp.ok(r.texto_pronto IS NULL AND r.instrucao_para_voce LIKE '%SILENCIO%', 'cenario 2: pediu o horario, fica calada');
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
  PERFORM pg_temp.ok(r.texto_pronto IS NULL AND r.instrucao_para_voce LIKE '%SILENCIO%', 'proprietario sugeriu: ele nao ouve "vou ver e ja te retorno"');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND motivo = 'proprietario_sugeriu' AND texto LIKE '%mas sugeriu%às 16h%Funciona pro seu cliente?'),
                     'proprietario sugeriu: o corretor recebe a proposta');

  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'pode ser', NULL, '{}');
  PERFORM pg_temp.ok(cab->>'papel' = 'corretor', 'sem prefixo e sem marcar: e o corretor');
  SELECT * INTO r FROM nai_responder_horario((cab->>'turno_id')::bigint, '4255', 'sim', NULL);
  PERFORM pg_temp.ok((SELECT extract(hour FROM quando AT TIME ZONE 'America/Manaus') FROM nai_visita WHERE id = v) = 16
                     AND (SELECT prop_ok_em FROM nai_visita WHERE id = v) IS NOT NULL, 'corretor aceitou: horario do proprietario vale como aceite dele');
  PERFORM pg_temp.ok(r.texto_pronto IS NULL AND r.instrucao_para_voce LIKE '%SILENCIO%', 'corretor aceitou: sem mensagem ao corretor (nao ha card)');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND motivo = 'fecha_novo_horario' AND papel_destino = 'proprietario'
                             AND texto LIKE 'Fechado! O corretor confirmou%às 16h.%' AND texto NOT LIKE '%CPF%'),
                     'card "Fecha o novo horario" vai ao proprietario, sem dados do visitante');

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

-- ------------------------------------ FIM: proprietario sem resposta ate 2h antes
DO $$
DECLARE cab jsonb; r record; v bigint; q text; n int; prop bigint;
BEGIN
  q := to_char((now() + interval '6 hours') AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI');
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'visita no 4255 hoje', NULL, '{}');
  SELECT * INTO r FROM nai_pedir_visita((cab->>'turno_id')::bigint, '4255', q, '');
  SELECT id, proprietario_id INTO v, prop FROM nai_visita WHERE codigo = 4255 AND id > (SELECT visita FROM _base) ORDER BY id DESC LIMIT 1;
  PERFORM * FROM nai_liberar_saida((cab->>'turno_id')::bigint);
  UPDATE nai_visita SET quando = now() + interval '100 minutes' WHERE id = v;
  n := nai_agenda_tick();
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND papel_destino = 'tel' AND motivo = 'p_tel_2h'
                             AND texto LIKE '%Que horas eu mando o próximo aviso ao proprietário?%Parei com o corretor e com o proprietário%'),
                     'FIM 2h: o Tel recebe o card "Acionar o Tel"');
  PERFORM pg_temp.ok((SELECT estado FROM nai_visita WHERE id = v) = 'com_tel', 'FIM 2h: a visita fica com o Tel');
  PERFORM pg_temp.ok((SELECT humano_motivo FROM nai_contato WHERE chave = nai_chave('5596991712835')) LIKE 'visita #' || v || ':%'
                     AND (prop IS NULL OR (SELECT humano_assumiu_em FROM nai_contato WHERE id = prop) IS NOT NULL),
                     'FIM 2h: para o chat do corretor E o do proprietario');
  n := nai_agenda_tick();
  PERFORM pg_temp.ok((SELECT count(*) FROM nai_saida WHERE visita_id = v AND motivo = 'p_tel_2h') = 1, 'FIM 2h: o aviso ao Tel nao se repete');

  cab := nai_abrir_turno('5596991712835', 'Tel Teste',
                         'T: visita ' || v || ' avisa ' || to_char((now() + interval '40 minutes') AT TIME ZONE 'America/Manaus', 'DD/MM HH24"h"MI'), NULL, '{}');
  PERFORM pg_temp.ok(cab->>'papel' = 'tel', 'FIM 2h: com o chat parado, o comando T: do Tel passa');
  SELECT * INTO r FROM nai_comando_tel((cab->>'turno_id')::bigint, cab->>'texto');
  PERFORM pg_temp.ok(r.msg_tel LIKE 'Combinado: mando o próximo aviso%Voltei a atender quem estava parado por essa visita.',
                     'VISITA N AVISA: agenda o aviso e devolve os chats (' || coalesce(left(r.msg_tel, 60), 'nada') || ')');
  PERFORM pg_temp.ok((SELECT humano_assumiu_em FROM nai_contato WHERE chave = nai_chave('5596991712835')) IS NULL
                     AND (prop IS NULL OR (SELECT humano_assumiu_em FROM nai_contato WHERE id = prop) IS NULL)
                     AND (SELECT estado FROM nai_visita WHERE id = v) = 'aguardando_proprietario',
                     'VISITA N AVISA: a visita volta a esperar o proprietario');
  UPDATE nai_visita SET estado = 'cancelada', encerrada_em = now() WHERE id = v;
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE humano_motivo LIKE 'visita #' || v || ':%';
END $$;

-- ------------------------------------ FIM: o Fernando nao pode
DO $$
DECLARE cab jsonb; r record; v bigint; q text;
BEGIN
  q := to_char((now() AT TIME ZONE 'America/Manaus')::date + 2, 'YYYY-MM-DD') || ' 11:00';
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'e o 5611 depois de amanha 11h?', NULL, '{}');
  SELECT * INTO r FROM nai_pedir_visita((cab->>'turno_id')::bigint, '5611', q, '');
  SELECT id INTO v FROM nai_visita WHERE codigo = 5611 AND id > (SELECT visita FROM _base) ORDER BY id DESC LIMIT 1;
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'P: pode', NULL, '{}');
  SELECT * INTO r FROM nai_resposta_proprietario((cab->>'turno_id')::bigint, 'aceita', NULL, NULL, NULL, NULL);
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'P: senha 7788', NULL, '{}');
  SELECT * INTO r FROM nai_resposta_proprietario((cab->>'turno_id')::bigint, 'acesso', NULL, NULL, NULL, '7788');
  PERFORM pg_temp.ok((SELECT estado FROM nai_visita WHERE id = v) = 'aguardando_motoboy', 'Fernando: visita chegou ao Fernando');
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'M: nao vou conseguir', NULL, '{}');
  SELECT * INTO r FROM nai_resposta_motoboy((cab->>'turno_id')::bigint, NULL, 'nao_pode', 'nao vou conseguir');
  PERFORM pg_temp.ok(r.texto_pronto IS NULL AND r.instrucao_para_voce LIKE '%SILENCIO%', 'FIM acompanhante nao pode: ninguem e avisado');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND papel_destino = 'tel' AND motivo = 'motoboy_nao_pode'
                             AND texto LIKE '%NÃO consegue acompanhar%Parei com o ' || nai_acompanhante() || ' e com o corretor%'), 'FIM acompanhante nao pode: o Tel recebe o card PROBLEMA');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND papel_destino = 'corretor' AND texto ~* 'verificar|retorno'),
                     'FIM Fernando nao pode: o corretor nao ouve "vou verificar e ja te retorno"');
  PERFORM pg_temp.ok((SELECT estado FROM nai_visita WHERE id = v) = 'com_tel'
                     AND (SELECT humano_motivo FROM nai_contato WHERE chave = nai_chave('5596991712835')) LIKE 'visita #' || v || ':%',
                     'FIM Fernando nao pode: visita com o Tel e chat parado');
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'T: visita ' || v || ' cancela', NULL, '{}');
  SELECT * INTO r FROM nai_comando_tel((cab->>'turno_id')::bigint, cab->>'texto');
  PERFORM pg_temp.ok(r.msg_tel LIKE '%Voltei a atender quem estava parado por essa visita.'
                     AND (SELECT humano_assumiu_em FROM nai_contato WHERE chave = nai_chave('5596991712835')) IS NULL,
                     'VISITA N CANCELA: devolve o chat parado por essa visita');
  UPDATE nai_visita SET estado = 'cancelada', encerrada_em = now() WHERE id = v AND nai_visita_aberta(estado);
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE chave = nai_chave('5596991712835');
END $$;

-- ------------------------------------ Fernando CALADO (Tel, 15/09)
-- Ele: "se o fernando por um acaso nao confirmar ou disser que nao pode e
-- para escalar o tel tambem la na de locacao". O "disser que nao pode" ja
-- tinha teste acima; o CALADO nao tinha nenhum -- e calado e o caso que
-- ninguem percebe, porque nada acontece na tela.
DO $$
DECLARE cab jsonb; r record; v bigint; q text;
BEGIN
  q := to_char((now() AT TIME ZONE 'America/Manaus')::date + 3, 'YYYY-MM-DD') || ' 16:00';
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'quero ver o 5611 em tres dias as 16h', NULL, '{}');
  SELECT * INTO r FROM nai_pedir_visita((cab->>'turno_id')::bigint, '5611', q, '');
  SELECT id INTO v FROM nai_visita WHERE codigo = 5611 AND id > (SELECT visita FROM _base) ORDER BY id DESC LIMIT 1;
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'P: pode', NULL, '{}');
  SELECT * INTO r FROM nai_resposta_proprietario((cab->>'turno_id')::bigint, 'aceita', NULL, NULL, NULL, NULL);
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'P: senha 4321', NULL, '{}');
  SELECT * INTO r FROM nai_resposta_proprietario((cab->>'turno_id')::bigint, 'acesso', NULL, NULL, NULL, '4321');
  PERFORM pg_temp.ok((SELECT estado FROM nai_visita WHERE id = v) = 'aguardando_motoboy',
                     'CALADO: a visita esta esperando o Fernando');

  -- passaram os 30 minutos e ele nao respondeu: primeiro vem o lembrete A ELE
  UPDATE nai_visita SET ult_msg_moto_em = now() - interval '31 minutes' WHERE id = v;
  PERFORM nai_agenda_tick();
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND papel_destino = 'motoboy'
                             AND motivo = 'motoboy_lembrete' AND texto LIKE '%consegue me confirmar%'),
                     'CALADO: 30 min sem resposta, ela cobra o Fernando uma vez');
  PERFORM pg_temp.ok((SELECT reenvios_moto FROM nai_visita WHERE id = v) = 1, 'CALADO: a cobranca foi contada');

  -- cobrou e ele continuou calado: agora sobe para o Tel
  UPDATE nai_visita SET ult_msg_moto_em = now() - interval '31 minutes' WHERE id = v;
  PERFORM nai_agenda_tick();
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND papel_destino = 'tel'
                             AND motivo = 'motoboy_sem_resposta' AND texto LIKE '%não confirmou a visita%'),
                     'CALADO: continuou calado, o Tel e avisado');
  PERFORM pg_temp.ok((SELECT aviso_tel_moto_em FROM nai_visita WHERE id = v) IS NOT NULL,
                     'CALADO: o aviso ao Tel fica carimbado');

  -- e o aviso nao se repete a cada minuto do relogio
  PERFORM nai_agenda_tick();
  PERFORM nai_agenda_tick();
  PERFORM pg_temp.ok((SELECT count(*) FROM nai_saida WHERE visita_id = v AND motivo = 'motoboy_sem_resposta') = 1,
                     'CALADO: o Tel e avisado UMA vez, nao a cada minuto');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND papel_destino = 'corretor'
                                 AND motivo IN ('motoboy_lembrete', 'motoboy_sem_resposta')),
                     'CALADO: o corretor nao fica sabendo do silencio do Fernando');
  UPDATE nai_visita SET estado = 'cancelada', encerrada_em = now() WHERE id = v AND nai_visita_aberta(estado);
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE chave = nai_chave('5596991712835');
END $$;

-- --------------------------- comandos do WhatsApp do Tel (Tel, 15/09)
-- Ele: "coloca funcao para o tel poder cancelar uma visita pelo whatsapp, e
-- parar o atendimento da nay geral com um comando especifico ... ou remarcar
-- uma visita manualmente pelo whatsapp dele".
DO $$
DECLARE cab jsonb; r record; v bigint; q text;
BEGIN
  q := to_char((now() AT TIME ZONE 'America/Manaus')::date + 4, 'YYYY-MM-DD') || ' 11:00';
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'quero ver o 5611 daqui a quatro dias as 11h', NULL, '{}');
  SELECT * INTO r FROM nai_pedir_visita((cab->>'turno_id')::bigint, '5611', q, '');
  SELECT id INTO v FROM nai_visita WHERE codigo = 5611 AND id > (SELECT visita FROM _base) ORDER BY id DESC LIMIT 1;
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'P: pode', NULL, '{}');
  SELECT * INTO r FROM nai_resposta_proprietario((cab->>'turno_id')::bigint, 'aceita', NULL, NULL, NULL, NULL);
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'P: senha 9090', NULL, '{}');
  SELECT * INTO r FROM nai_resposta_proprietario((cab->>'turno_id')::bigint, 'acesso', NULL, NULL, NULL, '9090');

  -- REMARCA: muda a hora e AVISA -- diferente do HORARIO, que pergunta
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'T: visita ' || v || ' remarca 16h', NULL, '{}');
  SELECT * INTO r FROM nai_comando_tel((cab->>'turno_id')::bigint, cab->>'texto');
  PERFORM pg_temp.ok(r.msg_tel LIKE '%remarcada para%' AND r.msg_tel LIKE '%Avisei o corretor%',
                     'REMARCA: confirma ao Tel quem foi avisado');
  PERFORM pg_temp.ok(to_char((SELECT quando FROM nai_visita WHERE id = v) AT TIME ZONE 'America/Manaus', 'HH24:MI') = '16:00',
                     'REMARCA: a hora mudou de verdade');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND papel_destino = 'corretor'
                             AND motivo = 'tel_remarcou' AND texto LIKE '%foi remarcada para%'),
                     'REMARCA: o corretor e avisado (nao e perguntado)');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND papel_destino = 'proprietario'
                             AND motivo = 'tel_remarcou' AND texto LIKE 'A visita no seu imóvel%'),
                     'REMARCA: o proprietario e avisado, com a redacao certa');
  PERFORM pg_temp.ok((SELECT aviso_motoboy_em IS NULL AND lembrete_1h_em IS NULL FROM nai_visita WHERE id = v),
                     'REMARCA: os avisos voltam a zero, para valerem na hora nova');

  -- CANCELA, que ja existia: continua cancelando e avisando
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'T: visita ' || v || ' cancela', NULL, '{}');
  SELECT * INTO r FROM nai_comando_tel((cab->>'turno_id')::bigint, cab->>'texto');
  PERFORM pg_temp.ok((SELECT estado FROM nai_visita WHERE id = v) = 'cancelada'
                     AND EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND motivo = 'cancelada_pelo_tel'),
                     'CANCELA: cancela e avisa o corretor');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE chave = nai_chave('5596991712835');
END $$;

DO $$
DECLARE cab jsonb; r record;
BEGIN
  -- PARAR / VOLTAR ATENDIMENTO, sem prefixo, do numero dele
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'parar atendimento', NULL, '{}');
  PERFORM pg_temp.ok(cab->>'papel' = 'tel' AND (cab->>'comando_nai')::boolean,
                     'PARAR: vira comando do Tel sem precisar do prefixo T:');
  SELECT * INTO r FROM nai_comando_tel((cab->>'turno_id')::bigint, cab->>'texto');
  PERFORM pg_temp.ok((SELECT valor FROM nai_config WHERE chave = 'pausada') = 'sim',
                     'PARAR: a NAI fica parada');

  -- e o mais importante: com ela PARADA, ele ainda consegue religar
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'voltar atendimento', NULL, '{}');
  PERFORM pg_temp.ok(cab->>'papel' = 'tel' AND (cab->>'comando_nai')::boolean AND (cab->>'pausado')::boolean,
                     'VOLTAR: com a NAI parada, o comando dele ainda chega');
  SELECT * INTO r FROM nai_comando_tel((cab->>'turno_id')::bigint, cab->>'texto');
  PERFORM pg_temp.ok((SELECT valor FROM nai_config WHERE chave = 'pausada') = 'nao' AND r.msg_tel = 'Voltei a atender.',
                     'VOLTAR: ela volta a atender');

  -- conversa comum que fala em parar NAO desliga nada
  PERFORM pg_temp.ok(NOT nai_e_comando_parada('pode parar o atendimento dela?')
                     AND NOT nai_e_comando_parada('parar'),
                     'PARAR: frase solta e conversa sobre parar nao desligam a NAI');
END $$;

-- ------------- o comando do TEL atravessa os QUATRO porteiros (15/09)
-- "tel mandou agenda de visitas e ela n respondeu": o numero do Tel nao esta
-- em `numeros_teste`, e cada um destes quatro sozinho bastava para o comando
-- morrer calado. Os quatro ficam presos aqui.
DO $$
DECLARE cab jsonb; r record; s record; TEL text := '559294717316'; n int; ini bigint;
BEGIN
  PERFORM pg_temp.ok(NOT (nai_chave(TEL) = ANY (nai_chaves_teste())),
                     'PORTEIROS: o numero do Tel NAO esta na lista de teste (e o cenario do bug)');

  -- 1. qual das duas Nays atende
  PERFORM pg_temp.ok(nai_quem_atende(TEL, false, 'Agenda de visitas') = 'nai',
                     'PORTEIRO 1: comando da NAI vem para a NAI, nao para a Nay antiga');
  PERFORM pg_temp.ok(nai_quem_atende(TEL, false, 'bom dia, tudo bem?') = 'nay',
                     'PORTEIRO 1: conversa normal do Tel continua na Nay antiga');
  PERFORM pg_temp.ok(nai_quem_atende(TEL, false, 'Nay posta o 5750') = 'nay',
                     'PORTEIRO 1: comando do publicador continua na Nay antiga');
  PERFORM pg_temp.ok(nai_quem_atende('5592988887777', false, 'Agenda de visitas') = 'nay',
                     'PORTEIRO 1: numero qualquer escrevendo o comando nao entra na NAI');

  -- 2. o turno abre para o comando, e so para ele
  ini := (SELECT coalesce(max(id), 0) FROM nai_saida);
  cab := nai_abrir_turno(TEL, 'Tel Sobreira', 'agenda de visitas', NULL, '{}');
  PERFORM pg_temp.ok((cab->>'ok')::boolean AND cab->>'papel' = 'tel',
                     'PORTEIRO 2: o comando abre turno mesmo fora da lista de teste');
  PERFORM pg_temp.ok((nai_abrir_turno(TEL, 'Tel Sobreira', 'bom dia, tudo bem?', NULL, '{}')->>'motivo') = 'fora_do_teste',
                     'PORTEIRO 2: conversa normal dele continua barrada pelo modo teste');

  -- 3 e 4. a resposta volta para ELE, sem redirecionar e sem a pausa segurar
  SELECT * INTO r FROM nai_comando_tel((cab->>'turno_id')::bigint, cab->>'texto');
  -- Conferido pelo DESTINO GRAVADO, nao pelo retorno da funcao: a bateria roda
  -- com envio_simulado ligado, e ai `nai_liberar_saida` marca a linha como
  -- 'simulado' e nao devolve nada para enviar. O que importa e para onde a
  -- mensagem foi endereçada.
  PERFORM nai_liberar_saida((cab->>'turno_id')::bigint);
  SELECT count(*) INTO n FROM nai_saida
   WHERE turno_id = (cab->>'turno_id')::bigint AND bloqueio IS NULL
     AND NOT redirecionado AND nai_chave(telefone_final) = nai_chave(TEL);
  PERFORM pg_temp.ok(n = 1, 'PORTEIRO 3: a resposta vai para o Tel, sem ser redirecionada ao numero de teste');

  UPDATE nai_config SET valor = 'sim' WHERE chave = 'pausada';
  cab := nai_abrir_turno(TEL, 'Tel Sobreira', 'voltar atendimento', NULL, '{}');
  SELECT * INTO r FROM nai_comando_tel((cab->>'turno_id')::bigint, cab->>'texto');
  PERFORM nai_liberar_saida((cab->>'turno_id')::bigint);
  SELECT count(*) INTO n FROM nai_saida
   WHERE turno_id = (cab->>'turno_id')::bigint AND bloqueio IS NULL
     AND nai_chave(telefone_final) = nai_chave(TEL);
  PERFORM pg_temp.ok(n = 1 AND (SELECT valor FROM nai_config WHERE chave = 'pausada') = 'nao',
                     'PORTEIRO 4: com a NAI parada, ele religa E recebe a confirmacao');
END $$;

-- ------------------- A PORTA: quem ela atende (Tel, 15/09) -------------
-- "Ative agora, somente para novas conversas... voce nao vai responder quem o
-- tel ja esta conversando, a nao ser que a pessoa peca fotos de um imovel x ou
-- peca imoveis claramente." E: "mensagem por humano pausa."
--
-- A regra e ligada AQUI DENTRO e o ROLLBACK desfaz -- estes testes valem com a
-- porta ligada ou desligada em producao.
DO $$
DECLARE
  r record;
  NOVO   text := '5592900011111';
  ANTIGO text := '5592900022222';
  v_modo text;
BEGIN
  v_modo := nai_cfg('modo');
  -- o modo 'todos' entra so aqui dentro: no modo teste o turno de um numero
  -- fora da lista nem abre, e a porta nunca seria consultada.
  UPDATE nai_config SET valor = 'todos' WHERE chave = 'modo';
  PERFORM nai_ligar_regra_publico();
  INSERT INTO mensagens (telefone, nome, direcao, origem, texto, status, fluxo, criada_em)
  VALUES (ANTIGO, 'Cliente Antigo', 'recebida', 'texto', 'boa tarde', 'Respondido', 'nai',
          now() - interval '20 days');
  PERFORM nai_contato_de(ANTIGO, 'Cliente Antigo');
  PERFORM nai_contato_de(NOVO, 'Gente Nova');

  -- gente nova
  SELECT * INTO r FROM nai_deve_atender(NOVO, 'tem apartamento de 2 quartos pra alugar?', NULL);
  PERFORM pg_temp.ok(r.atende, 'PORTA: contato novo perguntando de imovel e atendido');
  SELECT * INTO r FROM nai_deve_atender(NOVO, 'tem algo em Ponta Negra ate 4 mil?', NULL);
  PERFORM pg_temp.ok(r.atende, 'PORTA: contato novo com bairro e valor, sem dizer "imovel", e atendido');
  SELECT * INTO r FROM nai_deve_atender(NOVO, 'preciso da segunda via do meu boleto', NULL);
  PERFORM pg_temp.ok(NOT r.atende, 'PORTA: contato novo com duvida pessoal NAO e atendido');

  -- conversa que ja existia
  SELECT * INTO r FROM nai_deve_atender(ANTIGO, 'e ai, conseguiu ver aquilo?', NULL);
  PERFORM pg_temp.ok(NOT r.atende, 'PORTA: conversa que ja existia continua com o Tel');
  SELECT * INTO r FROM nai_deve_atender(ANTIGO, 'me manda umas fotos', NULL);
  PERFORM pg_temp.ok(NOT r.atende, 'PORTA: pediu foto sem dizer o imovel: ela fica calada');

  -- os dois pedidos que abrem a porta
  SELECT * INTO r FROM nai_deve_atender(ANTIGO, 'tem fotos do imovel 5717?', NULL);
  PERFORM pg_temp.ok(r.atende AND r.motivo = 'pediu foto de um imovel',
                     'PORTA: pedido de foto de um imovel abre a conversa antiga');
  SELECT * INTO r FROM nai_deve_atender(ANTIGO, 'e tem garagem?', NULL);
  PERFORM pg_temp.ok(r.atende, 'PORTA: aberta a conversa, ela segue atendendo');

  -- mensagem por humano pausa -- por MEIA HORA, desde 16/09 (arquivo 54)
  PERFORM nai_tel_assumiu(ANTIGO, NULL, 'deixa que eu falo com ele');
  SELECT * INTO r FROM nai_deve_atender(ANTIGO, 'e o condominio, quanto e?', NULL);
  PERFORM pg_temp.ok(NOT r.atende AND r.motivo ~ '^o Tel escreveu ha menos de',
                     'PORTA: mensagem do Tel pelo celular pausa a Nay naquela conversa');

  -- O GAP (Tel, 16/09): "toda mensagem que chegar no corretor dentro [do gap] e
  -- ignorada, e [ele conta] a cada mensagem que o Tel envia manualmente".
  DECLARE k_gap bigint;
  BEGIN
    SELECT id INTO k_gap FROM nai_contato WHERE chave = nai_chave(ANTIGO);

    -- dentro do gap: calada
    UPDATE nai_contato SET humano_assumiu_em = now() - interval '29 minutes'
     WHERE id = k_gap;
    SELECT * INTO r FROM nai_deve_atender(ANTIGO, 'e o condominio, quanto e?', NULL);
    PERFORM pg_temp.ok(NOT r.atende, 'GAP: 29 min depois do Tel, ela continua calada');

    -- passado o gap: a conversa volta a ser julgada pelas regras normais
    UPDATE nai_contato SET humano_assumiu_em = now() - interval '31 minutes'
     WHERE id = k_gap;
    SELECT * INTO r FROM nai_deve_atender(ANTIGO, 'tem fotos do imovel 5717?', NULL);
    PERFORM pg_temp.ok(r.atende, 'GAP: passados 31 min, a porta volta a julgar a conversa');

    -- o relogio reinicia a cada mensagem dele
    PERFORM nai_tel_assumiu(ANTIGO, 'id-que-nao-e-eco-1', 'deixa comigo de novo');
    PERFORM pg_temp.ok(nai_tel_com_a_conversa(k_gap),
                       'GAP: mensagem nova do Tel reinicia o gap');
    PERFORM pg_temp.ok(
      (SELECT humano_assumiu_em FROM nai_contato WHERE id = k_gap) > now() - interval '1 minute',
      'GAP: o carimbo passa a ser o da ULTIMA mensagem dele, nao o da primeira');

    -- escalada nao expira: segue com o Tel ate o DEVOLVER
    UPDATE nai_contato SET humano_assumiu_em = now() - interval '5 hours',
           humano_motivo = 'duvida fora da base: alguma coisa' WHERE id = k_gap;
    PERFORM pg_temp.ok(nai_tel_com_a_conversa(k_gap),
                       'GAP: escalada NAO expira -- so o DEVOLVER traz ela de volta');
    SELECT * INTO r FROM nai_deve_atender(ANTIGO, 'tem fotos do imovel 5717?', NULL);
    PERFORM pg_temp.ok(NOT r.atende AND r.motivo = 'o Tel assumiu essa conversa',
                       'GAP: conversa escalada continua com o Tel depois de 5 horas');

    -- e a caixa de saida le a mesma coisa que a porta
    UPDATE nai_contato SET humano_assumiu_em = now(),
           humano_motivo = 'o Tel escreveu pelo celular' WHERE id = k_gap;
    PERFORM pg_temp.ok(nai_tel_com_a_conversa(k_gap)
                   AND NOT (SELECT atende FROM nai_deve_atender(ANTIGO, 'e o condominio?', NULL)),
                       'GAP: porta e caixa de saida leem a pausa do mesmo jeito');

    -- deixa a conversa como o resto do teste espera encontrar
    UPDATE nai_contato SET humano_assumiu_em = now(),
           humano_motivo = 'o Tel escreveu pelo celular' WHERE id = k_gap;
  END;

  -- AREA DENTRO DO BAIRRO: Vieiralves = Nossa Sra. das Gracas (Tel, 18/09, arquivo 63)
  PERFORM pg_temp.ok(nay_normalizar_lugar('Vieiralves') = 'nossa senhora das gracas',
    'AREA: "Vieiralves" e lido como o bairro Nossa Senhora das Gracas');
  PERFORM pg_temp.ok(
    nai_pedido_de_perfil('procuro apartamento no vieiralves ate 5 mil')->>'bairro' = 'Nossa Senhora das Graças',
    'AREA: o pedido "no vieiralves" busca no bairro certo');
  PERFORM pg_temp.ok(nay_normalizar_lugar('Aleixo') = 'aleixo' AND nay_normalizar_lugar('pq 10') = 'parque 10',
    'AREA: os outros bairros continuam como eram');
  PERFORM pg_temp.ok((SELECT area FROM nai_area_citada('tem algo no Vieiralves?') LIMIT 1) = 'Vieiralves',
    'AREA: a area citada e reconhecida para ela falar o nome que a pessoa usou');

  -- O NOME SO QUANDO EXISTE (Tel, 16/09, arquivo 62)
  PERFORM pg_temp.ok(nai_vocativo('~') IS NULL,
    'NOME: o "~" do WhatsApp nao vira nome de gente');
  PERFORM pg_temp.ok(nai_vocativo('559291726959') IS NULL,
    'NOME: numero de telefone nao vira nome');
  PERFORM pg_temp.ok(nai_vocativo('.') IS NULL,
    'NOME: pontuacao sozinha nao vira nome');
  PERFORM pg_temp.ok(nai_vocativo('Carlus Abtibol') = 'Sr. Carlus',
    'NOME: quando existe, continua saindo com tratamento');

  -- ELA NUNCA PERGUNTA QUEM E (Tel, 16/09, arquivo 61)
  PERFORM pg_temp.ok(
    nai_sem_pergunta_de_identidade(
      'Boa tarde! Antes de combinarmos o dia e o horario, com quem eu falo e qual e o codigo do imovel?')
    = 'Boa tarde! Antes de combinarmos o dia e o horario, qual e o codigo do imovel?',
    'IDENTIDADE: "com quem eu falo" sai e o resto da frase fica de pe');
  PERFORM pg_temp.ok(
    btrim(nai_sem_pergunta_de_identidade('Com quem eu falo?')) = '',
    'IDENTIDADE: a pergunta sozinha nao vira mensagem nenhuma');
  PERFORM pg_temp.ok(
    btrim(nai_sem_pergunta_de_identidade('Qual e o seu nome?')) = '',
    'IDENTIDADE: "qual e o seu nome" tambem sai');
  PERFORM pg_temp.ok(
    nai_sem_pergunta_de_identidade('Certo! Me diz seu nome e o codigo do imovel.')
    = 'Certo! Me diz o codigo do imovel.',
    'IDENTIDADE: o verbo fica, so o pedido de nome sai');
  PERFORM pg_temp.ok(
    nai_sem_pergunta_de_identidade('Me passa o nome completo e o CPF do visitante, por favor.')
    = 'Me passa o nome completo e o CPF do visitante, por favor.',
    'IDENTIDADE: o nome do VISITANTE continua sendo pedido');
  PERFORM pg_temp.ok(
    nai_sem_pergunta_de_identidade('Certo, Sr. Carlos! Qual o codigo do imovel?')
    = 'Certo, Sr. Carlos! Qual o codigo do imovel?',
    'IDENTIDADE: frase sem pergunta de identidade nao e tocada');
  PERFORM pg_temp.ok(
    nai_sem_pergunta_de_identidade(E'Sim! Esta disponivel.

Tem 3 quartos.
Tem 2 banheiros.')
    = E'Sim! Esta disponivel.

Tem 3 quartos.
Tem 2 banheiros.',
    'IDENTIDADE: a ficha em varias linhas nao e amassada');

  -- IMOVEL DE PARCERIA NAO SAI (Tel, 16/09, arquivo 60)
  DECLARE k_p bigint; t_p bigint; s_p bigint; cod_p int; est text; url_p text;
  BEGIN
    SELECT i.codigo INTO cod_p FROM imoveis i
     WHERE coalesce(i.e_parceiro,false)
       AND nay_esta_no_mercado(i.disponivel,i.bloqueado,i.publicado_no_site)
     LIMIT 1;

    IF cod_p IS NOT NULL THEN
      k_p := nai_contato_de('5592900557788', 'Corretor da Parceria');
      INSERT INTO nai_turno (contato_id, papel, teste, texto, codigo)
           VALUES (k_p, 'corretor', true, 'quero o ' || cod_p, cod_p) RETURNING id INTO t_p;

      INSERT INTO nai_saida (turno_id, contato_id, papel_destino, tipo, texto, codigo, motivo, estado)
           VALUES (t_p, k_p, 'turno', 'texto', 'card', cod_p, 'teste', 'pendente') RETURNING id INTO s_p;
      SELECT estado INTO est FROM nai_saida WHERE id = s_p;
      PERFORM pg_temp.ok(est = 'bloqueado', 'PARCERIA: o card de imovel de parceria nao sai');

      SELECT f.url INTO url_p FROM imovel_fotos f WHERE f.codigo = cod_p LIMIT 1;
      IF url_p IS NOT NULL THEN
        INSERT INTO nai_saida (turno_id, contato_id, papel_destino, tipo, imagem_url, codigo, motivo, estado)
             VALUES (t_p, k_p, 'turno', 'imagem', url_p, cod_p, 'foto', 'pendente') RETURNING id INTO s_p;
        SELECT estado INTO est FROM nai_saida WHERE id = s_p;
        PERFORM pg_temp.ok(est = 'bloqueado', 'PARCERIA: a foto de imovel de parceria nao sai');
      END IF;

      -- o aviso ao Tel tem que continuar passando: e por ele que a parceria anda
      INSERT INTO nai_saida (turno_id, contato_id, papel_destino, tipo, texto, codigo, motivo, estado)
           VALUES (t_p, (SELECT id FROM nai_contato WHERE chave = nai_chave(nai_cfg('tel_telefone'))),
                   'tel', 'texto', 'Tel, perguntaram do ' || cod_p, cod_p, 'teste', 'pendente')
        RETURNING id INTO s_p;
      SELECT estado INTO est FROM nai_saida WHERE id = s_p;
      PERFORM pg_temp.ok(est <> 'bloqueado', 'PARCERIA: o aviso ao Tel sobre a parceria continua saindo');

      -- e a busca nunca oferece parceria
      PERFORM pg_temp.ok(
        NOT (SELECT nai_oferta_serve(i, '', NULL, NULL, false, false) FROM imoveis i WHERE i.codigo = cod_p),
        'PARCERIA: imovel de parceria nao entra na busca');
    END IF;

    -- imovel NOSSO continua saindo
    DECLARE cod_n int; k_n bigint; t_n bigint; s_n bigint; est_n text;
    BEGIN
      SELECT i.codigo INTO cod_n FROM imoveis i
       WHERE NOT coalesce(i.e_parceiro,false) AND coalesce(i.valor_aluguel,0) > 0
         AND nay_esta_no_mercado(i.disponivel,i.bloqueado,i.publicado_no_site) LIMIT 1;
      IF cod_n IS NOT NULL THEN
        k_n := nai_contato_de('5592900667799', 'Corretor do Nosso');
        INSERT INTO nai_turno (contato_id, papel, teste, texto, codigo)
             VALUES (k_n, 'corretor', true, 'quero o ' || cod_n, cod_n) RETURNING id INTO t_n;
        INSERT INTO nai_saida (turno_id, contato_id, papel_destino, tipo, texto, codigo, motivo, estado)
             VALUES (t_n, k_n, 'turno', 'texto', 'card', cod_n, 'teste', 'pendente') RETURNING id INTO s_n;
        SELECT estado INTO est_n FROM nai_saida WHERE id = s_n;
        PERFORM pg_temp.ok(est_n <> 'bloqueado', 'PARCERIA: imovel NOSSO continua saindo normalmente');
      END IF;
    END;
  END;

  -- O NOME DO CONDOMINIO FIXA O IMOVEL (Tel, 16/09, arquivo 58)
  DECLARE k_cnd bigint; t_cnd bigint; cod_cnd int; nome_cnd text;
  BEGIN
    SELECT i.codigo, nai_condominio_ok(i.condominio_nome) INTO cod_cnd, nome_cnd
      FROM imoveis i
     WHERE coalesce(i.valor_aluguel,0) > 0
       AND nay_esta_no_mercado(i.disponivel,i.bloqueado,i.publicado_no_site)
       AND NOT coalesce(i.e_parceiro,false)
       AND length(coalesce(nai_condominio_ok(i.condominio_nome),'')) >= 8
       AND nai_condominio_ok(i.condominio_nome) !~ '/'
       AND 1 = (SELECT count(*) FROM imoveis y
                 WHERE nai_condominio_ok(y.condominio_nome) = nai_condominio_ok(i.condominio_nome)
                   AND nay_esta_no_mercado(y.disponivel,y.bloqueado,y.publicado_no_site)
                   AND NOT coalesce(y.e_parceiro,false))
     LIMIT 1;

    IF cod_cnd IS NOT NULL THEN
      k_cnd := nai_contato_de('5592900116655', 'Corretor do Condominio');
      UPDATE nai_contato SET zerado_em = now() - interval '2 hours', liberado_em = now()
       WHERE id = k_cnd;

      -- ele pergunta pelo NOME: o imovel da conversa tem que sair dai
      PERFORM pg_temp.ok(
        nai_imovel_da_conversa(k_cnd, 'A unidade ' || nome_cnd || ' ainda esta disponivel?') = cod_cnd,
        'CONDOMINIO: o nome escrito por ele vira o imovel da conversa');

      -- o turno guarda, e a mensagem seguinte -- sem nome nenhum -- ainda acha
      INSERT INTO nai_turno (contato_id, papel, teste, texto, codigo)
           VALUES (k_cnd, 'corretor', true, 'A unidade ' || nome_cnd || ' ainda esta disponivel?', cod_cnd)
        RETURNING id INTO t_cnd;
      PERFORM pg_temp.ok(
        nai_imovel_da_conversa(k_cnd, 'Poderia enviar fotos?') = cod_cnd,
        'CONDOMINIO: "poderia enviar fotos?" acha o imovel da mensagem anterior');
    END IF;
  END;

  -- A FAIXA EM VOLTA DO TETO E A MOBILIA (Tel, 16/09, arquivo 59)
  DECLARE j_ped jsonb;
  BEGIN
    j_ped := nai_pedido_de_perfil(
      'Estou com uma cliente querendo algo, com modulados e ar, ate 4.200, preferencia dela no Dom Pedro');
    PERFORM pg_temp.ok((j_ped->>'e_pedido')::boolean,
      'PERFIL: "estou com uma cliente querendo" e pedido de imovel');
    PERFORM pg_temp.ok(j_ped->>'teto' = '4200',
      'PERFIL: o teto de 4.200 e lido');
    PERFORM pg_temp.ok(j_ped->>'mobilia' = 'com',
      'PERFIL: "com modulados e ar" vira filtro de mobilia');
    PERFORM pg_temp.ok(nai_pedido_de_perfil('procuro algo vazio em flores ate 2500')->>'mobilia' = 'sem',
      'PERFIL: "vazio" vira o filtro contrario');
    PERFORM pg_temp.ok(
      nai_pedido_de_perfil('tenho cliente que quer apartamento ate 3 mil mobiliado')->>'mobilia' = 'com',
      'PERFIL: "mobiliado" e reconhecido (o \M no fim da regex comia essa)');
    PERFORM pg_temp.ok(NOT (nai_pedido_de_perfil('esse apartamento tem garagem?')->>'e_pedido')::boolean,
      'PERFIL: pergunta de ficha continua NAO sendo busca');
    PERFORM pg_temp.ok(NOT (nai_pedido_de_perfil('me manda as fotos dele')->>'e_pedido')::boolean,
      'PERFIL: "as fotos dele" continua NAO sendo busca');
  END;

  -- so entra na faixa quem esta perto do teto
  DECLARE n_faixa int; n_baixo int;
  BEGIN
    SELECT count(*) FILTER (WHERE nai_oferta_serve(i, '', 4200, NULL, false, false)),
           count(*) FILTER (WHERE coalesce(i.valor_aluguel,0) > 0 AND i.valor_aluguel < 4200*0.85
                              AND nay_esta_no_mercado(i.disponivel,i.bloqueado,i.publicado_no_site)
                              AND NOT coalesce(i.e_parceiro,false)
                              AND nai_oferta_serve(i, '', 4200, NULL, false, false))
      INTO n_faixa, n_baixo FROM imoveis i;
    PERFORM pg_temp.ok(n_baixo = 0,
      'FAIXA: imovel 15%% abaixo do teto nao entra mais na oferta');
    PERFORM pg_temp.ok(n_faixa > 0,
      'FAIXA: mas a faixa em volta do teto tem opcoes');
  END;

  -- O PAPEL ESCRITO NO NOME DIZ O GENERO (Tel, 16/09, arquivo 57)
  PERFORM pg_temp.ok(nay_tratamento_por_nome('Fiuza - Corretor CRECI 8383') = 'Sr.',
    'TRATAMENTO: "Corretor" sem parenteses vale como masculino (o caso do Sr. Fiuza)');
  PERFORM pg_temp.ok(nay_tratamento_por_nome('Ribamar Neto Corretor de Imoveis') = 'Sr.',
    'TRATAMENTO: "Corretor de Imoveis" e gente, nao empresa');
  PERFORM pg_temp.ok(nay_tratamento_por_nome('Jessica Castro Corretora creci 6205') = 'Sra.',
    'TRATAMENTO: "Corretora" continua feminino (a palavra mais longa vem antes)');
  PERFORM pg_temp.ok(nay_tratamento_por_nome('Uchoa Imoveis') IS NULL,
    'TRATAMENTO: imobiliaria continua sem tratamento');
  PERFORM pg_temp.ok(nay_tratamento_por_nome('Corretor Guarda') IS NULL,
    'TRATAMENTO: sem nome de gente junto, nao inventa "Sr. Corretor"');
  PERFORM pg_temp.ok(nai_vocativo('Fiuza - Corretor CRECI 8383') = 'Sr. Fiuza',
    'TRATAMENTO: o vocativo do Sr. Fiuza sai certo');

  -- FICHA SEM CODIGO E VENDA (Tel, 16/09, arquivos 55 e 56)
  DECLARE
    v_loc  int;   -- um imovel de locacao com nome de condominio usavel
    v_ven  int;   -- um imovel so de venda, idem
    n_loc  text;
    n_ven  text;
  BEGIN
    SELECT i.codigo, nai_condominio_ok(i.condominio_nome) INTO v_loc, n_loc
      FROM imoveis i
     WHERE coalesce(i.valor_aluguel, 0) > 0
       AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
       AND NOT coalesce(i.e_parceiro, false)
       AND length(coalesce(nai_condominio_ok(i.condominio_nome), '')) >= 8
       AND nai_condominio_ok(i.condominio_nome) !~ '/'
     LIMIT 1;

    SELECT i.codigo, nai_condominio_ok(i.condominio_nome) INTO v_ven, n_ven
      FROM imoveis i
     WHERE coalesce(i.valor_aluguel, 0) = 0 AND coalesce(i.valor_venda, 0) > 0
       AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
       AND NOT coalesce(i.e_parceiro, false)
       AND length(coalesce(nai_condominio_ok(i.condominio_nome), '')) >= 8
       AND nai_condominio_ok(i.condominio_nome) !~ '/'
     LIMIT 1;

    IF v_loc IS NOT NULL THEN
      PERFORM pg_temp.ok(
        v_loc = ANY (nai_imovel_pelo_condominio('ficha: ' || n_loc || ' / disponivel?', ANTIGO)),
        'FICHA: card sem codigo e reconhecido pelo nome do condominio');
    END IF;

    IF v_ven IS NOT NULL THEN
      PERFORM pg_temp.ok(
        v_ven = ANY (nai_imovel_pelo_condominio('ficha: ' || n_ven || ' / disponivel para visita?', ANTIGO)),
        'VENDA: ficha de imovel de venda tambem e reconhecida (Tel, 16/09)');
    END IF;

    -- nome que e TIPO nao pode virar imovel
    PERFORM pg_temp.ok(
      coalesce(array_length(nai_imovel_pelo_condominio('voce tem apartamento disponivel?', ANTIGO), 1), 0) = 0,
      'FICHA: a palavra "apartamento" nao vira imovel, mesmo sendo nome de condominio na base');
    PERFORM pg_temp.ok(
      coalesce(array_length(nai_imovel_pelo_condominio('procuro uma casa boa', ANTIGO), 1), 0) = 0,
      'FICHA: "casa" nao vira imovel');
    PERFORM pg_temp.ok(
      coalesce(array_length(nai_imovel_pelo_condominio('bom dia, tudo bem?', ANTIGO), 1), 0) = 0,
      'FICHA: cumprimento nao acha imovel nenhum');
  END;

  -- A VISITA DE VENDA SEGUE O MESMO FLUXO (Tel, 16/09)
  DECLARE
    k_v   bigint;
    t_v   bigint;
    m_v   bigint;
    cod_v int;
    r_v   record;
  BEGIN
    SELECT i.codigo INTO cod_v FROM imoveis i
     WHERE coalesce(i.valor_aluguel, 0) = 0 AND coalesce(i.valor_venda, 0) > 0
       AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
       AND NOT coalesce(i.e_parceiro, false)
     LIMIT 1;

    IF cod_v IS NOT NULL THEN
      k_v := nai_contato_de('5592900009999', 'Corretor da Venda');
      INSERT INTO mensagens (telefone, nome, direcao, origem, texto, status, criada_em, fluxo)
           VALUES ('5592900009999', 'Corretor da Venda', 'recebida', 'texto',
                   'quero visitar o ' || cod_v, 'Recebido', now(), 'nai')
        RETURNING id INTO m_v;
      INSERT INTO nai_turno (contato_id, papel, teste, texto, codigo, msg_ids)
           VALUES (k_v, 'corretor', true, 'quero visitar o ' || cod_v, cod_v, ARRAY[m_v])
        RETURNING id INTO t_v;

      SELECT * INTO r_v FROM nai_pedir_visita(
        t_v, cod_v::text, to_char(now() + interval '2 days', 'YYYY-MM-DD') || ' 15:00', NULL);

      PERFORM pg_temp.ok(
        coalesce(r_v.instrucao_para_voce, '') !~* 'visita de venda segue pelo Tel',
        'VENDA: a visita de venda NAO e mais desviada para o Tel');
      PERFORM pg_temp.ok(
        EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = k_v AND x.codigo = cod_v),
        'VENDA: a visita de venda e criada, como a de locacao');
    END IF;
  END;

  -- pedido claro de imoveis, em outra conversa antiga
  INSERT INTO mensagens (telefone, nome, direcao, origem, texto, status, fluxo, criada_em)
  VALUES ('5592900033333', 'Outro Antigo', 'recebida', 'texto', 'oi', 'Respondido', 'nai',
          now() - interval '30 days');
  PERFORM nai_contato_de('5592900033333', 'Outro Antigo');
  SELECT * INTO r FROM nai_deve_atender('5592900033333', 'voce tem apartamento no Parque 10 ate 4 mil?', NULL);
  PERFORM pg_temp.ok(r.atende AND r.motivo = 'pediu imoveis',
                     'PORTA: pedido claro de imoveis abre a conversa antiga');

  -- ---- os casos das primeiras horas no ar (Tel, 15/09) ----
  -- MARCAR a mensagem do grupo e o filtro que ele deu: "sempre as mensagens
  -- dos grupos sao de imoveis". Ate "Boa noite!" abre a porta assim.
  SELECT * INTO r FROM nai_deve_atender(NOVO, 'Boa noite!', NULL);
  PERFORM pg_temp.ok(NOT r.atende, 'PORTA: cumprimento seco, sem marcar nada, fica calada');
  SELECT * INTO r FROM nai_deve_atender(NOVO, 'Boa noite!', 5717);
  PERFORM pg_temp.ok(r.atende AND r.motivo = 'marcou uma mensagem de imovel',
                     'PORTA: o mesmo cumprimento MARCANDO o card do grupo e atendido');
  PERFORM pg_temp.ok(nai_so_cumprimentou('Boa noite!') AND nai_so_cumprimentou('Oi Nay')
                     AND NOT nai_so_cumprimentou('boa noite, tem apartamento?'),
                     'PORTA: reconhece o cumprimento seco, e so ele');

  -- CONVERSA EM CURSO: frase curta de quem ela ja atende continua com ela.
  -- Sem isto, "pode mandar" e "Ate 400 mil" cairam em silencio nas primeiras
  -- horas no ar -- nove pessoas, a maioria no meio de negociacao.
  DECLARE v_k bigint; v_t bigint; v_s bigint;
  BEGIN
    v_k := (SELECT id FROM nai_contato WHERE chave = nai_chave(NOVO));
    v_t := (nai_abrir_turno(NOVO, 'Gente Nova', 'tem apartamento de 2 quartos?', NULL, '{}')->>'turno_id')::bigint;
    v_s := nai_enfileirar_texto(v_t, NULL, v_k, 'turno', 'Claro! Em qual bairro?', 'resposta', 1);
    UPDATE nai_saida SET estado = 'enviado', enviado_em = now() WHERE id = v_s;
    SELECT * INTO r FROM nai_deve_atender(NOVO, 'pode mandar', NULL);
    PERFORM pg_temp.ok(r.atende AND r.motivo = 'conversa que ela ja estava atendendo',
                       'PORTA: frase curta de quem ela ja atende continua com ela');
    SELECT * INTO r FROM nai_deve_atender(NOVO, 'Até 400 mil', NULL);
    PERFORM pg_temp.ok(r.atende, 'PORTA: "Ate 400 mil" no meio da conversa e atendido');
  END;

  -- e o cabecalho do turno leva a decisao ao fluxo
  PERFORM pg_temp.ok((nai_abrir_turno(NOVO, 'Gente Nova', 'tem apartamento de 2 quartos?', NULL, '{}')->>'atende')::boolean,
                     'PORTA: o cabecalho do turno entrega a decisao ao roteador');
  -- o mesmo pelo lado do NAO, num antigo que ninguem liberou e que o Tel nao
  -- assumiu (quando ele assume, o turno nem chega a abrir -- melhor ainda).
  INSERT INTO mensagens (telefone, nome, direcao, origem, texto, status, fluxo, criada_em)
  VALUES ('5592900044444', 'Antigo Calado', 'recebida', 'texto', 'oi', 'Respondido', 'nai',
          now() - interval '40 days');
  PERFORM nai_contato_de('5592900044444', 'Antigo Calado');
  PERFORM pg_temp.ok((nai_abrir_turno('5592900044444', 'Antigo Calado', 'bom dia', NULL, '{}')->>'atende') = 'false',
                     'PORTA: o cabecalho tambem entrega o NAO -- conversa antiga fica calada');

  -- devolve o mundo como estava: os testes seguintes contam com a regra
  -- desligada, e esquecer isto quebrou dois deles na primeira medicao.
  PERFORM nai_desligar_regra_publico();
  UPDATE nai_config SET valor = v_modo WHERE chave = 'modo';
END $$;

-- ---------- a apresentacao ao proprietario (Tel, 15/09) ----------------
-- "Como ja estamos falando com proprietarios em outros numeros, quando essa
-- nay locacao for falar, seria bom ela colocar antes uma apresentacao."
DO $$
DECLARE prop bigint; v_txt text; t_id bigint; s_id bigint; v_vis bigint;
BEGIN
  prop := nai_contato_de('5592900077777', 'Sr. Hugo');
  v_txt := nai_apresentacao_prop(prop);
  PERFORM pg_temp.ok(v_txt LIKE 'Olá! Este é o número%agendamentos de visitas.%',
                     'APRESENTACAO: vai na PRIMEIRA mensagem ao proprietario');

  -- Depois que ja saiu uma mensagem para ele, nao se apresenta de novo.
  -- A mensagem precisa de uma VISITA dele: a tabela de saida tem uma trava que
  -- so aceita recado a proprietario dentro de uma visita em que ele e o dono --
  -- e foi essa trava, e nao o teste, que derrubou a bateria na primeira
  -- medicao. A parede esta certa; o cenario e que estava pela metade.
  t_id := (nai_abrir_turno('5596991712835', 'Tel Teste', 'oi', NULL, '{}')->>'turno_id')::bigint;
  INSERT INTO nai_visita (codigo, corretor_id, proprietario_id, estado, quando)
  VALUES (5717, (SELECT contato_id FROM nai_turno WHERE id = t_id), prop, 'aguardando_proprietario',
          now() + interval '3 days')
  RETURNING id INTO v_vis;
  s_id := nai_enfileirar_texto(t_id, v_vis, prop, 'proprietario', 'ja falei com ele', 'p_solicita', 1);
  UPDATE nai_saida SET estado = 'enviado', enviado_em = now() WHERE id = s_id;
  PERFORM pg_temp.ok(nai_apresentacao_prop(prop) = '',
                     'APRESENTACAO: da segunda visita em diante ela NAO se repete');

  -- e a frase mora na configuracao: esvaziar desliga
  UPDATE nai_config SET valor = '' WHERE chave = 'apresentacao_proprietario';
  PERFORM pg_temp.ok(nai_apresentacao_prop(nai_contato_de('5592900088888', 'Outro Dono')) = '',
                     'APRESENTACAO: frase vazia na configuracao desliga a apresentacao');
END $$;

-- ------------------------------------------------ visita urgente (3h)
DO $$
DECLARE cab jsonb; r record; v bigint; q text;
BEGIN
  INSERT INTO mensagens (telefone, nome, direcao, origem, texto, status, fluxo)
  VALUES ('5596991712835', 'Tel Teste', 'recebida', 'texto', 'quero visitar o 4255 daqui a pouco', 'Processando', 'nai');
  q := to_char((now() + interval '90 minutes') AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI');
  cab := nai_abrir_turno('5596991712835', 'Tel Teste', 'quero visitar o 4255 daqui a pouco', NULL, ARRAY[(SELECT max(id) FROM mensagens)]::bigint[]);
  SELECT * INTO r FROM nai_pedir_visita((cab->>'turno_id')::bigint, '4255', q, '');
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
  PERFORM pg_temp.ok((SELECT humano_motivo FROM nai_contato WHERE chave = nai_chave('5596991712835')) LIKE 'visita #' || v || ':%',
                     'URGENTE: a Nay para o chat inteiro do corretor');
  PERFORM pg_temp.ok((SELECT nai_linha_acesso_corretor('chave_conosco')) LIKE '%providencio%'
                     AND (SELECT nai_linha_acesso_corretor('chave_conosco')) NOT LIKE '%' || nai_acompanhante() || ' leva%',
                     'CHAVE CONOSCO: ao corretor ela so diz que providencia');
  -- a agenda nao manda "nao consegui fechar" numa visita que estava com o Tel
  UPDATE nai_visita SET quando = now() - interval '5 minutes' WHERE id = v;
  PERFORM nai_agenda_tick();
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM nai_saida WHERE visita_id = v AND motivo = 'expirada' AND papel_destino = 'corretor'),
                     'URGENTE: visita com o Tel nao leva "nao consegui fechar" ao corretor');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE chave = nai_chave('5596991712835');
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
  -- A sugestao sai em mensagem PROPRIA -- pelo caminho de sempre quando nao ha
  -- foto, ou logo depois das fotos quando ha (Tel, 16/09: as fotos vao sempre).
  PERFORM pg_temp.ok((SELECT visita_sugerida_em FROM nai_contato WHERE id = k) IS NOT NULL
                     AND EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t1
                                   AND motivo IN ('sugere_visita', 'depois_das_fotos')
                                   AND texto LIKE '%quer fazer uma visita?%'),
                     'VISITA: a primeira sugestao sai (em outra mensagem) e fica registrada');
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

  -- BAIRRO + BAIRROS AO REDOR: a SEQUENCIA do fluxo mora na ferramenta
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
  PERFORM pg_temp.ok(r.texto_pronto LIKE 'No Ponta Negra eu tenho estas opções:%' AND r.texto_pronto LIKE '%🏢 *%',
                     'BUSCA: bairro com resultado responde a lista formatada (' || left(coalesce(r.texto_pronto, 'nada'), 40) || ')');
  PERFORM pg_temp.ok(nai_lista_pt(ARRAY['seu nome completo', 'CPF', 'CRECI']) = 'seu nome completo, CPF e CRECI', 'lista em portugues');
END $$;

-- ------------------------------------------------------ resposta pela base antes de escalar (13/09)
SELECT pg_temp.ok(nai_resposta_da_base(5611, 'olá o imovel é mobiliado?') LIKE 'Sim! É mobiliado.%',
                  'BASE: "o imovel e mobiliado?" -> a mobilia do cadastro');
SELECT pg_temp.ok(nai_resposta_da_base(5611, 'vem com os móveis?') LIKE '%mobiliado%'
                  AND nai_resposta_da_base(5611, 'tem armario planejado?') LIKE '%mobiliado%'
                  AND nai_resposta_da_base(5611, 'ta mobiliado ou vazio?') LIKE '%mobiliado%',
                  'BASE: mobilia perguntada de outros jeitos');
SELECT pg_temp.ok(nai_resposta_da_base(5611, 'quantos dormitórios?') LIKE '%3 quartos, sendo 1 suíte%'
                  AND nai_resposta_da_base(5611, 'tem garagem?') LIKE '%2 vagas cobertas%'
                  AND nai_resposta_da_base(5611, 'qual a metragem?') LIKE '%88 m²%'
                  AND nai_resposta_da_base(5611, 'quantos banheiros?') LIKE '%3 banheiros%',
                  'BASE: quartos, garagem, metragem e banheiros');
SELECT pg_temp.ok(nai_resposta_da_base(5718, 'é mobiliado?') LIKE 'É semi-mobiliado.%'
                  AND nai_resposta_da_base(5718, 'é mobiliado?') NOT LIKE 'Sim!%',
                  'BASE: imovel SEMI nao responde "Sim!" a "e mobiliado?" -- so a frase');
SELECT pg_temp.ok(nai_resposta_da_base(5611, 'quantos quartos tem?') NOT LIKE '%aluguel%'
                  AND nai_resposta_da_base(5611, 'quantas vagas tem?') NOT LIKE '%aluguel%'
                  AND nai_resposta_da_base(5611, 'quanto é o aluguel?') LIKE '%R$ 4.600%',
                  'BASE: "quantos quartos" nao responde o valor junto; "quanto e o aluguel" responde');
SELECT pg_temp.ok(nai_resposta_da_base(5611, 'quanto é o condomínio?') LIKE '%taxa de condomínio já está inclusa%'
                  AND nai_resposta_da_base(5611, 'qual o valor do aluguel?') LIKE '%R$ 4.600%'
                  AND nai_resposta_da_base(5611, 'é nascente?') LIKE '%nascente%'
                  AND nai_resposta_da_base(5611, 'ainda está disponível?') LIKE 'Sim! Está disponível.%',
                  'BASE: condominio incluso, valor, sol e disponibilidade');
SELECT pg_temp.ok(nai_resposta_da_base(5611, 'onde fica?') LIKE '%Avenida Coronel Teixeira%Ponta Negra%'
                  AND nai_resposta_da_base(5611, 'onde fica?') !~ '\d{3,}',
                  'BASE: onde fica, sem numero do predio nem do apartamento');
SELECT pg_temp.ok(nai_resposta_da_base(5611, 'qual o IPTU?') IS NULL AND nai_resposta_da_base(5611, 'tem energia solar?') IS NULL
                  AND nai_resposta_da_base(5611, 'aceita crianças?') IS NULL,
                  'BASE: sem o dado, nao inventa (volta NULL e a pergunta segue para o Tel)');
DO $$
DECLARE k bigint; t bigint; r record; j jsonb;
BEGIN
  k := nai_contato_de('5592955554444', 'Corretor Base');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = k;
  INSERT INTO mensagens (telefone, nome, direcao, origem, texto, status, fluxo)
  VALUES ('5592955554444', 'Corretor Base', 'recebida', 'texto', 'o 5611 é mobiliado?', 'Processando', 'nai');
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  SELECT * INTO r FROM nai_escalar(t, '5611', 'mobilia', 'olá o imovel é mobiliado?');
  PERFORM pg_temp.ok(r.texto_pronto LIKE 'Sim! É mobiliado.%'
                     AND NOT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND papel_destino = 'tel')
                     AND (SELECT humano_assumiu_em FROM nai_contato WHERE id = k) IS NULL,
                     'BASE: escalar_ao_tel com a resposta na ficha responde e NAO escala');
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  j := nai_enfileirar_resposta(t, 'SILENCIO', '["5611"]', 'olá o imovel é mobiliado?', '[]');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND papel_destino = 'turno' AND texto LIKE 'Sim! É mobiliado.%')
                     AND NOT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND papel_destino = 'tel')
                     AND (SELECT humano_assumiu_em FROM nai_contato WHERE id = k) IS NULL,
                     'BASE: marcou o card (codigo so no turno), perguntou sem numero e ela ficou calada -> responde pela ficha');
  SELECT * INTO r FROM nai_o_que_sei_do_imovel('5611', 'tem móveis?');
  PERFORM pg_temp.ok(r.sabe AND r.texto_pronto LIKE 'Sim! É mobiliado.%', 'BASE: a ferramenta o_que_sei_do_imovel responde pela ficha (sabe=true)');
END $$;

-- ------------------------------------------------------ o formato da resposta (Tel, 13/09)
SELECT pg_temp.ok(nai_resposta_da_base(5611, 'é mobiliado?') =
                  'Sim! É mobiliado.' || E'\n\n' || 'Tem móveis, cama e tudo.' || E'\n' ||
                  'Tem 3 quartos, sendo 1 suíte.' || E'\n' || 'Tem 3 banheiros.' || E'\n' ||
                  'Tem 2 vagas cobertas.' || E'\n' || 'Tem 88 m².' || E'\n' || 'Fica no 11º andar.',
                  'FORMATO: afirmacao formal, linha vazia, e a ficha listada (' || coalesce(nai_resposta_da_base(5611, 'é mobiliado?'), 'nada') || ')');
SELECT pg_temp.ok(nai_resposta_da_base(5611, 'é mobiliado?') !~ '[😀-🿿]'
                  AND nai_resposta_da_base(5611, 'qual o valor?') LIKE 'O aluguel é R$ 4.600%'
                  AND nai_resposta_da_base(5611, 'quantos quartos?') LIKE 'Tem 3 quartos, sendo 1 suíte.%',
                  'FORMATO: sem emoji, e pergunta com "qual/quantos" nao leva "Sim!"');
DO $$
DECLARE k bigint; t bigint; j jsonb; x text;
BEGIN
  k := nai_contato_de('5592933330000', 'Corretor Formato');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL, visita_sugerida_em = NULL WHERE id = k;
  UPDATE nai_visita SET estado = 'cancelada', encerrada_em = now() WHERE corretor_id = k AND nai_visita_aberta(estado);
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  PERFORM nai_usou_ferramenta(t, 'imovel_por_codigo');
  j := nai_enfileirar_resposta(t, 'Sim, Sr. Pedro! O 5611 ainda está disponível. Quer que eu mande as fotos?',
                               '["5611"]', 'o 5611 ainda ta disponivel?', '[]');
  SELECT string_agg(texto, ' || ' ORDER BY ordem) INTO x FROM nai_saida WHERE turno_id = t AND tipo = 'texto';
  -- as fotos vao junto desde 16/09, entao quem convida e o "depois das fotos"
  PERFORM pg_temp.ok(x = nai_resposta_da_base(5611, 'o 5611 ainda ta disponivel?') ||
                         ' || Aqui as fotos, quer fazer uma visita? Só me informar um horário' ||
                         ' || Ou se tiver alguma dúvida ou quiser mais imóveis me fala o que está procurando, que já vejo aqui para você, ok?'
                     AND j->>'guarda' LIKE '%formato_da_base%',
                     'FORMATO: a frase solta do modelo e trocada pela ficha, no formato do Tel (' || coalesce(x, 'nada') || ')');
  -- contato NOVO, sem nada na mesa: aqui nao ha imovel para a trava usar
  k := nai_contato_de('5592933339999', 'Corretor Sem Contexto');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL, visita_sugerida_em = now() WHERE id = k;
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  PERFORM nai_usou_ferramenta(t, 'imovel_por_codigo');
  j := nai_enfileirar_resposta(t, 'De qual imóvel você fala?', '[]', 'e esse outro, ainda tem?', '[]');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND texto = 'De qual imóvel você fala?'),
                     'FORMATO: sem imovel nenhum na conversa, a fala dela sai como ela escreveu');

  k := nai_contato_de('5592933331111', 'Corretor Ferramenta');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL, visita_sugerida_em = NULL WHERE id = k;
  UPDATE nai_visita SET estado = 'cancelada', encerrada_em = now() WHERE corretor_id = k AND nai_visita_aberta(estado);
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  PERFORM nai_usou_ferramenta(t, 'o_que_sei_do_imovel');
  j := nai_enfileirar_resposta(t, 'Sim! É mobiliado.' || E'\n\n' || 'Tem móveis, cama e tudo.', '[]', 'o 5611 é mobiliado?', '[]');
  SELECT string_agg(texto, ' || ' ORDER BY ordem) INTO x FROM nai_saida WHERE turno_id = t AND tipo = 'texto';
  PERFORM pg_temp.ok(x = nai_resposta_da_base(5611, 'o 5611 é mobiliado?') ||
                         ' || Aqui as fotos, quer fazer uma visita? Só me informar um horário || Ou se tiver alguma dúvida ou quiser mais imóveis me fala o que está procurando, que já vejo aqui para você, ok?',
                     'SUGESTAO: respondeu consultando a base (sem "Sobre isso:") e a sugestao sai em outra mensagem (' || coalesce(x, 'nada') || ')');
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  PERFORM nai_usou_ferramenta(t, 'imovel_por_codigo');
  UPDATE nai_contato SET visita_sugerida_em = NULL WHERE id = k;
  j := nai_enfileirar_resposta(t, 'Segue o card' || E'\n' || '📍 Teste' || E'\n' || 'Código: 5611', '["5611"]', 'manda as fotos do 5611', '[]');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND motivo = 'sugere_visita')
                     AND EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND motivo = 'depois_das_fotos'),
                     'SUGESTAO: com fotos na resposta, quem convida e o "depois das fotos" -- nao entra sugestao dupla');

  k := nai_contato_de('5592933332222', 'Corretor Emoji');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL, visita_sugerida_em = now() WHERE id = k;
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  j := nai_enfileirar_resposta(t, 'Boa tarde, Sr. Pedro! Tudo certo 😉🙌', '[]', 'boa tarde', '[]');
  SELECT texto INTO x FROM nai_saida WHERE turno_id = t AND tipo = 'texto';
  PERFORM pg_temp.ok(x = 'Boa tarde, Sr. Pedro! Tudo certo', 'EMOJI: sai de tudo que a Nay escreve (' || coalesce(x, 'nada') || ')');
END $$;

-- ------------------------------------------------------ so no numero do Pedro: escala sem parar o chat (13/09)
DO $$
DECLARE k bigint;
BEGIN
  k := nai_contato_de('5592966665555', 'Corretor Guarda');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = k;
  UPDATE nai_config SET valor = '5592966665555' WHERE chave = 'escala_sem_parar';
  PERFORM nai_parar_chat(k, 'teste');
  PERFORM pg_temp.ok((SELECT humano_assumiu_em FROM nai_contato WHERE id = k) IS NULL, 'EXCECAO: numero da lista escala sem parar o chat');
  UPDATE nai_config SET valor = '' WHERE chave = 'escala_sem_parar';
  PERFORM nai_parar_chat(k, 'teste');
  PERFORM pg_temp.ok((SELECT humano_assumiu_em FROM nai_contato WHERE id = k) IS NOT NULL, 'EXCECAO: fora da lista, para como sempre');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = k;
END $$;

-- ------------------------------------------------------ numero do Tel no teste (13/09)
UPDATE nai_config SET valor = '5596991712835,559294717316' WHERE chave = 'numeros_teste';
SELECT pg_temp.ok(nai_quem_atende('559294717316', false, 'Alugou piedade gavino') = 'nay',
                  'TEL NO TESTE: "Alugou piedade gavino" segue no caminho antigo (publicador)');
SELECT pg_temp.ok(nai_quem_atende('559294717316', false, 'envia esse imóvel para a Geina 92 9182-4643  5706') = 'nay',
                  'TEL NO TESTE: "envia esse imovel para a Geina" segue no publicador');
SELECT pg_temp.ok(nai_quem_atende('559294717316', false, 'Nay posta o 5750') = 'nay' AND nai_quem_atende('559294717316', false, 'Vagas') = 'nay'
                  AND nai_quem_atende('559294717316', false, 'RESPOSTA 12 pode ser 15h') = 'nay'
                  AND nai_quem_atende('559294717316', false, 'posta no nosso grupo anunciar easy o 5729') = 'nay',
                  'TEL NO TESTE: posta, Vagas e RESPOSTA seguem no publicador');
SELECT pg_temp.ok(nai_quem_atende('559294717316', false, 'boa tarde, tem fotos do 5718?') = 'nai'
                  AND nai_quem_atende('559294717316', false, 'me manda as fotos do 5718') = 'nai'
                  AND nai_quem_atende('559294717316', false, 'manda as fotos pra mim') = 'nai'
                  AND nai_quem_atende('559294717316', false, 'tira uma duvida: aceita pet?') = 'nai',
                  'TEL NO TESTE: conversa de corretor vai para a NAI');
SELECT pg_temp.ok(nai_quem_atende('5596991712835', false, 'Alugou piedade gavino') = 'nai'
                  AND nai_quem_atende('559291112222', false, 'boa tarde') = 'nay'
                  AND nai_quem_atende('559294717316', true, 'Alugou piedade gavino') = 'nay',
                  'TEL NO TESTE: so o numero do Tel desvia comando; fora do teste e grupo seguem na Nay');
DO $$
DECLARE cab jsonb;
BEGIN
  cab := nai_abrir_turno('559294717316', 'Tel', 'VISITAS', NULL, '{}');
  PERFORM pg_temp.ok(cab->>'papel' = 'tel', 'TEL NO TESTE: VISITAS do numero do Tel, sem prefixo, e comando do Tel');
  cab := nai_abrir_turno('559294717316', 'Tel', 'tem fotos do 5718?', NULL, '{}');
  PERFORM pg_temp.ok(cab->>'papel' = 'corretor', 'TEL NO TESTE: conversa normal do Tel e tratada como corretor');
END $$;

-- ------------------------------------------------------ revisao das mensagens (13/09)
SELECT pg_temp.ok(nai_fone_fmt('559691712835') = '(96) 99171-2835' AND nai_fone_fmt('5592992019498') = '(92) 99201-9498',
                  'TELEFONE: celular que chega sem o 9 sai com o 9');
DO $$
DECLARE k bigint; t bigint; j jsonb; x text;
BEGIN
  k := nai_contato_de('5592994209841', 'Corretor Sugestao');
  UPDATE nai_contato SET visita_sugerida_em = NULL WHERE id = k;
  UPDATE nai_visita SET estado = 'cancelada', encerrada_em = now() WHERE corretor_id = k AND nai_visita_aberta(estado);
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  j := nai_enfileirar_resposta(t, 'Sobre isso: o 5611 é mobiliado 😉', '[]', 'o 5611 é mobiliado?', '[]');
  SELECT string_agg(texto, ' || ' ORDER BY ordem) INTO x FROM nai_saida WHERE turno_id = t AND tipo = 'texto';
  PERFORM pg_temp.ok(x = nai_resposta_da_base(5611, 'o 5611 é mobiliado?') ||
                         ' || Aqui as fotos, quer fazer uma visita? Só me informar um horário || Ou se tiver alguma dúvida ou quiser mais imóveis me fala o que está procurando, que já vejo aqui para você, ok?',
                     'CARD "Responde com a base": a sugestao vai em OUTRA mensagem, e sem emoji (' || coalesce(x, 'nada') || ')');
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  j := nai_enfileirar_resposta(t, 'Sobre isso: tem 2 vagas 😉', '[]', 'quantas vagas?', '[]');
  SELECT string_agg(texto, ' || ' ORDER BY ordem) INTO x FROM nai_saida WHERE turno_id = t AND tipo = 'texto';
  -- 14/09: o imovel do turno anterior (5611) segue na conversa, entao a ficha
  -- responde a pergunta das vagas. O que este teste guarda e a sugestao: ela
  -- NAO se repete no mesmo dia.
  PERFORM pg_temp.ok(x = nai_resposta_da_base(5611, 'quantas vagas?')
                     AND NOT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t AND motivo = 'sugere_visita'),
                     'CARD "Responde com a base": a sugestao nao se repete no mesmo dia (' || coalesce(left(x, 40), 'nada') || ')');
END $$;

-- ------------------------------------------------------ no teste, tudo chega no chat dele (13/09)
DO $$
DECLARE k bigint; t bigint; r record;
BEGIN
  k := nai_contato_de('5592911115555', 'Corretor Simulado');
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  PERFORM nai_enfileirar_texto(t, NULL, k, 'turno', 'Boa tarde! Segue a resposta.', 'resposta', 1);
  PERFORM * FROM nai_liberar_saida(t);
  SELECT * INTO r FROM nai_saida WHERE turno_id = t ORDER BY id DESC LIMIT 1;
  PERFORM pg_temp.ok(r.redirecionado AND nai_chave(r.telefone_final) = nai_chave('5596991712835')
                     AND r.resposta->>'texto_final' LIKE '🧪 TESTE · iria para o CORRETOR Corretor Simulado (92) 91111-5555' || E'\n\n' || '%'
                     AND r.resposta->>'texto_final' LIKE '%Boa tarde! Segue a resposta.',
                     'TESTE: mensagem de corretor de outro numero chega no chat dele, etiquetada (' ||
                     coalesce(left(r.resposta->>'texto_final', 60), 'nada') || ')');
  SELECT * INTO r FROM nai_saida WHERE turno_id = t ORDER BY id DESC LIMIT 1;
  PERFORM pg_temp.ok(r.estado <> 'bloqueado', 'TESTE: nao morre mais como "teste_fora_da_lista"');
END $$;

-- ------------------------------------------------------ o teste completo do Tel (13/09, noite)
SELECT pg_temp.ok(nai_bloco_oferta(5718) = '🏢 *Arezzo Residencial — Flores #5718*' || E'\n' ||
                  '• 2 quartos' || E'\n' || '• R$ 2.500/mês' || E'\n' || '• Semimobiliado',
                  'OFERTA: o bloco sai no formato do Tel (' || coalesce(replace(nai_bloco_oferta(5718), E'\n', ' / '), 'nada') || ')');
SELECT pg_temp.ok(nai_sem_emoji_resposta('Boa tarde! Tudo certo 😉') = 'Boa tarde! Tudo certo'
                  AND nai_sem_emoji_resposta('🏢 *Arezzo* 😉' || E'\n' || '📍 Ponta Negra') = '🏢 *Arezzo*' || E'\n' || '📍 Ponta Negra',
                  'EMOJI: tira o da fala dela e mantem o simbolo do card e da lista');
DO $$
DECLARE k bigint; t bigint; j jsonb; r record; x text;
BEGIN
  -- IMOVEL DA CONVERSA
  k := nai_contato_de('5592922221111', 'Corretor Contexto');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL, visita_sugerida_em = now() WHERE id = k;
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  PERFORM nai_enfileirar_texto(t, NULL, k, 'turno', 'No Parque 10 eu tenho: Código: 5718', 'resposta', 1);
  PERFORM pg_temp.ok(nai_imovel_da_conversa(k, 'e aí, é mobiliado?') = 5718,
                     'CONTEXTO: um imovel na mesa -> a pergunta sem codigo e desse imovel');
  PERFORM nai_enfileirar_texto(t, NULL, k, 'turno', 'e também o Código: 5717', 'resposta', 2);
  PERFORM pg_temp.ok(nai_imovel_da_conversa(k, 'e aí, é mobiliado?') IS NULL,
                     'CONTEXTO: dois na mesa e sem nome -> NULL, ela pergunta em vez de chutar');
  PERFORM pg_temp.ok(nai_imovel_da_conversa(k, 'me manda foto do arezzo') = 5718,
                     'CONTEXTO: ele chamou pelo nome do condominio -> acha o imovel');
  PERFORM pg_temp.ok(nai_imovel_da_conversa(k, 'o 5717 é mobiliado?') = 5717,
                     'CONTEXTO: o codigo que ELE escreveu vale mais que tudo');

  -- FOTO PELO NOME, sem codigo escrito
  k := nai_contato_de('5592922222222', 'Corretor Foto');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL, visita_sugerida_em = now() WHERE id = k;
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  PERFORM nai_enfileirar_texto(t, NULL, k, 'turno', 'Segue: Código: 5718', 'resposta', 1);
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  j := nai_enfileirar_resposta(t, 'Claro, Sr. Pedro! Já mando as fotos.', '[]', 'Me manda foto do arezzo', '[]');
  PERFORM pg_temp.ok((j->>'fotos')::int > 0,
                     'FOTO: "me manda foto do arezzo" manda as fotos DAQUELE imovel (' || coalesce(j->>'fotos', '0') || ' fotos)');

  -- ela anuncia foto e nao ha imovel: UMA pergunta, sem loop
  k := nai_contato_de('5592922223333', 'Corretor Loop');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL, visita_sugerida_em = now() WHERE id = k;
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  j := nai_enfileirar_resposta(t, 'As fotos estão vindo, Sr. Pedro!', '[]', 'me manda as fotos', '[]');
  SELECT texto INTO x FROM nai_saida WHERE turno_id = t AND tipo = 'texto' ORDER BY id LIMIT 1;
  PERFORM pg_temp.ok((j->>'fotos')::int = 0 AND x = 'De qual imóvel o Sr. quer as fotos? Me passa o código que eu já mando.',
                     'FOTO: sem saber o imovel ela pergunta, em vez de anunciar foto que nao vem (' || coalesce(x, 'nada') || ')');

  -- "3500" e faixa de preco, nao codigo
  k := nai_contato_de('5592922224444', 'Corretor Valor');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = k;
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  PERFORM pg_temp.ok(NOT nai_esperando_valor(k), 'VALOR: sem ter perguntado, numero solto continua sendo codigo');
  PERFORM nai_enfileirar_texto(t, NULL, k, 'turno', 'E qual a faixa de preço que seus clientes estão buscando?', 'resposta', 1);
  PERFORM pg_temp.ok(nai_esperando_valor(k), 'VALOR: logo depois da pergunta da faixa, numero solto e VALOR');

  -- a lista formatada
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  SELECT * INTO r FROM nai_buscar_por_perfil(t, 'Parque 10 de Novembro', '3500', NULL, 'tanto faz');
  PERFORM pg_temp.ok(r.texto_pronto LIKE 'No Parque 10 de Novembro%' AND r.texto_pronto LIKE '%🏢 *%#%*%'
                     AND r.texto_pronto LIKE '%• R$ %/mês%',
                     'LISTA: sai no formato do Tel, um bloco por imovel');
  SELECT * INTO r FROM nai_buscar_por_perfil(t, 'Parque 10 de Novembro', '1200', NULL, 'tanto faz');
  PERFORM pg_temp.ok(r.texto_pronto NOT LIKE '%R$ 2.750%', 'LISTA: o teto que ele deu e respeitado');
END $$;

-- ------------------------------------------------------ a esteira de conferencia (Tel, 14/09)
SELECT pg_temp.ok(nai_limpar_markdown('**Oi**' || chr(10) || '## titulo') = 'Oi' || chr(10) || 'titulo'
                  AND nai_limpar_markdown('  **teste**  ') = 'teste',
                  'ESTEIRA: markdown do WhatsApp limpo (' || replace(nai_limpar_markdown('**Oi**' || chr(10) || '## titulo'), chr(10), ' / ') || ')');
SELECT pg_temp.ok(nai_tirar_frase('Boa tarde. Vou passar pro Tel. Segue o card.', '\mtel\M') = 'Boa tarde. Segue o card.',
                  'ESTEIRA: tira a frase inteira que cita o Tel (' || nai_tirar_frase('Boa tarde. Vou passar pro Tel. Segue o card.', '\mtel\M') || ')');
SELECT pg_temp.ok(nai_pergunta_qual_imovel('De qual imóvel o Sr. quer as fotos?')
                  AND NOT nai_pergunta_qual_imovel('Segue o imóvel que o Sr. pediu.'),
                  'ESTEIRA: reconhece a pergunta "de qual imovel?"');
SELECT pg_temp.ok(nai_uma_pergunta_da_sequencia('Qual bairro e qual a faixa de preço?') LIKE '%qual bairro?%'
                  AND nai_uma_pergunta_da_sequencia('Qual bairro seu cliente quer?') IS NULL,
                  'ESTEIRA: duas perguntas viram uma; uma pergunta so passa direto');
DO $$
DECLARE k bigint; t bigint; d jsonb; n int; x text;
BEGIN
  k := nai_contato_de('5592911116666', 'Corretor Esteira');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL, zerado_em = now(), visita_sugerida_em = now() WHERE id = k;
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;

  -- CONFERIR nao envia nada: so decide
  d := nai_conferir_resposta(t, 'Boa tarde, Sr. Pedro! Tudo certo por aqui.', '[]', 'boa tarde', '[]');
  PERFORM pg_temp.ok(d->>'acao' = 'responder' AND d->>'texto' = 'Boa tarde, Sr. Pedro! Tudo certo por aqui.'
                     AND NOT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = t),
                     'ESTEIRA: conferir DECIDE e nao envia nada (' || coalesce(d->>'acao', 'nada') || ')');
  SELECT count(*) INTO n FROM nai_conferencia WHERE turno_id = t;
  PERFORM pg_temp.ok(n >= 15, 'ESTEIRA: todas as conferencias ficam registradas (' || n || ' etapas)');
  SELECT esteira INTO x FROM vw_nai_conferencia WHERE turno_id = t;
  PERFORM pg_temp.ok(x LIKE '%1. imovel_da_conversa%' AND x LIKE '%6. silencio%' AND x LIKE '%15. portao_de_fotos%',
                     'ESTEIRA: a view mostra a esteira na ordem');

  -- a decisao de calar aparece como tal
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  d := nai_conferir_resposta(t, 'SILENCIO', '[]', 'ok, obrigado', '[]');
  PERFORM pg_temp.ok(d->>'acao' = 'silencio'
                     AND EXISTS (SELECT 1 FROM nai_conferencia WHERE turno_id = t AND etapa = 'silencio' AND resultado = 'parou'),
                     'ESTEIRA: o SILENCIO e uma decisao registrada, nao um efeito colateral');
END $$;

-- ------------------------------------------------------ a citacao do que a NAI mandou (14/09)
DO $$
DECLARE k bigint; t bigint; s1 bigint; s2 bigint;
BEGIN
  k := nai_contato_de('5592911117777', 'Corretor Citacao');
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  -- a foto tem que ser uma URL de verdade daquele imovel: o gatilho confere
  INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, imagem_url, codigo, ordem, motivo, message_id)
  VALUES (t, k, 'turno', '', 'imagem', (SELECT url FROM imovel_fotos WHERE codigo = 5611 ORDER BY ordem LIMIT 1),
          5611, 1, 'foto', 'ID-FOTO-TESTE') RETURNING id INTO s1;
  INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, texto, ordem, motivo, message_id)
  VALUES (t, k, 'turno', '', 'texto', E'📍 Condomínio Acquarelle\n• Bairro: Ponta Negra\nCódigo: 5611', 2, 'resposta', 'ID-CARD-TESTE') RETURNING id INTO s2;
  PERFORM pg_temp.ok(nay_imovel_da_citacao('ID-FOTO-TESTE') = '5611',
                     'CITACAO: marcou uma FOTO que a NAI mandou -> acha o imovel');
  PERFORM pg_temp.ok(nay_imovel_da_citacao('ID-CARD-TESTE') = '5611',
                     'CITACAO: marcou o CARD que a NAI mandou -> acha o imovel');
  PERFORM pg_temp.ok(nay_imovel_da_citacao('ID-QUE-NAO-EXISTE') IS NULL,
                     'CITACAO: ID que nao conhecemos continua devolvendo NULL (ela pergunta)');
  -- 14/09: ele marca a PROPRIA mensagem (o card que ele colou)
  INSERT INTO mensagens (telefone, nome, direcao, origem, texto, status, fluxo, message_id)
  VALUES ('5592911117777', 'Corretor Citacao', 'recebida', 'texto',
          E'📍 Condomínio Acquarelle\nBairro: Ponta Negra\nCódigo: 5611', 'Respondido', 'nai', 'ID-COLADO-TESTE');
  PERFORM pg_temp.ok(nay_imovel_da_citacao('ID-COLADO-TESTE') = '5611',
                     'CITACAO: marcou o card que ELE mesmo colou -> acha o imovel');
  INSERT INTO mensagens (telefone, nome, direcao, origem, texto, status, fluxo, message_id)
  VALUES ('5592911117777', 'Corretor Citacao', 'recebida', 'texto', 'bom dia, tudo bem?', 'Respondido', 'nai', 'ID-CONVERSA-TESTE');
  PERFORM pg_temp.ok(nay_imovel_da_citacao('ID-CONVERSA-TESTE') IS NULL,
                     'CITACAO: mensagem dele sem codigo nenhum continua NULL');
END $$;

-- ------------------------------------------------------ conversa zerada (Tel, 14/09)
DO $$
DECLARE k bigint; t bigint; j jsonb; x text; n int;
BEGIN
  k := nai_contato_de('5592911119999', 'Corretor Zerar');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL, zerado_em = NULL, visita_sugerida_em = now() WHERE id = k;
  INSERT INTO nai_turno (contato_id, papel, teste, codigo) VALUES (k, 'corretor', false, 5611) RETURNING id INTO t;
  PERFORM pg_temp.ok(nai_imovel_da_conversa(k, 'e as fotos dele?') = 5611,
                     'ZERAR: antes de zerar, o imovel do turno anterior e o da conversa');
  PERFORM nai_zerar_conversa('5592911119999');
  PERFORM pg_temp.ok(nai_imovel_da_conversa(k, 'e as fotos dele?') IS NULL
                     AND (SELECT zerado_em FROM nai_contato WHERE id = k) IS NOT NULL,
                     'ZERAR: depois de zerar, ela atende como se fosse cliente novo');
  PERFORM pg_temp.ok(nai_imovel_da_conversa(k, 'o 5611 é mobiliado?') = 5611,
                     'ZERAR: o codigo que ELE escreve agora vale, mesmo com a conversa zerada');

  -- foto saindo e "de qual imovel?" na mesma resposta: a pergunta nao sai
  k := nai_contato_de('5592911118888', 'Corretor Foto Pergunta');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL, zerado_em = NULL, visita_sugerida_em = now() WHERE id = k;
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  j := nai_enfileirar_resposta(t, 'De qual imóvel o Sr. quer as fotos?', '["5611"]', 'me manda as fotos do 5611', '[]');
  SELECT string_agg(texto, ' || ' ORDER BY ordem) INTO x FROM nai_saida WHERE turno_id = t AND tipo = 'texto';
  PERFORM pg_temp.ok((j->>'fotos')::int > 0 AND x NOT LIKE '%qual imóvel%'
                     AND x LIKE 'Aqui as fotos%',
                     'FOTO: com foto saindo, a pergunta "de qual imovel?" nao vai junto (' || coalesce(left(x, 40), 'nada') || ')');
END $$;

-- ------------------------------------------------------ pedido de foto de imovel SEM foto (14/09)
DO $$
DECLARE k bigint; t bigint; j jsonb; x text; n_sug int;
BEGIN
  k := nai_contato_de('5592911105555', 'Corretor Sem Foto');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL, zerado_em = now(), visita_sugerida_em = NULL WHERE id = k;
  UPDATE nai_visita SET estado = 'cancelada', encerrada_em = now() WHERE corretor_id = k AND nai_visita_aberta(estado);
  -- um imovel nosso, no mercado, sem nenhuma foto na tabela (simulado)
  CREATE TEMP TABLE IF NOT EXISTS _sem_foto AS SELECT id, codigo, url FROM imovel_fotos WHERE codigo = 5611;
  DELETE FROM imovel_fotos WHERE codigo = 5611;
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', false) RETURNING id INTO t;
  PERFORM nai_usou_ferramenta(t, 'imovel_por_codigo');
  j := nai_enfileirar_resposta(t, 'De qual imóvel o Sr. quer as fotos?', '["5611"]', 'tem fotos desse?', '[]');
  SELECT string_agg(texto, ' || ' ORDER BY ordem) INTO x FROM nai_saida WHERE turno_id = t AND tipo = 'texto';
  SELECT count(*) INTO n_sug FROM nai_saida WHERE turno_id = t AND motivo = 'sugere_visita';
  PERFORM pg_temp.ok(coalesce(x, '') NOT LIKE '%qual imóvel%',
                     'SEM FOTO: imovel IDENTIFICADO e sem foto -> nao pergunta "de qual imovel" (' || coalesce(x, 'nada') || ')');
  PERFORM pg_temp.ok(n_sug = 0,
                     'SEM FOTO: pedido de foto nunca solta a sugestao de visita antes das fotos');
  PERFORM pg_temp.ok(coalesce(x, '') NOT LIKE '%vou confirmar com o Tel%',
                     'SEM FOTO: sem promessa de "vou confirmar com o Tel e ja te mando"');
  INSERT INTO imovel_fotos (id, codigo, url) SELECT id, codigo, url FROM _sem_foto;
END $$;

-- ------------------------------------------------------ foto que ja e mosaico nao vai no privado (14/09)
DO $$
DECLARE n_antes int; n_depois int;
BEGIN
  SELECT count(*) INTO n_antes FROM nai_imagens_do_envio(5611);
  UPDATE imovel_fotos SET e_mosaico = true
   WHERE id = (SELECT id FROM imovel_fotos WHERE codigo = 5611 ORDER BY ordem LIMIT 1);
  SELECT count(*) INTO n_depois FROM nai_imagens_do_envio(5611);
  PERFORM pg_temp.ok(n_depois = n_antes - 1,
                     'MOSAICO: a foto do anuncio marcada como mosaico sai da lista do privado (' || n_antes || ' -> ' || n_depois || ')');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM nai_imagens_do_envio(5611) WHERE e_colagem),
                     'MOSAICO: a nossa colagem tambem nunca vai no privado');
END $$;

-- ------------------------------------------------------ "depois das fotos" nao e repeticao (14/09)
DO $$
DECLARE k bigint; t1 bigint; t2 bigint; t3 bigint; r record;
  frase text := 'Ou se tiver alguma dúvida ou quiser mais imóveis me fala o que está procurando, que já vejo aqui para você, ok?';
BEGIN
  k := nai_contato_de('5596991712835', 'Tel Teste');
  UPDATE nai_contato SET humano_assumiu_em = NULL, humano_motivo = NULL WHERE id = k;
  -- 1) a frase sai junto da sugestao de visita
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', true) RETURNING id INTO t1;
  PERFORM nai_enfileirar_texto(t1, NULL, k, 'turno', frase, 'sugere_visita', 1);
  PERFORM * FROM nai_liberar_saida(t1);
  -- 2) minutos depois, as fotos: a mesma frase TEM que sair
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', true) RETURNING id INTO t2;
  PERFORM nai_enfileirar_texto(t2, NULL, k, 'turno', frase, 'depois_das_fotos', 1);
  PERFORM * FROM nai_liberar_saida(t2);
  SELECT * INTO r FROM nai_saida WHERE turno_id = t2 ORDER BY id DESC LIMIT 1;
  PERFORM pg_temp.ok(r.estado <> 'bloqueado',
                     'REPETIDA: a frase do "depois das fotos" sai mesmo tendo saido minutos antes (' || r.estado || coalesce(' / ' || r.bloqueio, '') || ')');
  -- 3) a trava continua valendo para a fala do modelo
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', true) RETURNING id INTO t3;
  PERFORM nai_enfileirar_texto(t3, NULL, k, 'turno', frase, 'resposta', 1);
  PERFORM * FROM nai_liberar_saida(t3);
  SELECT * INTO r FROM nai_saida WHERE turno_id = t3 ORDER BY id DESC LIMIT 1;
  PERFORM pg_temp.ok(r.estado = 'bloqueado' AND r.bloqueio = 'repetida',
                     'REPETIDA: a mesma frase escrita pelo modelo continua barrada em 10 minutos');
  -- 3b) o mesmo texto de VISITA para outra visita nao e repeticao (14/09)
  DECLARE v1 bigint; v2 bigint; tv1 bigint; tv2 bigint; rv record;
  BEGIN
    -- uma visita aberta por vez (regra nai_visita_uma_aberta): a primeira e
    -- encerrada antes de a segunda abrir, como acontece de verdade.
    INSERT INTO nai_visita (corretor_id, codigo, quando, estado)
    VALUES (k, 5611, now() + interval '1 day', 'aguardando_proprietario') RETURNING id INTO v1;
    INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', true) RETURNING id INTO tv1;
    PERFORM nai_enfileirar_texto(tv1, v1, k, 'turno', 'Temos um pedido de visita no seu imóvel.', 'p_solicita', 1);
    PERFORM * FROM nai_liberar_saida(tv1);
    UPDATE nai_visita SET estado = 'cancelada', encerrada_em = now() WHERE id = v1;
    INSERT INTO nai_visita (corretor_id, codigo, quando, estado)
    VALUES (k, 5611, now() + interval '1 day', 'aguardando_proprietario') RETURNING id INTO v2;
    INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', true) RETURNING id INTO tv2;
    PERFORM nai_enfileirar_texto(tv2, v2, k, 'turno', 'Temos um pedido de visita no seu imóvel.', 'p_solicita', 1);
    PERFORM * FROM nai_liberar_saida(tv2);
    SELECT * INTO rv FROM nai_saida WHERE turno_id = tv2 ORDER BY id DESC LIMIT 1;
    PERFORM pg_temp.ok(rv.estado <> 'bloqueado',
                       'REPETIDA: o mesmo texto para OUTRA visita sai (' || rv.estado || coalesce(' / ' || rv.bloqueio, '') || ')');
    UPDATE nai_visita SET estado = 'cancelada', encerrada_em = now() WHERE id IN (v1, v2);
  END;
  -- 4) depois de ZERAR a conversa, o que saiu antes nao barra mais nada (14/09)
  PERFORM nai_zerar_conversa('5596991712835');
  INSERT INTO nai_turno (contato_id, papel, teste) VALUES (k, 'corretor', true) RETURNING id INTO t3;
  PERFORM nai_enfileirar_texto(t3, NULL, k, 'turno', frase, 'sugere_visita', 1);
  PERFORM * FROM nai_liberar_saida(t3);
  SELECT * INTO r FROM nai_saida WHERE turno_id = t3 ORDER BY id DESC LIMIT 1;
  PERFORM pg_temp.ok(r.estado <> 'bloqueado',
                     'REPETIDA: conversa zerada e conversa nova -- a frase de antes do marco nao barra (' || r.estado || coalesce(' / ' || r.bloqueio, '') || ')');
END $$;

-- ------------------------------------------------------ quem a Nay atende (Tel, 13/09) -- ainda DESLIGADA
SELECT pg_temp.ok(nai_pede_foto('Tem fotos do imóvel 5611?') AND nai_pede_foto('vc pode me mandar as imagens desse ap?')
                  AND nai_pede_foto('me mostra a fachada') AND NOT nai_pede_foto('já recebi as fotos, obrigado')
                  AND NOT nai_pede_foto('bom dia, tudo bem?'),
                  'PUBLICO: reconhece o pedido de foto e nao confunde com quem ja recebeu');
SELECT pg_temp.ok(nai_assunto_de_corretor('tem apartamento no Aleixo pra alugar?')
                  AND nai_assunto_de_corretor('o 5611 ainda está disponível?')
                  AND NOT nai_assunto_de_corretor('oi, preciso da segunda via do meu boleto')
                  AND NOT nai_assunto_de_corretor('bom dia, como vai a família?'),
                  'PUBLICO: separa assunto de corretor de duvida pessoal');
DO $$
DECLARE r record; k bigint;
BEGIN
  -- com a regra DESLIGADA (como esta hoje), a porta deixa todo mundo passar
  SELECT * INTO r FROM nai_deve_atender('5592911112222', 'bom dia, tudo bem?', NULL);
  PERFORM pg_temp.ok(r.atende AND r.motivo = 'regra desligada', 'PUBLICO: desligada, ninguem e barrado');

  PERFORM nai_ligar_regra_publico();

  -- NOVO: sem nenhuma mensagem antes do carimbo
  SELECT * INTO r FROM nai_deve_atender('5592911112222', 'oi, tem fotos do imóvel 5611?', NULL);
  PERFORM pg_temp.ok(r.atende AND r.motivo LIKE 'contato novo%', 'PUBLICO: contato novo falando de imovel e atendido');
  SELECT * INTO r FROM nai_deve_atender('5592911112222', 'oi, preciso da segunda via do meu boleto', NULL);
  PERFORM pg_temp.ok(NOT r.atende AND r.motivo LIKE '%nao e de corretor%', 'PUBLICO: contato novo com duvida pessoal fica sem resposta');

  -- ANTIGO: mensagem de antes do carimbo
  k := nai_contato_de('5592911113333', 'Corretor Antigo');
  INSERT INTO mensagens (telefone, nome, direcao, origem, texto, status, fluxo)
  VALUES ('5592911113333', 'Corretor Antigo', 'recebida', 'texto', 'bom dia Tel', 'Respondido', 'nay');
  UPDATE mensagens SET criada_em = now() - interval '30 days'
   WHERE telefone = '5592911113333' AND texto = 'bom dia Tel';

  SELECT * INTO r FROM nai_deve_atender('5592911113333', 'e aí, conseguiu ver aquilo?', NULL);
  PERFORM pg_temp.ok(NOT r.atende AND r.motivo LIKE 'conversa que ja existia%', 'PUBLICO: conversa antiga fica com o Tel');
  SELECT * INTO r FROM nai_deve_atender('5592911113333', 'tem fotos do imóvel?', NULL);
  PERFORM pg_temp.ok(NOT r.atende AND r.motivo LIKE '%nao da para saber o imovel%'
                     AND (SELECT liberado_em FROM nai_contato WHERE id = k) IS NULL,
                     'PUBLICO: antigo pedindo foto sem dizer o imovel continua com o Tel');
  SELECT * INTO r FROM nai_deve_atender('5592911113333', 'tem fotos do imóvel 5611?', NULL);
  PERFORM pg_temp.ok(r.atende AND r.motivo LIKE '%pediu foto%'
                     AND (SELECT liberado_em FROM nai_contato WHERE id = k) IS NOT NULL,
                     'PUBLICO: antigo pedindo foto DO IMOVEL liga a Nay naquela conversa');
  SELECT * INTO r FROM nai_deve_atender('5592911113333', 'e aí, conseguiu ver aquilo?', NULL);
  PERFORM pg_temp.ok(r.atende AND r.motivo LIKE '%liberada%', 'PUBLICO: depois de liberada, ela atende o resto da conversa');

  -- card do grupo marcado: o imovel vem do sistema, nao do texto
  SELECT * INTO r FROM nai_deve_atender('5592911114444', 'tem fotos desse?', 5611);
  PERFORM pg_temp.ok(r.atende, 'PUBLICO: contato novo marcando o card do grupo e atendido');

  PERFORM nai_desligar_regra_publico();
  SELECT * INTO r FROM nai_deve_atender('5592911113333', 'e aí?', NULL);
  PERFORM pg_temp.ok(r.atende AND r.motivo = 'regra desligada', 'PUBLICO: desligando, tudo volta a ser como hoje');
END $$;

SELECT count(*) FILTER (WHERE ok) AS passaram, count(*) FILTER (WHERE NOT ok) AS falharam FROM _r;
