# 02 — Odluke (ADR)

Svaka odluka ima kontekst, odluku i posljedice. Kad se odluka promijeni, ne briši je: dodaj novu i staru označi kao zamijenjenu.

---

## ADR-001: Nativni procesi, bez Dockera {#adr-001}

**Kontekst.** Docker Desktop na macOS-u vrti Linux VM. Disk I/O kroz VM sloj usporava RocksDB, a RAM se mora statički dodijeliti.

**Odluka.** Binariji rade izravno pod macOS-om, a nadzire ih launchd.

**Posljedice.** Koristimo samo klijente koji imaju Intel macOS build ili rade na JVM-u. Nadogradnje radimo sami, preko `config/versions.env` i `20-install.sh`.

---

## ADR-002: Nethermind kao execution klijent, klasični trie backend {#adr-002}

**Kontekst.** Gnosis podržava Nethermind, Erigon, Reth i Geth.

- Nethermind ima službeni, GPG-potpisan `macos-x64` build. Gnosis config je ugrađen (`-c gnosis`), a minimalni zahtjev je 16 GB RAM-a.
- Erigon 3.x izlazi samo za Linux, pa bi se na Macu morao kompajlirati.
- Nethermind 2.0.0 (2026-09-22) po defaultu koristi novi flat DB. Na njemu se snap sync **ne može nastaviti nakon restarta** (Nethermind #13601).

**Odluka.**

- Nethermind 2.0.0.
- Novi čvor sinkroniziramo s `NM_FLATDB=false` (klasični patricia trie), tako da prekid prve sinkronizacije na laptopu ne baca sate rada.

**Posljedice.**

- `--FlatDb.Enabled` vrijedi samo za **svježu** bazu.
- Na sinkroniziranom čvoru se nikad ne mijenja, jer Nethermind tada tiho briše bazu i sinkronizira ispočetka.
- Prelazak na flat DB je zaseban, planirani resync kad flat sazrije.

---

## ADR-003: Teku kao consensus i validator klijent {#adr-003}

**Kontekst** (provjereno 2026-10-01 preko GitHub API-ja; [istraživanje](research/2026-10-01-clients.md)):

| Klijent | Intel macOS build? | Napomena |
| --- | --- | --- |
| Lighthouse v8.x | **ne** (od v8.0.0) | iz izvornog koda samo uz `--features gnosis`; Homebrew formula nema Gnosis |
| Nimbus | ne (samo arm64) | Gnosis traži zaseban build (`make gnosis-build`) |
| Lodestar | ne (samo Linux) | |
| **Teku 26.9.1** | **da (Java, radi svugdje)** | službena Gnosis podrška; ima i validator client |

Zadnji Lighthouse s Intel macOS binarijem (v7.1.0) je star za Fusaku (aktivna od 2026-04-14), pa ne može pratiti lanac.

Nethermind + Lighthouse su većinska kombinacija na Gnosisu. Manjinski klijent je zdraviji za mrežu i smanjuje rizik da nas pogodi bug većinskog klijenta.

**Odluka.**

- CL je Teku (prebuilt tarball plus Temurin JRE 25), a validator je Teku VC kao **zaseban proces**: zaseban restart, a BN ostaje gore dok se VC mijenja.
- Lighthouse ostaje kao dokumentirana alternativa (`scripts/25-build-lighthouse.sh`, `CL_CLIENT=lighthouse`).

**Posljedice.**

- Ne kompajliramo ništa za normalan rad.
- Teku troši više RAM-a od Lighthousea (heap 6 GB). Uz 64 GB to nije problem.
- launchd ne pokreće Tekuov shell launcher nego izravno `java`. JVM opcije se pri generiranju plista čitaju iz launchera instalirane verzije.

---

## ADR-004: LaunchDaemoni, servisni korisnik `_gnosis`, `/opt/gnosis` {#adr-004}

**Kontekst.**

- LaunchAgent radi samo dok je korisnik ulogiran. Nakon restarta bez logina čvor bi stajao.
- Pokretanje kao admin korisnik znači da kompromitirani browser ili sesija može doći do validatorskih ključeva.
- macOS privacy zaštite (TCC) mogu blokirati daemone koji čitaju iz `~/Documents` i sličnih mapa.

**Odluka.**

- Sve servise vodimo kao LaunchDaemone u system domeni, s `UserName=_gnosis`. To je skriveni role account bez shella i lozinke.
- Binariji su root vlasništvo, a podaci, logovi i tajne pripadaju `_gnosis`. Admin je u grupi `_gnosis` i može čitati logove bez sudo.

**Posljedice.**

- Upravljanje ide kroz `sudo launchctl …`, koji `gnosisctl` omata.
- **Background Task Management** (macOS 13+) pri prvom učitavanju pokaže obavijest „Allow in the Background” za svaki daemon. Treba je dopustiti i provjeriti nakon **pravog restarta** ([docs/03](03-macbook-host.md#background-task-management)).
- `NumberOfFiles` u system daemonu postavlja i kernelske `kern.maxfiles` vrijednosti. Zato svi servisi imaju istu vrijednost (524288).

---

## ADR-005: Zero ingress; RPC prema van ide preko Cloudflare Tunnela i Workera {#adr-005}

**Kontekst.** Novčanik treba RPC, a router ne smije imati otvoren port. Antigravityjev nacrt je obećavao „mobilni upiti idu na naš čvor” i „nula otvorenih portova”, a to se bez tunela međusobno isključuje.

**Odluka.**

- `cloudflared` na Macu otvara **odlazni** tunel.
- Javni hostname ne vodi ravno na čvor, nego na **Worker** koji propušta samo dopuštene JSON-RPC metode, ograničava broj zahtjeva i dodaje Access service-token prema origin hostnameu.
- Sirovi RPC se nikad ne izlaže.

**Posljedice.**

- Cloudflare vidi RPC promet. To je svjesni kompromis u odnosu na Infuru: imamo vlastiti čvor i vlastita pravila, a ne pružatelja usluge koji profilira korisnike.
- Detalji su u [docs/06](06-rpc-exposure.md).

---

## ADR-006: Validator s 0x02 (compounding) ključevima, generiranim offline {#adr-006}

**Kontekst.**

- Gnosis preporučuje `ethstaker-deposit-cli` (v1.3.0, ima `darwin-amd64`).
- Stari `validator-data-generator` (2022) zna samo 0x01.
- S 1 GNO, 0x02 slaže nagrade u efektivni balans (koraci od 1/32 GNO).
- Prijelaz 0x01 → 0x02 je moguć, ali nazad nije.

**Odluka.**

- Ključeve generiramo s `ethstaker-deposit-cli … --compounding` na **offline** stroju.
- Withdrawal adresa je hardverski novčanik ili Safe.
- Na čvor idu samo `keystore-*.json`.

**Posljedice.**

- Isplata nagrada traži EIP-7002 zahtjev s withdrawal adrese, jer nema automatskog sweepa ispod 64 GNO.
- Detalji su u [docs/08](08-validator.md).

---

## ADR-007: Sve verzije zakucane, s SHA-256 u repou {#adr-007}

**Odluka.**

- `config/versions.env` drži verziju i checksum za svaku komponentu.
- `20-install.sh` odbija arhivu čiji se checksum ne poklapa.
- Upgrade je commit u ovom repou, a zatim `git pull`, `20-install.sh <komponenta>` i `gnosisctl restart` na čvoru.

**Zašto.** Antigravityjev nacrt je imao zakucane verzije iz 2024. i `latest` fallback na nepostojeće URL-ove. Rezultat je čvor koji se ne sinkronizira i nije jasno koju verziju zapravo vrti.

---

## ADR-008: Listener je redoslijedni procesor blokova, ne pretplata na logove {#adr-008}

**Kontekst.**

- `eth_subscribe("logs")` gubi evente dok je veza prekinuta.
- Ne vidi native xDAI transfere.
- Ne nosi se s reorgovima.

**Odluka.**

- Listener obrađuje blokove redom, 2 bloka iza vrha lanca.
- WebSocket služi samo kao budilica, a polling je rezerva.
- Napredak se sprema nakon svakog bloka, a nakon restarta listener nadoknađuje do 720 blokova.
- Blok se smatra obrađenim tek kad Worker primi sve njegove evente: isporuka je at-least-once, uz `id` za deduplikaciju.

**Posljedice.**

- Notifikacija s default `CONFIRMATIONS=2` kasni 10–15 s, a s `CONFIRMATIONS=0` stiže unutar ~50–200 ms od uvoza bloka na čvoru (uz detekciju tip reorga preko `newHeads`).
- xDAI koji šalje ugovor (internal transfer) se ne vidi bez `trace_*` metoda. Za ERC-20 tokene (poput EURe) to nije ograničenje jer svaki transfer emitira `Transfer` log. Vidi [docs/07](07-wallet-notifications.md#ograničenja).
- **Dopuna 2026-10-24 (EURe v1/v2 deduplikacija i `TOKEN_ALLOWLIST`):** Na Gnosis Chainu stari Monerium EURe v1 ugovor (`0xcB444e90D8198415266c6a2724b7900fb12FC56E`) interno poziva kanonski EURe v2 ugovor (`0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430`), pa oba ugovora u istoj transakciji emitiraju identičan `Transfer` log sa simbolom `EURe` (potvrđeno na 1.000 blokova na `i9`: 619 v1 transfera, svih 619 ima parnjak na v2). `listener.mjs` zato automatski preskače v1 adresu (`IGNORED_TOKENS`), a podržava i `TOKEN_ALLOWLIST` za filtriranje po adresama tokena ([docs/07 § 3](07-wallet-notifications.md#3-specifičnost-eure-na-gnosis-chainu-monerium-v1-vs-v2-zamka)).

---

## ADR-009: P2P ingress da, RPC ingress ne {#adr-009}

**Kontekst** (izmjereno na i9, 2026-10-10, [dnevnik](2026-10-10-prvo-pokretanje-i9-disk.md#sinkronizacija-prvi-sat)):

- Bez port forwardinga Nethermind je prvih sat i pol imao **4–5 EL peerova**, a snap sync je dobivao samo dio njih. Teku je na istoj mreži imao 11–14 CL peerova.
- Nethermind ispravno prepoznaje javnu IPv4 adresu, pa odlazne veze rade. Drugi nodovi se ne mogu spojiti na njega.
- [ADR-005](#adr-005) „zero ingress” je pisan za **RPC**: sirovi JSON-RPC ne smije biti dostupan izvana. P2P je druga stvar. Protokol je enkriptiran, napravljen za javni internet, i očekuje da ga peerovi mogu dosegnuti.
- Cloudflare Tunnel ne može nositi P2P. Peerovi dolaze izravno na IP i port iz enode/ENR zapisa, preko TCP-a i UDP-a (discovery), a ne preko `cloudflared`.
- Ured ima statičnu javnu IPv4 adresu.

**Odluka.**

- Na routeru se ručno forwardaju **samo P2P portovi**, s istim vanjskim i unutarnjim brojem:

  | Port | Protokol | Klijent | Config |
  | --- | --- | --- | --- |
  | 30313 | TCP + UDP | Nethermind (devp2p + discovery) | `EL_P2P_PORT` |
  | 9010 | TCP + UDP | Teku (libp2p + discv5) | `CL_P2P_PORT` |
  | 9001 | UDP | Teku (QUIC) | `CL_QUIC_PORT` |

- RPC (8545/8546), Engine API (8551), REST (5052) i metrics ostaju vezani na `127.0.0.1`. Izvana idu samo kroz tunel i Worker ([ADR-005](#adr-005)).
- Nema UPnP-a (`--p2p-nat-method=NONE`). Ručni forward je vidljiv i stabilan, a UPnP dopušta bilo kojem programu u LAN-u da otvara portove.
- Forward se uključuje **nakon** prve sinkronizacije. Prvi sync je namjerni test u lošijim uvjetima, a usporedba prije i poslije je i mjerenje koje vrijedi zapisati.

**Posljedice.**

- Više peerova, stabilnija veza i doprinos mreži: drugi nodovi mogu sinkronizirati s nas.
- Nakon synca čvor služi podatke peerovima, pa malo rastu upload i CPU. Gornja granica je `NM_MAX_PEERS` i `CL_MAX_PEERS`.
- IP ureda je javno vezan uz Gnosis čvor. To je i bez forwarda bio slučaj ([docs/09](09-security.md)), jer odlazni P2P objavljuje istu adresu.
- **Više nodova iza iste IP adrese** je moguće. Svaki dobiva svoje portove (npr. 30304/9002/9003) i svoja pravila na routeru. Vanjski port mora biti jednak unutarnjem, jer node objavljuje port na kojem sluša. Inače treba postaviti advertised portove (Teku `--p2p-advertised-port`, `--p2p-advertised-udp-port`, `--p2p-advertised-quic-port`).
- Na Macu treba provjeriti da application firewall pušta `nethermind` i `java` (`socketfilterfw --listapps`: „Allow incoming connections”). Na i9 je to već slučaj.

**Dopuna 2026-10-22: P2P portovi 30313 i 9010 umjesto 30303 i 9000.** Pri postavljanju forwarda u uredu ([docs/10](10-network.md)) TP-Link je odbio pravila za UDP 30303 i UDP 9000 („Conflicting with existing port”) s praznim tablicama forwarda, triggeringa i DMZ-a, a TCP i UDP 9001 je prihvatio. Uzrok su najvjerojatnije UPnP mapiranja koja sučelje ne prikazuje. Čišćenje UPnP-a bi na trenutak prekinulo Tailscale i ne jamči da se neće ponoviti. Standardni portovi su na kućnim i uredskim routerima često zauzeti (UPnP, drugi čvor), pa su **default u `config/node.env.example` sada `EL_P2P_PORT=30313` i `CL_P2P_PORT=9010`**; `CL_QUIC_PORT=9001` je ostao. Klijentima je port svejedno: objavljuju ga u enode/ENR zapisu, a peerovi se spajaju na objavljeni port. Posljedica: na postojećem čvoru promjena traži `sudo scripts/30-services.sh install nethermind teku` (restart oba klijenta), a pravila na routeru moraju pratiti `node.env`. Uz to Teku dobiva `--p2p-advertised-ip` iz nove postavke `P2P_ADVERTISED_IP` (statična javna IP). Bez nje je discv5 objavio NAT-om prepisani UDP port (23756 umjesto 9010), na koji nema forwarda ([docs/10](10-network.md#objavljena-adresa-enr-enode)).

---

## ADR-010: Povijest blokova i receiptsa samo od zadnjih godinu dana {#adr-010}

**Kontekst** (izmjereno na i9, 2026-10-10, [dnevnik](2026-10-10-prvo-pokretanje-i9-disk.md)):

- Nakon snapa (22:25) baza je imala ~166 GB, a slobodno je bilo ~363 GiB.
- Nethermind po defaultu za Gnosis preuzima tijela blokova i receipts sve do bloka 25.349.537 (2022). Prvih 15 % bodiesa je zauzelo 41 GB. Nethermind dokumentacija navodi ~218 GB samo za receipts. Projekcija je bila da cijela povijest **ne stane** na disk.
- Čvor služi za vlastiti RPC (novčanik, ugovori koje deployamo), notifikacije o novim uplatama i kasnije validator. Ništa od toga ne treba transakcije i logove starije od godinu dana. Stara povijest je dostupna na Gnosisscanu, Blockscoutu i indexerima.
- Ethereum ide u istom smjeru: nodovi više ne moraju čuvati staru povijest (EIP-4444, history expiry).

**Odluka.**

- `NM_HISTORY_FROM_BLOCK=42550000` (blok od 2025-10-10 11:17, provjereno preko RPC-a). `30-services.sh` ga postavlja kao `Sync.AncientBodiesBarrier` i `Sync.AncientReceiptsBarrier`.
- Granica je **fiksni blok**, a ne pomični prozor. Od nje nadalje čvor čuva sve.
- **Dopuna 2026-10-11: pomični prozor od 367 dana.** `NM_HISTORY_RETENTION_EPOCHS=198180` postavlja `History.Pruning=Rolling` i `History.RetentionEpochs`. **Nethermind 2.1.0 računa epohu kao 32 bloka** (Ethereum), a ne kao Gnosisovih 16 slotova: granica je `head − epohe × 32`. Na Gnosisu je jedna takva „epoha” 160 s, pa je 198.180 = 367 dana, cijela godina uz rezervu. Prva vrijednost, 396.360, računata s 80 s po epohi, dala je dvije godine. Pruner ju je prijavio kao „up to #36008506” (= head − 396.360 × 32). Blokovi i receipts stariji od prozora se brišu kako novi dolaze, pa povijest na disku ostaje ~konstantna (~160 GB, izmjereno ~27 KB po bloku, ~16.500 blokova dnevno). Nethermind 2.1.0 ovu postavku za Gnosis prihvaća bez greške (probni čvor na i9). Briše li stvarno ispravno, provjerava se nakon prvog prolaza na čvoru.

**Posljedice.**

- `eth_getBlockByNumber`, receipts i `eth_getLogs` za blokove prije granice vraćaju `null` ili prazno.
- Tijela blokova koja su na i9 preuzeta prije promjene (do ~2025-05-08) ostaju dok ih ne obriše pomični prozor.
- Stanje (state) pomični prozor ne dira. Patricia trie raste zasebno i povremeno treba full pruning, za koji mora biti slobodno otprilike koliko je živo stanje. Rast se mjeri tjedan dana prije odluke o trigeru.
- Promjena je reverzibilna. Spuštanjem granice i restartom Nethermind dopunjava stariju povijest, ako ima mjesta.
- Peerovi koji traže staru povijest od ovog čvora je neće dobiti. Mreža to podnosi, jer arhivske nodove drže drugi.


---

## ADR-011: RPC tunel po čvoru za vlastite Workere, iza Cloudflare Accessa {#adr-011}

**Kontekst.**

- Prvi korisnici RPC-a su **vlastiti Cloudflare Workeri** (npr. čitanje EURe transfera), a ne mobilni novčanik. Worker tajnu može držati kao secret, pa javni proxy Worker iz [ADR-005](#adr-005) u ovoj fazi nije potreban ([plan § 2](2026-10-11-plan-port-forward-i-tunel.md)).
- Port forward za RPC ne dolazi u obzir ([ADR-009](#adr-009)): tunel je odlazan i ne treba javni IP ni otvoren port.
- Workers VPC (Worker do tunela bindingom, bez javnog hostnamea) je 2026-10-22 još **beta** ([developers.cloudflare.com/workers-vpc](https://developers.cloudflare.com/workers-vpc/)).
- `cloudflared service install` stvara plist izvan repoa, pokreće `cloudflared` kao root i ostavlja uključen autoupdate.
- Zona `mpt.hr` je na Cloudflareu. Besplatni Universal SSL pokriva samo jednu razinu poddomene (`*.mpt.hr`).

**Odluka.**

- Svaki čvor ima vlastiti **lokalno upravljani** imenovani tunel. Ime tunela i hostnameova je ime čvora iz kataloga ([ADR-012](#adr-012), [docs/11](11-imena-cvorova.md)):
  - `<NODE_NAME>-rpc.mpt.hr` → `127.0.0.1:8545` (HTTP JSON-RPC);
  - `<NODE_NAME>-ws.mpt.hr` → `127.0.0.1:8546` (WebSocket);
  - sve ostalo dobiva 404. Engine API (8551), beacon REST i metrike nikad ne idu u tunel.
- Prvi čvor (i9) je `acutis`: `acutis-rpc.mpt.hr` i `acutis-ws.mpt.hr`.
- `cloudflared` radi kao LaunchDaemon `tv.domovina.gnosis.tunnel` pod `_gnosis`. Plist i `config.yml` generira `scripts/30-services.sh` iz `config/node.env` (`TUNNEL_ENABLED`, `NODE_NAME`, `TUNNEL_ZONE`, `TUNNEL_ID`). Verzija je zakucana u `config/versions.env`, a `--no-autoupdate` je uključen ([ADR-007](#adr-007)).
- Oba hostnamea su iza Cloudflare Access self-hosted aplikacije s politikom **Service Auth**. Svaki Worker koji zove RPC dobiva **vlastiti** service token, kako bi se mogao opozvati zasebno.
- Workers VPC se ponovno razmatra kad izađe iz bete.

**Posljedice.**

- Bez service tokena Access vraća 403. Ako token procuri, dostupni su samo moduli `[Eth,Net,Web3,Subscribe,Health]`.
- Credentials JSON tunela je tajna: `/opt/gnosis/secrets/cloudflared/<TUNNEL_ID>.json`, `_gnosis` 600. `cert.pem` iz `cloudflared tunnel login` vrijedi za cijelu zonu i treba samo za `tunnel create` i `route dns`; nakon postavljanja se briše.
- Cloudflare vidi sav RPC promet ([ADR-005](#adr-005)).
- `eth_getLogs` i receipts postoje samo za zadnjih 367 dana ([ADR-010](#adr-010)). Starija povijest EURe-a mora doći iz indexera ([ADR-014](#adr-014)).
- Faza 2 (javni proxy Worker za novčanik, [docs/06](06-rpc-exposure.md)) postaje još jedan klijent istog tunela.
- Log `cloudflared`-a (`logs/tunnel.stderr.log`) se ne rotira. Na razini `info` je mali; ako naraste, dodaje se newsyslog.

---

## ADR-012: Imena čvorova po svecima i blaženicima, vezana uz županiju {#adr-012}

**Kontekst.**

- Cilj je mreža od barem 21 čvora, po jedan u svakoj županiji i Gradu Zagrebu. Svaki čvor treba ime za hostname ([ADR-011](#adr-011)), logove i dokumentaciju.
- Hostnameovi su javni: imena poddomena se mogu izlistati i završavaju u Certificate Transparency logovima. Adresa ili IP u imenu otkrivaju lokaciju čvora, a time i validatora ([docs/08 § 7](08-validator.md#7-rizici-specificni-za-kucni-validator)).
- Čvor se može fizički preseliti.

**Odluka.**

- Ime čvora je ime hrvatskog sveca ili blaženika vezanog uz **županiju** u kojoj čvor stoji. Katalog s redoslijedom prioriteta po županiji je u [docs/11](11-imena-cvorova.md), a izvori u [istraživanju](research/2026-10-22-katalog-svetaca-po-zupanijama.md).
- Novi čvor uzima prvo slobodno ime svoje županije. Kad se preseli u drugu županiju, dobiva prvo slobodno ime nove županije. Iskorišteno ime se ne dodjeljuje ponovno.
- Uz katalog postoje **simbolična imena** vezana uz čvor, a ne uz lokaciju. Prvi čvor (i9, Zagrebačka) je `acutis`, po sv. Carlu Acutisu, zaštitniku interneta i programera.
- U hostnameu nema lokacije ni IP-a. Lokacija je u tablici čvorova u docs/11, bez ulice.

**Posljedice.**

- Selidba čvora mijenja hostnameove, pa Workere treba prebaciti ([docs/11 § Selidba](11-imena-cvorova.md#selidba)). Tunel (UUID) i credentials ostaju isti.
- Šest županija ima samo jedno ime u katalogu, a Osječko-baranjska i Međimurska nemaju sveca s osobnom vezom. Za njih se katalog dopunjava kad se zna mjesto čvora.
- `stepinac` ostaje plan za sljedeći čvor u Zagrebačkoj županiji, iako i9 stoji tamo pod imenom `acutis`.

---

## ADR-013: Log index u Nethermindu za široke `eth_getLogs` upite {#adr-013}

**Status:** prihvaćeno 2026-10-23 nakon mjerenja na i9 ([predaja](2026-10-23-predaja-log-index-i9.md)). Mjerenje kroz tunel s Mac Minija je još otvoreno.

**Kontekst** (izmjereno 2026-10-23 s Mac Minija kroz `acutis-rpc.mpt.hr`):

- Prvi Worker na tunelu je MPT rail (`pay.domovina.ai`, PR #143, ADR 0031 tog repoa). Sva čitanja na serveru idu prvo na čvor, a javni RPC je rezerva.
- Popis dolaznih EURe uplata po adresi (`/api/activity`) treba sve Transfer logove prema toj adresi kroz cijelu povijest koju čuvamo (367 dana, [ADR-010](#adr-010)). Danas ga daje Blockscout.
- Nethermind 2.1.0 bez log indexa odbija `eth_getLogs` preko više od 10.000 blokova (`Receipt.MaxBlockDepth`): „Logs request reads 6300001 blocks without the log index”.
- Brzina bez indexa: 10.000 blokova 0,74 s, a batch od 50 × 10.000 blokova 11,5 s. Cijela godina (~6,3M blokova) trajala bi oko 145 s, što je prespor za čitanje po zahtjevu.
- Nethermind 2.x ima `LogIndex.Enabled` (zadano `false`). Index je zasebna baza `logIndex` koja se gradi iz receiptsa na disku. Napredak i veličinu pokazuje RPC `logIndex_status` (modul `LogIndex`). Na čvoru s indexom limit od 10.000 vrijedi samo za blokove koje index još ne pokriva (release notes 2.1.0, #13131).

**Odluka.**

- `NM_LOG_INDEX=true` u `config/node.env` na i9. `30-services.sh` tada dodaje `--LogIndex.Enabled true` i modul `LogIndex` (samo za čitanje: `logIndex_status`, `logIndex_blockNumbers`).
- Prihvaća se ako backfill završi, ako baza indexa nije veća od ~30 GB i ako upit preko cijelog prozora za jednu adresu traje ispod ~2 s. Inače se `NM_LOG_INDEX=false` vraća, baza `logIndex` briše, a popis uplata ide kroz indexer u Workeru (D1).

**Posljedice.**

- Dodatni disk za bazu `logIndex` (nepoznat do mjerenja) i CPU/IO dok traje backfill.
- Značajka je nova u 2.x i prima popravke (#13036, #13565). Pri upgradeu Netherminda treba pročitati odjeljak release notesa o log indexu.
- Modul `LogIndex` je dostupan i kroz tunel, iza Accessa. Samo čita.
- Uz pomični prozor povijesti index treba pratiti brisanje starih receiptsa. To se provjerava u `logIndex_status` (`current.fromBlock` raste s prozorom).

**Mjerenje 2026-10-23 (i9, lokalno).**

- Backfill 6,35M blokova trajao je ~55 min (10:17–11:12) uz ~2,7 jezgre CPU-a. Za to vrijeme head je ostao 1–5 s star.
- Baza `logIndex` ima 3,2 GB, a slobodni disk je pao s 213 na 211 GB.
- `eth_getLogs` za jednu adresu preko cijelog prozora traje 0,1–0,9 s (105 logova), a prije je trajao ~145 s.
- Kriteriji su ispunjeni s velikom rezervom: < 30 GB i < 2 s.
- Ograničenja za klijente:
  - donja granica je granica pruninga, a ne `fromBlock: "earliest"`; ispod nje Nethermind vraća `Pruned history unavailable`;
  - najviše 20.000 logova po odgovoru.

---

## ADR-014: Trajna povijest EURe uplata živi u bazi Workera, ne na čvoru {#adr-014}

**Status:** prihvaćeno 2026-10-23.

**Kontekst:**

- Čvor čuva blokove i receipts samo 367 dana ([ADR-010](#adr-010)). Uz log index ([ADR-013](#adr-013)) `eth_getLogs` za jednu adresu preko tog prozora traje 0,1–0,9 s. Starije od toga čvor nema.
- Godina povijesti zauzima ~140 GB na i9 (2026-10-23): `blocks` 99G, `receipts` 37G, `logIndex` 3,2G. Slobodno je 211 GB, a `state` raste zasebno. Druga godina bi stala, ali disk bi ostao gotovo pun. Cijela povijest Gnosisa ne stane.
- Spuštanje granice povijesti je reverzibilno samo na papiru. Nethermind bi stare blokove i receipts trebao dohvatiti od peerova, a peerovi ih sve češće ne čuvaju (EIP-4444). Na i9 to nije isprobano.
- Popis uplata (`/api/activity` u `pay.domovina.ai`) treba povijest **naših** adresa, a ne proizvoljan `eth_getLogs` za bilo koju adresu.

**Odluka:**

- Čvor ostaje na pomičnom prozoru od 367 dana. Za veću povijest se ne proširuje.
- Trajna arhiva EURe Transfera za naše adrese je baza Workera `pay.domovina.ai` (D1, cron indexer `onchainIndexer.ts`). Indexer redovito čita nove logove s čvora i sprema ih trajno, pa brisanje na čvoru ne gubi ništa.
- Povijest stariju od prozora indexer učita **jednokratno** iz Blockscouta, Gnosisscana ili javnog arhivskog RPC-a, u istu bazu.
- Blockscout ostaje rezerva za adrese koje ne pratimo unaprijed i za vrijeme dok čvor nije dostupan.

**Posljedice:**

- Prozor od 367 dana sada je i rezerva za indexer: indexer smije stajati do godinu dana bez gubitka podataka. Treba nadzor koji javlja ako stoji danima.
- Nova adresa koju počnemo pratiti dobiva povijest prozora s čvora, a stariji dio jednokratno iz vanjskog izvora.
- Proširenje povijesti na čvoru ponovno se razmatra samo ako zatreba proizvoljan `eth_getLogs` za tuđe adrese stariji od godine. Tada treba veći disk (2–4 TB SSD) i prvo isprobati dohvat stare povijesti s peerova.
- Implementacija je u repou `pay.domovina.ai` (njegov ADR i PR), ovaj ADR samo određuje podjelu odgovornosti.
