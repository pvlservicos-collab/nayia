-- 369 -- OLX: os contatos de cada anúncio (leads) e a tabela de métricas
--
-- Pedro, 14/10/2026: "quero que monte um script de métricas lá em anúncios da OLX, uma lista com os anúncios e várias
-- colunas, com os dados que a OLX compartilha, número de mensagens, número de visualizações ... a lista vai se
-- atualizando por número maior de mensagens no topo, mas eu clicando em cada coluna consigo ver ordenado por esse
-- dado ... e já liga a Nay para atender lá, já veio msg lá sem atendimento".
--
-- 1. A NAY: já existe e está ligada (outra sessão, 14/10 à noite, nay-olx/olx/nay.py no servidor). O que a impede de
--    responder é a OLX: POST /autoservice/v1/chat/send devolve 500 com "Request failed with status code 403" (o serviço
--    de chat deles recusa o nosso envio). O receber funciona. Nada da Nay muda aqui.
-- 2. OS LEADS DA OLX. A OLX avisa cada contato feito num anúncio (chat, WhatsApp, telefone, simulação de financiamento),
--    um POST por contato para o endereço configurado em /autoservice/v1/lead. Ficam em `privado.olx_lead`.
-- 3. A TABELA DE MÉTRICAS (CRM › Chat OLX › Anúncios): uma linha por anúncio, com o que a OLX compartilha e o que o
--    chat mostra. VISUALIZAÇÕES A OLX NÃO FORNECE pela API (nenhuma rota da documentação traz).
BEGIN;
SET LOCAL lock_timeout = '3s';

-- 2 ────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE privado.olx_lead (
  id           bigserial PRIMARY KEY,
  conta        text NOT NULL REFERENCES privado.olx_conta(conta),
  origem       text,                -- whatsapp, telefone, chat, financing, olx
  list_id      text,
  ad_id        text,                -- o nosso id (IE<código>V/L) quando o anúncio subiu pela integração
  link         text,
  nome         text,
  email        text,
  telefone     text,
  mensagem     text,
  criado_em_olx timestamptz,
  recebido_em  timestamptz NOT NULL DEFAULT now(),
  external_id  text,
  bruto        jsonb
);
CREATE UNIQUE INDEX olx_lead_externo ON privado.olx_lead (conta, external_id) WHERE external_id IS NOT NULL;
CREATE INDEX olx_lead_anuncio ON privado.olx_lead (list_id, recebido_em DESC);
COMMENT ON TABLE privado.olx_lead IS '369: cada contato que a OLX avisa num anúncio da conta (chat, WhatsApp, telefone, financiamento), pelo webhook de leads.';

-- o segredo do endereço de leads: o mesmo da conta (o endereço do chat), mas outro caminho
CREATE FUNCTION public.crm_olx_lead_receber(p_conta text, p_segredo text, p jsonb, p_autorizacao text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_segredo text; v_id bigint;
BEGIN
  SELECT c.segredo INTO v_segredo FROM privado.olx_conta c WHERE c.conta = p_conta;
  IF v_segredo IS NULL OR p_segredo IS NULL OR length(p_segredo) < 24 OR v_segredo <> p_segredo THEN
    RETURN jsonb_build_object('ok', false, 'codigo_erro', 'nao_autorizado');
  END IF;
  IF p IS NULL OR jsonb_typeof(p) <> 'object' OR length(p::text) > 60000 THEN
    RETURN jsonb_build_object('ok', false, 'codigo_erro', 'formato');
  END IF;
  INSERT INTO privado.olx_lead (conta, origem, list_id, ad_id, link, nome, email, telefone, mensagem, criado_em_olx, external_id, bruto)
  VALUES (p_conta, left(p->>'source', 40), left(p->>'listId', 40), left(nullif(p->>'adId', ''), 40), left(p->>'linkAd', 300),
          left(p->>'name', 160), left(p->>'email', 160), left(p->>'phone', 40), left(p->>'message', 4000),
          CASE WHEN p->>'createdAt' ~ '^\d{4}-\d{2}-\d{2}T' THEN (p->>'createdAt')::timestamptz END,
          left(nullif(p->>'externalId', ''), 120), p)
  ON CONFLICT (conta, external_id) WHERE external_id IS NOT NULL DO NOTHING
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'novo', v_id IS NOT NULL);
EXCEPTION WHEN others THEN
  RETURN jsonb_build_object('ok', false, 'codigo_erro', 'falha', 'erro', SQLERRM);
END $function$;

