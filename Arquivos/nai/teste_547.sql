-- 547 (dentro do ensaio: tudo volta no ROLLBACK)
-- 1. o aviso de mídia bloqueado vai ao CRM
WITH t AS (INSERT INTO core_turno (chave, papel, texto, modo) VALUES ('559284486938', 'corretor', '[imagem] teste 547', 'teste') RETURNING id)
INSERT INTO core_saida (turno_id, chave_destino, ordem, tipo, texto, motivo, papel_destino, estado)
SELECT id, '5592999999999', 1, 'texto',
       'Tel, o corretor Thiago (559284486938) mandou 1 imagem(ns) nessa conversa (imóvel da conversa: 2944). Links: http://x',
       'aviso_tel', 'tel', 'pendente' FROM t;
SELECT '1 mídia' AS caso, s.estado, s.bloqueio, a.tipo, a.titulo
  FROM core_saida s LEFT JOIN privado.aviso_equipe a ON a.criado_em = now() AND a.tipo = 'midia'
 WHERE s.id = (SELECT max(id) FROM core_saida);

-- 2. a escalada do Gaspar como se tivesse sido há 45 min, com o "?" e o "Vou precisar da localização!" depois
UPDATE nai_contato SET humano_assumiu_em = now() - interval '45 minutes',
       humano_motivo = 'duvida fora da base (nay-core): assunto geral' WHERE chave = '559284298345';
INSERT INTO mensagens (telefone, direcao, texto, criada_em) VALUES
  ('559284298345', 'recebida', 'Ok', now() - interval '44 minutes'),
  ('559284298345', 'recebida', 'Vou precisar da localização!', now() - interval '10 minutes');
SELECT '2 cobrança (1a)' AS caso, nay_cobrar_escaladas() AS cobradas;
SELECT '2 o texto' AS caso, titulo, texto FROM privado.aviso_equipe WHERE fonte = 'nay-core-cobranca' AND criado_em = now();
SELECT '2 de novo logo depois: nada' AS caso, nay_cobrar_escaladas() AS cobradas;
SELECT '2 prazo' AS caso, nai_cfg('escalacao_expira_horas') AS horas;

-- 3. a promessa do agente abre a dúvida
WITH t AS (INSERT INTO core_turno (chave, papel, texto, modo) VALUES ('559284366529', 'agente', '[correção] teste 547', 'teste') RETURNING id)
INSERT INTO core_saida (turno_id, chave_destino, ordem, tipo, texto, motivo, papel_destino, estado)
SELECT id, '559284366529', 1, 'texto',
       'Luiz, vou levar a sua proposta de R$ 2.000 no Conquista Torquato (código 9047) ao proprietário e já te respondo por aqui.',
       'correcao_do_agente', 'turno', 'simulado' FROM t;
SELECT '3 dúvida aberta' AS caso, p.chave, p.codigo, p.faltou, left(p.pergunta, 90) FROM core_pendencia p WHERE p.criado_em = now();
-- e a correção que não promete nada não abre
WITH t AS (INSERT INTO core_turno (chave, papel, texto, modo) VALUES ('559284366529', 'agente', '[correção] teste 547 b', 'teste') RETURNING id)
INSERT INTO core_saida (turno_id, chave_destino, ordem, tipo, texto, motivo, papel_destino, estado)
SELECT id, '559284366529', 1, 'texto', 'Luiz, o 5756 fica no Parque 10 e custa R$ 430 mil.', 'correcao_do_agente', 'turno', 'simulado' FROM t;
SELECT '3 sem promessa: continua 1' AS caso, count(*) FROM core_pendencia p WHERE p.criado_em = now();
