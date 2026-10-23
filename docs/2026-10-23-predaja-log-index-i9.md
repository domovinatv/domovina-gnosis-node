# Predaja: log index u Nethermindu na i9 (2026-10-23)

Cilj: izmjeriti može li `acutis` posluživati `eth_getLogs` preko cijelog prozora povijesti (367 dana) u jednom upitu. O tome ovisi hoće li popis EURe uplata u `pay.domovina.ai` (`/api/activity`) čitati naš čvor umjesto Blockscouta. Odluka i kriteriji prihvaćanja su u [ADR-013](02-decisions.md#adr-013).

## Stanje u trenutku predaje

- `pay.domovina.ai` PR [#143](https://github.com/domovinatv/pay.domovina.ai/pull/143) (ADR 0031 tog repoa): sva čitanja na serveru idu prvo na `acutis-rpc.mpt.hr`, a javni RPC je rezerva. Secreti `CF_ACCESS_CLIENT_ID`/`CF_ACCESS_CLIENT_SECRET` su postavljeni na Worker `pay-domovina-backend`. Postaju aktivni s deployem nakon mergea.
- Mjerenje bez indexa ([ADR-013](02-decisions.md#adr-013)): najviše 10.000 blokova po upitu, a godina bi trajala oko 145 s.
- Repo: `NM_LOG_INDEX` u `config/node.env.example` (zadano `false`). `30-services.sh` iz njega dodaje `--LogIndex.Enabled true` i modul `LogIndex`.

## 1. i9: prije (bez sudo)

```bash
cd ~/git/domovinatv/domovina-gnosis-node && git pull && scripts/gnosisctl health && df -g /opt/gnosis && sudo du -sh /opt/gnosis/data/nethermind/*/* 2>/dev/null | sort -h | tail -8
```

Zapiši slobodan prostor i veličine baza (`state`, `blocks`, `receipts`).

## 2. i9: uključivanje (sudo, iTerm, jedan red)

```bash
cd ~/git/domovinatv/domovina-gnosis-node && (grep -q '^NM_LOG_INDEX=' config/node.env && sed -i '' 's/^NM_LOG_INDEX=.*/NM_LOG_INDEX=true/' config/node.env || echo 'NM_LOG_INDEX=true' >> config/node.env) && grep '^NM_LOG_INDEX' config/node.env && sudo scripts/30-services.sh install nethermind 2>&1 | tee /tmp/nm-logindex-install.log
```

Restart Netherminda traje ~4,5 min (otvaranje baze). Dok traje, Teku javlja greške Engine API-ja i to je očekivano. Rail za to vrijeme sam prelazi na javni RPC.

Provjera da je flag stvarno u plistu:

```bash
plutil -p /Library/LaunchDaemons/tv.domovina.gnosis.nethermind.plist | grep -A1 -E "LogIndex|EnabledModules"
```

## 3. i9: praćenje backfilla (bez sudo)

Status indexa (raspon koji pokriva, cilj, veličina baze, zadnja greška):

```bash
curl -s 127.0.0.1:8545 -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"logIndex_status","params":[]}' | python3 -m json.tool
```

Svakih 10 min u zasebnom prozoru (prekid s Ctrl-C):

```bash
while :; do date '+%H:%M'; curl -s 127.0.0.1:8545 -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"logIndex_status","params":[]}'; echo; df -g /opt/gnosis | awk 'NR==2{print "free GB", $4}'; sleep 600; done | tee -a /tmp/logindex-progress.log
```

Log: `grep -i "log index\|logindex" /opt/gnosis/logs/nethermind/*.log | tail -20`.

**Prekini** (korak 5) ako slobodan prostor padne ispod 150 GB, ako `lastError` nije prazan ili ako `gnosisctl health` pokaže da head zaostaje više od nekoliko minuta.

## 4. Test kad je `current` jednak `target`

Lokalno na i9 i kroz tunel s Mac Minija. Na Mac Miniju prvo `set -a; . secrets/cf-access-eure-reader.env; set +a`. Upit traži dolazne EURe uplate na MPT Safe kroz cijeli prozor:

```bash
H=$(printf '0x%x' $(( $(curl -s 127.0.0.1:8545 -H 'content-type: application/json' -d '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' | python3 -c 'import sys,json;print(int(json.load(sys.stdin)["result"],16))') - 6300000 )))
time curl -s 127.0.0.1:8545 -H 'content-type: application/json' -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getLogs\",\"params\":[{\"address\":\"0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430\",\"fromBlock\":\"$H\",\"toBlock\":\"latest\",\"topics\":[\"0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef\",null,\"0x000000000000000000000000449abcef4e29a7dd8d98db451af2c463561baf2e\"]}]}" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(len(d.get("result") or []),"logs",d.get("error"))'
```

Kroz tunel s Mac Minija je isto, samo s URL-om `https://acutis-rpc.mpt.hr` i zaglavljima `-H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET"`.

Za usporedbu, bez indexa je 500.000 blokova za istu adresu trajalo 11,5 s i dalo 58 logova (2026-10-23).

Rezultati za upis u [dnevnik](05-operations.md#dnevnik) i u ADR-013:

| Mjera | Vrijednost |
| --- | --- |
| početak backfilla (vrijeme restarta) | |
| kraj backfilla | |
| veličina `logIndex` (`dbSize`) | |
| slobodno prije / poslije | |
| CPU Netherminda tijekom backfilla (`top -l 1 -pid …`) | |
| `eth_getLogs` cijeli prozor, lokalno | |
| isto kroz tunel | |
| `current.fromBlock` nakon 24 h (prati li pomični prozor?) | |

## 5. Povratak (ako ne prođe)

```bash
cd ~/git/domovinatv/domovina-gnosis-node && sed -i '' 's/^NM_LOG_INDEX=.*/NM_LOG_INDEX=false/' config/node.env && sudo scripts/30-services.sh install nethermind && sudo find /opt/gnosis/data/nethermind -maxdepth 3 -type d -name logIndex
```

Mapu koju `find` pokaže obriši tek kad je Nethermind ponovno gore i sinkroniziran (`sudo rm -rf <ta mapa>`). Pokreni prvo `find`, pa pogledaj putanju prije brisanja.

## 6. Nakon prihvaćanja (Mac Mini, `pay.domovina.ai`)

- `/api/activity` čita popis s `eth_getLogs` preko cijelog prozora, a vremena dobiva jednim batchom `eth_getBlockByNumber` (`false`, bez transakcija). Blockscout ostaje rezerva za grešku čvora i za adrese starije od 367 dana.
- Cron indexer (`onchainIndexer.ts`, sada `CHUNK = 5_000`) može ići u većim komadima kad čita s čvora.
- ADR-013 iz „predloženo” prelazi u „prihvaćeno”, s izmjerenim brojkama.

## Otvoreno

- Trajanje tokena `eure-reader`: provjeri u Zero Trust → Access → Service credentials. Ako je godinu dana, dodaj podsjetnik za rotaciju (postupak je u ADR 0031 u `pay.domovina.ai`).

## Vezani dokumenti

- [Predaja tunela `acutis`](2026-10-22-predaja-acutis-tunel.md)
- [ADR-010](02-decisions.md#adr-010), [ADR-011](02-decisions.md#adr-011), [ADR-013](02-decisions.md#adr-013)
