-- 572 (Pedro, 03/11/2026: "liga a mesma Nay que atende OLX pedindo zap aí, puxando o telefone e já entrando em contato pelo
-- número Leads"). O lead do Grupo ZAP (ZAP Imóveis, Viva Real, OLX pelo Canal Pro; 542, privado.zap_lead) vira cliente da
-- Nay do WhatsApp do 8595, como o do Chaves na Mão (554): origem 'zap' em privado.olx_lead_whatsapp, e ela abre a conversa
-- dizendo que recebeu o contato pelo portal. Desliga com privado.zap_config.nay_atende <> 'sim'.
-- QUEM CHAMA: com a chave da homologação gravada (zap_config.lead_segredo), só o lead AUTENTICADO. Em 03/11 a chave ainda
-- não veio (todo lead chega autenticado = false): até ela chegar, a Nay atende o sem chave também, menos o lead de teste
-- deles ("Nome Consumidor", telefone 999999999 ou de dígito repetido).
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE privado.olx_lead_whatsapp DROP CONSTRAINT olx_lead_whatsapp_origem_check;
ALTER TABLE privado.olx_lead_whatsapp ADD CONSTRAINT olx_lead_whatsapp_origem_check
  CHECK (origem = ANY (ARRAY['olx', 'organico', 'manual', 'chavesnamao', 'zap']));
COMMENT ON COLUMN privado.olx_lead_whatsapp.origem IS
  'olx (deu o número no chat da OLX) · organico (escreveu direto) · manual (aberto pelo CRM) · chavesnamao (554: lead do '
  'portal Chaves na Mão) · zap (572: lead do Grupo ZAP pelo Canal Pro)';

INSERT INTO privado.zap_config (chave, valor) VALUES ('nay_atende', 'sim')
ON CONFLICT (chave) DO UPDATE SET valor = 'sim';

CREATE OR REPLACE FUNCTION public.zap_lead_para_a_nay(p_id text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  z      privado.zap_lead;
  v_fone text;
  v_neg  text;
  v_l    privado.olx_lead_whatsapp;
  v_id   bigint;
BEGIN
  IF coalesce((SELECT lower(btrim(valor)) FROM privado.zap_config WHERE chave = 'nay_atende'), 'nao') <> 'sim' THEN
    RETURN NULL;
  END IF;
  SELECT * INTO z FROM privado.zap_lead WHERE id = p_id;
  IF z.id IS NULL THEN RETURN NULL; END IF;
  v_fone := regexp_replace(coalesce(z.telefone, ''), '\D', '', 'g');
  IF NOT z.autenticado THEN
    -- com a chave gravada, o sem chave não chama ninguém; sem ela (antes da homologação), só o lead de teste fica de fora
    IF nullif(btrim((SELECT valor FROM privado.zap_config WHERE chave = 'lead_segredo')), '') IS NOT NULL
       OR coalesce(z.nome, '') ~* '^nome consumidor' OR right(v_fone, 9) ~ '^(\d)\1{8}$' THEN
      RETURN NULL;
    END IF;
  END IF;

  IF v_fone LIKE '55%' AND length(v_fone) IN (12, 13) THEN v_fone := substr(v_fone, 3); END IF;
  IF length(v_fone) NOT IN (10, 11) THEN RETURN NULL; END IF;

  -- a finalidade: o que o portal disse (SELL / RENT); senão, o imóvel (só venda ou só aluguel)
  v_neg := CASE
    WHEN coalesce(z.transacao, '') ~* '(rent|loca|alug)' THEN 'locacao'
    WHEN coalesce(z.transacao, '') ~* '(sell|sale|vend|compr)' THEN 'venda'
    ELSE (SELECT CASE WHEN coalesce(i.valor_venda, 0) > 0 AND coalesce(i.valor_aluguel, 0) = 0 THEN 'venda'
                      WHEN coalesce(i.valor_aluguel, 0) > 0 AND coalesce(i.valor_venda, 0) = 0 THEN 'locacao' END
            FROM imoveis i WHERE i.codigo = z.codigo)
  END;

  -- a mesma pessoa já é cliente da Nay do WhatsApp: é o MESMO lead (a regra da 393, como no Chaves na Mão)
  SELECT * INTO v_l FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = right(v_fone, 8) ORDER BY criado_em DESC LIMIT 1;
  IF v_l.id IS NOT NULL THEN
    UPDATE privado.olx_lead_whatsapp x
       SET codigo = coalesce(z.codigo, x.codigo), negocio = coalesce(v_neg, x.negocio),
           nome = coalesce(x.nome, z.nome),
           origem = CASE WHEN x.origem IN ('organico', 'manual') THEN 'zap' ELSE x.origem END,
           etapa = CASE WHEN x.humano_em IS NULL AND x.etapa NOT IN ('visita', 'proprietarios', 'fechamento')
                        AND z.codigo IS DISTINCT FROM x.codigo THEN 'nova' ELSE x.etapa END,
           assumido_em = CASE WHEN x.humano_em IS NULL AND x.etapa NOT IN ('visita', 'proprietarios', 'fechamento')
                              AND z.codigo IS DISTINCT FROM x.codigo THEN NULL ELSE x.assumido_em END,
           criado_em = CASE WHEN z.codigo IS DISTINCT FROM x.codigo THEN now() ELSE x.criado_em END,
           atualizado_em = now()
     WHERE x.id = v_l.id;
    RETURN v_l.id;
  END IF;

  INSERT INTO privado.olx_lead_whatsapp (chat, telefone, origem, codigo, negocio, nome, perfil)
  VALUES (NULL, v_fone, 'zap', z.codigo, v_neg, z.nome, '{"procura": "deixou o contato no portal (Grupo ZAP)"}'::jsonb)
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;

-- zap_lead_receber: o lead NOVO e autenticado vai à Nay (o resto da função é o que está no banco hoje)
CREATE OR REPLACE FUNCTION public.zap_lead_receber(p jsonb, p_segredo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_chave text := nullif(btrim((SELECT valor FROM zap_config WHERE chave = 'lead_segredo')), '');
  v_id    text := nullif(btrim(p->>'originLeadId'), '');
  v_orig  text := nullif(btrim(p->>'leadOrigin'), '');
  v_cod   integer;
  v_novo  boolean;
BEGIN
  IF jsonb_typeof(p) IS DISTINCT FROM 'object' OR v_id IS NULL THEN
    RETURN jsonb_build_object('status', 'invalido', 'erro', 'falta o originLeadId');
  END IF;
  -- com a chave guardada, só passa quem a manda; sem ela (antes da homologação), entra marcado como não autenticado
  IF v_chave IS NOT NULL AND coalesce(p_segredo, '') <> v_chave THEN
    RETURN jsonb_build_object('status', 'negado');
  END IF;
  -- lead de anúncio sem o nosso código: 4xx para eles revisarem e reenviarem (a regra do Grupo OLX); MCMV não tem
  IF coalesce(v_orig, '') <> 'MCMV_OLX' AND nullif(btrim(p->>'clientListingId'), '') IS NULL THEN
    RETURN jsonb_build_object('status', 'invalido', 'erro', 'falta o clientListingId');
  END IF;
  v_cod := CASE WHEN btrim(p->>'clientListingId') ~ '^[0-9]{1,9}$' THEN (p->>'clientListingId')::integer END;

  INSERT INTO zap_lead (id, origem, criado_em, codigo, anuncio_zap, nome, email, telefone, mensagem, temperatura,
                        transacao, canal, autenticado, dados)
  VALUES (v_id, v_orig,
          CASE WHEN (p->>'timestamp') ~ '^\d{4}-\d{2}-\d{2}' THEN (p->>'timestamp')::timestamptz END,
          v_cod, nullif(p->>'originListingId', ''), nullif(btrim(p->>'name'), ''), nullif(btrim(p->>'email'), ''),
          nullif(regexp_replace(coalesce(p->>'ddd', '') || coalesce(p->>'phone', ''), '\D', '', 'g'), ''),
          p->>'message', p->>'temperature', p->>'transactionType', p#>>'{extraData,leadType}',
          v_chave IS NOT NULL, p)
  ON CONFLICT (id) DO UPDATE SET vezes = zap_lead.vezes + 1
  RETURNING (xmax = 0) INTO v_novo;
  -- 572: o lead novo vai à Nay do 8595; falhar aqui não derruba o recebimento (o portal não reenviaria)
  IF v_novo THEN
    BEGIN
      PERFORM zap_lead_para_a_nay(v_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'zap_lead_para_a_nay(%): %', v_id, SQLERRM;
    END;
  END IF;
  RETURN jsonb_build_object('status', CASE WHEN v_novo THEN 'novo' ELSE 'repetido' END, 'id', v_id);
END
$function$;
COMMIT;
