-- =====================================================================
-- NAI -- 113: o texto espera as fotos, e o link vira pergunta ao Tel
-- (Tel, 23/09/2026)
--
-- Ele: "ela manda mensagem no meio das fotos, pede para ela so mandar a
-- proxima mensagem quando finalizar de enviar todas as fotos" e "organiza um
-- envio de links para o tel e pergunta e responde o cliente conforme o que ele
-- disser".
--
-- ============ 1. O TEXTO NO MEIO DAS FOTOS ============
-- O QUE A GEINA RECEBEU hoje as 11:55 (lido no eco, nao na fila):
--     11:55:00 .. 11:55:26   16 fotos
--     11:55:31   texto  "Ou se tiver alguma duvida ou quiser mais imoveis..."
--     11:55:37   foto
--     11:55:48   foto
--     11:55:53   texto  "Aqui as fotos, quer fazer uma visita?"
--
-- Repare que ate os dois textos trocaram de lugar entre si. A fila estava na
-- ordem certa; quem desordena e a ENTREGA: texto vai na hora, foto tem que
-- subir. Serializar a fila nao resolve -- a Z-API responde "ok" assim que
-- aceita a foto, nao quando o WhatsApp entrega.
--
-- ENTAO O TEXTO GANHA HORA MARCADA: cada texto sai depois de
-- (fotos na frente dele) x `segundos_por_foto`. Medido no eco: as 16 fotos
-- levaram 26 segundos, ~1,6s cada; o padrao fica em 2,5s, com folga.
--
-- ============ 2. O LINK DO CATALOGO ============
-- A 111 mandava o link para o Tel como AVISO -- ele lia, mas nao tinha como
-- responder pelo sistema. Agora abre PENDENCIA: ele responde
-- "RESPOSTA <n> <texto>" no WhatsApp dele, como ja faz, e a resposta vai para
-- o corretor sozinha. E o mesmo caminho que a secretaria usa desde a 99.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO nai_config (chave, valor) VALUES ('segundos_por_foto', '2.5')
ON CONFLICT (chave) DO NOTHING;

-- 1 ------------------------------ CADA TEXTO ESPERA AS FOTOS DA FRENTE
CREATE OR REPLACE FUNCTION public.nai_espacar_depois_das_fotos(p_turno bigint)
 RETURNS integer LANGUAGE plpgsql
AS $function$
DECLARE
  v_seg numeric := coalesce(nullif(nai_cfg('segundos_por_foto', '2.5'), ''), '2.5')::numeric;
  n int := 0;
BEGIN
  -- Vale para QUALQUER texto, nao so o fechamento: se o card do segundo
  -- imovel esta atras de dez fotos do primeiro, ele tambem espera. Assim a
  -- conversa chega na ordem em que foi escrita.
  UPDATE nai_saida s
     SET enviar_apos = greatest(s.enviar_apos, now() + (v_seg * x.fotos_na_frente) * interval '1 second')
    FROM (SELECT a.id,
                 (SELECT count(*) FROM nai_saida b
                   WHERE b.turno_id = a.turno_id AND b.tipo = 'imagem' AND b.ordem < a.ordem) AS fotos_na_frente
            FROM nai_saida a
           WHERE a.turno_id = p_turno AND a.tipo = 'texto' AND a.estado = 'pendente') x
   WHERE s.id = x.id AND x.fotos_na_frente > 0;
  GET DIAGNOSTICS n = ROW_COUNT;

  IF n > 0 THEN
    PERFORM nai_anotar(p_turno, 21, 'texto_espera_as_fotos', 'mudou',
                       n || ' mensagens com hora marcada para depois das fotos');
  END IF;
  RETURN n;
END;
$function$;

