-- 364 -- OLX: os anúncios sobem sozinhos do cadastro, e as funções do chat ficam prontas para a Nay da OLX
--
-- Pedro, 13/10/2026: "quero fazer tudo no automático, tanto subir anúncio, quanto responder, e futuramente vou
-- criar uma nay só para responder na olx então já deixa as funções prontas".
--
-- O QUE ISTO É. O banco decide; quem fala com a OLX é o serviço nay-olx (nayia/nay-olx, Python), do jeito que a
-- captação já funciona. Tudo nasce DESLIGADO (`privado.olx_config`): nada vai para a OLX sem a chave `publicar = sim`
-- e sem dizer qual conta publica.
--
-- POR QUE NASCE DESLIGADO, além da cautela: em 13/10 a OLX respondeu `-6 Without permission` para a conta conectada
-- (proprietários, Telmario Araújo). Pela documentação dela, a importação por API exige plano profissional habilitado
-- para integração de anúncios. O chat funciona; anúncio pela API só depois de a OLX liberar a conta.
--
-- A API da OLX (developers.olx.com.br, lida em 13/10/2026):
--   PUT  https://apps.olx.com.br/autoupload/import            {access_token, ad_list:[{id, operation, ...}]}
--   POST https://apps.olx.com.br/autoupload/import/<token>    {access_token}   -> o que aconteceu com cada anúncio
--   GET  https://apps.olx.com.br/autoupload/v1/published      a situação de todos os anúncios da conta (paginado)
--   categorias: 1020 apartamentos · 1040 casas · 1100 terrenos · 1120 comércio e indústria
--   o nosso `id` do anúncio: [A-Za-z0-9_{}-]{1,19}; título 2 a 90; descrição 2 a 6.000; até 20 fotos JPG/PNG/GIF;
--   parâmetro opcional vazio ou 0 faz a importação FALHAR: o que não sabemos não é mandado.
--
-- AS PEÇAS:
--   privado.olx_config         as chaves (publicar, conta_que_publica, teto, telefone, mostrar_telefone, nay_responde...)
--   privado.olx_anuncio        um por imóvel e negócio (venda / locação): o que mandamos e o que a OLX respondeu
--   olx_anuncio_montar()       o anúncio de UM imóvel no formato da OLX, ou por que ele não pode ir
--   olx_anuncios_candidatos()  todo imóvel nosso disponível: pronto, faltando dado ou barrado
--   olx_anuncios_plano()       o que a próxima rodada faz: publicar, atualizar (mudou no cadastro), remover (saiu)
--   olx_anuncio_enviado/_resultado/_falhou/_na_olx   o serviço conta ao banco o que aconteceu
--   olx_nay_fila/_contexto/_reservar/_soltar/_passar_para_gente/_devolver   o chat, para a Nay da OLX
--   crm_olx_anuncios_painel() / crm_olx_config_gravar()   a tela Chat OLX › Anúncios do CRM
--
-- O QUE NUNCA VAI PARA A OLX: imóvel de parceiro, bloqueado, fora do nosso site ou que não está Disponível; número da
-- casa, torre, apartamento, dono, a observação interna; telefone, e-mail e link que estiverem dentro da descrição.
BEGIN;
SET LOCAL lock_timeout = '3s';

-- ---------------------------------------------------------------------------------------------------------------
-- 1. AS TABELAS (schema privado, como as outras da OLX)
-- ---------------------------------------------------------------------------------------------------------------
CREATE TABLE privado.olx_config (
  chave          text PRIMARY KEY,
  valor          text NOT NULL DEFAULT '',
  descricao      text,
  atualizado_em  timestamptz NOT NULL DEFAULT now(),
  atualizado_por text
);
COMMENT ON TABLE privado.olx_config IS '364: as chaves da automação da OLX (publicar anúncios, qual conta, teto, telefone do anúncio, se a Nay responde). Tudo nasce desligado.';

INSERT INTO privado.olx_config (chave, valor, descricao) VALUES
  ('publicar', 'nao', 'sim = o serviço nay-olx sobe, atualiza e remove anúncios sozinho. nao = não manda nada à OLX.'),
  ('conta_que_publica', '', 'proprietarios ou corretores: a conta da OLX em que os anúncios sobem. Vazio = nenhuma.'),
  ('teto', '5', 'Quantos anúncios nossos podem estar na OLX ao mesmo tempo (enviados + publicados). Começa baixo de propósito.'),
  ('por_rodada', '10', 'Quantos anúncios vão em cada chamada à OLX.'),
  ('telefone', '92994717316', 'Telefone do anúncio (DDD + número, 10 ou 11 dígitos). A OLX exige mesmo quando fica oculto.'),
  ('mostrar_telefone', 'nao', 'nao = o telefone fica oculto e o contato vem pelo chat (que cai no CRM). sim = aparece no anúncio.'),
  ('nay_responde', 'nao', 'sim = a Nay da OLX responde as conversas sozinha. Hoje ela ainda não existe: ver nay-olx/olx/nay.py.'),
  ('nay_silencio_s', '20', 'Quantos segundos de silêncio do cliente antes de a Nay responder.'),
  ('humano_cala_horas', '24', 'Depois que gente responde uma conversa (pelo CRM ou pelo site da OLX), a Nay fica quieta nela por este tempo.'),
  ('permissao', '', 'O que a OLX respondeu à última tentativa de usar a importação: ok, sem_permissao, bloqueado... (gravado pelo serviço)'),
  ('permissao_detalhe', '', 'A resposta da OLX, por extenso.'),
  ('permissao_em', '', 'Quando foi a última conferência.');

CREATE TABLE privado.olx_anuncio (
  id            bigserial PRIMARY KEY,
  codigo        integer NOT NULL,
  negocio       text NOT NULL CHECK (negocio IN ('venda', 'locacao')),
  conta         text NOT NULL REFERENCES privado.olx_conta(conta),
  ad_id         text NOT NULL UNIQUE CHECK (ad_id ~ '^[A-Za-z0-9_{}-]{1,19}$'),
  estado        text NOT NULL CHECK (estado IN ('enviado', 'publicado', 'recusado', 'erro', 'removendo', 'removido')),
  conteudo      jsonb,
  conteudo_hash text,
  import_token  text,
  list_id       text,
  url           text,
  olx_status    text,
  mensagem      text,
  tentativas    integer NOT NULL DEFAULT 0,
  criado_em     timestamptz NOT NULL DEFAULT now(),
  enviado_em    timestamptz,
  conferido_em  timestamptz,
  publicado_em  timestamptz,
  removido_em   timestamptz,
  removido_por_fora boolean NOT NULL DEFAULT false,
  atualizado_em timestamptz NOT NULL DEFAULT now(),
  UNIQUE (codigo, negocio)
);
CREATE INDEX olx_anuncio_list_id ON privado.olx_anuncio (list_id) WHERE list_id IS NOT NULL;
CREATE INDEX olx_anuncio_estado ON privado.olx_anuncio (estado, enviado_em);
COMMENT ON TABLE privado.olx_anuncio IS '364: os NOSSOS anúncios na OLX, um por imóvel e negócio. O que foi mandado (conteudo), o token da importação e o que a OLX respondeu (list_id, url, olx_status, mensagem).';
COMMENT ON COLUMN privado.olx_anuncio.ad_id IS 'o nosso identificador na OLX: IE<código>V (venda) ou IE<código>L (locação)';
COMMENT ON COLUMN privado.olx_anuncio.removido_por_fora IS 'alguém apagou o anúncio pelo site da OLX: o serviço NÃO publica de novo sozinho (senão desfaria o que a pessoa fez)';
COMMENT ON COLUMN privado.olx_anuncio.estado IS 'enviado (a OLX aceitou a importação, falta publicar) · publicado · recusado (pela moderação) · erro (a importação falhou) · removendo · removido';

