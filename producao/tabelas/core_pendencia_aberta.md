# core_pendencia_aberta  (view, ~0 linhas)

## colunas
id  bigint
turno_id  bigint
chave  text
codigo  integer
pergunta  text
faltou  text[]
criado_em  timestamp with time zone

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT id,
    turno_id,
    chave,
    codigo,
    pergunta,
    faltou,
    criado_em
   FROM core_pendencia p
  WHERE NOT (EXISTS ( SELECT 1
           FROM nai_saida s
          WHERE s.motivo = 'resposta_do_tel'::text AND s.criado_em > p.criado_em AND "right"(regexp_replace(s.chave_destino, '\D'::text, ''::text, 'g'::text), 8) = "right"(regexp_replace(p.chave, '\D'::text, ''::text, 'g'::text), 8)));
