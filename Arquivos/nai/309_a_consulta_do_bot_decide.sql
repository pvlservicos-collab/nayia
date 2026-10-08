-- 309 (08/10/2026): A CONSULTA DO BOT DA OLX PASSA A DECIDIR.
-- Pedro: "mudei a forma como vou usar o grok bot da olx, ele vai achar um
-- anúncio, mandar o link e informações pra ti, tu vai checar no banco de dados
-- e vai devolver se temos para ele fechar, e se não temos para ele abordar e a
-- mensagem para ele mandar". E, em seguida: "mensagem personalizada".
--
-- ANTES (258) a consulta devolvia até 10 CANDIDATOS com nota, e quem decidia se
-- era o mesmo imóvel era um agente do lado do bot. AGORA quem decide é o banco,
-- e o bot recebe uma ordem só:
--     acao = "fechar"   -> não manda nada, fecha o anúncio
--     acao = "abordar"  -> manda ao anunciante, sem mudar, o texto de "mensagem"
--
-- "TEMOS" É A MESMA UNIDADE, NÃO O MESMO PRÉDIO. Medido hoje: dos 5.698 imóveis,
-- 3.549 estão em 985 pares (condomínio, área) repetidos, o maior com 40
-- unidades. "Condomínio igual + área igual" (a confiança "alta" da 258) é a
-- mesma PLANTA, e fechar por ela jogaria fora justamente o proprietário novo
-- dos condomínios em que a gente trabalha. Por isso (crm_anuncio_mesma_unidade):
--   link     mesmo link ou mesmo id do portal
--   dono     mesmo lugar (condomínio igual, rua ou CEP) + o nome do anunciante é
--            o do proprietário que está no cadastro + área em 3% ou preço em 2%
--   unidade  imóvel nosso que está NO MERCADO + mesmo lugar + preço em 2% + área
--            em 3% (anúncio sem área: os quartos iguais). Sem condomínio nem
--            rua: bairro + tipo + área + preço + quartos, todos.
--   Área mais de 10% diferente ou número de quartos diferente: não é a mesma.
-- Vendido, alugado ou removido só fecha por link ou pelo nome do dono: o preço
-- de um imóvel que saiu do mercado não prova nada sobre o anúncio de hoje.
--
-- TAMBÉM FECHA, SEM MENSAGEM (a ordem de 07/10 para a captação, 308: "não é
-- para sair nada para corretor nem parceiro"):
--   o telefone do anúncio já é de um proprietário nosso;
--   o anunciante é corretor: telefone na lista de corretores, CRECI no texto,
--   nome de imobiliária, ou conta marcada como profissional pelo portal;
--   o anúncio diz que não quer corretor nem imobiliária.
--
-- O MESMO ANÚNCIO NUNCA RECEBE A MENSAGEM DUAS VEZES. A entrega fica gravada
-- (privado.anuncio_consulta). Pergunta repetida em até 10 minutos devolve a
-- MESMA mensagem (o bot pode não ter recebido a resposta); depois disso volta
-- "fechar", motivo ja_abordado. O prompt o modelo esquece; a parede não.
--
-- FALHA NUNCA VIRA "ABORDAR": se a busca falhar, se faltar o mínimo para
-- comparar (preço, tipo ou título, bairro ou condomínio) ou se o texto da
-- mensagem estiver quebrado, volta consulta_ok = false e nada é gravado.
--
-- O TEXTO MORA NUMA TABELA (anuncio_abordagem_texto), não no código: a mensagem
-- e a frase do cliente para cada tipo de imóvel. Trocar é um UPDATE.
--   {saudacao}   bom dia / boa tarde / boa noite, pela hora de MANAUS
--   {cliente}    a frase do cliente, escolhida pelo tipo e pelos quartos
--   {onde}       "na região de <bairro>" com o nome que o catálogo usa
--   {anunciando} "vendendo" (venda) ou "anunciando" (aluguel)
--
-- A TABELA DAS CONSULTAS FICA NO SCHEMA `privado`: tem nome e telefone de
-- anunciante, e a /api/tabelas do site lê o public inteiro.
--
-- `"teste": true` no pedido decide e NÃO grava: é o teste de conexão do bot. E a
-- resposta de teste não é ordem (acao = "nenhuma"; o que seria feito vem em
-- `seria`): sem gravar não há parede, então não pode haver mensagem para mandar.
--
-- crm_imovel_candidatos (258) não muda: continua servindo a aba Imóveis da OLX
-- Bot (260) e é ela que acha os candidatos aqui dentro.
BEGIN;
SET LOCAL lock_timeout = '3s';

-- 1. OS TEXTOS ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.anuncio_abordagem_texto (
  chave         text PRIMARY KEY,
  texto         text NOT NULL,
  nota          text,
  atualizado_em timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE public.anuncio_abordagem_texto IS
  '309: a mensagem que o bot da OLX manda ao anunciante e a frase do cliente por tipo de imóvel';

INSERT INTO public.anuncio_abordagem_texto (chave, texto, nota) VALUES
('mensagem', $t$Oii, {saudacao}! Me chamo Nay Mendes, da Imob Easy.

Tenho {cliente} {onde} e o seu entrou no perfil deles. Tem o que eles procuram.

Posso apresentar pra eles?

Se gostarem, eu cuido de tudo: visita, documentação, contrato e assinatura. Sem exclusividade, você continua {anunciando} aqui no OLX.

Me passa seu nome e seu WhatsApp que a gente conversa melhor.$t$,
 'O texto inteiro (Pedro, 08/10). Marcadores: {saudacao} {cliente} {onde} {anunciando}.'),
('cliente_apartamento_grande', 'uma família procurando um apartamento maior', 'apartamento de 3 quartos ou mais (frase do Pedro, 08/10)'),
('cliente_apartamento',        'um casal procurando um apartamento',          'apartamento de até 2 quartos, ou sem os quartos no anúncio'),
('cliente_casa',               'uma família procurando uma casa',             'casa, sobrado, casa de condomínio'),
('cliente_comercial',          'uma empresa procurando um ponto comercial',   'sala, loja, galpão, prédio'),
('cliente_terreno',            'uma família procurando um terreno',           'terreno, lote, chácara'),
('cliente_outro',              'uma família procurando um imóvel',            'quando o tipo não deu para entender')
ON CONFLICT (chave) DO NOTHING;

-- 2. AS CONSULTAS (o que o bot perguntou e o que foi respondido) ---------------
CREATE TABLE IF NOT EXISTS privado.anuncio_consulta (
  id                bigserial PRIMARY KEY,
  link              text NOT NULL,
  link_normal       text NOT NULL UNIQUE,
  portal            text NOT NULL DEFAULT 'olx',
  id_anuncio        text,
  anunciante_nome   text,
  anunciante_perfil text,
  telefone          text,
  dados             jsonb NOT NULL,
  acao              text NOT NULL CHECK (acao IN ('fechar', 'abordar')),
  motivo            text NOT NULL,
  codigo            integer,
  parecido          jsonb,
  mensagem          text,
  entregue_em       timestamptz,
  pedidos           integer NOT NULL DEFAULT 1,
  recebido_em       timestamptz NOT NULL DEFAULT now(),
  atualizado_em     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS anuncio_consulta_id ON privado.anuncio_consulta (portal, id_anuncio) WHERE id_anuncio IS NOT NULL;
CREATE INDEX IF NOT EXISTS anuncio_consulta_acao ON privado.anuncio_consulta (acao, recebido_em DESC);
COMMENT ON TABLE privado.anuncio_consulta IS
  '309: cada anúncio que o bot da OLX consultou, a decisão (fechar/abordar), o motivo e a mensagem entregue';
COMMENT ON COLUMN privado.anuncio_consulta.codigo IS 'o imóvel nosso, quando a resposta foi "já temos"';
COMMENT ON COLUMN privado.anuncio_consulta.parecido IS 'o candidato mais parecido do catálogo, para gente conferir depois';
COMMENT ON COLUMN privado.anuncio_consulta.entregue_em IS 'quando a mensagem foi entregue ao bot; depois de 10 min o anúncio não recebe outra';

-- 3. O NOME EM PALAVRAS (para comparar anunciante com proprietário) ------------
CREATE OR REPLACE FUNCTION public.crm_anuncio_nome_palavras(p text)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- sem acento, sem tratamento (sr, dra, dona) e sem as palavras de duas letras
  SELECT coalesce(array_agg(t.w ORDER BY t.n), '{}')
    FROM regexp_split_to_table(nay_sem_acento(lower(coalesce(p, ''))), '[^a-z]+') WITH ORDINALITY t(w, n)
   WHERE length(t.w) >= 3
     AND t.w <> ALL (ARRAY['sra', 'dra', 'dona', 'dos', 'das', 'prop', 'proprietario', 'proprietaria',
                           'senhor', 'senhora', 'doutor', 'doutora']);
$function$;

-- 4. É A MESMA UNIDADE? -------------------------------------------------------
-- Recebe o anúncio e a resposta da crm_imovel_candidatos; devolve o imóvel nosso
-- que é a mesma unidade ({codigo, nivel, status, sinais}) ou NULL.
CREATE OR REPLACE FUNCTION public.crm_anuncio_mesma_unidade(p jsonb, p_cand jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH a AS (
    SELECT crm_anuncio_numero(p -> 'preco') AS preco,
           crm_anuncio_numero(p -> 'area_m2') AS area,
           crm_anuncio_numero(p -> 'quartos') AS quartos,
           nullif(p_cand -> 'entendido' ->> 'condominio', '') AS condo,
           crm_anuncio_nome_palavras(p ->> 'anunciante_nome') AS nome
  ),
  c AS (
    SELECT (x ->> 'id_imovel')::int AS codigo, coalesce((x ->> 'score')::int, 0) AS score,
           coalesce(x -> 'campos_que_bateram', '[]'::jsonb) AS bateu,
           (x -> 'dados' ->> 'preco')::numeric AS preco,
           (x -> 'dados' ->> 'area_m2')::numeric AS area,
           (x -> 'dados' ->> 'quartos')::numeric AS quartos,
           coalesce((x -> 'dados' ->> 'no_mercado')::boolean, false) AS no_mercado,
           x -> 'dados' ->> 'status' AS status
      FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_cand -> 'candidatos') = 'array'
                                     THEN p_cand -> 'candidatos' ELSE '[]'::jsonb END) x
     WHERE (x ->> 'id_imovel') ~ '^[0-9]+$'
  ),
  s AS (
    SELECT c.codigo, c.score, c.status, c.no_mercado,
           c.bateu ? 'link' AS m_link,
           ((a.condo IS NOT NULL AND n.nucleo IS NOT NULL
             AND (n.nucleo = a.condo OR crm_anuncio_palavras(n.nucleo) = crm_anuncio_palavras(a.condo)))
            OR c.bateu ? 'endereco' OR c.bateu ? 'cep') AS m_lugar,
           c.bateu ? 'bairro' AS m_bairro,
           c.bateu ? 'tipo' AS m_tipo,
           (a.area IS NOT NULL AND c.area IS NOT NULL AND abs(c.area - a.area) <= a.area * 0.03) AS m_area,
           (a.area IS NOT NULL AND c.area IS NOT NULL AND abs(c.area - a.area) > a.area * 0.10) AS x_area,
           (a.area IS NULL OR c.area IS NULL) AS sem_area,
           (a.preco IS NOT NULL AND c.preco IS NOT NULL AND abs(c.preco - a.preco) <= a.preco * 0.02) AS m_preco,
           (a.quartos IS NOT NULL AND c.quartos IS NOT NULL AND c.quartos = a.quartos) AS m_quartos,
           (a.quartos IS NOT NULL AND c.quartos IS NOT NULL AND c.quartos <> a.quartos) AS x_quartos,
           (a.nome[1] IS NOT NULL AND d.nome[1] = a.nome[1]
             AND (cardinality(a.nome) = 1 OR cardinality(d.nome) = 1 OR a.nome[2:] && d.nome[2:])) AS m_nome
      FROM c
      CROSS JOIN a
      JOIN imoveis i ON i.codigo = c.codigo
      LEFT JOIN imovel_privado ip ON ip.codigo = i.codigo
      LEFT JOIN proprietarios pr ON pr.id = coalesce(i.proprietario_id, ip.proprietario_id)
      CROSS JOIN LATERAL (SELECT nullif(nay_sem_acento(lower(nai_condominio_nucleo(coalesce(i.condominio_nome, '')))), '') AS nucleo) n
      CROSS JOIN LATERAL (SELECT crm_anuncio_nome_palavras(pr.nome) AS nome) d
  ),
  v AS (
    SELECT s.*,
           CASE WHEN s.m_link THEN 'link'
                WHEN s.x_area OR s.x_quartos THEN NULL
                WHEN s.m_lugar AND s.m_nome AND (s.m_area OR s.m_preco) THEN 'dono'
                WHEN s.no_mercado AND s.m_lugar AND s.m_preco AND (s.m_area OR (s.sem_area AND s.m_quartos)) THEN 'unidade'
                WHEN s.no_mercado AND s.m_bairro AND s.m_tipo AND s.m_area AND s.m_preco AND s.m_quartos THEN 'unidade'
           END AS nivel
      FROM s
  )
  SELECT jsonb_build_object('codigo', v.codigo, 'nivel', v.nivel, 'status', v.status,
           'sinais', to_jsonb(array_remove(ARRAY[
              CASE WHEN v.m_link THEN 'link' END,
              CASE WHEN v.m_lugar THEN 'lugar' END,
              CASE WHEN v.m_nome THEN 'nome do dono' END,
              CASE WHEN v.m_area THEN 'area' END,
              CASE WHEN v.m_preco THEN 'preco' END,
              CASE WHEN v.m_quartos THEN 'quartos' END,
              CASE WHEN v.m_bairro THEN 'bairro' END], NULL)))
    FROM v
   WHERE v.nivel IS NOT NULL
   ORDER BY array_position(ARRAY['link', 'dono', 'unidade'], v.nivel), v.score DESC, v.codigo
   LIMIT 1;
$function$;

-- 5. A MENSAGEM ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_anuncio_mensagem(p jsonb, p_finalidade text DEFAULT NULL, p_agora timestamptz DEFAULT now())
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  v_hora    int := extract(hour FROM p_agora AT TIME ZONE 'America/Manaus');
  v_fam     text := coalesce(crm_anuncio_familia(p ->> 'tipo'), crm_anuncio_familia(p ->> 'titulo'));
  v_quartos numeric := crm_anuncio_numero(p -> 'quartos');
  v_veio    text := btrim(coalesce(p ->> 'bairro', ''));
  v_bairro  text;
  v_cliente text;
  v_msg     text;
BEGIN
  SELECT t.texto INTO v_msg FROM anuncio_abordagem_texto t WHERE t.chave = 'mensagem';
  SELECT t.texto INTO v_cliente FROM anuncio_abordagem_texto t
   WHERE t.chave = CASE WHEN v_fam = 'apartamento' AND v_quartos >= 3 THEN 'cliente_apartamento_grande'
                        WHEN v_fam = 'apartamento' THEN 'cliente_apartamento'
                        WHEN v_fam = 'casa' THEN 'cliente_casa'
                        WHEN v_fam = 'comercial' THEN 'cliente_comercial'
                        WHEN v_fam = 'terreno' THEN 'cliente_terreno'
                        ELSE 'cliente_outro' END;
  IF coalesce(btrim(v_msg), '') = '' OR coalesce(btrim(v_cliente), '') = '' THEN RETURN NULL; END IF;

  -- o bairro com o nome que o catálogo usa (o bot pode mandar "nossa-senhora-das-gracas");
  -- fora do catálogo, só se veio escrito como nome (com maiúscula, sem traço de endereço)
  IF v_veio <> '' THEN
    SELECT b.bairro INTO v_bairro FROM bairro_normal b WHERE b.normal = nay_normalizar_lugar(v_veio, true) LIMIT 1;
    IF v_bairro IS NULL AND v_veio ~ '^[A-ZÀ-Ý]' AND v_veio !~ '[-_/|,;:()0-9]' AND length(v_veio) BETWEEN 3 AND 40 THEN
      v_bairro := v_veio;
    END IF;
  END IF;

  v_msg := replace(v_msg, '{saudacao}', CASE WHEN v_hora BETWEEN 5 AND 11 THEN 'bom dia'
                                              WHEN v_hora BETWEEN 12 AND 17 THEN 'boa tarde' ELSE 'boa noite' END);
  v_msg := replace(v_msg, '{cliente}', btrim(v_cliente));
  v_msg := replace(v_msg, '{onde}', CASE WHEN v_bairro IS NOT NULL THEN 'na região de ' || v_bairro ELSE 'na sua região' END);
  v_msg := replace(v_msg, '{anunciando}', CASE WHEN p_finalidade = 'venda' THEN 'vendendo' ELSE 'anunciando' END);
  -- marcador que sobrou é texto quebrado: melhor não mandar nada
  IF v_msg ~ '[{}]' OR length(v_msg) < 80 THEN RETURN NULL; END IF;
  RETURN v_msg;
END
$function$;

-- 6. A RESPOSTA DE TESTE NÃO É ORDEM -------------------------------------------
-- Com "teste": true nada é gravado; então a resposta também não pode servir de
-- ordem (senão o bot mandaria mensagem sem a parede do "já abordado"). Sai
-- acao = "nenhuma"; o que seria feito vai em `seria` e o texto em `mensagem_exemplo`.
CREATE OR REPLACE FUNCTION public.crm_anuncio_resposta_de_teste(r jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT jsonb_strip_nulls((r - 'acao' - 'mensagem' - 'id_consulta' - 'explicacao')
         || jsonb_build_object('teste', true, 'acao', 'nenhuma', 'seria', r ->> 'acao',
                               'mensagem_exemplo', r ->> 'mensagem',
                               'explicacao', 'Teste de conexão: nada foi gravado e isto NÃO é ordem. Em `seria` está o que eu responderia de verdade.'));
$function$;

-- 7. A DECISÃO ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.crm_anuncio_decidir(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
DECLARE
  JANELA   CONSTANT interval := interval '10 minutes';
  FECHE    CONSTANT text := ' Feche o anúncio, não mande mensagem.';
  v_link   text := btrim(coalesce(p ->> 'link', ''));
  v_normal text := crm_anuncio_link_normal(p ->> 'link');
  v_portal text := left(lower(coalesce(nullif(btrim(p ->> 'portal'), ''), 'olx')), 30);
  v_id_an  text;
  v_teste  boolean := coalesce(p -> 'teste' = 'true'::jsonb OR lower(btrim(coalesce(p ->> 'teste', ''))) IN ('true', 'sim'), false);
  v_prof   boolean := coalesce(p -> 'profissional' = 'true'::jsonb OR lower(btrim(coalesce(p ->> 'profissional', ''))) IN ('true', 'sim'), false);
  v_fone   text := nai_chave(p ->> 'telefone');
  v_nome   text := nay_sem_acento(lower(coalesce(p ->> 'anunciante_nome', '')));
  v_texto  text := nay_sem_acento(lower(concat_ws(E'\n', p ->> 'titulo', p ->> 'descricao')));
  v_falta  text[] := '{}';
  v_dados  jsonb;
  v_ja     privado.anuncio_consulta;
  v_cand   jsonb;
  v_un     jsonb;
  v_acao   text := 'fechar';
  v_motivo text;
  v_expl   text;
  v_cod    integer;
  v_msg    text;
  v_linha  bigint;
  v_r      jsonb;
BEGIN
  IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN
    RETURN jsonb_build_object('consulta_ok', false, 'ok', false, 'codigo_erro', 'formato',
                              'erro', 'Mande um objeto JSON com os campos do anúncio.');
  END IF;
  IF v_normal IS NULL OR v_normal !~ '^[a-z0-9.-]+\.[a-z]{2,}/' THEN
    RETURN jsonb_build_object('consulta_ok', false, 'ok', false, 'codigo_erro', 'faltam_campos', 'faltam', jsonb_build_array('link'),
                              'erro', 'Faltou o "link" do anúncio.');
  END IF;
  v_dados := p - 'hora' - 'cifrado' - 'assinatura' - 'teste';
  IF length(v_dados::text) > 60000 THEN
    RETURN jsonb_build_object('consulta_ok', false, 'ok', false, 'codigo_erro', 'grande_demais',
                              'erro', 'Os dados passaram de 60 mil caracteres: encurte a descrição.');
  END IF;
  v_id_an := coalesce(nullif(regexp_replace(coalesce(p ->> 'id_anuncio', ''), '\D', '', 'g'), ''), crm_anuncio_id_do_link(v_link));

  -- duas perguntas do mesmo anúncio ao mesmo tempo: uma espera a outra
  PERFORM pg_advisory_xact_lock(hashtext('anuncio_consulta:' || v_normal));
  SELECT * INTO v_ja FROM privado.anuncio_consulta c
   WHERE c.link_normal = v_normal OR (v_id_an IS NOT NULL AND c.portal = v_portal AND c.id_anuncio = v_id_an)
   ORDER BY (c.link_normal = v_normal) DESC, c.id LIMIT 1;

  -- A PAREDE: a mensagem deste anúncio já foi entregue
  IF v_ja.id IS NOT NULL AND v_ja.acao = 'abordar' THEN
    IF NOT v_teste THEN
      UPDATE privado.anuncio_consulta SET pedidos = pedidos + 1, atualizado_em = now() WHERE id = v_ja.id;
    END IF;
    IF v_ja.entregue_em > now() - JANELA THEN
      v_r := jsonb_build_object('consulta_ok', true, 'acao', 'abordar', 'temos', false, 'motivo', 'nao_temos',
        'repetido', true, 'id_consulta', v_ja.id::text, 'mensagem', v_ja.mensagem,
        'explicacao', 'É a mesma mensagem que entreguei há pouco para este anúncio. Mande UMA vez só, sem mudar o texto.');
    ELSE
      v_r := jsonb_build_object('consulta_ok', true, 'acao', 'fechar', 'temos', false, 'motivo', 'ja_abordado',
        'id_consulta', v_ja.id::text,
        'explicacao', 'A mensagem deste anúncio já foi entregue em '
                      || to_char(v_ja.entregue_em AT TIME ZONE 'America/Manaus', 'DD/MM "às" HH24:MI')
                      || '. Feche o anúncio, não mande de novo.');
    END IF;
    RETURN CASE WHEN v_teste THEN crm_anuncio_resposta_de_teste(v_r) ELSE v_r END;
  END IF;

  v_cand := crm_imovel_candidatos(p);
  IF coalesce((v_cand ->> 'consulta_ok')::boolean, false) IS NOT TRUE THEN
    RETURN jsonb_build_object('consulta_ok', false, 'ok', false, 'codigo_erro', 'falha',
                              'erro', coalesce(v_cand ->> 'erro', 'a busca no catálogo não respondeu'));
  END IF;
  v_un := crm_anuncio_mesma_unidade(p, v_cand);

  IF v_un IS NOT NULL THEN
    v_cod := (v_un ->> 'codigo')::int;
    v_motivo := 'ja_temos';
    v_expl := 'Já temos este imóvel no cadastro (código ' || v_cod || ').' || FECHE;
  ELSIF coalesce((v_cand -> 'entendido' ->> 'telefone_conhecido')::boolean, false) THEN
    v_motivo := 'proprietario_ja_e_nosso';
    v_expl := 'O telefone do anúncio já é de um proprietário do nosso cadastro.' || FECHE;
  ELSIF v_prof
     OR (v_fone IS NOT NULL AND EXISTS (SELECT 1 FROM corretores k WHERE nai_chave(k.telefone) = v_fone))
     OR v_texto ~ '\mcreci\M' OR v_nome ~ '\mcreci\M'
     OR v_nome ~ '(imob|imovel|imoveis|corretor|broker|realty|administradora|negocios imobiliarios)'
     OR nai_dono_e_parceiro(p ->> 'anunciante_nome') THEN
    v_motivo := 'corretor';
    v_expl := 'O anunciante é corretor ou imobiliária.' || FECHE;
  ELSIF v_texto ~ '(dispens[oa](mos)?|nao (aceito|aceitamos|atendo|atendemos|quero|queremos|trabalho com|trabalhamos com)|favor nao)[^.!?\n]{0,30}(corretor|imobiliaria|intermediari)'
     OR v_texto ~ '\msem (corretor|corretores|imobiliaria|imobiliarias|intermediario|intermediarios|intermediacao)\M' THEN
    v_motivo := 'dispensa_imobiliaria';
    v_expl := 'O anúncio diz que não quer corretor nem imobiliária.' || FECHE;
  ELSE
    -- NÃO TEMOS. Só aborda quem deu para comparar de verdade.
    IF crm_anuncio_numero(p -> 'preco') IS NULL THEN v_falta := array_append(v_falta, 'preco'); END IF;
    IF coalesce(crm_anuncio_familia(p ->> 'tipo'), crm_anuncio_familia(p ->> 'titulo')) IS NULL THEN
      v_falta := array_append(v_falta, 'tipo (ou titulo)');
    END IF;
    IF coalesce(btrim(p ->> 'bairro'), '') = '' AND coalesce(btrim(p ->> 'condominio_nome'), '') = '' THEN
      v_falta := array_append(v_falta, 'bairro (ou condominio_nome)');
    END IF;
    IF array_length(v_falta, 1) > 0 THEN
      RETURN jsonb_build_object('consulta_ok', false, 'ok', false, 'codigo_erro', 'faltam_campos', 'faltam', to_jsonb(v_falta),
        'erro', 'Não decidi: falta ' || array_to_string(v_falta, ', ') || '. Leia no anúncio e consulte de novo. Não mande mensagem sem a resposta.');
    END IF;
    v_msg := crm_anuncio_mensagem(p, v_cand -> 'entendido' ->> 'finalidade');
    IF v_msg IS NULL THEN
      RETURN jsonb_build_object('consulta_ok', false, 'ok', false, 'codigo_erro', 'texto',
        'erro', 'O texto da mensagem está com problema do nosso lado. Não mande nada e avise o Pedro no chat.');
    END IF;
    v_acao := 'abordar';
    v_motivo := 'nao_temos';
    v_expl := 'Não temos este imóvel. Mande ao anunciante exatamente o texto de "mensagem", sem mudar nada, uma vez só.';
  END IF;

  IF NOT v_teste THEN
    IF v_ja.id IS NOT NULL THEN
      UPDATE privado.anuncio_consulta c
         SET link = left(v_link, 600), id_anuncio = coalesce(v_id_an, c.id_anuncio),
             anunciante_nome = coalesce(left(nullif(btrim(p ->> 'anunciante_nome'), ''), 120), c.anunciante_nome),
             anunciante_perfil = coalesce(left(nullif(btrim(p ->> 'anunciante_perfil'), ''), 600), c.anunciante_perfil),
             telefone = coalesce(left(nullif(btrim(p ->> 'telefone'), ''), 40), c.telefone),
             dados = v_dados, acao = v_acao, motivo = v_motivo, codigo = v_cod,
             parecido = coalesce(v_un, (v_cand -> 'candidatos' -> 0) - 'dados' - 'campos_divergentes'),
             mensagem = v_msg, entregue_em = CASE WHEN v_acao = 'abordar' THEN now() END,
             pedidos = c.pedidos + 1, atualizado_em = now()
       WHERE c.id = v_ja.id
      RETURNING c.id INTO v_linha;
    ELSE
      INSERT INTO privado.anuncio_consulta (link, link_normal, portal, id_anuncio, anunciante_nome, anunciante_perfil, telefone,
                                            dados, acao, motivo, codigo, parecido, mensagem, entregue_em)
      VALUES (left(v_link, 600), v_normal, v_portal, v_id_an,
              left(nullif(btrim(p ->> 'anunciante_nome'), ''), 120), left(nullif(btrim(p ->> 'anunciante_perfil'), ''), 600),
              left(nullif(btrim(p ->> 'telefone'), ''), 40),
              v_dados, v_acao, v_motivo, v_cod,
              coalesce(v_un, (v_cand -> 'candidatos' -> 0) - 'dados' - 'campos_divergentes'),
              v_msg, CASE WHEN v_acao = 'abordar' THEN now() END)
      RETURNING id INTO v_linha;
    END IF;
  END IF;

  v_r := jsonb_strip_nulls(jsonb_build_object(
    'consulta_ok', true, 'acao', v_acao, 'temos', v_motivo = 'ja_temos', 'motivo', v_motivo, 'explicacao', v_expl,
    'id_imovel', v_cod::text, 'mensagem', v_msg, 'id_consulta', v_linha::text));
  RETURN CASE WHEN v_teste THEN crm_anuncio_resposta_de_teste(v_r) ELSE v_r END;
EXCEPTION WHEN others THEN
  -- nunca resposta vazia nem "abordar" por engano: falha é falha
  RETURN jsonb_build_object('consulta_ok', false, 'ok', false, 'codigo_erro', 'falha', 'erro', 'falha na consulta: ' || SQLERRM);
END
$function$;

REVOKE ALL ON FUNCTION crm_anuncio_decidir(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_anuncio_decidir(jsonb) TO nay_disparo;
COMMIT;
