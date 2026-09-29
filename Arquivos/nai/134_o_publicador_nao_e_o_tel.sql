-- =====================================================================
-- 134 — O QUE O PUBLICADOR MANDA NÃO É O TEL (27/09/2026)
--
-- Achado ao montar a fila nova (133): no fluxo da NAI, todo eco (`fromMe`)
-- espera 15s e passa por `nai_tel_assumiu`, que decide se foi a Nay ou se foi
-- o Tel digitando no celular. Ela só conhecia o que a NAI (`nai_saida`) e a
-- Nay antiga (`mensagem_saida`) mandam. O PUBLICADOR ficava de fora.
--
-- MEDIDO nas ~1.200 últimas execuções: 285 ecos que saíram PELA API foram
-- julgados "o Tel assumiu", contra 2 reconhecidos como eco. Desses 285: 257
-- fotos sem registro nenhum (o publicador só guardava o id do CARD), 15 cards
-- que ESTAVAM em `envios` e 13 textos. 87 contatos carimbados em 3 dias.
--
-- EFEITO: o Tel manda "envia 92 ... o 3210", o publicador manda card e fotos,
-- e a Nay fica 30 minutos calada com aquele corretor -- justo quando ele
-- responde.
--
-- O CONSERTO: `saida_do_sistema` guarda o id de TUDO que o publicador manda
-- (texto e cada foto, gravado em `enviar_zapi._post`), e a decisão passa a
-- olhar também `envios` e esta tabela. O que o CRM manda continua contando
-- como gente -- lá é uma pessoa digitando, e parar a Nay é o certo.
--
-- Aprovado pelo usuário: "Sim, corrigir".
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS saida_do_sistema (
  message_id text PRIMARY KEY,
  telefone   text,
  rota       text,
  -- o script que mandou (servidor.py, disparar_lembretes.py...)
  quem       text,
  em         timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.nai_tel_assumiu(p_tel text, p_message_id text, p_texto text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE v_chave text := nai_chave(p_tel); v_eco boolean;
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
