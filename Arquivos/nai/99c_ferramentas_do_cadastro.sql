-- =====================================================================
-- NAI -- 99c: as ferramentas do cadastro da secretaria (Tel, 22/09/2026)
--
-- O caso do Luiz Bastos, agora atendido: "tenho um Living Confort tambem, se
-- quiser te envio". A secretaria aceita, pergunta UMA coisa por mensagem e
-- guarda o que vem. Quando esta completo, o imovel sobe -- sem o contato do
-- corretor, como o Tel pediu.
--
-- QUEM PERGUNTA E A FERRAMENTA, nao o modelo. E a mesma licao do
-- `nai_buscar_por_perfil`: deixando a sequencia com o modelo, ele junta duas
-- perguntas numa mensagem so. Aqui a funcao devolve a PROXIMA pergunta e mais
-- nada.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- A pergunta de cada buraco. O texto e de conversa, nao de formulario.
CREATE OR REPLACE FUNCTION public.nai_imovel_novo_pergunta(p_falta text)
 RETURNS text LANGUAGE sql IMMUTABLE
AS $function$
  SELECT CASE p_falta
    WHEN 'tipo'       THEN 'Me conta o que é: apartamento, casa ou outra coisa?'
    WHEN 'finalidade' THEN 'É para venda ou para locação?'
    WHEN 'lugar'      THEN 'Qual o condomínio e o bairro?'
    WHEN 'quartos'    THEN 'Quantos quartos ele tem?'
    WHEN 'valor'      THEN 'E qual o valor?'
    WHEN 'fotos'      THEN 'Agora me manda as fotos, por favor.'
  END;
$function$;

-- ABRIR: uma ficha por contato. Se ele ja estava mandando um imovel e parou no
-- meio, a mesma ficha continua -- ninguem gosta de responder duas vezes.
CREATE OR REPLACE FUNCTION public.nai_sec_abrir_cadastro(p_turno bigint)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; v_id bigint; v_falta text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'turno inexistente'::text; RETURN;
  END IF;

  SELECT n.id INTO v_id FROM nai_imovel_novo n
   WHERE n.contato_id = t.contato_id AND n.situacao = 'colhendo'
   ORDER BY n.id DESC LIMIT 1;

  IF v_id IS NULL THEN
    INSERT INTO nai_imovel_novo (contato_id, turno_id) VALUES (t.contato_id, p_turno)
      RETURNING id INTO v_id;
    PERFORM nai_anotar(p_turno, 6, 'cadastro_aberto', 'mudou', 'ficha ' || v_id);
  END IF;

  v_falta := nai_imovel_novo_falta(v_id);
  IF v_falta IS NULL THEN
    RETURN QUERY SELECT 'Obrigada! Já deixei registrado aqui.'::text,
      ('a ficha ja esta completa. Agradeca e encerre, sem perguntar mais nada.')::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT nai_imovel_novo_pergunta(v_falta),
    ('ficha ' || v_id || '. Diga SO essa pergunta, sem juntar outra. Quando ele responder, '
     || 'chame guardar_do_imovel com o que veio.')::text;
END;
$function$;

