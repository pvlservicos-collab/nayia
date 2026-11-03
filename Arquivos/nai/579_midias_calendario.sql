-- 579 (Pedro, 03/11/2026, repassado pela sessão nay-ia-be): a aba MÍDIAS do admin do site, no lugar do "Gerador de posts".
-- "trocar o menu lá gerador de post por uma aba Mídias lá dentro do site e organizar essas demandas aqui criando essas
-- coisas e criando um calendário de conteúdo bonitinho com essas ideias e pensando e já organizando a produção, e lá em
-- Mídias vai ter abas: uma aba Insta, outra Face, outra YouTube, outra Google SEO e outra IA GEO".
--
-- Uma tabela só (midia_item): a DEMANDA (o que fazer, quem faz, status, prazo) e a PEÇA do calendário (conteúdo com dia,
-- presa à demanda de onde nasceu). A tela lê tudo por site_midias() e grava por site_midia_salvar / site_midia_excluir
-- (excluir = marca excluido_em; nada some do banco). As demandas e as 4 semanas de calendário (04/11 a 01/12) entram aqui
-- como ponto de partida: a lista do Pedro (origem 'lista do Pedro') e o que eu acrescentei pensando nela ('sugestão').
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TABLE IF NOT EXISTS public.midia_item (
  id             bigserial PRIMARY KEY,
  canal          text NOT NULL CHECK (canal IN ('insta', 'face', 'youtube', 'seo', 'geo')),
  tipo           text NOT NULL DEFAULT 'demanda' CHECK (tipo IN ('demanda', 'conteudo')),
  titulo         text NOT NULL CHECK (length(btrim(titulo)) > 0),
  descricao      text,
  formato        text,
  quem           text,
  status         text NOT NULL DEFAULT 'ideia' CHECK (status IN ('ideia', 'a_fazer', 'producao', 'pronto', 'publicado', 'pausado')),
  prioridade     text CHECK (prioridade IN ('alta', 'media', 'baixa')),
  data           date,
  demanda_id     bigint REFERENCES public.midia_item(id),
  origem         text,
  link           text,
  criado_em      timestamptz NOT NULL DEFAULT now(),
  atualizado_em  timestamptz NOT NULL DEFAULT now(),
  atualizado_por text,
  excluido_em    timestamptz
);
COMMENT ON TABLE public.midia_item IS '579: a aba Mídias do admin: demandas de conteúdo/tráfego por canal (Insta, Face, YouTube, Google SEO, IA GEO) e as peças do calendário.';
CREATE INDEX IF NOT EXISTS midia_item_data ON public.midia_item (data) WHERE excluido_em IS NULL;

CREATE OR REPLACE FUNCTION public.site_midias()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT jsonb_build_object(
    'hoje', (now() AT TIME ZONE 'America/Manaus')::date,
    'itens', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id', m.id, 'canal', m.canal, 'tipo', m.tipo, 'titulo', m.titulo, 'descricao', m.descricao, 'formato', m.formato,
        'quem', m.quem, 'status', m.status, 'prioridade', m.prioridade, 'data', m.data, 'demanda_id', m.demanda_id,
        'origem', m.origem, 'link', m.link, 'atualizado_em', m.atualizado_em, 'atualizado_por', m.atualizado_por)
        ORDER BY m.data NULLS LAST, m.id)
      FROM midia_item m WHERE m.excluido_em IS NULL), '[]'::jsonb))
$function$;

