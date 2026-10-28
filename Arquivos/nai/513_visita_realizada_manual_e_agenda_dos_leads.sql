-- 513: VISITA REALIZADA À MÃO e as visitas da Nay Leads na agenda do CRM (Pedro, 28/10/2026).
-- "45335053 aqui a Nay mandou um pedido de feedback de uma visita não realizada, desativa esses pedidos automáticos,
-- eles vão acontecer quando a Rayssa marcar lá na aba Visita, clicar na visita e clicar em VISITA REALIZADA, aí ela vai
-- perguntar, ou para o cliente ou para o corretor ... e desativa o lembrete para todos no automático, agora vai ser
-- manual em todos os números, e põe as visitas do número Leads e do número de Parceria diferentes lá na agenda".
--
-- O David (5053) marcou o #3841 para 27/10 14h; às 12h a Nay Leads lembrou e às 16h perguntou "como foi?" sozinha.
-- O automático saiu do nay-olx (visita_lembrete_auto / visita_depois_auto, desligados). Aqui:
--   * privado.olx_visita ganha o estado 'realizada' e quem pediu o "como foi?" (feedback_para: cliente | corretor);
--     o nay-olx (_feedback_pedido) manda a pergunta uma vez e carimba depois_em;
--   * crm_visitas_leads: as visitas da Nay Leads no molde da agenda (a da Parceria segue na crm_visitas);
--   * crm_visita_leads_realizada: o botão da agenda.

BEGIN;
SET LOCAL lock_timeout = '5s';

ALTER TABLE privado.olx_visita DROP CONSTRAINT olx_visita_estado_check;
ALTER TABLE privado.olx_visita ADD CONSTRAINT olx_visita_estado_check CHECK (estado = ANY (ARRAY[
  'confirmar_cliente', 'buscando_corretor', 'pedindo_proprietario', 'confirmada', 'sem_corretor', 'proprietario_nao',
  'sem_proprietario', 'cancelada', 'expirada', 'realizada']));
ALTER TABLE privado.olx_visita
  ADD COLUMN feedback_para text CHECK (feedback_para IN ('cliente', 'corretor')),
  ADD COLUMN realizada_em timestamptz,
  ADD COLUMN realizada_por text;
COMMENT ON COLUMN privado.olx_visita.feedback_para IS
  '513: a quem a Nay pergunta "como foi?" depois que a equipe marcou VISITA REALIZADA na agenda do CRM (cliente | corretor).';


CREATE OR REPLACE FUNCTION public.crm_visitas_leads(p_desde date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
 RETURNS TABLE(id bigint, codigo integer, imovel text, estado text, aberta boolean, quando timestamp with time zone,
               criado_em timestamp with time zone, cliente_confirmou_em timestamp with time zone,
               confirmada_em timestamp with time zone, realizada_em timestamp with time zone, realizada_por text,
               feedback_para text, feedback_em timestamp with time zone, atualizado_em timestamp with time zone,
               corretor_nome text, corretor_telefone text, proprietario_nome text, proprietario_telefone text,
               cliente_nome text, cliente_telefone text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  -- as abertas sempre; as fechadas na janela pedida (sem janela, todas), como a crm_visitas
  SELECT o.id, o.codigo, nai_ref_imovel(o.codigo), o.estado,
         o.estado IN ('confirmar_cliente', 'buscando_corretor', 'pedindo_proprietario', 'confirmada'),
         o.quando, o.criado_em, o.cliente_confirmou_em, o.confirmada_em, o.realizada_em, o.realizada_por,
         o.feedback_para, CASE WHEN o.feedback_para IS NOT NULL THEN o.depois_em END, o.atualizado_em,
         nullif(btrim(o.corretor_nome), ''), nullif(regexp_replace(coalesce(o.corretor_telefone, ''), '\D', '', 'g'), ''),
         nullif(btrim(o.proprietario_nome), ''), nullif(regexp_replace(coalesce(o.proprietario_telefone, ''), '\D', '', 'g'), ''),
         nullif(btrim(l.nome), ''), nullif(regexp_replace(coalesce(l.telefone, ''), '\D', '', 'g'), '')
    FROM privado.olx_visita o
    LEFT JOIN privado.olx_lead_whatsapp l ON l.id = o.lead
   WHERE o.estado IN ('confirmar_cliente', 'buscando_corretor', 'pedindo_proprietario', 'confirmada')
      OR ((p_desde IS NULL OR o.quando >= p_desde::timestamptz)
          AND (p_ate IS NULL OR o.quando < (p_ate + 1)::timestamptz))
   ORDER BY o.quando DESC
   LIMIT 300
$function$;


CREATE OR REPLACE FUNCTION public.crm_visita_leads_realizada(p_visita bigint, p_para text, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v privado.olx_visita;
BEGIN
  SELECT * INTO v FROM privado.olx_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL THEN
    RETURN QUERY SELECT false, 'Não achei essa visita da Nay Leads.'; RETURN;
  END IF;
  IF p_para NOT IN ('cliente', 'corretor') THEN
    RETURN QUERY SELECT false, 'Escolha se a Nay pergunta ao cliente ou ao corretor.'; RETURN;
  END IF;
  IF v.estado = 'realizada' THEN
    RETURN QUERY SELECT false, 'Essa visita já foi marcada como realizada'
                               || coalesce(' por ' || v.realizada_por, '') || '.'; RETURN;
  END IF;
  IF v.estado <> 'confirmada' THEN
    RETURN QUERY SELECT false, 'Só a visita confirmada pode ser marcada como realizada (esta está "' || v.estado || '").'; RETURN;
  END IF;
  IF v.quando > now() THEN
    RETURN QUERY SELECT false, 'A visita ainda não aconteceu (é ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'DD/MM "às" HH24:MI') || ').'; RETURN;
  END IF;
  IF p_para = 'corretor' AND coalesce(regexp_replace(v.corretor_telefone, '\D', '', 'g'), '') = '' THEN
    RETURN QUERY SELECT false, 'Essa visita não tem o número do corretor: pergunte ao cliente.'; RETURN;
  END IF;
  -- depois_em volta a vazio: o pedido da equipe vale mesmo se o automático antigo já tinha perguntado
  UPDATE privado.olx_visita
     SET estado = 'realizada', feedback_para = p_para, realizada_em = now(),
         realizada_por = nullif(btrim(coalesce(p_quem, '')), ''), depois_em = NULL, atualizado_em = now()
   WHERE id = v.id;
  RETURN QUERY SELECT true, 'Marcada como realizada. A Nay vai perguntar ao '
                            || CASE WHEN p_para = 'cliente' THEN 'cliente' ELSE 'corretor' END
                            || ' como foi a visita (sai em até 1 minuto, pelo número Leads).';
END $function$;

REVOKE ALL ON FUNCTION public.crm_visitas_leads(date, date), public.crm_visita_leads_realizada(bigint, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_visitas_leads(date, date), public.crm_visita_leads_realizada(bigint, text, text) TO nay_disparo;

COMMIT;
