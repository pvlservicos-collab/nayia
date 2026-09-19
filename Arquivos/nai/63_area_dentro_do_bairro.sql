-- =====================================================================
-- NAI -- 63: AREA dentro do bairro -- Vieiralves e Nossa Sra. das Gracas (Tel, 18/09/2026)
--
-- Ele: "quando falarem Vieiralves e a mesma coisa que Nossa Sra. das Gracas.
-- Nossa Sra. das Gracas e o bairro e Vieiralves e um conjunto do bairro -- a
-- area mais alto nivel dele, e sempre chamam por Vieiralves na maioria das
-- vezes. A Nay precisa identificar que sao os dois. Salva essa condicao como
-- AREA, alem de bairro, uma nova variavel."
--
-- O CASO: o Sr. Luciano pediu imovel "no Dom Pedro e Vieiralves" e ouviu
-- "Nao trabalhamos com imovel em Vieiralves no momento" -- com 36 imoveis em
-- Nossa Senhora das Gracas na base. Nenhum imovel tem "Vieiralves" no campo
-- bairro (0 na base); o nome so aparece em 9 descricoes.
--
-- O QUE ENTRA
--
-- 1. `bairro_area` (nova): a variavel AREA. Uma linha por area, apontando para
--    o bairro oficial. Vieiralves e a primeira; outras entram com um INSERT,
--    sem mexer em codigo.
--
-- 2. `nay_normalizar_lugar` passa a trocar a area pelo bairro. Ela e o ponto
--    por onde passam a busca, o pedido de perfil, a descricao do imovel e os
--    bairros vizinhos -- entao "Vieiralves" casa com Nossa Senhora das Gracas
--    em todos esses lugares de uma vez, sem uma copia da regra em cada um.
--
-- 3. Os dois prompts (locacao e captacao) ganham a frase: ela reconhece a area
--    e fala do jeito que a pessoa falou.
-- =====================================================================

CREATE TABLE IF NOT EXISTS bairro_area (
  area       text PRIMARY KEY,
  bairro     text NOT NULL,
  nota       text,
  criado_em  timestamptz NOT NULL DEFAULT now()
);

INSERT INTO bairro_area (area, bairro, nota)
VALUES ('Vieiralves', 'Nossa Senhora das Graças',
        'Conjunto dentro de Nossa Sra. das Gracas; a parte de mais alto padrao. '
        || 'E como quase todo mundo chama o bairro (Tel, 18/09/2026).')
ON CONFLICT (area) DO NOTHING;

