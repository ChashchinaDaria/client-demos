#!/usr/bin/env bash
# check-secrets.sh — поиск секретов перед commit.
#
# Показывает ТОЛЬКО имя файла, строку и тип совпадения.
# Само значение секрета никогда не печатается.
#
# Использование:
#   bash scripts/check-secrets.sh            # рабочая копия (без игнорируемых)
#   bash scripts/check-secrets.sh --staged   # только staged файлы
#
# Коды возврата:
#   0 — чисто
#   1 — найдены совпадения
#   2 — сам скрипт не смог отработать (grep сломан и т.п.)
#
# ВАЖНО про grep:
#   GNU grep 3.0 в составе Git for Windows аварийно завершается (SIGABRT)
#   при одновременных -i и -F. Поэтому используется -i с экранированным
#   BRE-шаблоном, без -F. Не добавлять -F к -i.
#
#   Ошибки grep НЕ подавляются: молча "чистый" сканер секретов опаснее,
#   чем его отсутствие. Любой сбой -> exit 2.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 2

STAGED=0
[ "${1:-}" = "--staged" ] && STAGED=1

FOUND=0
BROKEN=0

# Паттерн -> человекочитаемое имя типа
PATTERNS=(
  'api_key:API key'
  'apikey:API key'
  'secret:Secret'
  'token:Token'
  'password:Password'
  'BEGIN PRIVATE KEY:Private key block'
  'ghp_:GitHub personal token'
  'github_pat_:GitHub fine-grained token'
  'sk-ant-:Anthropic API key'
  'sk-:Generic API key'
)

# Экранирование метасимволов BRE, чтобы шаблон искался буквально.
escape_bre() {
  printf '%s' "$1" | sed 's/[][\.*^$\/]/\\&/g'
}

# Файлы, которые сами описывают правила и легитимно содержат слова-триггеры.
is_allowlisted() {
  case "$1" in
    CLAUDE.md|README.md|.gitignore) return 0 ;;
    scripts/check-secrets.sh) return 0 ;;
    scripts/validate-project.sh) return 0 ;;
    scripts/check-published-html.sh) return 0 ;;
    scripts/check-config.js) return 0 ;;
    config/project.example.json) return 0 ;;
    reports/*) return 0 ;;
    templates/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Самопроверка: убеждаемся, что grep вообще работает с нашими флагами.
selftest() {
  local tmp rc
  tmp="$(mktemp)" || { echo "  [BROKEN] не удалось создать временный файл"; return 1; }
  printf 'ghp_CANARYVALUE\nnothing here\n' > "$tmp"

  grep -n -i -e 'ghp_' "$tmp" >/dev/null
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "  [BROKEN] grep не нашел заведомо присутствующий шаблон (rc=$rc)"
    rm -f "$tmp"; return 1
  fi

  grep -n -i -e 'zzz_definitely_absent_zzz' "$tmp" >/dev/null
  rc=$?
  if [ "$rc" -ne 1 ]; then
    echo "  [BROKEN] grep повел себя неожиданно на отсутствующем шаблоне (rc=$rc)"
    rm -f "$tmp"; return 1
  fi

  rm -f "$tmp"
  return 0
}

# Список файлов для проверки.
list_files() {
  if [ "$STAGED" -eq 1 ]; then
    git diff --cached --name-only --diff-filter=ACM
  elif git rev-parse --git-dir >/dev/null 2>&1; then
    # Отслеживаемые + новые, но БЕЗ игнорируемых .gitignore
    git ls-files --cached --others --exclude-standard
  else
    find . -type f \
      -not -path './.git/*' \
      -not -path './node_modules/*' \
      -not -path './archive/*' \
      -not -path './source/*' | sed 's|^\./||'
  fi
}

echo "== check-secrets =="
[ "$STAGED" -eq 1 ] && echo "режим: staged" || echo "режим: рабочая копия"
echo

echo "-- самопроверка grep --"
if selftest; then
  echo "  [ok]   grep работает корректно"
else
  echo
  echo "РЕЗУЛЬТАТ: сканер неисправен. Считать проект НЕПРОВЕРЕННЫМ."
  echo "Push делать НЕЛЬЗЯ до починки скрипта."
  exit 2
fi
echo

echo "-- проверка файлов --"
while IFS= read -r file; do
  [ -z "$file" ] && continue
  [ -f "$file" ] || continue
  is_allowlisted "$file" && continue

  # Пропускаем бинарные файлы
  if ! grep -Iq . "$file" 2>/dev/null; then
    continue
  fi

  for entry in "${PATTERNS[@]}"; do
    pat="${entry%%:*}"
    name="${entry#*:}"
    esc="$(escape_bre "$pat")"

    # rc: 0 — найдено, 1 — не найдено, >=2 — ошибка grep
    matches="$(grep -n -i -e "$esc" "$file")"
    rc=$?

    if [ "$rc" -ge 2 ]; then
      echo "  [BROKEN] grep упал на $file (шаблон: $name, rc=$rc)"
      BROKEN=1
      continue
    fi
    [ "$rc" -ne 0 ] && continue

    while IFS= read -r line; do
      [ -z "$line" ] && continue
      lineno="${line%%:*}"
      # Печатаем только координаты и тип. Значение не показываем.
      echo "  [!] $file:$lineno — совпадение: $name"
      FOUND=1
    done <<< "$matches"
  done
done < <(list_files)

echo
if [ "$BROKEN" -eq 1 ]; then
  echo "РЕЗУЛЬТАТ: сканер отработал не полностью. Считать проект НЕПРОВЕРЕННЫМ."
  exit 2
fi

if [ "$FOUND" -eq 1 ]; then
  echo "РЕЗУЛЬТАТ: найдены возможные секреты. Push делать НЕЛЬЗЯ."
  echo "Проверьте каждый файл вручную. Значения намеренно не показаны."
  exit 1
fi

echo "РЕЗУЛЬТАТ: секретов не найдено."
exit 0
