-- =====================================================================
-- NAI -- 120b: o pedido e so dele (24/09/2026)
--
-- O conserto dos tres casos vermelhos da 120, mais a porta que faltava na
-- conferencia da saida. Quatro mudancas, cada uma com chave em `nai_config`
-- -- o Tel desliga qualquer uma sem deploy, e o rollback esta no fim.
--
-- 1. A OFERTA DELE NAO ENSINA O QUE ELE PROCURA. `nai_tipo_da_conversa` e
--    `nai_negocio_da_conversa` liam a conversa inteira para tras. Liam
--    tambem o anuncio que o proprio corretor mandou -- e "3 Dormitorios ...
--    sala" virou "ele procura sala". A regra agora ignora a fala que e
--    oferta. Chave: `pedido_ignora_oferta`.
--
-- 2. A REGRA VIROU FUNCAO PURA. `nai_tipo_das_falas(text[])` decide; a
--    `nai_tipo_da_conversa` so junta as falas do banco e chama. E por isso
--    que a bateria consegue testar uma CONVERSA e nao so uma frase.
--
-- 3. IMOVEL PEDIDO PELO NOME PASSA. A conferencia barrava por tipo mesmo o
--    imovel que ele citou -- foi o que apagou o Park Golf. O passe vale so
--    para tipo e finalidade: parceiro e fora do mercado continuam parede
--    fechada, sem excecao. Chave: `conferencia_passe_citado`.
--
-- 4. TEXTO NAO SAI PROMETENDO O QUE FOI RETIRADO. Se a conferencia tirou
--    todos os imoveis, a frase "segue abaixo" ia sozinha. Agora ela e
--    retirada junto e o Tel e avisado -- sem parar o chat (a licao da 111b).
--    Chave: `conferencia_barra_texto_orfao`.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO nai_config (chave, valor) VALUES
  ('pedido_ignora_oferta',          'sim'),
  ('conferencia_passe_citado',      'sim'),
  ('conferencia_barra_texto_orfao', 'sim')
ON CONFLICT (chave) DO NOTHING;

-- ====================================================================
-- 1 e 2. A REGRA, PURA
-- ====================================================================
CREATE OR REPLACE FUNCTION public.nai_tipo_das_falas(p_falas text[])
 RETURNS text LANGUAGE sql STABLE AS $function$
  SELECT nai_tipo_pedido(f.fala)
    FROM unnest(coalesce(p_falas, '{}'::text[])) WITH ORDINALITY AS f(fala, pos)
   WHERE nai_tipo_pedido(f.fala) IS NOT NULL
     -- a fala em que ele OFERECE um imovel dele nao conta
     AND NOT (nai_cfg('pedido_ignora_oferta', 'sim') = 'sim'
              AND nai_oferece_imovel(f.fala))
   ORDER BY f.pos LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION public.nai_negocio_das_falas(p_falas text[])
 RETURNS text LANGUAGE sql STABLE AS $function$
  SELECT nay_negocio_pedido(f.fala)
    FROM unnest(coalesce(p_falas, '{}'::text[])) WITH ORDINALITY AS f(fala, pos)
   WHERE nay_negocio_pedido(f.fala) IS NOT NULL
     AND NOT (nai_cfg('pedido_ignora_oferta', 'sim') = 'sim'
              AND nai_oferece_imovel(f.fala))
   ORDER BY f.pos LIMIT 1;
$function$;

-- As falas: a de agora primeiro, depois os turnos, depois as mensagens
-- antigas (conversa que nunca virou turno). As janelas sao as mesmas de
-- antes -- 30 dias de turno, 60 de mensagem, 24h para a finalidade.
CREATE OR REPLACE FUNCTION public.nai_tipo_da_conversa(p_contato bigint, p_texto text)
 RETURNS text LANGUAGE sql STABLE AS $function$
  SELECT nai_tipo_das_falas(
    array[coalesce(p_texto, '')]
    || coalesce((SELECT array_agg(x.texto ORDER BY x.id DESC) FROM (
         SELECT t.id, t.texto FROM nai_turno t
          WHERE t.contato_id = p_contato AND t.criado_em > now() - interval '30 days'
            AND nai_tipo_pedido(t.texto) IS NOT NULL
          ORDER BY t.id DESC LIMIT 8) x), '{}'::text[])
    || coalesce((SELECT array_agg(y.texto ORDER BY y.id DESC) FROM (
         SELECT m.id, m.texto FROM mensagens m
          WHERE nai_chave(m.telefone) = ANY (
                  SELECT c.chave FROM nai_contato c WHERE c.id = ANY (nai_contato_irmaos(p_contato)))
            AND m.direcao = 'recebida' AND m.criada_em > now() - interval '60 days'
            AND nai_tipo_pedido(m.texto) IS NOT NULL
          ORDER BY m.id DESC LIMIT 8) y), '{}'::text[]));
$function$;

CREATE OR REPLACE FUNCTION public.nai_negocio_da_conversa(p_contato bigint, p_texto text)
 RETURNS text LANGUAGE sql STABLE AS $function$
  SELECT nai_negocio_das_falas(
    array[coalesce(p_texto, '')]
    || coalesce((SELECT array_agg(x.texto ORDER BY x.id DESC) FROM (
         SELECT t.id, t.texto FROM nai_turno t
          WHERE t.contato_id = p_contato AND t.criado_em > now() - interval '24 hours'
            AND nay_negocio_pedido(t.texto) IS NOT NULL
          ORDER BY t.id DESC LIMIT 8) x), '{}'::text[]));
