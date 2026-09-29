-- =====================================================================
-- 144 — A RAJADA DE 15 S E LOCAÇÃO x VENDA NA IDENTIFICAÇÃO (28/09/2026)
--
-- Tel: "precisa ter a janela de aguardo para ela acumular mensagem de clientes
-- a toda mensagem, ela deve ter mandado tudo com pressa... quero uns 15
-- segundos de empilhamento" e "ela precisa saber se o imóvel que o cara quer
-- é venda ou locação também no processo de identificação, a não ser que isso
-- já tenha ficado claro em outras conversas".
--
-- A RAJADA: a janela (15 s desde a 140b) era fixa a partir da PRIMEIRA
-- mensagem -- "Ponta negra" (10:44:46) e "R$ 3.000,00 R$ 3.500,00" (10:45:02)
-- viraram dois turnos. Agora ela recomeça a cada mensagem: quando um turno vai
-- juntar as mensagens e chegou outra do mesmo corretor há menos de 15 s, ele
-- não pega nada -- quem junta tudo é a execução da ÚLTIMA, depois de 15 s de
-- silêncio. Mora num gatilho de `mensagens`, sem mexer no n8n.
--
-- LOCAÇÃO x VENDA: o filtro pergunta primeiro "Seu cliente procura imóvel
-- para alugar ou para comprar?" quando a conversa não disse; a fila dos
-- outros imóveis não manda imóvel do negócio errado nem lê nome de bairro
-- como condomínio; a rede da saída passa a tirar também o CARD de texto.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '5s';

-- A rajada: espera 15 s de silêncio.
CREATE OR REPLACE FUNCTION mensagens_espera_a_rajada()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
BEGIN
  IF OLD.status = 'Recebido' AND NEW.status = 'Processando'
     AND NEW.fluxo = 'nai' AND NEW.direcao = 'recebida'
     AND EXISTS (SELECT 1 FROM mensagens m2
                  WHERE m2.telefone = NEW.telefone AND m2.fluxo = 'nai' AND m2.direcao = 'recebida'
                    AND m2.status = 'Recebido' AND m2.id <> NEW.id
                    AND m2.criada_em > now() - make_interval(secs => greatest(nai_cfg_int('janela_segundos', 15) - 1, 1))) THEN
    RETURN NULL;   -- chegou outra ha menos de 15 s: quem junta e a execucao dela
  END IF;
  RETURN NEW;
END;
$fn$;
DROP TRIGGER IF EXISTS mensagens_espera_a_rajada ON mensagens;
CREATE TRIGGER mensagens_espera_a_rajada
  BEFORE UPDATE OF status ON mensagens
  FOR EACH ROW EXECUTE FUNCTION mensagens_espera_a_rajada();

-- A frase é só um bairro? ("Ponta negra", "no Adrianópolis")
CREATE OR REPLACE FUNCTION nai_e_so_bairro(p text)
RETURNS boolean
LANGUAGE sql
STABLE
AS $fn$
  SELECT EXISTS (SELECT 1 FROM (SELECT DISTINCT lower(unaccent(btrim(bairro))) b FROM imoveis WHERE coalesce(btrim(bairro), '') <> '') x
                  WHERE x.b = lower(unaccent(btrim(regexp_replace(coalesce(p, ''), '^\s*(no|na|em|bairro|o|a)\s+', '', 'i'), E' \t\n.,!?'))));
$fn$;

-- Locação ou venda: a conversa das últimas 24h, ou a régua do valor.
CREATE OR REPLACE FUNCTION nai_negocio_do_pedido(p_contato bigint, p_texto text)
RETURNS text
LANGUAGE sql
STABLE
AS $fn$
  SELECT coalesce(nai_negocio_da_conversa(p_contato, p_texto),
                  CASE WHEN x.v IS NULL THEN NULL WHEN x.v <= 30000 THEN 'locacao' WHEN x.v >= 100000 THEN 'venda' END)
    FROM (SELECT coalesce(nay_maior_valor(coalesce(p_texto, '')), nay_valor_em_reais(coalesce(p_texto, ''))) AS v) x;
$fn$;

