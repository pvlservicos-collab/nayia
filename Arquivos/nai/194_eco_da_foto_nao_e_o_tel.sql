-- =====================================================================
-- NAI -- 194: O ECO DAS PROPRIAS FOTOS NAO E O TEL (30/09/2026)
--
-- Entrevista de 29/09, pergunta 25. "Confirmar envio" so grava o message_id
-- depois do ULTIMO item do lote. O eco de uma foto chega antes, espera os 15 s
-- do no "Espera 15s (eco)", nao acha o id e -- foto nao tem texto -- tambem
-- nao casa pelo texto. Resultado: `nai_tel_assumiu` carimbava "o Tel escreveu
-- pelo celular", o fechamento saia barrado `tel_assumiu` e o que o corretor
-- escrevia nos 30 min seguintes caia em "Com o Tel". Prova: execucoes 143455 e
-- 143464 do n8n (29/09 18:05, fotos do 3854, turno 12605). Entre 27 e 29/09,
-- 11 turnos reais sem nenhum eco humano foram calados assim.
--
-- O QUE MUDA: antes de carimbar, uma regra a mais. Mensagem que chegou por
-- aqui (este no so roda para fromMe) SEM texto, com uma foto nossa em
-- 'enviando' ou 'enviado' para a mesma pessoa nos ultimos 15 minutos, e eco
-- nosso. "A mesma pessoa" inclui as linhas irmas (telefone e @lid), porque o
-- eco pode chegar com o @lid do chat.
--
-- O que continua carimbando: texto que o Tel digita, e midia sem foto nossa
-- saindo naquela conversa. Uma foto que o Tel manda a mao enquanto a Nay
-- esta mandando fotos para a mesma pessoa deixa de pausar -- e o preco
-- aceito, porque a Nay manda fotos a cada resposta e o Tel quase nunca.
--
-- Backup da versao anterior: /root/backups-funcoes/nai_tel_assumiu-20260929-2013.sql
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.nai_tel_assumiu(p_tel text, p_message_id text, p_texto text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE v_chave text := nai_chave(p_tel); v_eco boolean; v_chaves text[];
BEGIN
  IF v_chave IS NULL OR v_chave = nai_chave(nai_cfg('tel_telefone')) THEN
    RETURN jsonb_build_object('ok', false, 'motivo', 'sem_contato_ou_e_o_tel');
  END IF;
  v_eco := (nullif(p_message_id, '') IS NOT NULL AND (
              EXISTS (SELECT 1 FROM nai_saida s WHERE s.message_id = p_message_id)
           OR EXISTS (SELECT 1 FROM mensagem_saida m WHERE m.message_id = p_message_id)
           -- O PUBLICADOR TAMBEM E A NAY (27/09/2026). Ele manda pela API da
           -- Z-API e o eco volta aqui; sem estas duas linhas, cada card e cada
           -- foto que ele mandava a um corretor virava "o Tel escreveu pelo
           -- celular" e a Nay ficava 30 min calada com aquele corretor.
           OR EXISTS (SELECT 1 FROM envios e WHERE e.message_id = p_message_id)
           OR EXISTS (SELECT 1 FROM saida_do_sistema o WHERE o.message_id = p_message_id)))
        OR EXISTS (SELECT 1 FROM nai_saida s
                    WHERE s.chave_destino = v_chave AND s.estado IN ('enviado', 'enviando')
                      AND s.criado_em > now() - interval '15 minutes'
                      AND nullif(btrim(coalesce(p_texto, '')), '') IS NOT NULL
                      AND (btrim(s.texto) = btrim(p_texto) OR btrim(s.resposta->>'texto_final') = btrim(p_texto)
                           OR position(btrim(p_texto) IN coalesce(s.texto, '')) > 0));

  -- 194 (30/09): o ECO DA FOTO. Sem texto e com foto nossa saindo para a
  -- mesma pessoa (ou a linha irma dela) nos ultimos 15 min: e eco nosso.
  -- O id ainda nao foi gravado porque "Confirmar envio" so roda no fim do lote.
  IF NOT v_eco AND nullif(btrim(coalesce(p_texto, '')), '') IS NULL THEN
    v_chaves := ARRAY[v_chave]
      || coalesce((SELECT array_agg(k2.chave)
                     FROM nai_contato k
                     CROSS JOIN LATERAL unnest(nai_contato_irmaos(k.id)) AS ir(id)
                     JOIN nai_contato k2 ON k2.id = ir.id
                    WHERE k.chave = v_chave), '{}')
      || coalesce((SELECT array_agg(nai_chave(i.telefone))
                     FROM identidade_lid i
                    WHERE v_chave ~ '^lid:'
                      AND i.lid IN (substr(v_chave, 5), substr(v_chave, 5) || '@lid')), '{}');
    v_eco := EXISTS (SELECT 1 FROM nai_saida s
                      WHERE s.tipo = 'imagem'
                        AND s.estado IN ('enviando', 'enviado')
                        AND s.chave_destino = ANY (v_chaves)
                        AND coalesce(s.enviado_em, s.criado_em) > now() - interval '15 minutes');
    IF v_eco THEN
      RETURN jsonb_build_object('ok', true, 'eco_nosso', true, 'por', 'foto_sem_id');
    END IF;
  END IF;

  IF v_eco THEN RETURN jsonb_build_object('ok', true, 'eco_nosso', true); END IF;
  PERFORM nai_contato_do_cadastro(p_tel, NULL);
  -- O RELOGIO REINICIA A CADA MENSAGEM (Tel, 16/09): "essa hora e a cada
  -- mensagem que o Tel envia manualmente". O `coalesce` guardava o primeiro
  -- carimbo e nunca mais mexia: com a janela de tempo, uma conversa em que ele
  -- digitou a manha toda voltaria para a Nay no meio dela.
  --
  -- O MOTIVO continua com coalesce. Se a conversa ja estava escalada, ela
  -- segue escalada -- o carimbo novo nao a faz expirar, porque quem expira e
  -- so o motivo 'o Tel escreveu pelo celular'.
  UPDATE nai_contato SET humano_assumiu_em = now(),
                         humano_motivo = coalesce(humano_motivo, 'o Tel escreveu pelo celular')
   WHERE chave = v_chave;
  RETURN jsonb_build_object('ok', true, 'tel_assumiu', true);
END;
$function$;

COMMIT;
