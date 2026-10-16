-- 393: a revisão do fluxo da Nay do WhatsApp (clientes da OLX e orgânicos, 92 8595-6408)
--
-- Pedro, 16/10/2026: "revisa todo fluxo dessa Nay agora que mudamos o fluxo".
--   · a MESMA pessoa em dois anúncios virava duas linhas de lead, e as duas respondiam a mesma mensagem: agora é o mesmo
--     lead (o anúncio novo passa a ser o da frente, o perfil soma; quem estava encerrado volta a ser aberto pela Nay);
--   · a visita ganha o LEMBRETE (o Cristian, dono do 9045: "pode sim, só me avisar antes") e a pergunta de DEPOIS;
--   · horário de falar com o Diego, corretor e proprietário (7h às 21h): fora dele a visita espera e anda de manhã.
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '20s';

ALTER TABLE privado.olx_visita ADD COLUMN IF NOT EXISTS lembrete_em timestamptz;
ALTER TABLE privado.olx_visita ADD COLUMN IF NOT EXISTS depois_em timestamptz;

INSERT INTO privado.olx_config (chave, valor, descricao) VALUES
  ('visita_lembrete_h', '2', '393: horas antes da visita em que a Nay lembra o cliente, quem acompanha e o proprietário'),
  ('visita_depois_h', '2', '393: horas depois da visita em que a Nay pergunta ao cliente como foi'),
  ('visita_hora_ini', '7', '393: a Nay só chama Diego, corretor e proprietário a partir desta hora (Manaus)'),
  ('visita_hora_fim', '21', '393: e até esta hora; fora dela a visita espera')
ON CONFLICT (chave) DO NOTHING;

CREATE OR REPLACE FUNCTION public.olx_nay_lead_whatsapp(p_chat bigint, p_nome text, p_telefone text, p_quer_visita boolean, p_perfil jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_fone text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  v_id   bigint;
  v_l    privado.olx_lead_whatsapp;
BEGIN
  IF v_fone LIKE '55%' AND length(v_fone) IN (12, 13) THEN v_fone := substr(v_fone, 3); END IF;
  IF length(v_fone) NOT IN (10, 11) THEN RETURN NULL; END IF;

  -- 393: a mesma pessoa já é cliente da Nay do WhatsApp (outro anúncio, ou orgânica): é o MESMO lead
  SELECT * INTO v_l FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = right(v_fone, 8) ORDER BY criado_em DESC LIMIT 1;
  IF v_l.id IS NOT NULL THEN
    UPDATE privado.olx_lead_whatsapp x
       SET chat = coalesce(p_chat, x.chat), conta = coalesce(c.conta, x.conta), list_id = coalesce(c.list_id, x.list_id),
           codigo = coalesce(a.codigo, x.codigo), negocio = coalesce(a.negocio, x.negocio),
           nome = coalesce(nullif(btrim(coalesce(p_nome, '')), ''), x.nome),
           quer_visita = x.quer_visita OR coalesce(p_quer_visita, false),
           perfil = x.perfil || coalesce(p_perfil, '{}'::jsonb),
           -- a Nay abre de novo (com a conversa toda na mão) quem não está com a equipe e não tem visita andando
           etapa = CASE WHEN x.humano_em IS NULL AND x.etapa NOT IN ('visita', 'proprietarios', 'fechamento')
                        AND p_chat IS DISTINCT FROM x.chat THEN 'nova' ELSE x.etapa END,
           assumido_em = CASE WHEN x.humano_em IS NULL AND x.etapa NOT IN ('visita', 'proprietarios', 'fechamento')
                              AND p_chat IS DISTINCT FROM x.chat THEN NULL ELSE x.assumido_em END,
           criado_em = CASE WHEN p_chat IS DISTINCT FROM x.chat THEN now() ELSE x.criado_em END,
           atualizado_em = now()
      FROM (SELECT p_chat AS id) q
      LEFT JOIN privado.olx_chat c ON c.id = q.id
      LEFT JOIN LATERAL (SELECT y.codigo, y.negocio FROM privado.olx_anuncio y WHERE y.list_id = c.list_id
                          ORDER BY y.enviado_em DESC NULLS LAST, y.id DESC LIMIT 1) a ON true
     WHERE x.id = v_l.id;
    RETURN v_l.id;
  END IF;

  INSERT INTO privado.olx_lead_whatsapp AS l (chat, conta, list_id, codigo, negocio, nome, telefone, quer_visita, perfil)
  SELECT c.id, c.conta, c.list_id, a.codigo, a.negocio, nullif(btrim(coalesce(p_nome, '')), ''), v_fone,
         coalesce(p_quer_visita, false), coalesce(p_perfil, '{}'::jsonb)
    FROM privado.olx_chat c
    LEFT JOIN LATERAL (SELECT x.codigo, x.negocio FROM privado.olx_anuncio x WHERE x.list_id = c.list_id
                        ORDER BY x.enviado_em DESC NULLS LAST, x.id DESC LIMIT 1) a ON true
   WHERE c.id = p_chat
  ON CONFLICT (chat, telefone) DO UPDATE
     SET nome = coalesce(EXCLUDED.nome, l.nome), quer_visita = l.quer_visita OR EXCLUDED.quer_visita,
         perfil = l.perfil || EXCLUDED.perfil, atualizado_em = now()
  RETURNING l.id INTO v_id;
  RETURN v_id;
END
$function$;

-- a Josy: encerrou com "obrigada" e ficou em Finalizados com a visita de amanhã (17/10 13h) confirmada
UPDATE privado.olx_lead_whatsapp l SET etapa = 'visita', etapa_em = now(), atualizado_em = now()
 WHERE l.etapa = 'finalizado'
   AND EXISTS (SELECT 1 FROM privado.olx_visita v WHERE v.lead = l.id AND v.estado = 'confirmada' AND v.quando > now());

COMMIT;