CREATE OR REPLACE FUNCTION public.nai_fila_dos_outros_imoveis(p_turno bigint, p_escreveu text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  t       nai_turno;
  k       nai_contato;
  v_cods  int[];
  v_ja    int[];
  v_rej   int[];
  v_ordem int;
  c       int;
  f       record;
  v_card  text;
  n       int := 0;
  v_teto  int := 3;
  p       jsonb;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN 0; END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;

  -- 1. a secretaria nao tem catalogo
  IF t.atendente = 'secretaria' THEN
    PERFORM nai_anotar(p_turno, 22, 'fila_de_imoveis', 'cortou',
                       'quem atende é a secretária: ela não manda imóvel do catálogo');
    RETURN 0;
  END IF;

  p := nai_pedido_do_turno(p_turno);

  -- 2. oferta nao e pedido
  IF coalesce((p->>'oferta')::boolean, false) OR coalesce((p->>'link')::boolean, false) THEN
    PERFORM nai_anotar(p_turno, 22, 'fila_de_imoveis', 'cortou',
                       'ele está oferecendo, não pedindo');
    RETURN 0;
  END IF;

  -- 3. o Jev disse que nao foi pedido
  IF NOT nai_pediu_imovel(p_turno) THEN
    PERFORM nai_anotar(p_turno, 22, 'fila_de_imoveis', 'cortou',
                       'o Jev disse que ele não pediu imóvel neste turno');
    RETURN 0;
  END IF;

  -- 144: NOME DE BAIRRO NAO E PEDIDO DE CONDOMINIO (Walter, 28/09 10:44: ele
  -- respondeu "Ponta negra" a pergunta do bairro e recebeu 3 cards do
  -- Residencial Ponta Negra II, de venda).
  IF nai_e_so_bairro(coalesce(nullif(p_escreveu, ''), t.texto)) THEN
    PERFORM nai_anotar(p_turno, 22, 'fila_de_imoveis', 'cortou', 'ele disse um bairro, nao um imovel');
    RETURN 0;
  END IF;
  v_cods := nai_imoveis_pedidos(coalesce(nullif(p_escreveu, ''), t.texto), k.telefone);
  IF coalesce(array_length(v_cods, 1), 0) < 2 THEN RETURN 0; END IF;

  SELECT coalesce(array_agg(DISTINCT s.codigo), '{}') INTO v_ja
    FROM nai_saida s WHERE s.turno_id = p_turno AND s.codigo IS NOT NULL;
  SELECT coalesce(max(s.ordem), 0) INTO v_ordem FROM nai_saida s WHERE s.turno_id = p_turno;

  -- 4. O QUE ELE RECUSOU (era o que faltava)
  SELECT codigos_rejeitados INTO v_rej FROM nai_estado_conversa WHERE contato_id = t.contato_id;

  FOREACH c IN ARRAY v_cods LOOP
    EXIT WHEN n >= v_teto;
    CONTINUE WHEN c = ANY (v_ja);
    CONTINUE WHEN c = ANY (coalesce(v_rej, '{}'));
    -- 144: o negocio da conversa manda (locacao nao recebe imovel so de venda).
    CONTINUE WHEN nai_negocio_do_pedido(k.id, coalesce(nullif(p_escreveu, ''), t.texto)) = 'locacao'
                  AND NOT EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = c AND coalesce(i.valor_aluguel, 0) > 0);
    CONTINUE WHEN nai_negocio_do_pedido(k.id, coalesce(nullif(p_escreveu, ''), t.texto)) = 'venda'
                  AND NOT EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo = c AND coalesce(i.valor_venda, 0) > 0);
    CONTINUE WHEN NOT EXISTS (SELECT 1 FROM imoveis i
                               WHERE i.codigo = c
                                 AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
                                 AND NOT coalesce(i.e_parceiro, false));

    SELECT cc.texto_pronto INTO v_card FROM nai_card_do_imovel(c) cc;
    CONTINUE WHEN v_card IS NULL;

    v_ordem := v_ordem + 1;
    PERFORM nai_enfileirar_texto(p_turno, NULL, t.contato_id, 'turno', v_card, 'resposta', v_ordem);

    FOR f IN SELECT * FROM nai_imagens_do_envio(c) LOOP
      v_ordem := v_ordem + 1;
      INSERT INTO nai_saida (turno_id, contato_id, papel_destino, chave_destino, tipo, imagem_url, codigo, ordem, motivo)
           VALUES (p_turno, t.contato_id, 'turno', '', 'imagem', f.url, c, v_ordem,
                   CASE WHEN f.e_colagem THEN 'colagem' ELSE 'foto' END);
    END LOOP;

    n := n + 1;
  END LOOP;

  IF n > 0 THEN
    PERFORM nai_anotar(p_turno, 22, 'fila_de_imoveis', 'mudou',
                       'ele pediu ' || array_length(v_cods, 1) || ' imóveis; ' || n || ' foram para a fila');
  END IF;
  RETURN n;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_conferir_imoveis_da_saida(p_turno bigint)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  p jsonb; v_tipo text; v_negocio text; n int := 0; r record;
  v_citados int[]; v_passe boolean; v_sobrou boolean; v_texto text;
  v_promessa text := '(segue|abaixo|logo mais|vou te (mandar|enviar)|te envio|te mando|encontrei|separei|essas? (opç|sugest)|seguem)';
