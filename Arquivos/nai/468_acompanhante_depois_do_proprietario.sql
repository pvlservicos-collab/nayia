-- 468 -- Visita: o acompanhante só recebe depois que o proprietário confirma
--
-- Pedro, 22/10/2026: "hoje manda para os 3, mas quero que não mande para o André sem o proprietário ter confirmado que
-- pode ainda, organiza isso". (O acompanhante ativo é o Diego desde 21/10; o André está desativado na equipe.)
-- Hoje, no "sim" do corretor, nai_visita_para_a_rayssa mandava o pedido ao proprietário E o aviso ao acompanhante (443)
-- E o aviso ao Tel, no mesmo minuto. #1156 (Florence Garden): 13:57 os três; 14:05 o dono "Imóvel renovou o contrato".
-- Agora:
-- - nai_visita_para_a_rayssa: o pedido ao dono e os avisos à Rayssa e ao Tel (que dizem que o acompanhante espera o dono);
-- - nai_dono_disse_sim(texto): o "sim" CLARO do dono ("pode sim", "ok", "tudo bem", "confirmado"...), sem "não", sem
--   outro horário, sem "renovou/alugado/vendido", sem pergunta. Qualquer outra coisa fica com a Rayssa, como hoje;
-- - gatilho nai_turno_dono_respondeu (AFTER INSERT em nai_turno, papel 'proprietario'): o sim do dono numa visita com a
--   Rayssa e ainda sem acompanhante avisado -> prop_ok_em, evento, aviso ao acompanhante, à Rayssa e ao Tel;
-- - crm_visita_proprietario_ok(visita, quem): o botão "Proprietário confirmou" do CRM (o dono confirmou por telefone);
-- - nai_visita_avisar_acompanhante(visita, turno, por): uma vez só por visita.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.nai_dono_disse_sim(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  SELECT length(t) BETWEEN 1 AND 80
     AND t ~ '^\W*(sim|pode|ok|okay|okey|tudo bem|tudo certo|confirmad[oa]|confirmo|combinado|fechado|beleza|blz|claro|com certeza|perfeito|certo|tranquilo|show|isso|positivo|liberado|autorizado)\M'
     AND t !~ '\m(nao|n|nunca|renov\w*|alugad\w*|vendid\w*|ocupad\w*|indisponiv\w*|outr[oa]s?|mais tarde|mais cedo|amanha|depois|so|apenas|mas|porem|infelizmente|desculp\w*|viaj\w*|reforma\w*|quem|qual|quando|onde)\M'
     AND t !~ '\d{1,2}\s*(h\M|:|horas)' AND position('?' IN t) = 0
    FROM (SELECT lower(unaccent(btrim(coalesce(p_texto, '')))) AS t) x
$function$;
COMMENT ON FUNCTION public.nai_dono_disse_sim(text) IS
  '468: a resposta do proprietário é um sim claro ao pedido de visita (sem não, outro horário, pergunta ou imóvel ocupado).';

CREATE OR REPLACE FUNCTION public.nai_visita_avisar_acompanhante(p_visita bigint, p_turno bigint, p_por text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v    nai_visita;
  moto record;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL OR coalesce(nai_cfg('visita_avisar_motoboy', 'sim'), 'sim') <> 'sim' THEN RETURN NULL; END IF;
  IF EXISTS (SELECT 1 FROM nai_visita_evento e WHERE e.visita_id = v.id AND e.tipo = 'motoboy_avisado') THEN
    RETURN 'o acompanhante já tinha sido avisado';
  END IF;
  SELECT * INTO moto FROM nai_motoboy();
  IF moto.contato_id IS NULL OR moto.contato_id = v.corretor_id THEN RETURN 'sem acompanhante ativo na equipe'; END IF;
  UPDATE nai_visita SET motoboy_id = moto.contato_id, ult_msg_moto_em = now() WHERE id = v.id;
  PERFORM nai_enfileirar_texto(p_turno, v.id, moto.contato_id, 'motoboy',
    nai_texto_visita_completa(v.id, 'Oi, ' || coalesce(nullif(split_part(btrim(coalesce(moto.nome, '')), ' ', 1), ''), 'tudo bem')
      || '! Aqui é a Nay, da Imob Easy. Visita confirmada pelo proprietário')
      || E'\n\nVocê consegue acompanhar? Me responde SIM ou NÃO, por favor.',
    'visita_motoboy', 520);
  PERFORM nai_evento(v.id, 'motoboy_avisado', left(coalesce(moto.nome, '') || ' (' || coalesce(p_por, '?') || ')', 200));
  RETURN 'avisei o ' || coalesce(nullif(split_part(btrim(coalesce(moto.nome, '')), ' ', 1), ''), 'acompanhante');
END $function$;

CREATE OR REPLACE FUNCTION public.nai_turno_dono_respondeu()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v     nai_visita;
  v_msg text;
  v_apr bigint := nai_aprovador_contato();
BEGIN
  IF coalesce(NEW.teste, false) OR NOT nai_dono_disse_sim(NEW.texto) THEN RETURN NULL; END IF;
  SELECT * INTO v FROM nai_visita x
   WHERE x.proprietario_id = NEW.contato_id AND (NEW.visita_id IS NULL OR x.id = NEW.visita_id)
     AND x.estado = 'com_rayssa' AND x.prop_ok_em IS NULL AND x.excluida_em IS NULL
     AND x.ult_msg_prop_em IS NOT NULL AND x.ult_msg_prop_em < NEW.criado_em
     AND (x.quando IS NULL OR x.quando > now())
   ORDER BY x.quando NULLS LAST LIMIT 1;
  IF v.id IS NULL THEN RETURN NULL; END IF;
  UPDATE nai_visita SET prop_ok_em = now(), atualizado_em = now() WHERE id = v.id;
  PERFORM nai_evento(v.id, 'proprietario_confirmou', left('pela resposta dele: ' || NEW.texto, 200));
  v_msg := nai_visita_avisar_acompanhante(v.id, NEW.id, 'o proprietário respondeu');
  PERFORM nai_avisar_tel(NEW.id, v.id,
    nai_texto_visita_completa(v.id, 'Tel, o proprietário confirmou a visita ("' || left(btrim(NEW.texto), 60) || '"): '
      || coalesce(v_msg, 'o acompanhante não foi avisado')), 'visita_proprietario_ok');
  IF v_apr IS NOT NULL THEN
    PERFORM nai_enfileirar_texto(NEW.id, v.id, v_apr, 'equipe',
      nai_cfg('aprovador_visita_nome', 'Rayssa') || ', o proprietário confirmou a visita #' || v.id || ' ('
        || nai_ref_imovel(v.codigo) || ', ' || nai_quando_humano(v.quando) || '): "' || left(btrim(NEW.texto), 60) || '". '
        || initcap(left(coalesce(v_msg, 'o acompanhante não foi avisado'), 1)) || substr(coalesce(v_msg, 'o acompanhante não foi avisado'), 2) || '.',
      'visita_proprietario_ok', 451);
  END IF;
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  -- a mensagem do dono nunca se perde por causa disto: a Rayssa segue como antes
  RAISE WARNING '468 nai_turno_dono_respondeu: %', SQLERRM;
  RETURN NULL;
END $function$;

DROP TRIGGER IF EXISTS nai_turno_dono_respondeu ON public.nai_turno;
CREATE TRIGGER nai_turno_dono_respondeu AFTER INSERT ON public.nai_turno
  FOR EACH ROW WHEN (NEW.papel = 'proprietario') EXECUTE FUNCTION nai_turno_dono_respondeu();

CREATE OR REPLACE FUNCTION public.crm_visita_proprietario_ok(p_visita bigint, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v     nai_visita;
  v_msg text;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  IF v.id IS NULL OR v.excluida_em IS NOT NULL THEN
    RETURN QUERY SELECT false, 'Não achei essa visita.'; RETURN;
  END IF;
  IF NOT nai_visita_aberta(v.estado) THEN
    RETURN QUERY SELECT false, 'Essa visita já está ' || v.estado || '.'; RETURN;
  END IF;
  UPDATE nai_visita SET prop_ok_em = coalesce(prop_ok_em, now()), atualizado_em = now() WHERE id = v.id;
  PERFORM nai_evento(v.id, 'proprietario_confirmou', 'marcado no CRM por ' || coalesce(nullif(btrim(p_quem), ''), 'alguém'));
  v_msg := nai_visita_avisar_acompanhante(v.id, NULL, 'marcado no CRM por ' || coalesce(nullif(btrim(p_quem), ''), 'alguém'));
  RETURN QUERY SELECT true, 'Proprietário confirmado: ' || coalesce(v_msg, 'o acompanhante não foi avisado') || '.';
END $function$;
GRANT EXECUTE ON FUNCTION public.crm_visita_proprietario_ok(bigint, text) TO nay, nay_disparo;

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
  -- 468 (Pedro, 22/10/2026: "não mande para o André sem o proprietário ter confirmado que pode"): o acompanhante NÃO
  -- recebe mais junto com o pedido ao proprietário (a 443 mandava aos três de uma vez; na #1156 o dono respondeu "o
  -- imóvel renovou o contrato" e o Diego já tinha o pedido). Ele recebe quando o dono diz sim (nai_turno_dono_respondeu)
  -- ou quando a equipe marca no CRM (crm_visita_proprietario_ok): nai_visita_avisar_acompanhante.
  IF coalesce(nai_cfg('visita_avisar_motoboy', 'sim'), 'sim') = 'sim' AND v_prop IS NOT NULL AND v_prop <> v.corretor_id THEN
    v_dono := v_dono || '. O ' || nai_acompanhante() || ' (acompanhante) só recebe quando o proprietário confirmar';
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
END $function$;;

COMMIT;
