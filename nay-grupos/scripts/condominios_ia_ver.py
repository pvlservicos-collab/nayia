"""Mostra a resposta crua do modelo para um condomínio (depuração da sugestão da IA, 348).

    python -m scripts.condominios_ia_ver "Maison Rochelle" "Nossa Senhora das Graças"
"""
import json
import sys

from scripts.condominios_ia import limpar, perguntar

nome = sys.argv[1]
bairro = sys.argv[2] if len(sys.argv) > 2 else None
r = perguntar(nome, bairro)
print(json.dumps(r, ensure_ascii=False, indent=1))
print("limpo:", json.dumps(limpar(r or {}), ensure_ascii=False))
