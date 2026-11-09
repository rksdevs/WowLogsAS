// Runs tests/spec.lua in a Lua VM, after refusing syntax Lua 5.0 does not have.
// Usage, from the addon folder: NODE_PATH=<folder with fengari> node tests/run.js
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

const root = path.resolve(__dirname, '..');
process.chdir(root);

const banned = [
  [/(^|[\s(,=])#[A-Za-z_(]/, '# length operator'],
  [/\bselect\s*\(/, 'select'],
  [/string\.gmatch/, 'string.gmatch'],
  [/string\.match\b/, 'string.match'],
  [/\.\.\.\s*\)\s*$/, 'vararg use'],
  [/[\w)\]]\s+%\s+[\w(]/, '% operator'],
  [/\bgoto\b/, 'goto'],
  [/math\.fmod|table\.unpack|table\.pack/, 'newer library call'],
];
let bad = 0;
for (const file of fs.readdirSync(root).filter((f) => f.endsWith('.lua'))) {
  fs.readFileSync(path.join(root, file), 'utf8').split('\n').forEach((line, i) => {
    const code = line.replace(/--.*$/, '').replace(/"(?:[^"\\]|\\.)*"/g, '""');
    for (const [re, name] of banned) {
      if (re.test(code)) { console.log(`${file}:${i + 1} uses ${name}`); bad += 1; }
    }
  });
}
if (bad) process.exit(1);

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
// Lua 5.0 names missing from the VM; the addon itself relies on these two.
const shim = 'table.getn = function(t) return rawlen(t) end\n' +
  'string.len = string.len\n' +
  'math.ceil = math.ceil\n' +
  // Lua 5.0 has one number type and prints 12, where this VM prints a float as 12.0.
  'local plain = tostring\n' +
  'tostring = function(v)\n' +
  '  if math.type(v) == "float" and v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end\n' +
  '  return plain(v)\n' +
  'end\n';
if (lauxlib.luaL_dostring(L, to_luastring(shim)) !== lua.LUA_OK) throw new Error('shim failed');
if (lauxlib.luaL_dofile(L, to_luastring('tests/spec.lua')) !== lua.LUA_OK) {
  console.error(to_jsstring(lua.lua_tostring(L, -1)));
  process.exit(1);
}
