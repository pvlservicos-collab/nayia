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
