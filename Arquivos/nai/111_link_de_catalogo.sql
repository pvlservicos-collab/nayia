-- =====================================================================
-- NAI -- 111: o link do catalogo do WhatsApp (Tel, 23/09/2026)
--
-- Ele: "esse numero perguntou de um ap do catalogo, a nay conseguiu
-- observar?" -- (92) 9454-0289, Amanda Castilho (CRECI 7144).
--
-- NAO CONSEGUIU. As 11:31 ela escreveu:
--     "Bom dia Nay"
--     "Esse apartamento ainda esta disponivel?"
--     https://wa.me/p/27112258725070743/559294540289
-- e a Nay ficou calada.
--
-- POR QUE (dois motivos, um atras do outro):
--   1. A PORTA. Conversa antiga, das que ficaram com o Tel no religamento.
--      Abre com codigo, nome de condominio ou pedido de perfil -- e um link
--      de produto nao e nada disso. Mas perguntar "esse apartamento ainda
--      esta disponivel?" com o imovel no link E pedir imovel claramente.
--   2. O LINK NAO DIZ QUAL IMOVEL E. `wa.me/p/{produto}/{telefone}` carrega
--      o id do produto no catalogo do WhatsApp -- e o webhook traz isso como
--      TEXTO PURO, sem nome nem descricao (conferido na execucao 91357).
--      Nao existe, do nosso lado, como saber de qual imovel ele fala.
--
-- O QUE MUDA: a porta passa a abrir, e -- como ela NAO PODE ADIVINHAR -- o
-- caso vai para o Tel com o link, que ele abre e ve. Ela diz uma linha ao
-- corretor, do mesmo jeito que faz quando chega foto: recebeu e ja responde.
-- Inventar um imovel aqui seria pior do que o silencio; calar tambem e ruim,
-- porque o corretor fica olhando para a tela.
--
-- O LINK DO NOSSO SITE continua resolvendo sozinho: `imobeasy.com/imoveis/3649`
-- ja da o codigo 3649, e com isso o caminho normal segue.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- 1 ------------------------------------------- COMO SE RECONHECE O LINK
CREATE OR REPLACE FUNCTION public.nai_e_link_de_produto(p_texto text)
 RETURNS boolean LANGUAGE sql IMMUTABLE
AS $function$
  -- wa.me/p/... e o produto do catalogo do WhatsApp Business. O /c/ e o
  -- catalogo inteiro. Os dois querem dizer "estou falando DESTE imovel".
  SELECT lower(coalesce(p_texto, '')) ~ '(wa\.me/p/|api\.whatsapp\.com/product|/catalog/)';
$function$;

-- 2 ----------------------------------- A PORTA ABRE PARA QUEM MANDA O LINK
DO $mig$
DECLARE v_def text; v_alvo text; v_bloco text;
BEGIN
  v_def := pg_get_functiondef('nai_deve_atender(text,text,integer)'::regprocedure);
  IF position('nai_e_link_de_produto' IN v_def) > 0 THEN
    RAISE NOTICE 'a porta ja aceita link de catalogo'; RETURN;
  END IF;

  v_alvo := '  -- COLOU O CARD, OU ESCREVEU O CODIGO (101, Tel 23/09). E o caso mais';
  IF position(v_alvo IN v_def) = 0 THEN
    RAISE EXCEPTION 'nao achei o bloco do card colado na porta';
  END IF;

  v_bloco := $bloco$  -- MANDOU O IMOVEL PELO LINK DO CATALOGO (111, Tel 23/09). O link nao diz
  -- qual imovel e, mas diz que o assunto E imovel -- e e por isso que a porta
  -- abre. Quem descobre qual e o Tel, logo adiante.
  IF nai_e_link_de_produto(p_texto) THEN
    UPDATE nai_contato SET liberado_em = now(),
                           liberado_motivo = left('mandou link de catalogo: ' || coalesce(p_texto, ''), 200)
     WHERE chave = v_chave;
    RETURN QUERY SELECT true, 'mandou o imovel pelo link do catalogo'::text; RETURN;
  END IF;