CREATE OR REPLACE FUNCTION public.site_midia_salvar(p jsonb, p_quem text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id bigint := nullif(p->>'id', '')::bigint; v_dem bigint := nullif(p->>'demanda_id', '')::bigint;
BEGIN
  IF coalesce(btrim(p->>'titulo'), '') = '' THEN RAISE EXCEPTION 'falta o título'; END IF;
  IF v_dem IS NOT NULL AND NOT EXISTS (SELECT 1 FROM midia_item WHERE id = v_dem AND tipo = 'demanda' AND excluido_em IS NULL) THEN
    v_dem := NULL;
  END IF;
  IF v_id IS NULL THEN
    INSERT INTO midia_item (canal, tipo, titulo, descricao, formato, quem, status, prioridade, data, demanda_id, origem, link, atualizado_por)
    VALUES (p->>'canal', coalesce(nullif(p->>'tipo', ''), 'demanda'), btrim(p->>'titulo'), nullif(btrim(p->>'descricao'), ''),
            nullif(btrim(p->>'formato'), ''), nullif(btrim(p->>'quem'), ''), coalesce(nullif(p->>'status', ''), 'ideia'),
            nullif(p->>'prioridade', ''), nullif(p->>'data', '')::date, v_dem, coalesce(nullif(p->>'origem', ''), 'tela'),
            nullif(btrim(p->>'link'), ''), left(p_quem, 80))
    RETURNING id INTO v_id;
  ELSE
    UPDATE midia_item SET canal = p->>'canal', tipo = coalesce(nullif(p->>'tipo', ''), tipo), titulo = btrim(p->>'titulo'),
           descricao = nullif(btrim(p->>'descricao'), ''), formato = nullif(btrim(p->>'formato'), ''),
           quem = nullif(btrim(p->>'quem'), ''), status = coalesce(nullif(p->>'status', ''), status),
           prioridade = nullif(p->>'prioridade', ''), data = nullif(p->>'data', '')::date, demanda_id = v_dem,
           link = nullif(btrim(p->>'link'), ''), atualizado_em = now(), atualizado_por = left(p_quem, 80)
     WHERE id = v_id AND excluido_em IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'item % não existe', v_id; END IF;
  END IF;
  RETURN jsonb_build_object('id', v_id);
END
$function$;

CREATE OR REPLACE FUNCTION public.site_midia_excluir(p_id bigint, p_quem text)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- some da tela, fica no banco (excluido_em); as peças presas a uma demanda excluída ficam soltas, não somem
  WITH x AS (UPDATE midia_item SET excluido_em = now(), atualizado_por = left(p_quem, 80) WHERE id = p_id AND excluido_em IS NULL RETURNING id)
  SELECT jsonb_build_object('excluidos', (SELECT count(*) FROM x))
$function$;

REVOKE ALL ON FUNCTION public.site_midias() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.site_midia_salvar(jsonb, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.site_midia_excluir(bigint, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_midias() TO nay, nay_site_leitura, nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.site_midia_salvar(jsonb, text) TO nay, nay_site_escrita;
GRANT EXECUTE ON FUNCTION public.site_midia_excluir(bigint, text) TO nay, nay_site_escrita;
GRANT SELECT ON public.midia_item TO nay_leitura;

-- ───────── as demandas (só na primeira vez: a tabela vazia) ─────────
DO $seed$
DECLARE L text := 'lista do Pedro (03/11)'; N text := 'lista do Pedro (03/11), nova'; S text := 'sugestão (03/11)';
BEGIN
IF EXISTS (SELECT 1 FROM midia_item) THEN RETURN; END IF;
INSERT INTO midia_item (canal, titulo, descricao, formato, quem, status, prioridade, data, origem) VALUES
-- INSTA (e o status do WhatsApp, que é o mesmo formato vertical)
('insta', 'Ver as redes sociais da Imob Easy', 'Levantar o que existe hoje em cada rede (Instagram @imobeasy, Facebook, YouTube, TikTok): seguidores, última postagem, bio com o link /bio, destaques e o que está fora do padrão da marca. Sai daqui a lista do que arrumar primeiro.', 'Diagnóstico', 'Pedro', 'a_fazer', 'alta', '2026-11-06', L),
('insta', 'Calendário de status e redes sociais', 'É esta aba: cada peça com dia, canal, quem faz e status. Toda segunda, revisar a semana que entra e passar para "A fazer" o que vai ser gravado.', 'Rotina', 'Pedro', 'producao', 'alta', '2026-11-04', L),
('insta', 'Dicas para corretores nos status', 'Uma dica curta por dia útil nos status do WhatsApp do 8595 e da Parceria, onde estão os corretores: parceria 50%, pedir imóvel pelo código, visita marcada pela Nay, documentos, captação. O Claude escreve o lote da semana na segunda; quem posta publica de manhã.', 'Status', 'Rayssa (texto: Claude)', 'a_fazer', 'media', NULL, L),
('insta', 'Diego grava vídeo em toda visita', 'Vídeo vertical de 30 a 60 s em cada visita: fachada, sala, cozinha, quartos e vista, sem o cliente aparecer. Manda no grupo da equipe com o código do imóvel; vira Reels e Short (ver YouTube).', 'Reels', 'Diego', 'a_fazer', 'alta', NULL, L),
('insta', 'Perguntas das conversas viram pauta', 'Toda segunda, as 5 perguntas que mais apareceram na semana nas conversas da Nay (Leads, Parceria e Oficial) viram roteiro: a pergunta é o gancho dos 3 primeiros segundos e a resposta cabe em 30 s. As mesmas perguntas viram FAQ no blog (ver IA GEO).', 'Reels', 'Claude separa · Tel grava', 'ideia', 'alta', NULL, N),
('insta', 'Prova social de cada fechamento', 'Cada fechamento vira um post: "mais um alugado no [condomínio] em [x] dias", com a foto da fachada ou da entrega da chave e a autorização do cliente. Os fechamentos são da Rayssa: ela avisa e pede a autorização.', 'Post', 'Rayssa', 'ideia', 'alta', NULL, N),
('insta', 'A especialista da Ponta Negra', 'Conteúdo de bairro sem venda: os condomínios, onde comer, escolas, trânsito, quanto custa morar lá. Uma série semanal (terça); no blog vira o guia do bairro (ver IA GEO).', 'Reels', 'Tel grava · Claude roteiro', 'ideia', 'media', NULL, N),
('insta', 'Um conteúdo por dia, minerado de perfis que deram certo', 'Uma lista de 10 perfis de imobiliárias e corretores que crescem; toda semana, os posts com mais salvamentos e comentários viram a nossa versão, adaptada a Manaus (quinta e sábado do calendário).', 'Post / Reels', 'Claude pesquisa · Pedro aprova', 'ideia', 'media', NULL, N),
('insta', 'Vídeo do Tel chamando corretores para a rede', '"Quem quer trabalhar comigo": 60 s do Tel falando da parceria de 50%, da Nay que atende e do grupo. Sai no Insta, nos status e nos grupos de corretores, e depois vira anúncio para corretores.', 'Reels', 'Tel', 'a_fazer', 'alta', '2026-11-06', N),
-- YOUTUBE
('youtube', 'Editor de vídeo top automático', 'Os vídeos de visita (Diego) e os do gerador de posts saem prontos sozinhos: corte, legenda, música, capa, logo e o contato no fim. Testar 2 ou 3 ferramentas com o mesmo vídeo e ficar com a melhor.', 'Ferramenta', 'Pedro + Claude', 'ideia', 'media', NULL, L),
('youtube', 'Os vídeos do gerador de posts também como Shorts', 'Todo vídeo do gerador vira Short com título de busca de Manaus, ex.: "Apartamento 2 quartos para alugar na Ponta Negra, Manaus | R$ 2.600". Na descrição, o link do imóvel e o WhatsApp. Segunda, quarta e sexta no calendário.', 'Short', 'Claude (automático)', 'ideia', 'alta', NULL, N),
('youtube', 'Canal arrumado: capa, descrição e playlists por bairro', 'Para os Shorts terem onde morar: capa da marca, descrição com "imóveis em Manaus", playlists Ponta Negra, Adrianópolis, Parque 10, Tarumã.', 'Canal', 'Pedro', 'ideia', 'baixa', NULL, S),
-- FACE (página e Meta Ads)
('face', 'Notícia do mercado de Manaus comentada pelo Tel', 'Toda quinta: uma notícia (juros, lançamentos, obras, preço do m²); o Tel comenta em 2 ou 3 parágrafos ou num áudio; sai no blog e na página do Facebook.', 'Post + blog', 'Tel comenta · Claude escreve', 'ideia', 'media', NULL, N),
('face', 'Primeira campanha de clique para o WhatsApp do 8595', 'Meta Ads com objetivo de mensagens, com os imóveis de locação mais pedidos (a lista Top 5 de 03/11). Verba de teste por 7 dias; medir o custo por conversa e quantas viram visita.', 'Anúncio', 'Pedro', 'a_fazer', 'alta', '2026-11-09', L),
('face', 'Anúncio de captação para donos com clique para o Número Oficial', '"Quer alugar ou vender o seu imóvel em Manaus?": o clique abre a conversa no Oficial, onde a Nay de Captação atende.', 'Anúncio', 'Pedro', 'ideia', 'alta', '2026-11-16', N),
('face', 'Públicos do CRM no Meta', 'Subir listas do CRM: excluir os corretores dos anúncios de cliente, reencontrar o dono que não respondeu e achar gente parecida com quem visitou.', 'Públicos', 'Pedro (Claude exporta as listas)', 'ideia', 'media', NULL, N),
('face', 'Anúncio de formulário para as casas de condomínio à venda', 'Formulário instantâneo da Meta (nome, telefone, faixa de valor) que termina no WhatsApp da Nay Leads.', 'Anúncio', 'Pedro', 'ideia', 'media', '2026-11-23', N),
('face', 'Tráfego de posicionamento com remarketing de oferta', 'Os vídeos de autoridade (Tel, bairro, notícia) vão para público frio; quem assistiu metade recebe a oferta (imóvel ou captação).', 'Anúncio', 'Pedro', 'ideia', 'baixa', NULL, N),
-- GOOGLE SEO (site, Perfil da Empresa e Google Ads)
('seo', 'SEO da home do site', 'Título e descrição com "imóveis para alugar e comprar em Manaus", um H1 só, links para os bairros, dados estruturados de imobiliária e a página leve no celular.', 'Site', 'Pedro + Claude', 'a_fazer', 'alta', '2026-11-10', L),
('seo', 'Uma página para cada busca', 'Lente do Fabio Ricotta: "subindo isso para 3% dá 180 cadastros, o cadastro cai para R$ 167 cada. No Google, a landing page faz o trabalho que o criativo faz no Meta." Em vez de todas as buscas irem para a home, uma página por intenção ("apartamento para alugar na Ponta Negra", "casa em condomínio no Tarumã", "alugar meu imóvel em Manaus") com os imóveis daquela busca e o WhatsApp.', 'Landing pages', 'Pedro + Claude', 'ideia', 'alta', NULL, L),
('seo', 'Google Ads para o dono que procura "alugar meu imóvel" em Manaus', 'Campanha de Pesquisa com as palavras do dono (alugar meu imóvel, administradora de imóveis Manaus, anunciar imóvel) levando à página de captação e ao Número Oficial.', 'Anúncio', 'Pedro', 'ideia', 'alta', '2026-11-27', L),
('seo', 'Perfil da Empresa no Google e avaliações', 'Criar e verificar o perfil (fotos, horário, site, WhatsApp). Depois de cada visita e de cada fechamento, pedir a avaliação ao cliente e ao corretor.', 'Perfil Google', 'Pedro cria · Rayssa pede as avaliações', 'a_fazer', 'alta', '2026-11-05', L),
('seo', 'Campanha de Pesquisa por condomínio e bairro', 'Um grupo de anúncio por condomínio com imóvel no ar e por bairro, levando ao WhatsApp da Nay Leads.', 'Anúncio', 'Pedro', 'ideia', 'media', NULL, N),
-- IA GEO (aparecer quando alguém pergunta ao ChatGPT, Gemini ou Perplexity)
('geo', 'Guia da Ponta Negra no blog', 'A versão escrita da série da especialista: uma página longa, com perguntas e respostas, dados e condomínios, atualizada todo mês. É o tipo de página que a IA cita quando perguntam "onde morar em Manaus".', 'Blog', 'Claude escreve · Tel revisa', 'ideia', 'media', '2026-11-13', S),
('geo', 'As perguntas reais viram o FAQ do blog', 'As perguntas da semana (as mesmas da pauta do Insta) viram respostas curtas no blog, com a marcação de FAQ: é o formato que as buscas de IA mais citam.', 'Blog', 'Claude (automático)', 'ideia', 'media', NULL, S),
('geo', 'A notícia da semana também no blog', 'A mesma notícia comentada pelo Tel (ver Face), com data e fonte: conteúdo novo toda semana mostra às IAs que o site está vivo.', 'Blog', 'Claude', 'ideia', 'media', NULL, S),
('geo', 'Ser citada pelas IAs: dados iguais em todo lugar e llms.txt', 'Nome, CRECI, endereço, telefone e descrição iguais no site, no Google, no Instagram e nos portais; arquivo llms.txt no site; página "Sobre a Imob Easy" com números reais (imóveis, corretores, visitas).', 'Site', 'Pedro + Claude', 'ideia', 'media', '2026-11-20', S);
END
$seed$;

-- ───────── o calendário: 4 semanas, de 04/11 a 01/12 (só se ainda não houver peça) ─────────
DO $cal$
DECLARE d date; dow int; n int := 0; c text := 'calendário (579)';
  dicas text[] := ARRAY['Parceria 50%: você traz o cliente, a gente traz o imóvel',
    'Peça o imóvel pelo código: a Nay manda o card e as fotos na hora',
    'Visita marcada em minutos: a Nay confirma com o dono por você',
    'Cliente vai financiar? Peça só os imóveis que aceitam financiamento',
    'Documentos para alugar: o checklist que fecha mais rápido',
    'Como captar um imóvel numa conversa só',
    'Responder em 5 minutos fecha mais negócio',
    'Onde estão os pedidos desta semana: Ponta Negra, Adrianópolis, Parque 10',
    'Dono com preço alto: como mostrar o mercado sem perder a captação',
    'Entre no grupo e receba os imóveis novos primeiro'];
  pn text[] := ARRAY['Os condomínios da beira do rio', 'Onde comer na Ponta Negra', 'Escolas e faculdades perto da Ponta Negra',
    'Como é o trânsito para quem mora na Ponta Negra', 'Quanto custa morar na Ponta Negra (aluguel e condomínio)'];
  dem jsonb;
BEGIN
IF EXISTS (SELECT 1 FROM midia_item WHERE tipo = 'conteudo') THEN RETURN; END IF;
SELECT jsonb_object_agg(titulo, id) INTO dem FROM midia_item WHERE tipo = 'demanda';
FOR d IN SELECT generate_series('2026-11-04'::date, '2026-12-01'::date, '1 day')::date LOOP
  dow := extract(dow FROM d);
  -- Insta: um conteúdo por dia, com o tema do dia da semana
  INSERT INTO midia_item (canal, tipo, titulo, formato, quem, status, data, demanda_id, origem)
  SELECT 'insta', 'conteudo', t.titulo, t.formato, t.quem, 'ideia', d, (dem->>t.dem_titulo)::bigint, c
    FROM (VALUES
      (1, 'Pergunta da semana (sai das conversas da Nay)', 'Reels', 'Tel grava', 'Perguntas das conversas viram pauta'),
      (2, 'Ponta Negra: ' || pn[1 + (n % 5)], 'Reels', 'Tel grava', 'A especialista da Ponta Negra'),
      (3, 'Imóvel em vídeo: a visita da semana', 'Reels', 'Diego grava', 'Diego grava vídeo em toda visita'),
      (4, 'A nossa versão de um post que deu certo', 'Carrossel', 'Claude', 'Um conteúdo por dia, minerado de perfis que deram certo'),
      (5, 'Prova social: o fechamento da semana', 'Post', 'Rayssa', 'Prova social de cada fechamento'),
      (6, 'Imóvel da semana (carrossel do gerador de posts)', 'Carrossel', 'Claude', 'Um conteúdo por dia, minerado de perfis que deram certo'),
      (0, 'Bastidores: um dia de visitas da equipe', 'Stories', 'Diego', 'Diego grava vídeo em toda visita')) t(dia, titulo, formato, quem, dem_titulo)
   WHERE t.dia = dow;
  IF dow = 2 THEN n := n + 1; END IF;
  -- Status do WhatsApp: a dica do dia para corretores, de segunda a sexta
  IF dow BETWEEN 1 AND 5 THEN
    INSERT INTO midia_item (canal, tipo, titulo, formato, quem, status, data, demanda_id, origem)
    VALUES ('insta', 'conteudo', 'Status: ' || dicas[1 + ((d - '2026-11-04'::date) % 10)], 'Status', 'Rayssa', 'ideia', d,
            (dem->>'Dicas para corretores nos status')::bigint, c);
  END IF;
  -- YouTube: Short de segunda, quarta e sexta
  IF dow IN (1, 3, 5) THEN
    INSERT INTO midia_item (canal, tipo, titulo, formato, quem, status, data, demanda_id, origem)
    VALUES ('youtube', 'conteudo', 'Short: um imóvel do gerador com título de busca de Manaus', 'Short', 'Claude (automático)', 'ideia', d,
            (dem->>'Os vídeos do gerador de posts também como Shorts')::bigint, c);
  END IF;
  -- Face: a notícia comentada (quinta) e o imóvel da semana (sábado)
  IF dow = 4 THEN
    INSERT INTO midia_item (canal, tipo, titulo, formato, quem, status, data, demanda_id, origem)
    VALUES ('face', 'conteudo', 'Notícia do mercado de Manaus comentada pelo Tel', 'Post + blog', 'Tel comenta · Claude escreve', 'ideia', d,
            (dem->>'Notícia do mercado de Manaus comentada pelo Tel')::bigint, c),
           ('geo', 'conteudo', 'Blog: a notícia da semana', 'Blog', 'Claude', 'ideia', d,
            (dem->>'A notícia da semana também no blog')::bigint, c);
  END IF;
  IF dow = 6 THEN
    INSERT INTO midia_item (canal, tipo, titulo, formato, quem, status, data, origem)
    VALUES ('face', 'conteudo', 'Página: o imóvel da semana', 'Post', 'Claude', 'ideia', d, c);
  END IF;
  -- IA GEO: o FAQ da semana, toda sexta
  IF dow = 5 THEN
    INSERT INTO midia_item (canal, tipo, titulo, formato, quem, status, data, demanda_id, origem)
    VALUES ('geo', 'conteudo', 'Blog: FAQ com as perguntas da semana', 'Blog', 'Claude (automático)', 'ideia', d,
            (dem->>'As perguntas reais viram o FAQ do blog')::bigint, c);
  END IF;
END LOOP;
-- os marcos (uma vez só)
INSERT INTO midia_item (canal, tipo, titulo, formato, quem, status, data, demanda_id, origem) VALUES
  ('insta', 'conteudo', 'Vídeo do Tel: "quem quer trabalhar comigo"', 'Reels', 'Tel', 'a_fazer', '2026-11-06', (dem->>'Vídeo do Tel chamando corretores para a rede')::bigint, c),
  ('seo', 'conteudo', 'Perfil da Empresa no Google no ar', 'Perfil Google', 'Pedro', 'a_fazer', '2026-11-05', (dem->>'Perfil da Empresa no Google e avaliações')::bigint, c),
  ('face', 'conteudo', 'Começa o teste de clique para o WhatsApp do 8595', 'Anúncio', 'Pedro', 'a_fazer', '2026-11-09', (dem->>'Primeira campanha de clique para o WhatsApp do 8595')::bigint, c),
  ('seo', 'conteudo', 'SEO da home publicado', 'Site', 'Pedro + Claude', 'a_fazer', '2026-11-10', (dem->>'SEO da home do site')::bigint, c),
  ('seo', 'conteudo', 'Página: apartamento para alugar na Ponta Negra', 'Landing page', 'Pedro + Claude', 'ideia', '2026-11-12', (dem->>'Uma página para cada busca')::bigint, c),
  ('geo', 'conteudo', 'Guia da Ponta Negra publicado no blog', 'Blog', 'Claude · Tel revisa', 'ideia', '2026-11-13', (dem->>'Guia da Ponta Negra no blog')::bigint, c),
  ('face', 'conteudo', 'Começa o anúncio de captação para donos (Oficial)', 'Anúncio', 'Pedro', 'ideia', '2026-11-16', (dem->>'Anúncio de captação para donos com clique para o Número Oficial')::bigint, c),
  ('seo', 'conteudo', 'Página: casa em condomínio no Tarumã', 'Landing page', 'Pedro + Claude', 'ideia', '2026-11-19', (dem->>'Uma página para cada busca')::bigint, c),
  ('geo', 'conteudo', 'llms.txt e página Sobre a Imob Easy', 'Site', 'Pedro + Claude', 'ideia', '2026-11-20', (dem->>'Ser citada pelas IAs: dados iguais em todo lugar e llms.txt')::bigint, c),
  ('face', 'conteudo', 'Começa o anúncio de formulário das casas de condomínio', 'Anúncio', 'Pedro', 'ideia', '2026-11-23', (dem->>'Anúncio de formulário para as casas de condomínio à venda')::bigint, c),
  ('seo', 'conteudo', 'Página: alugar meu imóvel em Manaus', 'Landing page', 'Pedro + Claude', 'ideia', '2026-11-26', (dem->>'Uma página para cada busca')::bigint, c),
  ('seo', 'conteudo', 'Começa o Google Ads "alugar meu imóvel"', 'Anúncio', 'Pedro', 'ideia', '2026-11-27', (dem->>'Google Ads para o dono que procura "alugar meu imóvel" em Manaus')::bigint, c);
END
$cal$;

COMMIT;
