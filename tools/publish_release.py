"""Опубликовать релиз на GitHub: после этого игроки получат обновление автоматически.

Запуск из корня репозитория: python tools/publish_release.py [--dry-run]

Проверяет, что изменения закоммичены и отправлены, версия совпадает в manifest.json,
MilitarySkins.lua и install.ps1, хеши верны, а такого тега ещё нет. Затем создаёт релиз
v<версия> на текущем коммите и прикладывает manifest.json (по нему проверяют обновления
игроки) и архив для ручной установки. Токен берётся у git (Git Credential Manager).
"""
from pathlib import Path
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
REPO = 'JJKenn3dy/MilitarySkins'
PACKAGE = ROOT / 'MilitarySkins_Package'
LATEST = f'https://github.com/{REPO}/releases/latest/download/MilitarySkins.zip'
NOTES = """## Установка

1. Скачать архив: [MilitarySkins.zip]({LATEST}), он же в списке файлов ниже.
2. Полностью закрыть GTA.
3. Распаковать архив в папку игры, где лежит gta_sa.exe, с заменой файлов.
4. Запустить Install_MilitarySkins.cmd и дождаться надписи installed.
5. Запустить игру, в игре /mskin.

Ставится один раз. Дальше скрипт сам проверяет новые версии и ставит их без перезахода.
Откат: Rollback_MilitarySkins.cmd при закрытой игре. Назначения, ключи и настройки сохраняются.

Версия {version}."""


def git(*args):
    return subprocess.check_output(['git', *args], cwd=ROOT, text=True).strip()


def token():
    out = subprocess.run(['git', 'credential', 'fill'], cwd=ROOT, input='protocol=https\nhost=github.com\n\n',
                         capture_output=True, text=True, check=True).stdout
    value = dict(line.split('=', 1) for line in out.splitlines() if '=' in line).get('password')
    assert value, 'git не выдал токен GitHub'
    return value


def api(method, url, auth, data=None, content_type='application/json'):
    body = json.dumps(data).encode() if isinstance(data, dict) else data
    request = urllib.request.Request(url, data=body, method=method, headers={
        'Authorization': f'Bearer {auth}', 'Accept': 'application/vnd.github+json',
        'Content-Type': content_type, 'X-GitHub-Api-Version': '2022-11-28'})
    try:
        with urllib.request.urlopen(request) as response:
            return json.loads(response.read() or b'{}')
    except urllib.error.HTTPError as error:
        raise SystemExit(f'GitHub {error.code}: {error.read().decode(errors="replace")}')


manifest = json.loads((PACKAGE / 'manifest.json').read_text(encoding='utf-8-sig'))
version = manifest['version']
tag = f'v{version}'
main = (PACKAGE / 'payload/MoonLoader/MilitarySkins.lua').read_text(encoding='utf-8')
assert re.search(rf"local VERSION='{re.escape(version)}'", main), 'Версия в MilitarySkins.lua не совпадает с manifest.json'
installer = (PACKAGE / 'install.ps1').read_text(encoding='utf-8')
assert f"version='{version}'" in installer or 'version=$package.version' in installer, 'Версия в install.ps1 не совпадает'
assert git('status', '--porcelain') == '', 'Есть незакоммиченные изменения'
branch = git('rev-parse', '--abbrev-ref', 'HEAD')
head = git('rev-parse', 'HEAD')
git('fetch', '--quiet', 'origin')
assert git('rev-parse', f'origin/{branch}') == head, f'Сначала git push origin {branch}'
assert git('ls-remote', '--tags', 'origin', tag) == '', f'Тег {tag} уже существует'

build = subprocess.run([sys.executable, '-I', str(ROOT / 'tools/build_release.py')], capture_output=True, text=True, check=True)
archive = ROOT / 'dist' / f'MilitarySkins_Cloud_{version}.zip'
print(build.stdout.strip())
if '--dry-run' in sys.argv:
    print(f'Проверка пройдена: {tag} на {head[:7]} ({branch}). Без --dry-run релиз будет опубликован.')
    sys.exit(0)

auth = token()
notes = NOTES.format(version=version, LATEST=LATEST)
release = api('POST', f'https://api.github.com/repos/{REPO}/releases', auth,
              {'tag_name': tag, 'target_commitish': head, 'name': f'MilitarySkins {version}', 'body': notes})
upload = release['upload_url'].split('{')[0]
# MilitarySkins.zip: постоянная ссылка releases/latest/download/MilitarySkins.zip на свежую версию.
for name, path, kind in [('manifest.json', PACKAGE / 'manifest.json', 'application/json'),
                         (archive.name, archive, 'application/zip'), ('MilitarySkins.zip', archive, 'application/zip')]:
    api('POST', f'{upload}?name={name}', auth, path.read_bytes(), kind)
print(f'Опубликовано: {release["html_url"]}')