$bloco$ || v_alvo;

  EXECUTE replace(v_def, v_alvo, v_bloco);
  RAISE NOTICE 'porta: link de catalogo abre a conversa';
END $mig$;

-- 3 -------------------------- ELA NAO ADIVINHA: O TEL RECEBE O LINK
CREATE OR REPLACE FUNCTION public.nai_escalar_link_de_catalogo(p_turno bigint, p_escreveu text)
 RETURNS text LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; k nai_contato; v_nome text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  IF k.id IS NULL THEN RETURN NULL; END IF;
  v_nome := coalesce(k.nome_completo, k.nome_whatsapp, k.telefone);

  PERFORM nai_avisar_tel(p_turno, NULL,
    'Tel, ' || v_nome || ' (' || nai_fone_fmt(k.telefone) || ') perguntou de um imóvel mandando o '
    || 'link do catálogo do WhatsApp:' || E'\n' || left(coalesce(p_escreveu, ''), 400) || E'\n'
    || 'O link não diz qual imóvel é — só você abrindo dá para ver.'
    || E'\nFalei só que recebi e que já respondo. Parei de responder esse chat: quem segue é você. '
    || 'Para eu voltar: DEVOLVER ' || nai_fone_fmt(k.telefone) || '.',
    'link_de_catalogo');

  PERFORM nai_usou_ferramenta(p_turno, 'escalar');
  PERFORM nai_parar_chat(k.id, 'link de catalogo do WhatsApp');

  RETURN ('Recebi' || coalesce(', ' || nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)), '')
          || '! Já te respondo por aqui.')::text;
END;
$function$;

-- 4 ------------------------------ A PAREDE NO CONFERIDOR, ANTES DE QUALQUER CARD
DO $mig$
DECLARE v_def text; v_alvo text; v_bloco text;
BEGIN
  v_def := pg_get_functiondef('nai_conferir_resposta(bigint,text,jsonb,text,jsonb)'::regprocedure);
  IF position('nai_e_link_de_produto' IN v_def) > 0 THEN
    RAISE NOTICE 'o conferidor ja conhece o link de catalogo'; RETURN;
  END IF;

  v_alvo := '  -- 02b ------------------------------------------ ELA NÃO FAZ CADASTRO (97)';
  IF position(v_alvo IN v_def) = 0 THEN
    RAISE EXCEPTION 'nao achei a parede da 97 no conferidor';
  END IF;

  v_bloco := $bloco$  -- 02a ------------------------- LINK DE CATÁLOGO NÃO DIZ QUAL IMÓVEL É (111)
  -- Sem código na conversa, qualquer imóvel que ela mandasse aqui seria
  -- chute. O Tel recebe o link e responde; ela diz que recebeu, e não cala.
  IF t.papel = 'corretor' AND v_alvo IS NULL
     AND nai_e_link_de_produto(coalesce(p_escreveu, '')) THEN
    v_base := nai_escalar_link_de_catalogo(p_turno, p_escreveu);
    PERFORM nai_anotar(p_turno, 2, 'link_de_catalogo', 'mudou',
                       'link de produto sem código: subiu ao Tel');
    RETURN jsonb_build_object('acao', 'responder', 'texto', v_base,
                              'guarda', 'link_de_catalogo', 'codigo', NULL);
  END IF;

$bloco$ || v_alvo;

  EXECUTE replace(v_def, v_alvo, v_bloco);
  RAISE NOTICE 'conferidor: link de catalogo vai ao Tel';
END $mig$;

COMMIT;

SELECT t AS mensagem, nai_e_link_de_produto(t) AS e_link_de_catalogo,
       nay_codigos_citados(t) AS codigo_que_da_para_ler
  FROM unnest(ARRAY[
    'Esse apartamento ainda está disponível? https://wa.me/p/27112258725070743/559294540289',
    'Esse ainda está disponível? https://imobeasy.com/imoveis/3649',
    'bom dia, tudo bem?',
    'me manda as fotos do 5611'
  ]) t;
