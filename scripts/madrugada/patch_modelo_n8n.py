#!/usr/bin/env python3
"""TODOS OS NÓS DO n8n NO MESMO MODELO (Pedro, 01/10/2026).

"preciso que troque a api para o gpt6 luna na Nay, tá gastando muito" e "quero
todos os laços do n8n usando o luna de todas as VPS".

Troca `parameters.model` (o `value` e o `cachedResultName`, que é só o rótulo
que a interface mostra) de TODO nó que tem modelo, em todos os fluxos do
export. Não mexe em mais nada.

Levantado em 01/10, antes da troca:
  VPS1 (nay-srv1894338, 7 nós): NAI atendimento locação tem 4 (corretor,
    proprietário, Fernando, secretária) em gpt-5.6-sol; "Nay - captacao
    proprietarios" 1 em gpt-5.6-sol; "Nay- recebe mensagem" e "Nay Cerebro"
    já estavam em gpt-5.6-luna.
  VPS2 (nay-srv1877774, 1 nó): a captação que roda de verdade, em gpt-5.6-sol.

Uso: patch_modelo_n8n.py <export.json> <saida.json> [modelo]
Falha (exit 1) sem escrever nada se não houver nó nenhum para trocar.
"""
import json
import sys

MODELO = 'gpt-6-luna'


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    entrada, saida = sys.argv[1], sys.argv[2]
    modelo = sys.argv[3] if len(sys.argv) > 3 else MODELO

    with open(entrada, encoding='utf-8') as f:
        dados = json.load(f)
    fluxos = dados if isinstance(dados, list) else [dados]

    trocados, iguais = [], []
    for fluxo in fluxos:
        for no in fluxo.get('nodes', []):
            p = no.get('parameters') or {}
            m = p.get('model')
            if isinstance(m, dict):
                antes = m.get('value')
                if not isinstance(antes, str) or not antes.startswith('gpt'):
                    continue
                if antes == modelo:
                    iguais.append((fluxo.get('name'), no.get('name')))
                    continue
                m['value'] = modelo
                if 'cachedResultName' in m:
                    m['cachedResultName'] = modelo
            elif isinstance(m, str):
                if not m.startswith('gpt'):
                    continue
                if m == modelo:
                    iguais.append((fluxo.get('name'), no.get('name')))
                    continue
                p['model'] = modelo
            else:
                continue
            trocados.append((fluxo.get('name'), no.get('name'), antes if isinstance(m, dict) else m))

    for f, n, antes in trocados:
        print('   %s / %s: %s -> %s' % (f, n, antes, modelo))
    for f, n in iguais:
        print('   %s / %s: já estava em %s' % (f, n, modelo))
    if not trocados:
        print('nenhum nó para trocar: não escrevi nada')
        return 1

    with open(saida, 'w', encoding='utf-8') as f:
        json.dump(dados, f, ensure_ascii=False, indent=2)
    print('%d nó(s) trocado(s); patch em %s' % (len(trocados), saida))
    return 0


if __name__ == '__main__':
    sys.exit(main())
