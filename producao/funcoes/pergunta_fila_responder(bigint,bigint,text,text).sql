CREATE OR REPLACE FUNCTION public.pergunta_fila_responder(p_turno bigint, p_contato bigint, p_texto text, p_citado text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  f      pergunta_fila;
  s      text;
  a      text;
  pos    record;
  v_dest bigint;
  v_msg  text;
  v_ass  text;
  v_quem text;
BEGIN
  IF NOT pergunta_fila_resposta_valida(p_contato, p_texto, p_citado) THEN RETURN NULL; END IF;
  SELECT * INTO f FROM pergunta_fila WHERE estado = 'perguntada' LIMIT 1 FOR UPDATE;
  IF f.id IS NULL THEN RETURN NULL; END IF;
  SELECT * INTO pos FROM pergunta_fila_posicao();
  s := btrim(regexp_replace(coalesce(p_texto, ''), '^\s*@?nay[\s,:;.!-]*', '', 'i'));
  a := lower(unaccent(s));
  v_quem := coalesce(nullif(btrim(f.cliente), '') || ' — ', '') || nai_fone_fmt(f.chave);

  IF a ~ '^(pular|pula|pulo|depois|deixa (para|pra) depois)[\s.!]*$' THEN
    IF NOT EXISTS (SELECT 1 FROM pergunta_fila WHERE estado = 'fila') THEN
      v_msg := 'Essa é a única pergunta da fila: continua esperando a sua resposta (ou DESCARTAR).';
    ELSE
      UPDATE pergunta_fila SET estado = 'fila', perguntada_em = NULL, cobrada_em = NULL, saida_id = NULL,
                               ordem = (SELECT max(ordem) + 1 FROM pergunta_fila)
       WHERE id = f.id;
      v_msg := 'Deixei a pergunta ' || pos.k || '/' || pos.n || ' para o fim da fila.';
    END IF;
  ELSIF a ~ '^(descartar|descarta|descarte|tira|tirar)( (da|essa|a) (fila|pergunta))?[\s.!]*$' THEN
    UPDATE pergunta_fila SET estado = 'descartada', respondida_em = now() WHERE id = f.id;
    IF f.origem = 'pendencias' THEN
      UPDATE pendencias SET status = 'descartada', respondida_em = now() WHERE id = f.origem_id;
    END IF;
    v_msg := 'Tirei da fila a pergunta ' || pos.k || '/' || pos.n || '.';
  ELSE
    UPDATE pergunta_fila SET estado = 'respondida', resposta = s, respondida_em = now() WHERE id = f.id;
    IF f.linha = 'parceria' THEN
      SELECT id INTO v_dest FROM nai_contato WHERE chave = nai_chave(f.chave) LIMIT 1;
      IF v_dest IS NULL THEN
        SELECT id INTO v_dest FROM nai_contato
         WHERE right(regexp_replace(coalesce(telefone, ''), '\D', '', 'g'), 8) = right(f.chave, 8) ORDER BY id LIMIT 1;
      END IF;
      IF v_dest IS NOT NULL THEN
        -- o mesmo caminho do DEVOLVER: 'entrega' a partir do turno do Tel, motivo resposta_do_tel (fecha a pendência)
        PERFORM nai_enfileirar_texto(p_turno, NULL, v_dest, 'entrega',
          'Sobre ' || CASE WHEN f.codigo IS NOT NULL
                           THEN 'o #' || f.codigo || coalesce(' (' || nullif(btrim(f.imovel), '') || ')', '')
                           ELSE 'a sua pergunta' END || ': ' || nai_frase_maiuscula(s),
          'resposta_do_tel', 2);
        UPDATE pergunta_fila SET entregue_em = now() WHERE id = f.id;
        v_msg := '✅ Peguei a resposta da pergunta ' || pos.k || '/' || pos.n || ' e mandei para ' || v_quem || '.';
      ELSE
        UPDATE pergunta_fila SET entrega_erro = 'a conversa do cliente não foi achada' WHERE id = f.id;
        v_msg := '⚠️ Peguei a resposta da pergunta ' || pos.k || '/' || pos.n || ', mas não achei a conversa de '
                 || v_quem || ' para entregar.';
      END IF;
    ELSE
      v_msg := '✅ Peguei a resposta da pergunta ' || pos.k || '/' || pos.n || ': a Nay manda para ' || v_quem
               || ' pelo WhatsApp de captação.';
    END IF;
    IF f.origem = 'pendencias' THEN
      UPDATE pendencias SET status = 'respondida', resposta = s, respondida_em = now() WHERE id = f.origem_id;
    END IF;
    -- a memória: com o código, a resposta fica no imóvel (sem número de unidade, que é de um apartamento só)
    IF f.codigo IS NOT NULL AND a !~ '\m(apto|ap|apartamento|bloco|torre|unidade)\s*\.?\s*\d' THEN
      v_ass := coalesce(nay_assunto_do_imovel(f.pergunta),
                        'pergunta: ' || left(lower(unaccent(btrim(regexp_replace(f.pergunta, '\s+', ' ', 'g')))), 120));
      PERFORM nay_gravar_conhecimento(f.codigo::text, v_ass, s, 'tel (fila de perguntas)');
    END IF;
  END IF;
  PERFORM nai_enfileirar_texto(p_turno, NULL, p_contato, 'turno', v_msg, 'pergunta_fila_ok', 1);
  PERFORM pergunta_fila_perguntar_proxima();
  RETURN v_msg;
END
$function$;
