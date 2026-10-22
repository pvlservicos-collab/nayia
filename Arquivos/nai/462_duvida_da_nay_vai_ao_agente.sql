-- 462: a dúvida da Nay Parceria vai ao agente de revisão no painel, não mais ao PV do Tel (Pedro, 22/10/2026):
-- "quando ela tiver dúvida, ao invés dela enviar para o Tel ela vai enviar lá no agentes.imobeasy para o agente de
-- correção dela, Nay Parceria (revisão)", com o prompt "A Nay não soube responder, veja a dúvida dela e responda lá
-- para o cliente e depois reative ela, depois veja porque ela teve essa dúvida e ajuste para não ter mais lá, caso
-- realmente não tenha aí você manda só a dúvida no grupo", o número de quem perguntou e a dúvida.
--
-- O caminho de antes (391): core_pendencia (a Nay nova) -> gatilho pergunta_fila_da_pendencia -> pergunta_fila -> o PV
-- do Tel, uma por vez. Agora, com nai_config.duvida_vai_ao_agente = sim, o gatilho NÃO põe a dúvida da Parceria na
-- fila do Tel; quem a lê é o painel dos agentes (agente-claude/rotinas.py, de minuto em minuto, pelo id da
-- core_pendencia). O "perguntar" da Nay do WhatsApp de captação (nay-olx) continua indo ao Tel: não foi pedido.
-- Desligar (volta ao PV do Tel): UPDATE nai_config SET valor = 'nao' WHERE chave = 'duvida_vai_ao_agente'.

BEGIN;

INSERT INTO nai_config (chave, valor) VALUES ('duvida_vai_ao_agente', 'sim')
ON CONFLICT (chave) DO UPDATE SET valor = 'sim', atualizado_em = now();

CREATE OR REPLACE FUNCTION public.pergunta_fila_da_pendencia()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- 462: a dúvida da Parceria vai ao agente de revisão (painel dos agentes), não ao PV do Tel
  IF coalesce(nai_cfg('duvida_vai_ao_agente', 'nao'), 'nao') = 'sim' THEN
    RETURN NEW;
  END IF;
  IF pergunta_fila_ligada() THEN
    PERFORM pergunta_fila_entrar('parceria', NEW.chave, NULL, NEW.codigo, NULL, NEW.pergunta, 'core_pendencia', NEW.id,
                                 array_to_string(array_remove(NEW.faltou, 'assunto nao reconhecido'), ', '));
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'pergunta_fila_da_pendencia: %', SQLERRM;     -- a Nay nova nunca cai por causa da fila
  RETURN NEW;
END
$function$;

COMMIT;
