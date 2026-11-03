-- 574: CRM › Chat Zap (Pedro, 03/11/2026: "pessoal do zap ... cria lá um chat Zap lá no crm").
-- O mesmo molde do Chat Chaves na Mão (459): o Grupo OLX (ZAP Imóveis, Viva Real, OLX pelo Canal Pro) não tem chat
-- conosco; o que chega é o lead por POST (542, privado.zap_lead). Os leads da mesma pessoa (telefone, ou e-mail) são
-- uma conversa; cada lead é um balão. A resposta sai pelo WhatsApp Leads (a Nay do 8595 já chama, 572).
--   crm_zap_chats()        a lista, uma linha por pessoa
--   crm_zap_conversa(text) os leads de uma pessoa
--   crm_zap_ler(text)      abriu a conversa = lidos (coluna nova lido_em)
--   crm_zap_painel()       os imóveis que o nosso cadastro manda ao feed (cnm_imoveis ok), com os leads de cada um, e o
--                          estado da integração. QUEM FICA DE FORA DO XML do ZAP (CEP, 5 fotos JPG, descrição) é regra
--                          do nay-site-api (zap_api._falta): a rota do CRM junta o ?todos=1 dele, para não haver duas regras.
BEGIN;
SET LOCAL lock_timeout = '5s';

ALTER TABLE privado.zap_lead ADD COLUMN IF NOT EXISTS lido_em timestamptz;
COMMENT ON COLUMN privado.zap_lead.lido_em IS '574: quando alguém abriu a conversa no CRM (Chat Zap); NULL = não lida.';
-- o lead de teste da homologação (30/10) já foi visto
UPDATE privado.zap_lead SET lido_em = recebido_em WHERE lido_em IS NULL AND NOT autenticado AND telefone = '11999999999';

CREATE OR REPLACE FUNCTION public.zap_chave(l privado.zap_lead)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN length(coalesce(l.telefone, '')) >= 8 THEN 't' || right(l.telefone, 8)
              WHEN nullif(btrim(coalesce(l.email, '')), '') IS NOT NULL THEN 'e' || lower(btrim(l.email))
              ELSE 'l' || l.id END
$function$;

-- o portal de cada lead, como a Nay diz (nay-olx whatsapp.nome_do_zap): VivaReal -> Viva Real, OLX -> OLX, resto -> ZAP Imóveis
CREATE OR REPLACE FUNCTION public.zap_portal(p_origem text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN p_origem ~* 'viva' THEN 'Viva Real' WHEN p_origem ~* '^olx' THEN 'OLX' ELSE 'ZAP Imóveis' END
$function$;

-- transactionType do lead (SELL / RENT) no nosso português
CREATE OR REPLACE FUNCTION public.zap_negocio(p_transacao text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE WHEN p_transacao ~* 'sell|sale|venda' THEN 'Venda' WHEN p_transacao ~* 'rent|loca' THEN 'Locação' END
$function$;

CREATE OR REPLACE FUNCTION public.crm_zap_chats()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH l AS (SELECT x.*, zap_chave(x) AS chave, coalesce(x.criado_em, x.recebido_em) AS quando FROM privado.zap_lead x),
       u AS (SELECT DISTINCT ON (chave) * FROM l ORDER BY chave, quando DESC)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'chave', u.chave,
           'nome', (SELECT y.nome FROM l y WHERE y.chave = u.chave AND y.nome IS NOT NULL ORDER BY y.quando DESC LIMIT 1),
           'telefone', (SELECT y.telefone FROM l y WHERE y.chave = u.chave AND y.telefone IS NOT NULL ORDER BY y.quando DESC LIMIT 1),
           'email', (SELECT y.email FROM l y WHERE y.chave = u.chave AND y.email IS NOT NULL ORDER BY y.quando DESC LIMIT 1),
           'leads', (SELECT count(*) FROM l y WHERE y.chave = u.chave),
           'naoLidas', (SELECT count(*) FROM l y WHERE y.chave = u.chave AND y.lido_em IS NULL),
           'criadoEm', (SELECT min(y.quando) FROM l y WHERE y.chave = u.chave),
           'ultimaEm', u.quando,
           'ultimaTexto', coalesce(u.mensagem, 'pediu contato'),
           'tipo', zap_portal(u.origem),
           'autenticado', u.autenticado,
           'anuncio', jsonb_build_object('titulo', NULL, 'url', NULL, 'preco', NULL, 'negocio', zap_negocio(u.transacao),
                                         'codigo', u.codigo)
                      || coalesce(cnm_anuncio_do_codigo(u.codigo), '{}'::jsonb))
         ORDER BY u.quando DESC), '[]'::jsonb)
    FROM u
