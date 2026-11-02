-- 559 (Pedro, 02/11/2026): "organize todos os leads que possam vir de nossas redes sociais ou blogs em uma página dentro
-- do menu Imob Easy chamada Links orgânicos, são variações de links de WhatsApp com UTM para o número 92 8595-6408 para eu
-- saber de onde está vindo o lead baseado em uma mensagem automática também, ex.: Vim do blog, Vim do site".
--
-- Cada link tem um código curto (https://api.imobeasy.online/w/<código>?utm_...), que conta o clique com os UTMs e abre
-- o WhatsApp do 8595 com a mensagem pronta. A mensagem leva a MARCA do link ("Vim do blog da Imob Easy"): quando ela chega
-- (captacao_mensagens, recebida), o gatilho liga aquele telefone ao link (a marca mais comprida que aparecer vence:
-- "vim dos stories" não vira "vim do instagram").
--   privado.link_organico           os links (canal, nome, mensagem, marca, UTMs)
--   privado.link_organico_clique    cada clique no link curto (UTMs, de onde veio; o IP só como hash)
--   privado.link_organico_lead      o telefone que mandou a mensagem de um link, e quando
--   site_links_organicos()          a página: os links com cliques e leads (7 e 30 dias, total) e os últimos leads
--   site_link_organico_salvar()     criar ou mudar um link
--   site_link_organico_clique()     o link curto: anota o clique e devolve a mensagem (NULL: link desligado ou que não existe)
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.link_organico (
  codigo       text PRIMARY KEY CHECK (codigo ~ '^[a-z0-9][a-z0-9-]{1,39}$'),
  canal        text NOT NULL,
  nome         text NOT NULL,
  mensagem     text NOT NULL,
  marca        text NOT NULL,
  utm_source   text NOT NULL,
  utm_medium   text NOT NULL,
  utm_campaign text NOT NULL DEFAULT 'organico',
  ativo        boolean NOT NULL DEFAULT true,
  criado_em    timestamptz NOT NULL DEFAULT now(),
  criado_por   text,
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  CHECK (position(lower(marca) IN lower(mensagem)) > 0)
);
COMMENT ON TABLE privado.link_organico IS '559: os links orgânicos do WhatsApp do 8595 (redes, blog, site), com a marca que identifica o lead.';

CREATE TABLE IF NOT EXISTS privado.link_organico_clique (
  id       bigserial PRIMARY KEY,
  codigo   text NOT NULL REFERENCES privado.link_organico(codigo) ON UPDATE CASCADE,
  em       timestamptz NOT NULL DEFAULT now(),
  utm      jsonb NOT NULL DEFAULT '{}'::jsonb,
  referer  text,
  ip_hash  text
);
CREATE INDEX IF NOT EXISTS link_organico_clique_codigo ON privado.link_organico_clique (codigo, em DESC);

CREATE TABLE IF NOT EXISTS privado.link_organico_lead (
  telefone8    text NOT NULL,
  codigo       text NOT NULL REFERENCES privado.link_organico(codigo) ON UPDATE CASCADE,
  telefone     text NOT NULL,
  primeira_em  timestamptz NOT NULL,
  mensagem     text,
  PRIMARY KEY (telefone8, codigo)
);
CREATE INDEX IF NOT EXISTS link_organico_lead_em ON privado.link_organico_lead (codigo, primeira_em DESC);

CREATE OR REPLACE FUNCTION public.link_organico_normal(p text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT btrim(regexp_replace(lower(public.unaccent('public.unaccent'::regdictionary, coalesce(p, ''))), '[^a-z0-9]+', ' ', 'g'))
$function$;

-- o lead que chega pela mensagem de um link
CREATE OR REPLACE FUNCTION public.link_organico_do_lead()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_cod text;
  v_txt text;
BEGIN
  IF NEW.direcao <> 'recebida' OR coalesce(NEW.texto, '') !~* 'vim d' THEN
    RETURN NULL;
  END IF;
  v_txt := ' ' || link_organico_normal(NEW.texto) || ' ';
  SELECT l.codigo INTO v_cod FROM privado.link_organico l
   WHERE position(' ' || link_organico_normal(l.marca) || ' ' IN v_txt) > 0
   ORDER BY length(l.marca) DESC LIMIT 1;
  IF v_cod IS NOT NULL AND length(regexp_replace(coalesce(NEW.telefone, ''), '\D', '', 'g')) >= 8 THEN
    INSERT INTO privado.link_organico_lead (telefone8, codigo, telefone, primeira_em, mensagem)
    VALUES (right(regexp_replace(NEW.telefone, '\D', '', 'g'), 8), v_cod, NEW.telefone, coalesce(NEW.criada_em, now()),
            left(NEW.texto, 300))
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'link_organico_do_lead: %', SQLERRM;     -- a mensagem nunca cai por causa disto
  RETURN NULL;
END
$function$;

DROP TRIGGER IF EXISTS link_organico_do_lead ON public.captacao_mensagens;
CREATE TRIGGER link_organico_do_lead AFTER INSERT ON public.captacao_mensagens
  FOR EACH ROW EXECUTE FUNCTION link_organico_do_lead();

CREATE OR REPLACE FUNCTION public.site_link_organico_clique(p_codigo text, p_utm jsonb, p_referer text, p_ip text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE l privado.link_organico;
BEGIN
  SELECT * INTO l FROM privado.link_organico WHERE codigo = lower(btrim(p_codigo)) AND ativo;
  IF l.codigo IS NULL THEN RETURN NULL; END IF;
  INSERT INTO privado.link_organico_clique (codigo, utm, referer, ip_hash)
  VALUES (l.codigo, coalesce(p_utm, '{}'::jsonb), left(p_referer, 300),
          CASE WHEN coalesce(p_ip, '') <> '' THEN left(md5(p_ip || to_char(now(), 'YYYY-MM-DD')), 16) END);
  RETURN jsonb_build_object('mensagem', l.mensagem);
END
$function$;

CREATE OR REPLACE FUNCTION public.site_links_organicos()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'codigo', l.codigo, 'canal', l.canal, 'nome', l.nome, 'mensagem', l.mensagem, 'marca', l.marca,
           'utm_source', l.utm_source, 'utm_medium', l.utm_medium, 'utm_campaign', l.utm_campaign, 'ativo', l.ativo,
           'criado_em', l.criado_em,
           'cliques_7d', (SELECT count(*) FROM privado.link_organico_clique c WHERE c.codigo = l.codigo AND c.em > now() - interval '7 days'),
           'cliques_30d', (SELECT count(*) FROM privado.link_organico_clique c WHERE c.codigo = l.codigo AND c.em > now() - interval '30 days'),
           'cliques', (SELECT count(*) FROM privado.link_organico_clique c WHERE c.codigo = l.codigo),
           'leads_7d', (SELECT count(*) FROM privado.link_organico_lead d WHERE d.codigo = l.codigo AND d.primeira_em > now() - interval '7 days'),
           'leads_30d', (SELECT count(*) FROM privado.link_organico_lead d WHERE d.codigo = l.codigo AND d.primeira_em > now() - interval '30 days'),
           'leads', (SELECT count(*) FROM privado.link_organico_lead d WHERE d.codigo = l.codigo),
           'ultimos', coalesce((SELECT jsonb_agg(jsonb_build_object(
                          'em', d.primeira_em, 'final', right(d.telefone8, 4),
                          'nome', (SELECT coalesce(nullif(btrim(w.nome), ''), '') FROM privado.olx_lead_whatsapp w
                                    WHERE right(regexp_replace(w.telefone, '\D', '', 'g'), 8) = d.telefone8
                                    ORDER BY w.atualizado_em DESC LIMIT 1),
                          'etapa', (SELECT w.etapa FROM privado.olx_lead_whatsapp w
                                     WHERE right(regexp_replace(w.telefone, '\D', '', 'g'), 8) = d.telefone8
                                     ORDER BY w.atualizado_em DESC LIMIT 1)) ORDER BY d.primeira_em DESC)
                                  FROM (SELECT * FROM privado.link_organico_lead x WHERE x.codigo = l.codigo
                                         ORDER BY x.primeira_em DESC LIMIT 8) d), '[]'::jsonb))
           ORDER BY l.ativo DESC, l.canal, l.nome), '[]'::jsonb)
    FROM privado.link_organico l