CREATE TABLE privado.olx_anuncio_log (
  id       bigserial PRIMARY KEY,
  quando   timestamptz NOT NULL DEFAULT now(),
  ad_id    text,
  acao     text NOT NULL,
  detalhe  jsonb
);
CREATE INDEX olx_anuncio_log_ad ON privado.olx_anuncio_log (ad_id, id DESC);
COMMENT ON TABLE privado.olx_anuncio_log IS '364: o diário do que o serviço mandou à OLX e do que ela respondeu, por anúncio. Sem o token da conta.';

-- a conversa do chat vista pela Nay: quem está respondendo agora e se gente assumiu
CREATE TABLE privado.olx_chat_nay (
  chat           bigint PRIMARY KEY REFERENCES privado.olx_chat(id),
  reservada_em   timestamptz,
  reservada_por  text,
  humano_em      timestamptz,
  humano_motivo  text,
  atualizado_em  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE privado.olx_chat_nay IS '364: o estado de cada conversa da OLX para a Nay: reservada (alguém está respondendo agora) e passada para gente (a Nay não responde mais nela).';

-- ---------------------------------------------------------------------------------------------------------------
-- 2. AS CHAVES
-- ---------------------------------------------------------------------------------------------------------------
CREATE FUNCTION public.olx_cfg(p_chave text) RETURNS text
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$ SELECT c.valor FROM privado.olx_config c WHERE c.chave = p_chave $function$;

CREATE FUNCTION public.olx_cfg_gravar(p_chave text, p_valor text, p_quem text) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE privado.olx_config SET valor = coalesce(p_valor, ''), atualizado_em = now(), atualizado_por = left(coalesce(p_quem, ''), 80)
   WHERE chave = p_chave;
  RETURN FOUND;
END $function$;

-- o que a OLX respondeu sobre a permissão de importar (o serviço grava a cada tentativa)
CREATE FUNCTION public.olx_permissao_gravar(p_resultado text, p_detalhe text) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM olx_cfg_gravar('permissao', p_resultado, 'nay-olx');
  PERFORM olx_cfg_gravar('permissao_detalhe', left(coalesce(p_detalhe, ''), 500), 'nay-olx');
  PERFORM olx_cfg_gravar('permissao_em', to_char(now() AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI'), 'nay-olx');
END $function$;

-- ---------------------------------------------------------------------------------------------------------------
-- 3. O TEXTO QUE PODE IR PARA FORA: sem link, e-mail, telefone nem HTML
-- ---------------------------------------------------------------------------------------------------------------
CREATE FUNCTION public.olx_texto_limpo(p text) RETURNS text
 LANGUAGE sql IMMUTABLE
AS $function$
  SELECT btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
           coalesce(p, ''),
           '<[^>]+>', ' ', 'g'),                                             -- HTML
           '(https?://|www\.)\S+', '', 'gi'),                                -- link
           '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}', '', 'g'),     -- e-mail
           '(\+?55\s*)?\(?\d{2}\)?[\s.-]*9?\s*\d{4}[\s.-]?\d{4}', '', 'g'),   -- telefone
           '[ \t]+', ' ', 'g'),
           ' *\n *', E'\n', 'g'),
           '\n{3,}', E'\n\n', 'g'));
$function$;

-- alguma destas etiquetas casa com o padrão? (sem acento, sem maiúscula)
CREATE FUNCTION public.olx_tem(p_tags text[], p_padrao text) RETURNS boolean
 LANGUAGE sql IMMUTABLE
AS $function$
  SELECT EXISTS (SELECT 1 FROM unnest(coalesce(p_tags, '{}')) t WHERE lower(nay_sem_acento(t)) ~ p_padrao);
$function$;

-- ---------------------------------------------------------------------------------------------------------------
-- 4. O ANÚNCIO DE UM IMÓVEL, NO FORMATO DA OLX
--    Devolve {ok, barrado, falta[], ad_id, anuncio{...}, hash, titulo, preco, fotos}.
--    `barrado` = não pode estar na OLX (se estiver, sai). `falta` = pode, mas o cadastro está incompleto.
-- ---------------------------------------------------------------------------------------------------------------
CREATE FUNCTION public.olx_anuncio_montar(p_codigo integer, p_negocio text)
 RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  i         imoveis;
  cf        condominio_ficha;
  v_ad      text := 'IE' || p_codigo || CASE WHEN p_negocio = 'venda' THEN 'V' ELSE 'L' END;
  v_t       text;                      -- o tipo, sem acento e minúsculo
  v_cat     int;
  v_tipo    text;                      -- o tipo como vai no título
  v_preco   numeric;
  v_cep     text;
  v_fone    text := regexp_replace(coalesce(olx_cfg('telefone'), ''), '\D', '', 'g');
  v_condo   text;
  v_onde    text := '';
  v_titulo  text;
  v_corpo   text;
  v_linhas  text[] := '{}';
  v_fotos   jsonb;
  v_params  jsonb := '{}'::jsonb;
  v_im      text[];                    -- características do imóvel
  v_co      text[] := '{}';            -- do condomínio (lazer, segurança, comodidades)
  v_f       text[] := '{}';
  v_c       text[] := '{}';
  v_area    numeric;
  v_falta   text[] := '{}';
  v_barrado text;
  v_an      jsonb;
