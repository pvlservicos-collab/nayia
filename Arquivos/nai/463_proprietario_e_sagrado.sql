-- 463: o proprietário é sagrado para a Nay (Pedro, 22/10/2026). O caso: o Dunhellington ("DOS" no WhatsApp), dono do
-- 9019, recebeu o card pelo comando de ontem e hoje às 9h o follow-up de CORRETOR do sistema velho (nai_followup_rodar):
-- "Oi DOS, seu cliente tem interesse?" e "DOS, qualquer coisa temos muitas opções...". Ele: "Não entendi".
-- Pedro: "ela nunca deve entrar em contato com o proprietário se não for algo relacionado a visita ou fechamento, essa
-- aba proprietário do CRM é sagrada, a Nay não atende lá, só faz solicitações e tira dúvidas"; "salve todos os contatos
-- de proprietários em uma blacklist para ela não atender, só faz solicitações quando pedimos"; "sempre quando ela for
-- falar com o proprietário ela deve chamar pelo nome e não siglas ... se ela não souber o nome ela não coloca o nome";
-- "às vezes tem os nomes dos proprietários nas conversas, checa todas as com proprietários do número parceria e
-- atualiza os números deles para terem o nome".
--
-- 1. nay_proprietario_bloqueio: a LISTA salva dos donos (cadastro do site, admin antigo, captação, dono de visita; sem
--    corretor parceiro). nai_e_proprietario_contato olha a lista primeiro (rápido: a regra antiga varre os cadastros sem
--    índice e passava de 60 s numa contagem) e, fora dela, a regra de antes (dono novo continua pego). Entrar à mão:
--    INSERT INTO nay_proprietario_bloqueio (chave, nome, fontes) VALUES (nai_chave('5592...'), 'Nome', '{manual}').
-- 2. nai_followup_rodar pula proprietário ("seu cliente tem interesse?" é de corretor).
-- 3. nay_vocativo_dono: o nome do dono sem sigla ("DOS", "JR" -> sem nome) e sem caixa alta ("ANA PAULA" -> "Ana"); nas
--    mensagens ao dono (nai_pedir_ao_proprietario, nai_visita_para_a_rayssa).
-- 4. Os contatos de dono da linha da Parceria sem nome_completo ganham o nome do cadastro (149 em 22/10). O que estava
--    vazio fica em privado.nai_contato_nome_antes_463 (desfazer: devolver NULL a esses ids).
-- Desfazer as funções: reaplicar os pg_get_functiondef de /root/backups-funcoes/*-20261022-463.sql.

BEGIN;

CREATE TABLE IF NOT EXISTS nay_proprietario_bloqueio (
  chave        text PRIMARY KEY,                 -- nai_chave do telefone
  nome         text,
  fontes       text[] NOT NULL DEFAULT '{}',
  criado_em    timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now());
COMMENT ON TABLE nay_proprietario_bloqueio IS '463: os proprietários. A Nay não atende nem manda nada que não seja visita, fechamento ou pedido da equipe.';
GRANT SELECT ON nay_proprietario_bloqueio TO nay_leitura;

CREATE OR REPLACE FUNCTION public.nay_proprietario_bloqueio_atualizar()
 RETURNS integer LANGUAGE sql
AS $f$
  WITH f AS (
    SELECT nai_chave(p.telefone) AS chave, btrim(p.nome) AS nome, 'cadastro' AS fonte FROM proprietarios p
     WHERE coalesce(btrim(p.telefone), '') <> ''
    UNION ALL SELECT nai_chave(a.telefone), btrim(a.nome), 'admin antigo' FROM proprietarios_admin a
     WHERE coalesce(btrim(a.telefone), '') <> ''
    UNION ALL SELECT l.telefone_chave, btrim(l.nome), 'captacao' FROM captacao_leads l WHERE l.telefone_chave IS NOT NULL
    UNION ALL SELECT c.chave, btrim(v.proprietario_nome), 'visita' FROM nai_visita v JOIN nai_contato c ON c.id = v.proprietario_id),
  corr AS (SELECT DISTINCT nai_chave(telefone) AS chave FROM corretores WHERE coalesce(btrim(telefone), '') <> ''),
  d AS (SELECT chave,
               -- o nome que é nome: o do cadastro primeiro
               (array_agg(nome ORDER BY CASE fonte WHEN 'cadastro' THEN 1 WHEN 'visita' THEN 2 WHEN 'admin antigo' THEN 3 ELSE 4 END)
                  FILTER (WHERE nome ~ '[[:alpha:]]{3}'))[1] AS nome,
               array_agg(DISTINCT fonte) AS fontes
          FROM f WHERE chave IS NOT NULL AND length(chave) >= 10 AND chave NOT IN (SELECT chave FROM corr) GROUP BY chave),
  u AS (INSERT INTO nay_proprietario_bloqueio AS b (chave, nome, fontes) SELECT chave, nome, fontes FROM d
        ON CONFLICT (chave) DO UPDATE SET nome = coalesce(b.nome, excluded.nome),
                                          fontes = (SELECT array_agg(DISTINCT x) FROM unnest(b.fontes || excluded.fontes) x),
                                          atualizado_em = now()
        RETURNING 1)
  SELECT count(*)::integer FROM u
$f$;
SELECT nay_proprietario_bloqueio_atualizar() AS donos_na_lista;

-- o nome do dono: sem sigla, sem caixa alta, sem nome quando não há nome
CREATE OR REPLACE FUNCTION public.nay_vocativo_dono(p_nome text)
 RETURNS text LANGUAGE sql STABLE
AS $f$
  SELECT CASE
    WHEN v IS NULL THEN NULL
    -- sigla: o nome inteiro é uma palavra só, maiúscula, de até 4 letras ("DOS"), ou o primeiro nome não tem vogal ("JR")
    WHEN btrim(p_nome) ~ '^[[:upper:]]{1,4}$' OR lower(unaccent(v)) !~ '[aeiouy]' THEN NULL
    WHEN v = upper(v) THEN initcap(lower(v))
    ELSE v END
  FROM (SELECT nai_vocativo(p_nome) AS v) x
$f$;

CREATE OR REPLACE FUNCTION public.nai_e_proprietario_contato(p_contato bigint)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
-- A MESMA REGRA DA ABA PROPRIETÁRIOS DO CRM (crm_parceria_marcas, 173): o cadastro
-- do site, o do admin antigo, quem a captação procurou ou o dono de uma visita;
-- corretor parceiro não é proprietário, e a equipe não é nem um nem outro.
DECLARE
  v_ids    bigint[] := coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]);
  v_chaves text[];
BEGIN
  IF p_contato IS NULL OR nai_e_da_equipe_contato(p_contato) THEN RETURN false; END IF;
  SELECT array_agg(DISTINCT c.chave) INTO v_chaves FROM nai_contato c WHERE c.id = ANY (v_ids) AND c.chave IS NOT NULL;
  IF EXISTS (SELECT 1 FROM corretores c WHERE nai_chave(c.telefone) = ANY (v_chaves)) THEN RETURN false; END IF;
  -- 463: a lista salva dos donos (rápida); fora dela, a regra de antes pega o dono novo
  IF EXISTS (SELECT 1 FROM nay_proprietario_bloqueio b WHERE b.chave = ANY (v_chaves)) THEN RETURN true; END IF;
  RETURN EXISTS (SELECT 1 FROM nai_visita v WHERE v.proprietario_id = ANY (v_ids))
      OR EXISTS (SELECT 1 FROM proprietarios p WHERE coalesce(p.telefone, '') <> '' AND nai_chave(p.telefone) = ANY (v_chaves))
      OR EXISTS (SELECT 1 FROM proprietarios_admin a WHERE coalesce(a.telefone, '') <> '' AND nai_chave(a.telefone) = ANY (v_chaves))
      OR EXISTS (SELECT 1 FROM captacao_leads l WHERE l.telefone_chave = ANY (v_chaves));
END $function$;

CREATE OR REPLACE FUNCTION public.nai_followup_rodar()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_hoje   date := (now() AT TIME ZONE 'America/Manaus')::date;
  v_hora   time := (now() AT TIME ZONE 'America/Manaus')::time;
  r        record;
  v_ct     bigint;
  v_ids    bigint[];
  v_chaves text[];
  v_nome   text;
  v_pula   text;
  v_feitos int := 0;
  v_lim    int := greatest(nai_cfg_int('followup_por_minuto', 2), 1);
  v_dias   date[];
BEGIN
  IF nai_cfg('followup_ligado', 'nao') <> 'sim' THEN RETURN 0; END IF;
  IF nai_cfg('pausada', 'sim') <> 'nao' OR nai_cfg('modo', 'desligado') <> 'todos' THEN RETURN 0; END IF;
  IF extract(isodow FROM now() AT TIME ZONE 'America/Manaus') = 7 THEN RETURN 0; END IF;   -- domingo
  IF v_hora < nai_cfg('followup_inicio', '09:00')::time OR v_hora > nai_cfg('followup_fim', '18:00')::time THEN RETURN 0; END IF;

  -- 415: na segunda, o sábado também (domingo ela não roda; antes o sábado nunca ganhava follow-up). O dia gravado é o
  -- último em que recebeu; quem recebeu no sábado E no domingo ganha um só.
  v_dias := CASE WHEN extract(isodow FROM v_hoje) = 1 THEN ARRAY[v_hoje - 2, v_hoje - 1] ELSE ARRAY[v_hoje - 1] END;
  FOR r IN
    SELECT e.chave, array_agg(DISTINCT e.codigo ORDER BY e.codigo) AS codigos, min(e.primeiro_em) AS primeiro,
           max((e.primeiro_em AT TIME ZONE 'America/Manaus')::date) AS dia
      FROM imovel_enviado_no_dia e
     WHERE (e.primeiro_em AT TIME ZONE 'America/Manaus')::date = ANY (v_dias)
       AND NOT EXISTS (SELECT 1 FROM nai_followup f WHERE f.chave = e.chave AND f.dia_recebeu = ANY (v_dias))
     GROUP BY e.chave
     ORDER BY min(e.primeiro_em)
  LOOP
    EXIT WHEN v_feitos >= v_lim;
    v_pula := NULL;
    SELECT id INTO v_ct FROM nai_contato WHERE chave = r.chave;
    IF v_ct IS NULL THEN v_ct := nai_contato_do_cadastro(r.chave, NULL); END IF;
    v_ids := nai_contato_irmaos(v_ct);
    SELECT array_agg(chave) INTO v_chaves FROM nai_contato WHERE id = ANY (v_ids);

    IF nay_fora_da_regra_do_dia(r.chave) THEN
      v_pula := 'equipe ou teste';
    ELSIF nai_e_proprietario_contato(v_ct) THEN
      v_pula := 'proprietário';                             -- 463: "seu cliente tem interesse?" é de corretor
    ELSIF EXISTS (SELECT 1 FROM nai_followup f WHERE f.chave = ANY (v_chaves) AND f.dia_recebeu = ANY (v_dias)) THEN
      v_pula := 'a outra linha dele já recebeu';
    ELSIF EXISTS (SELECT 1 FROM mensagens m WHERE nai_chave(m.telefone) = ANY (v_chaves) AND m.direcao = 'recebida'
                   AND m.criada_em > r.primeiro AND nai_recusou(m.texto)) THEN
      v_pula := 'recusou';
    ELSIF EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = ANY (v_ids) AND nai_visita_aberta(x.estado)) THEN
      v_pula := 'visita em andamento';
    ELSIF nai_tel_com_a_conversa(v_ct) THEN
      v_pula := 'o Tel está com a conversa';
    ELSIF cadastro_whats_da_parceria(r.chave, v_ct) IS NOT NULL THEN
      v_pula := 'a Nay do cadastro está falando com ele';      -- 430
    ELSIF EXISTS (SELECT 1 FROM mensagens m WHERE nai_chave(m.telefone) = ANY (v_chaves) AND m.direcao = 'recebida'
                   AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = v_hoje) THEN
      v_pula := 'já conversou hoje';
    ELSIF EXISTS (SELECT 1 FROM nai_corretor_pergunta q WHERE q.chave = ANY (v_chaves) AND q.decisao = 'nao') THEN
      v_pula := 'o Tel disse que não é corretor';
    ELSIF btrim(nai_cfg('so_estes_numeros', '')) <> '' AND NOT nai_na_lista_curta(v_ct, r.chave) THEN
      v_pula := 'fora da lista curta';
    END IF;

    IF v_pula IS NOT NULL THEN
      INSERT INTO nai_followup (chave, dia_recebeu, contato_id, codigos, estado, motivo)
      VALUES (r.chave, r.dia, v_ct, r.codigos, 'pulado', v_pula) ON CONFLICT DO NOTHING;
      CONTINUE;
    END IF;

    SELECT nai_vocativo(coalesce(k.nome_completo, k.nome_whatsapp)) INTO v_nome FROM nai_contato k WHERE k.id = v_ct;
    INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, texto, ordem, motivo, enviar_apos)
    VALUES (NULL, v_ct, 'seguimento', '', 'texto',
            'Oi' || coalesce(' ' || v_nome, '') || ', seu cliente tem interesse?', 1, 'followup', now());
    INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, texto, ordem, motivo, enviar_apos)
    VALUES (NULL, v_ct, 'seguimento', '', 'texto',
            coalesce(v_nome || ', q', 'Q') || 'ualquer coisa temos muitas opções de imóveis para locação e venda, '
            || 'o que está procurando para seus clientes?', 2, 'followup', now() + interval '8 seconds');
    INSERT INTO nai_followup (chave, dia_recebeu, contato_id, codigos, estado)
    VALUES (r.chave, r.dia, v_ct, r.codigos, 'enviado') ON CONFLICT DO NOTHING;
    v_feitos := v_feitos + 1;
  END LOOP;
  RETURN v_feitos;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_pedir_ao_proprietario(p_visita bigint, p_turno bigint)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v       nai_visita;
  c       nai_contato;
  dono    record;
  v_prop  bigint;
  v_voc   text;
  v_texto text;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  SELECT * INTO c FROM nai_contato WHERE id = v.corretor_id;
  SELECT * INTO dono FROM nai_proprietario_do_imovel(v.codigo);
  -- 141: o telefone que a Rayssa mandou (TELEFONE <n> <numero>) vale mais que o cadastro.
  IF v.prop_telefone_manual IS NOT NULL THEN
    dono.telefone := v.prop_telefone_manual;
    dono.motivo   := NULL;
    -- sem nome no cadastro, fica sem vocativo ("Bom dia!", nunca "Bom dia, proprietario!")
  END IF;
  IF dono.motivo IS NULL THEN
    v_prop := nai_contato_do_cadastro(dono.telefone, dono.nome);
  END IF;

  -- Sem telefone, cadastro dizendo "tratar com", dois donos -- ou o
  -- "proprietario" e o proprio corretor: o Tel resolve.
  IF v_prop IS NULL OR v_prop = v.corretor_id THEN
    UPDATE nai_visita SET estado = 'com_tel', aguardando = 'tel', atualizado_em = now() WHERE id = v.id;
    PERFORM nai_evento(v.id, 'proprietario_sem_contato', coalesce(dono.motivo, 'mesmo_contato'));
    PERFORM nai_avisar_tel(p_turno, v.id,
      'Tel, pedido de visita no ' || nai_ref_imovel(v.codigo) || ', ' || nai_hora_exata(v.quando) || '.' ||
      E'\nCorretor: ' || coalesce(c.nome_completo, c.nome_whatsapp, '') || ' (' || nai_fone_fmt(c.telefone) || ')' ||
      E'\nNão consigo falar com o proprietário (' ||
      CASE dono.motivo WHEN 'sem_telefone' THEN 'sem telefone no cadastro'
                       WHEN 'tratar_com_outra_pessoa' THEN 'o cadastro diz: ' || coalesce(dono.nome, '')
                       WHEN 'dois_donos' THEN 'o imóvel tem dois proprietários no cadastro'
                       WHEN 'sem_cadastro' THEN 'imóvel sem proprietário cadastrado'
                       ELSE 'o telefone do proprietário é o do próprio corretor' END || ').' ||
      E'\nParei de responder esse corretor até você responder.\nQuando resolver, me responda:\nVISITA ' || v.id || E' OK  (proprietário confirmou)\nVISITA ' || v.id ||
      E' HORARIO 16h  (ele pediu outro horário)\nVISITA ' || v.id || ' CANCELA',
      'sem_proprietario');
    PERFORM nai_parar_chat(v.corretor_id, 'visita #' || v.id || ': sem contato do proprietario');
    RETURN 'com_tel';
  END IF;

  v_voc := nay_vocativo_dono(dono.nome);   -- 463: sem sigla
  -- Card p_solicita, humanizado como o Tel pediu ("hoje a tarde", sem data numerica).
  -- A APRESENTACAO (Tel, 15/09), so na primeira vez com este proprietario: ele
  -- ja fala com a Imob Easy em outro numero, e sem isto a mensagem chega de um
  -- desconhecido pedindo para entrar no imovel dele.
  v_texto := nai_apresentacao_prop(v_prop) ||
             nai_saudacao() || coalesce(', ' || v_voc, '') || '! Tudo bem? Aqui é a Nay, da Imob Easy. ' ||
             'Temos um pedido de visita ' || nai_ref_imovel_prop(v.codigo) ||
             ' para ' || nai_quando_humano(v.quando) || '. Tem como receber a visita nesse horário?';

  UPDATE nai_visita SET proprietario_id = v_prop, proprietario_cadastro = dono.cadastro_id,
                        proprietario_nome = dono.nome, estado = 'aguardando_proprietario', aguardando = 'proprietario',
                        ult_msg_prop_em = now(), reenvios_prop = 0, atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_enfileirar_texto(p_turno, v.id, v_prop, 'proprietario', v_texto, 'p_solicita', 500);
  RETURN 'pedido';
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_visita_para_a_rayssa(p_visita bigint, p_turno bigint)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v       nai_visita;
  dono    record;
  v_prop  bigint;
  v_apr   bigint := nai_aprovador_contato();
  v_min_h int := nai_cfg_int('antecedencia_minima_horas', 2);
  v_dono  text;
  v_urg   text := '';
  moto    record;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO dono FROM nai_proprietario_do_imovel(v.codigo);
  IF v.prop_telefone_manual IS NOT NULL THEN
    dono.telefone := v.prop_telefone_manual;
    dono.motivo   := NULL;
  END IF;
  IF dono.motivo IS NULL THEN
    v_prop := nai_contato_do_cadastro(dono.telefone, dono.nome);
  END IF;

  IF v_prop IS NOT NULL AND v_prop <> v.corretor_id THEN
    -- o dono é gravado ANTES: a trava da caixa (nai_saida_validar) só deixa sair
    -- para o proprietário da visita
    UPDATE nai_visita SET proprietario_id = v_prop, proprietario_cadastro = dono.cadastro_id,
                          proprietario_nome = dono.nome, ult_msg_prop_em = now()
     WHERE id = v.id;
    -- a 1ª solicitação ao proprietário: o mesmo texto de nai_pedir_ao_proprietario
    PERFORM nai_enfileirar_texto(p_turno, v.id, v_prop, 'proprietario',
      nai_apresentacao_prop(v_prop) || nai_saudacao() || coalesce(', ' || nay_vocativo_dono(dono.nome), '')
        || '! Tudo bem? Aqui é a Nay, da Imob Easy. Temos um pedido de visita ' || nai_ref_imovel_prop(v.codigo)
        || ' para ' || nai_quando_humano(v.quando) || '. Tem como receber a visita nesse horário?',
      'p_solicita', 500);
    v_dono := 'Já mandei ao proprietário' || coalesce(' (' || nullif(btrim(coalesce(dono.nome, '')), '') || ')', '')
              || ' o pedido da visita; a resposta dele chega na aba Proprietários';
  ELSE
    v_dono := 'NÃO consegui mandar ao proprietário (' ||
      CASE dono.motivo WHEN 'sem_telefone' THEN 'sem telefone no cadastro'
                       WHEN 'tratar_com_outra_pessoa' THEN 'o cadastro diz: ' || coalesce(dono.nome, '')
                       WHEN 'dois_donos' THEN 'o imóvel tem dois proprietários no cadastro'
                       WHEN 'sem_cadastro' THEN 'imóvel sem proprietário cadastrado'
                       ELSE 'o telefone do proprietário é o do próprio corretor' END || '): fale você com ele';
  END IF;
  -- 443 (Pedro, 20/10/2026: a Nay passa a avisar o motoboy): o acompanhante ativo da equipe recebe a visita completa
  -- junto com o pedido ao proprietário. O checklist do grupo (nay-olx, olx/visitas_parceria.py) marca se saiu e se ele
  -- respondeu. Desligar: nai_config visita_avisar_motoboy = nao.
  IF coalesce(nai_cfg('visita_avisar_motoboy', 'sim'), 'sim') = 'sim' THEN
    SELECT * INTO moto FROM nai_motoboy();
    IF moto.contato_id IS NOT NULL AND moto.contato_id <> v.corretor_id THEN
      UPDATE nai_visita SET motoboy_id = moto.contato_id, ult_msg_moto_em = now() WHERE id = v.id;
      PERFORM nai_enfileirar_texto(p_turno, v.id, moto.contato_id, 'motoboy',
        nai_texto_visita_completa(v.id, 'Oi, ' || coalesce(nullif(split_part(btrim(coalesce(moto.nome, '')), ' ', 1), ''), 'tudo bem')
          || '! Aqui é a Nay, da Imob Easy. Pedido de visita (o horário ainda está sendo confirmado com o proprietário)')
          || E'\n\nVocê consegue acompanhar? Me responde SIM ou NÃO, por favor.',
        'visita_motoboy', 520);
      PERFORM nai_evento(v.id, 'motoboy_avisado', left(coalesce(moto.nome, ''), 200));
    END IF;
  END IF;

  IF v.quando IS NOT NULL AND v.quando < now() + make_interval(hours => v_min_h) THEN
    v_urg := ' EM CIMA DA HORA';
  END IF;

  UPDATE nai_visita SET estado = 'com_rayssa', aguardando = 'equipe', atualizado_em = now() WHERE id = v.id;
  PERFORM nai_evento(v.id, 'com_a_rayssa', left(v_dono, 200));
  IF v_apr IS NOT NULL THEN
    PERFORM nai_enfileirar_texto(p_turno, v.id, v_apr, 'equipe',
      nai_texto_visita_completa(v.id, nai_cfg('aprovador_visita_nome', 'Rayssa') || ', visita confirmada pelo corretor'
        || v_urg || '. ' || v_dono || '. A partir de agora ela é sua: o corretor está na aba Visitas do CRM e eu não'
        || ' respondo mais ele até a visita acabar'),
      'visita_com_a_rayssa', 450);
  END IF;
  PERFORM nai_avisar_tel(p_turno, v.id,
    nai_texto_visita_completa(v.id, 'Tel, visita confirmada' || v_urg || ' e passada para a Rayssa. ' || v_dono),
    'visita_com_a_rayssa');
  RETURN 'com_a_rayssa';
END $function$;

-- 4. os nomes: os donos da linha da Parceria sem nome_completo ganham o do cadastro (o que é nome de verdade)
CREATE TABLE IF NOT EXISTS privado.nai_contato_nome_antes_463 (id bigint PRIMARY KEY, nome_completo text, nome_whatsapp text);
WITH alvo AS (
  SELECT k.id, k.nome_completo, k.nome_whatsapp, b.nome
    FROM nai_contato k JOIN nay_proprietario_bloqueio b ON b.chave = k.chave
   WHERE coalesce(btrim(k.nome_completo), '') = '' AND nay_vocativo_dono(b.nome) IS NOT NULL),
g AS (INSERT INTO privado.nai_contato_nome_antes_463 (id, nome_completo, nome_whatsapp)
      SELECT id, nome_completo, nome_whatsapp FROM alvo ON CONFLICT DO NOTHING RETURNING id)
UPDATE nai_contato k SET nome_completo = alvo.nome FROM alvo WHERE k.id = alvo.id;

COMMIT;
