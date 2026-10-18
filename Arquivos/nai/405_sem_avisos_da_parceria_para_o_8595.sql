-- 405: o número da Parceria (9445) para de mandar aviso para o 8595 (Captação)
--
-- Pedro, 17/10/2026: "o que é esse tanto de mensagem que o número de parceria manda para o de captação? ... tira esses
-- relatórios, as perguntas são feitas para o número do Tel naquele esquema novo de ordem de perguntas, pode tirar os
-- avisos de um número para o outro".
-- O 8595 entrou em 28/09 como "segundo número do Tel" (recebia tudo o que vai ao Tel). Desde 16/10 ele é também a linha
-- da Nay do WhatsApp (OLX), e os avisos (14 a 29 por dia) caíam na caixa da Captação como conversa da Parceria.
-- Aqui, o que é do banco:
--   escala_sem_parar           sai o 8595 (ficam o Pedro e o Tel)
--   aprovador_visita_telefone  fica vazio: o "Rayssa, visita confirmada..." / "pedido de visita para confirmar" não sai
--                              mais por WhatsApp. A aprovação já é feita pelo CRM (49 de 49 nos últimos 20 dias: 23 pela
--                              Rayssa, 5 pelo Tel, 21 automáticas); nai_aprovador_contato() vazio é tratado em todo lugar
--                              (nai_visita_para_a_rayssa, nai_visita_corretor_confirmou, nai_agenda_tick) e o Tel
--                              continua avisado.
-- Fica: comando_telefones (o 8595 continua mandando comando como o Tel). Fora do banco: TEL_WHATSAPP do nay-publicador
-- (relatório da agenda dos grupos, detector de visitas, alarmes, pendências) sem o 8595.
-- Antes: escala_sem_parar = Pedro, Tel, 8595; aprovador_visita_telefone = 8595.
BEGIN;
SET LOCAL lock_timeout = '3s';
UPDATE nai_config
   SET valor = array_to_string(ARRAY(SELECT btrim(x) FROM unnest(string_to_array(valor, ',')) x
                                      WHERE right(regexp_replace(x, '\D', '', 'g'), 8) <> '85956408' AND btrim(x) <> ''), ',')
 WHERE chave = 'escala_sem_parar';
UPDATE nai_config SET valor = '' WHERE chave = 'aprovador_visita_telefone' AND right(regexp_replace(valor, '\D', '', 'g'), 8) = '85956408';
COMMIT;
