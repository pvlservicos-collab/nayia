-- =====================================================================
-- NAI -- 119: a rodada de testes do Jev (Tel, 24/09/2026)
--
-- Ele: "quero testar o jev das ultimas conversas de corretores que ela errou
-- no zap, e nas ultimas 20 conversas de corretores".
--
-- A ideia e a mesma das rodadas de treino: pegar CONVERSA DE VERDADE, passar
-- pelo Jev e comparar com o que aconteceu no WhatsApp. So que aqui nao se
-- julga a resposta dela -- julga-se A ESCOLHA: quem deveria responder, e o
-- que o Jev entendeu da mensagem.
--
-- NADA SAI PARA O WHATSAPP. Isto le turnos que ja aconteceram e chama o Jev
-- por fora do fluxo. A Nay esta pausada de qualquer jeito.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE TABLE IF NOT EXISTS nai_jev_rodada (
  id          bigserial PRIMARY KEY,
  rodada      text NOT NULL,
  turno_id    bigint,
  quem        text,
  texto       text,
  leitura_img text,
  respostas   jsonb,
  jev_disse   text,      -- o que o Jev/os pisos decidiriam
  aconteceu   text,      -- o que de fato aconteceu naquele turno
  bateu       boolean,
  custo       numeric(12, 8),
  criado_em   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS nai_jev_rodada_r ON nai_jev_rodada (rodada, id);

-- A MESMA REGRA DE DECISAO da producao, sem gravar nada: e isto que o
-- corredor usa para dizer "o Jev decidiria X". Se a regra mudar em
-- `nai_decidir_com_jev`, muda aqui junto -- as duas leem os mesmos pisos.
CREATE OR REPLACE FUNCTION public.nai_jev_decidiria(p_jev jsonb)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE
    WHEN coalesce((p_jev #>> '{cortesia,noul}')::real, 0)
         >= coalesce(nullif(nai_cfg('jev_piso_cortesia','0.70'),''),'0.70')::real
      THEN 'cortesia: segue com quem atendia'
    WHEN coalesce((p_jev #>> '{oferta,noul}')::real, 0)
         >= coalesce(nullif(nai_cfg('jev_piso_oferta','0.60'),''),'0.60')::real
      OR (p_jev #>> '{o_que_mandou,choice}') = 'anuncio_dele'
      THEN 'secretaria'
    WHEN (p_jev #>> '{atendente,choice}') = 'secretaria' THEN 'secretaria'
    ELSE 'locacao'
  END;
$function$;

-- Os turnos que valem a pena testar: corretor, com texto, dos ultimos dias.
CREATE OR REPLACE FUNCTION public.nai_turnos_para_o_jev(p_quantos int DEFAULT 20,
                                                        p_so_erros boolean DEFAULT false)
 RETURNS TABLE(turno_id bigint, quem text, texto text, atendente text, porta text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT t.id,
         coalesce(k.nome_completo, k.nome_whatsapp, nai_fone_fmt(k.telefone)),
         t.texto, t.atendente, coalesce(t.porta, '-')
    FROM nai_turno t JOIN nai_contato k ON k.id = t.contato_id
   WHERE t.papel = 'corretor'
     AND coalesce(btrim(t.texto), '') <> ''
     AND t.contato_id <> 9707                    -- o espelho de treino fica fora
     AND t.criado_em > now() - interval '7 days'
     AND (NOT p_so_erros
          -- "as que ela errou": onde a saida foi barrada, ou onde ela nao
          -- respondeu nada, ou onde o assunto era imovel e foi para a
          -- secretaria
          OR EXISTS (SELECT 1 FROM nai_saida s
                      WHERE s.turno_id = t.id AND s.estado = 'bloqueado')
          OR NOT EXISTS (SELECT 1 FROM nai_saida s WHERE s.turno_id = t.id)
          OR (t.atendente = 'secretaria' AND nai_e_assunto_de_locacao(t.texto)))
   ORDER BY t.id DESC
   LIMIT p_quantos;
$function$;

COMMIT;

SELECT 'turnos de corretor nos ultimos 7 dias' AS o, count(*)::text FROM nai_turnos_para_o_jev(500, false)
UNION ALL
SELECT 'dos quais com erro (barrado, sem resposta ou desviado)', count(*)::text FROM nai_turnos_para_o_jev(500, true);