BEGIN
  IF p_negocio NOT IN ('venda', 'locacao') THEN
    RETURN jsonb_build_object('ok', false, 'barrado', 'negócio desconhecido', 'falta', '[]'::jsonb, 'ad_id', v_ad);
  END IF;
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.codigo IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'barrado', 'o imóvel não está no cadastro', 'falta', '[]'::jsonb, 'ad_id', v_ad);
  END IF;
  v_preco := CASE WHEN p_negocio = 'venda' THEN i.valor_venda ELSE i.valor_aluguel END;

  -- QUEM NÃO PODE IR (e sai, se estiver lá)
  v_barrado := CASE
    WHEN coalesce(i.e_parceiro, false) THEN 'imóvel de parceiro'
    WHEN i.status IS DISTINCT FROM 'Disponível' OR NOT coalesce(i.disponivel, false) THEN 'não está Disponível (' || coalesce(i.status, 'sem situação') || ')'
    WHEN coalesce(i.bloqueado, false) THEN 'bloqueado'
    WHEN NOT coalesce(i.publicado_no_site, false) THEN 'fora do nosso site'
    WHEN coalesce(v_preco, 0) <= 0 THEN 'sem valor de ' || CASE WHEN p_negocio = 'venda' THEN 'venda' ELSE 'aluguel' END
  END;
  IF v_barrado IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false, 'barrado', v_barrado, 'falta', '[]'::jsonb, 'ad_id', v_ad);
  END IF;

  SELECT * INTO cf FROM condominio_ficha c WHERE c.condominio_id = i.condo_id;
  v_t  := lower(nay_sem_acento(coalesce(i.tipo, '')));
  v_im := coalesce(i.caracteristicas, '{}');
  IF cf.id IS NOT NULL THEN v_co := cf.lazer || cf.seguranca || cf.comodidades; END IF;

  -- a categoria e o nome do tipo
  IF v_t ~ '^(apartamento|cobertura|flat|kitnet|kitinete|loft|studio)' THEN
    v_cat := 1020;
    v_tipo := CASE WHEN v_t ~ '^cobertura' OR coalesce(i.cobertura, false) THEN 'Cobertura' WHEN v_t ~ '^flat' THEN 'Flat'
                   WHEN v_t ~ '^kit' THEN 'Kitnet' WHEN v_t ~ '^loft' THEN 'Loft' WHEN v_t ~ '^studio' THEN 'Studio' ELSE 'Apartamento' END;
  ELSIF v_t ~ '^(casa|sobrado)' THEN
    v_cat := 1040;
    v_tipo := CASE WHEN v_t ~ 'condominio' THEN 'Casa em condomínio' ELSE 'Casa' END;
  ELSIF v_t ~ '^(lote|terreno|area|sitio|chacara|fazenda)' THEN
    v_cat := 1100;
    v_tipo := CASE WHEN v_t ~ '^sitio' THEN 'Sítio' WHEN v_t ~ '^chacara' THEN 'Chácara' WHEN v_t ~ '^fazenda' THEN 'Fazenda'
                   WHEN v_t ~ 'condominio' THEN 'Lote em condomínio' WHEN v_t ~ '^terreno' THEN 'Terreno' ELSE 'Lote' END;
  ELSIF v_t ~ '^(sala|andar|loja|ponto|galpao|deposito|predio|comercial)' THEN
    v_cat := 1120;
    v_tipo := CASE WHEN v_t ~ '^(sala|andar)' THEN 'Sala comercial' WHEN v_t ~ '^(loja|ponto)' THEN 'Loja'
                   WHEN v_t ~ '^(galpao|deposito)' THEN 'Galpão' WHEN v_t ~ '^predio' THEN 'Prédio comercial' ELSE 'Imóvel comercial' END;
  ELSE
    v_falta := array_append(v_falta, 'tipo de imóvel sem categoria na OLX (' || coalesce(nullif(btrim(i.tipo), ''), 'sem tipo') || ')');
  END IF;

  -- o valor tem de ser crível (um zero a mais ou a menos vira anúncio errado no ar)
  IF p_negocio = 'venda' AND v_preco < 20000 THEN v_falta := array_append(v_falta, 'valor de venda baixo demais para ser de venda (' || v_preco::bigint || ')'); END IF;
  IF p_negocio = 'locacao' AND v_preco NOT BETWEEN 300 AND 200000 THEN v_falta := array_append(v_falta, 'valor de aluguel fora do esperado (' || v_preco::bigint || ')'); END IF;

  -- o CEP: o do imóvel; sem ele, o do condomínio
  v_cep := regexp_replace(coalesce(i.cep, ''), '\D', '', 'g');
  IF v_cep !~ '^\d{8}$' THEN v_cep := regexp_replace(coalesce(cf.cep, ''), '\D', '', 'g'); END IF;
  IF v_cep !~ '^\d{8}$' THEN v_falta := array_append(v_falta, 'sem CEP (nem no imóvel nem no condomínio)'); END IF;

  IF length(v_fone) NOT BETWEEN 10 AND 11 THEN v_falta := array_append(v_falta, 'o telefone do anúncio (chave telefone) não tem 10 ou 11 dígitos'); END IF;

  -- as fotos: a capa primeiro, sem a montagem dos grupos, sem repetir, só JPG/PNG/GIF (a OLX não aceita webp), até 20
  SELECT jsonb_agg(x.url ORDER BY x.n) INTO v_fotos
    FROM (SELECT y.url, min(y.n) AS n
            FROM (SELECT f.url, row_number() OVER (ORDER BY coalesce(f.e_capa, false) DESC, f.ordem NULLS LAST, f.id) AS n
                    FROM imovel_fotos f
                   WHERE f.codigo = p_codigo AND NOT coalesce(f.e_mosaico, false)
                     AND f.url ~* '^https://' AND split_part(f.url, '?', 1) ~* '\.(jpe?g|png|gif)$') y
           GROUP BY y.url
           ORDER BY 2
           LIMIT 20) x;
  IF v_fotos IS NULL THEN v_falta := array_append(v_falta, 'sem foto que a OLX aceite (JPG, PNG ou GIF)'); END IF;

  -- os parâmetros da categoria. O que não sabemos NÃO vai: opcional vazio ou zero derruba a importação
  v_area := CASE WHEN v_cat = 1100 THEN coalesce(nullif(i.area_total, 0), nullif(i.area_util, 0)) ELSE coalesce(nullif(i.area_util, 0), nullif(i.area_total, 0)) END;
  IF v_area >= 1 THEN v_params := v_params || jsonb_build_object('size', round(v_area)::bigint::text); END IF;
  IF coalesce(i.taxa_condominio, 0) >= 1 AND i.taxa_condominio_em IS NOT NULL THEN
    v_params := v_params || jsonb_build_object('condominio', round(i.taxa_condominio)::bigint::text);
  END IF;
  IF v_cat IN (1020, 1040, 1120) AND i.vagas IS NOT NULL AND i.vagas >= 0 THEN
    v_params := v_params || jsonb_build_object('garage_spaces', least(i.vagas, 5)::text);
  END IF;
  IF v_cat IN (1020, 1040) THEN
    IF i.quartos IS NULL OR i.quartos < 0 THEN v_falta := array_append(v_falta, 'sem número de quartos');
    ELSE v_params := v_params || jsonb_build_object('rooms', least(i.quartos, 5)::text); END IF;
    IF coalesce(i.banheiros, 0) >= 1 THEN v_params := v_params || jsonb_build_object('bathrooms', least(i.banheiros, 5)::text); END IF;
  END IF;

  IF v_cat = 1020 THEN
    v_params := v_params || jsonb_build_object('apartment_type',
      CASE v_tipo WHEN 'Cobertura' THEN '2' WHEN 'Kitnet' THEN '4' WHEN 'Loft' THEN '5' WHEN 'Studio' THEN '4' ELSE '1' END);
    IF olx_tem(v_im, '(ar.condicionado|climatizad)') OR lower(coalesce(i.mobilia, '')) ~ '(climatizad| ar\M)' THEN v_f := array_append(v_f, '1'); END IF;
    IF olx_tem(v_im, 'armarios? no quarto') THEN v_f := array_append(v_f, '3'); END IF;
    IF olx_tem(v_im, '^varanda') THEN v_f := array_append(v_f, '4'); END IF;
    IF olx_tem(v_im, 'area de servico') THEN v_f := array_append(v_f, '5'); END IF;
    IF olx_tem(v_im, '(quarto de servico|dependencia de empregada)') THEN v_f := array_append(v_f, '7'); END IF;
    IF olx_tem(v_im, '^piscina') THEN v_f := array_append(v_f, '8'); END IF;
    IF olx_tem(v_im, 'armarios? na cozinha') THEN v_f := array_append(v_f, '11'); END IF;
    IF olx_tem(v_im, '^mobiliado') OR lower(coalesce(i.mobilia, '')) ~ '^mobiliado' THEN v_f := array_append(v_f, '12'); END IF;
    IF v_f <> '{}' THEN v_params := v_params || jsonb_build_object('apartment_features', to_jsonb(v_f)); END IF;
    IF olx_tem(v_co, 'condominio fechado') THEN v_c := array_append(v_c, '1'); END IF;
    IF olx_tem(v_co || v_im, '^elevador') OR lower(coalesce(cf.elevador, '')) ~ '^sim' THEN v_c := array_append(v_c, '2'); END IF;
    IF olx_tem(v_co, '(seguranca 24|guarita 24)') THEN v_c := array_append(v_c, '3'); END IF;
    IF olx_tem(v_co, '^(portaria|guarita)') THEN v_c := array_append(v_c, '4'); END IF;
    IF olx_tem(v_im || v_co, '(aceita pet|permitido animais)') THEN v_c := array_append(v_c, '5'); END IF;
    IF olx_tem(v_co, '(^academia|^fitness)') THEN v_c := array_append(v_c, '6'); END IF;
    IF olx_tem(v_co, '^piscina') THEN v_c := array_append(v_c, '7'); END IF;
    IF olx_tem(v_co, '^salao de festas') THEN v_c := array_append(v_c, '8'); END IF;
    IF v_c <> '{}' THEN v_params := v_params || jsonb_build_object('apartment_complex_features', to_jsonb(v_c)); END IF;
  ELSIF v_cat = 1040 THEN
    v_params := v_params || jsonb_build_object('home_type', CASE WHEN v_tipo = 'Casa em condomínio' THEN '3' ELSE '1' END);
    IF olx_tem(v_im, '(ar.condicionado|climatizad)') OR lower(coalesce(i.mobilia, '')) ~ '(climatizad| ar\M)' THEN v_f := array_append(v_f, '1'); END IF;
    IF olx_tem(v_im, '^piscina') THEN v_f := array_append(v_f, '2'); END IF;
    IF olx_tem(v_im, 'armarios? no quarto') THEN v_f := array_append(v_f, '3'); END IF;
    IF olx_tem(v_im, '^varanda') THEN v_f := array_append(v_f, '4'); END IF;
    IF olx_tem(v_im, 'area de servico') THEN v_f := array_append(v_f, '5'); END IF;
    IF olx_tem(v_im, '^churrasqueira') THEN v_f := array_append(v_f, '6'); END IF;
    IF olx_tem(v_im, '(quarto de servico|dependencia de empregada)') THEN v_f := array_append(v_f, '7'); END IF;
    IF olx_tem(v_im, 'armarios? na cozinha') THEN v_f := array_append(v_f, '9'); END IF;
    IF olx_tem(v_im, '^mobiliado') OR lower(coalesce(i.mobilia, '')) ~ '^mobiliado' THEN v_f := array_append(v_f, '10'); END IF;
    IF v_f <> '{}' THEN v_params := v_params || jsonb_build_object('home_features', to_jsonb(v_f)); END IF;
    IF v_tipo = 'Casa em condomínio' THEN v_c := array_append(v_c, '1'); END IF;
    IF olx_tem(v_co, '(seguranca 24|guarita 24)') THEN v_c := array_append(v_c, '2'); END IF;
    IF olx_tem(v_im, '(^murado|area murada)') THEN v_c := array_append(v_c, '3'); END IF;
    IF olx_tem(v_im || v_co, '(aceita pet|permitido animais)') THEN v_c := array_append(v_c, '4'); END IF;
    IF olx_tem(v_co, '(^academia|^fitness)') THEN v_c := array_append(v_c, '6'); END IF;
    IF olx_tem(v_co, '^piscina') THEN v_c := array_append(v_c, '9'); END IF;
    IF v_c <> '{}' THEN v_params := v_params || jsonb_build_object('home_complex_features', to_jsonb(v_c)); END IF;
  ELSIF v_cat = 1100 THEN
    v_params := v_params || jsonb_build_object('re_land_type',
      CASE WHEN v_tipo IN ('Sítio', 'Chácara') THEN '2' WHEN v_tipo = 'Fazenda' THEN '3' ELSE '1' END);
  ELSIF v_cat = 1120 THEN
    v_params := v_params || jsonb_build_object('commercial_type',
      CASE v_tipo WHEN 'Sala comercial' THEN '1' WHEN 'Galpão' THEN '2' WHEN 'Loja' THEN '6' ELSE '7' END);
    IF olx_tem(v_co, '(seguranca 24|guarita 24)') THEN v_f := array_append(v_f, '2'); END IF;
    IF olx_tem(v_co || v_im, '^elevador') OR lower(coalesce(cf.elevador, '')) ~ '^sim' THEN v_f := array_append(v_f, '4'); END IF;
    IF olx_tem(v_co, '^(portaria|guarita)') THEN v_f := array_append(v_f, '5'); END IF;
    IF olx_tem(v_co, 'acesso para deficientes') THEN v_f := array_append(v_f, '6'); END IF;
    IF v_f <> '{}' THEN v_params := v_params || jsonb_build_object('commercial_features', to_jsonb(v_f)); END IF;
  END IF;

  -- o título (até 90): "Apartamento com 3 quartos à venda no Kopenhagen, Ponta Negra"
  v_condo := nullif(btrim(coalesce(i.condominio_nome, '')), '');
  IF v_condo IN ('—', '-', '–') OR v_condo ~* 'n[aã]o identificad'
     OR lower(nay_sem_acento(coalesce(v_condo, ''))) ~ '^(casa|predio|lote|terreno|sala|loja|apartamento|galpao)( em via publica| comercial)?$'
     OR EXISTS (SELECT 1 FROM (SELECT DISTINCT x.tipo FROM imoveis x WHERE x.tipo IS NOT NULL) d
                 WHERE lower(nay_sem_acento(d.tipo)) = lower(nay_sem_acento(coalesce(v_condo, '')))) THEN
    v_condo := NULL;      -- "condomínio" que é só o nome do tipo ("Loja/Ponto", "Casa"; 356): cita o bairro
  END IF;
  v_onde := CASE WHEN v_condo IS NOT NULL THEN ' no ' || v_condo WHEN nullif(btrim(coalesce(i.bairro, '')), '') IS NOT NULL THEN ' em ' || btrim(i.bairro) ELSE '' END;
  v_titulo := coalesce(v_tipo, 'Imóvel')
    || CASE WHEN v_cat IN (1020, 1040) AND coalesce(i.quartos, 0) > 0 THEN ' com ' || i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END ELSE '' END
    || CASE WHEN p_negocio = 'venda' THEN ' à venda' ELSE ' para alugar' END
    || v_onde;
  IF v_condo IS NOT NULL AND nullif(btrim(coalesce(i.bairro, '')), '') IS NOT NULL
     AND length(v_titulo || ', ' || btrim(i.bairro)) <= 90 THEN
    v_titulo := v_titulo || ', ' || btrim(i.bairro);
  END IF;
  IF length(v_titulo) > 90 THEN v_titulo := btrim(regexp_replace(left(v_titulo, 90), '\s+\S*$', '')); END IF;

  -- a descrição: a do cadastro (limpa) e, embaixo, a ficha em linhas
  v_corpo := olx_texto_limpo(i.descricao);
  IF length(v_corpo) < 40 THEN v_corpo := v_titulo || '.'; END IF;
  IF v_cat IN (1020, 1040) AND coalesce(i.quartos, 0) > 0 THEN
    v_linhas := array_append(v_linhas, i.quartos || CASE WHEN i.quartos = 1 THEN ' quarto' ELSE ' quartos' END
      || CASE WHEN coalesce(i.suites, 0) > 0 THEN ' (' || i.suites || CASE WHEN i.suites = 1 THEN ' suíte)' ELSE ' suítes)' END ELSE '' END);
  END IF;
  IF coalesce(i.banheiros, 0) > 0 THEN v_linhas := array_append(v_linhas, i.banheiros || CASE WHEN i.banheiros = 1 THEN ' banheiro' ELSE ' banheiros' END); END IF;
  IF coalesce(i.vagas, 0) > 0 THEN v_linhas := array_append(v_linhas, i.vagas || CASE WHEN i.vagas = 1 THEN ' vaga de garagem' ELSE ' vagas de garagem' END); END IF;
  IF v_area >= 1 THEN v_linhas := array_append(v_linhas, round(v_area)::bigint || ' m²'); END IF;
  IF nullif(btrim(coalesce(i.mobilia, '')), '') IS NOT NULL AND v_cat IN (1020, 1040) THEN
    v_linhas := array_append(v_linhas, 'Mobília: ' || btrim(i.mobilia));
  END IF;
  IF v_params ? 'condominio' THEN
    v_linhas := array_append(v_linhas, 'Condomínio: R$ ' || replace(to_char(round(i.taxa_condominio), 'FM999,999,999'), ',', '.') || ' por mês');
  END IF;
  IF v_linhas <> '{}' THEN v_corpo := v_corpo || E'\n\n• ' || array_to_string(v_linhas, E'\n• '); END IF;
  IF v_im <> '{}' THEN
    v_corpo := v_corpo || E'\n\nNo imóvel: ' || (SELECT string_agg(olx_texto_limpo(t), ', ') FROM (SELECT t FROM unnest(v_im) WITH ORDINALITY u(t, n) WHERE btrim(t) <> '' ORDER BY n LIMIT 18) s) || '.';
  END IF;
  IF v_co <> '{}' THEN
    v_corpo := v_corpo || E'\n\nNo condomínio: ' || (SELECT string_agg(olx_texto_limpo(t), ', ') FROM (SELECT t FROM unnest(v_co) WITH ORDINALITY u(t, n) WHERE btrim(t) <> '' ORDER BY n LIMIT 18) s) || '.';
  END IF;
  v_corpo := left(v_corpo, 5800) || E'\n\nCódigo do imóvel: ' || p_codigo || E'\nImob Easy';

  IF v_falta <> '{}' THEN
    RETURN jsonb_build_object('ok', false, 'barrado', NULL, 'falta', to_jsonb(v_falta), 'ad_id', v_ad, 'titulo', v_titulo,
                              'preco', round(v_preco)::bigint, 'fotos', coalesce(jsonb_array_length(v_fotos), 0));
  END IF;

  v_an := jsonb_build_object(
    'id', v_ad, 'operation', 'insert', 'category', v_cat, 'subject', v_titulo, 'body', v_corpo,
    'phone', v_fone::bigint, 'type', CASE WHEN p_negocio = 'venda' THEN 's' ELSE 'u' END,
    'price', round(v_preco)::bigint, 'zipcode', v_cep,
    'phone_hidden', coalesce(olx_cfg('mostrar_telefone'), 'nao') <> 'sim',
    'params', v_params, 'images', v_fotos);
  RETURN jsonb_build_object('ok', true, 'barrado', NULL, 'falta', '[]'::jsonb, 'ad_id', v_ad, 'anuncio', v_an,
                            'hash', md5(v_an::text), 'titulo', v_titulo, 'preco', round(v_preco)::bigint,
                            'fotos', jsonb_array_length(v_fotos));
