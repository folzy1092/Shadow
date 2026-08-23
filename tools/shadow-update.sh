#!/usr/bin/env bash
#
# Shadow: обновление форка на свежую версию Telegram-iOS.
#
# Что делает:
#   1. Скачивает свежие теги апстрима (TelegramMessenger/Telegram-iOS).
#   2. Находит самую новую release-версию.
#   3. Создаёт ветку update-<версия> и мержит в неё апстрим.
#   4. Если конфликтов нет — пушит ветку, CI собирает IPA.
#   5. Если конфликты есть — пишет UPDATE_REPORT.md, где по каждому
#      конфликтному файлу показано, ЧТО именно форк там менял.
#      Этот файл можно целиком скормить любому ИИ и попросить помочь.
#
# Запуск (из корня репозитория):
#   bash tools/shadow-update.sh
#
# Полезные флаги:
#   --version release-13.0   обновиться на конкретную версию, а не на самую новую
#   --no-push                не пушить, даже если всё смержилось чисто
#   --inventory              только пересобрать FORK_CHANGES.md и выйти
#
set -uo pipefail

UPSTREAM_REMOTE="origin"      # TelegramMessenger/Telegram-iOS
FORK_REMOTE="ghostgram"       # folzy1092/Shadow
FORK_BRANCH="master"
REPORT_FILE="UPDATE_REPORT.md"
INVENTORY_FILE="FORK_CHANGES.md"

TARGET_VERSION=""
DO_PUSH=1
INVENTORY_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        --version) TARGET_VERSION="${2:-}"; shift 2 ;;
        --no-push) DO_PUSH=0; shift ;;
        --inventory) INVENTORY_ONLY=1; shift ;;
        -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
        *) echo "Неизвестный флаг: $1"; exit 1 ;;
    esac
done

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m[x] %s\033[0m\n' "$*"; exit 1; }

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || die "Это не git-репозиторий."

# Последняя версия апстрима, на которой форк уже стоит. Ищем в истории коммит
# слияния вида "Merge tag 'release-X.Y.Z'"; это то, что делает сам этот скрипт
# и что делалось руками раньше.
current_base_version() {
    git log --merges --pretty=%s \
        | grep -o "release-[0-9][0-9.]*" \
        | head -1
}

# --- Инвентаризация: полный список того, что форк поменял относительно апстрима.
# Пересобирается на каждом обновлении, чтобы не устаревала.
write_inventory() {
    local base="$1"
    say "Собираю $INVENTORY_FILE (что форк меняет относительно $base)"

    {
        echo "# Что Shadow меняет в Telegram-iOS"
        echo
        echo "Файл собран автоматически: \`bash tools/shadow-update.sh --inventory\`"
        echo
        echo "База сравнения: **$base**"
        echo "Дата: $(date '+%Y-%m-%d %H:%M')"
        echo
        echo "## Как это читать"
        echo
        echo "- **Свои файлы** — созданы форком, в апстриме их нет."
        echo "  При обновлении они НИКОГДА не конфликтуют. Трогать не нужно."
        echo "- **Правки в файлах апстрима** — вот тут и бывают конфликты при"
        echo "  обновлении. Большая часть таких правок помечена в коде"
        echo "  комментарием со словом \`Shadow:\` или \`AyuGram:\` — по нему их"
        echo "  удобно искать. Но помечено НЕ всё, поэтому единственный"
        echo "  надёжный источник правды — сам diff:"
        echo
        echo "  \`\`\`bash"
        echo "  git diff $base HEAD -- <путь-к-файлу>"
        echo "  \`\`\`"
        echo

        # Вывод git'а разбираем по ТАБУ, а не по пробелу: в путях есть пробелы
        # (например "Images.xcassets/Chat/Context Menu/..."), и разбор по
        # пробелу их обрезает. core.quotePath=false — чтобы кириллица и юникод
        # в путях не превращались в \321\210.
        echo "## Свои файлы форка ($(git diff --name-status "$base" HEAD -- submodules Telegram | grep -c '^A' || echo 0))"
        echo
        git -c core.quotePath=false diff --name-status "$base" HEAD -- submodules Telegram \
            | while IFS="$(printf '\t')" read -r status path _rest; do
                [ "$status" = "A" ] && printf -- "- \`%s\`\n" "$path"
            done | sort
        echo

        echo "## Правки в файлах апстрима ($(git diff --name-status "$base" HEAD -- submodules Telegram | grep -c '^M' || echo 0))"
        echo
        echo "Отсортировано по объёму правок — сверху те, где форк влез сильнее всего."
        echo
        git -c core.quotePath=false diff --numstat "$base" HEAD -- submodules Telegram \
            | while IFS="$(printf '\t')" read -r added deleted path; do
                # Только то, что в апстриме реально ЕСТЬ (свои файлы форка уже
                # перечислены выше). blob — обычный файл; commit — сабмодуль
                # (сдвинут указатель на другой коммит), его тоже показываем.
                # Путь-каталог тоже резолвится (в tree) — вот его отсекаем.
                # ls-tree, а НЕ cat-file: репозиторий склонирован частично
                # (blob:none), и cat-file полез бы тянуть объект по сети — на
                # сабмодуле это просто падает с ошибкой.
                objtype="$(git ls-tree "$base" -- "$path" 2>/dev/null | awk '{print $2}')"
                case "$objtype" in
                    blob)   suffix="строк изменено: $(( ${added//-/0} + ${deleted//-/0} ))" ;;
                    commit) suffix="сабмодуль (сдвинут указатель)" ;;
                    *)      continue ;;
                esac
                printf '%s\t%s\t%s\n' "$(( ${added//-/0} + ${deleted//-/0} ))" "$path" "$suffix"
            done | sort -rn \
            | while IFS="$(printf '\t')" read -r _lines path suffix; do
                printf -- "- \`%s\` — %s\n" "$path" "$suffix"
            done
    } > "$INVENTORY_FILE"

    echo "Готово: $INVENTORY_FILE"
}

