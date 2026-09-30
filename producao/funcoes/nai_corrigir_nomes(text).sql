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
      -- 218: número solto na janela não é pedaço de nome ("ponta negra 2 quartos"
      -- virava "ponta negra ii quartos" e o número de quartos sumia)
      CONTINUE WHEN j > 1 AND EXISTS (SELECT 1 FROM unnest(v_palavras[i : i + j - 1]) w
                                       WHERE regexp_replace(w, '[^[:alnum:]]', '', 'g') ~ '^[0-9]+$');

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
