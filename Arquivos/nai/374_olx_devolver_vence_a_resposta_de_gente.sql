-- 374 -- DEVOLVER A CONVERSA DA OLX PARA A NAY VALE DE VERDADE
--
-- Pedro, 15/10/2026: "responda todas as outras". A da Rebecca (conversa 7) tinha resposta de gente às 08:06 ("pode me
-- passar o seu nome e whatsapp?"), e a regra "gente respondeu, a Nay cala por 24 h" (364) continuava valendo mesmo
-- depois do `olx_nay_devolver`: devolver só limpava a marca, a mensagem de gente seguia calando a Nay.
-- Agora a devolução tem hora (`devolvida_em`) e só a mensagem de gente DEPOIS dela cala a Nay.
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE privado.olx_chat_nay ADD COLUMN IF NOT EXISTS devolvida_em timestamptz;
COMMENT ON COLUMN privado.olx_chat_nay.devolvida_em IS
  '374: quando a equipe devolveu a conversa para a Nay; mensagem de gente antes disso não cala mais a Nay';

CREATE OR REPLACE FUNCTION public.olx_nay_devolver(p_chat bigint)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  INSERT INTO privado.olx_chat_nay AS n (chat, devolvida_em) VALUES (p_chat, now())
  ON CONFLICT (chat) DO UPDATE
     SET humano_em = NULL, humano_motivo = NULL, reservada_em = NULL, devolvida_em = now(), atualizado_em = now();
$function$;

CREATE OR REPLACE FUNCTION public.olx_nay_fila(p_limite integer DEFAULT 10)
 RETURNS TABLE(chat bigint, conta text, list_id text, nome text, ultima_em timestamp with time zone, ultima_texto text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT h.id, h.conta, h.list_id, h.nome, h.ultima_em, h.ultima_texto
    FROM privado.olx_chat h
    LEFT JOIN privado.olx_chat_nay n ON n.chat = h.id
   WHERE h.ultima_de = 'comprador'
     AND h.ultima_em < now() - make_interval(secs => greatest(0, coalesce(nullif(olx_cfg('nay_silencio_s'), '')::int, 20)))
     AND h.ultima_em > now() - interval '3 days'
     AND n.humano_em IS NULL
     AND (n.reservada_em IS NULL OR n.reservada_em < now() - interval '5 minutes')
     AND NOT EXISTS (SELECT 1 FROM privado.olx_chat_mensagem m
                      WHERE m.chat = h.id AND m.de = 'nos' AND coalesce(m.enviada_por, '') !~* '^nay'
                        AND m.quando > now() - make_interval(hours => greatest(0, coalesce(nullif(olx_cfg('humano_cala_horas'), '')::int, 24)))
                        AND m.quando > coalesce(n.devolvida_em, '-infinity'::timestamptz))
   ORDER BY h.ultima_em
   LIMIT greatest(1, coalesce(p_limite, 10));
$function$;

COMMIT;
