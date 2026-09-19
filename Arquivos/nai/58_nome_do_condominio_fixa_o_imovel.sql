-- =====================================================================
-- NAI -- 58: o nome do condominio fixa o imovel da conversa (Tel, 16/09/2026)
--
-- Ele: "aqui ja era para ela enviar as fotos e ela nao enviou".
--
-- A CONVERSA (Sr. Luciano Moraes, hoje):
--   13:47  ele: "A unidade MAISON ROCHELLE, ainda esta disponivel pra locacao?"
--          Nay: "Sim! Esta disponivel. Tem 3 quartos, sendo 1 suite. Tem 2
--                banheiros. Tem 78 m2."      <- os dados do 2944, corretos
--   13:52  ele: "Poderia enviar fotos?"       <- marcando a resposta dela
--          Nay: "De qual imovel o Sr. quer as fotos? Me passa o codigo."
--   13:55  ele: "Maison Rochelle"
--          Nay: manda o card e 21 fotos
--
-- O modelo achou o imovel na primeira mensagem -- os dados que ela respondeu
-- sao do 2944. Quem nao guardou foi o SISTEMA: `nai_turno.codigo` ficou vazio
-- nos tres primeiros turnos, porque o codigo do turno so era preenchido a
-- partir de numero escrito ou card marcado. Cinco minutos depois, a conversa
-- estava sem imovel nenhum e ela teve que perguntar.
--
-- `nai_imovel_da_conversa` ja procurava o nome do condominio, mas so entre os
-- imoveis que estavam NA MESA -- card que ela mandou, codigo que ele escreveu
-- antes. Numa conversa que comeca pelo nome, a mesa esta vazia.
--
-- Agora o nome e procurado no catalogo, logo depois do codigo. So vale quando
-- aponta para UM imovel: "Maison Rochelle" tem dois cadastros, mas um so esta
-- no mercado, entao da 2944. Se desse dois, ela pergunta -- que e o certo.
--
-- Isso conserta a conversa inteira de uma vez: com o codigo gravado no
-- primeiro turno, "Poderia enviar fotos?" acha o imovel pelo turno anterior.
--
-- Gerado por `scratchpad/patch58.py` a partir do que estava NO BANCO.
-- =====================================================================

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
BEGIN
  SELECT * INTO k FROM nai_contato WHERE id = p_contato;
  IF k.id IS NULL THEN RETURN NULL; END IF;
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

  IF coalesce(array_length(v_cods, 1), 0) = 0 THEN RETURN NULL; END IF;

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
  ) y WHERE c IS NOT NULL;
  IF n = 1 THEN RETURN v_cod; END IF;

  -- 6. dois ou mais e sem nome: NULL -- ela pergunta, que é o certo.
  RETURN NULL;
END;
$function$;