$function$;

CREATE OR REPLACE FUNCTION public.site_link_organico_salvar(p jsonb, p_quem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_cod  text := lower(btrim(coalesce(p->>'codigo', '')));
  v_msg  text := btrim(coalesce(p->>'mensagem', ''));
  v_marca text := btrim(coalesce(p->>'marca', ''));
BEGIN
  IF v_cod !~ '^[a-z0-9][a-z0-9-]{1,39}$' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'O código usa só letras minúsculas, números e hífen (2 a 40).');
  END IF;
  IF btrim(coalesce(p->>'canal', '')) = '' OR btrim(coalesce(p->>'nome', '')) = '' OR v_msg = '' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Preencha o canal, o nome e a mensagem.');
  END IF;
  IF v_marca = '' THEN       -- sem marca: a primeira frase da mensagem depois do "Olá!"
    v_marca := btrim(split_part(regexp_replace(v_msg, '^\s*(ol[aá]|oi|bom dia|boa tarde|boa noite)[!,.]*\s*', '', 'i'), '.', 1));
  END IF;
  IF position(lower(v_marca) IN lower(v_msg)) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'A marca precisa estar dentro da mensagem.');
  END IF;
  IF link_organico_normal(v_marca) !~ '^vim d' THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'A marca começa com "Vim do/da/de/dos..." (é assim que o lead é reconhecido).');
  END IF;
  IF EXISTS (SELECT 1 FROM privado.link_organico WHERE codigo <> v_cod AND link_organico_normal(marca) = link_organico_normal(v_marca)) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Outro link já usa essa marca: mude a frase para saber de qual veio.');
  END IF;
  INSERT INTO privado.link_organico (codigo, canal, nome, mensagem, marca, utm_source, utm_medium, utm_campaign, ativo, criado_por)
  VALUES (v_cod, btrim(p->>'canal'), btrim(p->>'nome'), v_msg, v_marca,
          coalesce(nullif(btrim(p->>'utm_source'), ''), v_cod), coalesce(nullif(btrim(p->>'utm_medium'), ''), 'organico'),
          coalesce(nullif(btrim(p->>'utm_campaign'), ''), 'organico'), coalesce((p->>'ativo')::boolean, true), p_quem)
  ON CONFLICT (codigo) DO UPDATE SET canal = EXCLUDED.canal, nome = EXCLUDED.nome, mensagem = EXCLUDED.mensagem,
    marca = EXCLUDED.marca, utm_source = EXCLUDED.utm_source, utm_medium = EXCLUDED.utm_medium,
    utm_campaign = EXCLUDED.utm_campaign, ativo = EXCLUDED.ativo, atualizado_em = now();
  RETURN jsonb_build_object('ok', true, 'codigo', v_cod);
