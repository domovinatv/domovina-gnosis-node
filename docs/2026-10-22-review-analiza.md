# 2026-10-22 — Neovisna review analiza repozitorija, Git povijesti i stanja čvora (Gemini 4 Argon)

> **Autor analize:** Gemini 4 Argon (Antigravity)  
> **Datum:** 2026-10-22 (08:54 CEST)  
> **Opseg:** Snapshot analiza svih 26 commita u Git povijesti (`2026-10-01` → `2026-10-14`, `HEAD` = `b633da4`), svih skripti, konfiguracija i dokumentacije, živog stanja na i9 čvoru (nakon 11+ dana neprekidnog rada) te trenutnog stanja upstream izdanja na GitHubu. Bez izmjena postojećeg koda.

---

## 1. Što kaže Git povijest: tko je što kodirao?

Pregledom `git log` na grani `main` (ukupno **26 commita** između `2026-10-01` i `2026-10-14`):

- **Svih 26 commita u trenutnom repozitoriju potpisuje `Claude Opus 5.5`** (`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`).
- **Antigravity / Gemini (stari nacrt prije 2026-10-01):** Prvotna verzija repozitorija je u potpunosti odbačena i prepisana od nule u prvom commitu `36836c6` (`2026-10-01 18:33`). Razlozi odbacivanja (zastarjele verzije iz 2024., nepostojeći URL-ovi, Lighthouse bez Intel builda, kontradikcija između „zero ingress” i mobilnog RPC-a te curenje statičke IP adrese ureda) detaljno su dokumentirani u [2026-10-01 — prepisivanje i otvorene stavke](2026-10-01-prepisivanje-i-otvorene-stavke.md).
  - *Napomena:* U dokumentaciji piše da se stara grana `antigravity-original` čuva lokalno, no na samom i9 čvoru postoji samo `main` (stara grana je ostala samo na razvojnom M4 Pro stroju, što je sigurnosno dobro).
- **Fable 5.1 / Gemini 3.8:** U Git povijesti `main` grane nema nijednog commita tih modela. Cijeli aktivni codebase i dnevnik prve instalacije na i9 odradio je **Opus 5.5**.

### Opća ocjena postojećeg koda

Kvaliteta koda i dokumentacije koju je Opus 5.5 ostavio je **iznimno visoka**:
- Skripte su čiste, idempotentne, pisane disciplinirano za macOS-ov `/bin/bash` 3.2 (`set -euo pipefail`, `${arr[@]+"${arr[@]}"}`, bez asocijativnih nizova).
- Dijagnostika Nethermind CPU problema nakon prve sinkronizacije (`~1.500 %` → `~530 %` → `~16 %` CPU pomoću `sample`, `dotnet-stack` i `dotnet-trace` te pronalazak Nethermind PR-ova `#14162` i `#14190`) odrađena je na vrhunskoj inženjerskoj razini.
- Najbolji dokaz kvalitete je sam čvor danas (**2026-10-22**): Nethermind (`PID 3951`) i Teku (`PID 18876`) rade **11 dana i 7 sati bez ijednog restarta ili pada**, sinkronizirani na vrhu lanca (`head 0s old`, 48 EL / 37 CL peerova).

Ipak, detaljnim pregledom koda, git diffova i stvarnog stanja sustava pronađeno je **nekoliko konkretnih propusta, rubnih bugova i zaboravljenih stavki** koje vrijedi popraviti.

---

## 2. Propusti i bugovi u kodu (što je Opus 5.5 zaboravio)

