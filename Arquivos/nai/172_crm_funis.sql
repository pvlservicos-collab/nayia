-- 172 -- a etapa de cada lead nos funis do CRM (29/09/2026). Pedro: "cada tag
-- é uma etapa da pipeline e o lead é movido pelo CRM conforme muda de tag
-- automaticamente". O CRM lê isto a cada minuto (crm/src/lib/funis.ts) e só
-- move o card quando a etapa calculada MUDA -- quem arrastou à mão não é
-- desfeito a cada minuto.
--
-- Captação (decisão do Pedro, 29/09): todos que receberam o disparo; vale a
-- etapa mais avançada -- Mandou os dados (ficha pronta) > Vendido / Alugado /
-- Disponível (a situação que o dono disse) > Respondeu > Não respondeu. A
-- campanha que saiu pelo número oficial (canal 'oficial') fica fora: não é
-- conversa da linha da captação.
-- Parceria: a etapa da Nay (nai_etapa_contato), com o telefone e o @lid da
-- pessoa para o CRM achar a conversa.

BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION crm_captacao_funil()
RETURNS TABLE(telefone text, nome text, etapa text, mudou_em timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET jit = off AS $$
  SELECT nai_fone_br(l.telefone), nullif(btrim(l.nome), ''),
         CASE WHEN EXISTS (SELECT 1 FROM captacao_cadastro c WHERE c.lead_id = l.id AND c.estado = 'pronto') THEN 'Mandou os dados'
              WHEN l.situacao = 'vendido' THEN 'Vendido'
              WHEN l.situacao = 'alugado' THEN 'Alugado'
              WHEN l.situacao = 'disponivel' THEN 'Disponível'
              WHEN l.respondeu_em IS NOT NULL THEN 'Respondeu'
              ELSE 'Não respondeu' END,
         greatest(l.atualizado_em, l.respondeu_em, l.ultimo_envio_em)
    FROM captacao_leads l
   WHERE l.ultimo_envio_em IS NOT NULL
     AND coalesce(l.canal, '') <> 'oficial'
     AND coalesce(l.telefone, '') <> ''
$$;

CREATE OR REPLACE FUNCTION crm_parceria_funil()
RETURNS TABLE(telefone text, lid text, etapa text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET jit = off AS $$
  SELECT (SELECT nai_fone_br(c2.telefone) FROM nai_contato c2
           WHERE c2.id = ANY (nai_contato_irmaos(e.contato_id)) AND c2.chave !~ '^lid:' AND coalesce(c2.telefone, '') <> ''
           ORDER BY c2.id LIMIT 1),
         (SELECT regexp_replace(c3.chave, '\D', '', 'g') FROM nai_contato c3
           WHERE c3.id = ANY (nai_contato_irmaos(e.contato_id)) AND c3.chave ~ '^lid:'
           ORDER BY c3.id LIMIT 1),
         CASE e.etapa WHEN 'identificacao' THEN 'Identificação'
                      WHEN 'recebeu_imovel' THEN 'Recebeu imóvel'
                      WHEN 'agendamento_visita' THEN 'Agendamento de visita' END
    FROM nai_etapa_contato e
   WHERE e.etapa IN ('identificacao', 'recebeu_imovel', 'agendamento_visita')
$$;

REVOKE ALL ON FUNCTION crm_captacao_funil(), crm_parceria_funil() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_captacao_funil(), crm_parceria_funil() TO nay_disparo;

COMMIT;
