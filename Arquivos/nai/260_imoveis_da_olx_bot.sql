-- 260 (02/10/2026): IMÓVEIS DA OLX BOT -- o grokbot cadastra, um humano aprova.
-- Pedro: "também quero um webhook estilo cadastro de corretor... o grok vai
-- enviar nome de corretor, número dele, link do imóvel, dados do imóvel completo
-- para nosso cadastro, e esses imóveis vão vir para uma nova aba no site...
-- criando uma aba ao lado de Captação OLX, Imóveis da OLX Bot... vai armazenar
-- esses imóveis para aprovação manual humana... ele só vai enviar os que tiverem
-- autorização clara do proprietário; se ele ainda não deu autorização, não envia".
--
-- O QUE ENTRA AQUI NÃO É IMÓVEL AINDA. Fica numa caixa de espera
-- (privado.olx_bot_imovel) até alguém clicar em Aprovar na aba; só aí vira
-- pré-cadastro (Rascunho) no catálogo. Nada do que o bot manda chega ao site ou
-- à Nay sem passar por uma pessoa.
--
-- A AUTORIZAÇÃO DO PROPRIETÁRIO É PAREDE, NÃO SÓ INSTRUÇÃO. O prompt do bot diz
-- para não mandar sem autorização -- e o banco recusa quem mandar assim mesmo:
-- `autorizacao_proprietario` tem de ser `true` E `autorizacao_como` tem de
-- contar como ela foi dada. Instrução o modelo esquece; a parede não.
--
-- A TABELA MORA NO SCHEMA `privado`, não no public: ela tem telefone de corretor
-- e de proprietário, e a /api/tabelas do site lê o public inteiro sem senha.
--
-- O MESMO ANÚNCIO NÃO ENTRA DUAS VEZES: a chave é o link normalizado. Mandar de
-- novo um que ainda está pendente ATUALIZA os dados (o bot pode ter completado
-- o que faltava); um que já foi aprovado ou descartado volta dizendo isso.
--
-- CADA ENVIO JÁ CHEGA COM OS PARECIDOS: a consulta da 258 roda aqui dentro e o
-- resultado fica guardado, para quem aprova ver "este parece o 4679" sem ter de
-- procurar.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.olx_bot_imovel (
  id                  bigserial PRIMARY KEY,
  estado              text NOT NULL DEFAULT 'pendente' CHECK (estado IN ('pendente', 'aprovado', 'descartado')),
  link                text NOT NULL,
  link_normal         text NOT NULL UNIQUE,
  portal              text,
  id_anuncio          text,
  corretor_nome       text NOT NULL,
  corretor_telefone   text NOT NULL,
  proprietario_nome   text,
  proprietario_telefone text,
  autorizacao_como    text NOT NULL,
  dados               jsonb NOT NULL,
  fotos               text[] NOT NULL DEFAULT '{}',
  candidatos          jsonb,
  envios              integer NOT NULL DEFAULT 1,
  recebido_em         timestamptz NOT NULL DEFAULT now(),
  atualizado_em       timestamptz NOT NULL DEFAULT now(),
  codigo              integer,
  decidido_por        text,
  decidido_em         timestamptz,
  motivo              text
);
CREATE INDEX IF NOT EXISTS olx_bot_imovel_estado ON privado.olx_bot_imovel (estado, recebido_em DESC);
COMMENT ON TABLE privado.olx_bot_imovel IS
  '260: o que o grokbot mandou cadastrar, esperando um humano aprovar na aba Imóveis da OLX Bot';

-- a aba do site (papel nay_site_escrita) lista, aprova e descarta
GRANT SELECT, UPDATE ON privado.olx_bot_imovel TO nay_site_escrita;
-- aprovar registra o link do anúncio no imóvel criado (258)
GRANT SELECT, INSERT ON public.imovel_anuncio TO nay_site_escrita;
GRANT USAGE ON SEQUENCE public.imovel_anuncio_id_seq TO nay_site_escrita;

