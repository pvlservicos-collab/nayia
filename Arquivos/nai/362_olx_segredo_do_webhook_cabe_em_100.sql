-- 362 -- OLX: o endereço do webhook do chat tem de caber em 100 caracteres
--
-- Pedro, 13/10/2026, ao conectar a primeira conta: "Conta conectada (Telmario Araújo). Mas a OLX não ligou o
-- recebimento (HTTP 500)". A OLX respondeu, no corpo: {"error":"value too long for type character varying(100)"}.
-- O endereço que mandamos é https://crm.imobeasy.online/api/public/olx-chat/<conta>/<segredo>: 62 caracteres até a
-- barra da conta "proprietarios" + 64 do segredo (32 bytes em hexadecimal) = 126. Com o segredo de 32 caracteres
-- (122 bits de acaso, um uuid sem os traços) o endereço fica com 94.
--
-- Nenhum webhook chegou a ser registrado na OLX com o segredo antigo, então trocar não derruba nada. O CRM passa a
-- gerar o segredo novo já com 32 caracteres (src/lib/olxChat.ts, `segredoDaContaOlx`).
BEGIN;
SET LOCAL lock_timeout = '3s';

UPDATE privado.olx_conta
   SET segredo = replace(gen_random_uuid()::text, '-', ''), atualizado_em = now()
 WHERE length(segredo) > 32;

COMMIT;
