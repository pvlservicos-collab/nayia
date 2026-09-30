CREATE OR REPLACE FUNCTION public.nai_conferir_texto_da_saida(p_turno bigint)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE r record; v_novo text; n int := 0;
BEGIN
  IF nai_cfg('conferencia_confere_texto', 'sim') <> 'sim' THEN RETURN 0; END IF;

  FOR r IN
    SELECT id, texto FROM nai_saida
     WHERE turno_id = p_turno AND estado = 'pendente' AND codigo IS NULL
       AND papel_destino <> 'tel' AND texto ~ '\m\d{3,5}\s*[—–-]\s*\w'
  LOOP
    v_novo := nai_texto_sem_os_barrados(r.texto);
    CONTINUE WHEN v_novo = r.texto;

    -- sobrou lista? entao so tira a linha. Nao sobrou: a mensagem inteira sai.
    IF v_novo ~ '\m\d{3,5}\s*[—–-]\s*\w' THEN
      UPDATE nai_saida SET texto = v_novo WHERE id = r.id;
      PERFORM nai_anotar(p_turno, 23, 'texto_conferido', 'tirou linha',
                         'linha de imóvel de parceiro ou fora do mercado');
    ELSE
      UPDATE nai_saida SET estado = 'bloqueado', bloqueio = 'texto citava imóvel barrado'
       WHERE id = r.id;
      PERFORM nai_avisar_tel(p_turno, NULL,
        'Tel, segurei uma mensagem: ela ia listar imóvel de parceiro (ou fora do mercado) '
        || 'escrito no texto -- "' || left(r.texto, 200) || '". Não mandei nada.',
        'texto_com_imovel_barrado');
      PERFORM nai_anotar(p_turno, 23, 'texto_conferido', 'barrou', left(r.texto, 200));
    END IF;
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$function$
;
