CREATE OR REPLACE FUNCTION public.nai_fila_dos_outros_imoveis(p_turno bigint, p_escreveu text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  t       nai_turno;
  k       nai_contato;
  v_cods  int[];
  v_ja    int[];
  v_rej   int[];
  v_ordem int;
  c       int;
  f       record;
  v_card  text;
  n       int := 0;
  v_teto  int := 3;
  p       jsonb;
  v_txt   text;
  v_neg   text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN 0; END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  -- 1. a secretaria nao tem catalogo
  IF t.atendente = 'secretaria' THEN
    PERFORM nai_anotar(p_turno, 22, 'fila_de_imoveis', 'cortou',
                       'quem atende é a secretária: ela não manda imóvel do catálogo');
    RETURN 0;
  END IF;

  p := nai_pedido_do_turno(p_turno);

  -- 2. oferta nao e pedido
  IF coalesce((p->>'oferta')::boolean, false) OR coalesce((p->>'link')::boolean, false) THEN
    PERFORM nai_anotar(p_turno, 22, 'fila_de_imoveis', 'cortou',
                       'ele está oferecendo, não pedindo');
    RETURN 0;
  END IF;

  -- 3. o Jev disse que nao foi pedido
  IF NOT nai_pediu_imovel(p_turno) THEN
    PERFORM nai_anotar(p_turno, 22, 'fila_de_imoveis', 'cortou',
                       'o Jev disse que ele não pediu imóvel neste turno');
    RETURN 0;
  END IF;

  -- 144: NOME DE BAIRRO NAO E PEDIDO DE CONDOMINIO (Walter, 28/09 10:44: ele
  -- respondeu "Ponta negra" a pergunta do bairro e recebeu 3 cards do
  -- Residencial Ponta Negra II, de venda).
  IF nai_e_so_bairro(coalesce(nullif(p_escreveu, ''), t.texto)) THEN
    PERFORM nai_anotar(p_turno, 22, 'fila_de_imoveis', 'cortou', 'ele disse um bairro, nao um imovel');
    RETURN 0;
  END IF;
  v_txt  := coalesce(nullif(p_escreveu, ''), t.texto);
  v_cods := nai_imoveis_pedidos(v_txt, k.telefone);
  IF coalesce(array_length(v_cods, 1), 0) < 2 THEN RETURN 0; END IF;

  -- 147: NOME DE BAIRRO DENTRO DA FRASE NAO E CONDOMINIO (Taysa, 28/09 11:19:
  -- "Tem algo de 3 dormitorios / Pq das laranjeiras ou pq dez" virou o
  -- Residencial Laranjeiras e o Laranjeiras Premium, os dois de venda, com
  -- todas as fotos). O codigo que ele DIGITOU fica sempre.
  v_cods := ARRAY(SELECT u.c FROM unnest(v_cods) WITH ORDINALITY u(c, o)
                   WHERE u.c::text = ANY (coalesce(nay_codigos_citados(v_txt), '{}'))
                      OR NOT nai_nome_so_do_bairro(v_txt, u.c)
                   ORDER BY u.o);

  -- 147: LOCACAO OU VENDA AINDA NAO SE SABE -> A PERGUNTA VEM ANTES DO IMOVEL.
  -- Tel: "ela perguntou aluguel ou venda mas nao esperou, mandou varios ap de
  -- vendas para a mulher que ela nao pediu, ela nao pode fazer isso". So o
  -- codigo digitado passa: esse ja e o imovel, seja do negocio que for.
  v_neg := nai_negocio_do_pedido(k.id, v_txt);
  IF v_neg IS NULL THEN
    v_cods := ARRAY(SELECT u.c FROM unnest(v_cods) WITH ORDINALITY u(c, o)
                     WHERE u.c::text = ANY (coalesce(nay_codigos_citados(v_txt), '{}'))
                     ORDER BY u.o);
  END IF;
  IF coalesce(array_length(v_cods, 1), 0) < 2 THEN
    PERFORM nai_anotar(p_turno, 22, 'fila_de_imoveis', 'cortou',
      CASE WHEN v_neg IS NULL THEN 'ainda não se sabe se é locação ou venda: a pergunta vem antes do imóvel'
           ELSE 'o nome era de bairro, não de condomínio' END);
    RETURN 0;
  END IF;

  SELECT coalesce(array_agg(DISTINCT s.codigo), '{}') INTO v_ja
    FROM nai_saida s WHERE s.turno_id = p_turno AND s.codigo IS NOT NULL;
  SELECT coalesce(max(s.ordem), 0) INTO v_ordem FROM nai_saida s WHERE s.turno_id = p_turno;

  -- 4. O QUE ELE RECUSOU (era o que faltava)
  SELECT codigos_rejeitados INTO v_rej FROM nai_estado_conversa WHERE contato_id = t.contato_id;

  FOREACH c IN ARRAY v_cods LOOP
    EXIT WHEN n >= v_teto;
    CONTINUE WHEN c = ANY (v_ja);
    CONTINUE WHEN c = ANY (coalesce(v_rej, '{}'));
    -- 144: o negocio da conversa manda (locacao nao recebe imovel so de venda).
    CONTINUE WHEN v_neg = 'locacao'
                  AND NOT EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = c AND coalesce(i.valor_aluguel, 0) > 0);
    CONTINUE WHEN v_neg = 'venda'
                  AND NOT EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = c AND coalesce(i.valor_venda, 0) > 0);
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM imoveis i
                               WHERE i.codigo = c
                                 AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
                                 AND NOT coalesce(i.e_parceiro, false));

    SELECT cc.texto_pronto INTO v_card FROM nai_card_do_imovel(c) cc;
    CONTINUE WHEN v_card IS NULL;

    v_ordem := v_ordem + 1;
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_card, 'resposta', v_ordem);

    FOR f IN SELECT * FROM nai_imagens_do_envio(c) LOOP
      v_ordem := v_ordem + 1;
      INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, imagem_url, codigo, ordem, motivo)
           VALUES (p_turno, t.contato_id, 'turno', '', 'imagem', f.url, c, v_ordem,
                   CASE WHEN f.e_colagem THEN 'colagem' ELSE 'foto' END);
    END LOOP;

    n := n + 1;
  END LOOP;

  IF n > 0 THEN
    PERFORM nai_anotar(p_turno, 22, 'fila_de_imoveis', 'mudou',
                       'ele pediu ' || array_length(v_cods, 1) || ' imóveis; ' || n || ' foram para a fila');
  END IF;
  RETURN n;
END;
$function$
;
