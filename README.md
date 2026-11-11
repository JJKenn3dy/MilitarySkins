# MilitarySkins

MoonLoader-скрипт для SA-MP: показывает выбранным игрокам отдельные облики
(СВ, ОСН, ФБР, Президент) у всех, у кого установлен скрипт. Назначения общие
и приходят из облачного списка. Автор S.Kazama.

Инструкция для игроков: [README_RU.md](README_RU.md).

## Установка

Скачать архив из раздела Releases, распаковать в корень GTA при закрытой игре
и запустить `Install_MilitarySkins.cmd`. Откат: `Rollback_MilitarySkins.cmd`.

## Структура

- `MilitarySkins_Package/payload/MoonLoader` — сам скрипт, модули и модели DFF/TXD.
- `MilitarySkins_Package/manifest.json` — SHA256 каждого файла, по нему проверяет установщик.
- `MilitarySkins_Package/install.ps1` — установка с резервом и откат.
- `tools/` — служебные скрипты для разработки.

## Как вносить изменения

1. Изменить файлы в `payload`.
2. `python tools/update_manifest.py`: пересчитать хеши, иначе установщик откажется ставить.
3. При выпуске новой версии поменять номер в `MilitarySkins.lua` (`script_version` и строки
   с версией), `install.ps1`, `manifest.json` и `README_RU.md`.
4. `python tools/build_release.py`: архив для игроков появится в `dist/`.

Окончания строк в репозитории не преобразуются (`.gitattributes`): иначе хеши разойдутся.
Личные файлы игрока (`cloud_credentials.json`, журналы) в репозиторий не добавлять.
