# nai_treino_painel  (view, ~0 linhas)

## colunas
id  bigint
ciclo_id  bigint
estado  text
erro_execucao  text
turno_origem  bigint
turno_simulado  bigint
exec_id  text
quando_original  timestamp with time zone
rodado_em  timestamp with time zone
ele_disse  text
ela_respondeu_antes  text
ela_respondeu_agora  text
ferramentas_antes  text[]
ferramentas_agora  text[]
contexto  jsonb
mudou  boolean
nome_whatsapp  text
nome_completo  text
telefone  text
veredito  text
julgamento_erro  text
julgamento_solucao  text
aplicada_em  timestamp with time zone
julgado_em  timestamp with time zone
ciclo_rotulo  text
fotos_agora  integer
roteiro  text
passo  integer
persona  text
saida  jsonb

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_conteudo: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT k.id,
    k.ciclo_id,
    k.estado,
    k.erro AS erro_execucao,
    k.turno_origem,
    k.turno_simulado,
    k.exec_id,
    k.quando_original,
    k.rodado_em,
    k.ele_disse,
    k.ela_respondeu_antes,
    k.ela_respondeu_agora,
    k.ferramentas_antes,
    k.ferramentas_agora,
    k.contexto,
    k.estado = 'rodado'::text AND btrim(COALESCE(k.ela_respondeu_agora, ''::text)) IS DISTINCT FROM btrim(COALESCE(k.ela_respondeu_antes, ''::text)) AS mudou,
    c.nome_whatsapp,
    c.nome_completo,
    c.telefone,
    j.veredito,
    j.erro AS julgamento_erro,
    j.solucao AS julgamento_solucao,
    j.aplicada_em,
    j.julgado_em,
    cic.rotulo AS ciclo_rotulo,
    (( SELECT count(*) AS count
           FROM nai_saida s
          WHERE s.turno_id = k.turno_simulado AND s.tipo = 'imagem'::text))::integer AS fotos_agora,
    k.roteiro,
    k.passo,
    k.persona,
    blocos.saida
   FROM nai_treino_caso k
     JOIN nai_contato c ON c.id = k.contato_origem
     JOIN nai_treino_ciclo cic ON cic.id = k.ciclo_id
     LEFT JOIN nai_treino_julgamento j ON j.caso_id = k.id
     LEFT JOIN LATERAL ( SELECT COALESCE(jsonb_agg(jsonb_build_object('tipo', b.tipo, 'texto', b.texto, 'fotos', b.fotos, 'para', b.para) ORDER BY b.ordem), '[]'::jsonb) AS saida
           FROM ( SELECT min(g.ordem) AS ordem,
                        CASE
                            WHEN g.e_foto THEN 'fotos'::text
                            ELSE 'texto'::text
                        END AS tipo,
                        CASE
                            WHEN g.e_foto THEN NULL::text
                            ELSE min(g.texto)
                        END AS texto,
                        CASE
                            WHEN g.e_foto THEN count(*)::integer
                            ELSE NULL::integer
                        END AS fotos,
                        CASE g.destino
                            WHEN 'corretor'::text THEN 'o corretor'::text
                            WHEN 'proprietario'::text THEN 'o proprietário'::text
                            WHEN 'motoboy'::text THEN 'o acompanhante'::text
                            WHEN 'tel'::text THEN 'o Tel'::text
                            ELSE 'quem escreveu'::text
                        END AS para
                   FROM ( SELECT s.ordem,
                            s.texto,
                            s.papel_destino AS destino,
                            s.tipo = 'imagem'::text AS e_foto,
                                CASE
                                    WHEN s.tipo = 'imagem'::text THEN ('f'::text || s.papel_destino) || ((row_number() OVER (ORDER BY s.ordem, s.id) - row_number() OVER (PARTITION BY (s.tipo = 'imagem'::text), s.papel_destino ORDER BY s.ordem, s.id))::text)
                                    ELSE 't'::text || s.id::text
                                END AS grupo
                           FROM nai_saida s
                          WHERE s.turno_id = k.turno_simulado AND s.estado <> 'bloqueado'::text AND (s.tipo <> 'texto'::text OR btrim(COALESCE(s.texto, ''::text)) <> ''::text)) g
                  GROUP BY g.grupo, g.e_foto, g.destino) b) blocos ON true;