-- 3 ────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- uma linha por anúncio: os nossos (subiram pela integração) e os que só conhecemos pelo chat ou pelos leads
CREATE FUNCTION public.crm_olx_metricas() RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  WITH anuncios AS (
    SELECT a.list_id, a.ad_id, a.codigo, a.negocio, a.conta, a.estado, a.olx_status, a.url,
           a.conteudo->>'subject' AS titulo, (a.conteudo->>'price')::numeric AS preco, a.publicado_em
      FROM privado.olx_anuncio a WHERE a.list_id IS NOT NULL
    UNION ALL
    SELECT DISTINCT ON (x.list_id) x.list_id, NULL, NULL, NULL, x.conta, NULL, NULL, 'https://www.olx.com.br/vi/' || x.list_id || '.htm',
           NULL, NULL, NULL
      FROM (SELECT list_id, conta FROM privado.olx_chat WHERE list_id IS NOT NULL
            UNION SELECT list_id, conta FROM privado.olx_lead WHERE list_id IS NOT NULL) x
     WHERE NOT EXISTS (SELECT 1 FROM privado.olx_anuncio a WHERE a.list_id = x.list_id)
  ), chat AS (
    SELECT h.list_id, count(DISTINCT h.id) AS conversas,
           count(m.id) FILTER (WHERE m.de = 'comprador') AS recebidas,
           count(m.id) FILTER (WHERE m.de = 'nos') AS enviadas,
           count(m.id) FILTER (WHERE m.de = 'nos' AND coalesce(m.enviada_por, '') ~* '^nay') AS da_nay,
           count(DISTINCT h.id) FILTER (WHERE h.ultima_de = 'comprador') AS sem_resposta,
           max(m.quando) FILTER (WHERE m.de = 'comprador') AS ultima_do_cliente,
           count(m.id) FILTER (WHERE m.de = 'comprador' AND m.quando > now() - interval '7 days') AS recebidas_7d
      FROM privado.olx_chat h LEFT JOIN privado.olx_chat_mensagem m ON m.chat = h.id
     WHERE h.list_id IS NOT NULL GROUP BY h.list_id
  ), lead AS (
    SELECT l.list_id, count(*) AS leads,
           count(*) FILTER (WHERE l.origem = 'whatsapp') AS leads_whatsapp,
           count(*) FILTER (WHERE l.origem = 'telefone') AS leads_telefone,
           count(*) FILTER (WHERE l.origem = 'chat') AS leads_chat,
           count(*) FILTER (WHERE l.origem NOT IN ('whatsapp', 'telefone', 'chat') OR l.origem IS NULL) AS leads_outros,
           max(l.recebido_em) AS ultimo_lead
      FROM privado.olx_lead l WHERE l.list_id IS NOT NULL GROUP BY l.list_id
  )
  SELECT jsonb_build_object(
    'linhas', coalesce(jsonb_agg(jsonb_build_object(
       'list_id', a.list_id, 'ad_id', a.ad_id, 'codigo', a.codigo, 'negocio', a.negocio, 'conta', a.conta,
       'situacao', coalesce(a.olx_status, a.estado), 'url', a.url, 'titulo', coalesce(a.titulo, i.tipo || coalesce(' em ' || i.bairro, '')),
       'preco', a.preco, 'publicado_em', a.publicado_em,
       'dias_no_ar', CASE WHEN a.publicado_em IS NOT NULL THEN greatest(0, (now()::date - (a.publicado_em AT TIME ZONE 'America/Manaus')::date)) END,
       'conversas', coalesce(c.conversas, 0), 'recebidas', coalesce(c.recebidas, 0), 'enviadas', coalesce(c.enviadas, 0),
       'da_nay', coalesce(c.da_nay, 0), 'sem_resposta', coalesce(c.sem_resposta, 0), 'recebidas_7d', coalesce(c.recebidas_7d, 0),
       'ultima_do_cliente', c.ultima_do_cliente,
       'leads', coalesce(l.leads, 0), 'leads_whatsapp', coalesce(l.leads_whatsapp, 0), 'leads_telefone', coalesce(l.leads_telefone, 0),
       'leads_chat', coalesce(l.leads_chat, 0), 'leads_outros', coalesce(l.leads_outros, 0), 'ultimo_lead', l.ultimo_lead,
       'imovel_status', i.status, 'bairro', i.bairro, 'tipo', i.tipo)
       ORDER BY coalesce(c.recebidas, 0) DESC, coalesce(l.leads, 0) DESC, a.publicado_em DESC NULLS LAST), '[]'::jsonb),
    'leads_ligados', EXISTS (SELECT 1 FROM privado.olx_config k WHERE k.chave = 'leads_config_id' AND k.valor <> ''),
    'atualizado_em', now())
    FROM anuncios a
    LEFT JOIN chat c ON c.list_id = a.list_id
    LEFT JOIN lead l ON l.list_id = a.list_id
    LEFT JOIN imoveis i ON i.codigo = a.codigo;
$function$;

INSERT INTO privado.olx_config (chave, valor, descricao) VALUES
  ('leads_config_id', '', 'O id da configuração de leads na OLX (/autoservice/v1/lead). Vazio = os leads ainda não chegam.'),
  ('plano', '', 'O saldo do plano na OLX (/autoupload/balance), como a OLX devolveu na última leitura (JSON).')
ON CONFLICT (chave) DO NOTHING;

REVOKE ALL ON FUNCTION public.crm_olx_lead_receber(text, text, jsonb, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.crm_olx_metricas() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_olx_lead_receber(text, text, jsonb, text) TO nay_disparo;
GRANT EXECUTE ON FUNCTION public.crm_olx_metricas() TO nay_disparo;

COMMIT;
