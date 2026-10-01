CREATE OR REPLACE FUNCTION public.nai_imovel_da_conversa(p_contato bigint, p_texto text)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  k       nai_contato;
  q       text := lower(unaccent(coalesce(p_texto, '')));
  v_cod   int;
  v_cods  int[];
  v_desde timestamptz;
  v_seis  timestamptz;
  v_fim8  text;
  n       int;
  v_neg   text;   -- 190
  v_dele  int[];  -- 190
BEGIN
  SELECT * INTO k FROM nai_contato WHERE id = p_contato;
  IF k.id IS NULL THEN RETURN NULL; END IF;
  -- 190: VENDA NAO E LOCACAO. O imovel da conversa sai so da finalidade da
  -- conversa -- salvo o codigo que ele mesmo digitou ou colou. Era por aqui
  -- que o 5748 (venda) virou o imovel de quem pedia aluguel no Adrianopolis.
  v_neg  := nai_negocio_da_conversa(p_contato, p_texto);
  v_dele := nai_codigos_que_ele_digitou(p_contato);
  v_fim8 := right(regexp_replace(k.telefone, '\D', '', 'g'), 8);
  v_desde := greatest(coalesce(k.zerado_em, now() - interval '48 hours'), now() - interval '48 hours');
  v_seis  := greatest(coalesce(k.zerado_em, now() - interval '6 hours'), now() - interval '6 hours');

  -- 1. o que ELE escreveu agora vale mais que tudo
  SELECT x::int INTO v_cod
    FROM unnest(coalesce(nay_codigos_citados(coalesce(p_texto, '')), '{}'::text[])) x
   WHERE x ~ '^[0-9]{3,5}$' AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = x::int)
   LIMIT 1;
  IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;

  -- 1b. O NOME DO CONDOMINIO QUE ELE ESCREVEU (Tel, 16/09). Vale tanto quanto
  -- o codigo: quem escreve "a unidade MAISON ROCHELLE ainda esta disponivel?"
  -- disse de qual imovel fala.
  --
  -- O caso: as 13:47 o Sr. Luciano perguntou isso e a Nay respondeu certo --
  -- 3 quartos, 78 m2, os dados do 2944 -- mas o TURNO ficou sem codigo, porque
  -- so o que tem numero era gravado ali. Cinco minutos depois ele pediu
  -- "Poderia enviar fotos?" e nao havia imovel nenhum na conversa: ela
  -- perguntou de qual imovel era e ele teve que escrever o nome de novo.
  --
  -- O passo 3 la embaixo ja procurava o nome, mas so entre os imoveis que
  -- estavam na mesa (card mandado, codigo escrito antes). Quando a conversa
  -- comeca pelo nome, a mesa esta vazia e ele nao tinha onde procurar.
  --
  -- So vale quando o nome aponta para UM imovel: dois no mesmo condominio e
  -- escolher por ele seria pior do que perguntar.
  IF btrim(q) <> '' THEN
    DECLARE v_pelo_nome int[];
    BEGIN
      v_pelo_nome := nai_imovel_pelo_condominio(p_texto, k.telefone);
      v_pelo_nome := ARRAY(SELECT c FROM unnest(v_pelo_nome) c WHERE nai_finalidade_serve(c, v_neg));  -- 190
      IF coalesce(array_length(v_pelo_nome, 1), 0) = 1 THEN
        RETURN v_pelo_nome[1];
      END IF;
    END;
  END IF;

  -- 2. o que esteve na mesa DESDE o marco: card que ela mandou, card que ele
  --    colou, código que ele escreveu antes, envio do publicador, e o imóvel
  --    que um turno já tratou.
  SELECT coalesce(array_agg(DISTINCT c), '{}') INTO v_cods FROM (
    SELECT s.codigo AS c FROM nai_saida s
     WHERE s.contato_id = p_contato AND s.codigo IS NOT NULL AND s.criado_em > v_desde
    UNION ALL
    SELECT (regexp_matches(s.texto, 'C[óo]digo:\s*(\d{3,5})', 'gi'))[1]::int FROM nai_saida s
     WHERE s.contato_id = p_contato AND s.texto IS NOT NULL AND s.criado_em > v_desde
    UNION ALL
    SELECT t.codigo FROM nai_turno t
     WHERE t.contato_id = p_contato AND t.codigo IS NOT NULL AND t.criado_em > v_desde
    UNION ALL
    SELECT x::int FROM mensagens m
      CROSS JOIN LATERAL unnest(coalesce(nay_codigos_citados(coalesce(m.texto, '')), '{}'::text[])) x
     WHERE right(regexp_replace(m.telefone, '\D', '', 'g'), 8) = v_fim8
       AND m.direcao = 'recebida' AND m.criada_em > v_desde AND x ~ '^[0-9]{3,5}$'
    UNION ALL
    SELECT e.codigo::int FROM envios e
     WHERE right(regexp_replace(coalesce(e.telefone, ''), '\D', '', 'g'), 8) = v_fim8
       AND e.enviado_em > v_desde AND e.codigo ~ '^[0-9]{3,5}$'
  ) y WHERE c IS NOT NULL AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = y.c);

  v_cods := ARRAY(SELECT c FROM unnest(v_cods) c WHERE nai_finalidade_serve(c, v_neg) OR c = ANY (v_dele));  -- 190
  -- 240: ELE DESCREVEU O IMÓVEL (tipo + bairro: "o apartamento da Chapada"). Só
  -- serve o que bate; sem isto valia o último imóvel da conversa, de outro tipo e
  -- outro bairro (Raquel, 30/09: a casa do Parque 10 no lugar do 9004).
  IF nai_tipo_pedido(p_texto) IS NOT NULL THEN
    DECLARE
      v_desc  jsonb := nai_imovel_pela_descricao(p_texto, k.telefone);
      v_bate  int[];
    BEGIN
      IF v_desc ? 'bairro' THEN
        v_bate := ARRAY(SELECT i.codigo FROM imoveis i
                         WHERE i.codigo = ANY (v_cods) AND i.tipo ILIKE nai_tipo_pedido(p_texto)
                           AND nay_normalizar_lugar(i.bairro, true) = nay_normalizar_lugar(v_desc->>'bairro', true));
        IF coalesce(array_length(v_bate, 1), 0) = 1 THEN
          RETURN v_bate[1];
        ELSIF coalesce(array_length(v_bate, 1), 0) >= 2 THEN
          v_cods := v_bate;
        ELSIF coalesce((v_desc->>'quantos')::int, 0) = 1 THEN
          RETURN (v_desc->'codigos'->>0)::int;     -- o único do catálogo com essa descrição
        ELSE
          RETURN NULL;                             -- descreveu outro imóvel: ela pergunta qual
        END IF;
      END IF;
    END;
  END IF;

  IF coalesce(array_length(v_cods, 1), 0) = 0 THEN RETURN NULL; END IF;

  -- 2b. 257: A PERGUNTA CITA OUTRO CONDOMÍNIO. Se o nome que ele escreveu é de
  -- um condomínio e NENHUM imóvel da mesa é desse condomínio, não há imóvel da
  -- conversa: ela pergunta de qual é. Era aqui que a taxa do Acquarelle saía
  -- como resposta da pergunta sobre o Vitta Club House (01/10, 17:48).
  IF btrim(q) <> '' THEN
    DECLARE v_outro int;
    BEGIN
      v_outro := nai_condominio_da_pergunta(p_texto);
      IF v_outro IS NOT NULL AND NOT EXISTS (
           SELECT 1 FROM imoveis i, condominios cd
            WHERE i.codigo = ANY (v_cods) AND cd.id = v_outro
              AND (i.condo_id = cd.id
                   OR nay_sem_acento(lower(btrim(coalesce(i.condominio_nome, '')))) = nay_sem_acento(lower(btrim(cd.nome))))) THEN
        RETURN NULL;
      END IF;
    END;
  END IF;

  -- 3. ele chamou pelo NOME ("me manda foto do arezzo")
  IF btrim(q) <> '' THEN
    SELECT i.codigo INTO v_cod FROM imoveis i
     WHERE i.codigo = ANY (v_cods)
       AND coalesce(nai_condominio_ok(i.condominio_nome), '') <> ''
       AND position(lower(unaccent(split_part(nai_condominio_ok(i.condominio_nome), ' ', 1))) IN q) > 0
     LIMIT 1;
    IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;
  END IF;

  -- 4. o imóvel do ÚLTIMO turno que tratou de um imóvel: é dele que ele fala
  --    quando diz "dele", "desse", "e as fotos?".
  SELECT t.codigo INTO v_cod FROM nai_turno t
   WHERE t.contato_id = p_contato AND t.codigo IS NOT NULL AND t.criado_em > v_seis
     AND (nai_finalidade_serve(t.codigo, v_neg) OR t.codigo = ANY (v_dele))  -- 190
   ORDER BY t.id DESC LIMIT 1;
  IF v_cod IS NOT NULL THEN RETURN v_cod; END IF;

  -- 5. um único imóvel na mesa desde o marco (até 6h)
  SELECT count(DISTINCT c), min(c) INTO n, v_cod FROM (
    SELECT s.codigo AS c FROM nai_saida s
     WHERE s.contato_id = p_contato AND s.codigo IS NOT NULL AND s.criado_em > v_seis
    UNION ALL
    SELECT (regexp_matches(s.texto, 'C[óo]digo:\s*(\d{3,5})', 'gi'))[1]::int FROM nai_saida s
     WHERE s.contato_id = p_contato AND s.texto IS NOT NULL AND s.criado_em > v_seis
    UNION ALL
    SELECT x::int FROM mensagens m
      CROSS JOIN LATERAL unnest(coalesce(nay_codigos_citados(coalesce(m.texto, '')), '{}'::text[])) x
     WHERE right(regexp_replace(m.telefone, '\D', '', 'g'), 8) = v_fim8
       AND m.direcao = 'recebida' AND m.criada_em > v_seis AND x ~ '^[0-9]{3,5}$'
  ) y WHERE c IS NOT NULL AND (nai_finalidade_serve(c, v_neg) OR c = ANY (v_dele));  -- 190
  IF n = 1 THEN RETURN v_cod; END IF;

  -- 6. dois ou mais e sem nome: NULL -- ela pergunta, que é o certo.
  RETURN NULL;
END;
$function$;