BASE_VERSION="$(current_base_version)"
[ -n "$BASE_VERSION" ] || die "Не нашёл в истории, на какой версии апстрима стоит форк."

if [ "$INVENTORY_ONLY" = "1" ]; then
    write_inventory "$BASE_VERSION"
    exit 0
fi

# --- Проверки перед началом ---
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    die "Есть незакоммиченные изменения. Сначала закоммить или спрячь их: git stash -u"
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
say "Текущая ветка: $CURRENT_BRANCH, форк стоит на апстриме $BASE_VERSION"

say "Скачиваю свежие теги апстрима (может занять пару минут)"
git fetch "$UPSTREAM_REMOTE" --tags --quiet || die "Не смог скачать теги апстрима."

if [ -z "$TARGET_VERSION" ]; then
    TARGET_VERSION="$(git tag --list 'release-*' --sort=-v:refname | head -1)"
fi
[ -n "$TARGET_VERSION" ] || die "Не нашёл ни одного тега release-*."

git rev-parse -q --verify "refs/tags/$TARGET_VERSION" >/dev/null \
    || die "Тега $TARGET_VERSION не существует."

if [ "$TARGET_VERSION" = "$BASE_VERSION" ]; then
    say "Уже на самой свежей версии ($TARGET_VERSION). Обновлять нечего."
    write_inventory "$BASE_VERSION"
    exit 0
fi

say "Обновляю: $BASE_VERSION  ->  $TARGET_VERSION"

UPDATE_BRANCH="update-$TARGET_VERSION"
if git rev-parse -q --verify "refs/heads/$UPDATE_BRANCH" >/dev/null; then
    die "Ветка $UPDATE_BRANCH уже есть. Удали её (git branch -D $UPDATE_BRANCH) или доделай начатое."
fi

git checkout -b "$UPDATE_BRANCH" --quiet || die "Не смог создать ветку $UPDATE_BRANCH."
say "Создал ветку $UPDATE_BRANCH, мержу апстрим"