-- GUARDAR: cada parametro e opcional. O modelo manda o que entendeu; a funcao
-- so grava o que chegou e devolve a proxima pergunta.
CREATE OR REPLACE FUNCTION public.nai_sec_guardar_do_imovel(
    p_turno bigint, p_tipo text DEFAULT NULL, p_finalidade text DEFAULT NULL,
    p_condominio text DEFAULT NULL, p_bairro text DEFAULT NULL, p_quartos text DEFAULT NULL,
    p_suites text DEFAULT NULL, p_vagas text DEFAULT NULL, p_area text DEFAULT NULL,
    p_valor text DEFAULT NULL, p_taxa text DEFAULT NULL, p_mobilia text DEFAULT NULL,
    p_descricao text DEFAULT NULL)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; v_id bigint; v_falta text; v_num text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT n.id INTO v_id FROM nai_imovel_novo n
   WHERE n.contato_id = t.contato_id AND n.situacao = 'colhendo'
   ORDER BY n.id DESC LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO nai_imovel_novo (contato_id, turno_id) VALUES (t.contato_id, p_turno)
      RETURNING id INTO v_id;
  END IF;

  -- O PRIMEIRO numero, nao todos colados. "3 quartos sendo 1 suite" com
  -- `regexp_replace` virava 31 quartos -- medido no primeiro teste.
  v_num := '\d+';
  UPDATE nai_imovel_novo n SET
    tipo       = coalesce(nullif(btrim(coalesce(p_tipo, '')), ''), n.tipo),
    -- a finalidade tambem sai do VALOR: acima de 100 mil e venda (98).
    finalidade = coalesce(nay_negocio_pedido(concat_ws(' ', p_finalidade, p_valor)), n.finalidade),
    condominio = coalesce(nullif(btrim(coalesce(p_condominio, '')), ''), n.condominio),
    bairro     = coalesce(nullif(btrim(coalesce(p_bairro, '')), ''), n.bairro),
    quartos    = coalesce((regexp_match(coalesce(p_quartos, ''), v_num))[1]::int, n.quartos),
    suites     = coalesce((regexp_match(coalesce(p_suites, ''), v_num))[1]::int, n.suites),
    vagas      = coalesce((regexp_match(coalesce(p_vagas, ''), v_num))[1]::int, n.vagas),
    area       = coalesce((regexp_match(coalesce(p_area, ''), v_num))[1]::numeric, n.area),
    valor      = coalesce(nay_maior_valor(p_valor), nay_valor_em_reais(p_valor), n.valor),
    taxa_condominio = coalesce(nay_valor_em_reais(p_taxa), n.taxa_condominio),
    mobilia    = coalesce(nullif(btrim(coalesce(p_mobilia, '')), ''), n.mobilia),
    descricao  = coalesce(nullif(btrim(concat_ws(E'\n', n.descricao, nullif(btrim(coalesce(p_descricao, '')), ''))), ''), n.descricao)
   WHERE n.id = v_id;

  v_falta := nai_imovel_novo_falta(v_id);
  IF v_falta IS NULL THEN
    -- SOBE SOZINHO (Tel, 22/09: "so tira o contato do corretor e pode subir
    -- automatico"). O codigo sai aqui e fica na ficha.
    PERFORM nai_imovel_novo_subir(v_id);
    PERFORM nai_anotar(p_turno, 6, 'cadastro_completo', 'mudou',
                       'ficha ' || v_id || ' virou o imovel '
                       || coalesce((SELECT codigo::text FROM nai_imovel_novo WHERE id = v_id), '?'));
    RETURN QUERY SELECT 'Obrigada! Já deixei registrado aqui.'::text,
      ('a ficha fechou e o imovel entrou no sistema. Agradeca e encerre. NAO diga codigo, '
       || 'nao fale de comissao e nao prometa quando ele vai ao ar.')::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT nai_imovel_novo_pergunta(v_falta),
    ('ficha ' || v_id || '. Diga SO essa pergunta, sem juntar outra.')::text;
END;
$function$;

-- AS FOTOS chegam pelo fluxo, nao pelo modelo: quem tem a url da midia e o
-- ramo que ja baixa a imagem. Guarda so o que for de uma ficha aberta.
CREATE OR REPLACE FUNCTION public.nai_sec_guardar_foto(p_turno bigint, p_url text)
 RETURNS integer LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; v_id bigint;
BEGIN
  IF btrim(coalesce(p_url, '')) !~ '^https?://' THEN RETURN 0; END IF;
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN 0; END IF;
  SELECT n.id INTO v_id FROM nai_imovel_novo n
   WHERE n.contato_id = t.contato_id AND n.situacao = 'colhendo'
   ORDER BY n.id DESC LIMIT 1;
  IF v_id IS NULL THEN RETURN 0; END IF;
  INSERT INTO nai_imovel_novo_foto (novo_id, url) VALUES (v_id, btrim(p_url));
  RETURN 1;
END;
$function$;

COMMIT;

-- A conversa inteira do Luiz Bastos, como ela vai acontecer.
SELECT nai_imovel_novo_pergunta(f) AS pergunta, f AS falta
  FROM unnest(ARRAY['tipo','finalidade','lugar','quartos','valor','fotos']) f;
