# Predaja: log index u Nethermindu na i9 (2026-10-23)

Cilj: izmjeriti može li `acutis` posluživati `eth_getLogs` preko cijelog prozora povijesti (367 dana) u jednom upitu. O tome ovisi hoće li popis EURe uplata u `pay.domovina.ai` (`/api/activity`) čitati naš čvor umjesto Blockscouta. Odluka i kriteriji prihvaćanja su u [ADR-013](02-decisions.md#adr-013).

**Ishod (2026-10-23):** backfill gotov za ~55 min, index 3,2 GB, upit preko cijelog prozora 0,1–0,9 s lokalno. Kriteriji iz ADR-013 su ispunjeni lokalno, kroz tunel još treba izmjeriti s Mac Minija. Detalji su u tablici u koraku 4.

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

| Mjera | Vrijednost (2026-10-23) |
| --- | --- |
| početak backfilla (vrijeme restarta) | restart 10:12:27, baza otvorena i backfill krenuo 10:17:36 (pivot #48.898.093, 6.348.093 blokova unatrag) |
| kraj backfilla | ~11:12 (≈ 55 min, ~1.000–2.000 blk/s). Stao je na 99,89 % jer je pruner već obrisao 7.056 blokova iznad `NM_HISTORY_FROM_BLOCK`, vidi niže |
| veličina `logIndex` (`dbSize`) | 3,2 GB (`du`: 3,1 G) |
| slobodno prije / poslije | 213 GB / 211 GB |
| CPU Netherminda tijekom backfilla | ~266 % (2,7 jezgre); nakon backfilla 20–55 % |
| `eth_getLogs` cijeli prozor, lokalno | dolazni EURe na Safe: 105 logova, 0,88 s hladno, 0,10–0,20 s toplo; odlazni 105 logova 0,19 s; svi tokeni prema Safeu 0,10 s; batch 105 × `eth_getBlockByNumber(false)` 0,04 s |
| isto kroz tunel | čeka Mac Mini |
| `current.fromBlock` nakon 24 h (prati li pomični prozor?) | otvoreno; u 13:00 `current.fromBlock` = 42.557.056, ispod stvarne granice pruninga (42.558.336) |

Baze prije uključivanja (10:12): `state` 148G, `blocks` 99G, `receipts` 37G, `headers` 16G, ukupno 307G.

### Što je mjerenje pokazalo, a predaja nije predvidjela

- **`target.fromBlock` nikad neće biti dosegnut.** Cilj je `NM_HISTORY_FROM_BLOCK` (42.550.000), a pruner je u međuvremenu obrisao sve ispod `head − 198.180 × 32`. Backfill je gotov kad `Log index sync (Backward)` u logu stoji, a `current.fromBlock` je ispod granice pruninga.
- **Donja granica upita je granica pruninga, ne `current.fromBlock`.** `fromBlock` ispod najstarijeg receipta vraća `Pruned history unavailable`. U 13:00 najniži prihvaćeni `fromBlock` bio je `head − 6.341.958`, a formula `head − 6.341.760`. Razlika postoji jer pruner radi svakih 20–40 min. Klijent neka koristi `head − 6.330.000` (~16 h rezerve) i na tu grešku ponovi s višim `fromBlock`.
- **`fromBlock: "earliest"` ne radi.** Raspon ispod indexa ide starim putem i pada na limitu 10.000 blokova („reads 42557121 blocks without the log index”).
- **Najviše 20.000 logova po odgovoru** (`-32005 Too many logs requested`). Za jednu adresu je to daleko. Svi EURe Transferi rade se u komadima: 20.000 blokova dalo je 19.034 loga.

## 5. Povratak (ako ne prođe)

```bash
cd ~/git/domovinatv/domovina-gnosis-node && sed -i '' 's/^NM_LOG_INDEX=.*/NM_LOG_INDEX=false/' config/node.env && sudo scripts/30-services.sh install nethermind && sudo find /opt/gnosis/data/nethermind -maxdepth 3 -type d -name logIndex
```

Mapu koju `find` pokaže obriši tek kad je Nethermind ponovno gore i sinkroniziran (`sudo rm -rf <ta mapa>`). Pokreni prvo `find`, pa pogledaj putanju prije brisanja.

## 6. Nakon prihvaćanja (Mac Mini, `pay.domovina.ai`)

- Prvo izmjeri upit iz koraka 4 kroz tunel i upiši rezultat u tablicu. `fromBlock` neka bude `head − 6.330.000`, a ne vrijednost iz predaje (`head − 6.300.000` je također u redu).
- `/api/activity` čita popis s `eth_getLogs` preko cijelog prozora (`fromBlock = head − 6.330.000`; na `Pruned history unavailable` ponovi s višim `fromBlock`; ne koristi `earliest`; najviše 20.000 logova po odgovoru), a vremena dobiva jednim batchom `eth_getBlockByNumber` (`false`, bez transakcija). Blockscout ostaje rezerva za grešku čvora i za adrese starije od 367 dana.
- Cron indexer (`onchainIndexer.ts`, sada `CHUNK = 5_000`) može ići u većim komadima kad čita s čvora.
- Trajna arhiva EURe uplata je baza Workera, a ne čvor ([ADR-014](02-decisions.md#adr-014)). Indexer redovito sprema nove logove s čvora, a povijest stariju od 367 dana učita jednokratno iz Blockscouta ili arhivskog RPC-a.
- ADR-013 iz „predloženo” prelazi u „prihvaćeno”, s izmjerenim brojkama.

## Otvoreno

- Trajanje tokena `eure-reader`: provjeri u Zero Trust → Access → Service credentials. Ako je godinu dana, dodaj podsjetnik za rotaciju (postupak je u ADR 0031 u `pay.domovina.ai`).

## Vezani dokumenti

- [Predaja tunela `acutis`](2026-10-22-predaja-acutis-tunel.md)
- [ADR-010](02-decisions.md#adr-010), [ADR-011](02-decisions.md#adr-011), [ADR-013](02-decisions.md#adr-013), [ADR-014](02-decisions.md#adr-014)
