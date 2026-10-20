-- 447 -- Captação: a lista 5 (donos com imóvel alugado) recebe o modelo oficial `outro_imovel_04`
--        ("Cadastro de proprietário: {{1}}, o(a) Sr.(a) possui outro imóvel disponível além do que já consta conosco?"
--        + botões Tenho outro imóvel / Não tenho outro), 2 por minuto, pelo nay-captacao.
--
-- Pedro, 20/10/2026: "dispara para Donos com imóvel alugado | cadastro (data do contrato) | 169, o disparo 'Cadastro de
-- proprietário: ...' [Tenho outro imóvel] [Não tenho outro], e põe a nay para quando o cara responder ... faça o teste
-- para esses aí 2 por minuto ... NÃO QUERO DISPARAR PARA NENHUM PROPRIETÁRIO QUE JÁ FALAMOS EM OUTROS NÚMEROS NOS
-- ÚLTIMOS 60 DIAS, revise a lista de exclusão e depois dispare só para quem não consta nisso".
--
-- O que muda:
--   1. captacao_leads.modelo_abertura: o modelo que abre a conversa DESTE lead. NULL = o do serviço
--      (situacao_imovel_cadastrado_1), então a campanha que já existe não muda.
--   2. captacao_config.python_modelos_aprovados: o nay-captacao escreve aqui, a cada minuto, os modelos que a Meta
--      aprovou (a foto admin/dados/modelos.json, refeita a cada 10 min pelo cron nay-agentes). Lead com modelo fora
--      desta lista NÃO entra na fila: em 20/10 16:40 o outro_imovel_04 estava PENDING, e a fila espera a aprovação em
--      vez de queimar o lead (o CRM recusa modelo não aprovado, e 3 falhas seguidas parariam todo o disparo).
--   3. captacao_honorarios_frase: nesta campanha não se fala do imóvel alugado que já temos, então a pergunta dos 6%
--      sobre o valor de venda dele não existe (40 dos 163 têm valor de venda no cadastro).
--   4. Os 163 donos entram em captacao_leads como 'novo', etapa 'aguardando_outros', com o modelo outro_imovel_04.
--
-- Quem entra: a lista 5 de site_publicos_disparo (dono em vw_proprietarios_site com imóvel Alugado, sem corretor/
-- parceiro), menos, revisado em 20/10:
--   - quem falou conosco por qualquer número nos últimos 60 dias, nas duas direções (privado.falou_conosco: Parceria,
--     captação Z-API e oficial, Nay velha e nay-core, envios, corretores e a cópia do CRM): 308 dos 477;
--   - e, nesta lista, também as fontes que privado.falou_conosco não lê: core_mensagem, mensagem_saida,
--     saida_do_sistema e os WhatsApps da OLX (privado.olx_lead_whatsapp) -- nenhum dos 169 estava nelas;
--   - quem já está na campanha (4), em captacao_nao_disparar, corretor, nome de corretor/imobiliária/empresa, telefone
--     de corretor dos grupos (8 finais), sem nome, telefone ruim, e o que captacao_fora_da_campanha barrar.
-- Conferido também no crmdb (leads + lead_activities, entrada e saída, 60 dias): nenhum dos 163 tem conversa.
-- A fila (captacao_py_fila_do_disparo) ainda confere nay_falou_conosco(60) na hora de cada envio: quem falar conosco
-- até lá sai sozinho.
BEGIN;
SET LOCAL lock_timeout = '3s';

ALTER TABLE captacao_leads ADD COLUMN IF NOT EXISTS modelo_abertura text;
COMMENT ON COLUMN captacao_leads.modelo_abertura IS
  '447: o modelo da Meta que abre a conversa deste lead. NULL = o do serviço (CAPTACAO_MODELO_ABERTURA, situacao_imovel_cadastrado_1). Só sai quando está em captacao_config.python_modelos_aprovados.';

INSERT INTO captacao_config (chave, valor, nota)
VALUES ('python_modelos_aprovados', '',
        '447: os modelos APPROVED na Meta (foto admin/dados/modelos.json), escritos pelo nay-captacao a cada minuto. Lead com modelo_abertura fora desta lista não entra na fila do disparo.')
ON CONFLICT (chave) DO NOTHING;

CREATE OR REPLACE FUNCTION public.captacao_py_fila_do_disparo()
 RETURNS SETOF bigint
 LANGUAGE sql
 STABLE
