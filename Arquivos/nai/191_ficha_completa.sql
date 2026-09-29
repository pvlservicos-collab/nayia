-- 191 -- a Nay lê a ficha inteira antes de falar do imóvel (29/09/2026).
--
-- O CASO. O Paulo perguntou do Living Comfort (5664). A Nay: "A casa 1360
-- aceita pagamento à vista ou financiado. Já o Living Comfort 5664 é somente à
-- vista." Depois ele repetiu o que ela disse e ela confirmou: "O Living Comfort
-- é somente à vista mesmo." O anúncio diz "Aceita Financiamento? Sim". No banco
-- dela o 5664 não tinha descrição, características nem os campos do site -- ela
-- inventou.
--
-- Pedro: "precisamos fazer com que ela leia toda ficha do imóvel quando tiver
-- uma pergunta dessa, tudo fique disponível de maneira arquitetada dentro do
-- sistema, como um rag... para ela não responder essas coisas sensíveis assim
-- sem saber, e se não tiver lá claro, ela vai perguntar ao Tel e não informar
-- algo assim de forma errada, o card precisa ser ajustado, faça isso em todos
-- os imóveis".
--
-- AS CAMADAS
--   dado     `imovel_ficha` (191a), lida do anúncio a cada 3 h por
--            ficha_do_anuncio.py: todos os campos (inclusive os escondidos em
--            comentário), características do imóvel e do condomínio,
--            descrição, observações e o card dos grupos.
--   consulta `nai_ficha_valor(codigo, chave)` -- a ficha do anúncio, depois o
--            `extras` do site antigo; `nai_ficha_completa(codigo)` -- o
--            documento inteiro, organizado, que a ferramenta entrega ao modelo.
--   resposta `nai_resposta_da_base` (191p) responde financiamento/à vista,
--            FGTS, permuta, garantia, taxa, IPTU, incluso e escada PELA FICHA.
--   ferramenta `nai_o_que_sei_do_imovel` (191p): assunto sensível
--            (`nai_assunto_sensivel`) que a ficha não responde -> escalar ao
--            Tel, nunca supor; o resto -> a ficha inteira para o modelo ler.
--   parede   `nai_conferir_pagamento` na conferência (191p, etapa 05p): frase
--            da resposta que afirma forma de pagamento é conferida com a
--            ficha. Contradiz -> vira a frase certa. Ficha não diz -> sai, e o
--            Tel é chamado (`nai_escalar_calado`).
--   card     `nai_card_do_imovel` (191p) usa o card dos grupos lido na ficha,
--            enquanto ele for de hoje e bater o preço com o banco.

BEGIN;
SET LOCAL lock_timeout = '5s';

-- ------------------------------------------------------------- CONSULTA
CREATE OR REPLACE FUNCTION nai_ficha_valor(p_codigo int, p_chave text)
RETURNS text LANGUAGE sql STABLE AS $$
  -- A chave é o rótulo do anúncio normalizado (minúscula, sem acento, sem
  -- "?"): 'aceita financiamento', 'aceita permuta', 'incluso no aluguel',
  -- 'garantia de aluguel', 'taxa de condominio', 'iptu', 'lances de escada'.
  -- É a mesma forma das chaves de `imoveis.extras` (site antigo). O anúncio de
  -- hoje manda; o `extras` só completa.
  SELECT coalesce(
    nullif(btrim((SELECT f.campos->>p_chave FROM imovel_ficha f
                   WHERE f.codigo = p_codigo AND f.encontrado AND f.lido_em IS NOT NULL)), ''),
    nullif(btrim((SELECT i.extras->>p_chave FROM imoveis i WHERE i.codigo = p_codigo)), ''));
$$;

