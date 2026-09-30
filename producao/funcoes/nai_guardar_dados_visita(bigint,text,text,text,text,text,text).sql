CREATE OR REPLACE FUNCTION public.nai_guardar_dados_visita(p_turno bigint, p_codigo text, p_visitante_nome text, p_visitante_cpf text, p_corretor_nome text, p_corretor_cpf text, p_corretor_creci text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
AS $function$
DECLARE
  t       nai_turno;
  k       nai_contato;
  sel     record;
  v       nai_visita;
  d       record;
  v_vcpf  text := nai_cpf_valido(p_visitante_cpf);
  v_ccpf  text := nai_cpf_valido(p_corretor_cpf);
  v_vnome text := nai_nome_completo(p_visitante_nome);
  v_cnome text := nai_nome_completo(p_corretor_nome);
  v_creci text := NULLIF(btrim(coalesce(p_corretor_creci, '')), '');
  v_falta text[] := '{}';
  v_erro  text[] := '{}';
  v_res   text;
BEGIN
  PERFORM nai_usou_ferramenta(p_turno, 'visita');
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL OR t.papel <> 'corretor' THEN
    RETURN QUERY SELECT NULL::text, 'so o corretor passa os dados da visita.'::text; RETURN;
  END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  SELECT * INTO sel FROM nai_visita_do_corretor(k.id, p_codigo, ARRAY['confirmada']);
  IF sel.visita_id IS NULL THEN
    RETURN QUERY SELECT NULL::text, 'nao ha visita confirmada esperando dados. se ele quer marcar uma visita, chame pedir_visita.'::text; RETURN;
  END IF;
  IF sel.qtd > 1 THEN
    RETURN QUERY SELECT ('Só me confirma de qual visita são esses dados?' || E'\n' || nai_lista_visitas_corretor(k.id))::text,
      'pergunte de qual imovel sao os dados e chame de novo com o codigo.'::text; RETURN;
  END IF;
  SELECT * INTO v FROM nai_visita WHERE id = sel.visita_id FOR UPDATE;

  -- Os do CORRETOR (se veio). Grava no cadastro antigo quando ele existe,
  -- como a ferramenta antiga fazia, e sempre no contato da NAI.
  IF p_corretor_cpf IS NOT NULL AND btrim(p_corretor_cpf) <> '' AND v_ccpf IS NULL THEN
    v_erro := v_erro || 'o seu CPF não confere (confere os 11 números?)'::text;
  END IF;
  IF v_ccpf IS NOT NULL OR v_cnome IS NOT NULL OR (v_creci IS NOT NULL AND length(v_creci) BETWEEN 3 AND 30) THEN
    UPDATE nai_contato SET cpf = coalesce(v_ccpf, cpf), nome_completo = coalesce(v_cnome, nome_completo),
                           creci = coalesce(CASE WHEN length(v_creci) BETWEEN 3 AND 30 THEN v_creci END, creci),
                           atualizado_em = now()
     WHERE id = k.id;
    IF k.chave !~ '^lid:' THEN
      UPDATE corretores c SET nome = coalesce(v_cnome, c.nome),
                              nome_origem = CASE WHEN v_cnome IS NOT NULL THEN 'manual' ELSE c.nome_origem END,
                              creci = coalesce(NULLIF(btrim(c.creci), ''), CASE WHEN length(v_creci) BETWEEN 3 AND 30 THEN v_creci END),
                              ultima_interacao = now()
       WHERE nai_chave(c.telefone) = k.chave;
    END IF;
  END IF;

  -- Os do VISITANTE.
  IF p_visitante_cpf IS NOT NULL AND btrim(p_visitante_cpf) <> '' AND v_vcpf IS NULL THEN
    v_erro := v_erro || 'o CPF do visitante não confere (confere os 11 números?)'::text;
  END IF;
  IF p_visitante_nome IS NOT NULL AND btrim(p_visitante_nome) <> '' AND v_vnome IS NULL THEN
    v_erro := v_erro || 'preciso do nome COMPLETO do visitante (nome e sobrenome)'::text;
  END IF;
  UPDATE nai_visita SET visitante_nome = coalesce(v_vnome, visitante_nome),
                        visitante_cpf = coalesce(v_vcpf, visitante_cpf), atualizado_em = now()
   WHERE id = v.id RETURNING * INTO v;

  SELECT * INTO d FROM nai_dados_corretor(k.id);
  IF d.nome_completo IS NULL THEN v_falta := v_falta || 'seu nome completo'::text; END IF;
  IF d.cpf IS NULL THEN v_falta := v_falta || 'seu CPF'::text; END IF;
  IF d.creci IS NULL THEN v_falta := v_falta || 'seu CRECI'::text; END IF;
  IF v.visitante_nome IS NULL THEN v_falta := v_falta || 'o nome completo do visitante'::text; END IF;
  IF v.visitante_cpf IS NULL THEN v_falta := v_falta || 'o CPF do visitante'::text; END IF;

  IF array_length(v_falta, 1) >= 1 OR array_length(v_erro, 1) >= 1 THEN
    UPDATE nai_visita SET proximo_lembrete_dados_em =
             now() + make_interval(mins => nai_cfg_int('dados_primeiro_lembrete_min', 3))
     WHERE id = v.id;
    RETURN QUERY SELECT
      (CASE WHEN array_length(v_erro, 1) >= 1 THEN initcap(left(array_to_string(v_erro, '. '), 1)) || substr(array_to_string(v_erro, '. '), 2) || '. ' ELSE '' END ||
       CASE WHEN coalesce(array_length(v_erro, 1), 0) = 0 AND d.completo AND v.visitante_nome IS NULL AND v.visitante_cpf IS NULL
            THEN 'Anotado! Agora pode passar o nome completo e o CPF do visitante?'
            WHEN array_length(v_falta, 1) >= 1
            THEN 'Só falta ' || nai_lista_pt(v_falta) || ' pra eu fechar a visita' ELSE '' END)::text,
      'quando ele mandar, chame guardar_dados_da_visita de novo.'::text;
    RETURN;
  END IF;

  -- Tudo certo (fluxo v17, Tel 13/09): a visita JA esta confirmada. Os dados
  -- do visitante vao ao proprietario agora ("coloca para mandar depois") e o
  -- corretor nao recebe nada ("Nada, fica calada").
  UPDATE nai_visita SET proximo_lembrete_dados_em = NULL WHERE id = v.id;
  IF NOT EXISTS (SELECT 1 FROM nai_visita_evento e WHERE e.visita_id = v.id AND e.tipo = 'dados_ao_proprietario') THEN
    PERFORM nai_evento(v.id, 'dados_completos', NULL);
    IF v.proprietario_id IS NOT NULL THEN
      PERFORM nai_enfileirar_texto(p_turno, v.id, v.proprietario_id, 'proprietario', nai_texto_dados_visitante(v), 'dados_visitante', 500);
    ELSE
      PERFORM nai_avisar_tel(p_turno, v.id, 'Tel, dados do visitante da visita #' || v.id || ' (' || nai_ref_imovel(v.codigo) || ', ' ||
        nai_hora_exata(v.quando) || '): ' || nai_texto_dados_visitante(v), 'dados_visitante');
    END IF;
    PERFORM nai_evento(v.id, 'dados_ao_proprietario', NULL);
  END IF;
  RETURN QUERY SELECT NULL::text,
    'dados completos e repassados. o corretor NAO recebe nada: responda exatamente SILENCIO.'::text;
END;
$function$;