$function$;

-- ====================================================================
-- 3 e 4. A CONFERENCIA DA SAIDA
-- ====================================================================
CREATE OR REPLACE FUNCTION public.nai_conferir_imoveis_da_saida(p_turno bigint)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE
  p jsonb; v_tipo text; v_negocio text; n int := 0; r record;
  v_citados int[]; v_sobrou boolean; v_texto text;
  v_promessa text := '(segue|abaixo|logo mais|vou te (mandar|enviar)|te envio|te mando|encontrei|separei|essas? (opç|sugest)|seguem)';
BEGIN
  p := nai_pedido_do_turno(p_turno);
  v_tipo    := p->>'tipo';
  v_negocio := p->>'negocio';

  -- OS IMOVEIS QUE ELE CITOU pelo codigo ou pelo nome do condominio. Quem
  -- ele pediu pelo nome, ele recebe.
  SELECT coalesce(array_agg(e::int), '{}'::int[]) INTO v_citados
    FROM jsonb_array_elements_text(coalesce(p->'imoveis', '[]'::jsonb)) e
   WHERE e ~ '^[0-9]+$';

  FOR r IN
    SELECT s.id, s.codigo, i.tipo, i.valor_venda, i.valor_aluguel, i.e_parceiro,
           nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site) AS no_mercado
      FROM nai_saida s JOIN imoveis i ON i.codigo = s.codigo
     WHERE s.turno_id = p_turno AND s.estado = 'pendente' AND s.codigo IS NOT NULL
  LOOP
    -- PARCEIRO E FORA DO MERCADO NUNCA SAEM -- nem citados pelo nome. Esta
    -- parede nao tem excecao, de proposito.
    IF coalesce(r.e_parceiro, false) OR NOT r.no_mercado THEN
      UPDATE nai_saida SET estado = 'bloqueado',
                           bloqueio = CASE WHEN r.e_parceiro THEN 'parceiro' ELSE 'fora do mercado' END
       WHERE id = r.id;
      n := n + 1;
      CONTINUE;
    END IF;

    -- O PASSE DO CITADO. Ele perguntou do Park Golf pelo nome: o tipo que a
    -- conversa dizia nao manda mais que o imovel que ele nomeou.
    IF nai_cfg('conferencia_passe_citado', 'sim') = 'sim'
       AND r.codigo = ANY (v_citados) THEN
      PERFORM nai_anotar(p_turno, 23, 'passe_do_citado', 'passou',
                         'ele pediu o ' || r.codigo || ' pelo nome');
      CONTINUE;
    END IF;

    -- TIPO: casa nao vira apartamento nem no ultimo metro.
    IF v_tipo IS NOT NULL AND r.tipo IS NOT NULL AND r.tipo NOT ILIKE v_tipo THEN
      UPDATE nai_saida SET estado = 'bloqueado',
                           bloqueio = 'tipo errado: ele pediu ' || lower(nai_rotulo_do_tipo(v_tipo))
       WHERE id = r.id;
      n := n + 1;
      CONTINUE;
    END IF;

    -- FINALIDADE: quem procura compra nao recebe aluguel.
    IF v_negocio = 'venda' AND coalesce(r.valor_venda, 0) <= 0 THEN
      UPDATE nai_saida SET estado = 'bloqueado', bloqueio = 'ele procura venda'
       WHERE id = r.id; n := n + 1; CONTINUE;
    END IF;
    IF v_negocio = 'locacao' AND coalesce(r.valor_aluguel, 0) <= 0 THEN
      UPDATE nai_saida SET estado = 'bloqueado', bloqueio = 'ele procura locação'
       WHERE id = r.id; n := n + 1; CONTINUE;
    END IF;
  END LOOP;

  -- O TEXTO ORFAO. Se nao sobrou imovel nenhum, a frase que prometia os
  -- imoveis nao pode sair sozinha ("segue abaixo" sem nada abaixo).
  IF n > 0 AND nai_cfg('conferencia_barra_texto_orfao', 'sim') = 'sim' THEN
    SELECT EXISTS (SELECT 1 FROM nai_saida
                    WHERE turno_id = p_turno AND estado = 'pendente' AND codigo IS NOT NULL)
      INTO v_sobrou;
    IF NOT v_sobrou THEN
      SELECT string_agg(left(texto, 200), ' / ') INTO v_texto
        FROM nai_saida
       WHERE turno_id = p_turno AND estado = 'pendente' AND codigo IS NULL
         AND texto ~* v_promessa;
      IF v_texto IS NOT NULL THEN
        UPDATE nai_saida SET estado = 'bloqueado', bloqueio = 'texto sem o imóvel'
         WHERE turno_id = p_turno AND estado = 'pendente' AND codigo IS NULL
           AND texto ~* v_promessa;
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

COMMIT;

SELECT passou, regra, esperado, deu FROM nai_rodar_casos() ORDER BY passou;

-- =====================================================================
-- COMO DESFAZER
--   UPDATE nai_config SET valor='nao' WHERE chave='pedido_ignora_oferta';
--   UPDATE nai_config SET valor='nao' WHERE chave='conferencia_passe_citado';
--   UPDATE nai_config SET valor='nao' WHERE chave='conferencia_barra_texto_orfao';
-- As tres chaves voltam o comportamento exato de antes, sem deploy. Para
-- desfazer o codigo, reaplicar a 116 (fonte unica + conferencia) -- as
-- funcoes `*_das_falas` ficam sem uso e nao atrapalham.
-- =====================================================================
