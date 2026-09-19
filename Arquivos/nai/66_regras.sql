-- =====================================================================
-- NAI -- 66: AS REGRAS QUE ELA IGNORA (e com que frequência)
--
-- Ele (19/09/2026): "não quero tirar as regras que já tinha ensinado para ela,
-- o problema dela hoje é ignorar essas regras".
--
-- A VIRADA DE CHAVE:
-- as 17 conferências do arquivo 15 não são "travas do sistema". Cada uma é UMA
-- REGRA que o Tel ensinou, e o resultado dela é o veredito sobre se a regra foi
-- seguida:
--
--     passou           -> ela seguiu a regra sozinha
--     mudou / cortou   -> ELA IGNOROU, e o sistema consertou antes de sair
--     parou            -> ELA IGNOROU tão feio que nada pôde sair
--
-- Esse registro existe desde 14/09 em `nai_conferencia` e nunca foi lido assim.
-- Este arquivo não cria regra nenhuma, não apaga regra nenhuma e não muda
-- comportamento: ele dá NOME e TEXTO a cada conferência, e conta.
--
-- Com isso, "ela ignora as regras" para de ser sensação e vira uma lista
-- ordenada: qual regra, quantas vezes, e em quais conversas.
--
-- ADITIVO E REVERSÍVEL. Uma tabela nova e duas views. Nenhuma função de
-- atendimento é tocada. `DROP TABLE nai_regra CASCADE;` desfaz tudo.
--
-- Depende do arquivo 64 (usa `nai_setor`). Aplicar depois dele.
-- =====================================================================


-- =====================================================================
-- 1. O CATÁLOGO DAS REGRAS
-- =====================================================================
-- Cada linha é uma regra que o Tel ensinou, com o nome que ela tem no código
-- (`etapa`, o mesmo que `nai_conferencia.etapa`) e o texto em português.
--
-- `tipo` separa duas coisas que NÃO devem ser lidas juntas:
--   parede  -- regra de negócio. Ignorar tem custo real: corretor ouve promessa
--              que não será cumprida, recebe imóvel errado, descobre o número
--              do apartamento. É por estas que se começa.
--   ajuste  -- correção de forma (markdown, emoji, duas perguntas juntas).
--              Ignorar incomoda, não quebra negócio.
--   fluxo   -- não é regra sobre ela: é o sistema decidindo caminho
--              (qual imóvel é a conversa, se cabe sugerir visita).
--              Contar isso como "regra ignorada" inflaria o número e tiraria
--              a confiança da tela inteira.
CREATE TABLE IF NOT EXISTS nai_regra (
  etapa      text PRIMARY KEY,
  ordem      int  NOT NULL,
  tipo       text NOT NULL CHECK (tipo IN ('parede', 'ajuste', 'fluxo')),
  titulo     text NOT NULL,
  regra      text NOT NULL,          -- a regra, como o Tel a diria
  o_que_faz  text NOT NULL,          -- o que o sistema faz quando ela ignora
  nasceu     text                    -- de onde veio (bug, data, pedido)
);

COMMENT ON TABLE nai_regra IS
  'As regras ensinadas a ela, uma por conferencia. Da nome e texto ao que `nai_conferencia` ja grava (Tel, 19/09).';

