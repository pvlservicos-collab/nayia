-- testes da 422 (dentro do ensaio)
\pset pager off
SET ROLE nay_disparo;
SELECT crm_olx_busca_parceiro_abrir('{"telefone": "12", "finalidade": "locacao", "teto": 3000, "bairros": ["Flores"]}', 'ensaio') AS tel_ruim;
SELECT crm_olx_busca_parceiro_abrir('{"telefone": "92900001111", "finalidade": "x", "teto": 3000}', 'ensaio') AS sem_finalidade;
SELECT crm_olx_busca_parceiro_abrir('{"telefone": "92900001111", "finalidade": "locacao", "teto": 3000}', 'ensaio') AS sem_bairro;
SELECT crm_olx_busca_parceiro_abrir('{"nome": "Cliente Ensaio", "telefone": "(92) 90000-1111", "finalidade": "locacao", "tipo": "apartamento",
  "teto": "3000", "bairros": ["Parque 10", " "], "quartos": "2", "precisa_elevador": true, "mobilia": "mobiliado"}', 'ensaio') AS abriu;
SELECT crm_olx_busca_parceiro_abrir('{"telefone": "5592900001111", "finalidade": "venda", "teto": 300000, "qualquer_bairro": true}', 'ensaio') AS de_novo;
SELECT x->>'cliente' cliente, x->>'origem' origem, x->>'estado' estado, x->'filtros' filtros
  FROM jsonb_array_elements(crm_olx_buscas_parceiro(1)) x WHERE x->>'cliente_tel' = '92900001111';
RESET ROLE;
