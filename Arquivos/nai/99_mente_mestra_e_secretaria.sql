-- =====================================================================
-- NAI -- 99: a mente mestra e a Nay secretaria (Tel, 22/09/2026)
--
-- Ele: "preciso criar outra nay, e transformar a atual em um fluxo /
-- ferramenta que ja esta pronta, e a nova nay em uma nay geral como uma mente
-- por tras das coisas que vai ler a mensagem e escolher qual ia vai responder,
-- a ia atual de locacao/parceria ou uma ia de secretaria... essa secretaria
-- vai ficar se treinando falando com o tel para responder o cliente, uma ia do
-- 0 com menos contexto que so sabe que ela e secretaria da imobeasy e segue as
-- mesmas regras da outra, mas essa nao tem um fluxo de atendimento em si...
-- por enquanto ela vai comecar com pouco conhecimento e vai perguntando ao tel
-- ate se treinar sozinha."
--
-- COMO FICA
--   A MENTE MESTRA le o bloco inteiro (depois da espera, ja com tudo o que a
--   pessoa digitou) e escolhe quem responde. A Nay de locacao vira UM dos
--   caminhos -- a ferramenta pronta, como ele disse.
--   A SECRETARIA atende o que a de locacao nao atende. Comeca sem saber quase
--   nada: procura no `nai_saber`, e o que nao estiver la ela PERGUNTA ao Tel
--   pela mesa de pendencias que ele ja responde no WhatsApp. A resposta dele
--   vai para o cliente E fica guardada -- e assim ela se treina.
--   O CADASTRO: corretor que oferece imovel (o caso do Luiz Bastos) agora e
--   dela. Ela colhe os dados e as fotos, e o imovel sobe -- sem o contato do
--   corretor junto, como o Tel pediu.
--
-- PARA CLIENTE AS DUAS SAO A NAY. "Secretaria" e nome de bastidor.
--
-- LIGA E DESLIGA em `nai_config.secretaria_ligada`. Nasce DESLIGADA: enquanto
-- estiver assim, nada muda no que esta no ar -- a parede da 97 continua
-- mandando oferta de imovel direto para o Tel.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO nai_config (chave, valor) VALUES ('secretaria_ligada', 'nao')
ON CONFLICT (chave) DO NOTHING;

CREATE OR REPLACE FUNCTION public.nai_secretaria_ligada()
 RETURNS boolean LANGUAGE sql STABLE
AS $function$ SELECT lower(coalesce(nai_cfg('secretaria_ligada', 'nao'), 'nao')) = 'sim'; $function$;

-- 1 ------------------------------------------- QUEM RESPONDEU CADA TURNO
ALTER TABLE nai_turno ADD COLUMN IF NOT EXISTS atendente text NOT NULL DEFAULT 'locacao';

CREATE TABLE IF NOT EXISTS nai_mente (
  id         bigserial PRIMARY KEY,
  turno_id   bigint REFERENCES nai_turno(id) ON DELETE CASCADE,
  atendente  text NOT NULL,
  motivo     text,
  por        text NOT NULL DEFAULT 'mente',   -- 'regra' (barata) ou 'mente' (modelo)
  criado_em  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS nai_mente_turno ON nai_mente (turno_id);

CREATE OR REPLACE FUNCTION public.nai_mente_registrar(p_turno bigint, p_atendente text,
                                                      p_motivo text, p_por text)
 RETURNS text LANGUAGE plpgsql
AS $function$
DECLARE v_at text;
BEGIN
  v_at := CASE WHEN lower(coalesce(p_atendente, '')) = 'secretaria'
                AND nai_secretaria_ligada() THEN 'secretaria' ELSE 'locacao' END;
  UPDATE nai_turno SET atendente = v_at WHERE id = p_turno;
  INSERT INTO nai_mente (turno_id, atendente, motivo, por)
       VALUES (p_turno, v_at, left(coalesce(p_motivo, ''), 300), coalesce(p_por, 'mente'));
  PERFORM nai_anotar(p_turno, 4, 'mente_mestra', 'mudou',
                     'quem responde: ' || v_at || coalesce(' (' || p_motivo || ')', ''));
  RETURN v_at;
END;
$function$;

-- O QUE A REGRA JA SABE, sem gastar modelo: pedido de card, visita, codigo,
-- horario. A mente so e chamada para o que sobra.
CREATE OR REPLACE FUNCTION public.nai_e_assunto_de_locacao(p_texto text)
 RETURNS boolean LANGUAGE sql IMMUTABLE
AS $function$
  SELECT s ~ '\m(foto|fotos|card|codigo|valor|aluguel|venda|visita|visitar|agendar|dispon|quartos?|suite|mobiliad|condominio|bairro|apartamento|casa|imovel|imoveis)\M'
    FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s) x;
