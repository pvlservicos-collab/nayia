-- 290 (05/10/2026, Pedro): "quero um histórico de atendimento no card dentro do chat do CRM
-- Parceria, uma filinha para eu saber quando é a Nay atendendo, ou o Tel entra e digita
-- mensagem ... várias tags em uma fila ... que não gaste muito dos nossos recursos".
--
-- O CRM sabe quem mandou o que saiu PELO CRM (a conta de cada um: Tel, Rayssa). O resto
-- chega como eco da Z-API, sem autor: pode ser a Nay, o publicador ou alguém digitando no
-- celular do número da Nay. Quem sabe separar é o banco da Nay, pelo id da mensagem -- a
-- mesma conta de `nai_tel_assumiu`:
--   core_saida (a Nay nova, desde 02/10), nai_saida e mensagem_saida (a Nay antiga) -> 'nay'
--   envios e envios_foto (publicador) e saida_do_sistema (envio pela API)         -> 'sistema'
--   nenhuma delas                                                                   -> 'gente'
--
-- Só leitura, por id (todas as tabelas têm índice em message_id). O CRM lê o banco da Nay
-- pelo papel nay_disparo, que só enxerga funções: por isso SECURITY DEFINER.
BEGIN;

CREATE OR REPLACE FUNCTION public.crm_quem_mandou(p_ids text[])
 RETURNS TABLE(message_id text, origem text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT x.id,
         CASE
           WHEN EXISTS (SELECT 1 FROM core_saida s WHERE s.message_id = x.id)
             OR EXISTS (SELECT 1 FROM nai_saida s WHERE s.message_id = x.id)
             OR EXISTS (SELECT 1 FROM mensagem_saida s WHERE s.message_id = x.id) THEN 'nay'
           WHEN EXISTS (SELECT 1 FROM envios e WHERE e.message_id = x.id)
             OR EXISTS (SELECT 1 FROM envios_foto f WHERE f.message_id = x.id)
             OR EXISTS (SELECT 1 FROM saida_do_sistema o WHERE o.message_id = x.id) THEN 'sistema'
           ELSE 'gente'
         END
    FROM (SELECT DISTINCT u.id FROM unnest(p_ids) AS u(id) WHERE nullif(btrim(u.id), '') IS NOT NULL) x
   LIMIT 1000
$function$;

REVOKE ALL ON FUNCTION public.crm_quem_mandou(text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_quem_mandou(text[]) TO nay_disparo;

COMMIT;
