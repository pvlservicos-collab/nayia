-- 396: dois pedidos de gente que o serviço nay-olx executa
--
-- Pedro, 16/10/2026:
--   "cria um botão lá nos imóveis em editar imóveis, anunciar na OLX, ele cria um popup de anúncio manualmente"
--   "coloca esse campo [Enviar imóvel: um a um / por faixa] nos cards dos leads também do de captação"
--
-- ANUNCIAR NA OLX: o popup do editar imóvel lê o anúncio que o sistema monta (olx_anuncio_montar: título, descrição,
-- preço, CEP, fotos), a pessoa mexe no texto e pede; o pedido fica em privado.olx_anuncio_pedido e o nay-olx publica
-- pela API (a mesma importação da rodada) e registra em privado.olx_anuncio, de onde o serviço confere a moderação.
-- O hash guardado é o do cadastro na hora do pedido: a rodada automática não "corrige" o texto que a pessoa escreveu
-- enquanto o cadastro não mudar.
--
-- ENVIAR PELA CAPTAÇÃO: o card do lead da aba Captação do CRM pede os códigos; o pedido fica em
-- privado.captacao_envio_pedido e a Nay do WhatsApp (nay-olx) manda card + fotos, um imóvel por vez, pelo 8595-6408.
-- Imóvel de parceria ou fora do ar não sai (fica no resultado).
BEGIN;
SET LOCAL lock_timeout = '3s';
SET LOCAL statement_timeout = '20s';

CREATE TABLE IF NOT EXISTS privado.olx_anuncio_pedido (
  id         bigserial PRIMARY KEY,
  codigo     integer NOT NULL,
  negocio    text NOT NULL CHECK (negocio IN ('venda', 'locacao')),
  conta      text NOT NULL DEFAULT 'proprietarios',
  anuncio    jsonb NOT NULL,
  hash       text,
  ad_id      text,
  pedido_por text,
  estado     text NOT NULL DEFAULT 'pendente' CHECK (estado IN ('pendente', 'enviando', 'enviado', 'falhou')),
  resultado  text,
  criado_em  timestamptz NOT NULL DEFAULT now(),
  feito_em   timestamptz
);
CREATE INDEX IF NOT EXISTS olx_anuncio_pedido_pendente ON privado.olx_anuncio_pedido (id) WHERE estado = 'pendente';

CREATE TABLE IF NOT EXISTS privado.captacao_envio_pedido (
  id         bigserial PRIMARY KEY,
  telefone   text NOT NULL,
  codigos    integer[] NOT NULL,
  pedido_por text,
  estado     text NOT NULL DEFAULT 'pendente' CHECK (estado IN ('pendente', 'enviando', 'enviado', 'falhou')),
  enviados   integer[] NOT NULL DEFAULT '{}',
  resultado  text,
  criado_em  timestamptz NOT NULL DEFAULT now(),
  feito_em   timestamptz
);
CREATE INDEX IF NOT EXISTS captacao_envio_pedido_pendente ON privado.captacao_envio_pedido (id) WHERE estado = 'pendente';

-- ── o popup: o que o sistema monta, o que já está na OLX, os últimos pedidos ──
CREATE OR REPLACE FUNCTION public.site_olx_anuncio_rascunho(p_codigo integer)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'privado'
AS $function$
  SELECT jsonb_build_object(
    'codigo', p_codigo,
    'venda', olx_anuncio_montar(p_codigo, 'venda'),
    'locacao', olx_anuncio_montar(p_codigo, 'locacao'),
    'na_olx', coalesce((SELECT jsonb_agg(jsonb_build_object('negocio', a.negocio, 'ad_id', a.ad_id, 'estado', a.estado,
                                       'url', a.url, 'mensagem', a.mensagem, 'enviado_em', a.enviado_em,
                                       'publicado_em', a.publicado_em, 'removido_em', a.removido_em) ORDER BY a.id)
                          FROM privado.olx_anuncio a WHERE a.codigo = p_codigo), '[]'::jsonb),
    'pedidos', coalesce((SELECT jsonb_agg(jsonb_build_object('id', x.id, 'negocio', x.negocio, 'estado', x.estado,
                                        'resultado', x.resultado, 'criado_em', x.criado_em, 'pedido_por', x.pedido_por)
                                        ORDER BY x.id DESC)
                           FROM (SELECT * FROM privado.olx_anuncio_pedido WHERE codigo = p_codigo ORDER BY id DESC LIMIT 5) x),
                        '[]'::jsonb))
$function$;

CREATE OR REPLACE FUNCTION public.site_olx_anuncio_pedir(p_codigo integer, p_negocio text, p_campos jsonb, p_quem text)
 RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  m   jsonb := olx_anuncio_montar(p_codigo, p_negocio);
  a   jsonb;
  c   jsonb := coalesce(p_campos, '{}'::jsonb);
  v   text;
  fts jsonb;
  id_ bigint;