-- As 17, na ordem em que rodam. Os textos saem do proprio `Arquivos/nai/15_conferencia.sql`
-- e do `REGRAS-E-BUGS.md` -- nada aqui foi inventado.
INSERT INTO nai_regra (etapa, ordem, tipo, titulo, regra, o_que_faz, nasceu) VALUES
 ('imovel_da_conversa', 1, 'fluxo',
  'De qual imóvel é a conversa',
  'Quando ele diz "esse" ou "dele", é do imóvel que já estava em jogo -- não se pergunta de novo.',
  'Descobre o código pelo card marcado, pelo que ele escreveu ou pela conversa, e grava no turno.',
  'bug 31 (14/09): "marquei o imóvel e ela não identificou"'),

 ('fotos_do_site', 2, 'fluxo',
  'Foto que falta no banco é lida do anúncio',
  'Se o imóvel é nosso e está no ar, a foto existe -- mesmo que o banco não tenha.',
  'Lê o anúncio ao vivo e grava as fotos antes de responder. Nunca apaga.',
  'bug 12 (01/09): "não temos imagens" com 24 fotos no anúncio'),

 ('promessa_ou_sem_resposta', 3, 'parede',
  'Não existe "vou ver e te aviso"',
  'Ou ela responde com a base, ou o Tel responde. Ela nunca promete retorno.',
  'Troca pela resposta da ficha; não havendo, sobe ao Tel e para o chat.',
  'CLAUDE.md: capacidade ausente vira promessa (quatro bugs em dois dias)'),

 ('resposta_sem_consulta', 4, 'parede',
  'Não afirme sobre imóvel sem consultar',
  'Ela só afirma um fato depois de uma ferramenta ter devolvido esse fato.',
  'Troca pela resposta da ficha; não havendo, sobe ao Tel e para o chat.',
  'bugs 19 e 23 (12-13/09): "O 5611 é semimobiliado" sem consultar nada'),

 ('formato_da_base', 5, 'parede',
  'O formato da resposta é o do Tel, não o do modelo',
  'Quando a ficha tem a resposta pronta, é ela que sai -- palavra por palavra.',
  'Substitui o texto do modelo pelo da base.',
  'bug 26 (13/09): pergunta com a resposta na base subiu ao Tel'),

 ('silencio', 6, 'fluxo',
  'Quando calar',
  'Depois de escalar, e quando ele só agradece, ela não responde nada.',
  'Interrompe: nenhuma mensagem é montada.',
  'prompt, seção QUANDO RESPONDER SILENCIO'),

 ('voz_sem_emoji', 7, 'ajuste',
  'Sem emoji com proprietário e Fernando',
  'Emoji nunca, nem no fim da despedida. Risada escrita também não.',
  'Tira os emoji do texto.',
  'prompt da captação: "denunciam robô na hora"'),

 ('sugerir_visita', 8, 'fluxo',
  'Sugerir visita, uma vez por dia',
  'Depois de informar o imóvel, ela convida para visita -- no máximo uma vez por dia.',
  'Manda a sugestão em mensagem separada, depois da resposta.',
  'fluxo v10/v11 do editor (11/09)'),

 ('sugestao_repetida', 9, 'parede',
  'Não insistir em visita',
  'Se já sugeriu visita hoje, não sugere de novo. Só se ELE pedir.',
  'Corta a frase de sugestão da resposta.',
  'Tel (11/09): "visita sem forçar a barra"'),

 ('negou_imovel_que_existe', 10, 'parede',
  'Não negar imóvel que existe',
  'Se ele citou um código que é nosso e está no ar, ela não diz que não encontrou.',
  'Troca a negativa pelo card do imóvel.',
  'CLAUDE.md: "não encontrei o imóvel pelo código X"'),

 ('visita_sem_ferramenta', 11, 'parede',
  'Não falar de visita sem chamar a ferramenta',
  'Frases como "visita confirmada" ou "esse horário já passou" só saem se a ferramenta rodou.',
  'Tira a frase, avisa o Tel e PARA o chat.',
  'bug 25 (13/09): "esse horário já passou" sem chamar a ferramenta'),

 ('citou_o_tel', 12, 'parede',
  'Nunca citar o Tel',
  'Quem sobe para o Tel não conta para ninguém. Nada de "vou passar para o Tel".',
  'Tira a frase inteira que menciona o Tel.',
  'Tel (11/09): "o proprietário NÃO fica sabendo"'),

 ('uma_pergunta_por_mensagem', 13, 'ajuste',
  'Uma pergunta por mensagem',
  'Bairro, faixa de preço e mobília são três perguntas -- uma de cada vez.',
  'Devolve só a primeira pergunta da sequência.',
  'prompt: "uma pergunta por mensagem"'),

 ('markdown', 14, 'ajuste',
  'WhatsApp não é markdown',
  'Nada de ** nem # -- chegam como símbolo solto na tela do corretor.',
  'Limpa os símbolos do texto.',
  'prompt: "escreva sem emoji e sem markdown"'),

 ('portao_de_fotos', 15, 'fluxo',
  'Fotos vão junto da informação',
  'Falou de imóvel, saem informação e fotos -- menos para quem diz que já tem.',
  'Decide se as fotos daquele imóvel entram na resposta.',
  'Tel (16/09), pedido três vezes na mesma lista'),

 ('negou_foto_que_existe', 16, 'parede',
  'Não negar foto que existe',
  'Se ele pediu foto e a foto está no banco, ela não diz que não tem.',
  'Troca a negativa por "segue as fotos" e manda as fotos.',
  'bug 7 (01-02/09) e bug 12'),

 ('foto_que_nao_existe', 17, 'parede',
  'Não prometer foto que não existe',
  'Imóvel sem foto em lugar nenhum: ela não promete, e o Tel é avisado.',
  'Tira a frase de promessa e avisa o Tel.',
  'conferência 17, reescrita em 14/09 (antes ela prometia retorno)')
ON CONFLICT (etapa) DO UPDATE
   SET ordem = EXCLUDED.ordem, tipo = EXCLUDED.tipo, titulo = EXCLUDED.titulo,
       regra = EXCLUDED.regra, o_que_faz = EXCLUDED.o_que_faz, nasceu = EXCLUDED.nasceu;


