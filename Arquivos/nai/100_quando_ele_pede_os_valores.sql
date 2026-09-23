-- =====================================================================
-- NAI -- 100: quando ele pede OS VALORES, ela mostra o que tem
-- (Tel, 23/09/2026)
--
-- O CASO, da conversa do Joao Luiz ((92) 99248-5907) hoje de manha:
--
--   08:48  ele:  "Bom dia. Vc tem casa para locacao no nova cidade?"
--   08:48  ela:  "E qual a faixa de preco que seus clientes estao buscando?"
--   08:53  ele:  (audio) "O que que voce tem ai de alocacao? Voce ja tem
--                 alguma ai para alocacao?"
--   08:53  ela:  "E qual a faixa de preco que seus clientes estao buscando?"
--   08:54  ele:  "Qual sao os valores que vc tem?"
--   08:54  ela:  "E qual a faixa de preco que seus clientes estao buscando?"
--   08:56  ele:  "Coloca no grupo ai... Ela nao me especificou qual e o valor."
--
-- Tres vezes a MESMA pergunta. E ele ja tinha dito tudo o que ela precisava
-- na primeira mensagem -- bairro (Nova Cidade), tipo (casa) e finalidade
-- (locacao). Faltava so o teto, e o teto e dele, nao nosso: quando o corretor
-- pergunta "quais os valores que VOCE tem", quem tem que dizer numero e ela.
--
-- E, no Nova Cidade, existe UMA casa para alugar. Perguntar faixa de preco
-- para peneirar um imovel so nao tem defesa.
--
-- DUAS PORTAS PARA PULAR A PERGUNTA DO TETO:
--   1. ELE PEDIU OS VALORES / TODAS AS OPCOES. E o jeito de falar dos
--      corretores -- "quais os valores que vc tem", "o que voce tem ai",
--      "me passa todas as opcoes", "tem alguma?". Isso nao e um cliente sem
--      orcamento: e um pedido de lista.
--   2. O QUE EXISTE CABE NUMA MENSAGEM. Ate `limite_sem_teto` imoveis
--      (5, em `nai_config`) no bairro, com o tipo e a finalidade que ele
--      pediu, ela mostra. Peneirar faz sentido com 30 opcoes, nao com uma.
--
-- A sequencia do Tel continua inteira para quem chega vago ("tem apartamento
-- de 2 quartos?" num bairro cheio): ali a faixa de preco ainda e a segunda
-- pergunta.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO nai_config (chave, valor) VALUES ('limite_sem_teto', '5')
ON CONFLICT (chave) DO NOTHING;

-- 1 -------------------------------------------- ELE ESTA PEDINDO A LISTA
CREATE OR REPLACE FUNCTION public.nai_pede_os_valores(p_texto text)
 RETURNS boolean LANGUAGE sql IMMUTABLE
AS $function$
  SELECT s ~ ('(quais? (sao )?(os )?(valor|preco)|'
           || '(valor|preco)e?s? que (voce|vc|tu) tem|'
           || 'quanto (ta|esta|e) (o )?(aluguel|valor)|'
           || 'o que (voce|vc|tu) tem|'
           || 'que que (voce|vc) tem|'
           || 'todas as opcoes|todas opcoes|todos os (imoveis|que tiver)|'
           || 'me (manda|passa|mostra) (tudo|todas|todos|a lista|as opcoes)|'
           || '(tem|teria) (alguma|algum|algo)\M|'
           || 'ja tem (alguma|algum)\M|'
           || 'quais (voce|vc) tem|quais tem\M)')
    FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s) x;
$function$;

-- 2 ------------------------------ QUANTOS EXISTEM, ANTES DE PERGUNTAR NADA
CREATE OR REPLACE FUNCTION public.nai_quantos_no_bairro(p_bairro text, p_telefone text,
                                                        p_quartos integer, p_negocio text, p_tipo text)
 RETURNS integer LANGUAGE sql STABLE
AS $function$
  SELECT count(*)::int FROM imoveis i
   WHERE nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(coalesce(p_bairro, ''), true) || '%'
     AND nai_oferta_serve(i, coalesce(p_telefone, ''), NULL, p_quartos, false, false, p_negocio, p_tipo);
$function$;