$function$;

CREATE OR REPLACE FUNCTION public.crm_zap_conversa(p_chave text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', x.id,
           'quando', coalesce(x.criado_em, x.recebido_em),
           'recebidoEm', x.recebido_em,
           'texto', x.mensagem,
           'tipo', zap_portal(x.origem),
           'autenticado', x.autenticado,
           'anuncio', jsonb_build_object('titulo', NULL, 'url', NULL, 'preco', NULL, 'negocio', zap_negocio(x.transacao),
                                         'codigo', x.codigo))
         ORDER BY coalesce(x.criado_em, x.recebido_em)), '[]'::jsonb)
    FROM privado.zap_lead x WHERE zap_chave(x) = p_chave
$function$;

CREATE OR REPLACE FUNCTION public.crm_zap_ler(p_chave text)
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH u AS (UPDATE privado.zap_lead x SET lido_em = now() WHERE x.lido_em IS NULL AND zap_chave(x) = p_chave RETURNING 1)
  SELECT count(*)::integer FROM u
$function$;

CREATE OR REPLACE FUNCTION public.crm_zap_painel()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH c AS (SELECT * FROM cnm_imoveis() WHERE ok),
       n AS (SELECT codigo, count(*) AS leads, max(coalesce(criado_em, recebido_em)) AS ultimo
               FROM privado.zap_lead WHERE codigo IS NOT NULL GROUP BY codigo)
  SELECT jsonb_build_object(
    'xml', 'https://api.imobeasy.online/api/zap/imoveis.xml',
    'leadsUrl', 'https://api.imobeasy.online/api/zap/leads',
    'anuncios', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                    'codigo', c.codigo, 'ok', true, 'falta', '[]'::jsonb,
                    'titulo', c.imovel->>'titulo', 'tipo', c.imovel->>'tipo',
                    'valor', (c.imovel->>'valor')::numeric, 'valorLocacao', (c.imovel->>'valor_locacao')::numeric,
                    'transacao', concat_ws('+', c.imovel->>'transacao', nullif(c.imovel->>'transacao2', '')),
                    'fotos', coalesce(jsonb_array_length(c.imovel->'fotos'), 0),
                    'foto', c.imovel->'fotos'->>0,
                    'leads', coalesce(n.leads, 0), 'ultimoLead', n.ultimo)
                  ORDER BY n.ultimo DESC NULLS LAST, c.codigo), '[]'::jsonb)
                  FROM c LEFT JOIN n ON n.codigo = c.codigo),
    'leads', (SELECT jsonb_build_object('total', count(*), 'pessoas', count(DISTINCT zap_chave(l)),
                                        'naoLidos', count(*) FILTER (WHERE lido_em IS NULL),
                                        'autenticados', count(*) FILTER (WHERE autenticado),
                                        'ultimoEm', max(recebido_em))
                FROM privado.zap_lead l),
    'senhaGuardada', EXISTS (SELECT 1 FROM privado.zap_config
                              WHERE chave = 'lead_segredo' AND nullif(btrim(coalesce(valor, '')), '') IS NOT NULL),
    -- a mesma leitura de zap_lead_para_a_nay (572): sem a chave, a Nay não chama
    'naySim', coalesce((SELECT lower(btrim(valor)) FROM privado.zap_config WHERE chave = 'nay_atende'), 'nao') = 'sim')
$function$;

-- o CRM lê com o mesmo papel das funções do Chaves na Mão (nay_disparo); ninguém mais (são SECURITY DEFINER)
REVOKE ALL ON FUNCTION public.crm_zap_chats(), public.crm_zap_conversa(text), public.crm_zap_ler(text), public.crm_zap_painel() FROM PUBLIC;
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT DISTINCT grantee FROM information_schema.routine_privileges
            WHERE routine_name = 'crm_cnm_chats' AND grantee NOT IN ('nay', 'PUBLIC', 'postgres') LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.crm_zap_chats(), public.crm_zap_conversa(text), public.crm_zap_ler(text), public.crm_zap_painel() TO %I', r.grantee);
  END LOOP;
END $$;

COMMIT;
