-- 177 -- a conferência da captação no CRM (Pedro, 29/09/2026: "vê erros nas
-- mensagens na captação, engoliu outra mensagem do Jeferson"). Medido: depois
-- que a aba da captação existe (28/09 15:34), 25 de 62 textos recebidos não
-- chegaram ao CRM -- o espelho do fluxo da captação (VPS2) roda DEPOIS do
-- atendimento, e qualquer erro no caminho (a OpenAI sem crédito, hoje) para a
-- execução antes dele; e CRM reiniciando perde o que chega.
-- O CRM lê o registro da captação a cada minuto e traz o que falta. A
-- captação não guarda o id das RECEBIDAS: o CRM compara pela pessoa, pelo
-- texto e pela hora.

BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION crm_captacao_mensagens(p_desde timestamptz, p_ate timestamptz DEFAULT now(), p_limite int DEFAULT 2000)
RETURNS TABLE(id bigint, telefone text, nome text, direcao text, origem text, texto text, message_id text, criada_em timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET jit = off AS $$
  SELECT m.id, regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g'), nullif(btrim(l.nome), ''),
         m.direcao, coalesce(m.origem, ''), m.texto, nullif(m.message_id, ''), m.criada_em
    FROM captacao_mensagens m
    LEFT JOIN captacao_leads l ON l.id = m.lead_id
   WHERE m.criada_em >= p_desde AND m.criada_em < coalesce(p_ate, now())
     AND coalesce(m.telefone, '') !~ '-'                                   -- grupo não
     AND length(regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g')) BETWEEN 10 AND 16
   ORDER BY m.criada_em, m.id
   LIMIT greatest(1, least(coalesce(p_limite, 2000), 5000))
$$;

REVOKE ALL ON FUNCTION crm_captacao_mensagens(timestamptz, timestamptz, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_captacao_mensagens(timestamptz, timestamptz, int) TO nay_disparo;

COMMIT;