-- 3 ------------------------------------- AS PERGUNTAS GANHAM UM DESVIO
DO $mig$
DECLARE v_def text; v_velho text; v_novo text;
BEGIN
  v_def := pg_get_functiondef('nai_buscar_por_perfil(bigint,text,text,text,text)'::regprocedure);
  IF position('v_mostra_logo' IN v_def) > 0 THEN
    RAISE NOTICE 'o desvio ja esta posto'; RETURN;
  END IF;

  -- a) a variavel
  v_velho := '  v_diz    text;';
  IF position(v_velho IN v_def) = 0 THEN RAISE EXCEPTION 'nao achei o v_diz'; END IF;
  v_def := replace(v_def, v_velho, v_velho || E'
  v_mostra_logo boolean;   -- mostrar em vez de peneirar (100)');

  -- b) a decisao, uma vez so, logo depois de saber a finalidade e o tipo
  v_velho := '  v_diz     := CASE WHEN v_negocio = ''venda'' THEN ''venda'' ELSE ''locação'' END;';
  IF position(v_velho IN v_def) = 0 THEN RAISE EXCEPTION 'nao achei a linha do v_diz'; END IF;
  v_def := replace(v_def, v_velho, v_velho || $bloco$

  -- O TETO E DELE, MAS A LISTA E NOSSA (100, Tel 23/09). Ele pediu os
  -- valores, ou o que existe cabe numa mensagem: mostra, nao peneira.
  -- Com isso a sequencia de perguntas para de rodar em falso -- ela
  -- perguntou a faixa de preco TRES vezes ao Joao Luiz, que so queria ver a
  -- unica casa que temos no Nova Cidade.
  v_mostra_logo := nai_pede_os_valores(concat_ws(' ', t.texto, p_bairro))
                   OR nai_quantos_no_bairro(p_bairro, k.telefone, v_q, v_negocio, v_tipo)
                      BETWEEN 1 AND nai_cfg_int('limite_sem_teto', 5);
  IF v_mostra_logo THEN
    PERFORM nai_anotar(p_turno, 7, 'mostra_sem_peneirar', 'mudou',
                       'ele pediu os valores, ou o bairro tem pouca coisa');
  END IF;$bloco$);

  -- c) a pergunta do teto
  v_velho := '  IF nullif(btrim(coalesce(p_teto, '''')), '''') IS NULL THEN';
  IF position(v_velho IN v_def) = 0 THEN RAISE EXCEPTION 'nao achei a pergunta do teto'; END IF;
  v_def := replace(v_def, v_velho,
                   '  IF nullif(btrim(coalesce(p_teto, '''')), '''') IS NULL AND NOT v_mostra_logo THEN');

  -- d) a pergunta da mobilia
  v_velho := '  IF NOT v_direta AND nullif(btrim(coalesce(p_mobilia, '''')), '''') IS NULL THEN';
  IF position(v_velho IN v_def) = 0 THEN RAISE EXCEPTION 'nao achei a pergunta da mobilia'; END IF;
  v_def := replace(v_def, v_velho,
                   '  IF NOT v_direta AND nullif(btrim(coalesce(p_mobilia, '''')), '''') IS NULL'
                   || E'
     AND NOT v_mostra_logo THEN');

  EXECUTE v_def;
  RAISE NOTICE 'desvio posto: ela mostra em vez de peneirar';
END $mig$;

-- 4 ------------------------------ O JEITO DE FALAR ENTRA NA BIBLIOTECA (96)
INSERT INTO nai_giria (expressao, significado, exemplo, ativo) VALUES
  ('quais? (sao )?(os )?valores que (voce|vc) tem',
   'ele esta pedindo A LISTA do que temos, com os preços. Quem diz número aqui é você: mostre o que existe, não pergunte o orçamento dele.',
   'Qual são os valores que vc tem?', true),
  ('o que (voce|vc) tem (ai|aqui)?( de)?',
   'mesma coisa: ele quer ver o que existe. Mostre as opções.',
   'O que que você tem aí de locação?', true),
  ('todas as opcoes',
   'ele quer TUDO o que temos naquele bairro ou condomínio, sem peneira.',
   'Ele quer todas as opções de locação desse Nova Cidade', true)
ON CONFLICT DO NOTHING;

COMMIT;

-- O dialeto, lido.
SELECT nai_pede_os_valores(t) AS pede_a_lista, t AS frase
  FROM unnest(ARRAY[
    'Qual são os valores que vc tem?',
    'O que que você tem aí de locação? Você já tem alguma aí para locação?',
    'ele quer todas as opções de locação desse nova cidade',
    'Vc tem casa para locação no nova cidade?',
    'meu cliente tem até 3 mil',
    'quero agendar uma visita amanhã',
    'me manda as fotos do 5611'
  ]) t;
