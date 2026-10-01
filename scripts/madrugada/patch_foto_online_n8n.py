#!/usr/bin/env python3
"""AS FOTOS DO SITE NOVO PASSAM PELA CONFERÊNCIA DO CABEÇALHO (01/10/2026).

O nó "Conferir cabeçalho" do fluxo da NAI só aceitava foto de
`https://imobeasy.com/system/pictures/` (o site antigo) e da colagem. Resultado:
o imóvel que NÓS cadastramos, cuja foto mora em `imobeasy.online/fotos/<codigo>/`
(ou em `fotos-captacao/olx/<codigo>/`, o que veio da OLX), tinha a foto barrada
como `foto_sem_codigo` -- e a trava de 24 h já tinha sido queimada, então o
corretor não recebia nada e ninguém era avisado. Medido em 30/09: 18 imóveis,
entre eles o 5551 (Alecsandro pediu e não recebeu) e o 9004 (Parque dos Ingleses).

A regra nova é MAIS ESTRITA que a do site antigo: confere o código no caminho
(`/fotos/5551/...` só vale para o imóvel 5551), coisa que o prefixo
`imobeasy.com/system/pictures/` nunca fez.

Uso: patch_foto_online_n8n.py <export-do-n8n.json> <saida.json>
Falha (exit 1) sem escrever nada se não achar exatamente o que espera -- o
fluxo vivo muda, e aplicar um patch às cegas é pior do que não aplicar.
"""
import json
import sys

NO = 'Conferir cabe'          # "Conferir cabeçalho" (o acento varia no export)

DE = """  else if (j.rota === 'send-image' && !(Number(j.codigo) > 0 && (/^https:\\/\\/imobeasy\\.com\\/system\\/pictures\\//.test(String(j.corpo.image || ''))
           || String(j.corpo.image || '') === 'https://imobeasy.online/colagens/' + Number(j.codigo) + '.jpg'))) motivo = 'foto_sem_codigo';"""

PARA = """  else if (j.rota === 'send-image' && !(Number(j.codigo) > 0 && (/^https:\\/\\/imobeasy\\.com\\/system\\/pictures\\//.test(String(j.corpo.image || ''))
           // AS FOTOS DO SITE NOVO (01/10): imovel cadastrado por nos tem a foto em
           // imobeasy.online/fotos/<codigo>/ -- ou em fotos-captacao/<de onde
           // veio>/<codigo>/ (olx, whatsapp, crm). Eram 18 imoveis (5551, 9004...)
           // barrados aqui como foto_sem_codigo, queimando a trava de 24 h sem
           // mandar nada. Aqui o CODIGO no caminho e conferido: /fotos/5551/ so
           // vale para o 5551.
           || new RegExp('^https://imobeasy\\\\.online/fotos(-captacao/[a-z]+)?/' + Number(j.codigo) + '/').test(String(j.corpo.image || ''))
           || String(j.corpo.image || '') === 'https://imobeasy.online/colagens/' + Number(j.codigo) + '.jpg'))) motivo = 'foto_sem_codigo';"""


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    entrada, saida = sys.argv[1], sys.argv[2]
    with open(entrada, encoding='utf-8') as f:
        dados = json.load(f)
    fluxos = dados if isinstance(dados, list) else [dados]

    mexidos = 0
    for fluxo in fluxos:
        for no in fluxo.get('nodes', []):
            if not no.get('name', '').startswith(NO):
                continue
            codigo = no.get('parameters', {}).get('jsCode', '')
            if 'imobeasy.online/fotos' in codigo:
                print('o nó %r já aceita as fotos do site novo: nada a fazer' % no['name'])
                return 1
            if codigo.count(DE) != 1:
                print('não achei o trecho esperado no nó %r (achei %d vezes): não mexi'
                      % (no['name'], codigo.count(DE)))
                return 1
            no['parameters']['jsCode'] = codigo.replace(DE, PARA)
            mexidos += 1
    if mexidos != 1:
        print('esperava mexer em 1 nó "Conferir cabeçalho", mexi em %d: não escrevi nada' % mexidos)
        return 1

    with open(saida, 'w', encoding='utf-8') as f:
        json.dump(dados, f, ensure_ascii=False, indent=2)
    print('patch aplicado em %s' % saida)
    return 0


if __name__ == '__main__':
    sys.exit(main())
