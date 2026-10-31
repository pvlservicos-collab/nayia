-- 554 (Pedro, 31/10/2026, com o "Token de Integração de Leads" do painel do portal): "termina minha integração com o
-- chat do chaves na mão e põe a mesma Nay da OLX para responder lá com os mesmos objetivos".
--
-- O portal não tem chat (só manda o lead por POST: nome, telefone, e-mail, mensagem e o anúncio). "Responder lá" com os
-- objetivos da Nay da OLX = levar a pessoa ao WhatsApp e, lá, visita ou outras opções. A pessoa já deixou o telefone:
-- o lead vira cliente da Nay do WhatsApp do 8595 (privado.olx_lead_whatsapp, origem 'chavesnamao', etapa 'nova') e ela
-- abre a conversa como abre a de quem veio da OLX (nay-olx/olx/whatsapp.py).
--
-- A senha (lead_email / lead_token em privado.cnm_config) NÃO está aqui: segredo fora do git.
-- Chave privado.cnm_config.nay_atende: sim = o lead vai à Nay; qualquer outra coisa = fica só no CRM (como era).
BEGIN;

INSERT INTO privado.cnm_config (chave, valor) VALUES ('nay_atende', 'sim')
ON CONFLICT (chave) DO UPDATE SET valor = EXCLUDED.valor, atualizado_em = now();

