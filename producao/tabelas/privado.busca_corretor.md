# privado.busca_corretor  (tabela, ~31 linhas)
476: a conversa da Nay dos corretores (nay-olx olx/buscas.py) com cada corretor que oferece imóvel para uma busca.

## colunas
telefone8  text  NOT NULL
telefone  text  NOT NULL
nome  text
ultima_lida  bigint  NOT NULL  padrão 0
busca  bigint
codigo  integer
imovel  jsonb  NOT NULL  padrão '{}'::jsonb
estado  text  NOT NULL  padrão 'conversando'::text
humano_em  timestamp with time zone
criado_em  timestamp with time zone  NOT NULL  padrão now()
atualizado_em  timestamp with time zone  NOT NULL  padrão now()
origem  text   -- 488: como virou corretor da Nay Corretores: grupo | olx | parceria.
classificado_em  timestamp with time zone

## índices
CREATE UNIQUE INDEX busca_corretor_pkey ON privado.busca_corretor USING btree (telefone8)

## restrições
busca_corretor_busca_fkey: FOREIGN KEY (busca) REFERENCES privado.busca_cliente(id) ON DELETE SET NULL
busca_corretor_estado_check: CHECK ((estado = ANY (ARRAY['conversando'::text, 'cadastrando'::text, 'ofertado'::text, 'sem_match'::text, 'humano'::text])))
busca_corretor_origem_check: CHECK (((origem IS NULL) OR (origem = ANY (ARRAY['grupo'::text, 'olx'::text, 'parceria'::text]))))
busca_corretor_pkey: PRIMARY KEY (telefone8)

## permissões
(só o dono)

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
busca_corretor_e, crm_lead_busca_ativa, crm_leads_pipeline_outros, olx_organicos_novos
