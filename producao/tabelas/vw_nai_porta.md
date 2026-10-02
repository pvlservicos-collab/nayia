# vw_nai_porta  (view, ~0 linhas)
Quem escreveu nas ultimas 48h e o que a porta decidiu -- lido do turno, nao recalculado.

## colunas
id  bigint
quando  timestamp with time zone
quem  text
ele_disse  text
porta  text
ja_liberada  boolean
com_o_tel  boolean

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT t.id,
    t.criado_em AS quando,
    COALESCE(k.nome_completo, k.nome_whatsapp, nai_fone_fmt(k.telefone)) AS quem,
    "left"(t.texto, 120) AS ele_disse,
    t.porta,
    k.liberado_em IS NOT NULL AS ja_liberada,
    k.humano_assumiu_em IS NOT NULL AS com_o_tel
   FROM nai_turno t
     JOIN nai_contato k ON k.id = t.contato_id
  WHERE t.papel = 'corretor'::text AND t.criado_em > (now() - '48:00:00'::interval)
  ORDER BY t.id DESC;