-- =====================================================================
-- 2. QUAIS REGRAS ELA MAIS IGNORA
-- =====================================================================
-- A tela que responde a pergunta do Tel. Uma linha por regra, ordenada pelo
-- que mais dói.
--
-- Duas contagens diferentes, e a distinção importa:
--   `seguiu`  -- a regra foi exercida e ela cumpriu sozinha
--   `ignorou` -- ela não cumpriu, e o sistema teve que agir
--
-- `nunca_exercida` marca regra que passou mas nunca precisou agir. ISSO NÃO É
-- REGRA MORTA -- é parede que não foi testada. Tirar a parede porque não houve
-- incêndio é o erro que esta coluna existe para evitar.
CREATE OR REPLACE VIEW vw_nai_regras_ignoradas AS
WITH c AS (
  SELECT etapa,
         count(*)                                                  AS passagens,
         count(*) FILTER (WHERE resultado = 'passou')               AS seguiu,
         count(*) FILTER (WHERE resultado IN ('mudou','cortou'))    AS corrigida,
         count(*) FILTER (WHERE resultado = 'parou')                AS parou,
         max(criado_em)                                             AS ultima_vez,
         max(criado_em) FILTER (WHERE resultado <> 'passou')         AS ultima_vez_ignorada,
         (array_agg(turno_id ORDER BY criado_em DESC)
            FILTER (WHERE resultado <> 'passou'))[1:8]              AS ultimos_turnos
    FROM nai_conferencia
   WHERE criado_em > now() - interval '30 days'
   GROUP BY etapa
)
SELECT r.etapa,
       r.ordem,
       r.tipo,
       r.titulo,
       r.regra,
       r.o_que_faz,
       r.nasceu,
       coalesce(c.passagens, 0)                                     AS passagens,
       coalesce(c.seguiu, 0)                                        AS seguiu,
       coalesce(c.corrigida, 0) + coalesce(c.parou, 0)              AS ignorou,
       coalesce(c.corrigida, 0)                                     AS corrigida,
       coalesce(c.parou, 0)                                         AS parou,
       round(100.0 * (coalesce(c.corrigida, 0) + coalesce(c.parou, 0))
             / greatest(coalesce(c.passagens, 0), 1), 1)            AS pct_ignorou,
       c.ultima_vez,
       c.ultima_vez_ignorada,
       c.ultimos_turnos,
       (coalesce(c.passagens, 0) > 0
        AND coalesce(c.corrigida, 0) + coalesce(c.parou, 0) = 0)     AS nunca_exercida,
       CASE
         WHEN coalesce(c.passagens, 0) = 0 THEN 'sem dado'
         WHEN coalesce(c.corrigida, 0) + coalesce(c.parou, 0) = 0 THEN 'sempre seguiu'
         WHEN r.tipo = 'parede'
          AND 100.0 * (coalesce(c.corrigida,0) + coalesce(c.parou,0))
              / greatest(coalesce(c.passagens,0),1) >= 5           THEN 'IGNORA MUITO'
         WHEN coalesce(c.corrigida, 0) + coalesce(c.parou, 0) > 0   THEN 'ignora às vezes'
         ELSE 'sem dado'
       END                                                          AS veredito
  FROM nai_regra r
  LEFT JOIN c ON c.etapa = r.etapa
 ORDER BY
   -- Parede ignorada vem primeiro, sempre. Depois o resto, pela frequência.
   (r.tipo = 'parede' AND coalesce(c.corrigida,0) + coalesce(c.parou,0) > 0) DESC,
   coalesce(c.corrigida, 0) + coalesce(c.parou, 0) DESC,
   r.ordem;

COMMENT ON VIEW vw_nai_regras_ignoradas IS
  'Quais regras ela ignora, quantas vezes e em quais conversas. Parede ignorada vem primeiro (Tel, 19/09).';


-- =====================================================================
-- 3. O RESUMO EM UMA LINHA
-- =====================================================================
-- Para o topo da tela: de cada 100 vezes que uma REGRA DE PAREDE foi exercida,
-- quantas ela cumpriu sozinha? É o número que diz se está melhorando.
--
-- Só `parede` entra na conta: misturar markdown e emoji com "não prometa foto
-- que não existe" produz um número que sobe quando nada importante melhorou.
CREATE OR REPLACE VIEW vw_nai_obediencia AS
WITH base AS (
  SELECT (c.criado_em AT TIME ZONE 'America/Manaus')::date AS dia,
         c.resultado,
         r.tipo
    FROM nai_conferencia c
    JOIN nai_regra r ON r.etapa = c.etapa
   WHERE c.criado_em > now() - interval '30 days'
)
SELECT dia,
       count(*) FILTER (WHERE tipo = 'parede')                                 AS paredes_exercidas,
       count(*) FILTER (WHERE tipo = 'parede' AND resultado = 'passou')        AS paredes_seguidas,
       count(*) FILTER (WHERE tipo = 'parede' AND resultado <> 'passou')       AS paredes_ignoradas,
       round(100.0 * count(*) FILTER (WHERE tipo = 'parede' AND resultado = 'passou')
             / greatest(count(*) FILTER (WHERE tipo = 'parede'), 1), 1)        AS pct_obediencia,
       count(*) FILTER (WHERE tipo = 'ajuste' AND resultado <> 'passou')       AS ajustes_de_forma
  FROM base
 GROUP BY dia
 ORDER BY dia DESC;

COMMENT ON VIEW vw_nai_obediencia IS
  'Por dia: de cada 100 regras de PAREDE exercidas, quantas ela cumpriu sozinha (Tel, 19/09).';


-- =====================================================================
-- 4. GRANTS
-- =====================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nay_site_nai') THEN
    EXECUTE 'GRANT SELECT ON nai_regra, vw_nai_regras_ignoradas, vw_nai_obediencia TO nay_site_nai';
  END IF;
END $$;