BEGIN
  IF p_negocio NOT IN ('venda', 'locacao') THEN RAISE EXCEPTION 'negócio inválido: %', p_negocio; END IF;
  IF NOT coalesce((m->>'ok')::boolean, false) THEN
    RAISE EXCEPTION 'não dá para anunciar: %', coalesce(m->>'barrado',
      (SELECT string_agg(x, '; ') FROM jsonb_array_elements_text(coalesce(m->'falta', '[]'::jsonb)) x), 'o anúncio não monta');
  END IF;
  IF EXISTS (SELECT 1 FROM privado.olx_anuncio_pedido WHERE codigo = p_codigo AND negocio = p_negocio
                AND estado IN ('pendente', 'enviando')) THEN
    RAISE EXCEPTION 'já tem um pedido deste anúncio sendo enviado';
  END IF;
  a := m->'anuncio';
  -- só o que a pessoa pode mexer no popup: título, descrição, preço, CEP e as fotos (as nossas, na ordem dela)
  v := btrim(coalesce(c->>'subject', ''));
  IF v <> '' THEN a := jsonb_set(a, '{subject}', to_jsonb(left(v, 90))); END IF;
  v := btrim(coalesce(c->>'body', ''));
  IF v <> '' THEN a := jsonb_set(a, '{body}', to_jsonb(left(v, 6000))); END IF;
  v := regexp_replace(coalesce(c->>'price', ''), '[^0-9]', '', 'g');
  IF v <> '' THEN
    IF v::numeric < 100 THEN RAISE EXCEPTION 'preço inválido'; END IF;
    a := jsonb_set(a, '{price}', to_jsonb(v::numeric));
  END IF;
  v := regexp_replace(coalesce(c->>'zipcode', ''), '[^0-9]', '', 'g');
  IF v <> '' THEN
    IF length(v) <> 8 THEN RAISE EXCEPTION 'CEP inválido'; END IF;
    a := jsonb_set(a, '{zipcode}', to_jsonb(v));
  END IF;
  IF jsonb_typeof(c->'images') = 'array' THEN
    SELECT coalesce(jsonb_agg(u ORDER BY n), '[]'::jsonb) INTO fts
      FROM jsonb_array_elements_text(c->'images') WITH ORDINALITY x(u, n)
     WHERE u ~ '^https://' AND n <= 20;
    IF jsonb_array_length(fts) = 0 THEN RAISE EXCEPTION 'o anúncio precisa de pelo menos uma foto'; END IF;
    a := jsonb_set(a, '{images}', fts);
  END IF;
  a := jsonb_set(a, '{operation}', '"insert"');
  INSERT INTO privado.olx_anuncio_pedido (codigo, negocio, conta, anuncio, hash, ad_id, pedido_por)
  VALUES (p_codigo, p_negocio,
          coalesce(nullif((SELECT valor FROM privado.olx_config WHERE chave = 'conta_que_publica'), ''), 'proprietarios'),
          a, m->>'hash', m->>'ad_id', left(coalesce(p_quem, ''), 80))
  RETURNING id INTO id_;
  RETURN id_;
END
$function$;

CREATE OR REPLACE FUNCTION public.site_olx_anuncio_pedido(p_id bigint)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'privado'
AS $function$
  SELECT jsonb_build_object('id', p.id, 'codigo', p.codigo, 'negocio', p.negocio, 'estado', p.estado,
                            'resultado', p.resultado, 'ad_id', p.ad_id, 'criado_em', p.criado_em, 'feito_em', p.feito_em,
                            'na_olx', (SELECT jsonb_build_object('estado', a.estado, 'url', a.url, 'mensagem', a.mensagem)
                                         FROM privado.olx_anuncio a WHERE a.ad_id = p.ad_id ORDER BY a.id DESC LIMIT 1))
    FROM privado.olx_anuncio_pedido p WHERE p.id = p_id
$function$;

-- ── o card do lead da Captação no CRM ──
CREATE OR REPLACE FUNCTION public.crm_captacao_enviar_imoveis(p_telefone text, p_codigos integer[], p_quem text)
 RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_fone text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  v_cods integer[] := ARRAY(SELECT c FROM unnest(coalesce(p_codigos, '{}')) WITH ORDINALITY u(c, n) WHERE c > 0
                             GROUP BY c ORDER BY min(n));          -- sem repetir, na ordem que a pessoa escolheu
  id_    bigint;
BEGIN
  IF length(v_fone) < 10 THEN RAISE EXCEPTION 'telefone inválido'; END IF;
  IF cardinality(v_cods) = 0 THEN RAISE EXCEPTION 'escolha ao menos um imóvel'; END IF;
  IF cardinality(v_cods) > 10 THEN RAISE EXCEPTION 'no máximo 10 imóveis por vez'; END IF;
  IF EXISTS (SELECT 1 FROM privado.captacao_envio_pedido WHERE right(telefone, 8) = right(v_fone, 8)
                AND estado IN ('pendente', 'enviando')) THEN
    RAISE EXCEPTION 'já tem um envio para este contato saindo: espere terminar';
  END IF;
  INSERT INTO privado.captacao_envio_pedido (telefone, codigos, pedido_por)
  VALUES (v_fone, v_cods, left(coalesce(p_quem, ''), 80)) RETURNING id INTO id_;
  RETURN id_;
END
$function$;

CREATE OR REPLACE FUNCTION public.crm_captacao_envio_estado(p_id bigint)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'privado'
AS $function$
  SELECT jsonb_build_object('id', id, 'estado', estado, 'codigos', codigos, 'enviados', enviados, 'resultado', resultado)
    FROM privado.captacao_envio_pedido WHERE id = p_id
$function$;

REVOKE ALL ON FUNCTION public.site_olx_anuncio_rascunho(integer), public.site_olx_anuncio_pedir(integer, text, jsonb, text),
                       public.site_olx_anuncio_pedido(bigint), public.crm_captacao_enviar_imoveis(text, integer[], text),
                       public.crm_captacao_envio_estado(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_olx_anuncio_rascunho(integer), public.site_olx_anuncio_pedir(integer, text, jsonb, text),
                          public.site_olx_anuncio_pedido(bigint) TO nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.crm_captacao_enviar_imoveis(text, integer[], text), public.crm_captacao_envio_estado(bigint)
  TO nay_disparo;

COMMIT;
