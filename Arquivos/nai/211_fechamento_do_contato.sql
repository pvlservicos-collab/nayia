-- 211 (30/09/2026): O FECHAMENTO DE UM CONTATO, PARA A TELA DO CRM.
-- A aba Fechamento (Pedro, 30/09: modelos, autopreenchimento, documentos do
-- corretor e do cliente, envio ao Tel) precisa saber, para uma conversa: se há
-- fechamento, de que tipo (aluguel/venda) e QUANDO o checklist foi mandado -- é a
-- partir dali que as mensagens trazem os dados e os documentos.
-- Só leitura, pelo papel nay_disparo (que só executa função).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION crm_fechamento_do_contato(p_telefone text)
 RETURNS TABLE(fechamento_id bigint, tipo text, iniciado_em timestamptz, concluido_em timestamptz,
               checklist_tipo text, checklist_em timestamptz)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT f.id, f.tipo, f.iniciado_em, f.concluido_em, ck.tipo, ck.criado_em
    FROM crm_pessoas(ARRAY[p_telefone]) pe
    -- o aberto primeiro; senão, o último
    LEFT JOIN LATERAL (SELECT * FROM nai_fechamento f WHERE f.contato_id = ANY (pe.ids)
                        ORDER BY (f.concluido_em IS NULL) DESC, f.id DESC LIMIT 1) f ON true
    -- o último checklist que a Nay mandou (nai_enviar_checklist_para, motivo 'checklist')
    LEFT JOIN LATERAL (SELECT s.criado_em,
                              CASE WHEN s.texto ~* 'venda|vendedor|comprador' THEN 'venda' ELSE 'locacao' END AS tipo
                         FROM nai_saida s
                        WHERE s.contato_id = ANY (pe.ids) AND s.motivo = 'checklist'
                          AND s.estado IN ('enviado', 'enviando', 'simulado')
                        ORDER BY s.criado_em DESC LIMIT 1) ck ON true
   LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION crm_fechamento_do_contato(text) TO nay_disparo;
COMMIT;
