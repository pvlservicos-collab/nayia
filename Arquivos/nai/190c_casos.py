#!/usr/bin/env python3
"""190c -- os casos de 29/09 na bateria (nai_caso) e duas perguntas novas no
nai_rodar_casos: 'pelo_nome' (nai_imovel_pelo_condominio) e 'negocio_valor'
(nai_negocio_pelo_valor). Remenda a funcao VIVA e imprime o SQL."""
import subprocess, sys

def viva(nome):
    q = f"SELECT pg_get_functiondef('{nome}'::regproc)"
    return subprocess.run(['docker', 'exec', 'nay-postgres', 'psql', '-U', 'nay', '-d', 'naydb', '-At', '-c', q],
                          check=True, capture_output=True, text=True).stdout.rstrip('\n')

f = viva('nai_rodar_casos')
ancora = "      WHEN 'valor'      THEN coalesce(nay_maior_valor(c.frase)::text, '-')\n"
if f.count(ancora) != 1:
    sys.exit('ancora nao encontrada')
f = f.replace(ancora, ancora +
    "      WHEN 'pelo_nome'  THEN nai_imovel_pelo_condominio(c.frase, '')::text  -- 190\n"
    "      WHEN 'negocio_valor' THEN coalesce(nai_negocio_pelo_valor(c.frase), '-')  -- 190\n")
print('BEGIN;')
print(f + ';')
print("""
INSERT INTO nai_caso (quando, quem, frase, pergunta, esperado, regra, ativo) VALUES
 ('2026-09-29', 'Sulivam 29/09', 'Ela precisa de mais um cômodo P escritório Ideal 3 quartos', 'nomes',
  'Ela precisa de mais um cômodo P escritório Ideal 3 quartos', 'palavra de gente não vira nome de bairro (cômodo -> Coroado)', true),
 ('2026-09-29', 'corpus 14d', 'estou aqui dentro do condominio', 'nomes',
  'estou aqui dentro do condominio', 'palavra conhecida não é trocada (dentro -> Centro)', true),
 ('2026-09-29', 'corpus 14d', 'tem na luar ponta negra?', 'nomes',
  'tem na luar ponta negra?', 'palavra conhecida só troca por uma letra (luar -> life)', true),
 ('2026-09-29', 'Ponta Negra 29/09', 'Grato Vou encaminhar Tem Vieira Alves e Adrianópolis 3 quartos ?', 'pelo_nome',
  '{}', 'nome de bairro não é pista de condomínio (Adrianópolis -> Jardim Adrianópolis 5748)', true),
 ('2026-09-29', 'Ponta Negra 29/09', 'Me passa a sua lista de vc tem disponível na ponta negra ii de 7mil', 'negocio_valor',
  'locacao', 'o valor diz o negócio da conversa (7 mil = locação)', true),
 ('2026-09-29', 'Ponta Negra 29/09', 'Tem Vieira Alves e Adrianópolis 3 quartos ?', 'negocio_valor',
  '-', '3 quartos não é valor', true),
 ('2026-09-29', 'corpus', 'Bloco 13 apto 1601', 'negocio_valor',
  '-', 'número de apartamento não é valor', true),
 ('2026-09-29', 'Ponta Negra 29/09', 'Me passa a sua lista na ponta negra ii de 7mil || Tem Vieira Alves e Adrianópolis 3 quartos ?', 'negocio_conversa',
  'locacao', 'a conversa guarda o negócio: pediu 7 mil de manhã, segue locação à tarde', true);
COMMIT;""")