CREATE OR REPLACE FUNCTION public.cnm_lead_para_a_nay(p_lead_id text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  c      privado.cnm_lead;
  v_fone text;
  v_neg  text;
  v_l    privado.olx_lead_whatsapp;
  v_id   bigint;
BEGIN
  IF coalesce((SELECT lower(btrim(valor)) FROM privado.cnm_config WHERE chave = 'nay_atende'), 'nao') <> 'sim' THEN
    RETURN NULL;
  END IF;
  SELECT * INTO c FROM privado.cnm_lead WHERE lead_id = p_lead_id;
  -- o lead de teste do portal (sem a senha) não chama ninguém
  IF c.lead_id IS NULL OR NOT c.autenticado THEN RETURN NULL; END IF;

  v_fone := regexp_replace(coalesce(c.telefone, ''), '\D', '', 'g');
  IF v_fone LIKE '55%' AND length(v_fone) IN (12, 13) THEN v_fone := substr(v_fone, 3); END IF;
  IF length(v_fone) NOT IN (10, 11) THEN RETURN NULL; END IF;

  -- a finalidade: o que o portal disse; senão, o imóvel (só venda ou só aluguel); senão, o valor do anúncio
  v_neg := CASE
    WHEN concat_ws(' ', c.negocio, c.tipo) ~* '(loca|alug|rent)' THEN 'locacao'
    WHEN concat_ws(' ', c.negocio, c.tipo) ~* '(vend|compr|sale|sell)' THEN 'venda'
    ELSE coalesce(
      (SELECT CASE WHEN coalesce(i.valor_venda, 0) > 0 AND coalesce(i.valor_aluguel, 0) = 0 THEN 'venda'
                   WHEN coalesce(i.valor_aluguel, 0) > 0 AND coalesce(i.valor_venda, 0) = 0 THEN 'locacao' END
         FROM imoveis i WHERE i.codigo = c.codigo),
      CASE WHEN c.valor >= 100000 THEN 'venda' WHEN c.valor > 0 AND c.valor <= 30000 THEN 'locacao' END)
  END;

  -- a mesma pessoa já é cliente da Nay do WhatsApp (OLX, orgânica, outro anúncio): é o MESMO lead (a regra da 393)
  SELECT * INTO v_l FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = right(v_fone, 8) ORDER BY criado_em DESC LIMIT 1;
  IF v_l.id IS NOT NULL THEN
    UPDATE privado.olx_lead_whatsapp x
       SET codigo = coalesce(c.codigo, x.codigo), negocio = coalesce(v_neg, x.negocio),
           nome = coalesce(x.nome, c.nome),
           origem = CASE WHEN x.origem IN ('organico', 'manual') THEN 'chavesnamao' ELSE x.origem END,
           -- a Nay abre de novo (com a conversa toda na mão) quem não está com a equipe, não tem visita andando e
           -- chegou por outro imóvel
           etapa = CASE WHEN x.humano_em IS NULL AND x.etapa NOT IN ('visita', 'proprietarios', 'fechamento')
                        AND c.codigo IS DISTINCT FROM x.codigo THEN 'nova' ELSE x.etapa END,
           assumido_em = CASE WHEN x.humano_em IS NULL AND x.etapa NOT IN ('visita', 'proprietarios', 'fechamento')
                              AND c.codigo IS DISTINCT FROM x.codigo THEN NULL ELSE x.assumido_em END,
           criado_em = CASE WHEN c.codigo IS DISTINCT FROM x.codigo THEN now() ELSE x.criado_em END,
           atualizado_em = now()
     WHERE x.id = v_l.id;
    RETURN v_l.id;
  END IF;

  INSERT INTO privado.olx_lead_whatsapp (chat, telefone, origem, codigo, negocio, nome, perfil)
  VALUES (NULL, v_fone, 'chavesnamao', c.codigo, v_neg, c.nome, '{"procura": "deixou o contato no Chaves na Mão"}'::jsonb)
  RETURNING id INTO v_id;
  RETURN v_id;
END
$function$;
COMMENT ON FUNCTION public.cnm_lead_para_a_nay(text) IS
  '554: o lead do Chaves na Mão vira cliente da Nay do WhatsApp (8595), que abre a conversa; chave cnm_config.nay_atende.';
REVOKE ALL ON FUNCTION public.cnm_lead_para_a_nay(text) FROM PUBLIC;

-- a 458 com duas mudanças: (1) a senha também confere se o portal mandar o token do painel inteiro (ele já é
-- base64(email:token)); (2) o lead novo vai à Nay, sem nunca derrubar o recebimento (o erro da Nay não vira 500).
CREATE OR REPLACE FUNCTION public.cnm_lead_receber(p jsonb, p_email text, p_token text, p_agente text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_email text := nullif(btrim((SELECT valor FROM privado.cnm_config WHERE chave = 'lead_email')), '');
  v_token text := nullif(btrim((SELECT valor FROM privado.cnm_config WHERE chave = 'lead_token')), '');
  v_aut   boolean;
  v_id    text := nullif(btrim(p->>'id'), '');
  v_ref   text := btrim(coalesce(p#>>'{ad,reference}', ''));
  v_quando timestamptz;
  v_valor numeric;
  v_novo  boolean;
BEGIN
  IF v_email IS NOT NULL AND v_token IS NOT NULL THEN
    IF lower(btrim(coalesce(p_email, ''))) <> lower(v_email)
       OR coalesce(p_token, '') NOT IN (v_token, translate(encode(convert_to(v_email || ':' || v_token, 'UTF8'), 'base64'), E'\n', '')) THEN
      RETURN jsonb_build_object('status', 'negado');
    END IF;
    v_aut := true;
  ELSE
    -- sem a senha guardada (antes do contrato): só o que vem do portal, e marcado
    IF coalesce(p_agente, '') NOT ILIKE 'chavesnamao-leads-api%' THEN
      RETURN jsonb_build_object('status', 'negado');
    END IF;
    v_aut := false;
  END IF;
  IF v_id IS NULL OR jsonb_typeof(p) <> 'object' THEN
    RETURN jsonb_build_object('status', 'invalido', 'erro', 'falta o id do lead');
  END IF;

  BEGIN
    v_quando := (p->>'createdAt')::timestamp AT TIME ZONE 'America/Sao_Paulo';
  EXCEPTION WHEN others THEN v_quando := NULL;
  END;
  BEGIN
    v_valor := (p#>>'{ad,value}')::numeric;
  EXCEPTION WHEN others THEN v_valor := NULL;
  END;

  INSERT INTO privado.cnm_lead AS l (lead_id, autenticado, nome, telefone, email, mensagem, tipo, codigo, anuncio_id,
                                     anuncio_url, anuncio_titulo, negocio, valor, criado_no_portal, payload)
  VALUES (v_id, v_aut, nullif(btrim(p->>'name'), ''), nullif(regexp_replace(coalesce(p->>'phone', ''), '\D', '', 'g'), ''),
          nullif(btrim(p->>'email'), ''), nullif(btrim(p->>'message'), ''), nullif(btrim(p->>'proposeTypeName'), ''),
          CASE WHEN v_ref ~ '^\d{1,9}$' THEN v_ref::integer END, nullif(p#>>'{ad,id}', ''), nullif(p#>>'{ad,url}', ''),
          nullif(p#>>'{ad,title}', ''), nullif(p#>>'{ad,purpose}', ''), v_valor, v_quando, p)
  ON CONFLICT (lead_id) DO UPDATE SET vezes = l.vezes + 1, ultimo_em = now()
  RETURNING (xmax = 0) INTO v_novo;

  IF v_novo THEN
    BEGIN
      PERFORM cnm_lead_para_a_nay(v_id);
    EXCEPTION WHEN others THEN
      RAISE WARNING 'cnm_lead_para_a_nay(%): %', v_id, SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object('status', CASE WHEN v_novo THEN 'novo' ELSE 'repetido' END, 'autenticado', v_aut, 'id', v_id);
END
$function$;

COMMIT;
