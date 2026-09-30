-- 197 (Pedro, 30/09/2026): A VISITA CONFIRMADA, O FECHAMENTO E OS PROPRIETÁRIOS SÃO DA RAYSSA.
--
-- "ela vai rodar até confirmar a visita, vai responder todos na aba Todos do CRM;
--  uma vez confirmada ela avisa a Rayssa pelo +55 92 8595-6408 enviando toda a
--  confirmação ... a Rayssa faz a gestão da logística completa de visita, e o
--  corretor que agendou vai para a aba Visitas". E: "a Nay confirma a visita com o
--  corretor, avisa o proprietário da 1ª solicitação de visita, e depois avisa a
--  Rayssa ... lembretes e tudo mais cancela, deixa com a Rayssa". Volta para a Nay
--  "quando acabar a visita: passar o horário, ou cancelada, ou concluída".
--  FECHAMENTO: "quem já confirmou que o cliente vai fechar; entra assim que recebe
--  o checklist de documentação e fica lá até a Rayssa marcar como concluído".
--  PROPRIETÁRIOS: "fica só os proprietários, independente do assunto".
--
-- O que muda:
--   * estado novo de visita 'com_rayssa' (a agenda não mexe nele: sem lembrete,
--     sem cobrança de proprietário ou motoboy);
--   * nai_visita_para_a_rayssa: a 1ª solicitação ao proprietário (o mesmo texto de
--     nai_pedir_ao_proprietario), a visita passa para 'com_rayssa', a confirmação
--     completa vai à Rayssa (aprovador_visita_telefone) e o Tel é só avisado;
--     em cima da hora também vai para a Rayssa (marcado no aviso);
--   * nai_visita_corretor_confirmou chama isso no lugar do 179 (chave
--     visita_com_a_rayssa = 'nao' volta ao 179);
--   * o corretor ouve nai_texto_corretor_confirmou() no lugar de "Vou ver esse
--     horário com o proprietário e já te retorno";
--   * nai_fechamento: quem recebe o checklist (nai_enviar_checklist_para) entra;
--     sai quando a Rayssa conclui no CRM (crm_fechamento_concluir);
--   * nai_abrir_turno: corretor com visita com a Rayssa (até o horário + 120 min),
--     em fechamento, ou proprietário (a mesma regra da aba do CRM) -> a Nay NÃO
--     responde; a mensagem fica no CRM para a Rayssa (o mesmo "ok falso" do 186).
--     A equipe continua sempre atendida;
--   * crm_parceria_com_a_rayssa: as marcas novas das abas Visitas e Fechamento.
--
-- As funções grandes (confirmou, pedir_visita, conferir_resposta, abrir_turno,
-- enviar_checklist_para) são trocadas por trecho, sobre o texto VIVO do banco, e
-- cada trecho tem de aparecer exatamente uma vez: se o banco estiver diferente do
-- que foi lido, nada é aplicado.

BEGIN;
SET LOCAL lock_timeout = '3s';

-- 2. o fechamento --------------------------------------------------------------
CREATE TABLE IF NOT EXISTS nai_fechamento (
  id            bigserial PRIMARY KEY,
  contato_id    bigint NOT NULL REFERENCES nai_contato(id),
  tipo          text,
  iniciado_em   timestamptz NOT NULL DEFAULT now(),
  iniciado_por  text,
  concluido_em  timestamptz,
  concluido_por text
);
CREATE UNIQUE INDEX IF NOT EXISTS nai_fechamento_um_aberto ON nai_fechamento (contato_id) WHERE concluido_em IS NULL;

INSERT INTO nai_config (chave, valor, descricao) VALUES
  ('visita_com_a_rayssa', 'sim', '197: visita confirmada, fechamento e proprietário são da Rayssa (nao = volta ao 179)'),
  ('visita_rayssa_ate_min', '120', '197: minutos depois do horário da visita em que o corretor volta para a Nay')
ON CONFLICT (chave) DO NOTHING;

-- 3. as leituras ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_visita_com_a_rayssa(p_estado text, p_quando timestamptz)
 RETURNS boolean LANGUAGE sql STABLE AS $$
  -- a visita é da Rayssa até o horário dela + visita_rayssa_ate_min (ou até fechar)
  SELECT p_estado = 'com_rayssa'
     AND (p_quando IS NULL OR p_quando + make_interval(mins => nai_cfg_int('visita_rayssa_ate_min', 120)) > now());
$$;