CREATE OR REPLACE FUNCTION nai_ficha_texto_livre(p_codigo int)
RETURNS text LANGUAGE sql STABLE AS $$
  -- Descrição + observações, do banco ou do anúncio, SEM número de unidade
  -- (`nay_descricao_segura`, a mesma raspagem de sempre).
  SELECT nullif(btrim(concat_ws(E'\n',
           nay_descricao_segura(coalesce(nullif(btrim(i.descricao), ''), f.descricao)),
           nay_descricao_segura(f.observacoes))), '')
    FROM imoveis i LEFT JOIN imovel_ficha f ON f.codigo = i.codigo AND f.encontrado
   WHERE i.codigo = p_codigo;
$$;

CREATE OR REPLACE FUNCTION nai_ficha_caracteristicas(p_codigo int)
RETURNS text[] LANGUAGE sql STABLE AS $$
  SELECT coalesce(array_agg(DISTINCT btrim(c)) FILTER (WHERE btrim(c) <> ''), '{}')
    FROM imoveis i
    LEFT JOIN imovel_ficha f ON f.codigo = i.codigo AND f.encontrado
    CROSS JOIN LATERAL unnest(
      coalesce(i.caracteristicas, '{}')
      || coalesce(string_to_array(i.extras->>'caracteristicas', ','), '{}')
      || coalesce(f.caracteristicas_imovel, '{}')
      || coalesce(f.caracteristicas_condominio, '{}')) c
   WHERE i.codigo = p_codigo;
$$;

CREATE OR REPLACE FUNCTION nai_ficha_completa(p_codigo int)
RETURNS text LANGUAGE plpgsql STABLE AS $$
DECLARE
  i imoveis;
  f imovel_ficha;
  v text[] := '{}';
  x text;
  fmt text := 'FM999G999G990';
