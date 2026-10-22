-- teste da 468
\echo '--- o sim do dono (t = sim claro)'
SELECT x AS resposta, nai_dono_disse_sim(x) FROM unnest(ARRAY['Pode sim', 'ok', 'Tudo bem, pode vir', 'Confirmado!',
  'Imóvel renovou o contrato', 'pode, mas só às 17h', 'não posso', 'sim, quem vai?', 'Pode ser amanhã?', 'Sim às 16:00',
  'Bom dia', '1 ano novamente 🙏🏽']) x;
\echo '--- a #1156 com o dono dizendo "Pode sim": o gatilho avisa o acompanhante, a Rayssa e o Tel'
UPDATE nai_visita SET prop_ok_em = NULL, quando = now() + interval '1 day' WHERE id = 1156;
DELETE FROM nai_visita_evento WHERE visita_id = 1156 AND tipo = 'motoboy_avisado';
INSERT INTO nai_turno (contato_id, papel, visita_id, texto)
  SELECT proprietario_id, 'proprietario', id, 'Pode sim' FROM nai_visita WHERE id = 1156;
SELECT prop_ok_em IS NOT NULL AS dono_ok FROM nai_visita WHERE id = 1156;
SELECT s.papel_destino, s.estado, left(s.texto, 110) AS texto FROM nai_saida s
 WHERE s.visita_id = 1156 AND s.criado_em >= now() - interval '1 second' ORDER BY s.id;
SELECT tipo, detalhe FROM nai_visita_evento WHERE visita_id = 1156 AND quando >= now() - interval '1 second' ORDER BY id;
\echo '--- o botão do CRM numa visita já avisada não manda de novo'
SELECT * FROM crm_visita_proprietario_ok(1156, 'ensaio');