CREATE OR REPLACE FUNCTION nai_e_proprietario_contato(p_contato bigint)
 RETURNS boolean LANGUAGE plpgsql STABLE AS $$
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
  RETURN EXISTS (SELECT 1 FROM nai_visita v WHERE v.proprietario_id = ANY (v_ids))
      OR EXISTS (SELECT 1 FROM proprietarios p WHERE coalesce(p.telefone, '') <> '' AND nai_chave(p.telefone) = ANY (v_chaves))
      OR EXISTS (SELECT 1 FROM proprietarios_admin a WHERE coalesce(a.telefone, '') <> '' AND nai_chave(a.telefone) = ANY (v_chaves))
      OR EXISTS (SELECT 1 FROM captacao_leads l WHERE l.telefone_chave = ANY (v_chaves));
END $$;

CREATE OR REPLACE FUNCTION nai_com_a_rayssa(p_contato bigint, p_papel text)
 RETURNS text LANGUAGE plpgsql STABLE AS $$
-- NULL = a Nay atende. Senão, o motivo de a conversa ser da Rayssa.
DECLARE v_ids bigint[];
BEGIN
  IF p_contato IS NULL OR nai_cfg('visita_com_a_rayssa', 'sim') <> 'sim' OR nai_e_da_equipe_contato(p_contato) THEN
    RETURN NULL;
  END IF;
  v_ids := coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]);
  IF EXISTS (SELECT 1 FROM nai_fechamento f WHERE f.contato_id = ANY (v_ids) AND f.concluido_em IS NULL) THEN
    RETURN 'fechamento_com_a_rayssa';
  END IF;
  IF EXISTS (SELECT 1 FROM nai_visita v WHERE v.corretor_id = ANY (v_ids) AND nai_visita_com_a_rayssa(v.estado, v.quando)) THEN
    RETURN 'visita_com_a_rayssa';
  END IF;
  IF p_papel = 'proprietario' OR nai_e_proprietario_contato(p_contato) THEN
    RETURN 'proprietario_com_a_rayssa';
  END IF;
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION nai_texto_corretor_confirmou()
 RETURNS text LANGUAGE sql STABLE AS $$
  SELECT CASE WHEN nai_cfg('visita_com_a_rayssa', 'sim') = 'sim'
    THEN 'Certo! Anotei a sua visita. A partir de agora quem cuida dela com você é a '
         || nai_cfg('aprovador_visita_nome', 'Rayssa') || ', da nossa equipe, e ela te chama por aqui.'
    ELSE 'Certo! Vou ver esse horário com o proprietário e já te retorno.' END;
$$;

-- 4. a passagem para a Rayssa ---------------------------------------------------
CREATE OR REPLACE FUNCTION nai_visita_para_a_rayssa(p_visita bigint, p_turno bigint)
 RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  v       nai_visita;
  dono    record;
  v_prop  bigint;
  v_apr   bigint := nai_aprovador_contato();
  v_min_h int := nai_cfg_int('antecedencia_minima_horas', 2);
  v_dono  text;
  v_urg   text := '';
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
      nai_apresentacao_prop(v_prop) || nai_saudacao() || coalesce(', ' || nai_vocativo(dono.nome), '')
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
END $$;

-- 5. o CRM ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION crm_parceria_com_a_rayssa(p_telefones text[])
 RETURNS TABLE(telefone text, visita_rayssa boolean, visita_id bigint, fechamento_id bigint,
               fechamento_desde timestamptz, acompanhante boolean)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT pe.telefone, vr.id IS NOT NULL, vr.id, f.id, f.iniciado_em,
         EXISTS (SELECT 1 FROM equipe e
                  WHERE e.ativo AND e.papel = 'acompanhante' AND nai_chave(e.telefone) = ANY (pe.chaves))
    FROM crm_pessoas(p_telefones) pe
    LEFT JOIN LATERAL (SELECT v.id FROM nai_visita v
                        WHERE v.corretor_id = ANY (pe.ids) AND nai_visita_com_a_rayssa(v.estado, v.quando)
                        ORDER BY v.quando NULLS LAST LIMIT 1) vr ON true
    LEFT JOIN LATERAL (SELECT f.id, f.iniciado_em FROM nai_fechamento f
                        WHERE f.contato_id = ANY (pe.ids) AND f.concluido_em IS NULL
                        ORDER BY f.id DESC LIMIT 1) f ON true;
$$;

CREATE OR REPLACE FUNCTION crm_fechamento_concluir(p_id bigint, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text) LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE nai_fechamento SET concluido_em = now(), concluido_por = left(coalesce(p_quem, 'CRM'), 80)
   WHERE id = p_id AND concluido_em IS NULL;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'Esse fechamento já estava concluído.'::text;
    RETURN;
  END IF;
  RETURN QUERY SELECT true, 'Fechamento concluído: o corretor voltou para Todos e a Nay volta a responder.'::text;
END $$;

GRANT EXECUTE ON FUNCTION crm_parceria_com_a_rayssa(text[]), crm_fechamento_concluir(bigint, text) TO nay_disparo;

