-- =====================================================================
-- NAI -- 120e: o passe e so para quem ele apontou (24/09/2026)
--
-- DOIS BURACOS, um antigo e um que a 120b abriu.
--
-- 1. O PASSE LARGO DEMAIS (buraco novo, meu). A 120b deu passe na
--    conferencia da saida para "o imovel que ele citou". So que
--    `nai_imoveis_pedidos` nao devolve so o imovel apontado: ele tambem
--    expande nome de lugar. Medido:
--
--        "esse Park Golf so tem ar-condicionado?"  -> {5728}
--        "tem alguma casa pra venda no Itapuranga?" -> 10 codigos
--
--    Com o passe como estava, o segundo caso soltaria um "Lote em
--    Condominio" para quem pediu CASA -- que e exatamente o erro que a
--    conferencia existe para impedir, e que ela tinha barrado certo.
--
--    A regra agora: passe so quando ele apontou para UM imovel, nao para um
--    bairro inteiro. O teto esta em `nai_config.passe_citado_ate` (2, para
--    caber "me manda o 5718 e o 5722").
--
-- 2. "PONTO DE REFERENCIA" (o que sobrou da 120d). "Tem um ponto de
--    referencia dela?" ainda casava com Loja, pelo verbo. Ponto de
--    referencia, de onibus e de taxi saem da conta.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO nai_config (chave, valor) VALUES ('passe_citado_ate', '2')
ON CONFLICT (chave) DO NOTHING;

-- ---- os casos, antes do conserto ---------------------------------------
INSERT INTO nai_caso (quem, frase, pergunta, esperado, regra) VALUES
 ('Aleixo 90d', 'Tem um ponto de referência dela ou localização?', 'tipo', '-',
  'ponto de referência não é ponto comercial, nem com verbo antes'),
 ('Park Golf 24/09', 'Ei Nair, esse Park Golf só tem ar-condicionado?', 'passe', 'true',
  'imóvel apontado pelo nome tem passe na conferência'),
 ('Itapuranga 24/09', 'Tem alguma casa pra venda no Itapuranga?', 'passe', 'false',
  'nome de lugar não dá passe: bairro inteiro não é imóvel apontado'),
 ('Tel', 'me manda o 5718 e o 5722', 'passe', 'true',
  'dois códigos ditos na mão continuam com passe');

CREATE OR REPLACE FUNCTION public.nai_passe_do_citado(p_citados int[])
 RETURNS boolean
 LANGUAGE sql STABLE
AS $function$
  SELECT nai_cfg('conferencia_passe_citado', 'sim') = 'sim'
     AND coalesce(array_length(p_citados, 1), 0) BETWEEN 1
         AND coalesce(nullif(nai_cfg('passe_citado_ate', '2'), ''), '2')::int;
$function$;

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
      WHEN 'anuncio'    THEN nai_e_anuncio_dele(c.frase)::text
      WHEN 'link'       THEN nai_e_link_de_produto(c.frase)::text
      WHEN 'pede_lista' THEN nai_pede_os_valores(c.frase)::text
      WHEN 'sem_bairro' THEN nai_sem_preferencia_de_bairro(c.frase)::text
      WHEN 'de_imovel'  THEN nai_e_assunto_de_locacao(c.frase)::text
      WHEN 'imoveis'    THEN nai_imoveis_pedidos(c.frase, '')::text
      WHEN 'passe'      THEN nai_passe_do_citado(nai_imoveis_pedidos(c.frase, ''))::text
      WHEN 'nomes'      THEN nai_corrigir_nomes(c.frase)
      WHEN 'valor'      THEN coalesce(nay_maior_valor(c.frase)::text, '-')
      WHEN 'tipo_conversa'    THEN coalesce(nai_tipo_das_falas(string_to_array(c.frase, ' || ')), '-')
      WHEN 'negocio_conversa' THEN coalesce(nai_negocio_das_falas(string_to_array(c.frase, ' || ')), '-')
      ELSE '(pergunta desconhecida: ' || c.pergunta || ')'
    END;
    passou := (v = c.esperado);
    regra := c.regra; frase := c.frase; esperado := c.esperado; deu := v;
    RETURN NEXT;
  END LOOP;
END;
$function$;

\echo '=== ANTES do conserto (tem que ter vermelho) ==='
SELECT passou, regra, esperado, deu FROM nai_rodar_casos() WHERE NOT passou;

-- ---- 2. ponto de referencia sai da conta -------------------------------
CREATE OR REPLACE FUNCTION public.nai_tipo_pedido(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- AS RESIDENCIAIS bastam a palavra. AS COMERCIAIS exigem a marca
  -- ("sala comercial") ou o verbo do pedido ("alugar uma sala") -- medido:
  -- sem isso, 123 de 127 leituras eram falsas (120d). E "ponto de
  -- referencia/onibus/taxi" nunca e imovel (120e).
  SELECT CASE
    WHEN s ~ '\m(casa|casas|sobrado)\M'                     THEN 'Casa%'
    WHEN s ~ '\m(apartamento|apartamentos|apto|aptos|ap)\M' THEN 'Apartamento%'
    WHEN s ~ '\m(cobertura|coberturas)\M'                   THEN 'Cobertura%'
    WHEN s ~ '\m(flat|flats)\M'                             THEN 'Flat%'
    WHEN s ~ '\m(salas?|conjuntos?)\s+(comercial|comerciais)\M'
      OR   s ~ (v || 'salas?\M')                            THEN 'Sala%'
    WHEN s ~ '\m(lojas?|pontos?)\s+(comercial|comerciais)\M'
      OR   (s ~ (v || '(lojas?|pontos?)\M')
            AND NOT s ~ '\mpontos?\s+de\s+(referencia|onibus|taxi|encontro)\M')
                                                            THEN 'Loja%'
    WHEN s ~ '\m(galpao|galpoes)\M'
      OR   s ~ (v || 'depositos?\M')                        THEN 'Galp%'
    WHEN s ~ '\m(terreno|terrenos|lote|lotes)\M'            THEN 'Lote%'
    WHEN s ~ '\m(chacara|chacaras|sitio)\M'                 THEN 'Ch%'
    WHEN s ~ (v || 'predios?\M')                            THEN 'Pr%dio%'
  END
  FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s,
               '\m(alug\w*|loc\w*|procur\w*|quer\w*|busc\w*|precis\w*|tem|teria|tenho cliente p\w*|interesse em)\s+(\w+\s+){0,2}' AS v) x;
$function$;

-- ---- 1. o passe estreito na conferencia --------------------------------
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

\echo '=== DEPOIS do conserto ==='
SELECT count(*) FILTER (WHERE passou) || ' de ' || count(*) AS bateria FROM nai_rodar_casos();
SELECT passou, regra, esperado, deu FROM nai_rodar_casos() WHERE NOT passou;

COMMIT;

-- =====================================================================
-- COMO DESFAZER
--   UPDATE nai_config SET valor='0'   WHERE chave='passe_citado_ate';     -- desliga o passe
--   UPDATE nai_config SET valor='999' WHERE chave='passe_citado_ate';     -- passe largo (120b)
--   UPDATE nai_config SET valor='nao' WHERE chave='conferencia_passe_citado';
-- =====================================================================
