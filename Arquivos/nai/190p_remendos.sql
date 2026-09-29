-- 190p -- gerado por 190_remendos.py a partir do pg_proc vivo (29/09/2026).
-- Ver o cabeçalho de 190_venda_locacao_e_filtro.sql.
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.nai_corrigir_nomes(p_texto text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_palavras text[];
  v_espacos  text[];
  v_saida    text := '';
  -- 190 (29/09): o piso subiu de 0,70 para 0,80. Com 0,70, "comodo" (6
  -- letras) virava "Coroado" (7) com 2 letras trocadas: o Sulivam escreveu
  -- "ela precisa de mais um comodo" e a Nay respondeu que no Coroado nao tinha
  -- casa. "aquarelli" -> Acquarelle e "arezo" -> Arezzo continuam (0,80 e 0,83).
  -- numeric, e nao real: com real, 1 - 0,80 dava 0,1999999 e o teto de letras
  -- erradas de "aquarelli" x Acquarelle caia de 2 para 1.
  v_piso     numeric := greatest(coalesce(nullif(nai_cfg('piso_correcao_nome', '0.80'), ''), '0.80')::numeric, 0.80);
  i          int := 1;
  n          int;
  j          int;
  v_janela   text;
  v_limpo    text;
  v_chave    text;
  v_certo    text;
  v_forca    real;
  v_folga    int;
  v_achou    boolean;
  v_troca    boolean;
BEGIN
  IF btrim(coalesce(p_texto, '')) = '' THEN RETURN p_texto; END IF;
  -- AS QUEBRAS DE LINHA FICAM (190). Antes o texto era remontado com um espaco
  -- entre as palavras, e a mensagem de tres linhas virava uma so.
  v_palavras := regexp_split_to_array(btrim(p_texto), '\s+');
  v_espacos  := ARRAY(SELECT m[1] FROM regexp_matches(btrim(p_texto), '(\s+)', 'g') AS m);
  n := coalesce(array_length(v_palavras, 1), 0);

  WHILE i <= n LOOP
    v_achou := false;
    -- JANELA GRANDE PRIMEIRO: "bom pedro" antes de "bom" e "pedro" soltos.
    FOR j IN REVERSE least(3, n - i + 1) .. 1 LOOP
      v_janela := array_to_string(v_palavras[i : i + j - 1], ' ');
      v_limpo  := btrim(regexp_replace(v_janela, '[^[:alnum:] ]', '', 'g'));
      v_chave  := lower(unaccent(v_limpo));
      CONTINUE WHEN length(regexp_replace(v_chave, '[^a-z0-9]', '', 'g')) < 5;
      CONTINUE WHEN j = 1 AND nai_palavra_comum(v_limpo);
      -- PALAVRA DE GENTE NAO E NOME ESCRITO ERRADO (190). O que aparece em 5 ou
      -- mais mensagens recebidas (`nai_palavra_conhecida`) e palavra que o
      -- pessoal usa: "dentro" virava Centro, "vista" virava Vistas, "portal"
      -- virava Portugal, "terreno" virava Estilo. O nome escrito errado e raro
      -- e cada um erra de um jeito.
      CONTINUE WHEN j = 1 AND EXISTS (SELECT 1 FROM nai_palavra_conhecida p
                                       WHERE p.palavra = v_chave AND p.mensagens >= 5);
      -- NOME PROPRIO NAO COMECA NEM TERMINA EM CONECTIVO. Sem esta linha,
      -- "na ponta negrra" (3 palavras) casava com o condominio "Luar Ponta
      -- Negra" e o "na" era engolido -- quando o certo era o bairro Ponta
      -- Negra, na janela de 2.
      CONTINUE WHEN j > 1 AND (
           lower(unaccent(regexp_replace(v_palavras[i], '[^[:alnum:]]', '', 'g'))) = ANY (ARRAY[
             'na','no','em','de','da','do','das','dos','a','o','as','os','um','uma','uns','umas',
             'para','pra','com','sem','por','pelo','pela','e','ou','que','se','ai','aqui','la',
             'ta','to','meu','minha','seu','sua','esse','essa','este','esta','tem','quero'])
        OR lower(unaccent(regexp_replace(v_palavras[i + j - 1], '[^[:alnum:]]', '', 'g'))) = ANY (ARRAY[
             'na','no','em','de','da','do','das','dos','a','o','as','os','um','uma','uns','umas',
             'para','pra','com','sem','por','pelo','pela','e','ou','que','se']));

      -- QUANTAS LETRAS PODEM ESTAR ERRADAS, no maximo. Sai do piso. O TETO DA
      -- BUSCA e folgado de proposito: a conta final compara com o MAIOR dos dois
      -- nomes, entao "aquareli" (8) x "Acquarelle" (10) aceita 2 letras erradas.
      v_folga := floor((1.0 - v_piso) * (length(v_chave) + 4))::int + 1;

      -- CUIDADO COM O `less_equal`: quando a distancia passa do teto, ele NAO
      -- devolve a distancia -- devolve um numero maior que o teto. Por isso a
      -- linha `WHERE x.d <= ...`: so vale quem ficou DENTRO do teto de verdade.
      SELECT x.nome, x.forca INTO v_certo, v_forca FROM (
        SELECT v.nome, v.tamanho,
               levenshtein_less_equal(v.chave, v_chave, v_folga) AS d,
               1.0 - levenshtein_less_equal(v.chave, v_chave, v_folga)::real
                     / greatest(v.tamanho, length(v_chave), 1) AS forca
          FROM mv_vocabulario_nomes v
         WHERE v.palavras = j
           AND v.tamanho BETWEEN length(v_chave) - v_folga AND length(v_chave) + v_folga
        ) x
       WHERE x.d <= floor((1.0 - v_piso) * greatest(x.tamanho, length(v_chave), 1))
       ORDER BY x.forca DESC LIMIT 1;

      -- NA JANELA DE VARIAS PALAVRAS, a palavra conhecida so troca por uma
      -- letra (190): "Bom Pedro" -> Dom Pedro e "Living Confort" -> Living
      -- Comfort continuam; "luar ponta negra" -> Life Ponta Negra nao.
      -- (o 0,0001 e do arredondamento: 1 - 2/10 em double fica abaixo de 0,80 em real)
      v_troca := v_certo IS NOT NULL AND v_forca >= v_piso - 0.0001;
      IF v_troca AND j > 1 THEN
        v_troca := NOT EXISTS (
          SELECT 1
            FROM unnest(regexp_split_to_array(v_chave, '\s+'), regexp_split_to_array(lower(unaccent(v_certo)), '\s+')) AS w(dito, certo)
           WHERE w.dito IS DISTINCT FROM w.certo
             AND levenshtein(coalesce(w.dito, ''), coalesce(w.certo, '')) > 1
             AND EXISTS (SELECT 1 FROM nai_palavra_conhecida p
                          WHERE p.palavra = w.dito AND p.mensagens >= 5));
      END IF;

      IF v_troca THEN
        IF v_chave = lower(unaccent(v_certo)) THEN
          v_saida := v_saida || array_to_string(v_palavras[i : i + j - 1], ' ');
        ELSE
          -- a pontuacao do fim da janela volta junto ("dom pedro," fica com a virgula)
          v_saida := v_saida || v_certo || coalesce((regexp_match(v_palavras[i + j - 1], '([^[:alnum:]]+)$'))[1], '');
        END IF;
        v_saida := v_saida || coalesce(v_espacos[i + j - 1], '');
        i := i + j;
        v_achou := true;
        EXIT;
      END IF;
    END LOOP;

    IF NOT v_achou THEN
      v_saida := v_saida || v_palavras[i] || coalesce(v_espacos[i], '');
      i := i + 1;
    END IF;
  END LOOP;

  RETURN v_saida;
END;
$function$;

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

CREATE OR REPLACE FUNCTION public.nai_conferir_resposta(p_turno bigint, p_texto text, p_codigos jsonb, p_escreveu text, p_fotos_site jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  t        nai_turno;
  k        nai_contato;
  v_texto  text := btrim(coalesce(p_texto, ''));
  v_guarda text;
  v_alvo   int;
  v_cods   int[];
  v_sem    int[] := '{}';
  v_gate   boolean := false;
  v_sugerir boolean := false;
  v_base   text;
  v_novo   text;
  v_corretor boolean;
  v_calada boolean;
  c_ok     int;
  c_card   text;
  v_n      int;
  v_ident  boolean := false;
  v_cands  int[];
  v_fichas text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN jsonb_build_object('acao', 'parou', 'motivo', 'turno_inexistente'); END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  v_corretor := t.papel = 'corretor';
  v_calada := v_texto = '' OR upper(v_texto) ~ '^\W*SIL[EÊ]NCIO\W*$';

  -- 00p ------------------------------------------ PARCERIA (Tel, 28/09/2026)
  -- "Quando o corretor perguntar se aceitamos parceria, ela dizer 'Sim,
  -- aceitamos parceria em todos os nossos imoveis o que precisar pode contar
  -- com a gente'". Vem antes da secretaria de proposito: seja quem for que
  -- respondeu, a frase sai igual. Mensagem so de parceria = so a frase; com
  -- outro assunto junto, a frase vai na frente da resposta dela.
  IF t.papel = 'corretor' AND nai_pergunta_parceria(coalesce(p_escreveu, ''))
     AND v_texto !~* 'aceitamos parceria' THEN
    v_texto := nai_cfg('resposta_parceria', 'Sim, aceitamos parceria em todos os nossos imóveis, o que precisar pode contar com a gente!')
               || CASE WHEN v_calada OR nai_so_parceria(coalesce(p_escreveu, '')) THEN ''
                       ELSE E'\n\n' || v_texto END;
    PERFORM nai_anotar(p_turno, 0, 'parceria', 'mudou', 'resposta fixa de parceria');
    IF v_calada OR nai_so_parceria(coalesce(p_escreveu, '')) THEN
      RETURN jsonb_build_object('acao', 'responder', 'texto', v_texto, 'guarda', 'parceria', 'codigo', NULL);
    END IF;
    v_calada := false;
  END IF;

  -- 00 ------------------------------------------- A SECRETARIA (99)
  -- Turno da secretaria nao passa pelas guardas de locacao: elas cobram card,
  -- código e consulta à base, que é o fluxo da outra. Aqui vale o silêncio
  -- quando não há o que dizer, e nada mais.
  IF t.atendente = 'secretaria' THEN
    IF v_calada THEN
      RETURN jsonb_build_object('acao', 'silencio', 'guarda', 'secretaria_calada');
    END IF;
    RETURN jsonb_build_object('acao', 'responder', 'texto', v_texto,
                              'guarda', 'secretaria', 'codigo', NULL);
  END IF;

  -- 01 -------------------------------------------------- DE QUAL IMÓVEL É
  -- O código do turno (card marcado, card da resposta, o que ele escreveu) e,
  -- faltando esse, o imóvel da CONVERSA. O turno guarda o que achou: é o fio
  -- para a mensagem seguinte ("me manda as fotos dele").
  SELECT CASE WHEN count(DISTINCT x) = 1 THEN min(x)::int END INTO v_alvo
    FROM jsonb_array_elements_text(coalesce(p_codigos, '[]'::jsonb)) x WHERE x ~ '^[0-9]{3,5}$' AND x::int > 0;
  IF v_alvo IS NULL THEN v_alvo := nai_imovel_da_conversa(t.contato_id, p_escreveu); END IF;
  IF v_alvo IS NOT NULL THEN
    UPDATE nai_turno SET codigo = v_alvo WHERE id = p_turno AND codigo IS DISTINCT FROM v_alvo;
  END IF;
  PERFORM nai_anotar(p_turno, 1, 'imovel_da_conversa',
                     CASE WHEN v_alvo IS NULL THEN 'passou' ELSE 'mudou' END,
                     coalesce('imóvel ' || v_alvo, 'nenhum imóvel identificado'));

  -- 02 ------------------------------------------- FOTOS LIDAS NO SITE (camada 2)
  v_n := nai_gravar_fotos_do_site(p_fotos_site);
  PERFORM nai_anotar(p_turno, 2, 'fotos_do_site', CASE WHEN v_n > 0 THEN 'mudou' ELSE 'passou' END,
                     CASE WHEN v_n > 0 THEN v_n || ' fotos gravadas do anúncio' END);

  -- 02a ------------------------- LINK DE CATÁLOGO NÃO DIZ QUAL IMÓVEL É (111)
  -- Sem código na conversa, qualquer imóvel que ela mandasse aqui seria
  -- chute. O Tel recebe o link e responde; ela diz que recebeu, e não cala.
  IF t.papel = 'corretor' AND v_alvo IS NULL
     AND nai_e_link_de_produto(coalesce(p_escreveu, '')) THEN
    v_base := nai_escalar_link_de_catalogo(p_turno, p_escreveu);
    PERFORM nai_anotar(p_turno, 2, 'link_de_catalogo', 'mudou',
                       'link de produto sem código: subiu ao Tel');
    RETURN jsonb_build_object('acao', 'responder', 'texto', v_base,
                              'guarda', 'link_de_catalogo', 'codigo', NULL);
  END IF;

  -- 02b ------------------------------------------ ELA NÃO FAZ CADASTRO (97)
  -- Oferta de imóvel dele é pergunta para o Tel. Tem que ser AQUI, antes de
  -- tudo: o card e as fotos só são enfileirados depois que esta função
  -- devolve 'responder'. O Tel e o Fernando ficam de fora pelo papel.
  IF t.papel IN ('corretor', 'proprietario')
     AND NOT nai_secretaria_ligada()
     AND nai_oferece_imovel(coalesce(p_escreveu, '')) THEN
    PERFORM nai_escalar_cadastro(p_turno, p_escreveu);
    PERFORM nai_anotar(p_turno, 2, 'oferta_de_imovel', 'parou',
                       'ofereceu imóvel: subiu ao Tel e parou o chat');
    RETURN jsonb_build_object('acao', 'parou', 'guarda', 'oferta_de_imovel_foi_ao_tel');
  END IF;

  -- 03 --------------------------------- PERGUNTA SEM RESPOSTA / PROMESSA DE RETORNO
  -- Não existe "vou ver e te aviso": ou responde com a base, ou o Tel responde.
  IF v_corretor AND NOT (coalesce(t.ferramentas, '{}') && ARRAY['escalar', 'visita']::text[])
     AND ((v_calada AND coalesce(p_escreveu, '') ~ '\?') OR v_texto ~* nai_re_promessa()) THEN
    v_base := nai_escalar_calado(p_turno, p_escreveu,
      CASE WHEN v_texto ~* nai_re_promessa() THEN 'prometeu retorno' ELSE 'pergunta sem resposta' END, v_alvo);
    IF v_base IS NULL THEN
      PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'parou', 'subiu ao Tel e parou o chat');
      RETURN jsonb_build_object('acao', 'parou', 'guarda', 'sem_resposta_foi_ao_tel');
    END IF;
    v_texto := v_base; v_calada := false; v_guarda := 'respondido_pela_base';
    PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'mudou', 'a ficha respondeu no lugar');
  ELSIF v_corretor AND 'escalar' = ANY (coalesce(t.ferramentas, '{}')) AND v_texto ~* nai_re_promessa() THEN
    PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'cortou', 'já escalou neste turno: promessa cortada');
    RETURN jsonb_build_object('acao', 'silencio', 'guarda', 'promessa_cortada');
  ELSE
    PERFORM nai_anotar(p_turno, 3, 'promessa_ou_sem_resposta', 'passou', NULL);
  END IF;

  -- 04 ----------------------------------------------- RESPOSTA SEM CONSULTA
  -- Afirmou sobre imóvel sem ter chamado ferramenta nenhuma.
  IF v_corretor AND '_lidas' = ANY (coalesce(t.ferramentas, '{}'))
     AND coalesce(array_length(array_remove(t.ferramentas, '_lidas'), 1), 0) = 0
     AND NOT v_calada
     AND v_texto !~ '\?\s*\S{0,3}\s*$'
     AND (coalesce(p_escreveu, '') ~ '\?' OR coalesce(p_escreveu, '') ~ '\m\d{3,5}\M')
     AND (coalesce(p_escreveu, '') || ' ' || v_texto) ~* nai_re_assunto_imovel()
     AND v_guarda IS DISTINCT FROM 'respondido_pela_base' THEN
    v_base := nai_escalar_calado(p_turno, p_escreveu, 'respondeu sem consultar a base', v_alvo);
    IF v_base IS NULL THEN
      PERFORM nai_anotar(p_turno, 4, 'resposta_sem_consulta', 'parou', 'afirmou sem ferramenta: subiu ao Tel');
      RETURN jsonb_build_object('acao', 'parou', 'guarda', 'resposta_sem_consulta_foi_ao_tel');
    END IF;
    v_texto := v_base; v_guarda := 'respondido_pela_base';
    PERFORM nai_anotar(p_turno, 4, 'resposta_sem_consulta', 'mudou', 'trocada pela resposta da ficha');
  ELSE
    PERFORM nai_anotar(p_turno, 4, 'resposta_sem_consulta', 'passou', NULL);
  END IF;

  -- 05 ------------------------------------------- O FORMATO É DO TEL, NÃO DO MODELO
  -- 190: a resposta da BUSCA nao vira a ficha de um imovel. Em 29/09 a lista
  -- de locacao virou "Sim! Tem 4 quartos..." do 5748, de venda.
  IF v_corretor AND v_alvo IS NOT NULL AND coalesce(p_escreveu, '') ~ '\?'
     AND v_texto !~* 'c[óo]digo:'
     AND NOT ('buscar_por_perfil' = ANY (coalesce(t.ferramentas, '{}')))
     AND NOT (coalesce(t.ferramentas, '{}') && ARRAY['escalar', 'visita']::text[]) THEN
    v_base := nai_resposta_da_base(v_alvo, p_escreveu);
    IF v_base IS NOT NULL AND v_texto IS DISTINCT FROM v_base THEN
      v_texto := v_base; v_calada := false;
      v_guarda := coalesce(v_guarda || '+', '') || 'formato_da_base';
      PERFORM nai_anotar(p_turno, 5, 'formato_da_base', 'mudou', 'resposta da ficha, no formato dele');
    ELSE
      PERFORM nai_anotar(p_turno, 5, 'formato_da_base', 'passou', NULL);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 5, 'formato_da_base', 'passou', NULL);
  END IF;

  -- 06 ------------------------------------------------------------- SILÊNCIO
  IF v_texto = '' OR upper(v_texto) ~ '^\W*SIL[EÊ]NCIO\W*$' THEN
    PERFORM nai_anotar(p_turno, 6, 'silencio', 'parou', 'ela não responde nada, de propósito');
    RETURN jsonb_build_object('acao', 'silencio', 'guarda', v_guarda);
  END IF;
  PERFORM nai_anotar(p_turno, 6, 'silencio', 'passou', NULL);

  -- 07 ---------------------------------------------------- A VOZ DE CADA PAPEL
  IF t.papel IN ('proprietario', 'motoboy') THEN
    v_novo := nai_sem_emoji(v_texto);
    PERFORM nai_anotar(p_turno, 7, 'voz_sem_emoji', CASE WHEN v_novo <> v_texto THEN 'mudou' ELSE 'passou' END,
                       'proprietário e ' || nai_acompanhante() || ': voz da captação');
    v_texto := v_novo;
  ELSE
    PERFORM nai_anotar(p_turno, 7, 'voz_sem_emoji', 'passou', NULL);
  END IF;

  -- 08 ------------------------------------------ SUGERIR VISITA (uma vez por dia)
  IF v_corretor AND v_texto !~ '\?'
     AND (v_guarda LIKE '%respondido_pela_base%' OR v_guarda LIKE '%formato_da_base%' OR v_texto ~* '^\s*sobre isso:'
          OR coalesce(t.ferramentas, '{}') && ARRAY['o_que_sei_do_imovel', 'imovel_por_codigo',
                                                    'disponibilidade_no_condominio', 'listar_no_condominio',
                                                    'resumo_do_condominio']::text[])
     AND NOT (coalesce(t.ferramentas, '{}') && ARRAY['escalar', 'visita']::text[])
     AND v_texto !~* nai_re_sugere_visita()
     AND coalesce((k.visita_sugerida_em AT TIME ZONE 'America/Manaus')::date, date '1900-01-01')
         <> (now() AT TIME ZONE 'America/Manaus')::date
     AND NOT EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = k.id AND nai_visita_aberta(x.estado)) THEN
    v_sugerir := true;
    PERFORM nai_anotar(p_turno, 8, 'sugerir_visita', 'mudou', 'sai em outra mensagem, depois da resposta');
  ELSE
    PERFORM nai_anotar(p_turno, 8, 'sugerir_visita', 'passou', NULL);
  END IF;

  -- 09 ------------------------------------------ SUGESTÃO REPETIDA NO MESMO DIA
  IF v_corretor AND v_texto ~* nai_re_sugere_visita()
     AND NOT coalesce(nay_pede_visita(coalesce(p_escreveu, '')), false)
     AND NOT EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = k.id AND x.estado IN ('coletando', 'negociando')) THEN
    IF (k.visita_sugerida_em AT TIME ZONE 'America/Manaus')::date = (now() AT TIME ZONE 'America/Manaus')::date THEN
      v_texto := btrim(regexp_replace(v_texto, '(\m(e|se)\s+)?' || nai_re_sugere_visita() || '[^?!\n]*[?!]?', '', 'gi'));
      v_guarda := 'visita_repetida_cortada';
      PERFORM nai_anotar(p_turno, 9, 'sugestao_repetida', 'cortou', 'já sugeriu visita hoje');
      IF v_texto = '' THEN
        RETURN jsonb_build_object('acao', 'silencio', 'guarda', v_guarda);
      END IF;
    ELSE
      UPDATE nai_contato SET visita_sugerida_em = now() WHERE id = k.id;
      PERFORM nai_anotar(p_turno, 9, 'sugestao_repetida', 'passou', 'primeira sugestão do dia, registrada');
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 9, 'sugestao_repetida', 'passou', NULL);
  END IF;

  -- 10 --------------------------------------------- NEGOU IMÓVEL QUE EXISTE
  IF v_corretor AND v_texto ~* nai_re_nega_imovel() THEN
    SELECT i.codigo INTO c_ok
      FROM unnest(coalesce(nay_codigos_citados(coalesce(p_escreveu, '')), '{}'::text[])) x
      JOIN imoveis i ON i.codigo::text = x
     WHERE x ~ '^[0-9]{3,5}$'
       AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     ORDER BY i.codigo LIMIT 1;
    IF c_ok IS NOT NULL THEN
      SELECT texto_pronto INTO c_card FROM nai_card_do_imovel(c_ok);
      IF coalesce(c_card, '') <> '' THEN
        v_texto := c_card;
        v_guarda := coalesce(v_guarda || '+', '') || 'negou_imovel_que_existe';
        PERFORM nai_anotar(p_turno, 10, 'negou_imovel_que_existe', 'mudou', 'negativa trocada pelo card do ' || c_ok);
      END IF;
    ELSE
      PERFORM nai_anotar(p_turno, 10, 'negou_imovel_que_existe', 'passou', 'negou, mas o código não é nosso ou não está no ar');
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 10, 'negou_imovel_que_existe', 'passou', NULL);
  END IF;

  -- 11 -------------------------------------- FRASE DE VISITA SEM A FERRAMENTA
  IF v_corretor AND NOT ('visita' = ANY (coalesce(t.ferramentas, '{}')))
     AND v_texto ~* nai_re_frase_de_visita() THEN
    v_texto := nai_tirar_frase(v_texto, nai_re_frase_de_visita());
    v_guarda := coalesce(v_guarda || '+', '') || 'visita_sem_ferramenta';
    PERFORM nai_avisar_tel(p_turno, NULL,
      'Tel, o corretor ' || coalesce(k.nome_completo, k.nome_whatsapp, k.telefone) ||
      ' (' || nai_fone_fmt(k.telefone) || ') falou de visita e eu não consegui resolver aqui. Ele disse: "' ||
      left(coalesce(p_escreveu, ''), 300) ||
      E'". Não respondi nada e parei de responder esse chat: quem responde é você. Para eu voltar: DEVOLVER ' || nai_fone_fmt(k.telefone) || '.',
      'visita_sem_ferramenta');
    PERFORM nai_parar_chat(k.id, 'visita que eu nao consegui tratar');
    PERFORM nai_anotar(p_turno, 11, 'visita_sem_ferramenta', 'parou', 'falou de visita sem chamar a ferramenta');
    RETURN jsonb_build_object('acao', 'parou', 'guarda', v_guarda);
  END IF;
  PERFORM nai_anotar(p_turno, 11, 'visita_sem_ferramenta', 'passou', NULL);

  -- 12 ------------------------------------------------------ CITOU O TEL
  IF t.papel IN ('corretor', 'proprietario', 'motoboy') AND v_texto ~* '\mtel\M' THEN
    v_texto := nai_tirar_frase(v_texto, '\mtel\M');
    v_guarda := coalesce(v_guarda || '+', '') || 'citou_o_tel_cortado';
    PERFORM nai_anotar(p_turno, 12, 'citou_o_tel', 'cortou', 'quem sobe para o Tel não conta para ninguém');
    IF v_texto = '' THEN
      RETURN jsonb_build_object('acao', 'silencio', 'guarda', v_guarda);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 12, 'citou_o_tel', 'passou', NULL);
  END IF;

  -- 13 --------------------------------------------- UMA PERGUNTA POR MENSAGEM
  IF v_corretor THEN
    v_novo := nai_uma_pergunta_da_sequencia(v_texto);
    IF v_novo IS NOT NULL THEN
      v_texto := v_novo;
      v_guarda := coalesce(v_guarda || '+', '') || 'sequencia_uma_pergunta';
      PERFORM nai_anotar(p_turno, 13, 'uma_pergunta_por_mensagem', 'mudou', 'juntou duas perguntas: saiu só a primeira');
    ELSE
      PERFORM nai_anotar(p_turno, 13, 'uma_pergunta_por_mensagem', 'passou', NULL);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 13, 'uma_pergunta_por_mensagem', 'passou', NULL);
  END IF;

  -- 14 ------------------------------------------------------------- MARKDOWN
  v_novo := nai_limpar_markdown(v_texto);
  PERFORM nai_anotar(p_turno, 14, 'markdown', CASE WHEN v_novo <> v_texto THEN 'mudou' ELSE 'passou' END, NULL);
  v_texto := v_novo;

  -- 14v ------------------------------------------ VISITA QUE NINGUEM PEDIU (141)
  -- Walter, 28/09 09:28: ele perguntou se o Acquarelle estava disponivel e,
  -- num turno so com "Locacao", ela respondeu "A visita do 5712 seria hoje, as
  -- 11h30?" -- sem ferramenta, sem visita nenhuma no banco. Visita com dia ou
  -- hora so sai de ferramenta ou de visita que existe.
  IF v_corretor AND v_texto ~* '\mvisita'
     AND v_texto ~* '(\m\d{1,2}\s*h\M|\m\d{1,2}h\d{2}|\m\d{1,2}:\d{2}|\mhoje\M|\mamanh)'
     AND NOT coalesce(nay_pede_visita(coalesce(p_escreveu, '')), false)
     AND NOT ('visita' = ANY (coalesce(t.ferramentas, '{}')))
     AND NOT EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = ANY (nai_contato_irmaos(t.contato_id))
                      AND nai_visita_aberta(x.estado)) THEN
    PERFORM nai_anotar(p_turno, 14, 'visita_inventada', 'parou', left(v_texto, 200));
    RETURN jsonb_build_object('acao', 'silencio', 'guarda', 'visita_inventada');
  END IF;

  -- 14i ------------------------------------------ A FICHA DE IDENTIFICACAO (141)
  -- Tel, 28/09: "ela errou na identificacao do imovel, ela perguntou o codigo
  -- para o corretor, a confirmacao deve ser um modelo tambem, manda nome do
  -- imovel, endereco e preco de aluguel ou preco de venda e o codigo no final
  -- #0000". Quando ela pergunta QUAL imovel -- citando codigo, ou pedindo o
  -- codigo a ele -- a pergunta vira a ficha de cada candidato. Sem foto: as
  -- fotos saem quando ele confirmar.
  IF v_corretor AND position('📍' IN v_texto) = 0 AND v_texto ~ '\?' THEN
    IF v_texto ~* ('(\me\s+(esse|este)\M|\mseria\s+(esse|este|o)\M|voc[eê]\s+(quer|fala|diz)[^?]{0,50}\d{3,5}'
                   || '|qual\s+(deles|desses|dos)\M|de\s+qual\s+(im[oó]vel|deles)|mais\s+informa[cç][oõ]es\s+do\s+im[oó]vel)') THEN
      SELECT coalesce(array_agg(DISTINCT x::int), '{}') INTO v_cands
        FROM unnest(coalesce(nay_codigos_citados(v_texto), '{}'::text[])) x
       WHERE x ~ '^[0-9]{3,5}$' AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = x::int);
    END IF;
    -- O QUE ELE CITOU PELO NOME ENTRA JUNTO (Magna, 28/09: "o Rio negro" -> ela
    -- escolheu o Barra do Rio Negro, de venda; era o Conquista Rio Negro de
    -- 1.900). Com os candidatos do nome, a ficha pergunta "qual deles?" em vez
    -- de afirmar o que o modelo chutou. So os que estao no mercado.
    IF v_ident IS NOT TRUE AND (coalesce(array_length(v_cands, 1), 0) > 0 OR v_texto ~* 'c[oó]digo') THEN
      SELECT coalesce(array_agg(DISTINCT c ORDER BY c), '{}') INTO v_cands
        FROM unnest(v_cands || coalesce(nai_imovel_pelo_condominio(coalesce(p_escreveu, ''), k.telefone), '{}'::int[])) c
       WHERE nai_imovel_disponivel(c) AND NOT EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = c AND coalesce(i.e_parceiro, false));
    END IF;
    IF coalesce(array_length(v_cands, 1), 0) BETWEEN 1 AND 5 THEN
      SELECT string_agg(nai_ficha_imovel(c), E'\n\n' ORDER BY c) INTO v_fichas FROM unnest(v_cands) c;
      v_texto := CASE WHEN array_length(v_cands, 1) = 1 THEN 'É este imóvel?' ELSE 'Qual deles?' END
                 || E'\n\n' || v_fichas;
      v_ident := true;
      PERFORM nai_anotar(p_turno, 14, 'ficha_de_identificacao', 'mudou', array_to_string(v_cands, ', '));
    END IF;
  END IF;

  -- 14c ------------------------------------------ ELE CONFIRMOU A VISITA (141)
  -- A camada de baixo do "sim": visita esperando a confirmacao dele, ele
  -- respondeu que sim, e o modelo nao chamou pedir_visita. O banco confirma.
  IF v_corretor AND nai_e_sim_curto(coalesce(p_escreveu, ''))
     AND NOT ('visita' = ANY (coalesce(t.ferramentas, '{}')))
     AND EXISTS (SELECT 1 FROM nai_visita x WHERE x.corretor_id = ANY (nai_contato_irmaos(t.contato_id))
                  AND x.estado = 'confirmando') THEN
    PERFORM nai_visita_corretor_confirmou(x.id, p_turno)
       FROM nai_visita x WHERE x.corretor_id = ANY (nai_contato_irmaos(t.contato_id)) AND x.estado = 'confirmando';
    PERFORM nai_anotar(p_turno, 14, 'visita_confirmada_pelo_corretor', 'mudou', 'o banco confirmou');
    RETURN jsonb_build_object('acao', 'responder', 'guarda', 'visita_confirmada_pelo_corretor', 'codigo', NULL,
                              'texto', 'Certo! Vou ver esse horário com o proprietário e já te retorno.');
  END IF;

  -- 15 ------------------------------------------- DE QUAIS IMÓVEIS SÃO AS FOTOS
  SELECT coalesce(array_agg(DISTINCT x::int), '{}') INTO v_cods
    FROM jsonb_array_elements_text(coalesce(p_codigos, '[]'::jsonb)) x
   WHERE x ~ '^[0-9]{3,5}$' AND x::int > 0;
  IF t.papel IN ('corretor', 'tel') THEN
    -- AS FOTOS VAO SEMPRE (Tel, 16/09): falou de imovel, recebe informacao e
    -- foto na mesma resposta. Antes era preciso pedir "foto" com todas as
    -- letras, e quem escrevia "me encaminha o 5717" recebia so o card.
    v_gate := coalesce(nai_deve_mandar_fotos(t.contato_id, k.telefone, coalesce(p_escreveu, '')), false);
  END IF;
  -- 190: turno da BUSCA sem card na resposta (pergunta do filtro, lista) nao
  -- manda foto do "imovel da conversa": as fotos saem quando ele escolher.
  IF v_gate AND coalesce(array_length(v_cods, 1), 0) = 0
     AND NOT ('buscar_por_perfil' = ANY (coalesce(t.ferramentas, '{}'))) THEN
    v_cods := array_remove(ARRAY[coalesce(v_alvo, nai_imovel_da_conversa(t.contato_id, p_escreveu))], NULL);
  END IF;
  -- SEM IMOVEL NAO HA FOTO. Com o portao sempre aberto, ele continuava "true"
  -- mesmo quando nao se sabe de qual imovel se fala -- e os passos seguintes
  -- tratavam a resposta como se fotos fossem sair. Medido: seis testes de
  -- formato e de sugestao de visita cairam por isso.
  IF v_gate AND coalesce(array_length(v_cods, 1), 0) = 0 THEN
    v_gate := false;
  END IF;

  -- IMOVEL INDISPONIVEL NAO LEVA FOTO (138): a resposta de situacao lista os
  -- disponiveis do mesmo condominio e pergunta qual interessa. As fotos saem
  -- quando ele escolher -- as do indisponivel, nunca (parede no gatilho).
  IF v_gate AND v_texto ~ '^Hmmm, vi aqui que o' THEN
    v_gate := false;
  END IF;
  -- 141: a ficha de identificacao espera ele confirmar; pedido de visita nao
  -- leva card nem foto na hora ("primeiro confirma se sabe qual e o imovel").
  IF v_gate AND (v_ident OR coalesce(nay_pede_visita(coalesce(p_escreveu, '')), false)) THEN
    v_gate := false;
  END IF;

  -- NAO REPETE (Tel, 16/09): "o Tel ja tinha pedido manualmente para ela mandar
  -- as fotos do arezzo, mas ela foi la e mandou novamente". O imovel cujas
  -- fotos ja sairam para esta pessoa hoje sai da lista -- as informacoes
  -- continuam indo, so as fotos e que nao se repetem.
  -- ...A NAO SER QUE ELE PECA (Tel, 22/09: "manda de novo conforme
  -- solicitado"). A trava vale para foto que ele nao pediu.
  IF v_gate AND coalesce(array_length(v_cods, 1), 0) >= 1
     AND NOT nai_pede_foto(coalesce(p_escreveu, '')) THEN
    SELECT coalesce(array_agg(c), '{}') INTO v_cods
      FROM unnest(v_cods) c
     WHERE NOT nai_fotos_ja_mandadas(t.contato_id, c, 24);
    IF coalesce(array_length(v_cods, 1), 0) = 0 THEN
      v_gate := false;
    END IF;
  END IF;

  PERFORM nai_anotar(p_turno, 15, 'portao_de_fotos', CASE WHEN v_gate THEN 'mudou' ELSE 'passou' END,
                     CASE WHEN v_gate THEN 'ele pediu foto; imóveis: ' || coalesce(array_to_string(v_cods, ', '), 'nenhum')
                          ELSE 'ele não pediu foto' END);

  -- 16 ------------------------------- NEGOU FOTO QUE EXISTE / PROMETEU A QUE NÃO
  IF v_gate AND v_texto ~* nai_re_nega_foto() AND coalesce(array_length(v_cods, 1), 0) >= 1 THEN
    SELECT count(*) INTO v_n FROM imovel_fotos WHERE codigo = v_cods[1];
    IF v_n > 0 THEN
      v_texto := regexp_replace(v_texto, '[^.?!\n]*' || nai_re_nega_foto() || '[^.?!\n]*[.?!]?', 'segue as fotos', 'i');
      v_guarda := 'negacao_corrigida';
      PERFORM nai_anotar(p_turno, 16, 'negou_foto_que_existe', 'mudou', 'a foto existe: negativa trocada');
    END IF;
  END IF;
  IF v_gate THEN
    SELECT coalesce(array_agg(c), '{}') INTO v_sem FROM unnest(v_cods) c
     WHERE NOT EXISTS (SELECT 1 FROM imovel_fotos fx WHERE fx.codigo = c);
    IF coalesce(array_length(v_sem, 1), 0) >= 1 THEN
      -- 14/09: antes esta conferência TROCAVA a frase por "as fotos desse eu vou
      -- confirmar com o Tel e já te mando" -- promessa de retorno, que o fluxo
      -- v17 proíbe ("não existe vou ver e te aviso"). Agora a frase de foto
      -- (promessa ou negativa) sai fora e o Tel é avisado; o corretor não recebe
      -- promessa nenhuma.
      v_texto := nai_tirar_frase(v_texto, nai_re_promete_foto() || '|' || nai_re_nega_foto());
      PERFORM nai_avisar_tel(p_turno, NULL,
        'Tel, o corretor ' || coalesce(k.nome_whatsapp, k.telefone) || ' pediu fotos do ' ||
        array_to_string(v_sem, ', ') || ' e não achei foto nem no banco nem no anúncio do site. Pode me mandar?',
        'foto_inexistente');
      v_guarda := coalesce(v_guarda || '+', '') || 'promessa_sem_foto';
      PERFORM nai_anotar(p_turno, 17, 'foto_que_nao_existe', 'mudou', 'imóvel sem foto: o Tel foi avisado');
    ELSE
      PERFORM nai_anotar(p_turno, 17, 'foto_que_nao_existe', 'passou', NULL);
    END IF;
  ELSE
    PERFORM nai_anotar(p_turno, 17, 'foto_que_nao_existe', 'passou', NULL);
  END IF;

  RETURN jsonb_build_object(
    'acao', 'responder',
    'texto', v_texto,
    'guarda', v_guarda,
    'alvo', v_alvo,
    'cods', to_jsonb(v_cods),
    'gate', v_gate,
    'sugerir', v_sugerir);
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_saida_validar()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_chave text;
  v record;
  t record;
  v_cod int;
  v_ja  timestamptz;
  v_ind int;
  v_fin int;   -- 190
  v_neg text;  -- 190
BEGIN
  SELECT chave INTO v_chave FROM nai_contato WHERE id = NEW.contato_id;
  IF v_chave IS NULL THEN
    RAISE EXCEPTION 'NAI saida: contato % nao existe', NEW.contato_id;
  END IF;
  -- O destino e SEMPRE a chave do contato. Quem enfileira nao escolhe.
  NEW.chave_destino := v_chave;

  -- SEM SR. E SRA. (Tel, 28/09/2026): "retire o SR e SRA das mensagens e so
  -- cita o nome do corretor, porque os nomes no BR variam muito". Aqui e a
  -- ultima parede: o tratamento vinha do nome (`nai_vocativo`), do prompt, de
  -- frase pronta de funcao e ate da dica dentro do no do n8n -- qualquer um
  -- que escape sai limpo daqui.
  IF NEW.tipo = 'texto' AND NEW.texto ~ '\mSra?\M' THEN
    NEW.texto := nai_sem_senhor(NEW.texto);
  END IF;

  IF NEW.visita_id IS NOT NULL THEN
    SELECT * INTO v FROM nai_visita WHERE id = NEW.visita_id;
  END IF;
  IF NEW.turno_id IS NOT NULL THEN
    SELECT * INTO t FROM nai_turno WHERE id = NEW.turno_id;
  END IF;

  IF NEW.papel_destino = 'turno' THEN
    -- Resposta: so para quem escreveu aquele turno.
    IF t.id IS NULL OR t.contato_id <> NEW.contato_id THEN
      RAISE EXCEPTION 'NAI saida: resposta do turno % para contato % que nao e o autor', NEW.turno_id, NEW.contato_id;
    END IF;
  ELSIF NEW.papel_destino = 'entrega' THEN
    -- O TEL FALANDO PELA NAY (Tel, 16/09): o `DEVOLVER <telefone> <resposta>`
    -- precisa mandar texto para quem NAO escreveu aquele turno -- quem escreveu
    -- foi o Tel. A trava do papel 'turno' barrava, e estava certa.
    --
    -- Entao este papel tem trava propria: so sai de um turno cujo papel e
    -- 'tel'. Sem essa exigencia, qualquer funcao poderia mandar mensagem para
    -- qualquer pessoa do cadastro, que e o tipo de porta que nao se abre.
    IF t.id IS NULL OR t.papel <> 'tel' THEN
      RAISE EXCEPTION 'NAI saida: entrega so sai de um comando do Tel (turno %)', NEW.turno_id;
    END IF;
  ELSIF NEW.papel_destino = 'corretor' THEN
    IF v.id IS NULL OR v.corretor_id <> NEW.contato_id THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o corretor da visita %', NEW.contato_id, NEW.visita_id;
    END IF;
  ELSIF NEW.papel_destino = 'proprietario' THEN
    IF v.id IS NULL OR v.proprietario_id IS DISTINCT FROM NEW.contato_id THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o proprietario da visita %', NEW.contato_id, NEW.visita_id;
    END IF;
  ELSIF NEW.papel_destino = 'motoboy' THEN
    IF v.id IS NULL OR v.motoboy_id IS DISTINCT FROM NEW.contato_id OR NOT nai_e_motoboy(v_chave) THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o acompanhante da visita %', NEW.contato_id, NEW.visita_id;
    END IF;
  ELSIF NEW.papel_destino = 'equipe' THEN
    -- 141: o pedido de aprovacao da visita (a Rayssa) -- so para a equipe.
    IF NOT nai_e_da_equipe_contato(NEW.contato_id) THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e da equipe', NEW.contato_id;
    END IF;
  ELSIF NEW.papel_destino = 'seguimento' THEN
    -- 141: o follow-up do dia seguinte -- so para quem recebeu imovel nos
    -- ultimos 3 dias (pelas duas linhas da pessoa).
    IF NOT EXISTS (SELECT 1 FROM imovel_enviado_no_dia e
                    WHERE e.chave IN (SELECT c.chave FROM nai_contato c
                                       WHERE c.id = ANY (nai_contato_irmaos(NEW.contato_id)))
                      AND e.primeiro_em > now() - interval '3 days') THEN
      RAISE EXCEPTION 'NAI saida: contato % nao recebeu imovel para ter seguimento', NEW.contato_id;
    END IF;
  ELSIF NEW.papel_destino = 'tel' THEN
    IF v_chave IS DISTINCT FROM nai_chave(nai_cfg('tel_telefone')) THEN
      RAISE EXCEPTION 'NAI saida: contato % nao e o Tel', NEW.contato_id;
    END IF;
  END IF;

  -- IMOVEL DE PARCERIA NAO SAI DAQUI (Tel, 16/09): "a Nay enviou um imovel de
  -- parceiro; esses imoveis de parceiros nao e pra enviar, quero eles em
  -- blacklist, so listados no site mas nunca enviados".
  --
  -- O QUE ACONTECEU: as 13:46 ela mandou 13 fotos do 3649 (Vitali Residencial,
  -- Alvorada) e ainda disse que estava disponivel. O card ja sabia da regra --
  -- `nai_card_do_imovel` devolve aviso de parceria e ZERO fotos --, mas as
  -- fotos saem por outro caminho, e ali ninguem perguntava de quem era o
  -- imovel.
  --
  -- ESTA E A ULTIMA PAREDE, no gatilho por onde toda saida passa: cobre o card,
  -- a foto, a lista e qualquer caminho que venha a existir. Sao 908 imoveis de
  -- parceria no catalogo, 566 deles no mercado -- a maior parte da base --,
  -- entao a regra precisa valer por baixo, nao so na boa vontade do modelo.
  --
  -- NAO LEVANTA EXCECAO: a saida e gravada como 'bloqueado', com o motivo. Fica
  -- o rastro no painel de envios, e o resto da resposta segue viva -- estourar
  -- aqui derrubaria a mensagem inteira, inclusive o que podia ser dito.
  --
  -- O TEL CONTINUA RECEBENDO: e por ele que a parceria anda.
  IF NEW.codigo IS NOT NULL
     AND NEW.papel_destino <> 'tel'
     AND EXISTS (SELECT 1 FROM imoveis i
                  WHERE i.codigo = NEW.codigo AND coalesce(i.e_parceiro, false)) THEN
    NEW.estado   := 'bloqueado';
    NEW.bloqueio := 'imovel de parceria: so no site, nunca enviado';
    RETURN NEW;
  END IF;

  -- VENDA NAO SAI EM CONVERSA DE LOCACAO, NEM O CONTRARIO (190, 29/09/2026).
  -- Pedro: "se o cara ta pedindo locacao ela deve continuar enviando locacao, a
  -- nao ser se ele peca claramente venda... ela nunca deve confundir as duas
  -- listas de imoveis sem um pedido claro do corretor". Naquele dia sairam 24
  -- fotos do 5748 (Jardim Adrianopolis, venda, R$ 2 mi) para quem tinha pedido
  -- aluguel de 7 mil na Ponta Negra de manha.
  --
  -- A conversa diz o negocio (`nai_negocio_da_conversa`: a palavra dele, o
  -- valor, e o que ele ja recebeu); o imovel diz a finalidade
  -- (`nai_finalidade_do_imovel`). Nao casou: card e foto ficam 'bloqueado'. O
  -- pedido claro passa: o codigo que ELE digitou ou colou nos ultimos 3 dias.
  -- So resposta a corretor -- o Tel, a entrega e o seguimento ficam de fora.
  IF NEW.papel_destino = 'turno' AND t.papel = 'corretor' THEN
    v_fin := NEW.codigo;
    IF v_fin IS NULL AND NEW.tipo = 'texto'
       AND position('📍' IN coalesce(NEW.texto, '')) > 0
       AND (SELECT count(*) FROM regexp_matches(NEW.texto, 'C[óo]digo:\s*\d{3,5}', 'gi')) = 1 THEN
      v_fin := (regexp_match(NEW.texto, 'C[óo]digo:\s*(\d{3,5})', 'i'))[1]::int;
    END IF;
    IF v_fin IS NOT NULL AND NOT (v_fin = ANY (nai_codigos_que_ele_digitou(NEW.contato_id))) THEN
      v_neg := nai_negocio_da_conversa(NEW.contato_id, t.texto);
      IF NOT nai_finalidade_serve(v_fin, v_neg) THEN
        NEW.estado   := 'bloqueado';
        NEW.bloqueio := 'finalidade: conversa de ' || v_neg || ', o ' || v_fin || ' e so de '
                        || coalesce(nai_finalidade_do_imovel(v_fin), '?');
        RETURN NEW;
      END IF;
    END IF;
  END IF;

  -- IMOVEL INDISPONIVEL NAO VAI (Tel, 28/09/2026): "qualquer status alem de
  -- disponivel ela diz que esta indisponivel e nem manda o card e fotos". A
  -- foto fica 'bloqueado'; o CARD vira a resposta de situacao
  -- (`nai_status_do_imovel`): diz que esta alugado/indisponivel e ja lista os
  -- disponiveis do mesmo condominio. Vale para qualquer caminho da NAI, venha
  -- do modelo, da busca ou de regra nova. O Tel continua recebendo tudo.
  IF NEW.papel_destino <> 'tel' THEN
    v_ind := NEW.codigo;
    IF v_ind IS NULL AND NEW.tipo = 'texto'
       AND position('📍' IN coalesce(NEW.texto, '')) > 0
       AND (SELECT count(*) FROM regexp_matches(NEW.texto, 'C[óo]digo:\s*\d{3,5}', 'gi')) = 1 THEN
      v_ind := (regexp_match(NEW.texto, 'C[óo]digo:\s*(\d{3,5})', 'i'))[1]::int;
    END IF;
    IF v_ind IS NOT NULL AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = v_ind)
       AND NOT nai_imovel_disponivel(v_ind) THEN
      IF NEW.tipo = 'imagem' THEN
        NEW.estado   := 'bloqueado';
        NEW.bloqueio := 'imovel indisponivel: nem card nem foto';
        RETURN NEW;
      END IF;
      NEW.texto := coalesce((SELECT s.texto_pronto FROM nai_status_do_imovel(v_ind) s), NEW.texto);
    END IF;
  END IF;

  -- UM IMOVEL POR CORRETOR POR DIA (27/09/2026): "enviar somente uma vez um
  -- imovel ao corretor por dia... isso nunca pode acontecer mais". Naquele
  -- dia o 3210 chegou TRES vezes ao 92 8110-1119 a partir de um unico pedido
  -- do Tel. Ver o cabecalho da 131.
  --
  -- Aqui pega o que sai pela NAI: a foto (que traz o codigo) e o CARD (texto
  -- com o alfinete e UM "Codigo: NNNN" -- lista com varios codigos nao e card
  -- e segue). A mesma resposta continua passando inteira: o card e as fotos
  -- sao linhas separadas do mesmo turno, e a reserva e do turno.
  --
  -- Foto repetida fica 'bloqueado', com o rastro no painel de envios. Card
  -- repetido vira a frase dizendo que ja foi e a hora -- sumir calado seria
  -- pior do que avisar.
  IF NEW.papel_destino <> 'tel' AND nai_cfg('envio_simulado', 'nao') <> 'sim' THEN
    v_cod := NEW.codigo;
    IF v_cod IS NULL AND NEW.tipo = 'texto'
       AND position('📍' IN coalesce(NEW.texto, '')) > 0
       AND (SELECT count(*) FROM regexp_matches(NEW.texto, 'C[óo]digo:\s*\d{3,5}', 'gi')) = 1 THEN
      v_cod := (regexp_match(NEW.texto, 'C[óo]digo:\s*(\d{3,5})', 'i'))[1]::int;
    END IF;
    IF v_cod IS NOT NULL THEN
      -- A MARCA E DAS FOTOS (Tel, 28/09 10h): "essa regra de nao mandar as fotos
      -- deve ser linkada ao codigo do imovel, ela manda as fotos baseada no
      -- codigo do imovel 1 vez por cliente, hoje ela ta mandando so o card".
      -- Ate aqui o CARD tambem marcava: um card que saiu sem foto (lista com
      -- "qual deles?") travava as fotos do imovel por 24h -- em 28/09 o 5717 e
      -- o 5737 foram pedidos com foto e sairam so com o card. Agora so a FOTO
      -- reserva; o card so CONSULTA -- e vira "ja te mandei" apenas quando as
      -- fotos daquele codigo ja foram para essa pessoa.
      v_ja := CASE WHEN NEW.tipo = 'imagem'
                   THEN nay_reservar_imovel_do_dia(v_chave, v_cod, 'nai', NEW.turno_id)
                   ELSE nay_imovel_ja_foi_24h(v_chave, v_cod, NEW.turno_id) END;
      IF v_ja IS NOT NULL THEN
        IF NEW.tipo = 'imagem' THEN
          NEW.estado   := 'bloqueado';
          NEW.bloqueio := 'imovel ja enviado a este corretor nas ultimas 24h ('
                          || nay_quando_foi(v_ja) || ')';
          RETURN NEW;
        END IF;
        NEW.texto := 'O ' || v_cod || ' eu já mandei ' || nay_quando_foi(v_ja)
                     || ', está aqui em cima na conversa.';
      END IF;
    END IF;
  END IF;

  IF NEW.tipo = 'imagem' THEN
    -- Foto so para corretor, e so a foto que o banco diz ser DAQUELE imovel.
    -- 'entrega' (135): o card pedido pela equipe vai com as fotos. O papel so
    -- sai de turno de comando (papel 'tel'), conferido la em cima.
    IF NEW.papel_destino NOT IN ('turno', 'corretor', 'entrega')
       OR (NEW.papel_destino = 'turno' AND t.papel NOT IN ('corretor', 'tel')) THEN
      RAISE EXCEPTION 'NAI saida: foto so vai para corretor';
    END IF;
    -- A COLAGEM conta como imagem daquele imovel (Tel, 12/09): ela e nossa,
    -- montada das 4 primeiras fotos, e mora em `imovel_colagem`, nao em
    -- `imovel_fotos`. O resto da parede continua igual: url que nao esteja
    -- num dos dois lugares nao sai.
    IF NOT EXISTS (SELECT 1 FROM imovel_fotos f WHERE f.codigo = NEW.codigo AND f.url = NEW.imagem_url)
       AND NOT EXISTS (SELECT 1 FROM imovel_colagem c WHERE c.codigo = NEW.codigo AND c.url = NEW.imagem_url) THEN
      RAISE EXCEPTION 'NAI saida: a foto % nao e do imovel %', NEW.imagem_url, NEW.codigo;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_buscar_por_perfil(p_turno bigint, p_bairro text, p_teto text, p_quartos text, p_mobilia text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  t        nai_turno;
  k        nai_contato;
  b        record;
  v_teto   numeric := coalesce(nay_maior_valor(p_teto), nay_valor_em_reais(p_teto));
  v_q      int := NULLIF(regexp_replace(coalesce(p_quartos, ''), '[^0-9]', '', 'g'), '')::int;
  v_mob    text := lower(unaccent(btrim(coalesce(p_mobilia, ''))));
  v_sem    boolean;
  v_com    boolean;
  v_viz    text[];
  v_alt    text;
  v_aqui   text;
  v_txt    text;
  v_nome_b text;
  v_direta boolean;   -- entrou PEDINDO imovel, sem vir de um card
  v_negocio text;     -- venda, locacao, ambos (98)
  v_tipo   text;      -- 'Casa%', 'Apartamento%' ... (98)
  v_rotulo text;
  v_nada   text;
  v_diz    text;
  v_mostra_logo boolean;   -- mostrar em vez de peneirar (100)
  v_livre  boolean;        -- procurar na cidade inteira (102)
  v_perto  text;           -- o bairro parecido, quando ele escreve outro (105)
  v_sem_valor  boolean;    -- 146: o cliente nao disse o valor
  v_tem_filtro boolean;    -- 146: ja da para listar
  v_tanto_faz  boolean;    -- 152: "tanto faz" casa ou apartamento
  v_falta      text[];     -- 146: os filtros que ainda da para oferecer
  v_falta_valor  boolean;  -- 190
  v_falta_regiao boolean;  -- 190
  v_abertura     boolean;  -- 190
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  -- POR ONDE ELE ENTROU (Tel, 15/09: "ou a pessoa vem pelo grupo ou a pessoa
  -- manda msg pedindo imoveis especificos"). Nao precisa de marca nova: quem
  -- veio do grupo tem um imovel na conversa -- o card que colou, o codigo que
  -- escreveu, a foto que pediu. Quem chegou perguntando "tem apartamento de 2
  -- quartos?" nao tem nenhum.
  -- O texto do turno vai junto de proposito: e por ele que a funcao
  -- reconhece o card que ele acabou de colar, na PRIMEIRA mensagem --
  -- sem isso, quem cola o card e pede outras opcoes na mesma mensagem
  -- cairia no caminho de quem chegou do zero.
  v_direta := nai_imovel_da_conversa(k.id, t.texto) IS NULL;

  -- VENDA NAO E ALUGUEL, CASA NAO E APARTAMENTO (98, Tel 22/09). A sequencia
  -- de perguntas gasta tres mensagens: quando a busca roda, o texto do turno e
  -- so "700 mil". O que ele pediu no comeco esta nos turnos de tras -- por
  -- isso a leitura e da CONVERSA, e nao so desta mensagem.
  v_negocio := nai_negocio_da_conversa(k.id, concat_ws(' ', t.texto, p_teto));
  v_tipo    := nai_tipo_da_conversa(k.id, concat_ws(' ', t.texto, p_bairro));
  v_rotulo  := nai_rotulo_do_tipo(v_tipo);
  v_nada    := CASE WHEN v_rotulo IS NULL THEN 'nenhum imóvel'
                    WHEN v_rotulo IN ('casa', 'cobertura', 'sala', 'chácara') THEN 'nenhuma ' || v_rotulo
                    ELSE 'nenhum ' || v_rotulo END;
  v_diz     := CASE WHEN v_negocio = 'venda' THEN 'venda' ELSE 'locação' END;

  -- O TETO E DELE, MAS A LISTA E NOSSA (100, Tel 23/09). Ele pediu os
  -- valores, ou o que existe cabe numa mensagem: mostra, nao peneira.
  -- Com isso a sequencia de perguntas para de rodar em falso -- ela
  -- perguntou a faixa de preco TRES vezes ao Joao Luiz, que so queria ver a
  -- unica casa que temos no Nova Cidade.
  -- SEM PREFERENCIA DE BAIRRO (102, Tel 23/09). "Nao teria preferencia por
  -- bairro" nao era resposta aceita: a sequencia exigia um bairro, entao ela
  -- repetia a pergunta -- e repetiu, duas vezes, para a Deborah. Depois o
  -- modelo mandou "Manaus" como bairro e a busca antiga respondeu que NAO
  -- TRABALHAMOS COM IMOVEL EM MANAUS. A cidade nunca e bairro.
  v_livre := nai_e_a_cidade(p_bairro)
             OR nai_sem_preferencia_de_bairro(concat_ws(' ', p_bairro, t.texto));
  v_mostra_logo := nai_pede_os_valores(concat_ws(' ', t.texto, p_bairro))
                   OR nai_quantos_no_bairro(p_bairro, k.telefone, v_q, v_negocio, v_tipo)
                      BETWEEN 1 AND nai_cfg_int('limite_sem_teto', 5);
  IF v_mostra_logo THEN
    PERFORM nai_anotar(p_turno, 7, 'mostra_sem_peneirar', 'mudou',
                       'ele pediu os valores, ou o bairro tem pouca coisa');
  END IF;

  -- A SEQUENCIA DO FLUXO (cards do Tel): bairro -> faixa de preco -> mobilia,
  -- UMA PERGUNTA POR MENSAGEM. Quem manda a pergunta e esta funcao, nao o
  -- modelo: em 12/09 ele juntou duas perguntas numa mensagem so, duas vezes.
  -- Enquanto faltar resposta, ela devolve a PROXIMA pergunta e nada mais.
  -- O FILTRO DE IDENTIFICACAO (Tel, 28/09/2026): quem chegou pedindo imovel
  -- comeca pelo VALOR e depois os bairros, com a frase de abertura dele: "eu
  -- vou fazer um filtro com voce para poder te enviar as opcoes que mais podem
  -- atender a sua demanda. ate que valor o seu cliente quer? qual os bairros
  -- que atendem?". Uma pergunta por mensagem, como sempre. Quem veio do grupo
  -- segue o fluxo do site (bairro -> faixa -> mobilia), logo abaixo.
  -- 146: O FILTRO NAO TRAVA (Tel, 28/09: "a corretora disse que o cliente nao
  -- disse o valor que ele queria, entao ela deve ir para outro filtro e nao
  -- forcar a corretora a enviar o valor, ela deve perguntar regiao ou se e
  -- mobiliado ou semimobiliado... ela deveria listar os imoveis que temos e
  -- continuar perguntando depois se a corretora quer mais imoveis em outros
  -- filtros"). Com QUALQUER filtro na mao (valor, bairro, mobilia, tipo,
  -- quartos) ela LISTA -- na cidade toda se nao houver bairro -- e depois
  -- oferece os filtros que faltam. Sem filtro nenhum, pergunta um de cada vez.
  -- (Substitui a sequencia obrigatoria bairro -> faixa -> mobilia e a da 138.)
  v_sem_valor := lower(unaccent(concat_ws(' ', p_teto, t.texto))) ~
    '(nao\s+(disse|sabe|informou|falou|definiu|passou|me\s+disse)|sem\s+valor|qualquer\s+valor|tanto\s+faz|valor\s+(livre|aberto)|nao\s+tem\s+(um\s+)?valor)';
  v_tem_filtro := v_teto IS NOT NULL
               OR (nullif(btrim(coalesce(p_bairro, '')), '') IS NOT NULL AND NOT v_livre)
               OR (nullif(v_mob, '') IS NOT NULL AND v_mob !~ '(tanto faz|indiferente|qualquer)')
               OR v_tipo IS NOT NULL OR v_q IS NOT NULL;

  -- LOCACAO OU VENDA antes de listar (144), quando a conversa nao disse e o
  -- valor tambem nao diz (ate R$ 30 mil e aluguel; de R$ 100 mil para cima e venda).
  IF v_negocio IS NULL AND nai_negocio_do_pedido(k.id, concat_ws(' ', t.texto, p_teto)) IS NULL THEN
    RETURN QUERY SELECT
      CASE WHEN v_tem_filtro OR v_sem_valor THEN 'Seu cliente procura imóvel para alugar ou para comprar?'
           ELSE 'Eu vou fazer um filtro com você para poder te enviar as opções que mais podem atender a sua demanda. Seu cliente procura imóvel para alugar ou para comprar?' END::text,
      ('filtro: primeiro se e locacao ou venda. Diga SO isso. Quando ele responder, chame buscar_por_perfil '
       || 'de novo com tudo o que ele ja disse (bairro, teto, mobilia).')::text;
    RETURN;
  END IF;
  IF v_negocio IS NULL THEN
    v_negocio := nai_negocio_do_pedido(k.id, concat_ws(' ', t.texto, p_teto));
    v_diz := CASE WHEN v_negocio = 'venda' THEN 'venda' ELSE 'locação' END;
  END IF;

  -- 152: CASA OU APARTAMENTO antes de listar, quando a conversa nao disse
  -- (Tel, 28/09: "é bom pôr no filtro de identificação da Nay também perguntar
  -- se não ficou claro se é casa ou apartamento"). A Ane Cavalcante pediu "um
  -- imóvel com no mínimo 4 quartos" e recebeu uma cobertura; ela queria casa.
  -- Sem laco: "tanto faz / qualquer um / os dois" libera a lista, e quem ja
  -- ouviu a pergunta nas ultimas 24h nao ouve de novo.
  IF v_tipo IS NULL THEN
    v_tanto_faz := lower(unaccent(concat_ws(' ', t.texto, (
        SELECT string_agg(m.texto, ' ') FROM mensagens m
         WHERE nai_chave(m.telefone) IN (SELECT c.chave FROM nai_contato c WHERE c.id = ANY (nai_contato_irmaos(k.id)))
           AND m.direcao = 'recebida' AND m.criada_em > now() - interval '24 hours'))))
      ~ '(tanto faz|qualquer (um|uma|tipo|coisa|imovel)|os dois|as duas|ambos|indiferente|nao importa|nao tem preferencia|sem preferencia)';
    IF NOT v_tanto_faz AND NOT EXISTS (
         SELECT 1 FROM nai_saida s
          WHERE s.contato_id = ANY (nai_contato_irmaos(k.id)) AND s.tipo = 'texto'
            AND s.texto ILIKE '%casa ou apartamento?%' AND s.criado_em > now() - interval '24 hours') THEN
      RETURN QUERY SELECT 'Seu cliente procura casa ou apartamento?'::text,
        ('filtro: pergunte SO isso. Quando ele responder (casa, apartamento, ou que tanto faz), chame '
         || 'buscar_por_perfil de novo com tudo o que ele ja disse (bairro, teto, mobilia, quartos).')::text;
      RETURN;
    END IF;
  END IF;

  -- 190: O FILTRO VEM ANTES DE QUALQUER IMOVEL (Pedro, 29/09: "ela precisa
  -- fazer o filtro... sempre que tiver uma nova solicitacao de imoveis...
  -- primeiro fazer o filtro antes de enviar qualquer imovel"). O Sulivam pediu
  -- "casa, na media de 5mil" e a busca listou a cidade inteira sem perguntar a
  -- regiao, porque a 146 listava com QUALQUER filtro na mao. Agora a ordem e:
  -- locacao/venda (144) -> casa/apartamento (152) -> VALOR -> REGIAO, uma
  -- pergunta por mensagem. Quem veio do grupo comeca pela regiao (o fluxo do
  -- site: bairro -> faixa). A 146 continua valendo no que ela tinha de certo:
  -- "o cliente nao disse o valor" e "tanto faz o bairro" pulam a pergunta, e
  -- cada pergunta sai UMA vez por dia (`nai_filtro_ja_perguntado`) -- na
  -- segunda a busca lista com o que tiver.
  -- (Substitui o "sem filtro nenhum, pergunta um de cada vez" da 146.)
  v_falta_valor  := v_teto IS NULL AND NOT v_sem_valor AND NOT v_mostra_logo
                    AND NOT nai_filtro_ja_perguntado(k.id, 'valor');
  v_falta_regiao := nullif(btrim(coalesce(p_bairro, '')), '') IS NULL AND NOT v_livre
                    AND NOT nai_filtro_ja_perguntado(k.id, 'regiao');
  v_abertura     := NOT nai_filtro_ja_perguntado(k.id, 'abertura');
  IF v_falta_valor AND (v_direta OR NOT v_falta_regiao) THEN
    RETURN QUERY SELECT
      (CASE WHEN v_abertura
            THEN 'Eu vou fazer um filtro com você para poder te enviar as opções que mais podem atender a sua demanda. '
            ELSE '' END || 'Até que valor o seu cliente quer?')::text,
      ('filtro: diga SO essa pergunta. Se ele disser que o cliente nao disse o valor, chame buscar_por_perfil com '
       || 'teto "sem valor". Quando ele responder, chame buscar_por_perfil de novo com tudo o que ele ja disse '
       || '(bairro, teto, mobilia, quartos).')::text;
    RETURN;
  END IF;
  IF v_falta_regiao THEN
    RETURN QUERY SELECT
      (CASE WHEN v_sem_valor THEN 'Sem problema! Qual região ou bairro atende o seu cliente?'
            WHEN NOT v_direta THEN 'Eu também tenho outras opções de ' || v_diz || ', você está procurando imóveis em qual bairro?'
            ELSE 'Qual região ou bairro atende o seu cliente?' END)::text,
      ('filtro: diga SO essa pergunta. Se ele disser que tanto faz o bairro, chame buscar_por_perfil com bairro '
       || 'vazio: a lista sai da cidade toda. Quando ele responder, chame buscar_por_perfil de novo com tudo o que '
       || 'ele ja disse (bairro, teto, mobilia, quartos).')::text;
    RETURN;
  END IF;

  -- sem bairro, a lista e da cidade toda
  IF nullif(btrim(coalesce(p_bairro, '')), '') IS NULL THEN
    v_livre := true;
  END IF;

  v_sem := v_mob ~ '\m(sem|nao|vazio)\M';
  v_com := NOT v_sem AND v_mob ~ '\m(com|mobiliad|semi|modulad|planejad)';

  -- O FORMATO E DO TEL (13/09, depois do teste: "me mandou 2 imoveis de forma
  -- desformatada, quero algo assim bem formatado"). Um bloco por imovel, com o
  -- icone, o nome em negrito do WhatsApp e o codigo com #.
  SELECT string_agg(nai_bloco_oferta(z.c, v_negocio), E'\n\n' ORDER BY z.v) INTO v_aqui FROM (
    SELECT i.codigo AS c,
           CASE WHEN v_negocio = 'venda' THEN i.valor_venda
                ELSE coalesce(i.valor_aluguel, i.valor_venda) END AS v
      FROM imoveis i
     WHERE (v_livre OR nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%')
       AND nai_oferta_serve(i, k.telefone, v_teto, v_q, v_sem, v_com, v_negocio, v_tipo)
     ORDER BY 2 LIMIT 5) z;

  v_viz := CASE WHEN v_livre THEN '{}'::text[]
                ELSE nay_bairros_proximos(btrim(coalesce(p_bairro, ''))) END;
  IF coalesce(array_length(v_viz, 1), 0) > 1 THEN
    SELECT string_agg(nai_bloco_oferta(z.c, v_negocio), E'\n\n' ORDER BY z.v) INTO v_alt FROM (
      SELECT i.codigo AS c,
             CASE WHEN v_negocio = 'venda' THEN i.valor_venda
                  ELSE coalesce(i.valor_aluguel, i.valor_venda) END AS v
        FROM imoveis i
       WHERE i.bairro = ANY (v_viz)
         AND nay_normalizar_lugar(i.bairro, true) NOT LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
         AND nai_oferta_serve(i, k.telefone, v_teto, v_q, v_sem, v_com, v_negocio, v_tipo)
       ORDER BY 2 LIMIT 5) z;
  END IF;

  -- NADA AQUI NEM PERTO (105, Tel 23/09: "nao e para ocorrer esse tipo de
  -- dupla busca, se eu coloco regra e para seguir").
  --
  -- Ate aqui, quando esta busca nao achava nada, quem respondia era a busca
  -- ANTIGA -- que nao conhece tipo, nem finalidade, nem faixa de teto. Era a
  -- unica porta por onde as regras dele nao passavam, e foi por ela que
  -- sairam dois apartamentos para quem pediu casa. Agora quem responde e
  -- aqui, com as mesmas regras do resto da funcao.
  IF v_aqui IS NULL AND v_alt IS NULL THEN

    -- 146: O TIPO PEDIDO NAO TEM, O RESTO DO PERFIL TEM -> LISTA OS OUTROS
    -- ("ela deveria listar os imoveis que temos para ela"). Perguntar "quer
    -- que eu mande?" nao serve: na volta o tipo sairia da conversa de novo.
    IF v_tipo IS NOT NULL THEN
      SELECT string_agg(nai_bloco_oferta(z.c, v_negocio), E'

' ORDER BY z.v) INTO v_aqui FROM (
        SELECT i.codigo AS c,
               CASE WHEN v_negocio = 'venda' THEN i.valor_venda
                    ELSE coalesce(i.valor_aluguel, i.valor_venda) END AS v
          FROM imoveis i
         WHERE (v_livre OR nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%')
           AND nai_oferta_serve(i, k.telefone, v_teto, v_q, v_sem, v_com, v_negocio, NULL)
         ORDER BY 2 LIMIT 5) z;
      IF v_aqui IS NOT NULL THEN
        RETURN QUERY SELECT
          (initcap(coalesce(v_rotulo, 'esse tipo')) || ' nesse perfil eu não tenho no momento. Mas tenho estas opções nesse valor:'
           || E'

' || v_aqui || E'

'
           || 'Qual deles é de seu interesse? Assim, posso lhe enviar mais informações e detalhes.')::text,
          ('mande o texto_pronto EXATAMENTE como veio: cada imovel no seu bloco. NAO resuma e NAO invente imovel. '
           || 'Se ele quiser detalhe de um, chame imovel_por_codigo.')::text;
        RETURN;
      END IF;
    END IF;

    -- 1. O BAIRRO EXISTE? Pode ser so o jeito de escrever.
    IF NOT v_livre AND NOT EXISTS (
         SELECT 1 FROM imoveis i
          WHERE nay_normalizar_lugar(i.bairro, true)
                LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%') THEN

      SELECT i.bairro INTO v_perto
        FROM imoveis i
       WHERE i.bairro IS NOT NULL AND btrim(i.bairro) <> ''
       GROUP BY i.bairro
       ORDER BY similarity(lower(unaccent(i.bairro)), lower(unaccent(coalesce(p_bairro, '')))) DESC
       LIMIT 1;

      IF v_perto IS NOT NULL
         AND similarity(lower(unaccent(v_perto)), lower(unaccent(coalesce(p_bairro, '')))) >= 0.45 THEN
        RETURN QUERY SELECT
          ('Você quis dizer ' || v_perto || '?')::text,
          ('o bairro que ele escreveu nao existe no catalogo, mas parece com este. '
           || 'Confirme com ele antes de procurar.')::text;
        RETURN;
      END IF;

      RETURN QUERY SELECT
        ('Não tenho imóvel nesse bairro. Em qual outro o cliente aceita?')::text,
        ('esse bairro nao esta no catalogo. NUNCA diga que nao trabalhamos em Manaus: '
         || 'a imobiliaria e de Manaus.')::text;
      RETURN;
    END IF;

    -- 2. O BAIRRO EXISTE, mas nao ha nada no perfil pedido. Dizer isso e a
    -- resposta certa -- trocar por outro tipo ou outro negocio nao e.
    RETURN QUERY SELECT
      (CASE WHEN v_livre
            THEN 'Não tenho ' || v_nada || ' nesse perfil disponível no momento.'
            ELSE 'No ' || initcap(btrim(coalesce(p_bairro, ''))) || ' não tenho ' || v_nada
                 || ' nesse perfil, nem nos bairros aqui perto.' END
       || CASE WHEN v_teto IS NULL AND NOT v_sem_valor
               THEN ' Me diz até que valor o cliente vai, que eu procuro em toda a cidade.'
               ELSE '' END)::text,
      ('nao existe nada no perfil pedido' || coalesce(' (' || v_rotulo || ')', '')
       || '. NAO ofereca outro tipo nem outra finalidade no lugar. Pergunte outro bairro '
       || 'ou outra faixa de preco.')::text;
    RETURN;
  END IF;

  SELECT coalesce((SELECT i.bairro FROM imoveis i
                    WHERE nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
                    LIMIT 1), initcap(btrim(p_bairro))) INTO v_nome_b;

  -- AREA (Tel, 18/09): quem pediu "Vieiralves" ouve "No Vieiralves", e nao o
  -- nome oficial do bairro. A busca ja procurou em Nossa Senhora das Gracas; so
  -- o jeito de falar acompanha a pessoa.
  SELECT coalesce((SELECT a.area FROM nai_area_citada(p_bairro) a LIMIT 1), v_nome_b)
    INTO v_nome_b;

  -- UM SO, em lugar nenhum mais: vai o CARD (Tel, 22/09, caso 162). O card traz
  -- "Codigo:", e e isso que faz o sistema mandar as fotos e o fechamento.
  IF (SELECT count(*) FROM regexp_matches(coalesce(v_aqui, '') || coalesce(v_alt, ''), ' #[0-9]{3,5}\*', 'g')) = 1 THEN
    RETURN QUERY SELECT
      (SELECT cc.texto_pronto FROM nai_card_do_imovel(
         (regexp_match(coalesce(v_aqui, '') || coalesce(v_alt, ''), ' #([0-9]{3,5})\*'))[1]::int) cc),
      ('e um imovel so nesse perfil: mande o card EXATAMENTE como veio. O sistema manda as '
       || 'fotos e a sugestao de visita logo depois.')::text;
    RETURN;
  END IF;

  IF v_aqui IS NOT NULL THEN
    v_txt := CASE WHEN v_livre THEN 'Tenho estas opções:'
                  ELSE 'No ' || v_nome_b || ' eu tenho estas opções:' END
             || E'\n\n' || v_aqui;
    IF v_alt IS NOT NULL THEN
      v_txt := v_txt || E'\n\n' || 'E tenho estas aqui perto:' || E'\n\n' || v_alt;
    END IF;
  ELSE
    v_txt := 'No ' || v_nome_b || ', não tenho ' || v_nada || ' nesse perfil disponível no momento.' || E'\n\n' ||
             'Mas tenho estas opções aqui perto:' || E'\n\n' || v_alt;
  END IF;

  -- DEPOIS DE UMA LISTA, A PERGUNTA E PADRAO (Tel, 22/09, caso 159: "faltou ela
  -- perguntar De qual deles a Sra. quer mais informacoes? isso tem que ser
  -- padrao apos o envio de uma lista"). Vem daqui, e nao do prompt, para nao
  -- depender de ela lembrar.
  v_txt := v_txt || E'\n\n' || 'Qual deles é de seu interesse? Assim, posso lhe enviar mais informações e detalhes.';
  -- 146: e continua oferecendo os filtros que ainda nao foram usados
  v_falta := array_remove(ARRAY[
    CASE WHEN nullif(btrim(coalesce(p_bairro, '')), '') IS NULL THEN 'a região' END,
    CASE WHEN nullif(v_mob, '') IS NULL THEN 'se prefere mobiliado ou semimobiliado' END,
    CASE WHEN v_teto IS NULL AND NOT v_sem_valor THEN 'até que valor o cliente vai' END], NULL);
  IF coalesce(array_length(v_falta, 1), 0) > 0 THEN
    v_txt := v_txt || E'\n' || 'Se quiser mais opções, me diz ' || nai_lista_pt(v_falta) || ' que eu filtro aqui.';
  END IF;

  RETURN QUERY SELECT v_txt,
    ('mande o texto_pronto EXATAMENTE como veio: cada imovel no seu bloco, com o icone, o negrito e as linhas com •. '
     || 'NAO resuma, NAO junte tudo numa linha, NAO reescreva e NAO invente imovel que nao esta na lista. '
     || 'Se ele quiser detalhe de um, chame imovel_por_codigo. NAO sugira visita aqui.')::text;
END;
$function$;

COMMIT;

