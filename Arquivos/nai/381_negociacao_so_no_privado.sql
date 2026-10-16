-- 381: a MENSAGEM DE NEGOCIAÇÃO da captação ativa vai SÓ no privado do corretor (a citação da mensagem do grupo sai)
--
-- Pedro, 16/10/2026: "as mensagens de negociação não estão saindo pelo número de parceria". Medido: das 3 que ele mandou,
-- a de 15/10 11:17 (antes da 373) foi normal no privado; as duas que foram como "responder em particular" (373) CAÍRAM
-- NO GRUPO, citando a mensagem do corretor: 15/10 11:30 "oi, bom dia !" no "🟢 Locação OFERTA e BUSCA 🔍 - CREDENCIADOS"
-- e 16/10 12:54 "oi, boa tarde !" no "🟢 Alto Padrão - OFERTA e BUSCA 🔍" (privado.grupo_conversa, de_mim). A Z-API
-- aceitou o privateAnswer sem erro e mandou no grupo mesmo assim, também com mensagem de corretor (a 373 já tinha visto
-- isso com mensagem nossa).
--
-- O enviador (nay-publicador/enviador_manual.py, citacao_do_grupo) pergunta a esta função qual mensagem citar; sem
-- resposta, manda normal no privado. Agora ela só responde com a chave negociacao_citar_no_grupo = 'sim', que nasce
-- 'nao'. Religar só depois de provar num grupo de teste que a Z-API entrega em particular.
-- Backup: /root/backups-funcoes/site_captacao_grupos_citacao-2026-10-16-antes-381.sql
BEGIN;
SET LOCAL lock_timeout = '3s';

INSERT INTO nai_config (chave, valor, descricao)
VALUES ('negociacao_citar_no_grupo', 'nao',
        '381: sim = a mensagem de negociação vai como "responder em particular" à mensagem do grupo. Desligada: a Z-API mandou no GRUPO')
ON CONFLICT (chave) DO UPDATE SET valor = 'nao', descricao = EXCLUDED.descricao, atualizado_em = now();

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
     -- 381: desligada. Com o privateAnswer a Z-API mandou a negociação NO GRUPO (15/10 e 16/10): sem citação, vai no privado
     AND coalesce(nai_cfg('negociacao_citar_no_grupo'), 'nao') = 'sim'
     AND q.fonte = 'grupo' AND q.grupo_id LIKE '%-group' AND nullif(btrim(q.ref), '') IS NOT NULL
     -- só mensagem que veio da Z-API tem id que ela reconhece (a importada da conversa exportada não tem)
     -- e nunca mensagem NOSSA: com ela a Z-API ignora o privateAnswer e a resposta cairia no grupo
     AND EXISTS (SELECT 1 FROM privado.grupo_conversa c WHERE c.message_id = q.ref AND NOT c.de_mim)
   LIMIT 1
$function$;

COMMIT;
