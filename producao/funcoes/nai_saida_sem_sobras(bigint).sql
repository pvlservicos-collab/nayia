CREATE OR REPLACE FUNCTION public.nai_saida_sem_sobras(p_turno bigint)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_foto boolean; v_card boolean; v_resp boolean;
  n int := 0; m int;
BEGIN
  -- 224: a conferencia (116, 190) barra o card ou a foto que nao batem com o
  -- pedido, mas a frase que ia junto saia sozinha: em 30/09 o Marcio recebeu
  -- "📌 Status: Disponivel" e "Aqui as fotos, quer fazer uma visita?" sem card
  -- e sem foto nenhuma atras.
  SELECT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = p_turno AND estado = 'pendente' AND tipo = 'imagem'),
         EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = p_turno AND estado = 'pendente' AND tipo = 'texto'
                  AND texto ~* 'C[óo]digo:\s*\d{3,5}'),
         EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = p_turno AND estado = 'pendente' AND tipo = 'texto'
                  AND motivo = 'resposta')
    INTO v_foto, v_card, v_resp;

  IF NOT v_card THEN
    UPDATE nai_saida SET estado = 'bloqueado', bloqueio = 'sobra: o card do status foi barrado'
     WHERE turno_id = p_turno AND estado = 'pendente' AND motivo = 'status';
    GET DIAGNOSTICS m = ROW_COUNT; n := n + m;
  END IF;

  IF NOT v_foto THEN
    IF v_card OR v_resp THEN
      UPDATE nai_saida SET texto = 'Quer fazer uma visita? Só me informar um horário'
       WHERE turno_id = p_turno AND estado = 'pendente' AND motivo = 'depois_das_fotos'
         AND texto LIKE 'Aqui as fotos,%';
    ELSE
      UPDATE nai_saida SET estado = 'bloqueado', bloqueio = 'sobra: as fotos e o card foram barrados'
       WHERE turno_id = p_turno AND estado = 'pendente' AND motivo = 'depois_das_fotos';
    END IF;
    GET DIAGNOSTICS m = ROW_COUNT; n := n + m;
  END IF;

  -- Barrou tudo o que era imovel e nao sobrou nada para ele: o Tel fica sabendo.
  IF n > 0
     AND NOT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = p_turno AND estado = 'pendente'
                        AND papel_destino <> 'tel')
     AND NOT EXISTS (SELECT 1 FROM nai_saida WHERE turno_id = p_turno AND motivo = 'saida_sem_imovel') THEN
    PERFORM nai_avisar_tel(p_turno, NULL,
      'Tel, a conferência barrou os imóveis desta resposta (não batiam com o que o corretor pediu), '
      || 'então não mandei nada. Dá uma olhada nesse chat.', 'saida_sem_imovel');
  END IF;

  IF n > 0 THEN
    PERFORM nai_anotar(p_turno, 23, 'sobras_da_caixa', 'mudou', n || ' linha(s) sem o card ou a foto atrás');
  END IF;
  RETURN n;
END;
$function$;
