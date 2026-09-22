-- =====================================================================
-- NAI -- 97: ela nao faz cadastro -- oferta de imovel vai para o Tel
-- (Tel, 22/09/2026)
--
-- Ele: "ele perguntou se ela queria que ele enviasse para ela imoveis, nesse
-- caso como e algo fora do fluxo, ela bugou e enviou umas fotos aleatorias
-- depois cobrou ele de enviar no formato certo. Ela nao faz cadastros, era
-- para ela chamar o Tel quando o proprietario pedir algo assim para ela como
-- se fosse uma pergunta."
--
-- O QUE ACONTECEU (Luiz Bastos, turnos 10523-10527):
--   17:12  "Oi Nay, eu tenho um Living Confort tambem. Se quiser te envio"
--   ela -> 11 FOTOS do NOSSO 5664 + "Pode me enviar sim. E no Living Comfort?"
-- O imovel era DELE. Como o nome do condominio e nosso, a porta entendeu
-- "citou um imovel nosso pelo nome" e a conversa virou pedido de card.
--
-- A PAREDE: o conferidor roda ANTES da caixa de saida, entao parar ali
-- segura o texto E as fotos. Oferta de imovel = pergunta para o Tel: ela
-- avisa ele, nao fala nada e para o chat, igual duvida fora da base. Volta
-- com DEVOLVER <telefone>, como o resto.
--
-- A PENEIRA (medida em 7.579 mensagens recebidas do banco):
--   camada 1, ele se oferece para mandar: 20 acertos
--   camada 2, ele diz que TEM um:         10 acertos
-- "Posso anunciar?" e "Posso divulgar?" ficaram DE FORA de proposito: essas
-- sao as do "pode publicar sim" (85), que e sobre imovel NOSSO.
-- Fora tambem cliente, visita, CPF, documento, contrato, garagem: quem fala
-- dessas nao esta oferecendo imovel.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- 1 ------------------------------------------------------- A PENEIRA
CREATE OR REPLACE FUNCTION public.nai_oferece_imovel(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  WITH t AS (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s)
  SELECT
    -- 1. ele se oferece para mandar ("se quiser te envio", "posso te passar")
    ( (   s ~ '(se|caso) (voce |vc |tu |o sr |a sra )?quiser(es)?[ ,]*(eu )?(te |lhe )?(envio|mando|passo|encaminho|mostro|enviar|mandar|passar)'
       OR s ~ 'quer(es)? que eu ?(te |lhe )?(envie|mande|passe|cadastre|encaminhe|mostre)'
       OR s ~ 'posso ?(te |lhe )?(enviar|mandar|passar|encaminhar)'
       OR s ~ '(quero|gostaria de|preciso|como (faco|faz) (para|pra)) (cadastrar|colocar) ?(meu|um|uns|o)? ?(imovel|imoveis|apartamento|apto|casa)'
       OR s ~ '(voces|vcs) (pegam|aceitam|fazem|trabalham com|querem) (captacao|imove|apartamento|administracao)')
      AND s !~ '(cpf|\mrg\M|documento|contrato|comprovante|ficha|\mprint|\maudio\M|localizacao|\mo numero\M|deposito|\mchave)' )
    OR
    -- 2. ele diz que TEM um ("eu tenho um Living Confort tambem")
    ( s ~ '\m(eu )?(tenho|possuo)\M (um|uma|uns|umas|dois|duas|outro|outra|mais um|mais uma)\M'
      AND s !~ '\m(cliente|comprador|inquilin|interessad|visita|proposta|duvida|pergunta|horario|reuniao|compromisso|minuto|problema|detalhe|amigo|corretor|garagem|vaga)' )
  FROM t;
$function$;

-- 2 ------------------------------------------------ ELA CHAMA O TEL E PARA
CREATE OR REPLACE FUNCTION public.nai_escalar_cadastro(p_turno bigint, p_escreveu text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; k nai_contato; v_nome text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  IF k.id IS NULL THEN RETURN; END IF;
  v_nome := coalesce(k.nome_completo, k.nome_whatsapp, k.telefone);
  PERFORM nai_avisar_tel(p_turno, NULL,
    'Tel, ' || v_nome || ' (' || nai_fone_fmt(k.telefone) || ') está oferecendo imóvel: "' ||
    left(coalesce(p_escreveu, ''), 300) || '".' ||
    E'\nEu não faço cadastro, então não falei nada e parei de responder esse chat: quem responde é você. Para eu voltar: DEVOLVER '
    || nai_fone_fmt(k.telefone) || '.',
    'oferta_de_imovel');
  PERFORM nai_usou_ferramenta(p_turno, 'escalar');
  PERFORM nai_parar_chat(k.id, 'ofereceu imóvel (ela não faz cadastro)');
END;
$function$;

-- 3 ------------------------------------- A PAREDE DENTRO DO CONFERIDOR VIVO
DO $mig$
DECLARE
  v_def text; v_alvo text; v_bloco text;
BEGIN
  v_def := pg_get_functiondef('nai_conferir_resposta(bigint,text,jsonb,text,jsonb)'::regprocedure);

  IF position('oferta_de_imovel' IN v_def) > 0 THEN
    RAISE NOTICE 'a parede ja esta no conferidor'; RETURN;
  END IF;

  v_alvo := '  -- 03 --------------------------------- PERGUNTA SEM RESPOSTA / PROMESSA DE RETORNO';
  IF position(v_alvo IN v_def) = 0 THEN
    RAISE EXCEPTION 'nao achei o ponto de insercao no conferidor';
  END IF;

  v_bloco := $bloco$  -- 02b ------------------------------------------ ELA NÃO FAZ CADASTRO (97)
  -- Oferta de imóvel dele é pergunta para o Tel. Tem que ser AQUI, antes de
  -- tudo: o card e as fotos só são enfileirados depois que esta função
  -- devolve 'responder'. O Tel e o Fernando ficam de fora pelo papel.
  IF t.papel IN ('corretor', 'proprietario')
     AND nai_oferece_imovel(coalesce(p_escreveu, '')) THEN
    PERFORM nai_escalar_cadastro(p_turno, p_escreveu);
    PERFORM nai_anotar(p_turno, 2, 'oferta_de_imovel', 'parou',
                       'ofereceu imóvel: subiu ao Tel e parou o chat');
    RETURN jsonb_build_object('acao', 'parou', 'guarda', 'oferta_de_imovel_foi_ao_tel');
  END IF;

$bloco$ || v_alvo;

  EXECUTE replace(v_def, v_alvo, v_bloco);
  RAISE NOTICE 'parede posta no conferidor';
END $mig$;

-- 4 ------------------------------------------------------------- O PROMPT
DO $mig$
DECLARE
  v_texto text; v_novo text; v_versao int;
  v_ancora text := '- Ele já pediu visita: vá para a etapa 5.';
  v_linha  text := '- Ele ofereceu um imóvel dele ("tenho um lá também, se quiser te envio") ou quer cadastrar imóvel com a gente: chame escalar_ao_tel e responda SILENCIO. Você não cadastra imóvel nem recebe anúncio de ninguém; quem cuida de imóvel novo é o Tel.';
BEGIN
  SELECT texto INTO v_texto FROM nai_prompt WHERE papel = 'corretor';
  IF position('ofereceu um imóvel dele' IN v_texto) > 0 THEN
    RAISE NOTICE 'a linha ja esta no prompt'; RETURN;
  END IF;
  IF position(v_ancora IN v_texto) = 0 THEN
    RAISE EXCEPTION 'nao achei a ancora no prompt';
  END IF;
  v_novo := replace(v_texto, v_ancora, v_linha || E'\n' || v_ancora);
  SELECT coalesce(max(versao), 0) + 1 INTO v_versao FROM nai_prompt_historico WHERE papel = 'corretor';
  PERFORM nai_salvar_prompt('corretor', v_novo, v_versao, 'ela nao faz cadastro: oferta de imovel vai ao Tel (Tel, 22/09)');
  RAISE NOTICE 'prompt: % -> % chars (versao %)', length(v_texto), length(v_novo), v_versao;
END $mig$;

COMMIT;

-- O QUE TEM QUE PEGAR                                    e o que NÃO pode.
SELECT nai_oferece_imovel(t) AS pega, t AS frase
  FROM unnest(ARRAY[
    'Oi Nay, eu tenho um Living Confort também Se quiser te envio',
    'Posso te passar as Fotos e endereço também',
    'posso enviar as fotos e a descrição? caso vc tenha cliente, agendamos a visita',
    'eu tenho um Smille Flores',
    'quer que eu te mande uns imóveis?',
    'Posso anunciar?',
    'Boa noite! Posso anunciar os imóveis de vocês? Trabalho mais com locação',
    'Tenho um cliente procurando 3 quartos até 5 mil',
    'Tenho uma cliente, interessada nesse imóvel, vamos fazer essa parceria??',
    'boa tarde Nay! tenho um cliente querendo visitar o 5611 amanhã às 15h',
    'posso te mandar o CPF do cliente',
    'me manda as fotos do 5611'
  ]) t;
