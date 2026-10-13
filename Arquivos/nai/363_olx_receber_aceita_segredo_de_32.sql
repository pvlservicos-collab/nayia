-- 363 -- OLX: quem recebe a mensagem do chat aceita o segredo de 32 caracteres (o da 362)
--
-- A 362 encurtou o segredo do webhook para o endereço caber nos 100 caracteres da OLX, e a OLX ativou a integração
-- (HTTP 201, 13/10/2026 17:47). Mas `crm_olx_chat_receber` recusava todo segredo com menos de 40 caracteres: a
-- mensagem do cliente chegaria e levaria 401. O piso passa para 24; a comparação com o segredo guardado continua igual.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE FUNCTION pg_temp.remendar(p_fn regprocedure, p_de text, p_para text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v text := pg_get_functiondef(p_fn); n int;
BEGIN
  n := (length(v) - length(replace(v, p_de, ''))) / length(p_de);
  IF n <> 1 THEN RAISE EXCEPTION 'remendo em %: o trecho aparece % vez(es), esperava 1: %', p_fn, n, left(p_de, 60); END IF;
  EXECUTE replace(v, p_de, p_para);
END $$;

SELECT pg_temp.remendar('crm_olx_chat_receber(text,text,jsonb,text)',
$de$length(p_segredo) < 40$de$,
$para$length(p_segredo) < 24$para$);

COMMIT;
