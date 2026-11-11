"""Пересчитать MilitarySkins_Package/manifest.json по файлам payload.

Запуск из корня репозитория: python tools/update_manifest.py
Без пересчёта install.ps1 откажется ставить изменённый файл (Package checksum mismatch).
"""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'MilitarySkins_Package'
PAYLOAD = PACKAGE / 'payload'
manifest_path = PACKAGE / 'manifest.json'

old = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
# Сохранить порядок автора (главный MilitarySkins.lua последним), новые файлы в конец.
position = {f['name'].lower(): i for i, f in enumerate(old['files'])}
files = []
for path in PAYLOAD.rglob('*'):
    if path.is_file():
        name = str(path.relative_to(PAYLOAD)).replace('/', '\\')
        files.append({'name': name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
files.sort(key=lambda f: (position.get(f['name'].lower(), len(position)), f['name'].lower()))

before = {f['name']: f['sha256'] for f in old['files']}
after = {f['name']: f['sha256'] for f in files}
for name in sorted(set(before) | set(after)):
    if before.get(name) != after.get(name):
        state = 'добавлен' if name not in before else 'удалён' if name not in after else 'изменён'
        print(f'{state}: {name}')

text = json.dumps({'version': old['version'], 'files': files}, ensure_ascii=False, indent=2)
manifest_path.write_bytes(text.replace('\n', '\r\n').encode('utf-8'))
print(f'manifest.json: {len(files)} файлов, версия {old["version"]}')
