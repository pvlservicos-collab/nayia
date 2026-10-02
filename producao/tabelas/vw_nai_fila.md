# vw_nai_fila  (view, ~0 linhas)
O que chegou e ainda nao virou resposta, e o que ela escreveu e ainda nao saiu. Painel, Tel 15/09.

## colunas
lado  text
id  bigint
quando  timestamp with time zone
papel  text
quem  text
tipo  text
texto  text
estado  text
bloqueio  text
motivo  text
sai_apos  timestamp with time zone

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT 'saida'::text AS lado,
    s.id,
    s.criado_em AS quando,
    s.papel_destino AS papel,
    COALESCE(k.nome_completo, k.nome_whatsapp, nai_fone_fmt(k.telefone)) AS quem,
    s.tipo,
        CASE
            WHEN s.tipo = 'imagem'::text THEN ('[foto '::text || COALESCE(s.codigo::text, '?'::text)) || ']'::text
            ELSE "left"(s.texto, 160)
        END AS texto,
    s.estado,
    s.bloqueio,
    s.motivo,
    s.enviar_apos AS sai_apos
   FROM nai_saida s
     LEFT JOIN nai_contato k ON k.id = s.contato_id
  WHERE (s.estado = ANY (ARRAY['pendente'::text, 'enviando'::text])) OR s.estado = 'bloqueado'::text AND s.criado_em > (now() - '24:00:00'::interval)
UNION ALL
 SELECT 'entrada'::text AS lado,
    m.id,
    m.criada_em AS quando,
    'corretor'::text AS papel,
    COALESCE(m.nome, nai_fone_fmt(m.telefone)) AS quem,
    COALESCE(m.origem, 'texto'::text) AS tipo,
    "left"(m.texto, 160) AS texto,
    m.status AS estado,
    NULL::text AS bloqueio,
    NULL::text AS motivo,
    NULL::timestamp with time zone AS sai_apos
   FROM mensagens m
  WHERE m.fluxo = 'nai'::text AND m.direcao = 'recebida'::text AND (m.status = ANY (ARRAY['Recebido'::text, 'Processando'::text])) AND m.criada_em > (now() - '24:00:00'::interval)
  ORDER BY 3 DESC;
