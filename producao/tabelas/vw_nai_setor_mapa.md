# vw_nai_setor_mapa  (view, ~0 linhas)
Um setor por linha: quantas funcoes, quantas da IA antiga, e quantas candidatas a entulho (Tel, 19/09).

## colunas
setor  text
ordem  integer
titulo  text
descricao  text
funcoes  bigint
da_ia_nova  bigint
da_ia_antiga  bigint
chars_de_codigo  bigint
candidatas_a_entulho  bigint
dependencias_da_antiga  bigint

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT s.setor,
    s.ordem,
    s.titulo,
    s.descricao,
    count(v.*) AS funcoes,
    count(v.*) FILTER (WHERE v.familia = 'nai'::text) AS da_ia_nova,
    count(v.*) FILTER (WHERE v.familia = 'nay'::text) AS da_ia_antiga,
    sum(v.tamanho) AS chars_de_codigo,
    ( SELECT count(*) AS count
           FROM vw_nai_funcao_orfa o
          WHERE o.setor = s.setor AND o.chamador_de_fora IS NULL) AS candidatas_a_entulho,
    ( SELECT count(*) AS count
           FROM vw_nai_acoplamento a
          WHERE a.setores_afetados ~~ (('%'::text || s.setor) || '%'::text)) AS dependencias_da_antiga
   FROM nai_setor s
     LEFT JOIN vw_nai_funcao_viva v ON v.setor = s.setor
  GROUP BY s.setor, s.ordem, s.titulo, s.descricao
  ORDER BY s.ordem;
