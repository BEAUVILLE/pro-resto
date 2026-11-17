"""Porte historique PRO RESTO : jamais de renvoi à la vitrine ni d'accès direct à la gestion."""
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HTML = (ROOT / "index.html").read_text(encoding="utf-8")


class SecureOwnerEntry(unittest.TestCase):
    def test_magic_link_owner_access_target(self):
        self.assertIn("https://resto.digiylyfe.com/resa-resto/acces-proprietaire.html", HTML)
        self.assertNotIn('window.location.replace("https://digiylyfe.com/")', HTML)
        self.assertNotIn("resa-resto/gestion.html", HTML)
        self.assertIn("Magic Link", HTML)
        self.assertIn('name="robots" content="noindex,nofollow,noarchive,nosnippet"', HTML)

    def test_only_known_safe_query_params_are_forwarded(self):
        js = r"""
const fs=require("fs"), vm=require("vm"), assert=require("assert");
const html=fs.readFileSync("index.html", "utf8");
const match=html.match(/<script>([\s\S]*?)<\/script>/);
assert(match, "missing redirect script");
const script=match[1];
function go(search) {
  let call=[];
  const window={location:{search,replace(url){call.push(url);}}};
  vm.runInNewContext(script,{window,URL,URLSearchParams});
  assert.equal(call.length,1);
  return new URL(call[0]);
}
let x=go("");
assert.equal(x.origin,"https://resto.digiylyfe.com");
assert.equal(x.pathname,"/resa-resto/acces-proprietaire.html");
assert.equal(x.search,"");
x=go("?site=le-malraux-sarlat&lang=wo&token=not-forwarded");
assert.equal(x.searchParams.get("site"),"le-malraux-sarlat");
assert.equal(x.searchParams.get("lang"),"wo");
assert.equal(x.searchParams.has("token"),false);
x=go("?site=https%3A%2F%2Fevil.example&lang=xx&email=secret");
assert.equal(x.searchParams.has("site"),false);
assert.equal(x.searchParams.has("lang"),false);
assert.equal(x.searchParams.has("email"),false);
x=go("?site=entre2-sarlat&lang=zh");
assert.equal(x.searchParams.get("site"),"entre2-sarlat");
assert.equal(x.searchParams.get("lang"),"zh");
console.log("OK: owner magic-link route only, safe parameters preserved");
"""
        res = subprocess.run(["node", "-e", js], cwd=ROOT,
                             capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stderr)


if __name__ == "__main__":
    unittest.main()
