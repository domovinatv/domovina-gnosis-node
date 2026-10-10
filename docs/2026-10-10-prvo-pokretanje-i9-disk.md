# 2026-10-10 — Prvi preflight na i9 i čišćenje diska

Prvi put je repo pokrenut na ciljnom stroju. Instalacija još nije krenula, jer je preflight pao na disku. Nakon čišćenja odlučeno je krenuti s 534 GiB (vidi drugi krug).

## Stroj (izmjereno)

| Stavka | Vrijednost |
| --- | --- |
| Model | MacBookPro16,1 (16", 2019) |
| CPU | Intel Core i9-9980HK @ 2.4 GHz, 8 jezgri / 16 dretvi |
| RAM | 64 GB |
| Disk | APPLE SSD AP1024N, 1 TB, interni PCIe |
| macOS | 26.6.2 (25G83) |
| Baterija | 631 ciklus, stanje Normal, punjač 87 W |
| FileVault | OFF |
| Sleep | već isključen (`sleep 0`) |

`00-preflight.sh` prolazi sve osim slobodnog diska. Arhitektura, RAM, CLT, napajanje, checkpoint, sat i portovi su u redu. CPU i RAM za Nethermind + Teku nisu ograničenje; **disk jest**, kako je i predviđeno u [docs/03](03-macbook-host.md).

## Disk: od 226 GB do 534 GB slobodnog

Na stroju su dva admin korisnika:

- `ms`: trenutni korisnik;
- `stepanic`: stari korisnik, **UID 501**.

UID 501 je potvrda zamke s `tar --no-same-owner` iz [dnevnika od 2026-10-01](2026-10-01-prepisivanje-i-otvorene-stavke.md). Binariji raspakirani s numeričkim vlasnikom 501 pripali bi starom admin računu.

Gdje je bilo zauzeće (740 GB na data volumenu):

| Lokacija | GB | Napomena |
| --- | --- | --- |
| `/Users/stepanic` | 444 | od toga Library 291 (Xcode 128, Docker 57, CoreSimulator 42, Android 42), Downloads 45, git 31, Documents 13 |
| `/Users/ms` | ~90 | CoreSimulator 24, Docker 21, Flutter/CocoaPods ~15 |
| `/Library`, `/Applications`, ostalo | ~110 | |

Obrisano iz `stepanic`: Xcode, CoreSimulator, Android, `.android`, sadržaj Downloads i Documents, `Desktop/.tmp.driveupload`. Rezultat je bio 494 GB slobodno, a nakon dodatnog čišćenja na strani `ms` 534 GB.

### Zamke

- **`du` bez roota laže.** Bez sudoa `du` je za `/Users/stepanic` pokazao 79 GB, a stvarno je 444. Nečitljivi direktoriji se tiho preskaču (`2>/dev/null`).
- **`!` prefiks u Claude Codeu ne može pitati za sudo lozinku.** Naredbu treba pokrenuti u Terminal.app i rezultat preusmjeriti u fajl.
- **`~/Library/Containers/*` ne briše ni root** (`Operation not permitted`). Terminal treba Full Disk Access (System Settings → Privacy & Security).
- **Docker Desktop je bio pokrenut** na `ms`. Čvor ga ne koristi ([ADR](02-decisions.md)), a njegov VM troši RAM.

## Drugi krug: Docker na `stepanic` i odluka

iTerm je dobio Full Disk Access. Provjera: `ls "/Library/Application Support/com.apple.TCC"` prolazi bez `Operation not permitted`.

Docker podaci na `stepanic` nisu oslobodili ništa:

- `~/Library/Containers/com.docker.docker` više nije postojao (`No such file or directory`). Obrisan je u prvom krugu ili je procjena od 57 GB bila prividna veličina sparse `Docker.raw`. Ovo nije provjereno.
- Obrisan je `/Users/stepanic/.docker` (44 KB).
- Nema Docker procesa, pa ni otvorenog fajla koji drži obrisani prostor. Nema ni lokalnih Time Machine snapshotova.
- Na `ms` je Docker.app već uklonjen. Ostali su `/Library/LaunchDaemons/com.docker.{socket,vmnetd}.plist`, helperi u `/Library/PrivilegedHelperTools/` i symlinkovi u `/usr/local/bin/docker*`. Ne zauzimaju prostor.

Slobodno ostaje **534 GiB (~574 GB)**. `00-preflight.sh` za raspon 500–700 GB daje upozorenje, ne pad.

**Odluka:** instalacija kreće s ovim diskom, bez daljnjeg čišćenja. Prostor se po potrebi oslobađa kasnije, dok sync radi (vidi Otvoreno). Procjena za sync je ~509 GB za Nethermind i ~10 GB za Teku, dakle rezerva je mala i disk treba pratiti.

### Zamka

- **`df -h` pokazuje GiB, `diskutil` GB.** 534 Gi u `df` i „573.9 GB not allocated” u `diskutil apfs list` su ista brojka.

## Prva instalacija je namjerni test u lošijim uvjetima

Cilj prve instalacije je dokazati da čvor radi i bez idealnih uvjeta. Dva odstupanja od [runbooka](04-install-runbook.md) i [docs/03](03-macbook-host.md) su svjesna:

| Uvjet | Preporuka | Test |
| --- | --- | --- |
| Slobodan disk | ≥ 700 GB | ~534 GiB, smije pasti do ~500 GB |
| Mreža | USB-C Gigabit Ethernet | Wi-Fi |

Wi-Fi je izmjeren 2026-10-10 (Speedtest, Optima Telekom, server HT Zagreb): **428 Mbps down, 424 Mbps up, ping 4 ms**. Pod opterećenjem ping raste na 91 ms (down) i 34 ms (up).

Dugoročno je plan kabel i dodatne optimizacije. Ako čvor sinkronizira i radi u ovim uvjetima, s kabelom će raditi tim bolje.

Što izmjeriti tijekom testa i upisati ovdje:

- trajanje synca za Teku (checkpoint) i Nethermind (snap);
- slobodan disk na početku, u vrhuncu i nakon synca;
- broj peerova za EL i CL te prekide Wi-Fi veze tijekom synca;
- spaja li se Wi-Fi nakon pravog restarta **bez logina** (runbook § 8). Ovo je za Wi-Fi glavni rizik: mreža mora biti spremljena na razini sustava, a ne samo za korisnika.

## Provjera verzija prije instalacije

Po pravilu 1 iz [CLAUDE.md](../CLAUDE.md) verzije su provjerene protiv GitHub releases API-ja neposredno prije instalacije. Od 2026-10-01 izašle su dvije nove:

| Komponenta | Bilo | Novo | Izašlo | Napomena |
| --- | --- | --- | --- | --- |
| Nethermind | 2.0.0 | **2.1.0** | 2026-10-01 | Glamsterdam za Sepoliu, brži EVM, RocksDB 11. Za Gnosis nije obavezno. |
| Teku | 26.9.1 | **26.10.0** | 2026-10-08 | „recommended update”, bez breaking changes |
| Temurin JRE | jdk-25.0.4.1+1 | isto | | |

Gnosis nema zakazan novi fork (`gnosischain/configs`: zadnji je Fulu, epoha 1714688). Nadogradnja zato nije nužna. Kako je ovo **svježa** instalacija, uzete su nove verzije: sada ne koštaju ništa, a kasnije bi tražile restart.

Provjereno na i9 (x86_64, bez Rosette):

- SHA-256 obje arhive izračunat lokalno. Poklapa se s GitHub `digest` poljem, a za Teku i s `teku-26.10.0.tar.gz.sha256`.
- `nethermind --help` (2.1.0, `macos-x64`): postoji svih 16 flagova koje koristi `30-services.sh`.
- `teku --help` i `teku vc --help` (26.10.0 na Temurin JRE 25): postoje svi BN i VC flagovi.
- `30-services.sh render` u test modu protiv stvarnog Teku 26.10.0 launchera: JVM opcije su pročitane, a `plutil -lint` prolazi.
- **Nethermind #13601** (flat DB + snap sync se ne nastavlja nakon restarta) je i dalje otvoren. `NM_FLATDB=false` ostaje ([ADR-002](02-decisions.md#adr-002)).
- 2.1.0 sada **odbija** `--FlatDb.Enabled=false` na postojećoj flat bazi. U 2.0.0 ju je tiho brisao i sinkronizirao ispočetka. Za nas to znači da slučajna promjena `NM_FLATDB` na sinkroniziranom čvoru više ne briše bazu, nego servis ne starta.

## Host setup (`10-host-setup.sh`)

Pokrenut 2026-10-10 u 17:32. Svi koraci su prošli: `_gnosis` (uid/gid 470), `/opt/gnosis` s ispravnim vlasnicima, JWT, pmset, updateovi, firewall i newsyslog. `ms` je odmah u grupi `_gnosis` (`id -Gn`).

Nalazi:

- **`lowpowermode 1` i na AC i na bateriji.** Low Power Mode drži CPU na nižem taktu, što bi usporilo sync. Skripta ga do sada nije dirala. Dodano je `pmset -a lowpowermode 0`, ako ga `pmset -g cap` nudi.
- **`pmset -g cap` nema ni `autorestart` ni `autorestartatconnect`.** Skripta ih zato preskače, a [docs/03](03-macbook-host.md#napajanje-pmset) je ažuriran.
- **RustDesk je pokrenut.** On drži `displaysleep` i `sleep` budnima (`sleep prevented by … RustDesk`). Za čvor to nije problem, ali RustDesk je dodatna površina za udaljeni pristup ovom stroju. Treba odlučiti ostaje li ([docs/09](09-security.md)).
- **`df -h /` pokazuje sistemski volumen** (12 GiB used). Prostor za čvor se prati na `/System/Volumes/Data`, a `Avail` je zajednički za oba volumena.

## Instalacija klijenata (`20-install.sh`)

Pokrenuto 2026-10-10 u 17:54, gotovo u 17:55. Nethermind 2.1.0, Temurin JRE jdk-25.0.4.1+1 i Teku 26.10.0: svi SHA-256 su u redu, svi fajlovi su `root:wheel` i nijedan nema quarantine flag. Disk: 533 → 532 GiB slobodno.

Zamke:

- **Naredba zalijepljena u iTerm se nije izvršila**, a ekran je izgledao kao da nešto radi (samo prazni redovi). Provjera je `ps` (ima li `sudo`/`tee` ispod shella tog taba) i postoji li log fajl, jer `tee` ga stvara odmah, i prije `sudo` lozinke.
- **`sudo` na macOS-u zadržava `HOME`.** gpg je zato kao root koristio `/Users/ms/.gnupg`: ostavio je root-owned `crls.d` i `S.dirmngr` te pokrenuo `dirmngr` kao root. Nakon toga ni gpg korisnika `ms` nije mogao do keyservera (`No dirmngr`). Ispravljeno je tako da `20-install.sh` pokreće gpg kao `$SUDO_USER` (`sudo -u … -H`), pa koristi admin keyring u koji runbook § 5 uvozi Nethermindov ključ.

## Servisi (`30-services.sh install`)

Pokrenuto 2026-10-10 u 18:08. Oba plista su učitana bez greške.

- **Teku** se pokrenuo i za oko minutu povukao checkpoint stanje (head slot 30531008). Nakon toga čeka EL: `EXECUTION_CLIENT_OFFLINE`, „Beacon chain syncing complete, waiting for Execution Client”. Ovo je očekivano.
- **Nethermind se rušio u petlji** (`last exit 159`, `spawn scheduled`), a u `nethermind.stderr.log` je pisalo:
  ```
  Default extraction directory [/private/var/empty] either doesn't exist or is not accessible for read/write.
  DOTNET_BUNDLE_EXTRACT_BASE_DIR is not set, and a read-write cache directory couldn't be created.
  ```
  Nethermind je .NET single-file bundle i pri startu raspakira ugrađene native biblioteke u `$HOME`. Home korisnika `_gnosis` je `/var/empty`, u koji se ne može pisati. Test na arm64 ovo nije mogao uhvatiti, jer je tamo Nethermind radio kao obični korisnik.
  **Ispravak:** plist sada postavlja `HOME=/opt/gnosis/state/nethermind` i `DOTNET_BUNDLE_EXTRACT_BASE_DIR=…/dotnet-bundle`, a `30-services.sh` stvara `state/<servis>` u vlasništvu `_gnosis`. Raspakirane biblioteke tako pripadaju servisnom korisniku, a ne rootu. To je malo odstupanje od [ADR-004](02-decisions.md#adr-004), jer binariji iz zipa ostaju root-owned.


## Sinkronizacija: prvi sat

Nethermind je nakon ispravka startao u 18:11:52. Prvih ~15 s je ponavljao `Pivot block from Consensus Layer isn't higher than pivot from initial config. New PivotBlockNumber: 0, old: 48330000`. To je normalno: ima pivot hash od Teku, ali još ne i header od peerova. U 18:12:48 je primio forkchoice za blok 48687435 i krenuo.

| Vrijeme | Snap state ranges | Old headers | Baza | Slobodno | EL / CL peerovi |
| --- | --- | --- | --- | --- | --- |
| 18:12 | 0 % | 0 | 0,1 GB | 532 GiB | 0 / 2 |
| 18:22 | 5,43 % | 2,0 M / 48,7 M, 4.263 blk/s | 2,8 GB | 529 GiB | |
| 18:32 | 7,26 % | 5,0 M, 6.567 blk/s | 5,6 GB | 526 GiB | ? / 10 |
| 18:42 | | | | 522 GB | **4** / 11 |

- Backend je patricia (`State backend: patricia (flat DB disabled)`), a JWT je pročitan iz `secrets/jwt.hex`.
- **Snap usporava** (1,8 % u 10 min), a **EL ima samo 4 peera**, od toga 0 aktivnih za snap (`Sleeping: 2 Snap`). Teku na istoj mreži ima 11 peerova.
- macOS firewall nije uzrok: `socketfilterfw --listapps` za `nethermind` i `java` pokazuje „Allow incoming connections”. Uzrok je vjerojatnije router bez port forwardinga, uz malu Gnosis EL mrežu.
- Ako EL ostane na ~4 peera, idući korak je port forward 30303 TCP/UDP na routeru. Za P2P to ne krši [ADR-005](02-decisions.md#adr-005), koji se odnosi na RPC.
- Nethermind log je `logs/nethermind/gnosis.log`, a ne `*.txt`. `gnosisctl logs nethermind` je zato tražio krivi fajl; ispravljeno.
- U install diru Nethermind postoje `Data/` i `keystore/` iz zipa. Nethermind nije pisao pored binarija, sve ide u `data/nethermind`.

## Sinkronizacija: stanje gotovo (4 h 13 min)

| Vrijeme | Događaj | Baza | Slobodno | EL peerovi |
| --- | --- | --- | --- | --- |
| 18:12:48 | početak (pivot 48687435) | 0,1 GB | 532 GiB | 0 |
| 19:44 | snap state ranges 28 %, headeri 74 % | 41 GB | 491 GiB | 5 |
| 20:14 | headeri gotovi (~2 h) | | | 4 |
| 20:53 | state ranges 99,4 %; počinje „Large storage” | 115 GB | 417 GiB | 6 |
| 22:25 | snap gotov, healing („State Sync”) traje < 1 min | ~166 GB | 363 GiB | |
| 22:25 | **Teku više nije optimistic; Nethermind prati vrh lanca** | | 355 GB | 8 |

- Prvih ~2 h snap je jedva napredovao, jer su 4 EL peera bila zauzeta headerima. Kad su headeri završili, state ranges su od 34 % do 99 % došli za ~45 min.
- „Large storage” (storage nekoliko velikih ugovora, zadnji vuče jedan peer) trajao je ~1 h 30 min, oko 1 % u minuti.
- Healing je bio gotovo trenutan. Brojka „/ 137350 MB” u `State Sync` je procjena ukupnog stanja, a ne posao koji preostaje.
- U 22:30: `eth_blockNumber` vraća vrh lanca, head star 2 s, Teku `sync_distance 0`, 15 CL peerova. `eth_syncing` i dalje vraća objekt (ne `false`), jer traje preuzimanje povijesti.
- Promet do 21:50 (od 18:11): Nethermind 61 GB down / 0,33 GB up, Teku 0,16 / 0,19 GB. Teku na vrhu lanca troši ~0,2 Mbit/s.
- Opterećenje tijekom snapa: Nethermind 640–1.270 % CPU (od 1.600 %), Teku ~230 % dok čeka EL, ventilatori ~5.400 RPM.
- Nakon toga slijede **Old Bodies** (23,3 M blokova, početak ~1.700 blk/s) i Old Receipts.

## Povijest: disk ne bi bio dovoljan

- 22:49: Old Bodies 15 %, baza 207 GB (+41 GB od 22:25). Linearna projekcija za bodies je ~260 GB, a za receipts (Nethermind dokumentacija) 218 GB. Slobodno je bilo ~349 GB, pa bi se disk napunio tijekom receiptsa.
- 23:19: bodies 35 %, baza 253 GB, slobodno 278 GiB.
- 23:21: najstarije preuzeto tijelo je blok ~39.956.500 (2025-05-08). Receipts postoje samo od 22:25.
- Odluka: povijest samo od bloka 42.550.000 (2025-10-10), [ADR-010](02-decisions.md#adr-010). Za taj broj bloka se ne treba pouzdati u „5 s po bloku”: prosjek je bio ~5,2 s, pa je blok traženi preko `eth_getBlockByNumber` i `timestamp`.

## Restart s ADR-010 (23:27)

- `sudo scripts/30-services.sh install nethermind` u 23:27. Stari proces se ugasio u 23:27:25.
- **Novi proces je šutio u logu ~4,5 min** (23:27:35 → 23:31:54), uz ~93 % CPU-a, dok je otvarao bazu od ~250 GB. Na prvom startu je baza bila prazna, pa se to nije vidjelo. Ovo nije zastoj: pri restartu pričekati barem 5 minuta prije zaključka.
- `State sync unnecessary - already have state`: snap se ne ponavlja ([ADR-002](02-decisions.md#adr-002)). Za 4,5 min propuštenih blokova je sustigao odmah.
- Barrier je pročitan (`Sync.AncientBodiesBarrier = "0x28942f0"` = 42.550.000). Bodies su odmah gotovi. **Old Receipts** kreću s 6.140.906 blokova, točno od pivota do granice.
- **Receipts na disku su manji nego što prva brojka sugerira.** U 23:35 je bilo 7,9 GB za 131 k blokova (~58 KB/blok), a u 23:40 4,7 GB za 325 k blokova (~15 KB/blok), zbog RocksDB kompakcije i `Receipt.CompactReceiptStore`. Projekcija za godinu je ~90 GB. Ne zaključivati o disku iz prvih minuta pisanja.
- **Lookup transakcije po hashu treba receipts.** `eth_getTransactionByHash` je za transakciju iz bloka 48.654.130 vraćao `null`, iako je tijelo bloka bilo lokalno: `eth_getTransactionByBlockNumberAndIndex` ju je vratio. Nethermind indeks hash → blok gradi zajedno s receiptsima. Kad su Old Receipts stigli do tog bloka (2 min kasnije), radili su i lookup po hashu i receipt.

## Sync gotov (2026-10-11 00:27:33)

- `Fast blocks receipts task completed` u 00:27:33. `eth_syncing` vraća `false`, a `gnosisctl health` je zelen osim broja EL peerova (8). Brojač Old Receipts je stao na 98,2 %, jer je zadnjih ~110 k bilo u redu za obradu.
- **Ukupno: 6 h 15 min** od starta Nethermind (18:12) do kraja, s restartom u 23:27 (ADR-010) i ~4,5 min starta nakon njega. Stanje je bilo gotovo za 4 h 13 min.
- Baza u 00:31: state 146 GB, blocks 98 GB, receipts 36 GB (godina, nakon kompakcije), headers 16 GB. Ukupno 304 GB. Slobodno 227–229 GiB.
- Mirovanje (00:31–00:48): mreža 4,9 Mbit/s down / 0,9 up, disk 9 MB/s, Teku 37 % CPU. Obrada novog bloka ~35 ms (`newPayload` ~12 ms prosjek).
- **Nethermind nakon synca troši ~1.400–1.500 % CPU-a, od čega ~60 % sistemsko vrijeme**, i nakon 20 min se ne smiruje. Nema aktivne RocksDB kompakcije (LOG fajlovi), a u logu nema ništa osim obrade blokova. Stvarni posao je ~35 ms svakih 5 s, pa je ovo pozadinska petlja, a ne praćenje lanca. Uzrok se ne vidi bez `sudo sample <pid>` (proces radi kao `_gnosis`).

## Otvoreno

- [x] Instalacija do § 5: preflight, `10-host-setup.sh`, `20-install.sh`.
- [x] § 6 servisi.
- [x] § 7 stanje sinkronizirano (22:25), čvor prati vrh lanca.
- [ ] Nakon receiptsa: `sudo scripts/30-services.sh install nethermind` za pomični prozor od 367 dana ([ADR-010](02-decisions.md#adr-010)), pa pratiti prvi prolaz brisanja (koliko blokova i GB).
- [ ] Tjedan dana mjeriti rast `state` (bilo 146 GB u 22:25, 153 GB u 23:48), pa odlučiti o full pruning trigeru i upisati realnu procjenu trajanja diska.
- [x] Old bodies i receipts do kraja (00:27:33). Promet i disk izmjereni.
- [ ] **Nethermind ~1.500 % CPU nakon synca:** `sudo sample` pa uzrok. Ventilatori u mirovanju se mogu izmjeriti tek nakon toga.
- [ ] § 8 pravi restart (Wi-Fi bez logina!).
- [ ] Nakon synca: port forward 30303 TCP/UDP, 9000 TCP/UDP i 9001 UDP ([ADR-009](02-decisions.md#adr-009)), pa usporediti EL/CL peerove i CPU prije i poslije. `--p2p-quic-port` je u plistu tek nakon `sudo scripts/30-services.sh install teku`; vrijednost je ista kao Tekuov default, pa nije hitno.
- [ ] Očistiti root ostatke gpg-a u `~/.gnupg` i provjeriti GPG potpis Nethermind 2.1.0.
- [ ] RustDesk: ostaje li na čvoru.
- [ ] Disk pratiti tijekom synca. Ako slobodno padne ispod ~50 GB, slijedi čišćenje: obrisati račun `stepanic` (procjena +110 GB) i/ili s `ms` ukloniti `~/Library/Developer/CoreSimulator`, Xcode.app (CLT ostaju), Android Studio, FlutterFlow, `fvm`, `.pub-cache`, `.cocoapods` i instalere iz Downloads. `.nvm` ostaje, jer listener treba Node 22+.
- [ ] Prije brisanja računa `stepanic` provjeriti nepushane commitove u `/Users/stepanic/git` (31 GB).
- [ ] `~/thermal-backup` (root, rujan 2026: backup LaunchAgents/Daemons, „server-mode”) **ne brisati** dok se ne zna što je.
- [ ] Ostaci Docker Desktopa: `sudo launchctl bootout system/com.docker.{vmnetd,socket}`, pa obrisati plistove, helpere i `/usr/local/bin/docker*`. Nije hitno.

## Vezani dokumenti

- [docs/03-macbook-host.md](03-macbook-host.md): disk kao jedino stvarno ograničenje
- [docs/04-install-runbook.md](04-install-runbook.md)
- [2026-10-01 — prepisivanje i otvorene stavke](2026-10-01-prepisivanje-i-otvorene-stavke.md)
