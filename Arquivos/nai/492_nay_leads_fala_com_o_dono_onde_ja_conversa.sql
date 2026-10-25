-- 492 (Pedro, 24/10): a Nay Leads fala com o proprietário pelo número em que ele JÁ conversa conosco.
--   "antes de contatar o proprietário, checar se ele tem conversa conosco em outro número e usar esse (ex.: Parceria);
--    senão criar a conversa pelo número leads; na aba Parceria a conversa com esse proprietário fica com overlay roxo e
--    a tag 'Nay olx(leads) conversando'; NUNCA mandar pelo número da API OFICIAL (se houver conversa lá, ignorar)".
--
-- - nay_leads_linha_do_dono(tel): 'parceria' se ele já escreveu para a Parceria (mensagens), senão 'captacao' (8595).
--   O oficial nunca entra.
-- - nay_leads_mandar_pela_parceria(tel, texto, nome, motivo, lead): a mensagem vai pela fila do núcleo (core_saida,
--   como o mandar.py do agente: o enviador grava o message_id e o eco não vira "o Tel escreveu"), e a conversa ganha a
--   marca privado.nay_leads_com_dono por 24 h (o CRM pinta de roxo). A Nay Parceria nunca atende dono (463).
-- - olx_visita_consulta.linha: por onde a pergunta da visita saiu; a resposta é lida na mesma linha.
-- - crm_nay_leads_com_dono(): as marcas vivas, para o CRM.
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE privado.olx_visita_consulta ADD COLUMN IF NOT EXISTS linha text NOT NULL DEFAULT 'captacao';
ALTER TABLE privado.olx_visita_consulta ADD CONSTRAINT olx_visita_consulta_linha_check CHECK (linha IN ('captacao', 'parceria'));

CREATE TABLE IF NOT EXISTS privado.nay_leads_com_dono (
  chave     text PRIMARY KEY,
  telefone  text NOT NULL,
  nome      text,
  motivo    text,
  lead      bigint,
  desde     timestamptz NOT NULL DEFAULT now(),
  ate       timestamptz NOT NULL
);
COMMENT ON TABLE privado.nay_leads_com_dono IS
  '492: a Nay Leads está conversando com este proprietário pela linha da Parceria (o CRM pinta a conversa de roxo).';

CREATE OR REPLACE FUNCTION public.nay_leads_linha_do_dono(p_tel text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE WHEN nai_chave(p_tel) IS NOT NULL
                   AND EXISTS (SELECT 1 FROM mensagens m
                                WHERE m.direcao = 'recebida' AND nai_chave(m.telefone) = nai_chave(p_tel))
                   AND EXISTS (SELECT 1 FROM nai_contato c WHERE c.chave = nai_chave(p_tel))
              THEN 'parceria' ELSE 'captacao' END
$function$;

CREATE OR REPLACE FUNCTION public.nay_leads_mandar_pela_parceria(p_tel text, p_texto text, p_nome text, p_motivo text,
                                                                 p_lead bigint, p_horas integer DEFAULT 24)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_chave text := nai_chave(p_tel);
  v_turno bigint;
  v_saida bigint;
BEGIN
  IF v_chave IS NULL OR btrim(coalesce(p_texto, '')) = ''
     OR NOT EXISTS (SELECT 1 FROM nai_contato WHERE chave = v_chave) THEN
    RETURN NULL;
  END IF;
  INSERT INTO core_turno (chave, papel, texto, estado_antes, estado_depois, modo, criado_em, fechado_em)
  VALUES (v_chave, 'agente', '[Nay Leads ao proprietário] ' || left(p_texto, 200), 'NAY_LEADS', 'NAY_LEADS',
          'nay_leads_dono', now(), now())
  RETURNING id INTO v_turno;
  INSERT INTO core_saida (turno_id, chave_destino, ordem, tipo, texto, motivo, papel_destino, estado, enviar_apos, criado_em)
  VALUES (v_turno, v_chave, 1, 'texto', p_texto, 'nay_leads_dono', 'turno', 'pendente', now(), now())
  RETURNING id INTO v_saida;
  INSERT INTO privado.nay_leads_com_dono (chave, telefone, nome, motivo, lead, desde, ate)
  VALUES (v_chave, p_tel, nullif(btrim(coalesce(p_nome, '')), ''), left(p_motivo, 200), p_lead, now(),
          now() + make_interval(hours => greatest(1, p_horas)))
  ON CONFLICT (chave) DO UPDATE SET nome = coalesce(EXCLUDED.nome, nay_leads_com_dono.nome), motivo = EXCLUDED.motivo,
                                    lead = EXCLUDED.lead, desde = now(), ate = EXCLUDED.ate;
  RETURN v_saida;
END;
$function$;

-- a conversa terminou (o dono respondeu ou a visita acabou): a marca sai
CREATE OR REPLACE FUNCTION public.nay_leads_soltar_dono(p_tel text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  UPDATE privado.nay_leads_com_dono SET ate = now() WHERE chave = nai_chave(p_tel) AND ate > now();
$function$;

CREATE OR REPLACE FUNCTION public.crm_nay_leads_com_dono()
 RETURNS TABLE(telefone text, nome text, motivo text, desde timestamp with time zone, ate timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT d.telefone, d.nome, d.motivo, d.desde, d.ate FROM privado.nay_leads_com_dono d WHERE d.ate > now()
$function$;

REVOKE ALL ON FUNCTION public.crm_nay_leads_com_dono() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_nay_leads_com_dono() TO nay_disparo;
REVOKE ALL ON FUNCTION public.nay_leads_mandar_pela_parceria(text, text, text, text, bigint, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.nay_leads_soltar_dono(text) FROM PUBLIC;

COMMIT;
