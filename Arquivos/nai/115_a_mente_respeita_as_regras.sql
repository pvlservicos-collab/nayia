-- =====================================================================
-- NAI -- 115: a mente para de entregar imovel para a secretaria,
--             e o tipo vem da conversa inteira (Tel, 24/09/2026)
--
-- Ele: "ai eu respondo e do nada ela se mete na conversa e responde errado
-- ainda, ele esta procurando casa ela manda casa e apartamento tudo junto. la
-- no 8523 2884, revisa se a ia mestre que le a conversa ta respeitando as
-- regras do tel".
--
-- ============ O QUE A REVISAO ACHOU ============
-- Em 137 decisoes, 58 foram para a secretaria -- 42%. Lendo uma a uma, tem
-- imovel no meio:
--
--   "vc tem alguma casa terrea na Marina Rio Belo? venda"
--       -> secretaria, motivo "informacoes sobre venda de imoveis"
--   "Voce tem opcao de casa pra venda no Itapuranga"
--       -> secretaria, motivo "VENDA DE IMOVEL NAO E LOCACAO"
--   "tem alguma coisa no Acquarelle"
--       -> secretaria, "pedido de informacoes sobre imovel para venda"
--
-- A culpa e do texto que eu escrevi para a mente: chamei o caminho de
-- "LOCACAO". O modelo leu o nome e concluiu que VENDA nao e dali -- quando a
-- Nay atende venda desde 22/09 (98). Isso se conserta no fluxo, no texto da
-- mente; aqui fica a outra metade.
--
-- ============ 1. CORTESIA NAO MUDA DE ATENDENTE ============
--   "Ok" -> secretaria, "resposta nao solicitada"
--   "Oii" -> secretaria, "atendimento geral sobre a imobiliaria"
--   "Obrigado! Boa Noite." -> secretaria, "saudacao ou recado pessoal"
-- Lidos sozinhos, estao certos -- "Ok" nao e assunto de imovel. Mas "Ok" no
-- meio de uma conversa de imovel e a MESMA conversa, e trocar de atendente
-- ali e exatamente "do nada ela se mete na conversa".
-- Agora cortesia curta segue com quem ja estava atendendo.
--
-- ============ 2. O TIPO VEM DA CONVERSA, NAO DAS ULTIMAS 24H ============
-- O caso do (92) 98523-2884. Hoje ele mandou audio: "Ai tem alguma locacao na
-- Cidade Nova?" -- sem dizer "casa". Ela respondeu com a Casa 5736 E dois
-- apartamentos "aqui perto".
-- Ele e cliente de CASA: em 11/09 perguntou "A casa do nova cidade ainda esta
-- disponivel?". So que aquilo nunca virou TURNO -- era outro fluxo --, e a
-- memoria de tipo so olhava turnos das ultimas 24h. Agora olha tambem as
-- MENSAGENS dele, ate 60 dias atras.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- 1 ------------------------------------------------- SO CORTESIA
CREATE OR REPLACE FUNCTION public.nai_e_so_cortesia(p_texto text)
 RETURNS boolean LANGUAGE sql IMMUTABLE
AS $function$
  -- Mensagem curta que nao abre assunto: agradecimento, confirmacao,
  -- saudacao solta. Se tiver QUALQUER palavra de assunto junto, nao e
  -- cortesia -- "ok, e o 5611?" continua sendo pergunta.
  SELECT length(s) <= 40
     AND s ~ ('^(ok|okay|blz|beleza|certo|isso|sim|nao|show|otimo|perfeito|combinado|'
           || 'obrigad[oa]|obg|vlw|valeu|de nada|imagina|bom dia|boa tarde|boa noite|'
           || 'oi|ola|oii+|opa|eae|e ai|tudo bem|tudo bom|entendi|entendido|ta bom|'
           || 'ta certo|tamo junto|abraco|abs|att|falou|até|ate mais|👍|🙏|👏)[\s!.,;:)]*$')
    FROM (SELECT btrim(lower(unaccent(coalesce(p_texto, '')))) AS s) x;
$function$;

-- 2 ---------------------- A MENTE NAO TROCA DE ATENDENTE NUMA CORTESIA
CREATE OR REPLACE FUNCTION public.nai_mente_registrar(p_turno bigint, p_atendente text,
                                                      p_motivo text, p_por text)
 RETURNS text LANGUAGE plpgsql
