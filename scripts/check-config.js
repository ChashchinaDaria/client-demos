#!/usr/bin/env node
/**
 * check-config.js — проверка JSON-конфигураций проекта.
 *
 * Использование:
 *   node scripts/check-config.js
 *
 * Проверяет:
 *   - валидность JSON;
 *   - наличие обязательных ключей;
 *   - согласованность public_base_url с custom_domain / github_username;
 *   - заполненность хотя бы одного канала связи отправителя;
 *   - отсутствие секретов в конфиге.
 *
 * Коды возврата: 0 — ок, 1 — есть ошибки.
 */

"use strict";

const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const examplePath = path.join(root, "config", "project.example.json");
const localPath = path.join(root, "config", "project.local.json");

let errors = 0;
let warnings = 0;

const ok = (m) => console.log(`  [ok]   ${m}`);
const fail = (m) => { console.log(`  [FAIL] ${m}`); errors++; };
const warn = (m) => { console.log(`  [warn] ${m}`); warnings++; };

function load(p) {
  if (!fs.existsSync(p)) return null;
  try {
    return JSON.parse(fs.readFileSync(p, "utf8"));
  } catch (e) {
    fail(`невалидный JSON: ${path.relative(root, p)} — ${e.message}`);
    return undefined;
  }
}

console.log("== check-config ==\n");

// ---------- example ----------
console.log("-- config/project.example.json --");
const example = load(examplePath);
if (example === null) {
  fail("файл отсутствует");
} else if (example) {
  ok("валидный JSON");
}

// ---------- local ----------
console.log("\n-- config/project.local.json --");
const local = load(localPath);

if (local === null) {
  warn("файл отсутствует — создайте из project.example.json");
  console.log("\n== итог ==");
  console.log(`  ошибок: ${errors}, предупреждений: ${warnings}`);
  process.exit(errors > 0 ? 1 : 0);
}

if (local === undefined) {
  process.exit(1);
}

ok("валидный JSON");

// ---------- обязательные ключи ----------
const requiredTop = [
  "project_name",
  "github_username",
  "repository_name",
  "custom_domain",
  "public_base_url",
  "sender",
  "defaults",
];

for (const k of requiredTop) {
  if (!(k in local)) fail(`нет обязательного ключа: ${k}`);
}

const requiredSender = ["name", "email", "phone", "telegram", "website"];
if (local.sender && typeof local.sender === "object") {
  for (const k of requiredSender) {
    if (!(k in local.sender)) fail(`нет ключа sender.${k}`);
  }
} else {
  fail("sender отсутствует или не объект");
}

const requiredDefaults = [
  "language",
  "market",
  "first_batch_size",
  "manual_review_required",
  "auto_send_messages",
  "publish_after_validation",
];
if (local.defaults && typeof local.defaults === "object") {
  for (const k of requiredDefaults) {
    if (!(k in local.defaults)) fail(`нет ключа defaults.${k}`);
  }
} else {
  fail("defaults отсутствует или не объект");
}

if (errors > 0) {
  console.log("\n== итог ==");
  console.log(`  ошибок: ${errors}, предупреждений: ${warnings}`);
  process.exit(1);
}

ok("все обязательные ключи на месте");

// ---------- заполненность ----------
console.log("\n-- заполненность --");

const blank = (v) => v === undefined || v === null || String(v).trim() === "";

if (blank(local.github_username)) {
  warn("github_username не заполнен — публикация невозможна");
} else {
  ok(`github_username: ${local.github_username}`);
}

if (blank(local.repository_name)) {
  fail("repository_name пуст");
} else {
  ok(`repository_name: ${local.repository_name}`);
}

// ---------- public_base_url ----------
console.log("\n-- public_base_url --");

const hasDomain = !blank(local.custom_domain);
let expected = null;

if (hasDomain) {
  expected = `https://${String(local.custom_domain).trim()}`;
} else if (!blank(local.github_username)) {
  expected = `https://${local.github_username}.github.io/${local.repository_name}`;
}

if (expected === null) {
  warn("нельзя вычислить public_base_url: нет ни custom_domain, ни github_username");
} else if (blank(local.public_base_url)) {
  warn(`public_base_url пуст. Ожидается: ${expected}`);
} else {
  const actual = String(local.public_base_url).trim().replace(/\/+$/, "");
  if (actual === expected.replace(/\/+$/, "")) {
    ok(`public_base_url согласован: ${actual}`);
  } else {
    fail(`public_base_url не согласован.\n         сейчас:   ${actual}\n         ожидается: ${expected}`);
  }
}

if (hasDomain && /^https?:\/\//i.test(String(local.custom_domain))) {
  fail("custom_domain должен быть без протокола (например: demo.example.ru)");
}

// ---------- каналы связи отправителя ----------
console.log("\n-- отправитель --");

if (blank(local.sender.name)) {
  warn("sender.name не заполнен — письма подписывать нечем");
} else {
  ok(`sender.name: ${local.sender.name}`);
}

const channels = ["email", "telegram", "website"].filter(
  (k) => !blank(local.sender[k])
);

if (channels.length === 0) {
  warn(
    "не заполнен ни один канал связи (email / telegram / website).\n" +
      "         Для отправки сообщений нужен минимум один."
  );
} else {
  ok(`каналы связи: ${channels.join(", ")}`);
}

// ---------- защита от секретов ----------
console.log("\n-- безопасность конфига --");

const raw = fs.readFileSync(localPath, "utf8");
const secretPatterns = [
  [/ghp_[A-Za-z0-9]/, "GitHub personal token"],
  [/github_pat_/, "GitHub fine-grained token"],
  [/sk-ant-/, "Anthropic API key"],
  [/BEGIN [A-Z ]*PRIVATE KEY/, "Private key block"],
  [/"(api_?key|token|password|secret)"\s*:\s*"[^"]+"/i, "Secret-like key"],
];

let secretHit = false;
for (const [re, label] of secretPatterns) {
  if (re.test(raw)) {
    fail(`в конфиге найдено похожее на секрет: ${label}`);
    secretHit = true;
  }
}
if (!secretHit) ok("секретов в конфиге не найдено");

// ---------- защита от небезопасных значений ----------
if (local.defaults.auto_send_messages === true) {
  fail("defaults.auto_send_messages = true — автоотправка запрещена правилами проекта");
}
if (local.defaults.manual_review_required === false) {
  fail("defaults.manual_review_required = false — ручная проверка обязательна");
}

console.log("\n== итог ==");
console.log(`  ошибок: ${errors}, предупреждений: ${warnings}`);

if (errors > 0) {
  console.log("\nРЕЗУЛЬТАТ: конфигурация невалидна.");
  process.exit(1);
}
if (warnings > 0) {
  console.log("\nРЕЗУЛЬТАТ: конфигурация валидна, но не завершена.");
  process.exit(1);
}
console.log("\nРЕЗУЛЬТАТ: конфигурация валидна и заполнена.");
process.exit(0);