if git merge "$TARGET_VERSION" --no-edit; then
    say "Смержилось БЕЗ конфликтов"
    write_inventory "$TARGET_VERSION"

    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        git add "$INVENTORY_FILE" 2>/dev/null || true
        git commit -m "Shadow: обновление инвентаризации после мержа $TARGET_VERSION" --quiet || true
    fi

    if [ "$DO_PUSH" = "1" ]; then
        say "Пушу ветку $UPDATE_BRANCH — CI соберёт IPA и напишет в Telegram/Discord"
        if git push "$FORK_REMOTE" "$UPDATE_BRANCH"; then
            cat <<EOF

СЛЕДУЮЩИЙ ШАГ
-------------
Ветка запушена. Но CI собирает только ветку $FORK_BRANCH, поэтому:

  1. Дождись, что сборка ветки прошла (если настроена), ЛИБО собери локально.
  2. Убедись, что приложение работает.
  3. Влей в основную ветку и запушь:

       git checkout $FORK_BRANCH
       git merge $UPDATE_BRANCH
       git push $FORK_REMOTE $FORK_BRANCH

Вот после этого CI соберёт итоговый IPA.
EOF
        else
            warn "Push не прошёл. Ветка $UPDATE_BRANCH осталась локально."
        fi
    else
        say "Пуш пропущен (--no-push). Ветка $UPDATE_BRANCH готова локально."
    fi
    exit 0
fi

# --- Конфликты ---
CONFLICTS="$(git diff --name-only --diff-filter=U)"
CONFLICT_COUNT="$(printf '%s\n' "$CONFLICTS" | grep -c . || echo 0)"

warn "Конфликтов: $CONFLICT_COUNT. Собираю отчёт $REPORT_FILE"

{
    echo "# Отчёт по обновлению: $BASE_VERSION -> $TARGET_VERSION"
    echo
    echo "Дата: $(date '+%Y-%m-%d %H:%M')"
    echo "Ветка: \`$UPDATE_BRANCH\`"
    echo "Конфликтных файлов: **$CONFLICT_COUNT**"
    echo
    echo "## Что произошло"
    echo
    echo "Telegram обновил те же файлы, в которых форк делал свои правки."
    echo "Git не смог решить, чей вариант оставить, и попросил помощи."
    echo
    echo "## Что с этим делать"
    echo
    echo "Ниже по каждому конфликтному файлу показано, ЧТО в нём добавлял форк"
    echo "(diff относительно $BASE_VERSION). Задача — перенести эти же правки"
    echo "в новую версию файла."
    echo
    echo "Если сам не разбираешься — скопируй этот файл целиком и отдай любому"
    echo "ИИ с формулировкой: «помоги разрешить конфликты мержа, вот что мой"
    echo "форк менял в этих файлах»."
    echo
    echo "Большая часть правок форка помечена в коде комментарием со словом"
    echo "\`Shadow:\` или \`AyuGram:\`, но помечено не всё — diff'ы ниже полные."
    echo
    echo "Когда закончишь:"
    echo
    echo '```bash'
    echo "git add <файлы>"
    echo "git commit"
    echo "git checkout $FORK_BRANCH && git merge $UPDATE_BRANCH"
    echo "git push $FORK_REMOTE $FORK_BRANCH"
    echo '```'
    echo
    echo "Если решишь всё бросить и откатиться:"
    echo
    echo '```bash'
    echo "git merge --abort"
    echo "git checkout $FORK_BRANCH"
    echo "git branch -D $UPDATE_BRANCH"
    echo '```'
    echo
    echo "---"
    echo
    echo "## Конфликтные файлы"
    echo

    printf '%s\n' "$CONFLICTS" | while read -r file; do
        [ -n "$file" ] || continue
        echo "### \`$file\`"
        echo
        echo "Что форк менял в этом файле:"
        echo
        echo '```diff'
        git diff "$BASE_VERSION" HEAD -- "$file" 2>/dev/null | head -200
        echo '```'
        echo
    done
} > "$REPORT_FILE"

cat <<EOF

КОНФЛИКТЫ: $CONFLICT_COUNT файл(ов)
-----------------------------------
Подробный отчёт с diff'ами форка по каждому файлу: $REPORT_FILE

Список файлов:
$CONFLICTS

Дальше:
  - разрулить конфликты руками (или с ИИ, скормив ему $REPORT_FILE),
  - либо откатиться:  git merge --abort && git checkout $FORK_BRANCH

EOF
exit 1