BEGIN
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.codigo IS NULL OR coalesce(i.e_parceiro, false) THEN RETURN NULL; END IF;
  SELECT * INTO f FROM imovel_ficha WHERE codigo = p_codigo AND encontrado;

  v := v || ('FICHA DO IMÓVEL ' || i.codigo || ' — ' || concat_ws(' · ', nullif(nai_condominio_ok(i.condominio_nome), ''),
             i.tipo, i.bairro));
  v := v || ('SITUAÇÃO: ' || CASE WHEN nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
                                  THEN 'disponível' ELSE 'NÃO está disponível' END);
  v := v || ('VALORES: ' || concat_ws(' | ',
             CASE WHEN coalesce(i.valor_venda, 0) > 0 THEN 'venda R$ ' || replace(to_char(i.valor_venda, fmt), ',', '.') END,
             CASE WHEN coalesce(i.valor_aluguel, 0) > 0 THEN 'aluguel R$ ' || replace(to_char(i.valor_aluguel, fmt), ',', '.') END));
  v := v || ('PAGAMENTO: ' || concat_ws(' | ',
             'aceita financiamento: ' || coalesce(nai_ficha_valor(p_codigo, 'aceita financiamento'), 'NÃO INFORMADO'),
             'aceita permuta: ' || coalesce(nai_ficha_valor(p_codigo, 'aceita permuta'), 'NÃO INFORMADO')
               || coalesce(' (' || nai_ficha_valor(p_codigo, 'permuta') || ')', ''),
             CASE WHEN coalesce(nai_ficha_texto_livre(p_codigo), '') ~* 'fgts' THEN 'FGTS: o anúncio cita (ver descrição)'
                  ELSE 'FGTS: NÃO INFORMADO' END));
  v := v || ('TAXAS: ' || concat_ws(' | ',
             'condomínio: ' || coalesce(CASE WHEN coalesce(i.taxa_condominio, 0) > 0
                                             THEN 'R$ ' || replace(to_char(i.taxa_condominio, fmt), ',', '.') END,
                                        nai_ficha_valor(p_codigo, 'taxa de condominio'), 'não informado'),
             'IPTU: ' || coalesce(CASE WHEN coalesce(i.iptu, 0) > 0 THEN 'R$ ' || replace(to_char(i.iptu, fmt), ',', '.') END,
                                  nai_ficha_valor(p_codigo, 'iptu'), 'não informado'),
             'incluso no aluguel: ' || coalesce(nai_ficha_valor(p_codigo, 'incluso no aluguel'), 'não informado'),
             'garantia do aluguel: ' || coalesce(nai_ficha_valor(p_codigo, 'garantia de aluguel'), 'não informado')));
  v := v || ('O IMÓVEL: ' || concat_ws(' | ',
             CASE WHEN coalesce(i.area_util, 0) > 0 THEN trim(to_char(i.area_util, 'FM999990')) || ' m²' END,
             'área (anúncio): ' || nai_ficha_valor(p_codigo, 'area'),
             'área construída: ' || nai_ficha_valor(p_codigo, 'area construida'),
             'terreno: ' || nai_ficha_valor(p_codigo, 'tamanho do terreno'),
             CASE WHEN coalesce(i.quartos, 0) > 0 THEN i.quartos || ' quartos' || CASE WHEN coalesce(i.suites, 0) > 0 THEN ' (' || i.suites || CASE WHEN i.suites = 1 THEN ' suíte)' ELSE ' suítes)' END ELSE '' END END,
             CASE WHEN coalesce(i.banheiros, 0) > 0 THEN i.banheiros || ' banheiros' END,
             CASE WHEN coalesce(i.vagas, 0) > 0 OR coalesce(i.vagas_cobertas, 0) > 0
                  THEN 'vagas: ' || coalesce(i.vagas::text, '?') || coalesce(' (' || i.vagas_cobertas || ' cobertas)', '') END,
             'sol: ' || coalesce(nullif(i.sol, ''), nai_ficha_valor(p_codigo, 'sol')),
             CASE WHEN coalesce(i.andar, '') <> '' THEN 'andar ' || i.andar END,
             'lances de escada: ' || nai_ficha_valor(p_codigo, 'lances de escada'),
             'mobília: ' || nullif(i.mobilia, '')));
  IF coalesce(array_length(f.caracteristicas_imovel, 1), 0) > 0 OR coalesce(array_length(i.caracteristicas, 1), 0) > 0 THEN
    v := v || ('CARACTERÍSTICAS DO IMÓVEL: ' || array_to_string(
               ARRAY(SELECT DISTINCT c FROM unnest(coalesce(f.caracteristicas_imovel, '{}') || coalesce(i.caracteristicas, '{}')) c), ', '));
  END IF;
  IF coalesce(array_length(f.caracteristicas_condominio, 1), 0) > 0 THEN
    v := v || ('CARACTERÍSTICAS DO CONDOMÍNIO: ' || array_to_string(f.caracteristicas_condominio, ', '));
  END IF;
  x := nai_ficha_texto_livre(p_codigo);
  IF x IS NOT NULL THEN v := v || ('DESCRIÇÃO E OBSERVAÇÕES DO ANÚNCIO: ' || left(x, 2500)); END IF;
  SELECT string_agg('- ' || k.assunto || ': ' || k.texto, E'\n' ORDER BY k.atualizado_em DESC) INTO x
    FROM imovel_conhecimento k WHERE k.codigo = p_codigo::text;
  IF x IS NOT NULL THEN v := v || (E'O QUE O TEL JÁ RESPONDEU SOBRE ESTE IMÓVEL:\n' || x); END IF;
  v := v || ('ATUALIZADA EM: ' || coalesce(to_char(f.lido_em AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI'), 'sem leitura do anúncio'));
  RETURN array_to_string(v, E'\n');
END;
$$;

-- ------------------------------------------------------ ASSUNTO SENSÍVEL
CREATE OR REPLACE FUNCTION nai_assunto_sensivel(p_texto text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  -- O que NÃO se responde de cabeça: só com a linha da ficha, ou o Tel.
  SELECT CASE
    WHEN q ~ 'fgts' THEN 'fgts'
    WHEN q ~ '(financ|a vista|avista|forma de pagamento|\mpagamento|\mparcel|carta de credito|consorcio)' THEN 'pagamento'
    WHEN q ~ '(permuta|\mtroca\M|aceita (um |uma )?(carro|veiculo|terreno|imovel|apartamento|casa) (como|na|no|de) )' THEN 'permuta'
    WHEN q ~ '(fiador|caucao|garantia|seguro.?fianca|titulo de capitaliza)' THEN 'garantia'
    WHEN q ~ '(escritura|documenta|averba|quitad|inventario|matricula|habite.?se|regulariz|financiad[oa] pelo)' THEN 'documentacao'
    WHEN q ~ '(\mpets?\M|animal|animais|cachorro|\mgatos?\M|\mcao\M)' THEN 'pet'
  END
  FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS q) x;
$$;

-- --------------------------------------------- A PAREDE DA FORMA DE PAGAMENTO
CREATE OR REPLACE FUNCTION nai_re_pagamento()
RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT '(financ|[àa]\s+vista|avista|fgts|permuta)'::text $$;

CREATE OR REPLACE FUNCTION nai_afirmacao_de_pagamento(p_frase text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  -- O que uma frase DA NAY afirma sobre pagamento. Pergunta não afirma nada.
  SELECT CASE
    WHEN q ~ '\?\s*$' THEN NULL
    WHEN q ~ '((somente|so|apenas|exclusivamente|unicamente)\s+(o\s+)?(pagamento\s+)?(a|e)\s+vista|so\s+aceita\s+(pagamento\s+)?a\s+vista|nao\s+(aceita|faz|pega|trabalha\s+com|tem|da\s+(pra|para))\s+(ser\s+)?financ|sem\s+financiamento|nao\s+(e\s+)?financiav)'
      THEN 'so_a_vista'
    WHEN q ~ '((aceita|faz|pega|pode\s+ser|da\s+(pra|para)|trabalha\s+com|tem)\s+(pagamento\s+)?((a\s+vista|avista)\s+(ou|e)\s+)?(ser\s+)?financ|financiavel|pode\s+financiar)'
      THEN 'financia'
    WHEN q ~ 'nao\s+aceita\s+(permuta|troca)' THEN 'permuta_nao'
    WHEN q ~ 'aceita\s+(permuta|troca)' THEN 'permuta_sim'
    WHEN q ~ 'fgts' THEN 'fgts'
  END
  FROM (SELECT lower(unaccent(coalesce(p_frase, ''))) AS q) x;
$$;

CREATE OR REPLACE FUNCTION nai_verdade_de_pagamento(p_codigo int, p_afirmacao text)
RETURNS text LANGUAGE sql STABLE AS $$
  -- 'confere' | 'contradiz' | 'sem_dado'
  SELECT CASE p_afirmacao
    WHEN 'so_a_vista'  THEN CASE WHEN fin ~* '^s' THEN 'contradiz' WHEN fin ~* '^n' THEN 'confere' ELSE 'sem_dado' END
    WHEN 'financia'    THEN CASE WHEN fin ~* '^s' THEN 'confere' WHEN fin ~* '^n' THEN 'contradiz' ELSE 'sem_dado' END
    WHEN 'permuta_sim' THEN CASE WHEN per ~* '^s' THEN 'confere' WHEN per ~* '^n' THEN 'contradiz' ELSE 'sem_dado' END
    WHEN 'permuta_nao' THEN CASE WHEN per ~* '^n' THEN 'confere' WHEN per ~* '^s' THEN 'contradiz' ELSE 'sem_dado' END
    WHEN 'fgts'        THEN CASE WHEN coalesce(nai_ficha_texto_livre(p_codigo), '') ~* 'fgts' THEN 'confere' ELSE 'sem_dado' END
  END
  FROM (SELECT nai_ficha_valor(p_codigo, 'aceita financiamento') AS fin,
               nai_ficha_valor(p_codigo, 'aceita permuta') AS per) x;
$$;

CREATE OR REPLACE FUNCTION nai_frase_de_pagamento(p_codigo int, p_afirmacao text)
RETURNS text LANGUAGE sql STABLE AS $$
  -- A frase CERTA, quando a dela contradiz a ficha.
  SELECT 'O ' || coalesce(nullif(nai_condominio_ok(i.condominio_nome), ''), coalesce(i.tipo, 'imóvel'))
         || ' (' || i.codigo || ') '
         || CASE WHEN p_afirmacao IN ('so_a_vista', 'financia') THEN
                   CASE WHEN nai_ficha_valor(i.codigo, 'aceita financiamento') ~* '^s' THEN 'aceita financiamento.'
                        ELSE 'não aceita financiamento: é só à vista.' END
                 ELSE
                   CASE WHEN nai_ficha_valor(i.codigo, 'aceita permuta') ~* '^s' THEN 'aceita permuta.'
                        ELSE 'não aceita permuta.' END END
    FROM imoveis i WHERE i.codigo = p_codigo;
$$;

CREATE OR REPLACE FUNCTION nai_conferir_pagamento(p_texto text, p_alvo int)
RETURNS TABLE(texto text, trocas int, sem_dado int[]) LANGUAGE plpgsql STABLE AS $$
-- Cada frase da resposta que afirma forma de pagamento é conferida com a
-- ficha do imóvel de que ela fala (código ou nome na frase; senão o imóvel
-- da conversa). As linhas do CARD ficam fora: o card sai da ficha.
DECLARE
  s      text;
  a      text;
  cods   int[];
  c      int;
  ver    text;
  certa  text;
BEGIN
  texto := p_texto; trocas := 0; sem_dado := '{}';
  FOR s IN SELECT m[1] FROM regexp_matches(coalesce(p_texto, ''), '([^.!?\n]+[.!?]*)', 'g') AS m LOOP
    CONTINUE WHEN btrim(s) = '' OR s ~ '^\s*(•|📍|Venda:|Locação:|C[óo]digo:|OBS:)';
    a := nai_afirmacao_de_pagamento(s);
    CONTINUE WHEN a IS NULL;
    SELECT coalesce(array_agg(DISTINCT x), '{}') INTO cods FROM (
      SELECT y::int AS x FROM unnest(coalesce(nay_codigos_citados(s), '{}'::text[])) y
       WHERE y ~ '^[0-9]{3,5}$' AND EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = y::int)
      UNION SELECT unnest(nai_imovel_pelo_condominio(s, ''))) z;
    IF coalesce(array_length(cods, 1), 0) = 0 AND p_alvo IS NOT NULL THEN cods := ARRAY[p_alvo]; END IF;
    IF coalesce(array_length(cods, 1), 0) = 0 THEN
      -- afirmou sem dizer de qual imóvel e não há imóvel na conversa: não dá
      -- para conferir, então não sai. O -1 marca "sem imóvel".
      texto := replace(texto, s, ''); sem_dado := sem_dado || (-1); CONTINUE;
    END IF;
    certa := NULL;
    FOREACH c IN ARRAY cods LOOP
      ver := nai_verdade_de_pagamento(c, a);
      IF ver = 'sem_dado' THEN
        sem_dado := sem_dado || c;
      ELSIF ver = 'contradiz' THEN
        certa := concat_ws(' ', certa, nai_frase_de_pagamento(c, a));
      END IF;
    END LOOP;
    IF certa IS NOT NULL THEN
      -- o espaço que vinha antes da frase fica (senão "financiado.O Living")
      texto := replace(texto, s, coalesce(substring(s FROM '^\s*'), '') || certa); trocas := trocas + 1;
    ELSIF EXISTS (SELECT 1 FROM unnest(cods) k WHERE k = ANY (sem_dado)) THEN
      texto := replace(texto, s, '');
    END IF;
  END LOOP;
  texto := btrim(regexp_replace(texto, '[ \t]{2,}', ' ', 'g'));
  RETURN NEXT;
END;
$$;

COMMIT;