AS $function$
  SELECT l.id
    FROM captacao_leads l
   WHERE l.tentativas < 4 AND NOT l.opt_out AND l.humano_assumiu_em IS NULL
     AND coalesce(btrim(l.telefone), '') <> '' AND coalesce(btrim(l.nome), '') <> ''
     AND captacao_fora_da_campanha(l.id) IS NULL
     AND (
          -- quem nunca recebeu nada nosso por este número
          (l.status IN ('novo', 'erro')
           AND NOT EXISTS (SELECT 1 FROM captacao_mensagens m
                            WHERE nay_fone_chave(m.telefone) = l.telefone_chave AND m.direcao = 'enviada' AND m.status <> 'Falhou'))
          -- 323: a retomada pelo oficial -- recebeu pela Z-API, nunca respondeu, ainda sem o modelo oficial
          OR (l.status = 'enviado'
              AND EXISTS (SELECT 1 FROM captacao_retomada_oficial r WHERE r.lead_id = l.id)
              AND l.respondeu_em IS NULL
              AND NOT EXISTS (SELECT 1 FROM captacao_mensagens m
                               WHERE nay_fone_chave(m.telefone) = l.telefone_chave AND m.direcao = 'recebida')
              AND NOT EXISTS (SELECT 1 FROM captacao_motor mt WHERE mt.lead_id = l.id))
         )
     AND NOT EXISTS (SELECT 1 FROM captacao_leads o
                      WHERE o.id <> l.id AND o.proprietario_id IS NOT NULL AND o.proprietario_id = l.proprietario_id
                        AND (o.ultimo_envio_em IS NOT NULL OR o.respondeu_em IS NOT NULL))
     AND NOT EXISTS (SELECT 1 FROM captacao_nao_disparar n WHERE n.telefone_chave = l.telefone_chave)
     -- 352: quem falou conosco por qualquer número nos últimos 60 dias não recebe disparo; corretor não é proprietário
     AND NOT nay_falou_conosco(l.telefone_chave, 60)
     AND NOT nay_e_corretor_chave(l.telefone_chave)
     -- 447: o modelo próprio do lead só sai depois que a Meta aprovar (o nay-captacao escreve a lista)
     AND (l.modelo_abertura IS NULL
          OR l.modelo_abertura = ANY (regexp_split_to_array(
               coalesce((SELECT c.valor FROM captacao_config c WHERE c.chave = 'python_modelos_aprovados'), ''), '\s*,\s*')))
   ORDER BY (l.status = 'enviado'), l.id;
$function$;

