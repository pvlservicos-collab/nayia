-- =====================================================================
-- NAI -- 116: uma fonte de regras, e conferencia na saida (Tel, 24/09/2026)
--
-- Ele: "sinto que esta mal feito, reorganiza as regras e arquitetura para
-- adequar as regras, poe redundancias em tudo para nao ficar dando problema".
--
-- Ele esta certo. Ate aqui cada erro virou uma parede nova, e as regras
-- ficaram espalhadas por cinco lugares que falham sozinhos:
--     a porta          (quem ela atende)
--     a mente          (quem responde) -- e o texto dela mora no n8n
--     a busca          (tipo, finalidade, faixa)
--     o conferidor     (formato da resposta)
--     o portao da saida(parceria, pausa, espelho)
-- Quando a mente decidiu que "venda nao e locacao", nenhuma das outras
-- quatro percebeu. Quando o tipo se perdia, a lista saia misturada.
--
-- ============ O QUE MUDA ============
--
-- 1. UMA FONTE. `nai_pedido_do_turno` responde, de um jeito so, o que a
--    pessoa quer: tipo, finalidade, teto, bairro, imoveis citados, se e
--    cortesia, se esta oferecendo imovel. Quem precisar, pergunta a ela --
--    em vez de cada funcao adivinhar do seu jeito (era o que a memoria
--    `venda-x-locacao-e-implicito` ja avisava).
--
-- 2. REDUNDANCIA NA SAIDA. Mesmo que a busca erre, o modelo invente ou uma
--    regra nova quebre, NADA sai da caixa sem passar por
--    `nai_conferir_imoveis_da_saida`: card ou foto de imovel que nao bate
--    com o que ele pediu -- tipo errado, finalidade errada, parceiro, fora
--    do mercado -- e retirado antes de virar mensagem. E a mesma ideia da
--    parede da parceria, que ja salvou a gente.
--
-- 3. OS CASOS DO TEL. Uma bateria com os erros de verdade destes dias.
--    `SELECT * FROM nai_rodar_casos()` diz, em uma tela, se as regras dele
--    continuam de pe. E o que impede o proximo conserto de quebrar o
--    anterior.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- ====================================================================
-- 1. A FONTE UNICA
-- ====================================================================
CREATE OR REPLACE FUNCTION public.nai_pedido_do_turno(p_turno bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  t nai_turno; k nai_contato; v_texto text;
BEGIN
  SELECT * INTO t FROM nai_turno WHERE id = p_turno;
  IF t.id IS NULL THEN RETURN '{}'::jsonb; END IF;
  SELECT * INTO k FROM nai_contato WHERE id = t.contato_id;
  v_texto := coalesce(t.texto, '');

  RETURN jsonb_build_object(
    'turno',      p_turno,
    'texto',      v_texto,
    -- o que ele quer, lido da CONVERSA e nao so desta mensagem
    'tipo',       nai_tipo_da_conversa(t.contato_id, v_texto),
    'rotulo',     nai_rotulo_do_tipo(nai_tipo_da_conversa(t.contato_id, v_texto)),
    'negocio',    nai_negocio_da_conversa(t.contato_id, v_texto),
    'teto',       nay_maior_valor(v_texto),
    'imoveis',    to_jsonb(nai_imoveis_pedidos(v_texto, coalesce(k.telefone, ''))),
    -- o que a mensagem E
    'cortesia',   nai_e_so_cortesia(v_texto),
    'oferta',     nai_oferece_imovel(v_texto),
    'link',       nai_e_link_de_produto(v_texto),
    'pede_lista', nai_pede_os_valores(v_texto),
    'sem_bairro', nai_sem_preferencia_de_bairro(v_texto) OR nai_e_a_cidade(v_texto),
    'de_imovel',  nai_e_assunto_de_locacao(v_texto)
  );
END;
$function$;

-- ====================================================================
-- 2. A CONFERENCIA DA SAIDA -- a rede embaixo de tudo
-- ====================================================================
CREATE OR REPLACE FUNCTION public.nai_conferir_imoveis_da_saida(p_turno bigint)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  p jsonb; v_tipo text; v_negocio text; n int := 0; r record;
BEGIN
  p := nai_pedido_do_turno(p_turno);
  v_tipo    := p->>'tipo';
  v_negocio := p->>'negocio';

  FOR r IN
    SELECT s.id, s.codigo, i.tipo, i.valor_venda, i.valor_aluguel, i.e_parceiro,
           nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site) AS no_mercado
      FROM nai_saida s JOIN imoveis i ON i.codigo = s.codigo
     WHERE s.turno_id = p_turno AND s.estado = 'pendente' AND s.codigo IS NOT NULL
  LOOP
    -- PARCEIRO E FORA DO MERCADO NUNCA SAEM. Ja ha parede no gatilho da
    -- caixa; esta e a segunda, de proposito.
    IF coalesce(r.e_parceiro, false) OR NOT r.no_mercado THEN
      UPDATE nai_saida SET estado = 'bloqueado',
                           bloqueio = CASE WHEN r.e_parceiro THEN 'parceiro' ELSE 'fora do mercado' END
       WHERE id = r.id;
      n := n + 1;
      CONTINUE;
    END IF;

    -- TIPO: casa nao vira apartamento nem no ultimo metro.
    IF v_tipo IS NOT NULL AND r.tipo IS NOT NULL AND r.tipo NOT ILIKE v_tipo THEN
      UPDATE nai_saida SET estado = 'bloqueado',
                           bloqueio = 'tipo errado: ele pediu ' || coalesce(p->>'rotulo', v_tipo)
       WHERE id = r.id;
      n := n + 1;
      CONTINUE;
    END IF;

    -- FINALIDADE: quem pede venda nao recebe so-aluguel, e vice-versa.
    IF v_negocio = 'venda' AND coalesce(r.valor_venda, 0) = 0 THEN
      UPDATE nai_saida SET estado = 'bloqueado', bloqueio = 'ele pediu venda e este so tem aluguel'
       WHERE id = r.id;
      n := n + 1;
      CONTINUE;
    END IF;
    IF v_negocio = 'locacao' AND coalesce(r.valor_aluguel, 0) = 0 THEN
      UPDATE nai_saida SET estado = 'bloqueado', bloqueio = 'ele pediu locação e este só tem venda'
       WHERE id = r.id;
      n := n + 1;
    END IF;
  END LOOP;

  IF n > 0 THEN
    PERFORM nai_anotar(p_turno, 23, 'conferencia_da_saida', 'mudou',
                       n || ' mensagens retiradas: imóvel que não bate com o pedido');
  END IF;
  RETURN n;
