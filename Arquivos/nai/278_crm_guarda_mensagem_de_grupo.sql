-- 278 (03/10/2026): QUEM GUARDA AS MENSAGENS DOS GRUPOS É O CRM.
--
-- A 277 previa ligar a guarda (nai_grupo_guardar) no fluxo do n8n, de madrugada. Não precisa: o nó
-- "Espelhar no CRM" do fluxo principal já manda ao CRM uma cópia de TUDO o que chega pela Z-API, inclusive
-- as mensagens de grupo, que o CRM até hoje ignorava. O webhook do CRM (/api/webhooks/zapi) passa a chamar
-- nai_grupo_guardar para as mensagens de grupo da instância da Parceria. Nada muda no n8n.
BEGIN;
GRANT EXECUTE ON FUNCTION public.nai_grupo_guardar(jsonb) TO nay_disparo;
COMMIT;
