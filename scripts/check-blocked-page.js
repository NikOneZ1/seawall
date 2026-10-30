// Checks the blocked page's try count: `node scripts/check-blocked-page.js`.
// Runs the page's real shell script (taken from BlockedPageParts.swift) against a tiny DOM stub.
const fs = require('fs');
const path = require('path');
const assert = require('assert');

const swift = fs.readFileSync(path.join(__dirname, '../Sources/SeawallCore/BlockedPageParts.swift'), 'utf8');
const shellJS = swift.match(/static let shellJS = ##"""\n([\s\S]*?)\n"""##/)[1];

function load(search) {
  const els = {};
  const el = id => (els[id] ??= { id, textContent: '', innerHTML: '', hidden: false });
  const sandbox = {
    location: { search },
    document: { getElementById: el, querySelectorAll: () => [], title: '' },
    matchMedia: () => ({ matches: false }),
    localStorage: { getItem: () => null, setItem() {} },
  };
  const SW = new Function(...Object.keys(sandbox), shellJS + '\nreturn SW;')(...Object.values(sandbox));
  SW.render();
  return { SW, foot: el('foot').innerHTML };
}

let failed = 0;
const check = (name, fn) => {
  try { fn(); console.log('ok   ' + name); } catch (e) { failed++; console.log('FAIL ' + name + '\n     ' + e.message); }
};

const until = Math.floor(Date.now() / 1000) + 3600;
const { SW } = load('?n=1');
const ordinals = { 1: '1st', 2: '2nd', 3: '3rd', 4: '4th', 11: '11th', 12: '12th', 13: '13th', 21: '21st', 22: '22nd',
  101: '101st', 111: '111th', 112: '112th', 113: '113th', 23: '23rd', 100: '100th', 1011: '1011th', 1021: '1021st' };
for (const [n, want] of Object.entries(ordinals)) check(`ord(${n}) == ${want}`, () => assert.strictEqual(SW.ord(+n), want));

check('n=3 shows "3rd try this block"', () => {
  const { SW, foot } = load(`?until=${until}&n=3&url=x`);
  assert.strictEqual(SW.tries, 3);
  assert.ok(foot.includes('<span>3rd try this block</span>'), foot);
});
check('n=21 without until shows only the count', () =>
  assert.strictEqual(load('?n=21&url=x').foot, '<span>21st try this block</span>'));

for (const q of ['', 'n=', 'n=%20', 'n=abc', 'n=0', 'n=-2', 'n=3.5', 'n=1e2', 'n=0x10', 'n=99999999999999999999']) {
  check(`"?${q}" shows no count`, () => {
    const { SW, foot } = load(`?until=${until}&${q}&url=x`);
    assert.strictEqual(SW.tries, 0);
    assert.ok(!foot.includes('try'), foot);
    // Only the time left remains: no empty span, no dangling separator.
    assert.match(foot, /^<span>[^<]+ left<\/span>$/);
  });
}
check('no until and no n leaves the footer empty', () => assert.strictEqual(load('?url=x').foot, ''));

console.log(failed ? `\n${failed} failed` : '\nall passed');
process.exit(failed ? 1 : 0);