END
$function$;

-- ---------------------------------------------------------------------------------------------------------------
-- 5. TODO IMÓVEL NOSSO DISPONÍVEL, COM O QUE DARIA O ANÚNCIO
-- ---------------------------------------------------------------------------------------------------------------
CREATE FUNCTION public.olx_anuncios_candidatos()
 RETURNS TABLE(codigo integer, negocio text, m jsonb)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT i.codigo, n.negocio, olx_anuncio_montar(i.codigo, n.negocio)
    FROM imoveis i
    CROSS JOIN LATERAL (SELECT 'venda'::text AS negocio WHERE coalesce(i.valor_venda, 0) > 0
                        UNION ALL SELECT 'locacao' WHERE coalesce(i.valor_aluguel, 0) > 0) n
   WHERE i.status = 'Disponível' AND coalesce(i.disponivel, false) AND coalesce(i.publicado_no_site, false)
     AND NOT coalesce(i.e_parceiro, false) AND NOT coalesce(i.bloqueado, false);
$function$;

-- ---------------------------------------------------------------------------------------------------------------
-- 6. O PLANO DA PRÓXIMA RODADA: remover primeiro, depois atualizar, depois publicar (até o teto)
-- ---------------------------------------------------------------------------------------------------------------
CREATE FUNCTION public.olx_anuncios_plano(p_limite integer DEFAULT NULL)
 RETURNS TABLE(acao text, codigo integer, negocio text, ad_id text, motivo text, anuncio jsonb, hash text)
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_teto   int := greatest(0, coalesce(nullif(regexp_replace(coalesce(olx_cfg('teto'), ''), '\D', '', 'g'), '')::int, 0));
  v_rodada int := greatest(1, coalesce(p_limite, nullif(regexp_replace(coalesce(olx_cfg('por_rodada'), ''), '\D', '', 'g'), '')::int, 10));
  v_ativos int;
  v_n      int := 0;
  r        record;
  v_m      jsonb;
