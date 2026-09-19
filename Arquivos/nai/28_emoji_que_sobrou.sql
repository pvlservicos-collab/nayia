-- =====================================================================
-- NAI -- 28: o emoji que sobrou, e o simbolo que faltava (Tel, 15/09/2026)
--
-- Varredura das funcoes nai_* atras de emoji EMBUTIDO no texto
-- (scratchpad/caca_emoji.py). Emoji escrito dentro da funcao nao passa pelo
-- filtro que limpa o que o modelo escreve -- entao sai no WhatsApp mesmo com
-- a ordem do Tel, de 13/09, de nao usar emoji. Tres achados:
--
--   1. FALTAVA um simbolo na lista de preservados. As quatro linhas de acesso
--      que ele aprovou tem simbolo: chave (chave conosco), chave (o Fernando
--      busca), cadeado (fechadura eletronica) e mao erguida (o proprietario
--      abre). Os tres primeiros estavam na lista, o quarto nao -- entao
--      aquela linha sairia sem simbolo, sozinha entre as quatro. Agora esta.
--   2. a lista de visitas do corretor dizia "confirmada" com um visto verde;
--   3. o recado ao proprietario terminava com "Obrigada" e um sorriso.
--
-- O arquivo 27 ja tinha tirado o das maos da confirmacao de visita, visto no
-- teste conduzido do mesmo dia.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.nai_minhas_visitas(p_turno bigint)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE t nai_turno; linhas text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT string_agg('• ' || nai_ref_imovel(x.codigo) || ' — ' || coalesce(nai_quando_humano(x.quando), 'sem horário') ||
                    ' — ' || CASE x.estado
                      WHEN 'coletando' THEN 'falta me passar os dados'
                      WHEN 'aguardando_proprietario' THEN 'esperando o proprietário confirmar'
                      WHEN 'negociando' THEN CASE WHEN x.aguardando = 'corretor' THEN 'o proprietário sugeriu ' || coalesce(nai_quando_humano(x.quando_sugerido), 'outro horário') ELSE 'vendo outro horário com o proprietário' END
                      WHEN 'aguardando_acesso' THEN 'acertando a chave com o proprietário'
                      WHEN 'aguardando_motoboy' THEN 'confirmando com o Fernando'
                      WHEN 'confirmada' THEN 'confirmada'
                      WHEN 'com_tel' THEN 'o Tel está vendo'
                      WHEN 'realizada' THEN 'já aconteceu'
                      ELSE x.estado END, E'\n' ORDER BY x.quando)
    INTO linhas
    FROM nai_visita x WHERE x.corretor_id = t.contato_id AND nai_visita_aberta(x.estado);
  RETURN QUERY SELECT coalesce(linhas, 'Não tem nenhuma visita em andamento com você agora.'),
                      'repita a lista como veio.'::text;
END;
$function$;


CREATE OR REPLACE FUNCTION public.nai_responder_horario(p_turno bigint, p_codigo text, p_aceita text, p_outro_quando text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  t   nai_turno;
  sel record;
  v   nai_visita;
  q   timestamptz := nai_ler_quando(p_outro_quando);
  ok  boolean := lower(coalesce(p_aceita, '')) IN ('sim', 's', 'true', 'yes', 'aceita');
  v_txt text;
BEGIN
  PERFORM nai_usou_ferramenta(p_turno, 'visita');
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'corretor' THEN RETURN QUERY SELECT NULL::text, 'so o corretor responde isso.'::text; RETURN; END IF;
  SELECT * INTO sel FROM nai_visita_do_corretor(t.contato_id, p_codigo, ARRAY['negociando']);
  IF sel.visita_id IS NULL OR sel.qtd > 1 THEN
    RETURN QUERY SELECT NULL::text, 'nao achei UMA visita esperando a resposta dele sobre horario. chame minhas_visitas e pergunte qual.'::text; RETURN;
  END IF;
  SELECT * INTO v FROM nai_visita WHERE id = sel.visita_id FOR UPDATE;
  IF v.aguardando <> 'corretor' OR v.quando_sugerido IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'essa visita nao esta esperando resposta dele: o proprietario ainda nao sugeriu horario.'::text; RETURN;
  END IF;

  IF ok THEN
    -- O horario foi o proprietario que deu: vale como aceite dele.
    UPDATE nai_visita SET quando = quando_sugerido, quando_sugerido = NULL, prop_ok_em = now(),
                          atualizado_em = now()
     WHERE id = v.id;
    PERFORM nai_evento(v.id, 'corretor_aceitou_horario_do_proprietario', NULL);
    -- Card "Fecha o novo horario": "Fechado! O corretor confirmou ... Obrigada"
    v_txt := nai_prosseguir_acesso(v.id, p_turno, true);
    SELECT * INTO v FROM nai_visita WHERE id = v.id;
    -- Card p_ok, literal (sem dados do visitante: eles so vem depois da confirmacao).
    v_txt := 'Fechado! O corretor confirmou ' || nai_quando_humano(v.quando) || '. ' ||
             CASE WHEN v.estado = 'aguardando_acesso' THEN regexp_replace(coalesce(v_txt, ''), '^Obrigada!\s*', '')
                  ELSE 'Obrigada' END;
    PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario', v_txt, 'fecha_novo_horario', 500);
    -- Nao ha card para o corretor aqui (fluxo v17): ele so ouve de novo na confirmacao.
    RETURN QUERY SELECT NULL::text,
      'o horario foi fechado com o proprietario. responda exatamente SILENCIO: a confirmacao chega sozinha.'::text;
    RETURN;
  END IF;

  IF q IS NULL THEN
    RETURN QUERY SELECT 'Sem problemas! Qual horário fica bom pro seu cliente?'::text,
      'quando ele disser, chame responder_horario_do_proprietario de novo com outro_quando.'::text; RETURN;
  END IF;
  IF q <= now() + interval '10 minutes' THEN
    RETURN QUERY SELECT 'Esse horário já passou. Qual outro horário fica bom pro seu cliente?'::text, NULL::text; RETURN;
  END IF;

  -- Loop: leva a contraproposta ao proprietario.
  UPDATE nai_visita SET quando = q, quando_sugerido = NULL, prop_ok_em = NULL, estado = 'negociando',
                        aguardando = 'proprietario', reenvios_prop = 0, aviso_demora_em = NULL, atualizado_em = now()
   WHERE id = v.id;
  -- Card "Leva a contraproposta": "O cliente nao consegue as X. Pode ser as Y?"
  PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario',
    'O cliente não consegue ' || nai_quando_humano(v.quando_sugerido) || '. Pode ser ' || nai_quando_humano(q) || '?',
    'contraproposta_corretor', 500);
  RETURN QUERY SELECT 'Certo, vou ver esse horário com o proprietário e já te retorno'::text, NULL::text;
END;
$function$;