END;
$function$;

-- ligada no fim da montagem, antes do espacamento
DO $mig$
DECLARE v_def text; v_alvo text;
BEGIN
  v_def := pg_get_functiondef('nai_enfileirar_resposta'::regproc);
  IF position('nai_conferir_imoveis_da_saida' IN v_def) > 0 THEN
    RAISE NOTICE 'a conferencia da saida ja esta ligada'; RETURN;
  END IF;
  v_alvo := '  PERFORM nai_fila_dos_outros_imoveis(p_turno, p_escreveu);';
  IF position(v_alvo IN v_def) = 0 THEN RAISE EXCEPTION 'nao achei a fila da 114'; END IF;
  EXECUTE replace(v_def, v_alvo, v_alvo || E'\n\n'
    || '  -- A REDE EMBAIXO DE TUDO (116): imovel que nao bate com o pedido nao' || E'\n'
    || '  -- vira mensagem, venha o erro da busca, do modelo ou de uma regra nova.' || E'\n'
    || '  PERFORM nai_conferir_imoveis_da_saida(p_turno);');
  RAISE NOTICE 'conferencia da saida ligada';
END $mig$;

-- ====================================================================
-- 3. OS CASOS DO TEL -- a bateria que nao deixa regredir
-- ====================================================================
CREATE TABLE IF NOT EXISTS nai_caso (
  id        serial PRIMARY KEY,
  quando    date NOT NULL DEFAULT current_date,
  quem      text,
  frase     text NOT NULL,
  pergunta  text NOT NULL,   -- qual funcao responde
  esperado  text NOT NULL,
  regra     text NOT NULL,   -- a regra do Tel, em uma linha
  ativo     boolean NOT NULL DEFAULT true
);