BEGIN
  -- 6.1 o que saiu do cadastro (vendeu, alugou, bloqueou, virou parceiro) sai da OLX
  FOR r IN SELECT a.* FROM privado.olx_anuncio a WHERE a.estado IN ('enviado', 'publicado') ORDER BY a.id LOOP
    EXIT WHEN v_n >= v_rodada;
    v_m := olx_anuncio_montar(r.codigo, r.negocio);
    IF v_m->>'barrado' IS NOT NULL THEN
      acao := 'remover'; codigo := r.codigo; negocio := r.negocio; ad_id := r.ad_id; motivo := v_m->>'barrado';
      anuncio := jsonb_build_object('id', r.ad_id, 'operation', 'delete'); hash := NULL;
      v_n := v_n + 1; RETURN NEXT;
    END IF;
  END LOOP;

  -- 6.2 o que mudou no cadastro (valor, fotos, descrição) vai de novo: para a OLX, inserir de novo é editar
  FOR r IN SELECT a.* FROM privado.olx_anuncio a WHERE a.estado = 'publicado' ORDER BY a.id LOOP
    EXIT WHEN v_n >= v_rodada;
    v_m := olx_anuncio_montar(r.codigo, r.negocio);
    IF (v_m->>'ok')::boolean AND v_m->>'hash' IS DISTINCT FROM r.conteudo_hash THEN
      acao := 'atualizar'; codigo := r.codigo; negocio := r.negocio; ad_id := r.ad_id; motivo := 'o cadastro mudou';
      anuncio := v_m->'anuncio'; hash := v_m->>'hash';
      v_n := v_n + 1; RETURN NEXT;
    END IF;
  END LOOP;

  -- 6.3 os novos, do mais recente para o mais antigo, até o teto
  SELECT count(*) INTO v_ativos FROM privado.olx_anuncio a WHERE a.estado IN ('enviado', 'publicado');
  FOR r IN
    SELECT c.codigo, c.negocio, c.m
      FROM olx_anuncios_candidatos() c
      LEFT JOIN privado.olx_anuncio a ON a.codigo = c.codigo AND a.negocio = c.negocio
     WHERE (c.m->>'ok')::boolean
       AND (a.id IS NULL
            OR (a.estado = 'removido' AND NOT a.removido_por_fora)   -- o que alguém apagou na OLX não volta sozinho
            -- o que falhou tenta de novo depois de 6 h; o que a moderação recusou, só se o conteúdo mudou
            OR (a.estado = 'erro' AND coalesce(a.enviado_em, a.criado_em) < now() - interval '6 hours' AND a.tentativas < 5)
            OR (a.estado = 'recusado' AND c.m->>'hash' IS DISTINCT FROM a.conteudo_hash))
     ORDER BY c.codigo DESC, c.negocio
  LOOP
    EXIT WHEN v_n >= v_rodada OR v_ativos >= v_teto;
    acao := 'publicar'; codigo := r.codigo; negocio := r.negocio; ad_id := r.m->>'ad_id'; motivo := NULL;
    anuncio := r.m->'anuncio'; hash := r.m->>'hash';
    v_n := v_n + 1; v_ativos := v_ativos + 1; RETURN NEXT;
  END LOOP;