AS $function$
DECLARE v_at text; v_motivo text; v_contato bigint; v_ficha bigint;
        v_texto text; v_antes text; v_por text;
BEGIN
  v_at := CASE WHEN lower(coalesce(p_atendente, '')) = 'secretaria' THEN 'secretaria' ELSE 'locacao' END;
  v_motivo := left(coalesce(p_motivo, ''), 300);
  v_por := coalesce(p_por, 'mente');

  SELECT contato_id, texto INTO v_contato, v_texto FROM nai_turno WHERE id = p_turno;

  -- CORTESIA SEGUE COM QUEM JA ESTAVA (115). "Ok", "Obrigado", "Boa noite"
  -- no meio de uma conversa nao trocam o atendente -- trocar ali e o "do
  -- nada ela se mete na conversa" que o Tel viu.
  IF nai_e_so_cortesia(v_texto) THEN
    SELECT t.atendente INTO v_antes
      FROM nai_turno t
     WHERE t.contato_id = v_contato AND t.id < p_turno
       AND t.criado_em > now() - interval '6 hours'
     ORDER BY t.id DESC LIMIT 1;
    IF v_antes IS NOT NULL AND v_antes <> v_at THEN
      v_at := v_antes;
      v_motivo := 'cortesia: segue com quem já atendia';
      v_por := 'cola';
    END IF;
  END IF;

  -- A COLA DO CADASTRO (99e): ficha aberta manda em tudo.
  SELECT n.id INTO v_ficha
    FROM nai_imovel_novo n
   WHERE n.contato_id = v_contato AND n.situacao = 'colhendo'
     AND n.criado_em > now() - interval '24 hours'
   ORDER BY n.id DESC LIMIT 1;

  IF v_ficha IS NOT NULL AND nai_secretaria_ligada() THEN
    v_at := 'secretaria';
    v_motivo := 'cadastro em andamento (ficha ' || v_ficha || ')';
    v_por := 'cola';
  END IF;

  IF v_at = 'secretaria' AND NOT nai_secretaria_ligada() THEN
    v_at := 'locacao';
    v_motivo := 'secretaria desligada';
  END IF;

  UPDATE nai_turno SET atendente = v_at WHERE id = p_turno;
  INSERT INTO nai_mente (turno_id, atendente, motivo, por)
       VALUES (p_turno, v_at, v_motivo, v_por);
  PERFORM nai_anotar(p_turno, 4, 'mente_mestra', 'mudou',
                     'quem responde: ' || v_at || coalesce(' (' || v_motivo || ')', ''));
  RETURN v_at;
END;
$function$;

-- 3 ------------------- O TIPO SAI DA CONVERSA INTEIRA, NAO SO DOS TURNOS
CREATE OR REPLACE FUNCTION public.nai_tipo_da_conversa(p_contato bigint, p_texto text)
 RETURNS text LANGUAGE sql STABLE
AS $function$
  SELECT coalesce(
    -- 1. o que ele disse AGORA manda
    nai_tipo_pedido(coalesce(p_texto, '')),
    -- 2. o turno mais recente em que ele disse o tipo
    (SELECT nai_tipo_pedido(t.texto) FROM nai_turno t
      WHERE t.contato_id = p_contato AND t.criado_em > now() - interval '30 days'
        AND nai_tipo_pedido(t.texto) IS NOT NULL
      ORDER BY t.id DESC LIMIT 1),
    -- 3. e, se nem isso, a MENSAGEM mais recente dele. Conversa antiga nao
    -- virou turno (era outro fluxo), e era la que estava "a casa do nova
    -- cidade ainda esta disponivel?" -- o (92) 98523-2884, em 11/09.
    (SELECT nai_tipo_pedido(m.texto) FROM mensagens m
      WHERE nai_chave(m.telefone) = ANY (
              SELECT c.chave FROM nai_contato c WHERE c.id = ANY (nai_contato_irmaos(p_contato)))
        AND m.direcao = 'recebida'
        AND m.criada_em > now() - interval '60 days'
        AND nai_tipo_pedido(m.texto) IS NOT NULL
      ORDER BY m.id DESC LIMIT 1));
$function$;

COMMIT;

SELECT t AS mensagem, nai_e_so_cortesia(t) AS e_so_cortesia
  FROM unnest(ARRAY['Ok','Oii','Obrigado! Boa Noite.','blz','ok, e o 5611?',
                    'Bom dia','Bom dia, tem casa no Aleixo?','valeu mana']) t;
