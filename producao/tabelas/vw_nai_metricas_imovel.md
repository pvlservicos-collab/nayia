# vw_nai_metricas_imovel  (view, ~0 linhas)
Por imovel: quantas vezes foi oferecido, fotos, conversas e visitas. Painel da Nay Locacao (Tel, 15/09).

## colunas
codigo  integer
condominio_nome  text
bairro  text
aluguel  integer
quartos  integer
disponivel  boolean
vezes_mandado  bigint
fotos_enviadas  bigint
mensagens_sobre_ele  bigint
pessoas_perguntaram  bigint
visitas_pedidas  bigint
visitas_confirmadas  bigint
visitas_em_pe  bigint
visitas_canceladas  bigint
ultima_vez_mandado  timestamp with time zone
proxima_visita  timestamp with time zone

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 WITH ofertas AS (
         SELECT s.id,
            s.criado_em,
            c_1.codigo::integer AS codigo
           FROM nai_saida s
             CROSS JOIN LATERAL unnest(COALESCE(nay_codigos_citados(s.texto), '{}'::text[])) c_1(codigo)
          WHERE s.tipo = 'texto'::text AND s.papel_destino = 'corretor'::text AND s.estado = 'enviado'::text AND (EXISTS ( SELECT 1
                   FROM imoveis i_1
                  WHERE i_1.codigo = c_1.codigo::integer))
        ), fotos AS (
         SELECT s.codigo,
            count(*) AS fotos,
            count(DISTINCT s.contato_id) AS pessoas_com_foto,
            max(s.criado_em) AS ultima_foto
           FROM nai_saida s
          WHERE s.tipo = 'imagem'::text AND s.codigo IS NOT NULL AND s.estado = 'enviado'::text
          GROUP BY s.codigo
        ), mandados AS (
         SELECT o.codigo,
            count(*) AS vezes_mandado,
            max(o.criado_em) AS ultima_vez
           FROM ofertas o
          GROUP BY o.codigo
        ), visitas AS (
         SELECT v_1.codigo,
            count(*) AS visitas_pedidas,
            count(*) FILTER (WHERE v_1.confirmada_em IS NOT NULL) AS visitas_confirmadas,
            count(*) FILTER (WHERE v_1.estado = 'cancelada'::text) AS visitas_canceladas,
            count(*) FILTER (WHERE nai_visita_aberta(v_1.estado)) AS visitas_em_pe,
            max(v_1.quando) AS proxima_visita
           FROM nai_visita v_1
          GROUP BY v_1.codigo
        ), conversas AS (
         SELECT t.codigo,
            count(*) AS turnos,
            count(DISTINCT t.contato_id) AS pessoas
           FROM nai_turno t
          WHERE t.codigo IS NOT NULL
          GROUP BY t.codigo
        )
 SELECT COALESCE(m.codigo, f.codigo, v.codigo, c.codigo) AS codigo,
    i.condominio_nome,
    i.bairro,
    i.valor_aluguel::integer AS aluguel,
    i.quartos,
    COALESCE(i.disponivel, true) AS disponivel,
    COALESCE(m.vezes_mandado, 0::bigint) AS vezes_mandado,
    COALESCE(f.fotos, 0::bigint) AS fotos_enviadas,
    COALESCE(c.turnos, 0::bigint) AS mensagens_sobre_ele,
    COALESCE(c.pessoas, 0::bigint) AS pessoas_perguntaram,
    COALESCE(v.visitas_pedidas, 0::bigint) AS visitas_pedidas,
    COALESCE(v.visitas_confirmadas, 0::bigint) AS visitas_confirmadas,
    COALESCE(v.visitas_em_pe, 0::bigint) AS visitas_em_pe,
    COALESCE(v.visitas_canceladas, 0::bigint) AS visitas_canceladas,
    GREATEST(m.ultima_vez, f.ultima_foto) AS ultima_vez_mandado,
    v.proxima_visita
   FROM mandados m
     FULL JOIN fotos f ON f.codigo = m.codigo
     FULL JOIN visitas v ON v.codigo = COALESCE(m.codigo, f.codigo)
     FULL JOIN conversas c ON c.codigo = COALESCE(m.codigo, f.codigo, v.codigo)
     LEFT JOIN imoveis i ON i.codigo = COALESCE(m.codigo, f.codigo, v.codigo, c.codigo);
