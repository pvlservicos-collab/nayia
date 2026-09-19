-- =====================================================================
-- NAI -- 21b: o encaixe do gatilho de PEDIDO DE IMOVEL nas funcoes vivas.
--
-- Gerado por `scratchpad/patch_pedido.py` a partir do que estava NO BANCO,
-- com dois acrescimos e nenhuma remocao:
--   1. `nai_contexto_corretor` ganha o aviso de busca, com os filtros lidos
--      da propria mensagem;
--   2. `nai_escalar` ganha a parede: quando a mensagem e busca, devolve a
--      pergunta da sequencia em vez de acionar o Tel.
--
-- Rode `21_pedido_de_imovel.sql` ANTES deste arquivo.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.nai_contexto_corretor(p_contato bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  k         nai_contato;
  v_ids     bigint[];
  v_fim8    text;
  linhas    text;
  enviados  text;
  historico text;
  v_ult     timestamptz;
  v_mem     int;
  saida     text;
  v_dados   text;
BEGIN
  SELECT * INTO k FROM nai_contato WHERE id = p_contato;
  v_fim8 := right(regexp_replace(k.telefone, '\D', '', 'g'), 8);
  -- as mensagens DESTE turno (o turno ja foi aberto quando o contexto e montado)
  SELECT coalesce(t.msg_ids, '{}') INTO v_ids FROM nai_turno t WHERE t.contato_id = p_contato ORDER BY t.id DESC LIMIT 1;

  SELECT string_agg('visita #' || x.id || ' · ' || nai_ref_imovel(x.codigo) || ' · ' ||
                    coalesce(nai_quando_humano(x.quando), 'sem horário') || ' · ' || nai_status_humano(x), E'\n' ORDER BY x.id)
    INTO linhas
    FROM nai_visita x WHERE x.corretor_id = p_contato AND nai_visita_aberta(x.estado);
  saida := CASE WHEN linhas IS NULL THEN 'este corretor nao tem visita em andamento. '
                ELSE E'visitas em andamento deste corretor (so ele ve isto; use para saber em que pe esta):\n' || linhas || E'\n' END;

  -- DADOS PEDIDOS PELO SISTEMA (fluxo v17, 13/09): depois da "Visita confirmada"
  -- o sistema pede os dados numa mensagem que NAO passa pela memoria dela. Sem
  -- esta linha, "Pedro Victor Araujo, CPF ..., CRECI 1234" virou "qual e a duvida?".
  SELECT string_agg('visita #' || x.id || ' (' || nai_ref_imovel(x.codigo) || '): falta ' ||
                    nai_lista_pt(ARRAY_REMOVE(ARRAY[
                      CASE WHEN d.nome_completo IS NULL THEN 'o nome completo dele' END,
                      CASE WHEN d.cpf IS NULL THEN 'o CPF dele' END,
                      CASE WHEN d.creci IS NULL THEN 'o CRECI dele' END,
                      CASE WHEN x.visitante_nome IS NULL THEN 'o nome completo do visitante' END,
                      CASE WHEN x.visitante_cpf IS NULL THEN 'o CPF do visitante' END], NULL)), '; ')
    INTO v_dados
    FROM nai_visita x, nai_dados_corretor(p_contato) d
   WHERE x.corretor_id = p_contato AND x.estado = 'confirmada'
     AND (x.visitante_nome IS NULL OR x.visitante_cpf IS NULL OR NOT coalesce(d.completo, false));
  IF v_dados IS NOT NULL THEN
    saida := saida || 'O SISTEMA JA PEDIU A ELE OS DADOS DA VISITA CONFIRMADA -- ' || v_dados ||
             '. Se a mensagem dele trouxer nome, CPF ou CRECI (dele ou do visitante), chame guardar_dados_da_visita NESTA resposta com tudo o que veio e diga o texto_pronto como veio (vazio = SILENCIO). NAO pergunte qual e a duvida. ';
  END IF;

  -- Imoveis que ele JA recebeu (30 dias).
  SELECT string_agg(x.codigo || ' (' || x.quando || ')', ', ' ORDER BY x.ult DESC) INTO enviados
    FROM (SELECT e.codigo, max(e.enviado_em) AS ult,
                 to_char(max(e.enviado_em) AT TIME ZONE 'America/Manaus', 'DD/MM') AS quando
            FROM envios e
           WHERE right(regexp_replace(coalesce(e.telefone, ''), '\D', '', 'g'), 8) = v_fim8
             AND e.enviado_em > now() - interval '30 days' AND e.codigo IS NOT NULL
           GROUP BY e.codigo ORDER BY max(e.enviado_em) DESC LIMIT 15) x;
  IF enviados IS NOT NULL THEN
    saida := saida || 'imoveis que ele JA RECEBEU de voce: ' || enviados ||
             '. NAO mande de novo nenhum desses sem ele pedir; ao oferecer opcoes, mande outros. ';
  END IF;

  -- O IMOVEL DESTA CONVERSA (13/09): sem isto o modelo perdia o fio -- "quero
  -- saber se e mobiliado" virava pergunta sem imovel e subia ao Tel.
  DECLARE v_imv int; BEGIN
    v_imv := nai_imovel_da_conversa(p_contato, NULL);
    IF v_imv IS NOT NULL THEN
      saida := saida || 'IMOVEL DESTA CONVERSA: ' || nai_ref_imovel(v_imv) || ' (codigo ' || v_imv ||
               '). Quando ele perguntar algo sem dizer o codigo ("e mobiliado?", "tem garagem?", "me manda as fotos"), '
               || 'e DESTE imovel que ele fala: use este codigo nas ferramentas, sem perguntar de novo. ';
    END IF;
  END;

  -- PEDIDO DE IMOVEL SEM REFERENCIA (Tel, 15/09). "Voce tem apartamento no
  -- valor de R$ 350.000 de 2 quartos?" chegou numa conversa que ja tinha um
  -- imovel em andamento, e o modelo leu como pergunta DAQUELE imovel: nao
  -- achou resposta e escalou ao Tel. Aqui o cabecalho diz, em palavras, que a
  -- mensagem e uma BUSCA -- e ja entrega os filtros que vieram nela.
  DECLARE v_ped jsonb; v_txt text; v_tem text;
  BEGIN
    SELECT t.texto INTO v_txt FROM nai_turno t WHERE t.contato_id = p_contato ORDER BY t.id DESC LIMIT 1;
    v_ped := nai_pedido_de_perfil(v_txt);
    IF (v_ped->>'e_pedido')::boolean THEN
      v_tem := nai_lista_pt(ARRAY_REMOVE(ARRAY[
                 CASE WHEN v_ped->>'bairro'  IS NOT NULL THEN 'bairro=' || (v_ped->>'bairro') END,
                 CASE WHEN v_ped->>'teto'    IS NOT NULL THEN 'teto=' || (v_ped->>'teto') END,
                 CASE WHEN v_ped->>'quartos' IS NOT NULL THEN 'quartos=' || (v_ped->>'quartos') END], NULL));
      saida := saida || 'ELE ESTA PROCURANDO IMOVEL (esta mensagem e uma BUSCA, nao e pergunta sobre o imovel '
               || 'da conversa). Chame buscar_por_perfil AGORA'
               || coalesce(' com ' || v_tem, ' sem nenhum filtro')
               || ' e diga o texto_pronto que ela devolver, exatamente como veio. Ela conduz a sequencia de '
               || 'perguntas sozinha e ja pula o que ele acabou de dizer. ';
    END IF;
  END;

  -- Ja estao conversando? (mensagem dele ou nossa antes deste turno)
  -- 14/09: nada anterior ao marco de "conversa zerada" conta como contexto --
  -- no teste ela tem que atender como se fosse a primeira mensagem do cliente.
  SELECT max(q) INTO v_ult FROM (
    SELECT max(m.criada_em) AS q FROM mensagens m
     WHERE right(regexp_replace(m.telefone, '\D', '', 'g'), 8) = v_fim8
       AND NOT (m.id = ANY (v_ids))
       AND m.criada_em > coalesce(k.zerado_em, '-infinity'::timestamptz)
    UNION ALL
    SELECT max(s.enviado_em) FROM nai_saida s
     WHERE s.contato_id = p_contato AND s.estado IN ('enviado', 'simulado')
       AND s.enviado_em > coalesce(k.zerado_em, '-infinity'::timestamptz)) u;
  IF v_ult > now() - interval '12 hours' THEN
    saida := saida || 'voces JA ESTAO CONVERSANDO (ultima troca as ' || to_char(v_ult AT TIME ZONE 'America/Manaus', 'HH24:MI') ||
             '): NAO cumprimente como se fosse a primeira vez, NAO se apresente e NAO recomece o atendimento -- siga de onde parou. ';
  ELSIF v_ult IS NOT NULL THEN
    saida := saida || 'ele ja conversou com voce antes (ultima vez em ' || to_char(v_ult AT TIME ZONE 'America/Manaus', 'DD/MM') ||
             '): cumprimente, mas trate como quem ja conhece, sem se apresentar. ';
  END IF;

  -- Visita: no maximo UMA sugestao por DIA, por corretor (Tel, 12/09).
  IF (k.visita_sugerida_em AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date THEN
    saida := saida || 'voce JA SUGERIU visita a ele (' || to_char(k.visita_sugerida_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI') ||
             '): NAO sugira de novo HOJE nem pergunte se quer agendar; so fale de visita se ELE pedir. ';
  END IF;

  -- Enquanto a memoria da NAI for curta, a conversa dele com a Nay antiga.
  SELECT count(*) INTO v_mem FROM nai_memoria WHERE session_id = 'nai:corretor:' || p_contato;
  IF v_mem < 6 AND k.chave !~ '^lid:' THEN
    SELECT string_agg(l, E'\n' ORDER BY id) INTO historico FROM (
      SELECT id, CASE WHEN message->>'type' = 'human'
                      THEN 'corretor: ' || left(regexp_replace(coalesce(substring(message->>'content' FROM 'mensagem do corretor:(.*)$'),
                                                                      message->>'content'), '\s+', ' ', 'g'), 200)
                      ELSE 'nay: ' || left(regexp_replace(message->>'content', '\s+', ' ', 'g'), 200) END AS l
        FROM nay_memoria
       WHERE session_id IN ('=' || k.telefone, '=' || nai_fone_br(k.telefone), k.telefone)
         AND message->>'type' IN ('human', 'ai') AND jsonb_typeof(message->'content') = 'string'
         AND btrim(message->>'content') <> ''
       ORDER BY id DESC LIMIT 10) h;
    IF historico IS NOT NULL THEN
      saida := saida || E'\nconversa anterior dele com voce (da mais antiga para a mais nova; use para NAO repetir pergunta nem oferta):\n'
               || historico || E'\n';
    END IF;
  END IF;
  RETURN saida;
END;
$function$;


CREATE OR REPLACE FUNCTION public.nai_escalar(p_turno bigint, p_codigo text, p_assunto text, p_disse text)
 RETURNS TABLE(texto_pronto text)
 LANGUAGE plpgsql
AS $function$
DECLARE t nai_turno; k nai_contato; e record; v_nome text; v_cod text; v_base text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  -- ANTES DE ESCALAR, A BASE (Tel, 13/09): "olá o imovel é mobiliado?" subiu ao
  -- Tel com a resposta na ficha. O codigo precisa ser dele (escrito, card que
  -- mandamos, ou o card que ele MARCOU neste turno) -- nunca da cabeca do modelo.
  v_cod := NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '');
  IF length(v_cod) BETWEEN 3 AND 5
     AND (coalesce(nay_codigo_confirmado(k.telefone, v_cod, 72), 'nao') <> 'nao'
          OR EXISTS (SELECT 1 FROM mensagens m WHERE m.id = ANY (coalesce(t.msg_ids, '{}'))
                      AND nay_imovel_da_citacao(m.citado_id) = v_cod)) THEN
    v_base := coalesce(nai_resposta_da_base(v_cod::int, p_disse), nai_resposta_da_base(v_cod::int, p_assunto));
    IF v_base IS NOT NULL THEN
      RETURN QUERY SELECT v_base;
      RETURN;
    END IF;
  END IF;
  -- PAREDE: BUSCA NAO SOBE AO TEL (Tel, 15/09). Instrucao no cabecalho o
  -- modelo pode ignorar -- e ignorou, no teste de 15/09, escalando "voce tem
  -- apartamento de 2 quartos?" em vez de procurar. Aqui a busca volta como a
  -- pergunta certa da sequencia, e o Tel nao recebe nada.
  DECLARE v_ped jsonb; r_perfil record;
  BEGIN
    v_ped := nai_pedido_de_perfil(coalesce(nullif(p_disse, ''), t.texto));
    IF (v_ped->>'e_pedido')::boolean THEN
      SELECT * INTO r_perfil FROM nai_buscar_por_perfil(
        p_turno, v_ped->>'bairro', v_ped->>'teto', v_ped->>'quartos', NULL);
      IF r_perfil.texto_pronto IS NOT NULL THEN
        RETURN QUERY SELECT r_perfil.texto_pronto;
        RETURN;
      END IF;
    END IF;
  END;

  PERFORM nai_usou_ferramenta(p_turno, 'escalar');
  v_nome := coalesce(k.nome_completo, k.nome_whatsapp, k.telefone);
  SELECT * INTO e FROM nay_escalar(k.telefone, v_nome, p_codigo, p_assunto, p_disse);
  IF e.acao IN ('escalar', 'esperar') THEN
    v_cod := NULLIF(regexp_replace(coalesce(p_codigo, ''), '\D', '', 'g'), '');
    PERFORM nai_avisar_tel(p_turno, NULL,
      'Tel, o corretor ' || v_nome || ' (' || nai_fone_fmt(k.telefone) || ') perguntou sobre o ' ||
      coalesce(CASE WHEN length(v_cod) BETWEEN 3 AND 5 THEN nai_ref_imovel(v_cod::int) END, 'imóvel') || ': "' ||
      left(coalesce(nullif(p_disse, ''), p_assunto, ''), 300) || '". Não achei na base, você sabe?' ||
      E'\nNão falei nada com ele e parei de responder esse chat: quem responde é você. Para eu voltar: DEVOLVER ' || nai_fone_fmt(k.telefone) || '.',
      'duvida_fora_da_base');
    PERFORM nai_parar_chat(k.id, 'duvida fora da base: ' || coalesce(p_assunto, ''));
    RETURN QUERY SELECT 'SILENCIO'::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT e.texto_pronto;
END;
$function$;
