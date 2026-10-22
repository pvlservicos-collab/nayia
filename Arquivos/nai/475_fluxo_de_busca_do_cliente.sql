-- 475: O FLUXO DE BUSCA DO CLIENTE (Pedro, 22/10/2026)
--
-- "quero que cada lead que chega na aba leads da OLX seja criado para ele um registro de busca, sabemos o que ele está
-- buscando baseado no anúncio, e vamos mostrar nossas opções, se não tivermos avisamos a ele que vamos continuar
-- verificando, e aí se ativa automaticamente o fluxo de busca de imóvel, em 2 lugares ... primeiramente nos grupos de
-- WhatsApp ... nunca errar e pedir a coisa errada no grupo errado, e também na OLX ... buscar na nossa base de dados do
-- scrap ... e quando formos buscar e tiver um que se encaixe mandamos mensagem para o corretor perguntando se aceita
-- parceria ... isso tudo pelo WhatsApp de captação (leads) ... que tenha lá na lista de buscas cada pedido com uma
-- marcação tipo uma linha a ser preenchida de até onde ele já foi ... quando o corretor mandar no PV tenhamos uma Nay que
-- entenda que o cara enviou um imóvel que bate com uma das buscas ativas logo ele é corretor, e cadastre esse imóvel no
-- nosso site, pergunte as informações que faltar ... e completando tudo oferte ao cliente".
--
-- O serviço que anda é o nay-olx (olx/buscas.py, linha própria). Aqui ficam:
--   privado.busca_cliente         um registro por lead da aba Leads (olx_lead_whatsapp): o perfil e até onde a busca foi
--   privado.busca_cliente_passo   cada passo, para a linha do CRM (perfil, base, cliente, grupos, olx, corretor, oferta)
--   privado.busca_grupo           os grupos do número de captação e a regra de cada um (o que pode pedir lá)
--   privado.busca_contato         quem nós chamamos por causa de uma busca (anunciante da OLX) ou quem respondeu um grupo
--   privado.busca_grupo_membro    os participantes dos grupos: escreveu no PV = corretor, nunca cliente orgânico
--   busca_olx_candidatos(filtros) os anúncios da nossa base de scrap que servem para o perfil
--   crm_busca_cliente_lista(dias) a lista da tela Buscar imóvel OLX (CRM), com os passos
--   crm_busca_cliente_acao(id, acao, quem)  ativar | pausar | encerrar pela tela
--   olx_organicos_novos           passa a pular os contatos de busca e os membros dos grupos (a Nay dos clientes não
--                                 atende corretor como se fosse cliente)
-- Chaves (privado.olx_config): busca_fluxo, busca_grupos, busca_olx, busca_corretor = nao | teste | sim (teste: o que
-- iria ao grupo / ao anunciante vai ao primeiro número de whatsapp_teste, com "[teste: iria para ...]").

BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.busca_cliente (
  id                 bigserial PRIMARY KEY,
  lead               bigint NOT NULL UNIQUE REFERENCES privado.olx_lead_whatsapp(id) ON DELETE CASCADE,
  filtros            jsonb NOT NULL DEFAULT '{}'::jsonb,
  estado             text NOT NULL DEFAULT 'perfil'
                     CHECK (estado IN ('perfil', 'nossa_base', 'buscando', 'ofertado', 'pausada', 'encerrada')),
  motivo             text,
  teste              boolean NOT NULL DEFAULT false,
  ativada_em         timestamptz,
  cliente_avisado_em timestamptz,
  base_em            timestamptz,
  base_qtd           integer,
  grupos             jsonb NOT NULL DEFAULT '[]'::jsonb,   -- [{grupo, nome, em, mid}]
  grupos_em          timestamptz,
  olx                jsonb NOT NULL DEFAULT '[]'::jsonb,   -- [{olx_id, titulo, url, preco, bairro, tel, anunciante, em, mid, resposta}]
  olx_em             timestamptz,
  ofertas            jsonb NOT NULL DEFAULT '[]'::jsonb,   -- [{tel, nome, de, codigo, em, estado}]
  ofertado_em        timestamptz,
  criado_em          timestamptz NOT NULL DEFAULT now(),
  atualizado_em      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS busca_cliente_estado ON privado.busca_cliente (estado, atualizado_em);
COMMENT ON TABLE privado.busca_cliente IS '475: a busca de cada lead da aba Leads (nay-olx olx/buscas.py): o perfil e até onde foi (base, grupos, OLX, corretores, oferta).';

CREATE TABLE IF NOT EXISTS privado.busca_cliente_passo (
  id     bigserial PRIMARY KEY,
  busca  bigint NOT NULL REFERENCES privado.busca_cliente(id) ON DELETE CASCADE,
  em     timestamptz NOT NULL DEFAULT now(),
  lugar  text NOT NULL CHECK (lugar IN ('perfil', 'base', 'cliente', 'grupos', 'olx', 'corretor', 'oferta', 'equipe')),
  texto  text NOT NULL,
  dados  jsonb
);
CREATE INDEX IF NOT EXISTS busca_cliente_passo_busca ON privado.busca_cliente_passo (busca, id);

CREATE TABLE IF NOT EXISTS privado.busca_grupo (
  grupo_id        text PRIMARY KEY,
  nome            text NOT NULL,
  locacao         boolean NOT NULL,
  venda           boolean NOT NULL,
  locacao_min     numeric,          -- só pedido de locação com teto a partir disto
  venda_min       numeric,          -- só pedido de venda com teto a partir disto
  ativo           boolean NOT NULL DEFAULT true,
  ultimo_envio_em timestamptz
);
COMMENT ON TABLE privado.busca_grupo IS '475: os grupos do número de captação (8595) onde a busca do cliente é pedida, com a regra do Pedro (22/10).';
-- Pedro, 22/10: "ÚNICO GRUPO QUE NÃO ENVIA BUSCA DE COMPRA, SÓ DE LOCAÇÃO: Locação OFERTA e BUSCA - CREDENCIADOS; demais
-- manda venda e locação; ESSE GRUPO ENVIA BUSCA DE LOCAÇÃO DE 7K EM DIANTE E VENDA ACIMA DE 800K EM DIANTE: Alto Padrão".
-- Os ids vieram da Z-API (GET /groups da instância de captação, 22/10). Os outros grupos do número (Comercial, Altarquia,
-- Imóveis para anunciar, os da 1104) não recebem busca.
INSERT INTO privado.busca_grupo (grupo_id, nome, locacao, venda, locacao_min, venda_min) VALUES
  ('120363320022482743-group', '🟢 Locação OFERTA e BUSCA 🔍 - CREDENCIADOS', true, false, NULL, NULL),
  ('120363179394595348-group', '📍CREDENCIADOS | Corretores Performance', true, true, NULL, NULL),
  ('559291005912-1563982274', 'BUSCA E OFERTA IMOB EASY 1⃣', true, true, NULL, NULL),
  ('559291005912-1567004759', 'FECHANDO PARCERIAS 2.0', true, true, NULL, NULL),
  ('559291005912-1609266311', 'FECHANDO PARCERIAS 1.0', true, true, NULL, NULL),
  ('120363319292435731-group', '🟢 Alto Padrão - OFERTA e BUSCA 🔍', true, true, 7000, 800000)
ON CONFLICT (grupo_id) DO NOTHING;

CREATE TABLE IF NOT EXISTS privado.busca_contato (
  id        bigserial PRIMARY KEY,
  telefone8 text NOT NULL,
  telefone  text NOT NULL,
  busca     bigint REFERENCES privado.busca_cliente(id) ON DELETE SET NULL,
  de        text NOT NULL CHECK (de IN ('anunciante_olx', 'corretor_grupo', 'corretor_pv')),
  olx_id    bigint,
  nome      text,
  em        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS busca_contato_tel ON privado.busca_contato (telefone8, em);

CREATE TABLE IF NOT EXISTS privado.busca_grupo_membro (
  telefone8     text PRIMARY KEY,
  telefone      text NOT NULL,
  grupos        text[] NOT NULL DEFAULT '{}',
  atualizado_em timestamptz NOT NULL DEFAULT now()
);

INSERT INTO privado.olx_config (chave, valor) VALUES
  ('busca_fluxo', 'teste'), ('busca_grupos', 'teste'), ('busca_olx', 'teste'), ('busca_corretor', 'teste'),
  ('busca_grupos_intervalo_min', '120'), ('busca_lote_min', '10'), ('busca_olx_por_busca', '3'),
  ('busca_horario', '8-19')
ON CONFLICT (chave) DO NOTHING;

INSERT INTO privado.ia_no_modelo (no, modelo, trocado_por) VALUES ('olx.corretor', 'gpt-6-luna', '475 (o fluxo de busca)')
ON CONFLICT (no) DO NOTHING;

-- os anúncios da base de scrap que servem: negócio, tipo, valor de -20% a +10% do teto, quartos, bairros (o mesmo
-- normalizador da nossa busca), só com telefone e só dos últimos 30 dias de coleta
CREATE OR REPLACE FUNCTION public.busca_olx_candidatos(p_filtros jsonb, p_excluir bigint[] DEFAULT '{}', p_limite integer DEFAULT 5)
 RETURNS TABLE(olx_id bigint, titulo text, url text, preco numeric, preco_texto text, bairro text, quartos integer,
               subtipo text, tipo_negocio text, anunciante text, telefones text[], fotos text[], descricao text, nota integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  WITH f AS (
    SELECT lower(coalesce(p_filtros->>'finalidade', '')) AS fin, lower(coalesce(p_filtros->>'tipo', '')) AS tipo,
           nullif(p_filtros->>'teto', '')::numeric AS teto, nullif(p_filtros->>'quartos', '')::int AS q,
           coalesce(p_filtros->>'aceita_menos_quartos', '') = 'true' AS menos,
           coalesce(p_filtros->>'qualquer_bairro', '') = 'true' AS qualquer
  ), pedidos AS (
    SELECT DISTINCT nay_normalizar_lugar(coalesce(nay_bairro_parecido(b), b), true) AS n
      FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(p_filtros->'bairros') = 'array' THEN p_filtros->'bairros' ELSE '[]'::jsonb END) b
  ), cand AS (
    SELECT DISTINCT ON (a.olx_id) a.*
      FROM scrap_anuncio a, f
     WHERE cardinality(a.telefones) > 0
       AND a.coletado_em > now() - interval '30 days'
       AND NOT (a.olx_id = ANY (p_excluir))
       AND (f.fin = '' OR (f.fin LIKE 'loca%' AND a.tipo_negocio ILIKE 'Aluguel%') OR (f.fin LIKE 'vend%' AND a.tipo_negocio ILIKE 'Venda%'))
       AND (f.tipo = ''
            OR (f.tipo ~ 'condom' AND a.tipo_negocio ILIKE '%condom%')
            OR (f.tipo !~ 'condom' AND f.tipo ~ 'casa' AND a.categoria = 'Casas')
            OR (f.tipo ~ 'apart' AND a.categoria = 'Apartamentos'))
       AND (f.teto IS NULL OR a.preco BETWEEN f.teto * 0.8 AND f.teto * 1.1)
       AND (f.q IS NULL OR a.quartos BETWEEN f.q - CASE WHEN f.menos THEN 1 ELSE 0 END AND f.q + 1)
       AND (f.qualquer OR NOT EXISTS (SELECT 1 FROM pedidos)
            OR nay_normalizar_lugar(a.bairro, true) IN (SELECT n FROM pedidos))
       AND coalesce(a.anunciante, '') !~* '(imob ?easy|f ?v sobreira)'
     ORDER BY a.olx_id, a.coletado_em DESC
  )
  SELECT c.olx_id, c.titulo, c.url, c.preco, c.preco_texto, c.bairro, c.quartos, c.subtipo, c.tipo_negocio, c.anunciante,
         c.telefones, c.fotos, left(c.descricao, 1500),
         (100 - CASE WHEN f.teto IS NULL THEN 0 ELSE least(30, round(abs(c.preco - f.teto) / f.teto * 100)::int) END
              - CASE WHEN f.q IS NOT NULL AND c.quartos <> f.q THEN 10 ELSE 0 END)::int AS nota
    FROM cand c, f
   ORDER BY 14 DESC, c.data_olx DESC NULLS LAST
   LIMIT greatest(p_limite, 1);
$function$;

-- a tela do CRM (Buscar imóvel OLX): as buscas com o lead, o perfil e os passos
CREATE OR REPLACE FUNCTION public.crm_busca_cliente_lista(p_dias integer DEFAULT 14)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT coalesce(jsonb_agg(x ORDER BY x->>'atualizado_em' DESC), '[]'::jsonb) FROM (
    SELECT jsonb_build_object(
             'id', b.id, 'lead', b.lead, 'estado', b.estado, 'motivo', b.motivo, 'teste', b.teste, 'filtros', b.filtros,
             'nome', l.nome, 'telefone', l.telefone, 'origem', l.origem, 'etapa', l.etapa, 'codigo', l.codigo,
             'criado_em', b.criado_em, 'atualizado_em', b.atualizado_em, 'ativada_em', b.ativada_em,
             'cliente_avisado_em', b.cliente_avisado_em, 'base_em', b.base_em, 'base_qtd', b.base_qtd,
             'grupos', b.grupos, 'grupos_em', b.grupos_em, 'olx', b.olx, 'olx_em', b.olx_em,
             'ofertas', b.ofertas, 'ofertado_em', b.ofertado_em,
             'passos', coalesce((SELECT jsonb_agg(jsonb_build_object('em', p.em, 'lugar', p.lugar, 'texto', p.texto) ORDER BY p.id)
                                  FROM (SELECT * FROM privado.busca_cliente_passo p WHERE p.busca = b.id ORDER BY p.id DESC LIMIT 40) p), '[]'::jsonb)) AS x
      FROM privado.busca_cliente b JOIN privado.olx_lead_whatsapp l ON l.id = b.lead
     WHERE b.atualizado_em > now() - make_interval(days => greatest(p_dias, 1))) y;
$function$;

CREATE OR REPLACE FUNCTION public.crm_busca_cliente_acao(p_id bigint, p_acao text, p_quem text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_estado text;
BEGIN
  SELECT estado INTO v_estado FROM privado.busca_cliente WHERE id = p_id FOR UPDATE;
  IF v_estado IS NULL THEN RETURN jsonb_build_object('ok', false, 'erro', 'busca não existe'); END IF;
  IF p_acao = 'ativar' THEN
    UPDATE privado.busca_cliente SET estado = 'buscando', ativada_em = coalesce(ativada_em, now()), motivo = 'ativada pela tela',
           atualizado_em = now() WHERE id = p_id;
  ELSIF p_acao = 'pausar' THEN
    UPDATE privado.busca_cliente SET estado = 'pausada', motivo = 'pausada pela tela', atualizado_em = now() WHERE id = p_id;
  ELSIF p_acao = 'encerrar' THEN
    UPDATE privado.busca_cliente SET estado = 'encerrada', motivo = 'encerrada pela tela', atualizado_em = now() WHERE id = p_id;
  ELSE
    RETURN jsonb_build_object('ok', false, 'erro', 'ação desconhecida');
  END IF;
  INSERT INTO privado.busca_cliente_passo (busca, lugar, texto) VALUES
    (p_id, 'equipe', CASE p_acao WHEN 'ativar' THEN 'Busca ativada' WHEN 'pausar' THEN 'Busca pausada' ELSE 'Busca encerrada' END
                     || coalesce(' por ' || nullif(btrim(p_quem), ''), '') || ' (tela do CRM)');
  RETURN jsonb_build_object('ok', true);
END $function$;

GRANT EXECUTE ON FUNCTION public.crm_busca_cliente_lista(integer), public.crm_busca_cliente_acao(bigint, text, text) TO nay_disparo;

-- a Nay dos clientes não atende como cliente orgânico quem nós chamamos por uma busca nem quem está nos grupos
CREATE OR REPLACE FUNCTION public.olx_organicos_novos(p_janela_min integer DEFAULT 60)
 RETURNS TABLE(telefone text, primeira bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH cfg AS (
    SELECT coalesce(nullif((SELECT valor FROM privado.olx_config WHERE chave = 'organico_desde'), '')::timestamptz, now()) AS desde,
           coalesce((SELECT valor FROM privado.olx_config WHERE chave = 'whatsapp_nunca'), '') AS nunca
  ), novas AS (
    SELECT m.id, regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g') AS d
      FROM captacao_mensagens m CROSS JOIN cfg
     WHERE m.direcao = 'recebida' AND m.criada_em > greatest(cfg.desde, now() - make_interval(mins => greatest(p_janela_min, 1)))
  ), primeiras AS (
    SELECT DISTINCT ON (right(d, 8)) d, id FROM novas
     WHERE d ~ '^55[1-9][0-9]9?[0-9]{8}$'
     ORDER BY right(d, 8), id
  )
  SELECT CASE WHEN length(p.d) IN (12, 13) THEN substr(p.d, 3) ELSE p.d END, p.id
    FROM primeiras p CROSS JOIN cfg
   WHERE NOT EXISTS (SELECT 1 FROM captacao_mensagens x WHERE x.id < p.id
                       AND right(regexp_replace(coalesce(x.telefone, ''), '\D', '', 'g'), 8) = right(p.d, 8))
     AND NOT EXISTS (SELECT 1 FROM captacao_leads c WHERE c.telefone_chave = nay_fone_chave(p.d))
     AND NOT EXISTS (SELECT 1 FROM proprietarios pr WHERE right(regexp_replace(coalesce(pr.telefone, ''), '\D', '', 'g'), 8) = right(p.d, 8))
     AND NOT EXISTS (SELECT 1 FROM nai_contato k WHERE right(regexp_replace(coalesce(k.telefone, ''), '\D', '', 'g'), 8) = right(p.d, 8))
     AND NOT EXISTS (SELECT 1 FROM privado.olx_lead_whatsapp o WHERE right(o.telefone, 8) = right(p.d, 8))
     -- 475: o anunciante que chamamos por uma busca e o corretor dos grupos são da Nay dos corretores (olx/buscas.py)
     AND NOT EXISTS (SELECT 1 FROM privado.busca_contato bc WHERE bc.telefone8 = right(p.d, 8))
     AND NOT EXISTS (SELECT 1 FROM privado.busca_grupo_membro gm WHERE gm.telefone8 = right(p.d, 8))
     AND position(right(p.d, 8) IN regexp_replace(cfg.nunca, '\D', '', 'g')) = 0
$function$;

COMMIT;
