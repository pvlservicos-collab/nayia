-- 453 -- O Diego Soares (92 98209-2845) passa a ser o motoboy que a Nay avisa nas visitas; o André sai
--
-- Pedro, 21/10/2026: "esse é o contato do motoboy que a nay precisa comunicar 92 9 8209-2845". O número já estava na
-- equipe como corretor_interno (392). Perguntado (um telefone tem um papel só na equipe), escolheu: "Diego vira o motoboy
-- e o André sai".
--
-- Quem recebe o aviso de motoboy é nai_motoboy(): o acompanhante ATIVO da equipe (443). Depois desta, só o Diego.
-- O que não muda: a visita de LOCAÇÃO da Nay do WhatsApp da OLX continua chamando o Diego primeiro, pela chave própria
-- privado.olx_config.visita_locacao (392), que não lê o papel da equipe; e a Nay nova continua sem atender o Diego
-- (equipe ou acompanhante, os dois ficam fora do atendimento). O André fica na tabela, desativado.
BEGIN;
SET LOCAL lock_timeout = '3s';

UPDATE equipe SET papel = 'acompanhante', ativo = true WHERE telefone = '5592982092845';
UPDATE equipe SET ativo = false WHERE papel = 'acompanhante' AND telefone <> '5592982092845';

COMMIT;
