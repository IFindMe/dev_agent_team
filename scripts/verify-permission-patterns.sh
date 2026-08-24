#!/bin/sh
# verify-permission-patterns.sh — test loaded opencode permission-engine semantics in a
# THROWAWAY temp HOME. Prints PASS/FAIL per rule; exit 0=all pass, 1=drift, 2=no runtime.
set -u
T="$(mktemp -d)" || exit 2; trap 'rm -rf "$T"' EXIT
# BIN resolution: OPENCODE_BIN env override -> 'opencode' on PATH -> no runtime (exit 2).
BIN=""
if [ -n "${OPENCODE_BIN:-}" ] && [ -r "$OPENCODE_BIN" ]; then
  BIN="$OPENCODE_BIN"
elif command -v opencode >/dev/null 2>&1; then
  BIN="$(command -v opencode)"
fi
[ -n "$BIN" ] || { echo "FAIL no opencode runtime found (set OPENCODE_BIN or put 'opencode' on PATH)" >&2; exit 2; }
if grep -aqF '.replace(/\*/g,".*").replace(/\?/g,".")' "$BIN"; then
  echo "PASS engine-signature present in loaded binary"
else
  echo "FAIL engine-signature NOT found — binary changed, re-extract Wildcard.match"; exit 1
fi
command -v node >/dev/null || { echo "FAIL no node runtime"; exit 2; }
if HOME="$T" node -e '
function m(i,p){if(i)i=i.replaceAll("\\","/");if(p)p=p.replaceAll("\\","/");
let l=p.replace(/[.+^${}()|[\]\\]/g,"\\$&").replace(/\*/g,".*").replace(/\?/g,".");
if(l.endsWith(" .*"))l=l.slice(0,-3)+"( .*)?";return new RegExp("^"+l+"$","s").test(i)}
const C=[["**/AgentsReport/**","AgentsReport/toolsmith/x.md",false],["AgentsReport/**","AgentsReport/toolsmith/x.md",true],
["**","AgentsReport/x.md",true],["git status*","git status",true],["*","head",true],["edit","edit",true]];
let f=0;for(const[p,i,w]of C){const g=m(i,p);g===w||f++;console.log((g===w?"PASS":"FAIL")+" match("+JSON.stringify(i)+","+JSON.stringify(p)+")="+g+" want "+w)}
process.exit(f?1:0)'; then
  echo "RESULT: engine matches documented semantics"
else
  echo "RESULT: DRIFT — re-read binary"; exit 1
fi
