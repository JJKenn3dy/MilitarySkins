"""Выпуск одной командой: python tools/release.py ["что изменилось"]

1. Прибавляет версию (4.4.5 -> 4.4.6) в MilitarySkins.lua, README_RU.md и manifest.json,
   пересчитывает хеши.
2. Коммитит всё в dev и отправляет на GitHub.
3. Публикует релиз (tools/publish_release.py): игроки получат его автоматически.
4. Переводит main на выпущенный коммит.

Запускать из ветки dev, когда изменения уже проверены в игре.
"""
from pathlib import Path
import json
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / 'MilitarySkins_Package'
MAIN = PACKAGE / 'payload/MoonLoader/MilitarySkins.lua'


def run(*args):
    return subprocess.run(args, cwd=ROOT, check=True, capture_output=True, text=True).stdout.strip()


def replace_once(path, pattern, value):
    raw = path.read_bytes().decode('utf-8')
    text, count = re.subn(pattern, value, raw, count=1)
    assert count == 1, f'{path.name}: не найдено {pattern}'
    path.write_bytes(text.encode('utf-8'))


assert run('git', 'rev-parse', '--abbrev-ref', 'HEAD') == 'dev', 'Выпуск делается из ветки dev'
summary = ' '.join(a for a in sys.argv[1:]) or 'обновление'
old = json.loads((PACKAGE / 'manifest.json').read_text(encoding='utf-8-sig'))['version']
major, minor, patch = (int(x) for x in old.split('.'))
version = f'{major}.{minor}.{patch + 1}'

replace_once(MAIN, r"local VERSION='\d+\.\d+\.\d+'", f"local VERSION='{version}'")
replace_once(ROOT / 'README_RU.md', r'# MilitarySkins \d+\.\d+\.\d+', f'# MilitarySkins {version}')
run(sys.executable, '-I', str(ROOT / 'tools/update_manifest.py'), '--version', version)

run('git', 'add', '-A')
run('git', 'commit', '-m', f'{version}: {summary}\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')
run('git', 'push', '-q', 'origin', 'dev')
print(run(sys.executable, '-I', str(ROOT / 'tools/publish_release.py')).splitlines()[-1])
run('git', 'checkout', '-q', 'main')
run('git', 'merge', '-q', '--ff-only', 'dev')
run('git', 'push', '-q', 'origin', 'main')
run('git', 'checkout', '-q', 'dev')
print(f'Выпущена {version} ({old} -> {version}). Игроки получат её в течение 5 минут.')
