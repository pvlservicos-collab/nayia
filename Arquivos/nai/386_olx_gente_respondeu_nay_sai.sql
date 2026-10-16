-- 386: na conversa da OLX em que alguém da equipe respondeu, a Nay da OLX NÃO VOLTA MAIS (só se devolverem pelo CRM)
--
-- Pedro, 16/10/2026: "veja que eu respondi a Camila, a nay não deve mais responder ela na olx, implemente isso". Até aqui a
-- resposta de gente calava a Nay só por `humano_cala_horas` (24 h): no dia seguinte ela voltaria a responder a Camila por
-- cima do Tel. Agora a mensagem de gente (enviada_por que não começa com "Nay") tira a Nay da conversa de vez; o
-- "devolver para a Nay" do CRM (olx_nay_devolver, 374) continua trazendo de volta, e só a resposta de gente DEPOIS da
-- devolução a cala de novo. A conversa da Camila (chat 26, o Tel respondeu às 14:39) fica com a equipe também pela marca.
-- Backup: /root/backups-funcoes/olx_nay_fila-2026-10-16-antes-386.sql
BEGIN;
SET LOCAL lock_timeout = '3s';

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
     -- 386: gente da equipe respondeu nesta conversa (depois da última devolução): a Nay não volta mais
     AND NOT EXISTS (SELECT 1 FROM privado.olx_chat_mensagem m
                      WHERE m.chat = h.id AND m.de = 'nos' AND coalesce(m.enviada_por, '') !~* '^nay'
                        AND m.quando > coalesce(n.devolvida_em, '-infinity'::timestamptz))
   ORDER BY h.ultima_em
   LIMIT greatest(1, coalesce(p_limite, 10));
$function$;

UPDATE privado.olx_config SET descricao = '386: não vale mais para a Nay da OLX (gente respondeu = ela sai da conversa de vez); fica só como referência'
 WHERE chave = 'humano_cala_horas';

-- a Camila: o Tel respondeu às 14:39; a marca deixa claro no CRM que a conversa é da equipe
SELECT olx_nay_passar_para_gente(26, 'o Tel respondeu (16/10 14:39): a conversa é da equipe');

COMMIT;
