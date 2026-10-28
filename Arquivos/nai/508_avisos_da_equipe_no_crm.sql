-- 508: OS AVISOS À EQUIPE SAEM DO GRUPO E VÃO ÀS NOTIFICAÇÕES DO CRM (Pedro, 28/10/2026, depois da lista das 156
-- mensagens de 27/10 no grupo Altarquia: "as filas de dúvidas, e as mensagens de escala põe no painel notificações do
-- crm, deixa só as visitas e lembretes de visitas no grupo; o relatório da IA põe nas notificações do CRM também").
--
-- No grupo ficam: o quadro da visita agendada, a visita confirmada e o lembrete de 1 h (nay-olx/visitas_parceria.py e
-- visita.py). O resto passa por nay_aviso_equipe() e mora em privado.aviso_equipe; o CRM (cron espelho-nay) lê com
-- crm_avisos_da_equipe() e grava uma notificação para cada pessoa da equipe (Tel, Rayssa).
--   - Nay nova (nay-core): a escalada com papel 'grupo' em core_saida. O gatilho daqui a desvia: a linha fica
--     gravada como 'bloqueado' (o enviador não manda) e o aviso vai ao CRM. Sem deploy do nay-core.
--   - Nay de captação (nay-captacao/atender.py), Nay do WhatsApp da OLX (nay-olx) e os agentes do servidor 2
--     (dúvida sem resposta, áudio de dono, relatório das 22h): chamam nay_aviso_equipe().
BEGIN;
SET LOCAL lock_timeout = '5s';        -- o CREATE TRIGGER trava a core_saida: se a Nay estiver gravando, desiste
SET LOCAL statement_timeout = '20s';

CREATE TABLE IF NOT EXISTS privado.aviso_equipe (
  id        bigserial PRIMARY KEY,
  fonte     text NOT NULL,                 -- nay-core, nay-captacao, nay-olx, agente
  tipo      text NOT NULL CHECK (tipo IN ('escalada', 'duvida', 'midia', 'relatorio', 'lead', 'outro')),
  titulo    text NOT NULL,
  texto     text NOT NULL,
  telefone  text,                          -- só dígitos: o CRM abre a conversa por ele
  criado_em timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE privado.aviso_equipe IS
  '508 (28/10): o aviso à equipe que não é de visita; o CRM leva às Notificações (crm_avisos_da_equipe).';

CREATE OR REPLACE FUNCTION public.nay_aviso_equipe(p_fonte text, p_tipo text, p_titulo text, p_texto text,
                                                   p_telefone text DEFAULT NULL)
RETURNS bigint
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, privado
AS $$
  INSERT INTO privado.aviso_equipe (fonte, tipo, titulo, texto, telefone)
  VALUES (left(coalesce(nullif(btrim(p_fonte), ''), 'desconhecida'), 40),
          CASE WHEN p_tipo IN ('escalada', 'duvida', 'midia', 'relatorio', 'lead', 'outro') THEN p_tipo ELSE 'outro' END,
          left(coalesce(nullif(btrim(p_titulo), ''), 'Aviso da Nay'), 200),
          left(coalesce(nullif(btrim(p_texto), ''), coalesce(nullif(btrim(p_titulo), ''), 'Aviso da Nay')), 20000),
          nullif(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), ''))
  RETURNING id
$$;
REVOKE ALL ON FUNCTION public.nay_aviso_equipe(text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nay_aviso_equipe(text, text, text, text, text) TO nay, nay_core;

-- o CRM lê o que veio depois do último que ele já levou (o id fica no metadata da notificação)
CREATE OR REPLACE FUNCTION public.crm_avisos_da_equipe(p_depois bigint)
RETURNS TABLE (id bigint, fonte text, tipo text, titulo text, texto text, telefone text, criado_em timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, privado
AS $$
  SELECT a.id, a.fonte, a.tipo, a.titulo, a.texto, a.telefone, a.criado_em
    FROM privado.aviso_equipe a
   WHERE a.id > coalesce(p_depois, 0)
   ORDER BY a.id
   LIMIT 200
$$;
REVOKE ALL ON FUNCTION public.crm_avisos_da_equipe(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_avisos_da_equipe(bigint) TO nay, nay_disparo;

-- a escalada da Nay nova: "Corretor Kellen (559282717655) na Parceria precisa de uma pessoa da equipe: ..."
CREATE OR REPLACE FUNCTION public.core_saida_grupo_no_crm()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, privado
AS $$
DECLARE
  v_quem text;
BEGIN
  IF NEW.papel_destino = 'grupo' AND NEW.estado = 'pendente' AND NEW.tipo = 'texto' THEN
    v_quem := substring(NEW.texto from '^(.{1,80}?) \(\d{10,15}\)');
    PERFORM nay_aviso_equipe('nay-core', 'escalada',
                             coalesce(v_quem || ' precisa da equipe (Parceria)', 'Nay Parceria: precisa da equipe'),
                             NEW.texto, substring(NEW.texto from '\((\d{10,15})\)'));
    NEW.estado   := 'bloqueado';
    NEW.bloqueio := 'aviso à equipe: foi às Notificações do CRM (508)';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS core_saida_zzzz_grupo_no_crm ON public.core_saida;
CREATE TRIGGER core_saida_zzzz_grupo_no_crm BEFORE INSERT ON public.core_saida
  FOR EACH ROW EXECUTE FUNCTION public.core_saida_grupo_no_crm();

COMMIT;
