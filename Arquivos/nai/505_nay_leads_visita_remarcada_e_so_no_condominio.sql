-- 505 (27/10/2026, Pedro, erros da Nay Leads): só dados, sem função.
-- 1) O Sr. Eduardo (lead 59) remarcou o #5699 de segunda 26/10 17h30 (visita 11) para sábado 31/10 10h (visita 12);
--    a 11 ficou 'confirmada' e mandou o lembrete e o "como foi?". Fica cancelada (o código novo já faz isso sozinho e
--    relê a visita antes de cada lembrete: nay-olx visita.ainda_vale).
-- 2) O Sr. Karis (lead 60, busca 52) quer SÓ no Ponta Negra Village: o modelo marcou so_condominio sem o nome e a
--    busca saiu como "Ponta Negra". O nome entra no lead e na busca (o pedido aos grupos sai "só no Ponta Negra Village").
BEGIN;

UPDATE privado.olx_visita SET estado = 'cancelada', atualizado_em = now()
 WHERE id = 11 AND lead = 59 AND estado = 'confirmada';

UPDATE privado.olx_lead_whatsapp SET filtros = filtros || '{"condominio": "Ponta Negra Village", "so_condominio": true}'::jsonb
 WHERE id = 60 AND coalesce(filtros->>'condominio', '') = '';

UPDATE privado.busca_cliente
   SET filtros = filtros || '{"condominio": "Ponta Negra Village", "so_condominio": true}'::jsonb, atualizado_em = now()
 WHERE id = 52 AND lead = 60 AND coalesce(filtros->>'condominio', '') = '';

INSERT INTO privado.busca_cliente_passo (busca, lugar, texto)
SELECT 52, 'perfil', 'Perfil atualizado (Pedro, 27/10): só no Ponta Negra Village'
 WHERE EXISTS (SELECT 1 FROM privado.busca_cliente WHERE id = 52 AND filtros->>'condominio' = 'Ponta Negra Village');

COMMIT;
