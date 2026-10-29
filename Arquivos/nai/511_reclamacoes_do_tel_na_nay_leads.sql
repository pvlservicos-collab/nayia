-- 511: AS RECLAMAÇÕES DO TEL DE 28/10 NA NAY LEADS (número de captação, 8595). Pedro: "todas as reclamações dele são
-- nay lead"; o link do anúncio "só no CRM".
--
-- 1. "Não conseguimos ver a mensagem que foi no grupo" (Cláudia, 92 99143-3570): ela marcou o PEDIDO DE BUSCA que a Nay
--    Leads postou às 10:15 no grupo CREDENCIADOS | Corretores Performance. O id está em privado.busca_cliente.grupos
--    (desde agora com o texto junto, nay-olx buscas.py); crm_mensagem_citada passa a procurar ali.
-- 2. "Coloquei para atender e não enviou" (Ivy, 92 99300-6380): o "Nay voltar a atender" (398) marcava como lida a
--    última mensagem recebida e ela só respondia a PRÓXIMA; o "Tem fotos?" ficou sem resposta. Agora o que a pessoa
--    escreveu depois da nossa última mensagem (nas últimas 24 h) continua por ler: a Nay responde.
-- 3. O link do anúncio da OLX (Tel: "enviar o link do imóvel para depois a gente clicar para saber se esse imóvel pelo
--    perfil vai atender o cliente"): o aviso tipo 'nota' (nay_aviso_equipe) não vira notificação; o CRM grava como
--    nota interna na conversa do telefone (crm_notas_da_nay). Ao anunciante continua sem link (Pedro, 23/10).
-- 4. Inteligências gerais (o agente das dúvidas lê antes de responder): financiamento = todos os bancos; disponibilidade
--    de parceiro só com o parceiro (o agente respondeu ao Gilson "Sim, disponível" do 4434, de parceiro, pelo cadastro).
BEGIN;

-- 1. a citação do pedido de busca no grupo
CREATE OR REPLACE FUNCTION public.crm_mensagem_citada(p_ids text[])
 RETURNS TABLE(message_id text, quem text, texto text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_id    text;
  v_quem  text;
  v_texto text;
  r       record;
BEGIN
  FOR v_id IN
    SELECT DISTINCT btrim(x) FROM unnest(coalesce(p_ids, '{}'::text[])) x
     WHERE nullif(btrim(x), '') IS NOT NULL LIMIT 300
  LOOP
    v_quem := NULL; v_texto := NULL;

    -- 1. o CARD que o publicador mandou (no grupo, ou direto ao corretor): o mesmo card, montado de novo
    SELECT e.codigo, e.destino, e.grupo_nome, e.enviado_em INTO r
      FROM envios e WHERE e.message_id = v_id ORDER BY e.enviado_em DESC LIMIT 1;
    IF FOUND AND r.codigo ~ '^[0-9]{1,6}$' THEN
      v_quem := CASE WHEN r.destino = 'grupo' THEN 'Card postado no grupo ' || coalesce(nullif(btrim(r.grupo_nome), ''), '(sem nome)')
                     ELSE 'Card enviado pela Nay' END
                || ' · ' || to_char(r.enviado_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI');
      v_texto := coalesce((SELECT nullif(btrim(c.texto_pronto), '') FROM nai_card_do_imovel(r.codigo::int) c LIMIT 1),
                          'Imóvel ' || nay_saida_rotulo_do_imovel(r.codigo));
    END IF;

    -- 2. a FOTO do post (o dedo vai na foto, não no texto)
    IF v_texto IS NULL THEN
      SELECT f.codigo, f.destino, f.grupo_nome, f.enviado_em INTO r
        FROM envios_foto f WHERE f.message_id = v_id ORDER BY f.enviado_em DESC LIMIT 1;
      IF FOUND THEN
        v_quem := CASE WHEN r.destino = 'grupo' THEN 'Foto postada no grupo ' || coalesce(nullif(btrim(r.grupo_nome), ''), '(sem nome)')
                       ELSE 'Foto enviada pela Nay' END
                  || ' · ' || to_char(r.enviado_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI');
        v_texto := '[foto] Imóvel ' || nay_saida_rotulo_do_imovel(r.codigo::text);
      END IF;
    END IF;

    -- 3. a LISTA do grupo: o que era a lista e os imóveis dela, na ordem
    IF v_texto IS NULL THEN
      SELECT min(l.grupo_nome) AS grupo_nome, min(l.enviado_em) AS enviado_em, min(l.categoria) AS categoria,
             min(l.negocio) AS negocio, count(*) AS n,
             string_agg(nay_saida_rotulo_do_imovel(l.codigo::text), E'\n' ORDER BY l.posicao) AS itens
        INTO r FROM envios_lista_grupo l WHERE l.message_id = v_id;
      IF r.n > 0 THEN
        v_quem := 'Lista postada no grupo ' || coalesce(nullif(btrim(r.grupo_nome), ''), '(sem nome)')
                  || ' · ' || to_char(r.enviado_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI');
        v_texto := 'Lista de ' || CASE r.negocio WHEN 'locacao' THEN 'locação' WHEN 'venda' THEN 'venda' ELSE coalesce(r.negocio, 'imóveis') END
                   || coalesce(' · ' || replace(r.categoria, '_', ' '), '') || ' (' || r.n || ' imóveis)' || E'\n' || r.itens;
      END IF;
    END IF;

    -- 3b. 511: o PEDIDO DE BUSCA que a Nay Leads postou num grupo de corretores (Tel, 28/10: "não conseguimos ver a
    --     mensagem que foi no grupo")
    IF v_texto IS NULL THEN
      SELECT b.id, g.item->>'nome' AS grupo_nome, g.item->>'em' AS em, g.item->>'texto' AS texto INTO r
        FROM privado.busca_cliente b, jsonb_array_elements(b.grupos) AS g(item)
       WHERE g.item->>'mid' = v_id LIMIT 1;
      IF FOUND THEN
        v_quem := 'Pedido de busca no grupo ' || coalesce(nullif(btrim(r.grupo_nome), ''), '(sem nome)')
                  || coalesce(' · ' || to_char((r.em)::timestamptz AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI'), '');
        v_texto := coalesce(nullif(btrim(r.texto), ''), '[o pedido da busca #' || r.id || ']');
      END IF;
    END IF;

    -- 4. o que a Nay mandou no privado (a velha, a nova e a antiga)
    IF v_texto IS NULL THEN
      SELECT 'Nay', coalesce(nullif(btrim(s.texto), ''), '[foto do imóvel ' || s.codigo || ']') INTO v_quem, v_texto
        FROM nai_saida s WHERE s.message_id = v_id ORDER BY s.id DESC LIMIT 1;
    END IF;
    IF v_texto IS NULL THEN
      SELECT 'Nay', coalesce(nullif(btrim(s.texto), ''), '[foto do imóvel ' || s.codigo || ']') INTO v_quem, v_texto
        FROM core_saida s WHERE s.message_id = v_id ORDER BY s.id DESC LIMIT 1;
    END IF;
    IF v_texto IS NULL THEN
      SELECT 'Nay', nullif(btrim(s.texto), '') INTO v_quem, v_texto
        FROM mensagem_saida s WHERE s.message_id = v_id LIMIT 1;
    END IF;

    -- 5. mensagem que chegou (dele mesmo, ou de grupo)
    IF v_texto IS NULL THEN
      SELECT CASE WHEN m.direcao = 'recebida' THEN nullif(btrim(m.nome), '') ELSE 'Nay' END,
             coalesce(nullif(btrim(m.texto), ''), '[' || m.origem || ']') INTO v_quem, v_texto
        FROM mensagens m WHERE m.message_id = v_id ORDER BY m.id DESC LIMIT 1;
    END IF;
    IF v_texto IS NULL THEN
      SELECT NULL, coalesce(nullif(btrim(m.texto), ''), nullif(btrim(m.transcricao), ''), '[' || m.tipo || ']') INTO v_quem, v_texto
        FROM core_mensagem m WHERE m.message_id = v_id LIMIT 1;
    END IF;
    IF v_texto IS NULL THEN
      SELECT nullif(btrim(coalesce(g.remetente, '') || coalesce(' no grupo ' || nullif(btrim(g.grupo_nome), ''), '')), ''),
             nullif(btrim(g.texto), '') INTO v_quem, v_texto
        FROM grupo_mensagens g WHERE g.message_id = v_id LIMIT 1;
    END IF;
    IF v_texto IS NULL THEN
      SELECT CASE WHEN c.direcao = 'recebida' THEN NULL ELSE 'Nay (captação)' END, nullif(btrim(c.texto), '') INTO v_quem, v_texto
        FROM captacao_mensagens c WHERE c.message_id = v_id ORDER BY c.id DESC LIMIT 1;
    END IF;

    -- 6. saiu de um robô nosso e só o registro do envio ficou: diz de onde foi
    IF v_texto IS NULL THEN
      SELECT 'Enviada pelo sistema · ' || to_char(s.em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI'),
             '[' || CASE WHEN s.rota ~ 'image' THEN 'imagem' WHEN s.rota ~ 'audio' THEN 'áudio' ELSE 'mensagem' END || ' enviada '
             || CASE s.quem WHEN 'disparar_grade.py' THEN 'pela grade dos grupos'
                            WHEN 'servidor.py' THEN 'por comando do Tel'
                            WHEN 'alertar_visitas.py' THEN 'pelo alerta de visitas'
                            WHEN 'detectar_visitas.py' THEN 'pelo detector de visitas'
                            ELSE 'por ' || coalesce(s.quem, 'um robô') END || ']'
        INTO v_quem, v_texto
        FROM saida_do_sistema s WHERE s.message_id = v_id LIMIT 1;
    END IF;

    IF v_texto IS NOT NULL THEN
      message_id := v_id; quem := v_quem; texto := left(v_texto, 3000);
      RETURN NEXT;
    END IF;
  END LOOP;
END
$function$;

-- 2. "Nay voltar a atender": o que ficou sem resposta é respondido
CREATE OR REPLACE FUNCTION public.crm_captacao_etapa_manual(p_telefone text, p_etapa text, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v_dig  text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  v_quem text := left(coalesce(nullif(btrim(p_quem), ''), 'CRM'), 80);
  v_n    int;
BEGIN
  IF length(v_dig) IN (10, 11) THEN v_dig := '55' || v_dig; END IF;
  IF v_dig !~ '^[0-9]{12,13}$' THEN
    RETURN QUERY SELECT false, 'Não entendi o telefone.'; RETURN;
  END IF;
  IF p_etapa NOT IN ('todos', 'em_andamento', 'followup', 'disponiveis', 'alugados',
                     'quer_vender', 'ja_vendeu', 'tem_outro_imovel', 'sem_resposta', 'com_o_tel', 'rayssa') THEN
    RETURN QUERY SELECT false, 'Etapa desconhecida: ' || coalesce(p_etapa, ''); RETURN;
  END IF;

  IF p_etapa = 'todos' THEN
    DELETE FROM captacao_etapa_manual WHERE telefone = v_dig;
    UPDATE captacao_leads SET humano_assumiu_em = NULL, humano_motivo = NULL
     WHERE right(telefone, 8) = right(v_dig, 8) AND humano_assumiu_em IS NOT NULL;
    -- 398: a Nay do WhatsApp (OLX/orgânico) volta a atender.
    -- 511 (Tel, 28/10, a Ivy: "coloquei para atender e não enviou"): o que a pessoa escreveu DEPOIS da nossa última
    -- mensagem, nas últimas 24 h, ficou sem resposta e continua por ler: a Nay responde já. O resto (o que já teve
    -- resposta, ou é de mais de 24 h) fica lido, como era.
    UPDATE privado.olx_lead_whatsapp o
       SET humano_em = NULL, parada_motivo = NULL, assumido_em = now(), atualizado_em = now(),
           ultima_lida = greatest(o.ultima_lida, (
             SELECT coalesce(max(m.id), 0) FROM captacao_mensagens m
              WHERE m.direcao = 'recebida'
                AND right(regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g'), 8) = right(v_dig, 8)
                AND (m.criada_em < now() - interval '24 hours'
                     OR m.id < (SELECT coalesce(max(e.id), 0) FROM captacao_mensagens e
                                 WHERE e.direcao = 'enviada'
                                   AND right(regexp_replace(coalesce(e.telefone, ''), '\D', '', 'g'), 8) = right(v_dig, 8)))))
     WHERE right(o.telefone, 8) = right(v_dig, 8) AND o.humano_em IS NOT NULL;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN QUERY SELECT true, CASE WHEN v_n > 0 THEN 'Em Todos: a Nay volta a atender e responde o que ficou sem resposta.'
                                   ELSE 'Em Todos: a etapa volta a ser a que a campanha diz.' END;
    RETURN;
  END IF;

  INSERT INTO captacao_etapa_manual (telefone, etapa, definido_por)
  VALUES (v_dig, p_etapa, v_quem)
  ON CONFLICT (telefone) DO UPDATE SET etapa = EXCLUDED.etapa, definido_por = EXCLUDED.definido_por, definido_em = now();

  -- com o Tel OU com a Rayssa: a Nay para de responder essa pessoa (o mesmo da Parceria)
  IF p_etapa IN ('com_o_tel', 'rayssa') THEN
    UPDATE captacao_leads
       SET humano_assumiu_em = coalesce(humano_assumiu_em, now()),
           humano_motivo = coalesce(humano_motivo, left('CRM: ' || v_quem || ' mandou para ' ||
                                     CASE WHEN p_etapa = 'rayssa' THEN 'a Rayssa' ELSE 'o Tel' END, 200))
     WHERE right(telefone, 8) = right(v_dig, 8);
    GET DIAGNOSTICS v_n = ROW_COUNT;
    -- 398: e a Nay do WhatsApp (OLX/orgânico) sai da conversa
    UPDATE privado.olx_lead_whatsapp
       SET humano_em = coalesce(humano_em, now()), atualizado_em = now(),
           parada_motivo = coalesce(parada_motivo, left('CRM: ' || v_quem || ' parou a Nay', 200))
     WHERE right(telefone, 8) = right(v_dig, 8);
    v_n := v_n + (SELECT count(*) FROM privado.olx_lead_whatsapp WHERE right(telefone, 8) = right(v_dig, 8));
    RETURN QUERY SELECT true, CASE WHEN v_n > 0
      THEN CASE WHEN p_etapa = 'rayssa' THEN 'Com a Rayssa: a Nay não fala mais com essa pessoa até voltar para Todos.'
                ELSE 'Com o Tel: a Nay não fala mais com essa pessoa até voltar para Todos.' END
      ELSE CASE WHEN p_etapa = 'rayssa' THEN 'Com a Rayssa.' ELSE 'Com o Tel.' END
           || ' (Essa pessoa não está na campanha, então não havia nada para calar.)' END;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'Movido para ' || CASE p_etapa
    WHEN 'em_andamento' THEN 'Em andamento' WHEN 'followup' THEN 'Follow-up'
    WHEN 'disponiveis' THEN 'Disponíveis'  WHEN 'alugados' THEN 'Alugados'
    WHEN 'quer_vender' THEN 'Quer vender'  WHEN 'ja_vendeu' THEN 'Já vendeu'
    WHEN 'tem_outro_imovel' THEN 'Tem outro imóvel' ELSE 'Sem resposta' END || '.';
END $function$;

-- 3. a nota interna na conversa (o link do anúncio da OLX)
ALTER TABLE privado.aviso_equipe DROP CONSTRAINT aviso_equipe_tipo_check;
ALTER TABLE privado.aviso_equipe ADD CONSTRAINT aviso_equipe_tipo_check
  CHECK (tipo = ANY (ARRAY['escalada', 'duvida', 'midia', 'relatorio', 'lead', 'outro', 'nota']));

CREATE OR REPLACE FUNCTION public.nay_aviso_equipe(p_fonte text, p_tipo text, p_titulo text, p_texto text, p_telefone text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  INSERT INTO privado.aviso_equipe (fonte, tipo, titulo, texto, telefone)
  VALUES (left(coalesce(nullif(btrim(p_fonte), ''), 'desconhecida'), 40),
          -- 511: 'nota' = nota interna na conversa do telefone (não é notificação)
          CASE WHEN p_tipo IN ('escalada', 'duvida', 'midia', 'relatorio', 'lead', 'outro', 'nota') THEN p_tipo ELSE 'outro' END,
          left(coalesce(nullif(btrim(p_titulo), ''), 'Aviso da Nay'), 200),
          left(coalesce(nullif(btrim(p_texto), ''), coalesce(nullif(btrim(p_titulo), ''), 'Aviso da Nay')), 20000),
          nullif(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), ''))
  RETURNING id
$function$;

-- as notificações não levam as notas (o CRM grava as notas na conversa, pela crm_notas_da_nay)
CREATE OR REPLACE FUNCTION public.crm_avisos_da_equipe(p_depois bigint)
 RETURNS TABLE(id bigint, fonte text, tipo text, titulo text, texto text, telefone text, criado_em timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT a.id, a.fonte, a.tipo, a.titulo, a.texto, a.telefone, a.criado_em
    FROM privado.aviso_equipe a
   WHERE a.id > coalesce(p_depois, 0) AND a.tipo <> 'nota'
   ORDER BY a.id
   LIMIT 200
$function$;

-- as notas dos últimos dias: o CRM grava as que ainda não estão na conversa (a conversa do anunciante pode nascer no
-- CRM depois da nota, por isso não há marcador: ele confere pelo avisoId)
CREATE OR REPLACE FUNCTION public.crm_notas_da_nay(p_dias integer DEFAULT 3)
 RETURNS TABLE(id bigint, fonte text, titulo text, texto text, telefone text, criado_em timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT a.id, a.fonte, a.titulo, a.texto, a.telefone, a.criado_em
    FROM privado.aviso_equipe a
   WHERE a.tipo = 'nota' AND a.telefone IS NOT NULL
     AND a.criado_em > now() - make_interval(days => greatest(1, least(coalesce(p_dias, 3), 30)))
   ORDER BY a.id
   LIMIT 500
$function$;
REVOKE ALL ON FUNCTION public.crm_notas_da_nay(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_notas_da_nay(integer) TO nay, nay_disparo;

-- 4. as duas regras para os agentes (o das dúvidas lê nay_inteligencia_geral antes de responder; a Nay Leads já tem
--    as duas no prompt: aplicada em 'leads')
INSERT INTO nay_inteligencia_geral (regra, porque, origem, vale_para, aplicada_em, assunto, criada_por)
SELECT x.regra, x.porque, 'tel', ARRAY['parceria', 'leads', 'captacao', 'olx'], ARRAY['leads'], x.assunto, 'migração 511'
  FROM (VALUES
    ('Imóvel que aceita financiamento aceita qualquer banco que faz financiamento habitacional (Caixa, Banco do Brasil, '
     'Itaú, Bradesco, Santander...). "Pode ser pela Caixa?" responde sim, sem perguntar à equipe. Entrada e parcela saem '
     'da simulação: não inventar números, oferecer a simulação.',
     'Tel, 28/10: "no caso ela disse que iria verificar se financiava pela caixa, mas se financia o imóvel ele pode ser '
     'financiado por todos os bancos que fazem financiamento habitacional" (Susi, Amazonas Flat #4904).',
     'financiamento'),
    ('Disponível só se confirma pelo nosso site atual. Imóvel de parceiro (e_parceiro) ou que só aparece no site antigo '
     '(imobeasy.com): o status do cadastro é cópia do site antigo e NÃO confirma nada. Pergunte ao parceiro/dono '
     '(nay_leads_perguntar_ao_dono) antes de dizer ao cliente que está disponível.',
     'Tel, 28/10: "ela está passando que o imóvel do site antigo está disponível, sendo que ela tem que pegar as '
     'informações do site atual para poder passar ao cliente, precisa confirmar antes se está disponível" (Gilson, '
     '#4434 Flex Parque Dez, de parceiro: a fila respondeu "Sim, disponível" pelo cadastro).',
     'disponibilidade')
  ) AS x(regra, porque, assunto)
 WHERE NOT EXISTS (SELECT 1 FROM nay_inteligencia_geral g WHERE g.porque = x.porque);

COMMIT;
