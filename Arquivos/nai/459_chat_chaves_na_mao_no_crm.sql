-- 459: CRM › Chat Chaves na Mão (Pedro, 21/10/2026): "vai ter uma outra aba lá no menu, no lugar de visitantes que vai
-- pra dentro do menu, Chat Chaves na Mão igual o olx mesmas coisas".
--
-- O portal não tem chat: o que chega é o LEAD (privado.cnm_lead, 458), com a mensagem que a pessoa escreveu no
-- anúncio. A aba mostra os leads como conversas (um por pessoa: o mesmo telefone, ou o mesmo e-mail, junta), o
-- anúncio (o nosso imóvel pelo código) no topo, e a resposta sai pelo WhatsApp Leads (o CRM abre a conversa lá).
-- Anúncios = o que está no XML e o que ficou de fora (cnm_imoveis); Informações = os endereços e o estado.
--
-- Desfazer: DROP FUNCTION crm_cnm_chats(), crm_cnm_conversa(text), crm_cnm_ler(text), crm_cnm_painel();
-- ALTER TABLE privado.cnm_lead DROP COLUMN lido_em.

BEGIN;

ALTER TABLE privado.cnm_lead ADD COLUMN IF NOT EXISTS lido_em timestamptz;
COMMENT ON COLUMN privado.cnm_lead.lido_em IS '459: quando alguém abriu a conversa no CRM (Chat Chaves na Mão); NULL = não lida.';

-- a chave da conversa: o telefone (8 últimos dígitos, como o resto do CRM), senão o e-mail, senão o próprio lead
CREATE OR REPLACE FUNCTION public.cnm_chave(l privado.cnm_lead)
 RETURNS text LANGUAGE sql IMMUTABLE
AS $f$
  SELECT CASE WHEN length(coalesce(l.telefone, '')) >= 8 THEN 't' || right(l.telefone, 8)
              WHEN nullif(btrim(coalesce(l.email, '')), '') IS NOT NULL THEN 'e' || lower(btrim(l.email))
              ELSE 'l' || l.lead_id END
$f$;

-- o imóvel de um código, como vai no topo da conversa e na lista
CREATE OR REPLACE FUNCTION public.cnm_anuncio_do_codigo(p_codigo integer)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $f$
  SELECT jsonb_build_object(
           'codigo', i.codigo,
           'condominio', nay_condominio_de_verdade(i.tipo, i.condominio_nome),
           'bairro', nullif(btrim(coalesce(i.bairro, '')), ''),
           'noAr', i.status = 'Disponível' AND coalesce(i.disponivel, false) AND coalesce(i.publicado_no_site, false),
           'foto', (SELECT f.url FROM imovel_fotos f
                     WHERE f.codigo = i.codigo AND NOT coalesce(f.e_mosaico, false) AND f.url ~* '^https://'
                     ORDER BY coalesce(f.e_capa, false) DESC, f.ordem NULLS LAST, f.id LIMIT 1))
    FROM imoveis i WHERE i.codigo = p_codigo
$f$;

-- a lista: uma conversa por pessoa, a mais recente em cima
CREATE OR REPLACE FUNCTION public.crm_cnm_chats()
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $f$
  WITH l AS (SELECT x.*, cnm_chave(x) AS chave, coalesce(x.criado_no_portal, x.recebido_em) AS quando FROM privado.cnm_lead x),
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
           'ultimaTexto', coalesce(u.mensagem, u.tipo, 'pediu contato'),
           'tipo', u.tipo,
           'autenticado', u.autenticado,
           'anuncio', jsonb_build_object('titulo', u.anuncio_titulo, 'url', u.anuncio_url, 'preco', u.valor, 'negocio', u.negocio,
                                         'codigo', u.codigo)
                      || coalesce(cnm_anuncio_do_codigo(u.codigo), '{}'::jsonb))
         ORDER BY u.quando DESC), '[]'::jsonb)
    FROM u
$f$;

