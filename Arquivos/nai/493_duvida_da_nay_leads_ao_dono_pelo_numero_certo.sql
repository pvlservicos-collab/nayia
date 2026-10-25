-- 493 (Pedro, 24/10): a dúvida da Nay Leads ("aceita pet?") que o agente não achou na ficha nem nas conversas vai ao
-- proprietário pelo número em que ele JÁ conversa conosco (492): Parceria se ele já escreveu lá, senão o 8595. Nunca o
-- oficial. Antes o agente só tinha o mandar.py, que manda pela Parceria e exige contato lá.
--
-- - nay_leads_perguntar_ao_dono(fila, telefone, nome, texto): o agente enfileira; o nay-olx manda (visita.mandar_ao_dono)
--   em segundos e anota por qual linha saiu.
-- - privado.nay_leads_dono_pergunta: a fila, com a linha, o estado e o erro.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.nay_leads_dono_pergunta (
  id          bigserial PRIMARY KEY,
  fila        bigint,
  telefone    text NOT NULL,
  nome        text,
  texto       text NOT NULL,
  estado      text NOT NULL DEFAULT 'pendente' CHECK (estado IN ('pendente', 'enviada', 'erro')),
  linha       text CHECK (linha IN ('captacao', 'parceria')),
  erro        text,
  criado_em   timestamptz NOT NULL DEFAULT now(),
  enviado_em  timestamptz
);
CREATE INDEX IF NOT EXISTS nay_leads_dono_pergunta_pendente ON privado.nay_leads_dono_pergunta (id) WHERE estado = 'pendente';

CREATE OR REPLACE FUNCTION public.nay_leads_perguntar_ao_dono(p_fila bigint, p_tel text, p_nome text, p_texto text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  v_d  text := regexp_replace(coalesce(p_tel, ''), '\D', '', 'g');
  v_id bigint;
BEGIN
  IF length(v_d) < 10 OR btrim(coalesce(p_texto, '')) = '' THEN
    RAISE EXCEPTION 'diga o telefone do dono (com DDD) e o texto';
  END IF;
  -- a mesma pergunta ao mesmo dono, ainda na fila, não entra duas vezes
  SELECT id INTO v_id FROM privado.nay_leads_dono_pergunta
   WHERE estado = 'pendente' AND right(regexp_replace(telefone, '\D', '', 'g'), 8) = right(v_d, 8) AND texto = btrim(p_texto);
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  INSERT INTO privado.nay_leads_dono_pergunta (fila, telefone, nome, texto)
  VALUES (p_fila, right(regexp_replace(v_d, '^55', ''), 11), nullif(btrim(coalesce(p_nome, '')), ''), btrim(p_texto))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

COMMIT;
