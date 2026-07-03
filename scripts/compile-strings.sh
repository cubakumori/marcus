#!/bin/zsh
# Compila los String Catalogs (i18n, decisión D14) a .lproj/Localizable.strings.
#
# Uso:  scripts/compile-strings.sh
#
# Los .xcstrings (Sources/<target>/Localizable.xcstrings) son la fuente de la
# verdad y se editan a mano (o con el editor de Xcode). SwiftPM aún no los
# compila en `swift build`, así que los .strings generados se commitean en
# Sources/<target>/Resources/. Ejecuta este script tras cambiar un catálogo.

set -euo pipefail

cd "$(dirname "$0")/.."

for target in Marcus MarcusPreview; do
  catalog="Sources/$target/Localizable.xcstrings"
  out="Sources/$target/Resources"
  echo "==> $catalog"
  rm -rf "$out"/*.lproj(N)
  xcrun xcstringstool compile "$catalog" --output-directory "$out"

  # xcstringstool omite el inglés (los valores base viven en la clave), pero
  # sin en.lproj el bundle anunciaría solo "es" y Foundation serviría español
  # a usuarios en inglés. Generamos en.lproj con clave = valor.
  mkdir -p "$out/en.lproj"
  python3 - "$catalog" > "$out/en.lproj/Localizable.strings" <<'PY'
import json, sys

def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

catalog = json.load(open(sys.argv[1]))
for key in sorted(catalog["strings"]):
    print(f'"{esc(key)}" = "{esc(key)}";')
PY
done

echo "Listo. Revisa los .lproj generados y commitéalos."