-- a conversa: cada lead é uma mensagem (o que a pessoa escreveu, o tipo e o anúncio de cada vez)
CREATE OR REPLACE FUNCTION public.crm_cnm_conversa(p_chave text)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $f$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', x.lead_id,
           'quando', coalesce(x.criado_no_portal, x.recebido_em),
           'recebidoEm', x.recebido_em,
           'texto', x.mensagem,
           'tipo', x.tipo,
           'autenticado', x.autenticado,
           'anuncio', jsonb_build_object('titulo', x.anuncio_titulo, 'url', x.anuncio_url, 'preco', x.valor, 'negocio', x.negocio,
                                         'codigo', x.codigo))
         ORDER BY coalesce(x.criado_no_portal, x.recebido_em)), '[]'::jsonb)
    FROM privado.cnm_lead x WHERE cnm_chave(x) = p_chave
$f$;

-- abriu a conversa: os leads dela ficam lidos
CREATE OR REPLACE FUNCTION public.crm_cnm_ler(p_chave text)
 RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $f$
  WITH u AS (UPDATE privado.cnm_lead x SET lido_em = now() WHERE x.lido_em IS NULL AND cnm_chave(x) = p_chave RETURNING 1)
  SELECT count(*)::integer FROM u
$f$;

-- Anúncios e Informações: o que está no XML, o que ficou de fora e por quê, e o estado dos leads
CREATE OR REPLACE FUNCTION public.crm_cnm_painel()
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $f$
  WITH c AS (SELECT * FROM cnm_imoveis()),
       n AS (SELECT codigo, count(*) AS leads, max(coalesce(criado_no_portal, recebido_em)) AS ultimo
               FROM privado.cnm_lead WHERE codigo IS NOT NULL GROUP BY codigo)
  SELECT jsonb_build_object(
    'xml', 'https://api.imobeasy.online/api/chavesnamao/imoveis.xml',
    'leadsUrl', 'https://api.imobeasy.online/api/chavesnamao/leads',
    'vao', (SELECT count(*) FROM c WHERE ok),
    'ficam', (SELECT count(*) FROM c WHERE NOT ok),
    'anuncios', (SELECT coalesce(jsonb_agg(jsonb_build_object(
                    'codigo', c.codigo, 'ok', c.ok, 'falta', c.falta,
                    'titulo', c.imovel->>'titulo', 'tipo', c.imovel->>'tipo',
                    'valor', (c.imovel->>'valor')::numeric, 'valorLocacao', (c.imovel->>'valor_locacao')::numeric,
                    'transacao', concat_ws('+', c.imovel->>'transacao', nullif(c.imovel->>'transacao2', '')),
                    'fotos', coalesce(jsonb_array_length(c.imovel->'fotos'), 0),
                    'foto', c.imovel->'fotos'->>0,
                    'leads', coalesce(n.leads, 0), 'ultimoLead', n.ultimo)
                  ORDER BY c.ok, n.ultimo DESC NULLS LAST, c.codigo), '[]'::jsonb)
                  FROM c LEFT JOIN n ON n.codigo = c.codigo),
    'leads', (SELECT jsonb_build_object('total', count(*), 'pessoas', count(DISTINCT cnm_chave(l)),
                                        'naoLidos', count(*) FILTER (WHERE lido_em IS NULL),
                                        'autenticados', count(*) FILTER (WHERE autenticado),
                                        'ultimoEm', max(recebido_em))
                FROM privado.cnm_lead l),
    'senhaGuardada', (SELECT count(*) = 2 FROM privado.cnm_config
                       WHERE chave IN ('lead_email', 'lead_token') AND nullif(btrim(coalesce(valor, '')), '') IS NOT NULL))
$f$;

REVOKE ALL ON FUNCTION public.cnm_anuncio_do_codigo(integer), public.crm_cnm_chats(), public.crm_cnm_conversa(text),
  public.crm_cnm_ler(text), public.crm_cnm_painel() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_cnm_chats(), public.crm_cnm_conversa(text), public.crm_cnm_ler(text),
  public.crm_cnm_painel() TO nay_disparo;

COMMIT;
