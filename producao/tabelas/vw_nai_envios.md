# vw_nai_envios  (view, ~0 linhas)
Tudo que saiu pelo numero da locacao: o dela vem da caixa de saida, o de gente vem do eco sem par. Tel, 15/09.

## colunas
id  bigint
quando  timestamp with time zone
para_quem  text
quem_mandou  text
papel  text
motivo  text
texto  text
status  text

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT s.id,
    s.criado_em AS quando,
    COALESCE(k.nome_completo, k.nome_whatsapp, nai_fone_fmt(k.telefone)) AS para_quem,
    'a Nay'::text AS quem_mandou,
    s.papel_destino AS papel,
    COALESCE(s.motivo, '-'::text) AS motivo,
        CASE
            WHEN s.tipo = 'imagem'::text THEN ('[foto '::text || COALESCE(s.codigo::text, ''::text)) || ']'::text
            ELSE "left"(s.texto, 160)
        END AS texto,
    s.estado AS status
   FROM nai_saida s
     LEFT JOIN nai_contato k ON k.id = s.contato_id
  WHERE s.estado = ANY (ARRAY['enviado'::text, 'enviando'::text, 'simulado'::text])
UNION ALL
 SELECT m.id + 1000000 AS id,
    m.criada_em AS quando,
    COALESCE(( SELECT COALESCE(k2.nome_completo, k2.nome_whatsapp) AS "coalesce"
           FROM nai_contato k2
          WHERE k2.chave = nai_chave(m.telefone)), nai_fone_fmt(m.telefone)) AS para_quem,
    'alguém digitou'::text AS quem_mandou,
    '-'::text AS papel,
    '-'::text AS motivo,
        CASE
            WHEN COALESCE(btrim(m.texto), ''::text) = ''::text THEN '[foto ou mídia]'::text
            ELSE "left"(m.texto, 160)
        END AS texto,
    COALESCE(m.status, '-'::text) AS status
   FROM mensagens m
  WHERE m.direcao = 'enviada'::text AND m.fluxo = 'nai'::text AND NOT (EXISTS ( SELECT 1
           FROM nai_saida s
          WHERE s.message_id IS NOT NULL AND s.message_id = m.message_id)) AND NOT (EXISTS ( SELECT 1
           FROM nai_saida s
          WHERE (s.estado = ANY (ARRAY['enviado'::text, 'enviando'::text])) AND COALESCE(btrim(m.texto), ''::text) <> ''::text AND btrim(s.texto) = btrim(m.texto) AND s.criado_em >= (m.criada_em - '00:20:00'::interval) AND s.criado_em <= (m.criada_em + '00:20:00'::interval)))
  ORDER BY 2 DESC;
