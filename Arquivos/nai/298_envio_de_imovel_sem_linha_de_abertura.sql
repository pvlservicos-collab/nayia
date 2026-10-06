-- 298 (06/10/2026, Pedro): "quando recebi o imóvel ela me mandou isso também: Oi, boa tarde! Segue o imóvel que
-- fiquei de te enviar. Não é para ter essa mensagem fixa nos cards de envio de imóvel, eu já tinha pedido para
-- retirar ... só o card e fotos, para todo imóvel que ela envia ela tá enviando isso junto, retira".
-- A 294 só tinha tirado o cumprimento quando já havia conversa no dia; a frase "Segue o imóvel..." continuava
-- indo sempre. Agora nai_enviar_imoveis_para manda só o card e as fotos de cada imóvel. O resto da função é a
-- viva de producao/funcoes (as variáveis v_hora e v_falou ficam declaradas, sem uso).
BEGIN;

CREATE OR REPLACE FUNCTION public.nai_enviar_imoveis_para(p_turno bigint, p_codigos integer[], p_telefone text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_digitos text := regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g');
  v_chave   text;
  v_destino bigint;
  v_card    text;
  v_ja      timestamptz;
  v_hora    int;
  v_falou   boolean;
  v_ordem   int := 1;
  v_fotos   int;
  v_vao     int[] := '{}';
  v_linhas  text[] := '{}';
  v_feitos  text[] := '{}';
  c         int;
  i         record;
  f         record;
BEGIN
  IF length(v_digitos) < 10 THEN
    RETURN 'Não entendi o número "' || coalesce(p_telefone, '') || '". Manda assim: envia [telefone …9999] o 3210';
  END IF;
  v_chave := nai_chave(v_digitos);
  IF v_chave IS NULL OR coalesce(array_length(p_codigos, 1), 0) = 0 THEN
    RETURN 'Não entendi o pedido. Manda assim: envia [telefone …9999] o 3210';
  END IF;

  -- 1. o que pode ir
  FOREACH c IN ARRAY p_codigos LOOP
    SELECT codigo, coalesce(e_parceiro, false) AS parceiro,
           nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site) AS no_mercado
      INTO i FROM imoveis WHERE codigo = c;
    IF i.codigo IS NULL OR (SELECT texto_pronto FROM nai_card_do_imovel(c)) IS NULL THEN
      v_linhas := v_linhas || (c || ': não achei esse código');
    ELSIF i.parceiro THEN
      v_linhas := v_linhas || (c || ': é imóvel de parceiro, não mandei (parceria não sai)');
    ELSIF NOT coalesce(i.no_mercado, false) THEN
      v_linhas := v_linhas || (c || ': está indisponível, não mandei');
    ELSE
      v_ja := nay_reservar_imovel_do_dia(v_chave, c, 'nai', p_turno);
      IF v_ja IS NOT NULL THEN
        v_linhas := v_linhas || (c || ': já foi para esse número ' || nay_quando_foi(v_ja)
                                 || ', não mandei de novo (libera '
                                 || nay_quando_foi(v_ja + interval '24 hours') || ')');
      ELSE
        v_vao := v_vao || c;
      END IF;
    END IF;
  END LOOP;

  IF coalesce(array_length(v_vao, 1), 0) = 0 THEN
    RETURN 'Não mandei nada para ' || nai_fone_fmt(v_digitos) || E':\n'
           || array_to_string(v_linhas, E'\n');
  END IF;

  -- 2. o contato do destino (nasce aqui se não existir)
  SELECT id INTO v_destino FROM nai_contato WHERE chave = v_chave;
  IF v_destino IS NULL THEN
    INSERT INTO nai_contato (chave, telefone, nome_whatsapp)
    VALUES (v_chave, v_digitos, NULL)
    RETURNING id INTO v_destino;
  END IF;

  -- 3. (298, Pedro 06/10) SEM linha de abertura: "não é para ter essa mensagem fixa nos cards de envio de
  --    imóvel ... só o card e fotos". Saiu o "Oi, boa tarde! Segue o imóvel que fiquei de te enviar." que ia
  --    antes de todo envio (comando ENVIA, aba Enviar imóvel do site/CRM e o "Me envia" do /imoveis).

  -- 4. card e fotos, um imóvel de cada vez, na ordem pedida
  FOREACH c IN ARRAY v_vao LOOP
    SELECT texto_pronto INTO v_card FROM nai_card_do_imovel(c);
    v_ordem := v_ordem + 1;
    PERFORM nai_enfileirar_texto(p_turno, NULL, v_destino, 'entrega', v_card, 'envia_comando', v_ordem);
    v_fotos := 0;
    FOR f IN SELECT * FROM nai_imagens_do_envio(c) LOOP
      -- a colagem de 4 fotos é só dos grupos (Tel, 14/09)
      CONTINUE WHEN f.e_colagem;
      v_ordem := v_ordem + 1;
      INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino,
                             tipo, imagem_url, codigo, ordem, motivo)
      VALUES (p_turno, v_destino, 'entrega', v_chave, 'imagem', f.url, c, v_ordem, 'foto');
      v_fotos := v_fotos + 1;
    END LOOP;
    v_feitos := v_feitos || (c || ' (card e ' || v_fotos || ' foto' || CASE WHEN v_fotos = 1 THEN '' ELSE 's' END || ')');
  END LOOP;

  RETURN 'Mandei para ' || nai_fone_fmt(v_digitos) || ': ' || array_to_string(v_feitos, ', ')
         || CASE WHEN array_length(v_linhas, 1) > 0
                 THEN E'.\n' || array_to_string(v_linhas, E'\n') ELSE '.' END;
END;
$function$;

COMMIT;
