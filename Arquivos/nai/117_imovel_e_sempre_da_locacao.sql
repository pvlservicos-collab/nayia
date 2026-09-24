-- =====================================================================
-- NAI -- 117: pediu imovel, quem responde e a de imoveis (Tel, 24/09/2026)
--
-- A REDUNDANCIA que faltava na decisao. A mente e um modelo lendo um texto:
-- ela erra, e errou -- mandou para a secretaria quem perguntava de imovel,
-- com motivos como "VENDA DE IMOVEL NAO E LOCACAO".
--
-- O texto dela sera corrigido no fluxo. Mas texto de prompt nao e garantia:
-- se amanha alguem reescrever, o erro volta. Entao a decisao passa a ter uma
-- CONFERENCIA no banco, que e onde as regras do Tel moram:
--
--   Falou de imovel (codigo, condominio, bairro, foto, valor, visita,
--   disponibilidade, venda, locacao)?
--     - e NAO esta oferecendo imovel dele
--     - e NAO e link de catalogo
--   -> quem responde e a de imoveis, diga a mente o que disser.
--
-- As tres excecoes continuam de pe, porque sao regras dele tambem: oferta de
-- imovel e da secretaria (97/99), link de catalogo vai para o Tel (111), e
-- cadastro em andamento gruda (99e).
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION public.nai_mente_registrar(p_turno bigint, p_atendente text,
                                                      p_motivo text, p_por text)
 RETURNS text LANGUAGE plpgsql
AS $function$
DECLARE v_at text; v_motivo text; v_contato bigint; v_ficha bigint;
        v_texto text; v_antes text; v_por text; p jsonb;
BEGIN
  v_at := CASE WHEN lower(coalesce(p_atendente, '')) = 'secretaria' THEN 'secretaria' ELSE 'locacao' END;
  v_motivo := left(coalesce(p_motivo, ''), 300);
  v_por := coalesce(p_por, 'mente');

  SELECT contato_id, texto INTO v_contato, v_texto FROM nai_turno WHERE id = p_turno;
  p := nai_pedido_do_turno(p_turno);

  -- 1. CORTESIA SEGUE COM QUEM JA ESTAVA (115).
  IF (p->>'cortesia')::boolean THEN
    SELECT t.atendente INTO v_antes FROM nai_turno t
     WHERE t.contato_id = v_contato AND t.id < p_turno
       AND t.criado_em > now() - interval '6 hours'
     ORDER BY t.id DESC LIMIT 1;
    IF v_antes IS NOT NULL AND v_antes <> v_at THEN
      v_at := v_antes; v_motivo := 'cortesia: segue com quem já atendia'; v_por := 'cola';
    END IF;
  END IF;

  -- 2. PEDIU IMOVEL, E DA DE IMOVEIS (117). A conferencia sobre a mente.
  IF v_at = 'secretaria'
     AND (p->>'de_imovel')::boolean
     AND NOT (p->>'oferta')::boolean
     AND NOT (p->>'link')::boolean THEN
    v_at := 'locacao';
    v_motivo := 'fala de imóvel: é da de imóveis (a mente disse: ' || left(v_motivo, 80) || ')';
    v_por := 'regra';
  END IF;

  -- 3. A COLA DO CADASTRO (99e): ficha aberta manda em tudo.
  SELECT n.id INTO v_ficha FROM nai_imovel_novo n
   WHERE n.contato_id = v_contato AND n.situacao = 'colhendo'
     AND n.criado_em > now() - interval '24 hours'
   ORDER BY n.id DESC LIMIT 1;
  IF v_ficha IS NOT NULL AND nai_secretaria_ligada() THEN
    v_at := 'secretaria'; v_motivo := 'cadastro em andamento (ficha ' || v_ficha || ')'; v_por := 'cola';
  END IF;

  -- 4. OFERTA E LINK SAO DELA, sempre (97, 111).
  IF ((p->>'oferta')::boolean OR (p->>'link')::boolean) AND nai_secretaria_ligada() THEN
    v_at := 'secretaria';
    v_motivo := CASE WHEN (p->>'link')::boolean THEN 'link de catálogo' ELSE 'está oferecendo imóvel' END;
    v_por := 'regra';
  END IF;

  IF v_at = 'secretaria' AND NOT nai_secretaria_ligada() THEN
    v_at := 'locacao'; v_motivo := 'secretaria desligada';
  END IF;

  UPDATE nai_turno SET atendente = v_at WHERE id = p_turno;
  INSERT INTO nai_mente (turno_id, atendente, motivo, por) VALUES (p_turno, v_at, v_motivo, v_por);
  PERFORM nai_anotar(p_turno, 4, 'mente_mestra', 'mudou',
                     'quem responde: ' || v_at || coalesce(' (' || v_motivo || ')', ''));
  RETURN v_at;
END;
$function$;

COMMIT;

-- As quatro que a mente errou: com a conferencia, todas voltam para imoveis.
SELECT left(t, 48) AS a_mensagem,
       nai_e_assunto_de_locacao(t) AS fala_de_imovel,
       nai_oferece_imovel(t) AS e_oferta,
       CASE WHEN nai_e_assunto_de_locacao(t) AND NOT nai_oferece_imovel(t)
            THEN 'IMOVEIS' ELSE 'secretaria' END AS quem_responde
  FROM unnest(ARRAY[
    'vc tem alguma casa terrea na Marina Rio Belo? venda',
    'Voce tem opcao de casa pra venda no Itapuranga',
    'Nay, tem alguma coisa no Acquarelle de 2 quartos?',
    'Tenho vivenda verde p locação tbm se precisar. 110m2',
    'Bom dia Como funciona pra você anunciar ? Tenho vista do sol'
  ]) t;
