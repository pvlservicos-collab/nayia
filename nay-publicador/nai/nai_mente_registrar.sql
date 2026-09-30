CREATE OR REPLACE FUNCTION public.nai_mente_registrar(p_turno bigint, p_atendente text, p_motivo text, p_por text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE v_at text; v_motivo text; v_contato bigint; v_ficha bigint;
        v_texto text; v_antes text; v_por text; p jsonb;
        v_pediu boolean;
BEGIN
  v_at := CASE WHEN lower(coalesce(p_atendente, '')) = 'secretaria' THEN 'secretaria' ELSE 'locacao' END;
  v_motivo := left(coalesce(p_motivo, ''), 300);
  v_por := coalesce(p_por, 'mente');

  SELECT contato_id, texto INTO v_contato, v_texto FROM nai_turno WHERE id = p_turno;
  v_pediu := nai_jev_pedido(p_turno);   -- NULL quando o Jev nao respondeu
  p := nai_pedido_do_turno(p_turno);

  -- 1. CORTESIA SEGUE COM QUEM JA ESTAVA (115). Continua igual: nao e
  --    palpite de palavra, e a conversa de antes.
  IF (p->>'cortesia')::boolean THEN
    SELECT t.atendente INTO v_antes FROM nai_turno t
     WHERE t.contato_id = v_contato AND t.id < p_turno
       AND t.criado_em > now() - interval '6 hours'
     ORDER BY t.id DESC LIMIT 1;
    IF v_antes IS NOT NULL AND v_antes <> v_at THEN
      v_at := v_antes; v_motivo := 'cortesia: segue com quem já atendia'; v_por := 'cola';
    END IF;
  END IF;

  -- 2. A 117, AGORA COM DUAS CARAS.
  --
  --    Com resposta do Jev (v_pediu NOT NULL): ela NAO manda mais. Vira
  --    anotacao, para dar para medir quantas vezes ela teria trocado a
  --    decisao -- e para poder voltar atras com dado, nao com impressao.
  --    Falar de imovel nao e pedir imovel, e era exatamente isso que ela
  --    confundia.
  --
  --    Sem resposta do Jev: ela manda como sempre mandou. Enquanto o no
  --    do n8n nao mandar o campo, nada aqui muda.
  IF v_at = 'secretaria'
     AND (p->>'de_imovel')::boolean
     AND NOT (p->>'oferta')::boolean
     AND NOT (p->>'link')::boolean THEN
    IF v_pediu IS NULL THEN
      v_at := 'locacao';
      v_motivo := 'fala de imóvel: é da de imóveis (a mente disse: ' || left(v_motivo, 80) || ')';
      v_por := 'regra';
    ELSE
      PERFORM nai_anotar(p_turno, 4, 'regra_117_virou_aviso',
                         CASE WHEN v_pediu THEN 'passou' ELSE 'passou' END,
                         'fala de imóvel, mas o Jev disse pediu_imovel=' || v_pediu
                         || ' -- a decisão dele ficou de pé');
    END IF;
  END IF;

  -- 3. A COLA DO CADASTRO (99e): ficha aberta manda em tudo. FICA.
  --    Isto nao e palpite de palavra: e estado -- existe uma ficha meio
  --    preenchida, e abandonar ela no meio deixa o corretor falando com
  --    duas atendentes na mesma frase. Foi a maior sobrescritora medida
  --    (36 de 80), e continua sendo, de proposito.
  SELECT n.id INTO v_ficha FROM nai_imovel_novo n
   WHERE n.contato_id = v_contato AND n.situacao = 'colhendo'
     AND n.criado_em > now() - interval '24 hours'
   ORDER BY n.id DESC LIMIT 1;
  IF v_ficha IS NOT NULL AND nai_secretaria_ligada() THEN
    -- O CORRETOR JA RESPONDEU: guarda antes de perguntar de novo (124b).
    -- Sem isto a ficha so era preenchida se o modelo lembrasse de chamar a
    -- ferramenta -- e foi assim que a Nay perguntou cinco vezes a mesma
    -- coisa enquanto ele respondia tudo.
    PERFORM nai_cadastro_absorver(v_ficha, p->>'texto');

    IF nai_cfg('cola_solta_no_catalogo','sim') = 'sim'
       AND nai_pergunta_de_catalogo(p->>'texto') THEN
      PERFORM nai_anotar(p_turno, 5, 'cola_soltou', 'passou',
                         'ficha ' || v_ficha || ' aberta, mas ele perguntou do catalogo');
    ELSE
      v_at := 'secretaria'; v_motivo := 'cadastro em andamento (ficha ' || v_ficha || ')'; v_por := 'cola';
    END IF;
  END IF;

  -- 4. OFERTA E LINK SAO DELA, sempre (97, 111). FICA.
  --    Sinal especifico e medido: no teste, oferta 0,77 com
  --    atendente=secretaria 0,41 -- o especifico ganha do geral.
  IF ((p->>'oferta')::boolean OR (p->>'link')::boolean) AND nai_secretaria_ligada() THEN
    v_at := 'secretaria';
    v_motivo := CASE WHEN (p->>'link')::boolean THEN 'link de catálogo' ELSE 'está oferecendo imóvel' END;
    v_por := 'regra';
  END IF;

  IF v_at = 'secretaria' AND NOT nai_secretaria_ligada() THEN
    v_at := 'locacao'; v_motivo := 'secretaria desligada';
  END IF;

  UPDATE nai_turno SET atendente = v_at WHERE id = p_turno;
  INSERT INTO nai_mente (turno_id, atendente, motivo, por) VALUES (p_turno, v_at, v_motivo, v_por);
  PERFORM nai_anotar(p_turno, 4, 'mente_mestra', 'mudou',
                     'quem responde: ' || v_at || coalesce(' (' || v_motivo || ')', ''));
  RETURN v_at;
END;
$function$
;
