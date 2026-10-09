-- 319 -- O espelho da captação no CRM não copia a conversa do NÚMERO OFICIAL para a aba da Z-API
--
-- Pedro, 08/10/2026, ao ligar o disparo do modelo: "lembra de ver se a nay captação vai atender e mostrar a
-- conversa lá no crm certinho".
--
-- O que estava errado: a conversa pelo número oficial (8456-0874) já entra no CRM pela aba WhatsApp Oficial -- quem
-- manda grava (`registrarEnvioNoCrm`) e o que chega vem do webhook da Meta. Só que a conferência de minuto em minuto
-- (`conferirACaptacao`, que lê esta função) trazia TUDO de `captacao_mensagens` para a linha "WhatsApp Captação
-- (Z-API)". Resultado: a mesma conversa nascia de novo na aba Captação, como se tivesse acontecido no número antigo
-- (8595-6408), e uma resposta da equipe por lá sairia pelo número antigo -- para quem acabou de ler "este é o novo
-- número da Imob Easy".
--
-- A regra: mensagem de lead cujo canal é o oficial, ou enviada com id da Meta (wamid.), não vai ao espelho da Z-API.
-- O resto (quem conversa pela Z-API) continua igual.
BEGIN;

DO $mig$
DECLARE
  v_def   text := pg_get_functiondef('public.crm_captacao_mensagens(timestamptz, timestamptz, integer)'::regprocedure);
  v_velho text := $v$     AND length(regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g')) BETWEEN 10 AND 16$v$;
  v_novo  text := $n$     AND length(regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g')) BETWEEN 10 AND 16
     -- 319: o número oficial já está na aba Oficial do CRM; aqui ele viraria conversa repetida na aba da Z-API
     AND NOT (coalesce(l.canal, 'zapi') = 'oficial' OR coalesce(m.message_id, '') LIKE 'wamid.%')$n$;
BEGIN
  IF (length(v_def) - length(replace(v_def, v_velho, ''))) / length(v_velho) <> 1 THEN
    RAISE EXCEPTION '319: o trecho de crm_captacao_mensagens mudou no banco; leia a função viva antes';
  END IF;
  IF position('319:' IN v_def) > 0 THEN
    RAISE EXCEPTION '319: já aplicada';
  END IF;
  EXECUTE replace(v_def, v_velho, v_novo);
END
$mig$;

COMMIT;