END
$function$;

-- ---------------------------------------------------------------------------------------------------------------
-- 7. O SERVIÇO CONTA AO BANCO O QUE ACONTECEU
-- ---------------------------------------------------------------------------------------------------------------
CREATE FUNCTION public.olx_anuncio_registrar(p_ad_id text, p_acao text, p_detalhe jsonb) RETURNS void
 LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $function$
  INSERT INTO privado.olx_anuncio_log (ad_id, acao, detalhe) VALUES (p_ad_id, p_acao, p_detalhe);
$function$;

-- a OLX aceitou a importação (statusCode 0): falta a moderação publicar (ou remover)
CREATE FUNCTION public.olx_anuncio_enviado(p_ad_id text, p_codigo integer, p_negocio text, p_conta text, p_operacao text,
                                           p_conteudo jsonb, p_hash text, p_token text) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  IF p_operacao = 'delete' THEN
    UPDATE privado.olx_anuncio SET estado = 'removendo', import_token = p_token, enviado_em = now(), mensagem = NULL, atualizado_em = now()
     WHERE ad_id = p_ad_id;
  ELSE
    INSERT INTO privado.olx_anuncio AS a (codigo, negocio, conta, ad_id, estado, conteudo, conteudo_hash, import_token, enviado_em, tentativas)
    VALUES (p_codigo, p_negocio, p_conta, p_ad_id, 'enviado', p_conteudo, p_hash, p_token, now(), 1)
    ON CONFLICT (codigo, negocio) DO UPDATE
       SET conta = excluded.conta, estado = 'enviado', conteudo = excluded.conteudo, conteudo_hash = excluded.conteudo_hash,
           import_token = excluded.import_token, enviado_em = now(), mensagem = NULL, removido_em = NULL,
           removido_por_fora = false, tentativas = a.tentativas + 1, atualizado_em = now();
  END IF;
  PERFORM olx_anuncio_registrar(p_ad_id, 'enviado:' || p_operacao, jsonb_build_object('token', p_token));
END $function$;

-- a importação nem entrou (validação da OLX, sem permissão, sem vaga...)
CREATE FUNCTION public.olx_anuncio_falhou(p_ad_id text, p_codigo integer, p_negocio text, p_conta text, p_conteudo jsonb,
                                          p_hash text, p_mensagem text) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO privado.olx_anuncio AS a (codigo, negocio, conta, ad_id, estado, conteudo, conteudo_hash, enviado_em, tentativas, mensagem)
  VALUES (p_codigo, p_negocio, p_conta, p_ad_id, 'erro', p_conteudo, p_hash, now(), 1, left(p_mensagem, 500))
  ON CONFLICT (codigo, negocio) DO UPDATE
     SET estado = CASE WHEN a.estado IN ('publicado', 'removendo') THEN a.estado ELSE 'erro' END,   -- o que já está no ar continua no ar
         mensagem = left(p_mensagem, 500), enviado_em = now(), tentativas = a.tentativas + 1, atualizado_em = now();
  PERFORM olx_anuncio_registrar(p_ad_id, 'falhou', jsonb_build_object('mensagem', p_mensagem));
END $function$;

-- o que a consulta do token disse de cada anúncio
CREATE FUNCTION public.olx_anuncio_resultado(p_ad_id text, p_estado text, p_list_id text, p_url text, p_mensagem text) RETURNS void
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE privado.olx_anuncio
     SET estado = p_estado,
         list_id = coalesce(nullif(btrim(p_list_id), ''), list_id),
         url = coalesce(nullif(btrim(p_url), ''), url),
         mensagem = nullif(left(coalesce(p_mensagem, ''), 500), ''),
         conferido_em = now(), atualizado_em = now(),
         publicado_em = CASE WHEN p_estado = 'publicado' THEN coalesce(publicado_em, now()) ELSE publicado_em END,
         removido_em = CASE WHEN p_estado = 'removido' THEN now() ELSE removido_em END,
         import_token = CASE WHEN p_estado IN ('enviado', 'removendo') THEN import_token END
   WHERE ad_id = p_ad_id;
  PERFORM olx_anuncio_registrar(p_ad_id, 'resultado:' || p_estado, jsonb_build_object('list_id', p_list_id, 'url', p_url, 'mensagem', p_mensagem));
END $function$;

