CREATE OR REPLACE FUNCTION public.nai_enfileirar_resposta_ferramentas(p_turno bigint, p_texto text, p_codigos jsonb, p_escreveu text, p_fotos_site jsonb, p_ferramentas jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_contato   bigint;
  v_rej       int[];
  v_consultou boolean := false;
  v_tem_lista boolean := (p_ferramentas IS NOT NULL AND jsonb_typeof(p_ferramentas) = 'array');
  v_antes     int;
  v_depois    int;
  v_codigos   jsonb := coalesce(p_codigos, '[]'::jsonb);
  v_cortados  int[] := '{}';
  v_r         jsonb;
  v_base      text;       -- 214
  v_papel     text;       -- 214
BEGIN
  -- ---------------------------------------------------- registrar ----
  -- (igual a versao anterior: as ferramentas viram carimbo no turno)
  IF v_tem_lista THEN
    PERFORM nai_usou_ferramenta(p_turno, '_lidas');
    PERFORM nai_usou_ferramenta(p_turno, x)
       FROM jsonb_array_elements_text(p_ferramentas) x WHERE btrim(x) <> '';
  END IF;

  SELECT contato_id INTO v_contato FROM nai_turno WHERE id = p_turno;
  v_antes := jsonb_array_length(v_codigos);

  -- --------------------------------------- parede 1: houve consulta? --
  IF v_tem_lista AND v_antes > 0 THEN
    SELECT bool_or(nai_ferramenta_de_imovel(x)) INTO v_consultou
      FROM jsonb_array_elements_text(p_ferramentas) x;

    IF NOT coalesce(v_consultou, false) THEN
      SELECT coalesce(array_agg(e::int), '{}') INTO v_cortados
        FROM jsonb_array_elements_text(v_codigos) e;
      v_codigos := '[]'::jsonb;
      PERFORM nai_anotar(p_turno, 21, 'saida_sem_consulta', 'cortou',
        'nenhuma ferramenta de imóvel foi chamada; ' || coalesce(array_length(v_cortados,1),0)
        || ' código(s) não saíram: ' || array_to_string(v_cortados, ', '));
    END IF;
  END IF;

  -- ------------------------------------ parede 2: rejeitado nao volta --
  IF v_contato IS NOT NULL AND jsonb_array_length(v_codigos) > 0 THEN
    SELECT codigos_rejeitados INTO v_rej
      FROM nai_estado_conversa WHERE contato_id = v_contato;

    IF coalesce(array_length(v_rej, 1), 0) > 0 THEN
      SELECT coalesce(array_agg(e::int), '{}') INTO v_cortados
        FROM jsonb_array_elements_text(v_codigos) e WHERE e::int = ANY (v_rej);

      SELECT coalesce(jsonb_agg(e), '[]'::jsonb) INTO v_codigos
        FROM jsonb_array_elements_text(v_codigos) e WHERE NOT (e::int = ANY (v_rej));

      IF coalesce(array_length(v_cortados,1),0) > 0 THEN
        PERFORM nai_anotar(p_turno, 21, 'imovel_rejeitado', 'cortou',
          'ele já recusou: ' || array_to_string(v_cortados, ', ') || ' -- não volta');
      END IF;
    END IF;
  END IF;

  -- ------------------------------------------- o que sobrou, registra --
  v_depois := jsonb_array_length(v_codigos);
  IF v_antes <> v_depois THEN
    PERFORM nai_registrar_saida_v2(p_turno,
      jsonb_build_object('codigos', v_codigos),
      jsonb_build_object('cortados', v_antes - v_depois));
  END IF;

  -- O ESTADO APRENDE COM O QUE SAIU: o que for mostrado agora entra em
  -- `codigos_mostrados`, e o ultimo vira o foco. E assim que a proxima
  -- mensagem curta ("esse nao", "pode ser") ganha sentido.
  IF v_contato IS NOT NULL AND v_depois > 0 THEN
    PERFORM nai_estado_gravar_v2(
      v_contato,
      (SELECT max(e::int) FROM jsonb_array_elements_text(v_codigos) e),
      'mostramos',
      ARRAY(SELECT e::int FROM jsonb_array_elements_text(v_codigos) e),
      '{}', p_texto, NULL, NULL);
  ELSIF v_contato IS NOT NULL AND nullif(btrim(coalesce(p_texto,'')), '') IS NOT NULL THEN
    PERFORM nai_estado_gravar_v2(v_contato, NULL, NULL, '{}', '{}', p_texto, NULL, NULL);
  END IF;

  -- ---------------------------------------------------- o gargalo ----
  -- Filtrar a ENTRADA nao basta, e o teste provou: `nai_enfileirar_resposta`
  -- RECALCULA a propria lista de codigos por dentro, via
  -- `nai_conferir_resposta` (o campo `d->'cods'`), lendo o texto de novo.
  -- Passei a lista ja limpa e sairam 12 fotos do imovel recusado mesmo
  -- assim.
  --
  -- Entao a parede fica DEPOIS, sobre o que de fato entrou na caixa de
  -- saida. E o unico ponto por onde tudo passa, venha de onde vier:
  -- da resposta, da fila dos outros imoveis, ou de qualquer funcao que
  -- alguem escreva amanha.
  v_r := nai_enfileirar_resposta(p_turno, p_texto, v_codigos, p_escreveu, p_fotos_site);

  IF v_contato IS NOT NULL THEN
    SELECT codigos_rejeitados INTO v_rej FROM nai_estado_conversa WHERE contato_id = v_contato;

    IF coalesce(array_length(v_rej, 1), 0) > 0 THEN
      WITH fora AS (
        DELETE FROM nai_saida s
         WHERE s.turno_id = p_turno
           AND s.codigo = ANY (v_rej)
           AND s.estado = 'pendente'          -- nunca mexer no que ja saiu
        RETURNING s.codigo
      )
      SELECT coalesce(array_agg(DISTINCT codigo), '{}') INTO v_cortados FROM fora;

      IF coalesce(array_length(v_cortados, 1), 0) > 0 THEN
        PERFORM nai_anotar(p_turno, 23, 'rejeitado_fora_da_caixa', 'cortou',
          'tirei da caixa de saída o que ele já recusou: ' || array_to_string(v_cortados, ', '));
      END IF;
    END IF;
  END IF;

  -- 214: A PAREDE CORTOU E NÃO SOBROU NADA. Sem isto o corretor ficava sem
  -- resposta ("Manda as de locação", "Cliente gostou do apto"). Cortesia continua
  -- sem resposta, de propósito.
  SELECT papel INTO v_papel FROM nai_turno WHERE id = p_turno;
  IF v_contato IS NOT NULL AND v_papel = 'corretor' AND v_tem_lista AND v_antes > 0
     AND NOT coalesce(v_consultou, false)
     AND NOT EXISTS (SELECT 1 FROM nai_saida s WHERE s.turno_id = p_turno)
     AND nullif(btrim(coalesce(p_escreveu, '')), '') IS NOT NULL
     AND NOT nai_e_so_cortesia(p_escreveu) THEN
    v_base := nai_escalar_calado(p_turno, p_escreveu, 'resposta cortada: ia mandar imóvel sem consultar', NULL);
    IF v_base IS NOT NULL THEN
      PERFORM nai_enfileirar_texto(p_turno, NULL, v_contato, 'turno', v_base, 'resposta', 1);
      PERFORM nai_anotar(p_turno, 24, 'corte_sem_silencio', 'mudou', 'a ficha respondeu no lugar do que foi cortado');
    ELSE
      PERFORM nai_anotar(p_turno, 24, 'corte_sem_silencio', 'parou', 'nada saiu depois do corte: foi ao Tel');
    END IF;
  END IF;

  -- 223: ELE PERGUNTOU DO ELEVADOR: depois da resposta, a pergunta do perfil
  -- ("Para o seu cliente, só serve imóvel com elevador?"), uma vez por perfil
  BEGIN
    IF v_contato IS NOT NULL AND v_papel = 'corretor' AND coalesce(p_escreveu, '') ~* 'elevador'
       AND EXISTS (SELECT 1 FROM nai_saida s WHERE s.turno_id = p_turno)
       AND NOT EXISTS (SELECT 1 FROM nai_perfil_ativo(v_contato) pa
                        WHERE pa.exige ? 'elevador' OR pa.pendente = 'elevador') THEN
      PERFORM nai_perfil_gravar(v_contato, false, NULL, NULL, NULL, NULL, NULL, NULL);
      UPDATE nai_perfil_cliente SET pendente = 'elevador', pendente_em = now()
       WHERE id = (SELECT id FROM nai_perfil_ativo(v_contato));
      -- uma pergunta por vez: a sugestão de visita deste turno sai (volta depois)
      DELETE FROM nai_saida WHERE turno_id = p_turno AND motivo = 'sugere_visita' AND estado = 'pendente';
      PERFORM nai_enfileirar_texto(p_turno, NULL, v_contato, 'turno',
        'Para o seu cliente, só serve imóvel com elevador?', 'perfil_do_cliente', 95);
      PERFORM nai_anotar(p_turno, 24, 'perfil_do_cliente', 'mudou', 'perguntou se o cliente só aceita com elevador');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL;   -- a pergunta do perfil nunca derruba a resposta
  END;

  RETURN v_r;
END;
$function$;
