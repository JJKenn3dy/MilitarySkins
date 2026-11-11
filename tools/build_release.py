"""Собрать архив для игроков в dist/ в том же виде, что и исходный пакет.

Запуск из корня репозитория: python tools/build_release.py
Перед сборкой проверяет, что manifest.json совпадает с файлами.
"""
from pathlib import Path
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'MilitarySkins_Package'
manifest = json.loads((PACKAGE / 'manifest.json').read_text(encoding='utf-8-sig'))
for item in manifest['files']:
    path = PACKAGE / 'payload' / item['name'].replace('\\', '/')
    assert hashlib.sha256(path.read_bytes()).hexdigest() == item['sha256'], \
        f'{item["name"]} не совпадает с manifest.json, запусти tools/update_manifest.py'

entries = ['Install_MilitarySkins.cmd', 'Rollback_MilitarySkins.cmd', 'README_RU.md',
           'MilitarySkins_Package/install.ps1', 'MilitarySkins_Package/manifest.json']
entries += [f'MilitarySkins_Package/payload/{item["name"].replace(chr(92), "/")}' for item in manifest['files']]

out = ROOT / 'dist' / f'MilitarySkins_Cloud_{manifest["version"]}.zip'
out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for entry in entries:
        archive.write(ROOT / entry, entry)
digest = hashlib.sha256(out.read_bytes()).hexdigest()
print(f'{out} {out.stat().st_size} байт\nSHA256 {digest}')
