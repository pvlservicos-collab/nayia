-- =====================================================================
-- NAI -- 22: os DOIS gatilhos de entrada da busca (Tel, 15/09/2026)
--
-- Ele: "essa etapa e nova, vc vai criar ela como se fosse 2 gatilhos: ou a
-- pessoa vem pelo grupo ou a pessoa manda msg pedindo imoveis especificos".
--
--   PELO GRUPO (ja existe imovel na conversa): nada muda. Continua a sequencia
--   de tres perguntas do fluxo do site -- bairro, faixa de preco, mobilia --
--   comecando com "Eu tambem tenho outras opcoes de locacao".
--
--   PEDINDO IMOVEL (nenhum imovel na conversa): duas perguntas, bairro e faixa
--   de preco, e a primeira sem o "tambem" -- ela ainda nao ofereceu nada a que
--   esse "tambem" pudesse se referir. Mobilia e qualquer outro filtro entram
--   so se o proprio corretor falar deles.
--
-- Como se sabe por onde ele entrou, sem marca nova no banco: quem veio do
-- grupo tem imovel na conversa (o card que colou, o codigo que escreveu, a
-- foto que pediu); quem chegou perguntando "tem apartamento de 2 quartos?"
-- nao tem nenhum. E `nai_imovel_da_conversa`, que ja existe e ja respeita o
-- marco de conversa zerada.
--
-- Gerado por `scratchpad/patch_dois_gatilhos.py` a partir do que estava NO
-- BANCO: quatro acrescimos, nenhuma remocao.
-- =====================================================================

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