CREATE OR REPLACE FUNCTION public.nai_rodar_casos()
 RETURNS TABLE(passou boolean, regra text, frase text, esperado text, deu text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE c record; v text;
BEGIN
  FOR c IN SELECT * FROM nai_caso WHERE ativo ORDER BY id LOOP
    v := CASE c.pergunta
      WHEN 'tipo'       THEN coalesce(nai_tipo_pedido(c.frase), '-')
      WHEN 'tipo_canon' THEN coalesce(nai_tipo_canonico(c.frase), '-')
      WHEN 'negocio'    THEN coalesce(nay_negocio_pedido(c.frase), '-')
      WHEN 'cortesia'   THEN nai_e_so_cortesia(c.frase)::text
      WHEN 'oferta'     THEN nai_oferece_imovel(c.frase)::text
      WHEN 'link'       THEN nai_e_link_de_produto(c.frase)::text
      WHEN 'pede_lista' THEN nai_pede_os_valores(c.frase)::text
      WHEN 'sem_bairro' THEN nai_sem_preferencia_de_bairro(c.frase)::text
      WHEN 'de_imovel'  THEN nai_e_assunto_de_locacao(c.frase)::text
      WHEN 'imoveis'    THEN nai_imoveis_pedidos(c.frase, '')::text
      WHEN 'nomes'      THEN nai_corrigir_nomes(c.frase)
      WHEN 'valor'      THEN coalesce(nay_maior_valor(c.frase)::text, '-')
      ELSE '(pergunta desconhecida: ' || c.pergunta || ')'
    END;
    passou := (v = c.esperado);
    regra := c.regra; frase := c.frase; esperado := c.esperado; deu := v;
    RETURN NEXT;
  END LOOP;
END;
$function$;

-- Os casos sao os ERROS DE VERDADE destes dias, um por regra dele.
INSERT INTO nai_caso (quem, frase, pergunta, esperado, regra) VALUES
 ('Geina 22/09',   'essas mediações de casa para aluguel ate 4 mil', 'tipo', 'Casa%',
  'casa não vira apartamento'),
 ('Tel 22/09',     'tenho cliente para 3 quartos ate 700 mil no aleixo', 'negocio', 'venda',
  'acima de 100 mil é venda'),
 ('Tel 22/09',     'o cliente paga até 3.500 de aluguel', 'negocio', 'locacao',
  'aluguel dito é locação'),
 ('Deborah 23/09', 'não teria preferência por bairro', 'sem_bairro', 'true',
  'sem preferência de bairro não repete a pergunta'),
 ('João Luiz 23/09','Qual são os valores que vc tem?', 'pede_lista', 'true',
  'quem pede os valores recebe a lista, não a pergunta de faixa'),
 ('Luiz Bastos 22/09','Oi Nay, eu tenho um Living Confort também Se quiser te envio', 'oferta', 'true',
  'oferta de imóvel é da secretária, ela não faz cadastro sozinha'),
 ('Tel 22/09',     'Posso anunciar os imóveis de vocês?', 'oferta', 'false',
  'pode publicar sim: anunciar NOSSO imóvel não é oferta'),
 ('Amanda 23/09',  'Esse apartamento ainda está disponível? https://wa.me/p/2711225/5592', 'link', 'true',
  'link do catálogo vai para o Tel'),
 ('Marcio 24/09',  'Ok', 'cortesia', 'true',
  'cortesia não troca de atendente'),
 ('Marcio 24/09',  'ok, e o 5611?', 'cortesia', 'false',
  'cortesia com pergunta junto não é cortesia'),
 ('Marina 23/09',  'vc tem alguma casa terrea na Marina Rio Belo? venda', 'de_imovel', 'true',
  'venda é assunto de imóvel, não da secretária'),
 ('Geina 23/09',   'Alvorada, Bom Pedro, né? Essas mediações de casa', 'nomes',
  'Alvorada, Dom Pedro, né? Essas mediações de casa',
  'nome torto do áudio vira o nome certo'),
 ('Lily 22/09',    'o aquarelli ainda ta valendo?', 'nomes', 'o acquarelle ainda ta valendo?',
  'condomínio escrito de ouvido é reconhecido'),
 ('Marcio 24/09',  'apartamentos, casas e imóveis em prédios', 'tipo_canon', '-',
  'a carteira do corretor não é um tipo de imóvel'),
 ('Andre 23/09',   'pode ver se aina está disponível esse Arezzo? Condomínio Residencial Conquista Tarumã',
  'imoveis', '{5718,5722}', 'pediu dois, recebe os dois')
ON CONFLICT DO NOTHING;

COMMIT;

SELECT CASE WHEN passou THEN 'ok ' ELSE 'FALHOU' END AS estado, regra, esperado, deu
  FROM nai_rodar_casos() ORDER BY passou, regra;
