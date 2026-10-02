-- 259 (01/10/2026): SAI A PRIMEIRA VERSÃO DA CONSULTA DO BOT.
-- A 258 nasceu recebendo texto solto (crm_imovel_do_anuncio(text)) e chegou a
-- ser aplicada assim; minutos depois o bot mandou o contrato dele, em campos, e
-- a 258 foi reescrita como crm_imovel_candidatos(jsonb). A função de texto ficou
-- no banco sem ninguém chamar. Função SECURITY DEFINER sem dono é a que alguém
-- acha daqui a um mês e não sabe se pode mexer: sai agora.
BEGIN;
SET LOCAL lock_timeout = '3s';
DROP FUNCTION IF EXISTS public.crm_imovel_do_anuncio(text);
COMMIT;