### 2.1. `listener/listener.mjs` — nezaštićen `JSON.parse` kod čitanja `watchlist.json`
- **Gdje:** [`listener/listener.mjs`](../listener/listener.mjs#L107-L122) (`refreshWatchlist()`)
- **Problem:** `fs.statSync(WATCHLIST_FILE)` je unutar `try/catch` bloka, ali čitanje i parsiranje na liniji 118 (`const list = JSON.parse(fs.readFileSync(WATCHLIST_FILE, 'utf8'));`) **nije**.
- **Posljedica:** Budući da se `refreshWatchlist()` poziva u svakom `tick()`-u (na svaki novi blok / svakih 5 s), ako admin ili proces koji sinkronizira adrese u tom trenutku zapisuje u `/opt/gnosis/etc/watchlist.json` (djelomični zapis) ili ako se potkrade sintaksna greška u JSON-u, `tick()` baca iznimku i **prekida obradu blokova**, a `watchMtime` se ne ažurira pa svaki idući `tick()` ponovno puca.
- **Preporuka:** Omotati `JSON.parse(fs.readFileSync(...))` u `try/catch`, zalogirati upozorenje i zadržati postojeći `watch` Set u memoriji ako čitanje ne uspije, a pri automatskom ažuriranju `watchlist.json` koristiti atomarni zapis (`tmp` + `mv`, kao kod `saveState`).

### 2.2. `listener/listener.mjs` — trajno keširanje neuspjelih `eth_call` upita u `tokenCache`
- **Gdje:** [`listener/listener.mjs`](../listener/listener.mjs#L137-L151) (`tokenInfo(address)`)
- **Problem:** Ako `rpc('eth_call', ...)` za `symbol()` ili `decimals()` baci prolaznu grešku (npr. kratkotrajni timeout na lokalnom RPC-u), prazni `catch {}` blokovi je progutaju i u `tokenCache` se **trajno** spremi `{ symbol: null, decimals: null }`.
- **Posljedica:** Do idućeg restarta servisa `listener`, sve uplate tog ERC-20 tokena šalju se Workeru s `symbol: null`, `decimals: null` i `amount: null`.
- **Preporuka:** Razlikovati prazan odgovor ugovora (`0x` / revert) od RPC/mrežne greške — ako sam RPC poziv ne uspije, ne spremati rezultat u `tokenCache`.

### 2.3. `listener/listener.mjs` — reorg petlja ne sprema stanje odmah i ne javlja poništene uplate
- **Gdje:** [`listener/listener.mjs`](../listener/listener.mjs#L279-L286)
- **Problem:**
  1. Kod detekcije reorga (`block.parentHash !== prevHash`), listener smanji `state.lastBlock = n - 2` i obriše `state.hashes[n - 1]`, ali **ne pozove `saveState(state)`** prije `continue`. Ako proces stane usred reorga, na disku ostaje stari `lastBlock`.
  2. Ako se dogodi reorg dublji od `CONFIRMATIONS=2` (10 sekundi), webhook za transakciju iz odbačenog bloka je već poslan, a kad novi kanonski blok prođe, Worker ne dobiva nikakvu obavijest da je prethodni `id` poništen.
- **Preporuka:** Pozvati `saveState(state)` odmah pri detekciji reorga; za produkcijski novčanik razmotriti malo veći `CONFIRMATIONS` (npr. 4–6 blokova = 20–30 s) ili u Workeru provjeriti konačnost transakcije prije kritičnih akcija.

### 2.4. `scripts/40-validator.sh` — nesigurno korištenje `/tmp` pri exportu/importu slashing baze i izostanak JVM opcija
- **Gdje:** [`scripts/40-validator.sh`](../scripts/40-validator.sh#L21-L73)
- **Problem:**
  1. `cmd_slashing_export` piše u `/tmp/slashing-export.$$.json` kao `_gnosis`, pa ga kao `root` premješta (`mv`) na odredište `$out` (fajl ostaje u vlasništvu `_gnosis` i prolazi kroz world-writable `/tmp`).
  2. `cmd_slashing_import` kopira slashing bazu u `/tmp/slashing-import.$$.json` s dozvolama `644` (čitljivo svima na stroju).
  3. Funkcija `teku()` u `40-validator.sh` (`L21-L25`) pokreće `java` izravno bez `DEFAULT_JVM_OPTS` iz Teku launchera (za razliku od `teku_java_cmd` u `30-services.sh`).
- **Preporuka:** Za privremeni fajl pri slashing exportu/importu koristiti `$GNOSIS_ROOT/state/validator/` (koji je `750 _gnosis:_gnosis`) umjesto `/tmp`.

### 2.5. `scripts/gnosisctl` — `gnosisctl restart all` koristi obrnuti redoslijed bez pauze
- **Gdje:** [`scripts/gnosisctl`](../scripts/gnosisctl#L169-L175)
- **Problem:** `cmd_restart` iterira kroz `order_down` (`validator listener lighthouse teku nethermind`) i za svaki poziva `launchctl kickstart -k`. Kod `restart all` to znači da se validator i Teku restartaju prvi, a Nethermind zadnji (kojemu pri otvaranju baze od 300 GB treba ~4,5–5 min dok Teku već čeka). Uz to, `kickstart -k` ne učitava promjene u `.plist` fajlu na disku.
- **Preporuka:** Za `restart all` koristiti `order_up` ili napraviti `cmd_stop "$1"` pa `cmd_start "$1"`.

### 2.6. `config/node.env.example` vs `scripts/30-services.sh` vs `scripts/00-preflight.sh` — mrtva varijabla i nepotpuna provjera portova
- **Gdje:** [`config/node.env.example`](../config/node.env.example#L62), [`scripts/30-services.sh`](../scripts/30-services.sh#L117-L140), [`scripts/00-preflight.sh`](../scripts/00-preflight.sh#L63-L70)
- **Problem:**
  1. U `config/node.env.example` definirana je varijabla `EL_METRICS_PORT=6060`, ali je nijedna skripta u repozitoriju ne koristi (ostala je nakon što su Nethermind metrics isključeni).
  2. `00-preflight.sh` provjerava samo TCP portove i zaboravlja provjeriti `CL_QUIC_PORT` (`9001/UDP`), UDP P2P portove (`30303/UDP`, `9000/UDP`) i `CL_METRICS_PORT` (`8008/TCP`).

### 2.7. `scripts/25-build-lighthouse.sh` — ne koristi `activate_version` ni `unquarantine`
- **Gdje:** [`scripts/25-build-lighthouse.sh`](../scripts/25-build-lighthouse.sh#L56-L60)
- **Problem:** Za razliku od `20-install.sh`, instalacija Lighthousea ručno radi `sudo mkdir` i `sudo install`, ali ne osigurava `chown -R root:wheel` i `chmod -R go-w` preko `activate_version` iz `lib.sh`.

### 2.8. Pre-commit provjera iz `AGENTS.md` puca na samom i9 čvoru
- **Gdje:** [`AGENTS.md`](../AGENTS.md#L27-L32)
- **Problem:** `AGENTS.md` propisuje `node --check listener/listener.mjs`. Na i9 čvoru trenutno globalni `/usr/local/bin/node` (stari Homebrew Node 22.9.0) puca s greškom `dyld: Library not loaded: /usr/local/opt/icu4c/lib/libicui18n.74.dylib` (tipičan Homebrew lom na Intelu!), a `/opt/gnosis/node/current/bin/node` još nije instaliran jer je `LISTENER_ENABLED=false`.
- **Preporuka:** Instalirati Node u `/opt/gnosis/node` (`sudo scripts/20-install.sh node`) ili u `AGENTS.md` navesti `/opt/gnosis/node/current/bin/node --check listener/listener.mjs`.

---

## 3. Zaboravljene sitnice u dokumentaciji (tragovi u Git povijesti)

U nekoliko commita u kojima su mijenjane datoteke i verzije (`36836c6`, `ecd72a7`), ostale su sitne neusklađenosti:

| Datoteka | Linija | Što piše | Što treba pisati |
| --- | --- | --- | --- |
| [`listener/listener.mjs`](../listener/listener.mjs#L6) | L6 | `See docs/08-wallet-notifications.md.` | `See docs/07-wallet-notifications.md.` (`08` je validator) |
| [`scripts/30-services.sh`](../scripts/30-services.sh#L13) | L13 | `in docs/04-services.md.` | `in docs/01-architecture.md.` (`04-services.md` ne postoji) |
| [`README.md`](../README.md#L48) | L48 | `Nethermind 2.0` (u Mermaid dijagramu) | `Nethermind` (bez zakucane verzije, po pravilu 2 iz `AGENTS.md`) |
| [`docs/01-architecture.md`](../docs/01-architecture.md#L7) | L7 | `**Nethermind 2.0** (EL)` | `**Nethermind 2.x** (EL)` |
| [`docs/02-decisions.md`](../docs/02-decisions.md#L27) | L27 | `Nethermind 2.0.0.` (u ADR-002) | Dopuniti da je od 2026-10-10 na `2.1.0` (`config/versions.env`) |

---

## 4. Što se dogodilo od zadnjeg commita (2026-10-14 → 2026-10-22): Upstream i stanje čvora

### 4.1. Mjerenje čvora na dan 2026-10-22 (11 dana i 7 sati bez restarta!)

Zadnji unos u dnevniku ([`docs/05-operations.md`](05-operations.md#L154)) je od **2026-10-14**. Provjera stanja čvora danas (**2026-10-22 u 08:54**):

- **Uptime i memorija procesa (`ps -o pid,etime,pcpu,rss,comm`):**
  - `nethermind` (`PID 3951`): uptime `11-07:00:20` (11 dana i 7 sati), RSS **~7,13 GiB** (`7482144 KB`), nikad se nije srušio (`last exit: never exited`).
  - `teku` (`PID 18876`): uptime `11-14:45:43` (11 dana i 14 sati), RSS **~9,05 GiB** (`9489108 KB`), nikad se nije srušio (`last exit: never exited`).
- **Sync i peerovi (`gnosisctl health`):** `in sync`, head star `0s` (`#48880396`), **48 EL peerova** i **37 CL peerova**, `clock offset +0.057763s`, na struji (`AC power`).
- **Točan raspored diska (`du -sh /opt/gnosis/data/...`, `df -h /System/Volumes/Data`):**

| Direktorij / stavka | 2026-10-11 (nakon synca) | 2026-10-22 (nakon 11 d 7 h) | Promjena |
| --- | --- | --- | --- |
| `nethermind_db/gnosis/state` | 146 GB | **148 GB** | **+2 GB u 11 dana (~5,5 GB/mj.)** |
| `nethermind_db/gnosis/blocks` | 98 GB | **99 GB** | stabilno (pomični prozor 367 d) |
| `nethermind_db/gnosis/receipts` | 36 GB | **41 GB** | stabilizirano oko ~40 GB |
| `nethermind_db/gnosis/headers` | 16 GB | **16 GB** | bez promjene |
| `nethermind_db/gnosis/blockNumbers` | — | **2,3 GB** | |
| `nethermind_db/gnosis/blockInfos` | — | **2,2 GB** | |
| `nethermind_db/gnosis/code` | — | **1,0 GB** | |
| `nethermind_db/gnosis/blobTransactions` | — | **332 MB** | |
| `data/teku` | ~1 GB (6,7 GB 10-13) | **7,1 GB** | +0,4 GB u 9 dana |
| **Slobodno (`/System/Volumes/Data`)** | 227 GiB | **208–209 GiB** (706 Gi used) | −7 GiB u zadnjih 8 dana (<1 GiB/dan) |

- **Zaključak o disku (odgovor na otvorenu stavku iz dnevnika):** Pomični prozor povijesti od 367 dana ([ADR-010](02-decisions.md#adr-010)) radi izvrsno i drži blokove/receiptse stabilnima, a stanje (`state`) raste vrlo sporo (~5–6 GB mjesečno). S >200 GiB slobodnog prostora čvor može raditi mjesecima bez potrebe za full pruningom.

### 4.2. Nove upstream verzije i važna zamka oko Netherminda 2.2.0!

Provjerom GitHub API-ja na dan **2026-10-22** (po pravilu 1 iz `AGENTS.md`):

| Komponenta | U `config/versions.env` | Najnovije na GitHubu (2026-10-22) | Objavljeno | Važna napomena |
| --- | --- | --- | --- | --- |
| **Nethermind** | `2.1.0` | **`2.2.0`** | 2026-10-16 | Sadrži fix za PeerManager petlju (**PR `#14190` je spojen**), ali **NE sadrži PR `#14162`**! |
| **Teku** | `26.10.0` | **`26.10.1`** | 2026-10-15 | GitHub org je preimenovan iz `Consensys/teku` u **`Consensys-Incorporated/teku`**! |
| **cloudflared** | `2026.9.3` | **`2026.10.3`** | 2026-10-21 | Ažurirati prije postavljanja tunela ([docs/06](06-rpc-exposure.md)) |
| **Lighthouse** | `v8.2.3` | **`v8.3.1`** | 2026-10-22 | Samo opcionalni fallback (`CL_CLIENT=lighthouse`) |
| **ethstaker-deposit-cli** | `v1.3.0` | `v1.3.0` | 2026-04-30 | Nema promjene |

> [!IMPORTANT]
> **Kritična napomena za budući upgrade na Nethermind 2.2.0:**
> U komentarima u [`scripts/30-services.sh`](../scripts/30-services.sh#L100-L116) i u [dnevniku od 2026-10-10](2026-10-10-prvo-pokretanje-i9-disk.md#L280) stoji napomena da se pri idućem upgradeu Netherminda uklone obje zaobilaznice (`--Network.FilterPeersByRecentIp false` i `DOTNET_ThreadPool_UnfairSemaphoreSpinLimit=0`).
> Provjerom GitHub PR-ova danas:
> 1. **PR `#14190`** (*PeerManager petlja*) **JEST ušao u Nethermind 2.2.0** — `--Network.FilterPeersByRecentIp false` se može ukloniti pri prelasku na 2.2.0.
> 2. **PR `#14162`** (*.NET thread-pool spin*) je **zatvoren bez spajanja (`closed, unmerged`)** dok autori još mjere utjecaj na p99 latenciju bloka (u benchmark raspravi na PR-u otkriveno je i da .NET varijablu okoline `DOTNET_ThreadPool_UnfairSemaphoreSpinLimit` parsira u **heksadecimalnom** sustavu, pa je `0` i dalje `0`, ali default `70` u hexu bi bio `46`)! Ako biste pri prelasku na 2.2.0 maknuli `DOTNET_ThreadPool_UnfairSemaphoreSpinLimit=0`, Nethermind bi se na i9 ponovno vratio na ~1.000+ % CPU-a. **Ta varijabla okoline mora ostati u `30-services.sh`!**
> 3. **Issue `#13601`** (*flat DB snap sync ne nastavlja nakon restarta*) je i dalje **otvoren**, pa `NM_FLATDB=false` ostaje.

> [!NOTE]
> **Preimenovan GitHub repozitorij za Teku (`Consensys` → `Consensys-Incorporated`):**
> `curl -s https://api.github.com/repos/Consensys/teku/releases/latest` (bez `-L`, kako piše u `AGENTS.md` pravilu 1) sada vraća `Moved Permanently`. U `AGENTS.md` treba dodati `-L` (`curl -sL`) ili promijeniti org u `Consensys-Incorporated/teku` (isto i u [`scripts/20-install.sh`](../scripts/20-install.sh#L57)).

---

## 5. Što je na samom i9 stroju ostalo neodrađeno (iz otvorenih stavki)

Pregledom stvarnog stanja na i9 MacBooku u odnosu na otvorene zadatke iz [dnevnika 2026-10-10](2026-10-10-prvo-pokretanje-i9-disk.md#otvoreno) i [dnevnika u `docs/05-operations.md`](05-operations.md#dnevnik):

1. **Redoslijed mrežnih servisa (`networksetup -listnetworkserviceorder`) još nije popravljen:**
   - U dnevniku od `2026-10-11` zapisano je da treba staviti USB Ethernet (`AX88179B`) na vrh.
   - Trenutno stanje na stroju je i dalje: `(1) Redmi Note 8 Pro`, `(2) motorola edge 30 ultra`, `(3) AX88179B`, `(4) Wi-Fi`.
2. **Aktivni Teku plist na čvoru je iz `Oct 10 18:08` (prije commita `5756685`):**
   - `/Library/LaunchDaemons/tv.domovina.gnosis.teku.plist` nije regeneriran nakon dodavanja `CL_QUIC_PORT=9001` u `30-services.sh`, a u lokalnom `config/node.env` još nema linije `CL_QUIC_PORT=9001`.
3. **Pravi restart bez logina ([runbook § 8](04-install-runbook.md#8-pravi-restart)):**
   - Još nije izveden jer se čvor pustio da u komadu odradi razdoblje promatranja. Sad kad imamo 11+ dana neprekidnog rada, to je logičan sljedeći test (pogotovo provjera spaja li se Wi-Fi prije logina i pušta li BTM daemone nakon boota).
4. **Ostaci Docker Desktopa u `/Library/LaunchDaemons/`:**
   - `com.docker.socket.plist` i `com.docker.vmnetd.plist` su još prisutni.
5. **Formalizacija odluke o FileVaultu i RustDesku:**
   - FileVault je `OFF`, a RustDesk je bio zatečen pokrenut — odluke o tome još nisu upisane kao ADR u `docs/02-decisions.md`.

---

## 6. Predloženi plan poboljšanja (prioriteti)

1. **Dokumentacija i dnevnik (odmah, bez diranja servisa):**
   - Upisati mjerenje od `2026-10-22` (11 d 7 h uptimea, `state` +2 GB u 11 dana, slobodno 208 GiB) u [`docs/05-operations.md`](05-operations.md#dnevnik).
   - Ažurirati komentar u [`scripts/30-services.sh`](../scripts/30-services.sh#L114-L116) da `DOTNET_ThreadPool_UnfairSemaphoreSpinLimit=0` **ostaje** jer je PR `#14162` zatvoren bez spajanja, dok je `#14190` ušao u Nethermind 2.2.0.
   - Popraviti krive reference u komentarima (`docs/08-wallet-notifications.md` → `docs/07`, `docs/04-services.md` → `docs/01-architecture.md`, `Consensys-Incorporated/teku`).
2. **Popravci u skriptama i listeneru:**
   - Zaštititi `JSON.parse` u `refreshWatchlist()` i ne keširati RPC greške u `tokenInfo()` u [`listener/listener.mjs`](../listener/listener.mjs).
   - Zamijeniti `/tmp` s `$GNOSIS_ROOT/state/validator` u [`scripts/40-validator.sh`](../scripts/40-validator.sh).
   - Dopuniti [`scripts/00-preflight.sh`](../scripts/00-preflight.sh) provjerom `CL_QUIC_PORT` i ukloniti ili iskoristiti `EL_METRICS_PORT`.
3. **Sljedeći operativni koraci na čvoru (kad odlučiš prekinuti uptime niz):**
   - Složiti redoslijed mreže (`AX88179B` na vrh).
   - Po želji nadograditi Nethermind na `2.2.0` i Teku na `26.10.1` te napraviti test pravog restarta ([runbook § 8](04-install-runbook.md#8-pravi-restart)).
   - Krenuti u realizaciju [plana port forwarda i Cloudflare Tunnela](2026-10-11-plan-port-forward-i-tunel.md) (s `cloudflared 2026.10.3`).