BEGIN
  p := nai_pedido_do_turno(p_turno);
  v_tipo    := p->>'tipo';
  v_negocio := p->>'negocio';

  SELECT coalesce(array_agg(e::int), '{}'::int[]) INTO v_citados
    FROM jsonb_array_elements_text(coalesce(p->'imoveis', '[]'::jsonb)) e
   WHERE e ~ '^[0-9]+$';
  -- O passe vale para quem APONTOU um imovel. Nome de bairro expande para
  -- dez codigos e nao e apontar: ai a peneira do tipo continua valendo.
  v_passe := nai_passe_do_citado(v_citados);

  FOR r IN
    SELECT s.id, s.codigo, i.tipo, i.valor_venda, i.valor_aluguel, i.e_parceiro,
           nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site) AS no_mercado
      FROM nai_saida s JOIN imoveis i ON i.codigo = s.codigo
     WHERE s.turno_id = p_turno AND s.estado = 'pendente' AND s.codigo IS NOT NULL
  LOOP
    -- PARCEIRO E FORA DO MERCADO NUNCA SAEM -- nem apontados pelo nome.
    IF coalesce(r.e_parceiro, false) OR NOT r.no_mercado THEN
      UPDATE nai_saida SET estado = 'bloqueado',
                           bloqueio = CASE WHEN r.e_parceiro THEN 'parceiro' ELSE 'fora do mercado' END
       WHERE id = r.id;
      n := n + 1;
      CONTINUE;
    END IF;

    IF v_passe AND r.codigo = ANY (v_citados) THEN
      PERFORM nai_anotar(p_turno, 23, 'passe_do_citado', 'passou',
                         'ele apontou o ' || r.codigo || ' pelo nome');
      CONTINUE;
    END IF;

    IF v_tipo IS NOT NULL AND r.tipo IS NOT NULL AND r.tipo NOT ILIKE v_tipo THEN
      UPDATE nai_saida SET estado = 'bloqueado',
                           bloqueio = 'tipo errado: ele pediu ' || lower(nai_rotulo_do_tipo(v_tipo))
       WHERE id = r.id;
      n := n + 1;
      CONTINUE;
    END IF;

    IF v_negocio = 'venda' AND coalesce(r.valor_venda, 0) <= 0 THEN
      UPDATE nai_saida SET estado = 'bloqueado', bloqueio = 'ele procura venda'
       WHERE id = r.id; n := n + 1; CONTINUE;
    END IF;
    IF v_negocio = 'locacao' AND coalesce(r.valor_aluguel, 0) <= 0 THEN
      UPDATE nai_saida SET estado = 'bloqueado', bloqueio = 'ele procura locação'
       WHERE id = r.id; n := n + 1; CONTINUE;
    END IF;
  END LOOP;

  -- O TEXTO ORFAO: "segue abaixo" nao sai sem nada abaixo.
  -- 144: O CARD DE TEXTO TAMBEM. A rede so olhava as linhas com codigo (as
  -- fotos): o card do imovel errado saia sozinho, sem as fotos. Card = texto
  -- com o alfinete e UM "Codigo: NNNN".
  FOR r IN
    SELECT s.id, x.cod AS codigo, i.tipo, i.valor_venda, i.valor_aluguel
      FROM nai_saida s
      CROSS JOIN LATERAL (SELECT (regexp_match(s.texto, 'C[óo]digo:\s*(\d{3,5})', 'i'))[1]::int AS cod) x
      JOIN imoveis i ON i.codigo = x.cod
     WHERE s.turno_id = p_turno AND s.estado = 'pendente' AND s.codigo IS NULL AND s.tipo = 'texto'
       AND position('📍' IN coalesce(s.texto, '')) > 0
       AND (SELECT count(*) FROM regexp_matches(s.texto, 'C[óo]digo:\s*\d{3,5}', 'gi')) = 1
  LOOP
    CONTINUE WHEN v_passe AND r.codigo = ANY (v_citados);
    IF (v_tipo IS NOT NULL AND r.tipo IS NOT NULL AND r.tipo NOT ILIKE v_tipo)
       OR (v_negocio = 'venda' AND coalesce(r.valor_venda, 0) <= 0)
       OR (v_negocio = 'locacao' AND coalesce(r.valor_aluguel, 0) <= 0) THEN
      UPDATE nai_saida SET estado = 'bloqueado',
                           bloqueio = 'card que nao bate com o pedido (' || coalesce(v_negocio, '') || ' ' || coalesce(lower(nai_rotulo_do_tipo(v_tipo)), '') || ')'
       WHERE id = r.id;
      n := n + 1;
    END IF;
  END LOOP;

  IF n > 0 AND nai_cfg('conferencia_barra_texto_orfao', 'sim') = 'sim' THEN
    SELECT EXISTS (SELECT 1 FROM nai_saida
                    WHERE turno_id = p_turno AND estado = 'pendente' AND codigo IS NOT NULL)
      INTO v_sobrou;
    IF NOT v_sobrou THEN
      SELECT string_agg(left(texto, 200), ' / ') INTO v_texto
        FROM nai_saida
       WHERE turno_id = p_turno AND estado = 'pendente' AND codigo IS NULL AND texto ~* v_promessa;
      IF v_texto IS NOT NULL THEN
        UPDATE nai_saida SET estado = 'bloqueado', bloqueio = 'texto sem o imóvel'
         WHERE turno_id = p_turno AND estado = 'pendente' AND codigo IS NULL AND texto ~* v_promessa;
        PERFORM nai_avisar_tel(p_turno, NULL,
          'Tel, a conferência retirou todos os imóveis desta resposta, então não mandei nada: ela ia dizer "'
          || left(v_texto, 200) || '" sem imóvel nenhum atrás. Dá uma olhada nesse chat.',
          'saida_sem_imovel');
        PERFORM nai_anotar(p_turno, 23, 'texto_orfao', 'barrou', left(v_texto, 200));
      END IF;
    END IF;
  END IF;

  IF n > 0 THEN
    PERFORM nai_anotar(p_turno, 23, 'conferencia_da_saida', 'retirou',
                       n || ' linha(s) que não batiam com o pedido');
  END IF;
  RETURN n;
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
  -- 144: LOCACAO OU VENDA PRIMEIRO (Tel, 28/09: "ela precisa saber se o
  -- imovel que o cara quer e venda ou locacao tambem no processo de
  -- identificacao, a nao ser que isso ja tenha ficado claro em outras
  -- conversas"). Claro = a conversa das ultimas 24h disse, ou o valor dele diz
  -- (ate R$ 30 mil e aluguel; de R$ 100 mil para cima e venda).
  IF v_direta AND nai_negocio_do_pedido(k.id, concat_ws(' ', t.texto, p_teto)) IS NULL THEN
    RETURN QUERY SELECT
      CASE WHEN nullif(btrim(coalesce(p_teto, '')), '') IS NULL AND nullif(btrim(coalesce(p_bairro, '')), '') IS NULL
           THEN 'Eu vou fazer um filtro com você para poder te enviar as opções que mais podem atender a sua demanda. Seu cliente procura imóvel para alugar ou para comprar?'
           ELSE 'Seu cliente procura imóvel para alugar ou para comprar?' END::text,
      ('filtro: primeiro se e locacao ou venda. Diga SO isso. Quando ele responder, chame buscar_por_perfil '
       || 'de novo com tudo o que ele ja disse (bairro, teto).')::text;
    RETURN;
  END IF;

  IF v_direta AND nullif(btrim(coalesce(p_teto, '')), '') IS NULL AND NOT v_mostra_logo THEN
    RETURN QUERY SELECT
      CASE WHEN nullif(btrim(coalesce(p_bairro, '')), '') IS NULL AND NOT v_livre
           THEN 'Eu vou fazer um filtro com você para poder te enviar as opções que mais podem atender a sua demanda. Até que valor o seu cliente quer?'
           ELSE 'Até que valor o seu cliente quer?' END::text,
      ('filtro, pergunta 1 de 2. Diga SO isso, sem listar imovel nenhum e sem juntar outra pergunta. '
       || 'Quando ele responder, chame buscar_por_perfil de novo com o teto (e o bairro, se ele ja disse).')::text;
    RETURN;
  END IF;
  IF v_direta AND nullif(btrim(coalesce(p_bairro, '')), '') IS NULL AND NOT v_livre THEN
    RETURN QUERY SELECT 'E quais os bairros que atendem?'::text,
      ('filtro, pergunta 2 de 2. Diga SO essa pergunta. Quando ele responder, chame buscar_por_perfil '
       || 'de novo com o bairro e o teto.')::text;
    RETURN;
  END IF;

  IF nullif(btrim(coalesce(p_bairro, '')), '') IS NULL AND NOT v_livre THEN
    RETURN QUERY SELECT
      CASE WHEN v_direta
           -- ele chegou pedindo: nao existe "tambem", porque ela ainda nao
           -- ofereceu nada.
           THEN 'Claro! Você está procurando imóveis em qual bairro?'
           ELSE 'Eu também tenho outras opções de ' || v_diz || ', você está procurando imóveis em qual bairro?'
      END::text,
      ('etapa 1 de ' || CASE WHEN v_direta THEN '2' ELSE '3' END || ' da sequencia. Diga SO essa pergunta, '
       || 'sem listar imovel nenhum e sem juntar outra pergunta. Quando ele responder, chame '
       || 'buscar_por_perfil de novo com o bairro.')::text;
    RETURN;
  END IF;
  IF nullif(btrim(coalesce(p_teto, '')), '') IS NULL AND NOT v_mostra_logo THEN
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
  IF NOT v_direta AND nullif(btrim(coalesce(p_mobilia, '')), '') IS NULL
     AND NOT v_mostra_logo THEN
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
       || CASE WHEN v_teto IS NULL
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

  RETURN QUERY SELECT v_txt,
    ('mande o texto_pronto EXATAMENTE como veio: cada imovel no seu bloco, com o icone, o negrito e as linhas com •. '
     || 'NAO resuma, NAO junte tudo numa linha, NAO reescreva e NAO invente imovel que nao esta na lista. '
     || 'Se ele quiser detalhe de um, chame imovel_por_codigo. NAO sugira visita aqui.')::text;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_etapa_para_o_modelo(p_contato bigint)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  r     record;
  v_txt text;
  v_conf text;
BEGIN
  -- a etapa que o `nai_etapa_atualizar` acabou de gravar neste mesmo turno;
  -- so recalcula se ainda nao existe linha
  SELECT e.etapa, e.motivo INTO r FROM nai_etapa_contato e WHERE e.contato_id = p_contato;
  IF r.etapa IS NULL THEN
    SELECT * INTO r FROM nai_etapa_calcular(p_contato);
  END IF;
  v_txt := '(informação de sistema) ETAPA DESTA CONVERSA: ' ||
    CASE r.etapa
      WHEN 'identificacao' THEN
        'IDENTIFICAÇÃO (' || r.motivo || '; ' ||
        coalesce('ele procura ' || CASE nai_negocio_do_pedido(p_contato, '') WHEN 'locacao' THEN 'LOCAÇÃO'
                                                                             WHEN 'venda' THEN 'VENDA' ELSE NULL END,
                 'ainda não se sabe se é locação ou venda: pergunte antes de mandar imóvel') || '). Descubra o que o cliente dele quer: pediu foto, informação ou '
        || 'o imóvel -> card; perguntou se está disponível -> o_que_sei_do_imovel; falou de um imóvel pelo nome e você '
        || 'não tem certeza de qual é -> confirme com a ficha (a ferramenta devolve); pediu opções ou não disse -> '
        || 'buscar_por_perfil (valor, depois bairros). Fale de visita só se ele pedir.'
      WHEN 'recebeu_imovel' THEN
        'RECEBEU O IMÓVEL (' || r.motivo || '). Responda as dúvidas desse imóvel; se ele quiser visitar, vá '
        || 'para a visita; se quiser outras opções, faça o filtro.'
      ELSE
        'AGENDAMENTO DE VISITA (' || r.motivo || '). Cuide só da visita: sem card e sem fotos agora.'
    END;
  SELECT string_agg('o ' || x.codigo || ' em ' || to_char(x.quando AT TIME ZONE 'America/Manaus', 'DD/MM "às" HH24"h"MI')
                    || ' (para confirmar: pedir_visita com codigo ' || x.codigo || ' e quando '
                    || to_char(x.quando AT TIME ZONE 'America/Manaus', 'YYYY-MM-DD HH24:MI') || ')', '; ')
    INTO v_conf
    FROM nai_visita x WHERE x.corretor_id = ANY (nai_contato_irmaos(p_contato)) AND x.estado = 'confirmando';
  IF v_conf IS NOT NULL THEN
    v_txt := v_txt || ' VISITA ESPERANDO A CONFIRMAÇÃO DELE: ' || v_conf
             || '. Se ele confirmar (sim, isso, correto), chame pedir_visita com esses dados.';
  END IF;
  RETURN v_txt;
END;
$function$;

COMMIT;