-- 6. os trechos nas funções grandes (sobre o texto vivo; cada um exatamente 1 vez)
CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE d text; n int;
BEGIN
  d := pg_get_functiondef(p_fn);
  n := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
  IF n <> 1 THEN RAISE EXCEPTION '%: o trecho aparece % vez(es), esperado 1: %', p_fn, n, left(p_de, 80); END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

SELECT pg_temp.trocar('public.nai_visita_corretor_confirmou(bigint,bigint)',
  E'    PERFORM nai_evento(v.id, ''aprovada'', ''automática'');\n',
  E'    PERFORM nai_evento(v.id, ''aprovada'', ''automática'');\n\n'
  || E'    -- 197 (Pedro, 30/09/2026): a visita confirmada é da Rayssa (1ª solicitação ao\n'
  || E'    -- proprietário, a confirmação completa à Rayssa, o Tel só avisado)\n'
  || E'    IF nai_cfg(''visita_com_a_rayssa'', ''sim'') = ''sim'' THEN\n'
  || E'      PERFORM nai_visita_para_a_rayssa(v.id, p_turno);\n'
  || E'      RETURN;\n'
  || E'    END IF;\n');

SELECT pg_temp.trocar('public.nai_pedir_visita(bigint,text,text,text)',
  E'''Certo! Vou ver esse horário com o proprietário e já te retorno.''::text',
  'nai_texto_corretor_confirmou()');

SELECT pg_temp.trocar('public.nai_conferir_resposta(bigint,text,jsonb,text,jsonb)',
  E'''texto'', ''Certo! Vou ver esse horário com o proprietário e já te retorno.'')',
  E'''texto'', nai_texto_corretor_confirmou())');

SELECT pg_temp.trocar('public.nai_abrir_turno(text,text,text,text,bigint[])',
  E'  v_porta   record;',
  E'  v_rayssa  text;       -- 197: a conversa é da Rayssa (visita, fechamento, proprietário)\n  v_porta   record;');

SELECT pg_temp.trocar('public.nai_abrir_turno(text,text,text,text,bigint[])',
  E'  -- 141b: a etapa e atualizada ANTES de montar o cabecalho.',
  E'  -- 197 (Pedro, 30/09/2026): corretor com a visita confirmada (até ela acabar), em\n'
  || E'  -- fechamento, ou proprietário: quem responde é a Rayssa, pelo CRM. A mensagem\n'
  || E'  -- fica gravada e a Nay não responde (o mesmo "ok falso" do 186).\n'
  || E'  IF v_papel IN (''corretor'', ''proprietario'') THEN\n'
  || E'    v_rayssa := nai_com_a_rayssa(v_contato, v_papel);\n'
  || E'    IF v_rayssa IS NOT NULL THEN\n'
  || E'      UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;\n'
  || E'      RETURN jsonb_build_object(''ok'', false, ''motivo'', v_rayssa, ''turno_id'', v_turno,\n'
  || E'                                ''contato_id'', v_contato, ''papel'', v_papel);\n'
  || E'    END IF;\n'
  || E'  END IF;\n\n'
  || E'  -- 141b: a etapa e atualizada ANTES de montar o cabecalho.');

SELECT pg_temp.trocar('public.nai_enviar_checklist_para(bigint,text,text)',
  E'  RETURN ''Mandei o checklist de '' || v_nome',
  E'  -- 197: quem recebe o checklist entra no FECHAMENTO (é da Rayssa até ela concluir no CRM)\n'
  || E'  IF nai_cfg(''visita_com_a_rayssa'', ''sim'') = ''sim'' AND NOT nai_e_da_equipe_contato(v_destino) THEN\n'
  || E'    INSERT INTO nai_fechamento (contato_id, tipo, iniciado_por) VALUES (v_destino, p_tipo, ''checklist'')\n'
  || E'      ON CONFLICT DO NOTHING;\n'
  || E'  END IF;\n'
  || E'  RETURN ''Mandei o checklist de '' || v_nome');

-- 7. por último: a trava da tabela de visitas dura só até o COMMIT logo abaixo
-- o estado novo -------------------------------------------------------------
DO $$
DECLARE d text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO d FROM pg_constraint WHERE conname = 'nai_visita_estado_check';
  IF d !~ 'com_rayssa' THEN
    d := replace(d, '''expirada''::text', '''expirada''::text, ''com_rayssa''::text');
    IF d !~ 'com_rayssa' THEN RAISE EXCEPTION 'CHECK de nai_visita diferente do lido: %', d; END IF;
    ALTER TABLE nai_visita DROP CONSTRAINT nai_visita_estado_check;
    EXECUTE 'ALTER TABLE nai_visita ADD CONSTRAINT nai_visita_estado_check ' || d || ' NOT VALID';
  END IF;
END $$;

COMMIT;