CREATE OR REPLACE FUNCTION public.captacao_honorarios_frase(p_telefone text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  WITH l AS (
    SELECT c.tratamento, nay_primeiro_nome(c.nome) AS n, c.modelo_abertura
      FROM captacao_leads c WHERE c.telefone_chave = nay_fone_chave(p_telefone) LIMIT 1
  ), d AS (
    SELECT l.tratamento,
           CASE WHEN l.n = upper(l.n) OR l.n = lower(l.n) THEN initcap(l.n) ELSE l.n END AS nome,
           captacao_honorarios_valor(p_telefone) AS valor
      FROM l
     -- 447: na campanha do "outro imóvel" não se fala do imóvel que já temos (está alugado): sem a pergunta dos 6%
     WHERE coalesce(l.modelo_abertura, '') NOT LIKE 'outro\_imovel%'
  )
  SELECT CASE WHEN d.tratamento IN ('Sr.', 'Sra.') THEN d.tratamento || coalesce(' ' || d.nome, '') || ', só'
              WHEN d.nome IS NOT NULL THEN d.nome || ', só'
              ELSE 'Só' END
         || ' para eu anotar certinho: no valor de ' || d.valor
         || ' já estão inclusos os 6% de honorários de corretagem, ou '
         || CASE d.tratamento WHEN 'Sra.' THEN 'a Sra.' WHEN 'Sr.' THEN 'o Sr.' ELSE 'você' END
         || ' quer esse valor líquido?'
    FROM d
   WHERE d.valor IS NOT NULL;
$function$;

DROP TABLE IF EXISTS _entram;
CREATE TEMP TABLE _entram ON COMMIT DROP AS
WITH corretor AS MATERIALIZED (
    SELECT nay_fone_chave(nay_fone_com_ddi(c.telefone)) AS chave FROM corretores c WHERE coalesce(c.telefone, '') <> ''
    UNION
    SELECT nay_fone_chave(nay_fone_com_ddi(p.telefone)) FROM proprietarios_export p WHERE coalesce(p.corretor, '') ~* 'parceir'
), dono AS MATERIALIZED (
    SELECT nay_fone_chave(nay_fone_com_ddi(ps.telefone)) AS chave,
           -- o imóvel citado é o ALUGADO de menor código (o mesmo telefone pode estar em mais de um cadastro)
           (array_agg(ps.id ORDER BY (v.status <> 'Alugado'), v.codigo))[1] AS proprietario_id,
           (array_agg(ps.nome ORDER BY (v.status <> 'Alugado'), v.codigo))[1] AS nome,
           (array_agg(nay_fone_com_ddi(ps.telefone) ORDER BY (v.status <> 'Alugado'), v.codigo))[1] AS telefone,
           bool_or(v.status = 'Alugado') AS tem_alugado,
           (array_agg(v.codigo ORDER BY (v.status <> 'Alugado'), v.codigo))[1] AS codigo,
           (array_agg(v.condominio ORDER BY (v.status <> 'Alugado'), v.codigo))[1] AS condominio,
           (array_agg(v.bairro ORDER BY (v.status <> 'Alugado'), v.codigo))[1] AS bairro,
           (array_agg(v.tipo ORDER BY (v.status <> 'Alugado'), v.codigo))[1] AS tipo,
           jsonb_agg(jsonb_build_object('codigo', v.codigo, 'condominio', v.condominio, 'endereco', v.endereco) ORDER BY v.codigo) AS imoveis_prop
      FROM vw_proprietarios_site ps JOIN vw_imoveis_todos v ON v.proprietario_id = ps.id
     WHERE length(regexp_replace(coalesce(ps.telefone, ''), '\D', '', 'g')) BETWEEN 10 AND 13 AND NOT site_nao_e_dono(ps.nome)
       AND NOT EXISTS (SELECT 1 FROM corretor k WHERE k.chave = nay_fone_chave(nay_fone_com_ddi(ps.telefone)))
     GROUP BY 1
), extra AS MATERIALIZED (   -- as fontes de conversa que privado.falou_conosco não lê (60 dias, 8 finais)
    SELECT right(regexp_replace(m.chave, '\D', '', 'g'), 8) AS f8 FROM core_mensagem m
     WHERE m.chave !~ '@' AND m.recebida_em > now() - interval '60 days'
    UNION SELECT right(regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g'), 8) FROM mensagem_saida m
     WHERE m.enviado_em > now() - interval '60 days' AND coalesce(m.telefone, '') !~ '@'
    UNION SELECT right(regexp_replace(coalesce(s.telefone, ''), '\D', '', 'g'), 8) FROM saida_do_sistema s
     WHERE s.em > now() - interval '60 days' AND coalesce(s.telefone, '') !~ '@'
    UNION SELECT right(regexp_replace(o.telefone, '\D', '', 'g'), 8) FROM privado.olx_lead_whatsapp o
     WHERE o.atualizado_em > now() - interval '60 days'
), marcado AS (
    SELECT d.*, nay_tratamento_por_nome(d.nome) AS tratamento,
           CASE WHEN coalesce(btrim(d.condominio), '') NOT IN ('', '—', '-') AND d.condominio !~* 'n[aã]o identificad' THEN 'no ' || btrim(d.condominio)
                WHEN coalesce(btrim(d.bairro), '') <> '' THEN 'no bairro ' || btrim(d.bairro) END AS imovel_desc
      FROM dono d WHERE d.tem_alugado
)
SELECT m.* FROM marcado m
 WHERE m.telefone ~ '^[0-9]{12,13}$'
   AND coalesce(btrim(m.nome), '') <> ''
   AND NOT EXISTS (SELECT 1 FROM captacao_leads l WHERE l.telefone_chave = m.chave OR l.telefone = m.telefone)
   AND NOT EXISTS (SELECT 1 FROM captacao_nao_disparar n WHERE n.telefone_chave = m.chave)
   AND NOT (m.nome ~* 'corretor|corretora|parceir|broker|assessoria|imobili[aá]ri|im[oó]veis|ltda|eireli|construtor|empreendiment'
            OR nai_dono_e_parceiro(m.nome))
   AND NOT EXISTS (SELECT 1 FROM corretores k
                    WHERE right(regexp_replace(coalesce(k.telefone, ''), '\D', '', 'g'), 8) = right(m.telefone, 8))
   AND NOT nay_falou_conosco(m.chave, 60)
   AND NOT nay_e_corretor_chave(m.chave)
   AND NOT EXISTS (SELECT 1 FROM extra e WHERE e.f8 = right(m.telefone, 8))
   AND NOT EXISTS (SELECT 1 FROM captacao_leads o WHERE o.proprietario_id = m.proprietario_id
                                                    AND (o.ultimo_envio_em IS NOT NULL OR o.respondeu_em IS NOT NULL));

INSERT INTO captacao_leads (telefone, nome, tratamento, proprietario_id, codigo, imovel_desc, condominio, bairro, tipo_imovel,
                            lista_id, quem_importou, status, etapa, pergunta_pendente, imoveis_prop, modelo_abertura)
SELECT e.telefone, e.nome, e.tratamento, e.proprietario_id, e.codigo::text, e.imovel_desc, e.condominio, e.bairro, e.tipo,
       NULL, 'Pedro (lista 5: donos com imóvel alugado, outro_imovel_04, 20/10)', 'novo', 'aguardando_outros',
       'tem outro imóvel disponível além do que já consta conosco?', e.imoveis_prop, 'outro_imovel_04'
  FROM _entram e
 ORDER BY e.proprietario_id
ON CONFLICT DO NOTHING;

-- a regra da campanha (308: corretor, nome de corretor/imobiliária, imóvel de parceiro...) é por lead: quem ela barra sai agora
DELETE FROM captacao_leads l
 WHERE l.quem_importou = 'Pedro (lista 5: donos com imóvel alugado, outro_imovel_04, 20/10)' AND captacao_fora_da_campanha(l.id) IS NOT NULL;

COMMIT;