-- 2 ------------------------- LIGADO NO FIM DA MONTAGEM DA RESPOSTA
DO $mig$
DECLARE v_def text; v_alvo text;
BEGIN
  v_def := pg_get_functiondef('nai_enfileirar_resposta'::regproc);
  IF position('nai_espacar_depois_das_fotos' IN v_def) > 0 THEN
    RAISE NOTICE 'o espacamento ja esta ligado'; RETURN;
  END IF;
  v_alvo := '  PERFORM nai_anotar(p_turno, 20, ''montagem'', ''passou'', v_textos || '' mensagens e '' || v_fotos || '' fotos na caixa de saída'');';
  IF position(v_alvo IN v_def) = 0 THEN
    RAISE EXCEPTION 'nao achei o fim da montagem';
  END IF;
  EXECUTE replace(v_def, v_alvo, v_alvo || E'\n\n'
    || '  -- O TEXTO ESPERA AS FOTOS (113). Tem que ser aqui, com a caixa ja' || E'\n'
    || '  -- montada: so agora da para saber quantas fotos estao na frente de' || E'\n'
    || '  -- cada mensagem.' || E'\n'
    || '  PERFORM nai_espacar_depois_das_fotos(p_turno);');
  RAISE NOTICE 'espacamento ligado na montagem';
END $mig$;

-- 3 ------------- A AGENDA NAO PODE FAZER O TEXTO ESPERAR 3 MINUTOS
-- A regra dos 3 minutos existe para nao pegar resposta de turno que ainda esta
-- sendo montado. Texto com hora marcada por nos ja passou por essa montagem --
-- ele so esta esperando a foto -- entao nao precisa cumprir a carencia.
DO $mig$
DECLARE v_def text; v_alvo text;
BEGIN
  v_def := pg_get_functiondef('nai_liberar_saida'::regproc);
  IF position('hora marcada' IN v_def) > 0 THEN
    RAISE NOTICE 'a agenda ja solta o texto com hora marcada'; RETURN;
  END IF;
  v_alvo := '         OR (p_turno IS NULL AND (s.turno_id IS NULL OR s.criado_em < now() - interval ''3 minutes'')';
  IF position(v_alvo IN v_def) = 0 THEN
    RAISE EXCEPTION 'nao achei a regra dos 3 minutos';
  END IF;
  EXECUTE replace(v_def, v_alvo,
    '         OR (p_turno IS NULL AND (s.turno_id IS NULL OR s.criado_em < now() - interval ''3 minutes''' || E'\n'
 || '                                   -- com hora marcada (113): e o texto que espera as fotos' || E'\n'
 || '                                   OR s.enviar_apos > s.criado_em + interval ''1 second'')');
  RAISE NOTICE 'agenda solta o texto com hora marcada';
END $mig$;

-- 4 ------------------ O LINK DO CATALOGO VIRA PERGUNTA QUE ELE RESPONDE
CREATE OR REPLACE FUNCTION public.nai_escalar_link_de_catalogo(p_turno bigint, p_escreveu text)
 RETURNS text LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; k nai_contato; v_nome text; v_pend int;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  IF k.id IS NULL THEN RETURN NULL; END IF;
  v_nome := coalesce(k.nome_completo, k.nome_whatsapp, k.telefone);

  -- A MESMA MESA DE PENDENCIAS de sempre: ele responde "RESPOSTA <n> <texto>"
  -- e o corretor recebe. Sem isto ele lia o link e nao tinha por onde
  -- responder -- a conversa morria com ele.
  INSERT INTO pendencias (codigo, o_que_falta, de_quem, avisar, status)
       VALUES (NULL, left('link do catálogo: ' || coalesce(p_escreveu, ''), 400),
               'secretaria', regexp_replace(coalesce(k.telefone, ''), '\D', '', 'g'), 'aberta')
    RETURNING id INTO v_pend;

  PERFORM nai_avisar_tel(p_turno, NULL,
    'Tel, ' || v_nome || ' (' || nai_fone_fmt(k.telefone) || ') perguntou de um imóvel mandando o '
    || 'link do catálogo do WhatsApp:' || E'\n' || left(coalesce(p_escreveu, ''), 400) || E'\n'
    || 'O link não diz qual imóvel é — só você abrindo dá para ver.'
    || E'\nMe diz o que responder: RESPOSTA ' || v_pend || ' <o que eu digo a ele>. '
    || 'Eu mando para ele e guardo para a próxima.',
    'link_de_catalogo');

  PERFORM nai_usou_ferramenta(p_turno, 'escalar');

  RETURN ('Recebi' || coalesce(', ' || nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)), '')
          || '! Já te respondo por aqui.')::text;
END;
$function$;

COMMIT;

SELECT 'segundos por foto' AS o, nai_cfg('segundos_por_foto', '?') AS valor
UNION ALL
SELECT 'com 16 fotos, o texto sai em', (16 * 2.5)::text || ' segundos';
