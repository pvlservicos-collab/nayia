\pset pager off
-- a visita 1136 de novo (o ensaio desfaz): o pedido ao dono, a Rayssa, o Tel e agora o motoboy
SELECT nai_visita_para_a_rayssa(1136, (SELECT turno_id FROM nai_saida WHERE visita_id = 1136 ORDER BY id LIMIT 1)) r;
SELECT papel_destino, estado, coalesce(bloqueio, '') bloqueio, left(replace(texto, E'\n', ' | '), 220) texto
  FROM nai_saida WHERE visita_id = 1136 ORDER BY id DESC LIMIT 4;
SELECT motoboy_id IS NOT NULL tem_motoboy, ult_msg_moto_em IS NOT NULL avisado FROM nai_visita WHERE id = 1136;
