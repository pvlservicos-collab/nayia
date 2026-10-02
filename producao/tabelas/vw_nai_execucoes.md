# vw_nai_execucoes  (view, ~0 linhas)
Uma linha por execucao, com veredito (ok/corrigida/parada/barrada/muda/erro). A lista do painel (Tel, 19/09).

## colunas
turno  bigint
quando  timestamp with time zone
papel  text
porta  text
imovel  integer
teste  boolean
modelo  text
prompt_versao  integer
exec_id  text
quem  text
ele_disse  text
ferramentas  text[]
textos  bigint
fotos  bigint
barradas  bigint
motivos_barrada  text
conf_agiram  text
setores_com_problema  text
primeiro_erro  text
ms_total  bigint
seg_ate_responder  integer
veredito  text

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 WITH ev AS (
         SELECT nai_evento.turno_id,
            count(*) FILTER (WHERE nai_evento.resultado = 'erro'::text) AS erros,
            count(*) FILTER (WHERE nai_evento.resultado = 'parou'::text) AS paradas,
            max(
                CASE
                    WHEN nai_evento.resultado = 'erro'::text THEN nai_evento.detalhe
                    ELSE NULL::text
                END) AS primeiro_erro,
            sum(nai_evento.ms) AS ms_soma,
            max(nai_evento.exec_id) AS exec_id,
            string_agg(DISTINCT nai_evento.setor, ','::text) FILTER (WHERE nai_evento.resultado <> 'ok'::text) AS setores_com_problema
           FROM nai_evento
          GROUP BY nai_evento.turno_id
        ), sd AS (
         SELECT nai_saida.turno_id,
            count(*) FILTER (WHERE nai_saida.tipo = 'texto'::text AND (nai_saida.estado = ANY (ARRAY['enviado'::text, 'simulado'::text]))) AS textos,
            count(*) FILTER (WHERE nai_saida.tipo = 'imagem'::text AND (nai_saida.estado = ANY (ARRAY['enviado'::text, 'simulado'::text]))) AS fotos,
            count(*) FILTER (WHERE nai_saida.estado = 'bloqueado'::text) AS barradas,
            count(*) FILTER (WHERE nai_saida.estado = 'erro'::text) AS erros_envio,
            string_agg(DISTINCT nai_saida.bloqueio, ', '::text) FILTER (WHERE nai_saida.estado = 'bloqueado'::text) AS motivos_barrada,
            min(nai_saida.enviado_em) AS primeira_saida
           FROM nai_saida
          GROUP BY nai_saida.turno_id
        ), cf AS (
         SELECT nai_conferencia.turno_id,
            count(*) FILTER (WHERE nai_conferencia.resultado = 'parou'::text) AS conf_parou,
            count(*) FILTER (WHERE nai_conferencia.resultado = ANY (ARRAY['mudou'::text, 'cortou'::text])) AS conf_mexeu,
            string_agg(nai_conferencia.etapa, ', '::text ORDER BY nai_conferencia.ordem) FILTER (WHERE nai_conferencia.resultado <> 'passou'::text) AS conf_agiram
           FROM nai_conferencia
          GROUP BY nai_conferencia.turno_id
        )
 SELECT t.id AS turno,
    t.criado_em AS quando,
    t.papel,
    t.porta,
    t.codigo AS imovel,
    t.teste,
    t.modelo,
    t.prompt_versao,
    COALESCE(t.exec_id, ev.exec_id) AS exec_id,
    k.nome_whatsapp AS quem,
    "left"(COALESCE(t.texto, ''::text), 160) AS ele_disse,
    COALESCE(t.ferramentas, '{}'::text[]) AS ferramentas,
    COALESCE(sd.textos, 0::bigint) AS textos,
    COALESCE(sd.fotos, 0::bigint) AS fotos,
    COALESCE(sd.barradas, 0::bigint) AS barradas,
    sd.motivos_barrada,
    cf.conf_agiram,
    ev.setores_com_problema,
    ev.primeiro_erro,
    COALESCE(t.ms_total::bigint, ev.ms_soma) AS ms_total,
    EXTRACT(epoch FROM sd.primeira_saida - t.criado_em)::integer AS seg_ate_responder,
        CASE
            WHEN COALESCE(ev.erros, 0::bigint) > 0 OR COALESCE(sd.erros_envio, 0::bigint) > 0 THEN 'erro'::text
            WHEN COALESCE(sd.textos, 0::bigint) = 0 AND COALESCE(sd.fotos, 0::bigint) = 0 AND COALESCE(sd.barradas, 0::bigint) = 0 THEN 'muda'::text
            WHEN COALESCE(sd.barradas, 0::bigint) > 0 AND COALESCE(sd.textos, 0::bigint) = 0 THEN 'barrada'::text
            WHEN COALESCE(cf.conf_parou, 0::bigint) > 0 THEN 'parada'::text
            WHEN COALESCE(cf.conf_mexeu, 0::bigint) > 0 THEN 'corrigida'::text
            ELSE 'ok'::text
        END AS veredito
   FROM nai_turno t
     LEFT JOIN nai_contato k ON k.id = t.contato_id
     LEFT JOIN ev ON ev.turno_id = t.id
     LEFT JOIN sd ON sd.turno_id = t.id
     LEFT JOIN cf ON cf.turno_id = t.id;
