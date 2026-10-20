-- 426: RELATÓRIO › AS ETIQUETAS DO WHATSAPP LEADS GUARDADAS (Pedro, 20/10/2026: "quero que salve todos esses leads lá
-- no site na aba relatório, vai ser uma tabela com cada contato em cada uma das etapas que tem aí no de captação (leads),
-- e a partir de agora vão sair essas etapas e as etapas vão virar as tags lá em cima, mas não mexa em nada que possa
-- apagar essas etapas ... quero que faça isso de forma segura").
--
-- Uma FOTO: quem estava em cada etiqueta da linha de captação do CRM (Não respondeu, Alugado, Disponível, ...) no
-- momento em que foi tirada. Nada é apagado no CRM: as etiquetas continuam nos contatos; só deixam de ser as abas.
-- A cópia é feita pelo scripts/foto_etiquetas_leads.sh (CRM -> esta tabela), e pode ser tirada de novo quando quiser.
-- A tela: admin › Relatórios, rota /admin/api/relatorio/etiquetas-leads (com senha: tem telefone).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.relatorio_etiquetas_foto (
  id         serial PRIMARY KEY,
  linha      text NOT NULL,
  tirada_em  timestamptz NOT NULL DEFAULT now(),
  observacao text
);
CREATE TABLE IF NOT EXISTS privado.relatorio_etiquetas_contato (
  foto_id          integer NOT NULL REFERENCES privado.relatorio_etiquetas_foto(id),
  etiqueta         text NOT NULL,
  lead_id          text NOT NULL,
  nome             text,
  telefone         text,
  ultima_atividade timestamptz,
  criado_no_crm    timestamptz,
  PRIMARY KEY (foto_id, etiqueta, lead_id)
);
COMMENT ON TABLE privado.relatorio_etiquetas_contato IS '426: a foto de quem estava em cada etiqueta de uma linha do CRM (cópia; o CRM não muda).';

CREATE OR REPLACE FUNCTION public.site_relatorio_etiquetas(p_foto integer DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'privado' AS $function$
  WITH f AS (
    SELECT * FROM privado.relatorio_etiquetas_foto
     WHERE id = coalesce(p_foto, (SELECT max(id) FROM privado.relatorio_etiquetas_foto))),
  c AS (SELECT x.* FROM privado.relatorio_etiquetas_contato x JOIN f ON f.id = x.foto_id)
  SELECT jsonb_build_object(
    'foto', (SELECT jsonb_build_object('id', f.id, 'linha', f.linha, 'tirada_em', f.tirada_em, 'observacao', f.observacao) FROM f),
    'fotos', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', id, 'linha', linha, 'tirada_em', tirada_em) ORDER BY id DESC), '[]')
                FROM privado.relatorio_etiquetas_foto),
    'contatos', (SELECT count(DISTINCT lead_id) FROM c),
    'etiquetas', coalesce((
      SELECT jsonb_agg(jsonb_build_object('etiqueta', e.etiqueta, 'n', e.n, 'contatos', e.contatos) ORDER BY e.n DESC, e.etiqueta)
        FROM (SELECT etiqueta, count(*) AS n,
                     jsonb_agg(jsonb_build_object('nome', nome, 'telefone', telefone, 'ultima', ultima_atividade, 'criado', criado_no_crm)
                               ORDER BY ultima_atividade DESC NULLS LAST) AS contatos
                FROM c GROUP BY etiqueta) e), '[]'))
$function$;

REVOKE ALL ON FUNCTION public.site_relatorio_etiquetas(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_relatorio_etiquetas(integer) TO nay_site_escrita;
COMMIT;