CREATE OR REPLACE FUNCTION public.crm_olx_bot_receber(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
DECLARE
  v_link   text := btrim(coalesce(p ->> 'link', ''));
  v_normal text := crm_anuncio_link_normal(p ->> 'link');
  v_id_an  text;
  v_nome   text := btrim(coalesce(p ->> 'corretor_nome', ''));
  v_fone   text := btrim(coalesce(p ->> 'corretor_telefone', ''));
  v_como   text := btrim(coalesce(p ->> 'autorizacao_como', ''));
  v_fotos  text[];
  v_dados  jsonb;
  v_cand   jsonb;
  v_ja     privado.olx_bot_imovel;
  v_novo   bigint;
  v_falta  text[] := '{}';
BEGIN
  IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN
    RETURN jsonb_build_object('ok', false, 'codigo_erro', 'formato', 'erro', 'mande um objeto JSON com os campos do imóvel');
  END IF;

  -- 1. A PAREDE DA AUTORIZAÇÃO. Só `true` de verdade (ou "sim"/"true" escrito):
  --    nulo, falso, "acho que sim" e campo ausente são todos "não".
  --    O coalesce é a parede: campo ausente dá NULL, e `IF NOT NULL` não entra --
  --    no ensaio, um envio SEM o campo passava por aqui e só era barrado adiante.
  IF NOT coalesce(p -> 'autorizacao_proprietario' = 'true'::jsonb
                  OR lower(btrim(coalesce(p ->> 'autorizacao_proprietario', ''))) IN ('true', 'sim', 'yes'), false) THEN
    RETURN jsonb_build_object('ok', false, 'codigo_erro', 'sem_autorizacao',
      'erro', 'Não cadastrei: falta a autorização clara do proprietário (autorizacao_proprietario: true). '
           || 'Sem ela, não envie este imóvel. Se estiver em dúvida, mande um lembrete ao Pedro no chat.');
  END IF;
  IF length(v_como) < 10 THEN
    RETURN jsonb_build_object('ok', false, 'codigo_erro', 'sem_autorizacao',
      'erro', 'Não cadastrei: diga em "autorizacao_como" como e quando o proprietário autorizou '
           || '(ex.: "respondeu SIM no WhatsApp em 02/10 às 14h"). Sem isso, não envie; na dúvida, lembre o Pedro no chat.');
  END IF;

  -- 2. o mínimo para alguém conseguir aprovar
  IF v_normal IS NULL OR v_normal !~ '^[a-z0-9.-]+\.[a-z]{2,}/' THEN v_falta := array_append(v_falta, 'link'); END IF;
  IF length(v_nome) < 2 THEN v_falta := array_append(v_falta, 'corretor_nome'); END IF;
  IF nai_chave(v_fone) IS NULL THEN v_falta := array_append(v_falta, 'corretor_telefone (com DDD)'); END IF;
  IF array_length(v_falta, 1) > 0 THEN
    RETURN jsonb_build_object('ok', false, 'codigo_erro', 'faltam_campos', 'faltam', to_jsonb(v_falta),
      'erro', 'Não cadastrei: falta ' || array_to_string(v_falta, ', ') || '.');
  END IF;

  v_id_an := coalesce(nullif(regexp_replace(coalesce(p ->> 'id_anuncio', ''), '\D', '', 'g'), ''), crm_anuncio_id_do_link(v_link));
  -- só foto em https, sem repetir, até 40
  SELECT coalesce(array_agg(x.u ORDER BY x.n), '{}') INTO v_fotos FROM (
    SELECT f.u, min(f.n) AS n FROM jsonb_array_elements_text(
      CASE WHEN jsonb_typeof(p -> 'fotos') = 'array' THEN p -> 'fotos' ELSE '[]'::jsonb END) WITH ORDINALITY f(u, n)
     WHERE f.u ~ '^https://' GROUP BY f.u ORDER BY 2 LIMIT 40) x;
  -- o que fica guardado em `dados`: o imóvel. Pessoas e autorização têm coluna própria.
  v_dados := p - 'corretor_nome' - 'corretor_telefone' - 'proprietario_nome' - 'proprietario_telefone'
               - 'autorizacao_proprietario' - 'autorizacao_como' - 'fotos' - 'hora' - 'cifrado' - 'assinatura';
  IF length(v_dados::text) > 60000 THEN
    RETURN jsonb_build_object('ok', false, 'codigo_erro', 'grande_demais', 'erro', 'Os dados passaram de 60 mil caracteres: encurte a descrição.');
  END IF;

  SELECT * INTO v_ja FROM privado.olx_bot_imovel o WHERE o.link_normal = v_normal FOR UPDATE;

  -- REENVIO COMPLETA, NÃO APAGA: o bot pode mandar de novo só o que mudou (o
  -- preço, uma foto). O que veio preenchido entra por cima; o que veio nulo ou
  -- não veio fica como estava. No ensaio, um reenvio só com o preço apagava o
  -- proprietário e o resto dos dados.
  IF v_ja.id IS NOT NULL THEN
    v_dados := v_ja.dados || jsonb_strip_nulls(v_dados);
  END IF;

  -- 3. os parecidos do catálogo, para quem aprova (a consulta da 258)
  v_cand := crm_imovel_candidatos(v_dados || jsonb_build_object('link', v_link,
              'telefone', coalesce(nullif(btrim(coalesce(p ->> 'proprietario_telefone', '')), ''), v_ja.proprietario_telefone)));
  IF coalesce((v_cand ->> 'consulta_ok')::boolean, false) IS NOT TRUE THEN v_cand := NULL; END IF;
  IF v_ja.id IS NOT NULL AND v_ja.estado <> 'pendente' THEN
    RETURN jsonb_build_object('ok', true, 'id_cadastro', v_ja.id::text, 'situacao', v_ja.estado, 'ja_existia', true,
      'id_imovel', v_ja.codigo::text,
      'mensagem', CASE v_ja.estado
        WHEN 'aprovado' THEN 'Este anúncio já foi aprovado' || coalesce(' e virou o imóvel ' || v_ja.codigo, '') || '. Não mandei de novo.'
        ELSE 'Este anúncio já foi descartado por uma pessoa' || coalesce(' (' || v_ja.motivo || ')', '') || '. Não mandei de novo.' END);
  END IF;

  IF v_ja.id IS NOT NULL THEN
    UPDATE privado.olx_bot_imovel o
       SET link = left(v_link, 600), portal = left(lower(coalesce(nullif(btrim(p ->> 'portal'), ''), o.portal, 'olx')), 30),
           id_anuncio = v_id_an, corretor_nome = left(v_nome, 120), corretor_telefone = left(v_fone, 40),
           proprietario_nome = coalesce(left(nullif(btrim(coalesce(p ->> 'proprietario_nome', '')), ''), 120), o.proprietario_nome),
           proprietario_telefone = coalesce(left(nullif(btrim(coalesce(p ->> 'proprietario_telefone', '')), ''), 40), o.proprietario_telefone),
           autorizacao_como = left(v_como, 600), dados = v_dados,
           fotos = CASE WHEN array_length(v_fotos, 1) > 0 THEN v_fotos ELSE o.fotos END,
           candidatos = v_cand, envios = o.envios + 1, atualizado_em = now()
     WHERE o.id = v_ja.id;
    v_novo := v_ja.id;
  ELSE
    INSERT INTO privado.olx_bot_imovel (link, link_normal, portal, id_anuncio, corretor_nome, corretor_telefone,
                                        proprietario_nome, proprietario_telefone, autorizacao_como, dados, fotos, candidatos)
    VALUES (left(v_link, 600), v_normal, left(lower(coalesce(nullif(btrim(p ->> 'portal'), ''), 'olx')), 30), v_id_an,
            left(v_nome, 120), left(v_fone, 40),
            left(nullif(btrim(coalesce(p ->> 'proprietario_nome', '')), ''), 120),
            left(nullif(btrim(coalesce(p ->> 'proprietario_telefone', '')), ''), 40),
            left(v_como, 600), v_dados, v_fotos, v_cand)
    RETURNING id INTO v_novo;
  END IF;

  RETURN jsonb_build_object('ok', true, 'id_cadastro', v_novo::text, 'situacao', 'pendente',
    'ja_existia', v_ja.id IS NOT NULL,
    'fotos_recebidas', coalesce(array_length(v_fotos, 1), 0),
    -- o bot fica sabendo se parece com algo que já é nosso
    'parecido_com', CASE WHEN coalesce((v_cand ->> 'melhor_score')::int, 0) >= 45
        THEN jsonb_build_object('id_imovel', v_cand -> 'candidatos' -> 0 ->> 'id_imovel',
                                'score', (v_cand ->> 'melhor_score')::int,
                                'confianca', v_cand -> 'candidatos' -> 0 ->> 'confianca') END,
    'mensagem', CASE WHEN v_ja.id IS NOT NULL THEN 'Atualizei o cadastro que já estava esperando aprovação.'
                     ELSE 'Recebido. Fica esperando a aprovação de uma pessoa da Imob Easy.' END);
EXCEPTION WHEN others THEN
  RETURN jsonb_build_object('ok', false, 'codigo_erro', 'falha', 'erro', 'falha ao receber: ' || SQLERRM);
END
$function$;
COMMENT ON FUNCTION crm_olx_bot_receber(jsonb) IS
  '260: recebe um imóvel do grokbot para aprovação humana. Recusa sem autorização clara do proprietário.';

REVOKE ALL ON FUNCTION crm_olx_bot_receber(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_olx_bot_receber(jsonb) TO nay_disparo;
COMMIT;
