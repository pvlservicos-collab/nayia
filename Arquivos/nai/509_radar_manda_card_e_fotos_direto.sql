-- 509: a Nay Captação dos Grupos (radar automático) manda o card e as fotos DIRETO, sem perguntar antes.
-- Pedro, 27/10/2026: "a Nay tá demorando a mandar imóvel quando ela acha o cara vindo do grupo, eu pedi um algoritmo
-- com um imóvel já correspondente, ela fica listando e atrasa o processo, ela deveria logo enviar card e fotos, tipo a
-- conversa do Anderson Silva". Desde a 429 o automático mandava só a pergunta ("Serve para o seu cliente? Se servir,
-- te mando as fotos"): o Anderson (6935) teve de responder "Envia" e esperar 2 min; a Silvana (6117) respondeu
-- "manda por gentileza" às 19:50 e não recebeu nada; a Julinne (3589) esperou 12 min.
--
-- site_captacao_grupos_mandar: as travas da pergunta (430: a Nay do cadastro falando com ele; o imóvel tem de ter
-- casado com o pedido), depois o mesmo envio do botão "Enviar vários imóveis" (382: abertura, card e fotos, intervalo,
-- parceiro e indisponível fora, um imóvel por número em 24 h), e o contexto para a Nay da Parceria (nay-core) SEM
-- pergunta: para ela o card já saiu (mostrados = o imóvel), então o "manda as fotos" dele não repete o envio.
-- A pergunta (site_captacao_grupos_perguntar) continua para quando a mobília do imóvel não é a que ele pediu (20/10).

BEGIN;

CREATE OR REPLACE FUNCTION public.site_captacao_grupos_mandar(p_id bigint, p_codigo integer, p_abertura text DEFAULT NULL::text, p_quem text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE
  q      privado.grupo_pedido;
  v_fone text;
  v_ids  bigint[];
  v_k    text;
  r      jsonb;
BEGIN
  SELECT * INTO q FROM privado.grupo_pedido WHERE id = p_id;
  IF q.id IS NULL THEN RETURN jsonb_build_object('erro', 'Não achei essa solicitação.'); END IF;
  v_fone := regexp_replace(coalesce(q.remetente, ''), '\D', '', 'g');
  -- 430: a Nay do cadastro está perguntando a ele sobre um imóvel: nada mais sai até ela terminar
  IF length(v_fone) BETWEEN 10 AND 13 AND cadastro_whats_da_parceria(v_fone) IS NOT NULL THEN
    RETURN jsonb_build_object('erro', 'A Nay do cadastro está falando com esse corretor agora (cadastro de imóvel). Espere ela terminar.');
  END IF;
  -- o imóvel tem de ter casado com este pedido (ou com outra parte da mesma mensagem), como na pergunta
  PERFORM privado.grupo_pedido_juntar_novos();
  SELECT array_agg(j.pedido_id) INTO v_ids
    FROM privado.grupo_pedido_junto j WHERE j.card = (SELECT card FROM privado.grupo_pedido_junto WHERE pedido_id = q.id);
  IF v_ids IS NULL THEN
    v_k := privado.grupo_pedido_chave(q.fonte, q.id, q.remetente, q.texto, q.parte);
    SELECT array_agg(c.id) INTO v_ids FROM privado.grupo_pedido c
     WHERE privado.grupo_pedido_chave(c.fonte, c.id, c.remetente, c.texto, c.parte) = v_k;
  END IF;
  v_ids := array_append(coalesce(v_ids, '{}'), q.id);
  IF NOT EXISTS (SELECT 1 FROM privado.grupo_pedido_par p JOIN privado.grupo_pedido c ON c.id = p.pedido_id
                  WHERE p.codigo = p_codigo AND (c.id = q.id OR (c.id = ANY (v_ids) AND c.fonte = q.fonte AND c.ref = q.ref))) THEN
    RETURN jsonb_build_object('erro', 'Esse imóvel não está entre os que casaram com este pedido.');
  END IF;

  r := site_captacao_grupos_enviar_varios(p_id, ARRAY[p_codigo], p_abertura, true, true, p_quem);
  IF r ? 'ok' THEN
    INSERT INTO nay_contexto_do_grupo (final8, telefone, pedido_id, codigo, pergunta, filtros, pedido_texto)
    VALUES (right(v_fone, 8), v_fone, q.id, p_codigo, NULL, privado.grupo_pedido_filtros_para_nay(q.id), q.texto);
  END IF;
  RETURN r;
END
$function$;

REVOKE ALL ON FUNCTION public.site_captacao_grupos_mandar(bigint, integer, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_captacao_grupos_mandar(bigint, integer, text, text) TO nay_site_escrita;

COMMIT;
