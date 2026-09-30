CREATE OR REPLACE FUNCTION public.nai_pedido_de_perfil(p_texto text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  s        text := lower(unaccent(coalesce(p_texto, '')));
  s_lugar  text := nay_normalizar_lugar(coalesce(p_texto, ''), true);
  v_busca  boolean;
  v_teto   numeric;
  v_q      int;
  v_bairro text;
  m        text[];
BEGIN
  -- ------------------------------------------------------ o BAIRRO primeiro
  -- Vem antes porque um bairro conhecido no texto ja e, sozinho, sinal de
  -- busca: "tem algo em Ponta Negra?" nao fala a palavra "apartamento".
  -- Casa o nome inteiro; e, para nome de tres palavras ou mais, as duas
  -- primeiras -- ninguem escreve "Parque 10 de Novembro" no WhatsApp.
  SELECT b.bairro INTO v_bairro FROM (
    SELECT DISTINCT i.bairro FROM imoveis i WHERE nullif(btrim(i.bairro), '') IS NOT NULL) b
   WHERE s_lugar LIKE '%' || nay_normalizar_lugar(b.bairro, true) || '%'
      OR (array_length(string_to_array(nay_normalizar_lugar(b.bairro, true), ' '), 1) >= 3
          AND s_lugar LIKE '%' ||
              array_to_string((string_to_array(nay_normalizar_lugar(b.bairro, true), ' '))[1:2], ' ') || '%')
   ORDER BY length(b.bairro) DESC LIMIT 1;

  -- ------------------------------------------------------------ e uma BUSCA?
  -- Os parenteses em volta da concatenacao NAO sao enfeite: `~` e `||` tem a
  -- mesma precedencia no Postgres e a leitura e da esquerda para a direita,
  -- entao sem eles a regex vira so o primeiro pedaco -- e quebra.
  v_busca := s ~ ('\m(procuro|procurando|proucurando|busco|buscando|preciso de|precisa de|'
                 || 'teria|tem algum|tem alguma|tem algo|tem apartamento|tem apto|tem casa|tem kit|'
                 || 'voce tem|vc tem|vcs tem|voces tem|tens|quero um|quero uma|queria um|queria uma|'
                 || 'tenho cliente|meu cliente|cliente quer|cliente procura|cliente busca|'
                 -- 16/09: "Estou com uma cliente querendo algo, com modulados e
                 -- ar, ate 4.200" nao era reconhecido como busca. Quem diz
                 -- "estou com cliente" esta pedindo imovel.
                 || 'estou com cliente|estou com uma cliente|estou com um cliente|'
                 || 'cliente querendo|cliente interessad|to com cliente|tô com cliente|'
                 -- "quero com modulados e ar" -- so "quero um|quero uma" estava
                 -- aqui, e quem pede pela caracteristica ficava de fora.
                 || 'quero com|queria com|quero algo|queria algo|quero imovel|'
                 || 'to procurando|tô procurando|preciso achar|me ve|me ve algo|'
                 || 'esta procurando|estao procurando|to procurando|estou procurando)\M');

  -- ...e fala de imovel, de um filtro, ou de um bairro nosso. Sem isto, "voce
  -- tem o contato do proprietario?" entraria aqui.
  v_busca := v_busca AND (
       s ~ ('\m(apartamento|apartamentos|apto|aptos|ap|casa|casas|kitnet|kitinete|quitinete|'
           || 'studio|estudio|flat|cobertura|sala|salas|imovel|imoveis|terreno|galpao|predio)\M')
    OR s ~ '\m\d+\s*(quarto|quartos|dormitorio|dormitorios|qto|qtos)\M'
    OR s ~ 'r\$'
    OR v_bairro IS NOT NULL
  );

  -- MAS nao e busca quando ele aponta para O imovel da conversa: "esse
  -- apartamento tem garagem?" e pergunta de ficha, e continua indo para a base.
  IF s ~ '\m(desse|deste|nesse|neste|esse|este|essa|esta|dele|dela|do imovel|no imovel)\M'
     AND NOT (s ~ '\m(outro|outros|outra|outras|mais algum|mais alguma|parecido|similar)\M')
     -- 16/09: "preferencia DELA no Dom Pedro" derrubava a busca por causa do
     -- "dela" -- que ali era a cliente, nao um imovel. Quem diz um VALOR esta
     -- procurando: pergunta de ficha nao vem com preco dentro.
     AND NOT (s ~ 'r\$'
              OR s ~ '\m[0-9][0-9.,]*\s*(mil|k)\M'
              OR s ~ ('\m(ate|no maximo|maximo de|em torno de|faixa de)'
                   || '\s+[0-9][0-9.,]{2,}')) THEN
    v_busca := false;
  END IF;

  IF NOT v_busca THEN
    RETURN jsonb_build_object('e_pedido', false);
  END IF;

  -- --------------------------------------------------------------- QUARTOS
  m := regexp_match(s, '\m(\d+)\s*(quarto|quartos|dormitorio|dormitorios|qto|qtos)\M');
  IF m IS NOT NULL THEN v_q := m[1]::int; END IF;
  IF v_q IS NULL THEN
    m := regexp_match(s, '\m(um|uma|dois|duas|tres|quatro|cinco)\s+(quarto|quartos|dormitorio|dormitorios)\M');
    IF m IS NOT NULL THEN
      v_q := CASE m[1] WHEN 'um' THEN 1 WHEN 'uma' THEN 1 WHEN 'dois' THEN 2 WHEN 'duas' THEN 2
                       WHEN 'tres' THEN 3 WHEN 'quatro' THEN 4 ELSE 5 END;
    END IF;
  END IF;

  -- ------------------------------------------------------------------ TETO
  -- Em tres tentativas, da mais certa para a menos certa. O "de" solto ficou
  -- DE FORA de proposito: em "apartamento de 3 quartos" ele lia 3 como o
  -- orcamento do cliente, e foi exatamente o que aconteceu na primeira
  -- medicao. Numero colado a quarto, vaga, suite ou metro nunca e dinheiro.
  m := regexp_match(s, 'r\$\s*([\d\.,]+)\s*(mil|k)?');
  IF m IS NOT NULL THEN v_teto := nay_valor_em_reais(m[1] || coalesce(' ' || m[2], '')); END IF;
  IF v_teto IS NULL THEN
    m := regexp_match(s, '\m([\d\.,]+)\s*(mil|k)\M');
    IF m IS NOT NULL THEN v_teto := nay_valor_em_reais(m[1] || ' mil'); END IF;
  END IF;
  IF v_teto IS NULL THEN
    m := regexp_match(s, '\m(ate|por|faixa de|em torno de|no maximo|maximo de)\s+([\d\.,]{3,})\s*(reais)?'
                         '(?!\s*(quarto|quartos|dormitorio|dormitorios|vaga|vagas|suite|suites|m2|metros))');
    IF m IS NOT NULL THEN v_teto := nay_valor_em_reais(m[2]); END IF;
  END IF;

  -- ------------------------------------------------------------- MOBILIA
  -- "com modulados e ar" (Tel, 16/09): "ela pode filtrar por semi-mobiliado
  -- que esta no site, que no caso seria com modulados e ar".
  --
  -- No cadastro esses imoveis aparecem como "semi-mobiliado" e
  -- "semi-mobiliado (moveis planejados + ar)". Quem pede modulado, planejado
  -- ou ar-condicionado quer isso -- e tambem serve o mobiliado completo, que
  -- tem tudo o que o semi tem. Por isso o filtro devolvido e "com mobilia",
  -- que `nai_oferta_serve` ja entende dos dois jeitos.
  --
  -- E quem pede o contrario -- "vazio", "sem moveis" -- continua indo para o
  -- lado de la.
  DECLARE v_mob text;
  BEGIN
    -- Sem `\M` no fim de proposito: a marca de fim de palavra exigia que o
    -- texto acabasse em "mobiliad", e "mobiliado" tem um "o" depois -- entao
    -- "cliente que quer apartamento mobiliado" nao era reconhecido. O `\m` da
    -- frente basta: ele garante o comeco da palavra, e "desmobiliado" nao casa
    -- com "\mmobiliad" porque comeca em "des".
    IF s ~ '\m(vazio|sem mobilia|sem moveis|desmobiliad|nao mobiliad)' THEN
      v_mob := 'sem';
    -- Os parenteses em volta da concatenacao NAO sao enfeite: `~` e `||` tem a
    -- mesma precedencia no Postgres, entao sem eles a regex vira so o primeiro
    -- pedaco e o resto sobra solto -- foi o que estourou no primeiro teste.
    ELSIF s ~ ('\m(modulad|planejad|mobiliad|semi.?mobiliad|climatizad|'
            || 'ar.?condicionado|com ar)') THEN
      v_mob := 'com';
    END IF;

    RETURN jsonb_build_object(
      'e_pedido', true,
      'teto',    v_teto,
      'quartos', v_q,
      'mobilia', v_mob,
      'bairro',  v_bairro);
  END;
END;
$function$;
