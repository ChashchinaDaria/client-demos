#!/usr/bin/env bash
# validate-project.sh — проверка структуры и конфигурации проекта.
#
# Использование: bash scripts/validate-project.sh
# Коды возврата: 0 — все проверки прошли, 1 — есть ошибки.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

ERRORS=0
WARNINGS=0

ok()   { echo "  [ok]   $1"; }
fail() { echo "  [FAIL] $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo "  [warn] $1"; WARNINGS=$((WARNINGS + 1)); }

echo "== validate-project =="
echo

# ---------- 1. Обязательные папки ----------
echo "-- структура --"
for d in config source/incoming source/processed clients docs outreach \
         reports reports/screenshots scripts templates/demo \
         templates/outreach templates/client archive; do
  [ -d "$d" ] && ok "папка $d" || fail "нет папки: $d"
done

# ---------- 2. Обязательные файлы ----------
echo
echo "-- обязательные файлы --"
for f in CLAUDE.md README.md .gitignore config/project.example.json \
         docs/index.html docs/.nojekyll docs/robots.txt; do
  [ -f "$f" ] && ok "файл $f" || fail "нет файла: $f"
done

# ---------- 3. Валидность JSON ----------
echo
echo "-- JSON --"
json_check() {
  local f="$1"
  if [ ! -f "$f" ]; then
    return 2
  fi
  if command -v node >/dev/null 2>&1; then
    if node -e "JSON.parse(require('fs').readFileSync('$f','utf8'))" 2>/dev/null; then
      ok "валидный JSON: $f"
    else
      fail "невалидный JSON: $f"
    fi
  elif command -v python3 >/dev/null 2>&1; then
    if python3 -c "import json,sys; json.load(open('$f',encoding='utf-8'))" 2>/dev/null; then
      ok "валидный JSON: $f"
    else
      fail "невалидный JSON: $f"
    fi
  else
    warn "нет node/python — JSON не проверен: $f"
  fi
}

json_check config/project.example.json

if [ -f config/project.local.json ]; then
  json_check config/project.local.json
else
  warn "config/project.local.json отсутствует (создайте из example)"
fi

# ---------- 4. Заполненность локального конфига ----------
echo
echo "-- заполненность config/project.local.json --"
if [ -f config/project.local.json ] && command -v node >/dev/null 2>&1; then
  node scripts/check-config.js 2>/dev/null || warn "check-config.js сообщил о незаполненных полях"
else
  warn "проверка пропущена (нет файла или node)"
fi

# ---------- 5. Секреты ----------
echo
echo "-- секреты --"
if bash scripts/check-secrets.sh >/dev/null 2>&1; then
  ok "секретов не найдено"
else
  fail "check-secrets.sh нашел совпадения (запустите отдельно)"
fi

# ---------- 6. Исходные базы в staging ----------
echo
echo "-- staging --"
if git rev-parse --git-dir >/dev/null 2>&1; then
  STAGED=$(git diff --cached --name-only 2>/dev/null || true)

  BAD=$(echo "$STAGED" | grep -Ei '^source/incoming/.*\.(xlsx|xls|csv|json|pdf|zip)$' || true)
  if [ -n "$BAD" ]; then
    fail "исходные базы в staging:"
    echo "$BAD" | sed 's/^/         /'
  else
    ok "исходных Excel/JSON/PDF в staging нет"
  fi

  ENVBAD=$(echo "$STAGED" | grep -E '(^|/)\.env($|\.)' || true)
  if [ -n "$ENVBAD" ]; then
    fail ".env в staging:"
    echo "$ENVBAD" | sed 's/^/         /'
  else
    ok ".env в staging нет"
  fi

  LOCALBAD=$(echo "$STAGED" | grep -F 'config/project.local.json' || true)
  if [ -n "$LOCALBAD" ]; then
    fail "config/project.local.json в staging"
  else
    ok "локальный конфиг в staging нет"
  fi
else
  warn "не git-репозиторий — проверка staging пропущена"
fi

# ---------- 7. Плейсхолдеры на главной ----------
echo
echo "-- главная страница --"
if [ -f docs/index.html ]; then
  if grep -q '{{' docs/index.html 2>/dev/null; then
    fail "в docs/index.html остались незамененные плейсхолдеры {{...}}"
  else
    ok "незамененных плейсхолдеров нет"
  fi

  grep -qi 'noindex' docs/index.html && ok "noindex присутствует" \
    || fail "в docs/index.html нет noindex"

  grep -qi 'viewport' docs/index.html && ok "viewport присутствует" \
    || fail "в docs/index.html нет viewport"
fi

# ---------- Итог ----------
echo
echo "== итог =="
echo "  ошибок:        $ERRORS"
echo "  предупреждений: $WARNINGS"
echo

if [ "$ERRORS" -gt 0 ]; then
  echo "РЕЗУЛЬТАТ: проверка НЕ пройдена. Push делать нельзя."
  exit 1
fi

echo "РЕЗУЛЬТАТ: проверка пройдена."
exit 0
