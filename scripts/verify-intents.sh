#!/bin/zsh
# Comprueba, sin lanzar nada, que un Marcus.app lleva las acciones de Atajos
# y el diccionario AppleScript que debe llevar (ver DEPLOY.md).
#
# Uso:  scripts/verify-intents.sh [dist/Marcus.app]
#
# Falla (exit 1) si falta una acción, una cadena localizada o el sdef.

set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-dist/Marcus.app}"
ACTIONS="$APP/Contents/Resources/Metadata.appintents/extract.actionsdata"
SDEF="$APP/Contents/Resources/Marcus.sdef"
STRINGS_ES="$APP/Contents/Resources/es.lproj/Localizable.strings"
STRINGS_EN="$APP/Contents/Resources/en.lproj/Localizable.strings"

for f in "$ACTIONS" "$SDEF" "$STRINGS_ES" "$STRINGS_EN"; do
  [ -f "$f" ] || { echo "FALTA: $f"; exit 1; }
done

python3 - "$ACTIONS" "$STRINGS_ES" "$STRINGS_EN" "$SDEF" <<'PY'
import json, re, sys
actions_path, es_path, en_path, sdef_path = sys.argv[1:5]
data = json.load(open(actions_path))
actions = data.get("actions", {})
expected = ["OpenInMarcusIntent", "CreateDocumentIntent", "GetDocumentTextIntent",
            "AppendToDocumentIntent", "ExportDocumentIntent", "CountWordsIntent"]
missing = [a for a in expected if a not in actions]
extra = [a for a in actions if a not in expected]
print(f"acciones: {len(actions)} ({', '.join(sorted(actions))})")
if missing:
    print("FALTAN acciones:", missing); sys.exit(1)
if extra:
    print("acciones inesperadas:", extra)

# Las claves que Atajos localizará: títulos, descripciones, parámetros y
# resúmenes; cada una debe estar en los dos .strings del bundle.
def keys(node, out):
    if isinstance(node, dict):
        if "key" in node and isinstance(node["key"], str):
            out.add(node["key"])
        if "formatString" in node and isinstance(node["formatString"], str):
            out.add(node["formatString"])
        for v in node.values():
            keys(v, out)
    elif isinstance(node, list):
        for v in node:
            keys(v, out)
wanted = set()
keys(actions, wanted)
keys(data.get("enums", {}), wanted)
keys(data.get("entities", {}), wanted)
# Literales sin traducción posible (nombres de formato, cadenas vacías).
wanted = {k for k in wanted if k and k not in ("HTML", "PDF", "RTF")}

import plistlib
def strings(path):
    raw = open(path, "rb").read()
    # xcstringstool escribe un plist XML; el en.lproj generado a mano va en
    # el formato clásico "clave" = "valor";
    if raw.lstrip().startswith(b"<?xml") or raw.startswith(b"bplist"):
        return set(plistlib.loads(raw).keys())
    text = raw.decode("utf-8")
    found = re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=', text, re.M)
    return {k.replace('\\"', '"').replace("\\\\", "\\") for k in found}
es = strings(es_path)
en = strings(en_path)
missing_es = sorted(k for k in wanted if k not in es)
missing_en = sorted(k for k in wanted if k not in en)
print(f"cadenas localizables: {len(wanted)}; es.lproj: {len(es)}; en.lproj: {len(en)}")
if missing_es or missing_en:
    print("FALTAN en es.lproj:", missing_es)
    print("FALTAN en en.lproj:", missing_en)
    sys.exit(1)

sdef = open(sdef_path, encoding="utf-8").read()
if 'extends="document"' not in sdef or 'key="scriptingText"' not in sdef:
    print("sdef sin la propiedad text del documento"); sys.exit(1)
print("sdef: Marcus Suite con document.text")
print("OK")
PY