-- A funcao base. A de dois argumentos chama esta, entao herda a troca.
CREATE OR REPLACE FUNCTION public.nay_normalizar_lugar(p_texto text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  t text;
  a record;
BEGIN
  t := btrim(regexp_replace(
         regexp_replace(
           regexp_replace(
             regexp_replace(lower(unaccent(coalesce(p_texto,''))),
                            '[^a-z0-9]+', ' ', 'g'),
             '\m(pq|pque)\M', 'parque', 'g'),
           '\m(dez)\M', '10', 'g'),
         '\s+', ' ', 'g'));

  -- AREA -> BAIRRO (Tel, 18/09). "vieiralves" vira "nossa senhora das gracas",
  -- e dai em diante tudo o que compara bairro enxerga os dois como um so.
  -- A tabela e pequena; o IF evita ler ela quando o texto nao cita area nenhuma.
  IF t <> '' THEN
    FOR a IN
      SELECT btrim(regexp_replace(lower(unaccent(area)),   '[^a-z0-9]+', ' ', 'g')) AS de,
             btrim(regexp_replace(lower(unaccent(bairro)), '[^a-z0-9]+', ' ', 'g')) AS para
        FROM bairro_area
    LOOP
      IF position(a.de IN t) > 0 THEN
        t := regexp_replace(t, '\m' || a.de || '\M', a.para, 'g');
      END IF;
    END LOOP;
  END IF;

  RETURN t;
END;
$function$;

-- Para quem quiser saber a area que a pessoa citou (e responder com o nome dela).
CREATE OR REPLACE FUNCTION public.nai_area_citada(p_texto text)
 RETURNS TABLE(area text, bairro text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT b.area, b.bairro
    FROM bairro_area b
   WHERE position(btrim(regexp_replace(lower(unaccent(b.area)), '[^a-z0-9]+', ' ', 'g'))
                  IN regexp_replace(lower(unaccent(coalesce(p_texto,''))), '[^a-z0-9]+', ' ', 'g')) > 0;
$function$;

-- 4. A resposta da busca fala o nome que a pessoa usou.
CREATE OR REPLACE FUNCTION public.nai_buscar_por_perfil(p_turno bigint, p_bairro text, p_teto text, p_quartos text, p_mobilia text)
 RETURNS TABLE(texto_pronto text, instrucao_para_voce text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  t        nai_turno;
  k        nai_contato;
  b        record;
  v_teto   numeric := nay_valor_em_reais(p_teto);
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

  -- A SEQUENCIA DO FLUXO (cards do Tel): bairro -> faixa de preco -> mobilia,
  -- UMA PERGUNTA POR MENSAGEM. Quem manda a pergunta e esta funcao, nao o
  -- modelo: em 12/09 ele juntou duas perguntas numa mensagem so, duas vezes.
  -- Enquanto faltar resposta, ela devolve a PROXIMA pergunta e nada mais.
  IF nullif(btrim(coalesce(p_bairro, '')), '') IS NULL THEN
    RETURN QUERY SELECT
      CASE WHEN v_direta
           -- ele chegou pedindo: nao existe "tambem", porque ela ainda nao
           -- ofereceu nada.
           THEN 'Claro! Você está procurando imóveis em qual bairro?'
           ELSE 'Eu também tenho outras opções de locação, você está procurando imóveis em qual bairro?'
      END::text,
      ('etapa 1 de ' || CASE WHEN v_direta THEN '2' ELSE '3' END || ' da sequencia. Diga SO essa pergunta, '
       || 'sem listar imovel nenhum e sem juntar outra pergunta. Quando ele responder, chame '
       || 'buscar_por_perfil de novo com o bairro.')::text;
    RETURN;
  END IF;
  IF nullif(btrim(coalesce(p_teto, '')), '') IS NULL THEN
    RETURN QUERY SELECT 'E qual a faixa de preço que seus clientes estão buscando?'::text,
      ('etapa 2 de ' || CASE WHEN v_direta THEN '2' ELSE '3' END || ' da sequencia. Diga SO essa pergunta, '
       || 'sem listar imovel nenhum e sem juntar outra pergunta. Quando ele responder, chame '
       || 'buscar_por_perfil de novo com bairro e teto.')::text;
    RETURN;
  END IF;
  -- A MOBILIA e a terceira pergunta SO de quem veio do grupo. Quem chegou
  -- pedindo imovel responde duas e ja ve a lista (Tel, 15/09: "essas 2
  -- perguntas padroes e mais filtros so se o cliente ja pedir"). Se ele falar
  -- de mobilia por conta propria, o filtro entra do mesmo jeito -- o valor
  -- chega em p_mobilia e e usado logo abaixo.
  IF NOT v_direta AND nullif(btrim(coalesce(p_mobilia, '')), '') IS NULL THEN
    RETURN QUERY SELECT 'E eles têm preferência por semimobiliado ou mobiliado?'::text,
      ('etapa 3 de 3 da sequencia. Diga SO essa pergunta, sem listar imovel nenhum, e quando ele '
       || 'responder chame buscar_por_perfil de novo com bairro, teto e mobilia.')::text;
    RETURN;
  END IF;

  v_sem := v_mob ~ '\m(sem|nao|vazio)\M';
  v_com := NOT v_sem AND v_mob ~ '\m(com|mobiliad|semi|modulad|planejad)';

  -- O FORMATO E DO TEL (13/09, depois do teste: "me mandou 2 imoveis de forma
  -- desformatada, quero algo assim bem formatado"). Um bloco por imovel, com o
  -- icone, o nome em negrito do WhatsApp e o codigo com #.
  SELECT string_agg(nai_bloco_oferta(z.c), E'\n\n' ORDER BY z.v) INTO v_aqui FROM (
    SELECT i.codigo AS c, i.valor_aluguel AS v FROM imoveis i
     WHERE nay_normalizar_lugar(i.bairro, true) LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
       AND nai_oferta_serve(i, k.telefone, v_teto, v_q, v_sem, v_com)
     ORDER BY i.valor_aluguel LIMIT 5) z;

  v_viz := nay_bairros_proximos(btrim(coalesce(p_bairro, '')));
  IF coalesce(array_length(v_viz, 1), 0) > 1 THEN
    SELECT string_agg(nai_bloco_oferta(z.c), E'\n\n' ORDER BY z.v) INTO v_alt FROM (
      SELECT i.codigo AS c, i.valor_aluguel AS v FROM imoveis i
       WHERE i.bairro = ANY (v_viz)
         AND nay_normalizar_lugar(i.bairro, true) NOT LIKE '%' || nay_normalizar_lugar(p_bairro, true) || '%'
         AND nai_oferta_serve(i, k.telefone, v_teto, v_q, v_sem, v_com)
       ORDER BY i.valor_aluguel LIMIT 5) z;
  END IF;

  -- Nada aqui nem perto: quem responde e a funcao antiga, que sabe dizer "voce
  -- quis dizer Ponta Negra?" e "esse bairro nao e da nossa area".
  IF v_aqui IS NULL AND v_alt IS NULL THEN
    SELECT * INTO b FROM nay_buscar_por_perfil(p_bairro, 'locacao', p_teto, p_quartos, p_mobilia);
    RETURN QUERY SELECT upper(left(b.texto_pronto, 1)) || substr(b.texto_pronto, 2), b.instrucao_para_voce;
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

  IF v_aqui IS NOT NULL THEN
    v_txt := 'No ' || v_nome_b || ' eu tenho estas opções:' || E'\n\n' || v_aqui;
    IF v_alt IS NOT NULL THEN
      v_txt := v_txt || E'\n\n' || 'E tenho estas aqui perto:' || E'\n\n' || v_alt;
    END IF;
  ELSE
    v_txt := 'No ' || v_nome_b || ', não tenho nenhum imóvel nesse perfil disponível no momento.' || E'\n\n' ||
             'Mas tenho estas opções aqui perto:' || E'\n\n' || v_alt;
  END IF;

  RETURN QUERY SELECT v_txt,
    ('mande o texto_pronto EXATAMENTE como veio: cada imovel no seu bloco, com o icone, o negrito e as linhas com •. '
     || 'NAO resuma, NAO junte tudo numa linha, NAO reescreva e NAO invente imovel que nao esta na lista. '
     || 'Se ele quiser detalhe de um, chame imovel_por_codigo. NAO sugira visita aqui.')::text;
END;
$function$;
