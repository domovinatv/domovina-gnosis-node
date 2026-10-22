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

- Notifikacija kasni 10–15 s, a ne „1 s” kako je bilo obećano.
- xDAI koji šalje ugovor (internal transfer) se ne vidi bez `trace_*` metoda. Vidi [docs/07](07-wallet-notifications.md#ograničenja).

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

