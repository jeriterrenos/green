import json
import urllib.request
import urllib.error
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
URL = 'https://lhcmllgnouedddoedgrr.supabase.co/rest/v1/rpc/exec_sql'
KEY = 'sb_publishable_pSaZ1h5Fo-gsrdeNwOe0MA_Q2_YAixr'

chunks_dir = RAIZ / "supabase" / "chunks"

for i in range(6):
    fpath = chunks_dir / f"chunk_{i}.sql"
    with open(fpath, "r", encoding="utf-8") as f:
        sql = f.read()
    payload = json.dumps({"query": sql}).encode("utf-8")
    req = urllib.request.Request(URL, data=payload, headers={
        "apikey": KEY,
        "Authorization": f"Bearer {KEY}",
        "Content-Type": "application/json"
    })
    try:
        with urllib.request.urlopen(req) as resp:
            print(f"Chunk {i} executado com sucesso! Status: {resp.status}")
    except urllib.error.HTTPError as e:
        err = e.read().decode("utf-8", errors="ignore")
        print(f"Chunk {i} falhou: {e.code} - {err}")
