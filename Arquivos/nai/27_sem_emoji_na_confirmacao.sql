-- =====================================================================
-- NAI -- 27: o emoji que sobrou na confirmacao de visita (Tel, 15/09/2026)
--
-- Ordem dele, de 13/09: "diz para nao usar emojis" -- o que ELA escreve sai
-- sem emoji; os simbolos do CARD do imovel ficam, porque sao do modelo dele.
--
-- A confirmacao de visita tinha um emoji EMBUTIDO no proprio texto da funcao,
-- entao nao passava pelo filtro que limpa o que o modelo escreve: saia
-- "Visita confirmada, Sr. Pedro! [maos] Amanha a tarde...". Ja tinha ido
-- assim 15 vezes.
--
-- Conferido no fluxo de mensagens do site: o card dele diz apenas "Visita
-- confirmada, {data_visita} as {horario_visita}" -- sem emoji nenhum.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.nai_confirmar_visita(p_visita bigint, p_turno bigint)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE v nai_visita; c nai_contato; m record; v_nome text; d record; v_pede text;
BEGIN
  SELECT * INTO v FROM nai_visita WHERE id = p_visita FOR UPDATE;
  SELECT * INTO c FROM nai_contato WHERE id = v.corretor_id;
  SELECT * INTO m FROM nai_motoboy();
  v_nome := nai_vocativo(coalesce(c.nome_completo, c.nome_whatsapp));
  UPDATE nai_visita SET estado = 'confirmada', aguardando = NULL, confirmada_em = now(), atualizado_em = now()
   WHERE id = v.id;
  PERFORM nai_evento(v.id, 'confirmada', NULL);
  PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor',
    'Visita confirmada' || coalesce(', ' || v_nome, '') || '! ' || initcap(left(nai_quando_humano(v.quando), 1)) ||
    substr(nai_quando_humano(v.quando), 2) || ', no ' || nai_ref_imovel(v.codigo) || '.' ||
    E'\nQuem vai acompanhar sua visita é o Fernando' || coalesce(', ' || nai_fone_fmt(m.telefone), '') || '.' ||
    CASE WHEN nai_linha_acesso_corretor(v.acesso) <> '' THEN E'\n' || nai_linha_acesso_corretor(v.acesso) ELSE '' END,
    'visita_confirmada', 400);
  -- Fluxo v17 (Tel, 13/09): SO AGORA os dados. Cards "Checa os dados do
  -- corretor" -> CORRETOR CONHECIDO / CORRETOR NOVO, sem o "vou confirmar aqui
  -- a visita" (ela ja esta confirmada) -- "tira o vou confirmar e pede claramente".
  SELECT * INTO d FROM nai_dados_corretor(c.id);
  IF NOT coalesce(d.completo, false) THEN
    v_pede := 'Me passa o ' || nai_lista_pt(ARRAY_REMOVE(ARRAY[
      CASE WHEN d.nome_completo IS NULL THEN 'seu nome completo' END,
      CASE WHEN d.cpf IS NULL THEN 'o CPF' END,
      CASE WHEN d.creci IS NULL THEN 'o CRECI' END], NULL)) || '?';
  ELSIF v.visitante_nome IS NULL OR v.visitante_cpf IS NULL THEN
    v_pede := 'Me passa o nome completo e o CPF do visitante?';
  END IF;
  IF v_pede IS NOT NULL THEN
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.corretor_id, 'corretor', v_pede, 'pedir_dados', 401);
    UPDATE nai_visita SET lembretes_dados = 0,
           proximo_lembrete_dados_em = now() + make_interval(mins => nai_cfg_int('dados_primeiro_lembrete_min', 3))
     WHERE id = v.id;
  END IF;
END;
$function$;