END
$function$;

-- os links de partida (o Pedro muda e cria outros na página)
INSERT INTO privado.link_organico (codigo, canal, nome, mensagem, marca, utm_source, utm_medium, criado_por) VALUES
  ('blog',          'Blog',       'Blog: botão dos posts',             'Olá! Vim do blog da Imob Easy e quero saber mais sobre imóveis.',                 'Vim do blog da Imob Easy',             'blog',      'post',     '559'),
  ('newsletter',    'Blog',       'Newsletter do blog (e-mail)',       'Olá! Vim da newsletter da Imob Easy e quero saber mais sobre imóveis.',           'Vim da newsletter da Imob Easy',       'newsletter','email',    '559'),
  ('site',          'Site',       'Site: botão do WhatsApp',           'Olá! Vim do site da Imob Easy e quero saber mais sobre imóveis.',                 'Vim do site da Imob Easy',             'site',      'botao',    '559'),
  ('instagram',     'Instagram',  'Instagram: link da bio',            'Olá! Vim do Instagram da Imob Easy e quero saber mais sobre imóveis.',            'Vim do Instagram da Imob Easy',        'instagram', 'bio',      '559'),
  ('stories',       'Instagram',  'Instagram: stories',                'Olá! Vim dos stories da Imob Easy e quero saber mais sobre imóveis.',             'Vim dos stories da Imob Easy',         'instagram', 'stories',  '559'),
  ('instagram-post','Instagram',  'Instagram: posts e reels',          'Olá! Vim de um post da Imob Easy no Instagram e quero saber mais sobre imóveis.', 'Vim de um post da Imob Easy no Instagram', 'instagram', 'post', '559'),
  ('facebook',      'Facebook',   'Facebook: página',                  'Olá! Vim do Facebook da Imob Easy e quero saber mais sobre imóveis.',             'Vim do Facebook da Imob Easy',         'facebook',  'pagina',   '559'),
  ('youtube',       'YouTube',    'YouTube: descrição dos vídeos',     'Olá! Vim do YouTube da Imob Easy e quero saber mais sobre imóveis.',              'Vim do YouTube da Imob Easy',          'youtube',   'video',    '559'),
  ('tiktok',        'TikTok',     'TikTok: link do perfil',            'Olá! Vim do TikTok da Imob Easy e quero saber mais sobre imóveis.',               'Vim do TikTok da Imob Easy',           'tiktok',    'bio',      '559'),
  ('google',        'Google',     'Google: perfil da empresa',         'Olá! Vim do Google e quero saber mais sobre os imóveis da Imob Easy.',            'Vim do Google',                        'google',    'perfil',   '559'),
  ('linkedin',      'LinkedIn',   'LinkedIn: página da empresa',       'Olá! Vim do LinkedIn da Imob Easy e quero saber mais sobre imóveis.',             'Vim do LinkedIn da Imob Easy',         'linkedin',  'pagina',   '559')
ON CONFLICT (codigo) DO NOTHING;

GRANT EXECUTE ON FUNCTION public.link_organico_normal(text) TO nay_site_leitura, nay_site_escrita, nay;
GRANT EXECUTE ON FUNCTION public.site_links_organicos() TO nay_site_leitura, nay_site_escrita, nay;
GRANT EXECUTE ON FUNCTION public.site_link_organico_salvar(jsonb, text) TO nay_site_escrita, nay;
GRANT EXECUTE ON FUNCTION public.site_link_organico_clique(text, jsonb, text, text) TO nay_site_leitura, nay_site_escrita, nay;

COMMIT;
