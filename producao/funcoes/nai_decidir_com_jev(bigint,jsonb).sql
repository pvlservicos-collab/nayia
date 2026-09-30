CREATE OR REPLACE FUNCTION public.nai_decidir_com_jev(p_turno bigint, p_jev jsonb)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_cortesia real; v_oferta real; v_atendente text; v_conf real;
  v_imagem text; v_tipo text; v_fin text;
  v_pedido real; v_pediu boolean;
  v_piso_c real := coalesce(nullif(nai_cfg('jev_piso_cortesia','0.70'),''),'0.70')::real;
  v_piso_o real := coalesce(nullif(nai_cfg('jev_piso_oferta','0.60'),''),'0.60')::real;
  v_piso_p real := coalesce(nullif(nai_cfg('jev_piso_pedido','0.60'),''),'0.60')::real;
  v_escolha text; v_motivo text;
BEGIN
  INSERT INTO nai_jev (turno_id, respostas, modelo, custo)
       VALUES (p_turno, coalesce(p_jev, '{}'::jsonb),
               p_jev->>'modelo', (p_jev->>'custo')::numeric);

  v_cortesia  := coalesce((p_jev #>> '{cortesia,noul}')::real, 0);
  v_oferta    := coalesce((p_jev #>> '{oferta,noul}')::real, 0);
  v_atendente := p_jev #>> '{atendente,choice}';
  v_conf      := coalesce((p_jev #>> '{atendente,confidence}')::real, 0);
  v_imagem    := p_jev #>> '{o_que_mandou,choice}';
  v_tipo      := p_jev #>> '{tipo,choice}';
  v_fin       := p_jev #>> '{finalidade,choice}';

  -- O CAMPO NOVO. Ausente = NULL, e a 117 volta a mandar. Nao precisa
  -- gravar em lugar nenhum: o INSERT em `nai_jev` la em cima ja guardou
  -- a resposta inteira, e `nai_jev_pedido` le de la.
  v_pedido := (p_jev #>> '{pedido,noul}')::real;
  IF v_pedido IS NOT NULL THEN
    v_pediu := v_pedido >= v_piso_p;
  END IF;

  -- 1. CORTESIA nao decide nada: quem decide e a conversa de antes.
  IF v_cortesia >= v_piso_c THEN
    v_escolha := 'locacao';   -- `nai_mente_registrar` troca pela conversa anterior
    v_motivo  := 'cortesia (' || round(v_cortesia::numeric, 2) || ')';

  -- 2. OFERTA E DA SECRETARIA, e este sinal vale MAIS que o campo
  --    `atendente`: o sinal especifico ganha do geral.
  ELSIF v_oferta >= v_piso_o OR v_imagem = 'anuncio_dele' THEN
    v_escolha := 'secretaria';
    v_motivo  := 'oferece imóvel dele (' || round(v_oferta::numeric, 2) || ')'
                 || CASE WHEN v_imagem = 'anuncio_dele' THEN ' + anúncio na foto' ELSE '' END;

  -- 3. O resto segue a escolha do Jev.
  ELSE
    v_escolha := CASE WHEN v_atendente = 'secretaria' THEN 'secretaria' ELSE 'locacao' END;
    v_motivo  := coalesce(v_atendente, 'sem resposta') || ' (' || round(v_conf::numeric, 2) || ')'
                 || coalesce(' · foto: ' || v_imagem, '')
                 || CASE WHEN v_pedido IS NOT NULL
                         THEN ' · pediu imóvel: ' || CASE WHEN v_pediu THEN 'sim' ELSE 'não' END
                              || ' (' || round(v_pedido::numeric, 2) || ')'
                         ELSE '' END;
  END IF;

  IF v_tipo IN ('casa', 'apartamento') AND nai_tipo_da_conversa(
       (SELECT contato_id FROM nai_turno WHERE id = p_turno),
       (SELECT texto FROM nai_turno WHERE id = p_turno)) IS NULL THEN
    PERFORM nai_anotar(p_turno, 5, 'jev_leu_o_tipo', 'passou',
                       'o Jev entendeu ' || v_tipo || ', e a conversa não dizia');
  END IF;

  RETURN nai_mente_registrar(p_turno, v_escolha, v_motivo, 'jev');
END;
$function$;