-- a situação que a OLX mostra na lista de anúncios da conta (published, expired, deleted, pending_pay...)
CREATE FUNCTION public.olx_anuncio_na_olx(p_ad_id text, p_list_id text, p_status text) RETURNS void
 LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $function$
  UPDATE privado.olx_anuncio
     SET olx_status = p_status, list_id = coalesce(nullif(btrim(p_list_id), ''), list_id), conferido_em = now(), atualizado_em = now(),
         -- a moderação publicou depois da nossa consulta, ou alguém apagou pelo site da OLX
         estado = CASE WHEN p_status = 'published' AND estado = 'enviado' THEN 'publicado'
                       WHEN p_status IN ('deleted', 'deleted_sold') AND estado IN ('publicado', 'enviado', 'removendo') THEN 'removido'
                       ELSE estado END,
         publicado_em = CASE WHEN p_status = 'published' THEN coalesce(publicado_em, now()) ELSE publicado_em END,
         removido_em = CASE WHEN p_status IN ('deleted', 'deleted_sold') THEN coalesce(removido_em, now()) ELSE removido_em END,
         -- estava no ar e sumiu sem a gente pedir: foi apagado pelo site da OLX
         removido_por_fora = removido_por_fora OR (p_status IN ('deleted', 'deleted_sold') AND estado IN ('publicado', 'enviado'))
   WHERE ad_id = p_ad_id AND (olx_status IS DISTINCT FROM p_status OR list_id IS NULL);
$function$;

-- os que esperam a resposta da moderação
CREATE FUNCTION public.olx_anuncios_a_conferir()
 RETURNS TABLE(ad_id text, conta text, import_token text, estado text)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT a.ad_id, a.conta, a.import_token, a.estado FROM privado.olx_anuncio a
   WHERE a.estado IN ('enviado', 'removendo') AND a.import_token IS NOT NULL ORDER BY a.enviado_em;
$function$;

-- ---------------------------------------------------------------------------------------------------------------
-- 8. O CHAT, PARA A NAY DA OLX
-- ---------------------------------------------------------------------------------------------------------------
-- as conversas que esperam resposta da Nay: a última mensagem é do cliente, já fez silêncio, ninguém está
-- respondendo agora, não foi passada para gente e nenhuma pessoa respondeu nela há pouco (gente falou, a Nay cala)
CREATE FUNCTION public.olx_nay_fila(p_limite integer DEFAULT 10)
 RETURNS TABLE(chat bigint, conta text, list_id text, nome text, ultima_em timestamptz, ultima_texto text)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT h.id, h.conta, h.list_id, h.nome, h.ultima_em, h.ultima_texto
    FROM privado.olx_chat h
    LEFT JOIN privado.olx_chat_nay n ON n.chat = h.id
   WHERE h.ultima_de = 'comprador'
     AND h.ultima_em < now() - make_interval(secs => greatest(0, coalesce(nullif(olx_cfg('nay_silencio_s'), '')::int, 20)))
     AND h.ultima_em > now() - interval '3 days'
     AND n.humano_em IS NULL
     AND (n.reservada_em IS NULL OR n.reservada_em < now() - interval '5 minutes')
     AND NOT EXISTS (SELECT 1 FROM privado.olx_chat_mensagem m
                      WHERE m.chat = h.id AND m.de = 'nos' AND coalesce(m.enviada_por, '') !~* '^nay'
                        AND m.quando > now() - make_interval(hours => greatest(0, coalesce(nullif(olx_cfg('humano_cala_horas'), '')::int, 24))))
   ORDER BY h.ultima_em
   LIMIT greatest(1, coalesce(p_limite, 10));
$function$;

-- pega a conversa para responder (uma de cada vez; a reserva vence sozinha em 5 minutos)
CREATE FUNCTION public.olx_nay_reservar(p_chat bigint, p_quem text) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_ok boolean := false;
BEGIN
  INSERT INTO privado.olx_chat_nay AS n (chat, reservada_em, reservada_por)
  VALUES (p_chat, now(), left(coalesce(p_quem, 'nay-olx'), 60))
  ON CONFLICT (chat) DO UPDATE SET reservada_em = now(), reservada_por = excluded.reservada_por, atualizado_em = now()
   WHERE n.humano_em IS NULL AND (n.reservada_em IS NULL OR n.reservada_em < now() - interval '5 minutes')
  RETURNING true INTO v_ok;
  RETURN coalesce(v_ok, false);
END $function$;

CREATE FUNCTION public.olx_nay_soltar(p_chat bigint) RETURNS void
 LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $function$ UPDATE privado.olx_chat_nay SET reservada_em = NULL, atualizado_em = now() WHERE chat = p_chat $function$;

-- a Nay não sabe ou não deve responder: a conversa fica com gente até alguém devolver
CREATE FUNCTION public.olx_nay_passar_para_gente(p_chat bigint, p_motivo text) RETURNS void
 LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $function$
  INSERT INTO privado.olx_chat_nay AS n (chat, humano_em, humano_motivo)
  VALUES (p_chat, now(), left(coalesce(p_motivo, ''), 300))
  ON CONFLICT (chat) DO UPDATE SET humano_em = now(), humano_motivo = excluded.humano_motivo, reservada_em = NULL, atualizado_em = now();
$function$;

CREATE FUNCTION public.olx_nay_devolver(p_chat bigint) RETURNS void
 LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $function$ UPDATE privado.olx_chat_nay SET humano_em = NULL, humano_motivo = NULL, reservada_em = NULL, atualizado_em = now() WHERE chat = p_chat $function$;

-- tudo o que a Nay precisa para responder UMA conversa: quem escreveu, de qual anúncio, o imóvel (o que a página
-- pública já mostra) e a conversa inteira
CREATE FUNCTION public.olx_nay_contexto(p_chat bigint) RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'chat', h.id, 'conta', h.conta, 'chat_id', h.chat_id, 'list_id', h.list_id,
    'cliente', jsonb_build_object('nome', h.nome, 'telefone', h.telefone, 'email', h.email),
    'anuncio', (SELECT jsonb_build_object('ad_id', a.ad_id, 'codigo', a.codigo, 'negocio', a.negocio, 'url', a.url, 'estado', a.estado,
                                          'titulo', a.conteudo->>'subject', 'preco', a.conteudo->'price')
                  FROM privado.olx_anuncio a WHERE a.list_id = h.list_id ORDER BY a.id DESC LIMIT 1),
    'imovel', (SELECT site_imovel_publico(a.codigo) || jsonb_build_object('link', 'https://imobeasy.online/imovel/' || a.codigo)
                 FROM privado.olx_anuncio a WHERE a.list_id = h.list_id ORDER BY a.id DESC LIMIT 1),
    'com_gente', coalesce((SELECT n.humano_em IS NOT NULL FROM privado.olx_chat_nay n WHERE n.chat = h.id), false),
    'mensagens', coalesce((SELECT jsonb_agg(jsonb_build_object('de', x.de, 'texto', x.texto, 'quando', x.quando, 'por', x.enviada_por) ORDER BY x.id)
                             FROM (SELECT m.* FROM privado.olx_chat_mensagem m WHERE m.chat = h.id ORDER BY m.id DESC LIMIT 60) x), '[]'::jsonb))
    FROM privado.olx_chat h WHERE h.id = p_chat;
