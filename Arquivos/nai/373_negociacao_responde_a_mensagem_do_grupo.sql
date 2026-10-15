-- 373: a mensagem de negociação sai como RESPOSTA EM PARTICULAR à mensagem dele no grupo, e sem espera entre mensagens
--
-- Pedro, 15/10/2026: "pode tirar a regra de não poder mandar 2 msg seguidas ao corretor que solicitou, e idealmente
-- essa mensagem de negociação queria que viesse como se eu tivesse marcado a mensagem do cara no grupo e chamado no
-- pv, se não der ok mas se der quero assim".
--
-- 1) site_captacao_grupos_citacao(saida): para uma linha da nai_saida que é mensagem de negociação, o grupo e o id da
--    mensagem dele no grupo. O nay-enviador-manual manda então pela Z-API com messageId + privateAnswer = true: no PV
--    dele aparece a mensagem do grupo citada, como o "Responder em particular" do WhatsApp. Sem citação (mensagem que
--    não veio da Z-API, como a conversa importada) ou se a Z-API recusar, sai normal no PV.
-- 2) A trava do mesmo texto cai de 10 minutos para 1 (só o clique duplo). A espera entre mensagens do "Enviar ao
--    corretor" é config: intervalo_min_entre_envios = 0 em nay-grupos/config.json.

BEGIN;

CREATE OR REPLACE FUNCTION public.site_captacao_grupos_citacao(p_saida bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT jsonb_build_object('grupo', q.grupo_id, 'message_id', q.ref, 'pedido', q.id)
    FROM nai_saida s
    JOIN privado.grupo_pedido_mensagem m ON m.turno_id = s.turno_id
    JOIN privado.grupo_pedido q ON q.id = m.pedido_id
   WHERE s.id = p_saida AND s.motivo = 'captacao_ativa_negociacao' AND s.tipo = 'texto'
     AND q.fonte = 'grupo' AND q.grupo_id LIKE '%-group' AND nullif(btrim(q.ref), '') IS NOT NULL
     -- só mensagem que veio da Z-API tem id que ela reconhece (a importada da conversa exportada não tem)
     -- e nunca mensagem NOSSA: com ela a Z-API ignora o privateAnswer e a resposta cairia no grupo
     AND EXISTS (SELECT 1 FROM privado.grupo_conversa c WHERE c.message_id = q.ref AND NOT c.de_mim)
   LIMIT 1
$function$;
REVOKE ALL ON FUNCTION public.site_captacao_grupos_citacao(bigint) FROM PUBLIC;
COMMENT ON FUNCTION public.site_captacao_grupos_citacao(bigint) IS
  '373: a mensagem do grupo que a negociação cita (o enviador manda com messageId + privateAnswer).';

DO $$
DECLARE v text;
BEGIN
  v := pg_get_functiondef('public.site_captacao_grupos_mensagem(bigint,text,text)'::regprocedure);
  IF position('interval ''10 minutes''' IN v) = 0 THEN RAISE EXCEPTION 'a função mudou: não achei a trava de 10 minutos'; END IF;
  v := replace(v, 'interval ''10 minutes''', 'interval ''1 minute''');
  v := replace(v, 'Essa mesma mensagem já foi para ele há menos de 10 minutos.', 'Essa mesma mensagem acabou de ir para ele (clique duplo?).');
  EXECUTE v;
END $$;

COMMIT;
