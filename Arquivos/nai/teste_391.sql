-- 391: a fila que entrou, a primeira pergunta ao Tel, a resposta dele (que vai ao cliente) e a próxima
SELECT id, linha, estado, right(chave, 4) AS fim, codigo, left(imovel, 25) AS imovel, left(regexp_replace(pergunta, '\s+', ' ', 'g'), 60) AS pergunta
  FROM pergunta_fila ORDER BY ordem, id;
SELECT * FROM pergunta_fila_posicao();
-- os remendos
SELECT 'abrir_turno' AS fn, position('pergunta_fila_resposta_valida' IN pg_get_functiondef('nai_abrir_turno(text,text,text,text,bigint[])'::regprocedure)) > 0 AS ok
UNION ALL SELECT 'comando_tel', position('pergunta_fila_responder' IN pg_get_functiondef('nai_comando_tel(bigint,text)'::regprocedure)) > 0
UNION ALL SELECT 'agenda_tick', position('pergunta_fila_tick' IN pg_get_functiondef('nai_agenda_tick()'::regprocedure)) > 0;
-- o relógio manda a primeira
SELECT pergunta_fila_tick() AS mandou;
SELECT s.motivo, s.estado, s.texto FROM nai_saida s WHERE s.motivo LIKE 'pergunta_fila%' ORDER BY s.id DESC LIMIT 1;
-- o Tel escreve: o que é e o que não é resposta
SELECT x.t, pergunta_fila_resposta_valida((SELECT id FROM nai_contato WHERE chave = nai_chave(nai_cfg('tel_telefone'))), x.t) AS e_resposta
  FROM (VALUES ('Bom dia'), ('ok'), ('VISITAS'), ('DEVOLVER 92991234567 sim'), ('posta o 3050'), ('Aceita sim, pet pequeno'),
               ('PULAR'), ('resposta 81 sim')) x(t);
-- a resposta de verdade, por um turno do Tel (desfeito no ROLLBACK)
WITH t AS (INSERT INTO nai_turno (contato_id, papel, texto, msg_ids)
           SELECT id, 'tel', 'É de fibra, com aquecimento solar.', '{}' FROM nai_contato WHERE chave = nai_chave(nai_cfg('tel_telefone'))
           RETURNING id)
SELECT (SELECT msg_tel FROM nai_comando_tel(t.id, 'É de fibra, com aquecimento solar.')) AS ao_tel FROM t;
SELECT id, estado, resposta, entregue_em IS NOT NULL AS entregue, entrega_erro FROM pergunta_fila WHERE estado <> 'fila' ORDER BY id;
SELECT s.papel_destino, s.motivo, right(c.chave, 4) AS para, left(s.texto, 160) AS texto
  FROM nai_saida s JOIN nai_contato c ON c.id = s.contato_id
 WHERE s.id > (SELECT max(id) - 10 FROM nai_saida) AND (s.motivo LIKE 'pergunta_fila%' OR s.motivo = 'resposta_do_tel')
 ORDER BY s.id;
SELECT codigo, assunto, texto, quem_contou FROM imovel_conhecimento WHERE quem_contou LIKE 'tel (fila%';
-- o aviso solto da Nay nova é bloqueado
INSERT INTO core_saida (turno_id, chave_destino, papel_destino, ordem, tipo, texto, motivo, enviar_apos, estado)
SELECT (SELECT max(id) FROM core_turno), '559294717316', 'tel', 9, 'texto',
       'Tel, o corretor X (92 9999-9999) perguntou sobre o 3050: "tem pet?". Não achei na ficha. Continuo atendendo esse chat. Para eu entregar a resposta a ele: DEVOLVER 92999999999 [resposta]',
       'aviso_tel', now(), 'pendente'
RETURNING estado, bloqueio;
