-- 520: o passo da Nay Leads (1 a 5) e a finalidade de cada cliente, para o CRM (Pedro, 29/10/2026: "no número, embaixo das
-- tags, uma barrinha sendo preenchida que mostra da etapa 1 a 5 onde o lead tá ... ela vai atender o lead e subir a
-- barrinha dele, e depois se ele mudar de solicitação ela volta a barrinha dele sozinha"; "trocar a tag orgânico por
-- Locação ou Venda, e a tag cliente por OLX").
--
-- crm_olx_clientes_etapas ganha três colunas no fim (quem lê com SELECT * ou por nome continua igual):
--   passo        1 Filtrar · 2 Busca feita · 3 Imóveis enviados · 4 Visita pedida (visita ou proprietarios sem visita
--                confirmada) · 5 Visita confirmada; fechamento e finalizado = 5; nova = 0
--   finalidade   locacao | venda | NULL (o que a Nay entendeu do pedido: filtros.finalidade)
--   visita_confirmada
-- A volta da barrinha quando o pedido muda é do nay-olx (whatsapp.mudou_o_pedido): a etapa volta a 'filtrar'.
BEGIN;

DROP FUNCTION IF EXISTS public.crm_olx_clientes_etapas();
CREATE FUNCTION public.crm_olx_clientes_etapas()
 RETURNS TABLE(telefone text, etapa text, nome text, codigo integer, quer_visita boolean, humano boolean,
               atualizado_em timestamp with time zone, origem text, passo integer, finalidade text,
               visita_confirmada boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  SELECT DISTINCT ON (right(l.telefone, 8)) l.telefone, l.etapa, l.nome, l.codigo, l.quer_visita, l.humano_em IS NOT NULL,
         greatest(l.atualizado_em, l.etapa_em), l.origem,
         CASE l.etapa WHEN 'filtrar' THEN 1 WHEN 'feito_busca' THEN 2 WHEN 'imoveis_enviados' THEN 3
                      WHEN 'visita' THEN CASE WHEN c.ok THEN 5 ELSE 4 END
                      WHEN 'proprietarios' THEN CASE WHEN c.ok THEN 5 ELSE 4 END
                      WHEN 'fechamento' THEN 5 WHEN 'finalizado' THEN 5 ELSE 0 END,
         nullif(l.filtros->>'finalidade', ''),
         c.ok
    FROM privado.olx_lead_whatsapp l
    CROSS JOIN LATERAL (SELECT EXISTS (SELECT 1 FROM privado.olx_visita v
                                        WHERE v.lead = l.id AND v.estado = 'confirmada') AS ok) c
   ORDER BY right(l.telefone, 8), l.criado_em DESC
$function$;
REVOKE ALL ON FUNCTION public.crm_olx_clientes_etapas() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crm_olx_clientes_etapas() TO nay, nay_disparo;

COMMIT;
