CREATE OR REPLACE FUNCTION public.nai_rodada_montar(p_rotulo text, p_contatos bigint[], p_motivos text[], p_teto_blocos integer DEFAULT 20)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE v_rodada bigint; v_conv bigint; i int; v_n int;
BEGIN
  INSERT INTO nai_treino_rodada (rotulo, arquitetura)
  VALUES (p_rotulo, 'v2: estado + decisao gravada + saida por ferramenta')
  RETURNING id INTO v_rodada;

  FOR i IN 1 .. coalesce(array_length(p_contatos,1),0) LOOP
    INSERT INTO nai_treino_conversa (rodada_id, contato_origem, nome, motivo)
    SELECT v_rodada, k.id, coalesce(k.nome_completo, k.nome_whatsapp),
           coalesce(p_motivos[i], '')
      FROM nai_contato k WHERE k.id = p_contatos[i]
    RETURNING id INTO v_conv;

    INSERT INTO nai_treino_bloco (conversa_id, ordem, turno_origem, quando_original,
                                  ele_disse, ela_antes, fotos_antes)
    SELECT v_conv,
           row_number() OVER (ORDER BY t.id),
           t.id, t.criado_em, t.texto,
           (SELECT string_agg(s.texto, E'\n---\n' ORDER BY s.ordem, s.id)
              FROM nai_saida s WHERE s.turno_id = t.id AND s.tipo='texto'),
           (SELECT count(*) FROM nai_saida s WHERE s.turno_id = t.id AND s.tipo='imagem')
      FROM (SELECT * FROM nai_turno t2
             WHERE t2.contato_id = p_contatos[i]
               AND t2.papel='corretor'
               AND btrim(coalesce(t2.texto,'')) <> ''
             ORDER BY t2.id LIMIT p_teto_blocos) t;

    GET DIAGNOSTICS v_n = ROW_COUNT;
    UPDATE nai_treino_conversa SET blocos_total = v_n WHERE id = v_conv;
  END LOOP;

  RETURN v_rodada;
END;
$function$
;