$function$;

-- 2 ------------------------------------------------- O QUE ELA JA APRENDEU
CREATE TABLE IF NOT EXISTS nai_saber (
  id            bigserial PRIMARY KEY,
  assunto       text,
  pergunta      text NOT NULL,
  resposta      text NOT NULL,
  ensinado_por  text NOT NULL DEFAULT 'tel',
  pendencia_id  int,
  vezes_usada   int NOT NULL DEFAULT 0,
  ativo         boolean NOT NULL DEFAULT true,
  criado_em     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS nai_saber_trgm ON nai_saber USING gin (pergunta gin_trgm_ops);

CREATE OR REPLACE FUNCTION public.nai_saber_busca(p_texto text)
 RETURNS TABLE(id bigint, resposta text, semelhanca real)
 LANGUAGE sql STABLE
AS $function$
  -- O piso de 0,35 e o mesmo criterio da parecenca de condominio (89): acima
  -- disso e a mesma pergunta escrita de outro jeito; abaixo e outra coisa, e
  -- responder seria inventar.
  SELECT s.id, s.resposta, similarity(lower(unaccent(s.pergunta)), lower(unaccent(coalesce(p_texto, ''))))
    FROM nai_saber s
   WHERE s.ativo
     AND similarity(lower(unaccent(s.pergunta)), lower(unaccent(coalesce(p_texto, '')))) >= 0.35
   ORDER BY 3 DESC LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION public.nai_saber_guardar(p_pergunta text, p_resposta text,
                                                    p_quem text, p_pendencia int)
 RETURNS bigint LANGUAGE plpgsql
AS $function$
DECLARE v_id bigint;
BEGIN
  IF btrim(coalesce(p_pergunta, '')) = '' OR btrim(coalesce(p_resposta, '')) = '' THEN
    RETURN NULL;
  END IF;
  INSERT INTO nai_saber (pergunta, resposta, ensinado_por, pendencia_id)
       VALUES (btrim(p_pergunta), btrim(p_resposta), coalesce(p_quem, 'tel'), p_pendencia)
    RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

-- 3 ------------------------------------------ A FERRAMENTA: O QUE EU SEI?
CREATE OR REPLACE FUNCTION public.nai_sec_consultar(p_turno bigint, p_pergunta text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM nai_saber_busca(p_pergunta);
  IF r.id IS NOT NULL THEN
    UPDATE nai_saber SET vezes_usada = vezes_usada + 1 WHERE id = r.id;
    PERFORM nai_anotar(p_turno, 5, 'secretaria_sabia', 'passou',
                       'respondeu pelo saber ' || r.id);
    RETURN QUERY SELECT r.resposta,
      ('isto e o que o Tel ja te ensinou sobre isso. Responda com esta informacao, '
       || 'no seu tom, sem citar que consultou nada.')::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT NULL::text,
    ('voce ainda NAO sabe isso. Chame perguntar_ao_tel com a pergunta dele, do jeito que ele '
     || 'fez, e responda o que a ferramenta devolver.')::text;
END;
$function$;

-- 4 ------------------------------------ A FERRAMENTA: PERGUNTA PARA O TEL
CREATE OR REPLACE FUNCTION public.nai_sec_perguntar_ao_tel(p_turno bigint, p_pergunta text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; k nai_contato; v_nome text; v_pend int;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  IF k.id IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'nao achei o contato deste turno.'::text; RETURN;
  END IF;
  v_nome := coalesce(k.nome_completo, k.nome_whatsapp, k.telefone);

  -- A MESMA MESA DE PENDENCIAS que ele ja responde no WhatsApp: "RESPOSTA 81
  -- <texto>". Nao invento canal novo -- o Tel ja tem o dele, e a resposta
  -- volta sozinha para quem perguntou.
  INSERT INTO pendencias (codigo, o_que_falta, de_quem, avisar, status)
       VALUES (NULL, left(btrim(coalesce(p_pergunta, t.texto, '')), 400),
               'secretaria', regexp_replace(coalesce(k.telefone, ''), '\D', '', 'g'), 'aberta')
    RETURNING id INTO v_pend;

  PERFORM nai_avisar_tel(p_turno, NULL,
    'Tel, ' || v_nome || ' (' || nai_fone_fmt(k.telefone) || ') perguntou uma coisa que eu ainda '
    || 'não sei responder:' || E'\n"' || left(btrim(coalesce(p_pergunta, t.texto, '')), 300) || '"'
    || E'\nMe ensina? Responda: RESPOSTA ' || v_pend || ' <o que eu digo a ele>. '
    || 'Eu mando para ele e guardo para a próxima.',
    'secretaria_pergunta');

  PERFORM nai_usou_ferramenta(p_turno, 'escalar');
  PERFORM nai_anotar(p_turno, 5, 'secretaria_perguntou', 'mudou', 'pendencia ' || v_pend);

  -- Ela NAO cala (Tel, 16/09: "teve um que mandou boa noite e ela n
  -- respondeu"). Diz que vai ver e o Tel responde pela pendencia.
  RETURN QUERY SELECT
    ('Vou confirmar isso certinho'
     || coalesce(', ' || nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)), '')
     || ', e já te respondo por aqui!')::text,
    ('mande o texto_pronto como veio e pare por aqui: quem responde o resto e o Tel.')::text;
END;
$function$;

-- 5 ------------------------------------------ O IMOVEL QUE ELE QUER MANDAR
CREATE TABLE IF NOT EXISTS nai_imovel_novo (
  id            bigserial PRIMARY KEY,
  contato_id    bigint REFERENCES nai_contato(id),
  turno_id      bigint,
  tipo          text,
  finalidade    text,          -- venda | locacao
  condominio    text,
  bairro        text,
  quartos       int,
  suites        int,
  vagas         int,
  area          numeric,
  valor         numeric,
  taxa_condominio numeric,
  mobilia       text,
  descricao     text,
  situacao      text NOT NULL DEFAULT 'colhendo',   -- colhendo | subido
  codigo        int,
  criado_em     timestamptz NOT NULL DEFAULT now(),
  subido_em     timestamptz
);

CREATE TABLE IF NOT EXISTS nai_imovel_novo_foto (
  id        bigserial PRIMARY KEY,
  novo_id   bigint NOT NULL REFERENCES nai_imovel_novo(id) ON DELETE CASCADE,
  url       text NOT NULL,
  criado_em timestamptz NOT NULL DEFAULT now()
);

-- O que ainda falta perguntar. A ordem e a de quem conversa, nao a do
-- cadastro: primeiro o que o imovel E, depois quanto custa, depois as fotos.
CREATE OR REPLACE FUNCTION public.nai_imovel_novo_falta(p_id bigint)
 RETURNS text LANGUAGE sql STABLE
AS $function$
  SELECT CASE
    WHEN n.tipo       IS NULL THEN 'tipo'
    WHEN n.finalidade IS NULL THEN 'finalidade'
    WHEN coalesce(n.condominio, n.bairro) IS NULL THEN 'lugar'
    WHEN n.quartos    IS NULL THEN 'quartos'
    WHEN n.valor      IS NULL THEN 'valor'
    WHEN NOT EXISTS (SELECT 1 FROM nai_imovel_novo_foto f WHERE f.novo_id = n.id) THEN 'fotos'
  END
  FROM nai_imovel_novo n WHERE n.id = p_id;
$function$;

-- SOBE AUTOMATICO, SEM O CONTATO DO CORRETOR (Tel, 22/09: "so tira o contato
-- do corretor e pode subir automatico"). Telefone, e-mail e "falar com
-- fulano" saem da descricao antes de virar imovel nosso.
CREATE OR REPLACE FUNCTION public.nai_imovel_novo_subir(p_id bigint)
 RETURNS integer LANGUAGE plpgsql
AS $function$
DECLARE n nai_imovel_novo; v_cod int; v_desc text;
BEGIN
  SELECT * INTO n FROM nai_imovel_novo WHERE id = p_id;
  IF n.id IS NULL OR n.situacao = 'subido' THEN RETURN n.codigo; END IF;

  v_desc := coalesce(n.descricao, '');
  v_desc := regexp_replace(v_desc, '\(?\d{2}\)?\s*9?\d{4}[-. ]?\d{4}', '', 'g');
  v_desc := regexp_replace(v_desc, '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[a-z]{2,}', '', 'g');
  v_desc := regexp_replace(v_desc, '(?i)\m(whats(app)?|contato|falar com|corretor[a]?)\M[^.\n]*', '', 'g');
  v_desc := btrim(regexp_replace(v_desc, '[ \t]+', ' ', 'g'));

  SELECT coalesce(max(codigo), 0) + 1 INTO v_cod FROM imoveis;

  INSERT INTO imoveis (codigo, tipo, condominio_nome, bairro, quartos, suites, vagas,
                       area_total, valor_venda, valor_aluguel, taxa_condominio, mobilia,
                       descricao, origem, disponivel, bloqueado, publicado_no_site,
                       e_parceiro, travado, precisa_confirmacao, administrado)
       VALUES (v_cod, coalesce(n.tipo, 'Apartamento'), n.condominio, n.bairro, n.quartos,
               n.suites, n.vagas, n.area,
               CASE WHEN n.finalidade = 'venda'   THEN n.valor END,
               CASE WHEN n.finalidade = 'locacao' THEN n.valor END,
               n.taxa_condominio, n.mobilia, nullif(v_desc, ''), 'secretaria',
               true, false, true, false, false, false, false);

  INSERT INTO imovel_fotos (codigo, url, ordem, e_capa)
       SELECT v_cod, f.url, row_number() OVER (ORDER BY f.id), row_number() OVER (ORDER BY f.id) = 1
         FROM nai_imovel_novo_foto f WHERE f.novo_id = n.id;

  UPDATE nai_imovel_novo SET situacao = 'subido', codigo = v_cod, subido_em = now() WHERE id = n.id;
  RETURN v_cod;
END;
$function$;

-- 6 ------------------------------ A PAREDE DA 97 SO VALE COM ELA DESLIGADA
-- Com a secretaria no ar, oferta de imovel nao sobe mais ao Tel: e o assunto
-- DELA. Desligada, tudo continua como estava hoje.
DO $mig$
DECLARE v_def text; v_velho text; v_novo text;
BEGIN
  v_def := pg_get_functiondef('nai_conferir_resposta(bigint,text,jsonb,text,jsonb)'::regprocedure);
  v_velho := '  IF t.papel IN (''corretor'', ''proprietario'')' || E'\n'
          || '     AND nai_oferece_imovel(coalesce(p_escreveu, '''')) THEN';
  v_novo  := '  IF t.papel IN (''corretor'', ''proprietario'')' || E'\n'
          || '     AND NOT nai_secretaria_ligada()' || E'\n'
          || '     AND nai_oferece_imovel(coalesce(p_escreveu, '''')) THEN';
  IF position('nai_secretaria_ligada' IN v_def) > 0 THEN
    RAISE NOTICE 'a parede da 97 ja conhece a secretaria'; RETURN;
  END IF;
  IF position(v_velho IN v_def) = 0 THEN
    RAISE EXCEPTION 'nao achei a parede da 97 no conferidor';
  END IF;
  EXECUTE replace(v_def, v_velho, v_novo);
  RAISE NOTICE 'parede da 97 agora respeita a secretaria';
END $mig$;

-- 7 --------------------------- O CONFERIDOR NAO JULGA A SECRETARIA POR CARD
-- As guardas do conferidor sao do fluxo de locacao -- "respondeu sem
-- consultar a base", "prometeu retorno", formato de card. A secretaria nao
-- tem esse fluxo: o que vale para ela e nao inventar, e disso cuidam as
-- ferramentas dela.
DO $mig$
DECLARE v_def text; v_alvo text; v_bloco text;
BEGIN
  v_def := pg_get_functiondef('nai_conferir_resposta(bigint,text,jsonb,text,jsonb)'::regprocedure);
  IF position('atendente = ''secretaria''' IN v_def) > 0 THEN
    RAISE NOTICE 'o conferidor ja conhece a secretaria'; RETURN;
  END IF;
  v_alvo := '  -- 01 -------------------------------------------------- DE QUAL IMÓVEL É';
  IF position(v_alvo IN v_def) = 0 THEN
    RAISE EXCEPTION 'nao achei o comeco do conferidor';
  END IF;
  v_bloco := $bloco$  -- 00 ------------------------------------------- A SECRETARIA (99)
  -- Turno da secretaria nao passa pelas guardas de locacao: elas cobram card,
  -- código e consulta à base, que é o fluxo da outra. Aqui vale o silêncio
  -- quando não há o que dizer, e nada mais.
  IF t.atendente = 'secretaria' THEN
    IF v_calada THEN
      RETURN jsonb_build_object('acao', 'silencio', 'guarda', 'secretaria_calada');
    END IF;
    RETURN jsonb_build_object('acao', 'responder', 'texto', v_texto,
                              'guarda', 'secretaria', 'codigo', NULL);
  END IF;

$bloco$ || v_alvo;
  EXECUTE replace(v_def, v_alvo, v_bloco);
  RAISE NOTICE 'conferidor: caminho da secretaria posto';
END $mig$;

COMMIT;

SELECT 'secretaria ligada?' AS o, nai_cfg('secretaria_ligada', '?') AS valor
UNION ALL SELECT 'tabelas novas', string_agg(table_name, ', ')
  FROM information_schema.tables
 WHERE table_schema = 'public' AND table_name IN ('nai_saber', 'nai_mente', 'nai_imovel_novo', 'nai_imovel_novo_foto');
