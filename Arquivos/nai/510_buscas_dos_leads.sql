-- 510 (Pedro, 28/10/2026): "analisar toda a aba leads, seguindo os princípios de nota de quanto o imóvel se encaixa com o
-- pedido do corretor nos grupos, mas vai encontrar todas as solicitações de leads e ver se tem algum dos nossos imóveis
-- que faz sentido enviar para esses leads, é claro que ainda não foi enviado, e deixar salvo essas buscas do lead como
-- um cardzinho no contato deles no menu da direita do contato aberto".
--
-- Cada pedido de um lead da aba Leads (privado.olx_lead_whatsapp) vira uma linha de privado.lead_busca, com os imóveis
-- NOSSOS que passaram na nota da Captação ativa (nay-grupos/pontuar.py, o mesmo aperto da busca do cliente:
-- olx/buscas.py opcoes_da_base) e ainda não tinham ido a ele. Quem grava é nay-olx/analisar_leads.py (papel nay); o CRM
-- lê por crm_lead_buscas(telefone) no card da direita do contato (BuscasDoLead.tsx).
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '20s';

CREATE TABLE privado.lead_busca (
  id          bigserial PRIMARY KEY,
  lead_id     integer NOT NULL,
  telefone    text NOT NULL,
  ordem       integer NOT NULL DEFAULT 1,
  titulo      text NOT NULL,                 -- a manchete: VENDA · Apartamento · 3 quartos · até R$ 1.000.000
  disse       text,                          -- o pedido nas palavras dele (resumo da conversa)
  filtros     jsonb NOT NULL DEFAULT '{}',   -- no formato dos filtros da Nay do WhatsApp
  situacao    text NOT NULL CHECK (situacao IN ('com_opcoes', 'sem_opcoes', 'abaixo_do_minimo')),
  motivo      text,                          -- sem opção: por quê (o funil da nota)
  ja_enviados integer[] NOT NULL DEFAULT '{}',
  analisada_em timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX lead_busca_fone8 ON privado.lead_busca (right(regexp_replace(telefone, '\D', '', 'g'), 8));

CREATE TABLE privado.lead_busca_imovel (
  busca_id bigint NOT NULL REFERENCES privado.lead_busca(id) ON DELETE CASCADE,
  posicao  integer NOT NULL,
  codigo   integer NOT NULL,
  nota     numeric NOT NULL,
  detalhe  jsonb NOT NULL DEFAULT '[]',      -- os itens da nota: [{criterio, texto, peso, pontos}]
  PRIMARY KEY (busca_id, codigo)
);

GRANT SELECT, INSERT, UPDATE, DELETE ON privado.lead_busca, privado.lead_busca_imovel TO nay;
GRANT USAGE ON SEQUENCE privado.lead_busca_id_seq TO nay;

-- O card do CRM. "Já enviado" é lido na hora (o que foi depois da análise também aparece marcado), e o imóvel que saiu
-- do mercado depois da análise some.
CREATE OR REPLACE FUNCTION public.crm_lead_buscas(p_telefone text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH f AS (SELECT right(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g'), 8) AS f8)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id, 'titulo', b.titulo, 'disse', b.disse, 'situacao', b.situacao, 'motivo', b.motivo,
           'analisada_em', b.analisada_em,
           'imoveis', coalesce((
             SELECT jsonb_agg(jsonb_build_object(
                      'codigo', x.codigo, 'nota', x.nota, 'detalhe', x.detalhe,
                      'condominio', i.condominio_nome, 'bairro', i.bairro, 'tipo', i.tipo, 'quartos', i.quartos,
                      'venda', i.valor_venda, 'aluguel', i.valor_aluguel,
                      'enviado', EXISTS (SELECT 1 FROM privado.olx_cliente_enviada e
                                          WHERE e.lead = b.lead_id AND e.codigo = x.codigo))
                    ORDER BY x.posicao)
               FROM privado.lead_busca_imovel x
               JOIN imoveis i ON i.codigo = x.codigo
              WHERE x.busca_id = b.id AND i.status = 'Disponível' AND coalesce(i.disponivel, true)), '[]'::jsonb))
         ORDER BY b.ordem, b.id), '[]'::jsonb)
    FROM privado.lead_busca b, f
   WHERE f.f8 <> '' AND right(regexp_replace(b.telefone, '\D', '', 'g'), 8) = f.f8
$function$;
GRANT EXECUTE ON FUNCTION public.crm_lead_buscas(text) TO nay_disparo, nay;

COMMIT;
