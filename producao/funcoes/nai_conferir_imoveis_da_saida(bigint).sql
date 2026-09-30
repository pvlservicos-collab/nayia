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