$function$;

-- ---------------------------------------------------------------------------------------------------------------
-- 9. A TELA DO CRM (Chat OLX › Anúncios): o estado da automação, os nossos anúncios e o que falta em cada imóvel
-- ---------------------------------------------------------------------------------------------------------------
CREATE FUNCTION public.crm_olx_anuncios_painel() RETURNS jsonb
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  WITH c AS MATERIALIZED (SELECT * FROM olx_anuncios_candidatos()),
  j AS (SELECT c.*, a.estado, a.id AS anuncio_id FROM c LEFT JOIN privado.olx_anuncio a ON a.codigo = c.codigo AND a.negocio = c.negocio)
  SELECT jsonb_build_object(
    'config', (SELECT jsonb_object_agg(k.chave, k.valor) FROM privado.olx_config k),
    'contagem', jsonb_build_object(
      'imoveis', (SELECT count(DISTINCT codigo) FROM c),
      'prontos', (SELECT count(*) FROM j WHERE (m->>'ok')::boolean AND coalesce(estado, 'removido') IN ('removido', 'erro', 'recusado')),
      'faltando_dados', (SELECT count(*) FROM j WHERE NOT (m->>'ok')::boolean),
      'enviados', (SELECT count(*) FROM privado.olx_anuncio WHERE estado = 'enviado'),
      'publicados', (SELECT count(*) FROM privado.olx_anuncio WHERE estado = 'publicado'),
      'recusados', (SELECT count(*) FROM privado.olx_anuncio WHERE estado IN ('recusado', 'erro')),
      'removidos', (SELECT count(*) FROM privado.olx_anuncio WHERE estado IN ('removido', 'removendo'))),
    'falta', coalesce((SELECT jsonb_agg(jsonb_build_object('motivo', f.motivo, 'n', f.n, 'codigos', f.codigos) ORDER BY f.n DESC)
                         FROM (SELECT regexp_replace(t.motivo, '\s*\(.*$', '') AS motivo, count(*) AS n,
                                      (array_agg(DISTINCT j.codigo ORDER BY j.codigo DESC))[1:40] AS codigos
                                 FROM j, jsonb_array_elements_text(j.m->'falta') t(motivo)
                                WHERE NOT (j.m->>'ok')::boolean GROUP BY 1) f), '[]'::jsonb),
    'nossos', coalesce((SELECT jsonb_agg(jsonb_build_object(
                           'ad_id', a.ad_id, 'codigo', a.codigo, 'negocio', a.negocio, 'conta', a.conta, 'estado', a.estado,
                           'titulo', a.conteudo->>'subject', 'preco', a.conteudo->'price', 'list_id', a.list_id, 'url', a.url,
                           'olx_status', a.olx_status, 'mensagem', a.mensagem, 'enviado_em', a.enviado_em, 'publicado_em', a.publicado_em)
                           ORDER BY a.atualizado_em DESC)
                          FROM (SELECT * FROM privado.olx_anuncio ORDER BY atualizado_em DESC LIMIT 300) a), '[]'::jsonb),
    'proximos', coalesce((SELECT jsonb_agg(jsonb_build_object('codigo', p.codigo, 'negocio', p.negocio, 'titulo', p.m->>'titulo',
                                                             'preco', p.m->'preco', 'fotos', p.m->'fotos') ORDER BY p.codigo DESC)
                            FROM (SELECT * FROM j WHERE (m->>'ok')::boolean AND coalesce(estado, 'removido') IN ('removido', 'erro', 'recusado')
                                   ORDER BY codigo DESC LIMIT 40) p), '[]'::jsonb));
$function$;

-- as chaves que a tela pode mudar (ligar/desligar, a conta, o teto, mostrar o telefone)
CREATE FUNCTION public.crm_olx_config_gravar(p_chave text, p_valor text, p_quem text) RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v text := btrim(coalesce(p_valor, ''));
BEGIN
  IF p_chave IN ('publicar', 'mostrar_telefone', 'nay_responde') THEN
    IF v NOT IN ('sim', 'nao') THEN RETURN jsonb_build_object('ok', false, 'erro', 'use sim ou nao'); END IF;
    IF p_chave = 'publicar' AND v = 'sim' AND coalesce(olx_cfg('conta_que_publica'), '') = '' THEN
      RETURN jsonb_build_object('ok', false, 'erro', 'escolha antes a conta que publica');
    END IF;
  ELSIF p_chave = 'conta_que_publica' THEN
    IF v NOT IN ('', 'proprietarios', 'corretores') THEN RETURN jsonb_build_object('ok', false, 'erro', 'conta desconhecida'); END IF;
  ELSIF p_chave IN ('teto', 'por_rodada') THEN
    IF v !~ '^\d{1,4}$' THEN RETURN jsonb_build_object('ok', false, 'erro', 'diga um número'); END IF;
    IF p_chave = 'por_rodada' AND v::int NOT BETWEEN 1 AND 50 THEN RETURN jsonb_build_object('ok', false, 'erro', 'de 1 a 50 por rodada'); END IF;
  ELSIF p_chave = 'telefone' THEN
    v := regexp_replace(v, '\D', '', 'g');
    IF length(v) NOT BETWEEN 10 AND 11 THEN RETURN jsonb_build_object('ok', false, 'erro', 'o telefone tem de ter DDD + número (10 ou 11 dígitos)'); END IF;
  ELSE
    RETURN jsonb_build_object('ok', false, 'erro', 'esta chave não se muda pela tela');
  END IF;
  PERFORM olx_cfg_gravar(p_chave, v, p_quem);
  RETURN jsonb_build_object('ok', true, 'chave', p_chave, 'valor', v);
END $function$;

-- ---------------------------------------------------------------------------------------------------------------
-- 10. QUEM PODE CHAMAR. O serviço nay-olx entra como `nay` (o dono); o CRM entra como `nay_disparo`.
-- ---------------------------------------------------------------------------------------------------------------
DO $$
DECLARE f regprocedure;
BEGIN
  FOR f IN SELECT p.oid::regprocedure FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND (p.proname ~ '^olx_' OR p.proname IN ('crm_olx_anuncios_painel', 'crm_olx_config_gravar'))
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', f);
  END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION public.crm_olx_anuncios_painel() TO nay_disparo;
GRANT EXECUTE ON FUNCTION public.crm_olx_config_gravar(text, text, text) TO nay_disparo;
GRANT EXECUTE ON FUNCTION public.olx_anuncio_montar(integer, text) TO nay_disparo;
GRANT EXECUTE ON FUNCTION public.olx_nay_passar_para_gente(bigint, text) TO nay_disparo;
GRANT EXECUTE ON FUNCTION public.olx_nay_devolver(bigint) TO nay_disparo;

-- o que a OLX respondeu à sonda de 13/10 (remoção de um id que não existe, pela conta proprietários)
SELECT olx_permissao_gravar('sem_permissao', 'statusCode -6 "Without permission": a conta não tem plano profissional habilitado para integração de anúncios (conta proprietarios, 13/10/2026)');

COMMIT;
