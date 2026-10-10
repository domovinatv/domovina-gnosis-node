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

## Otvoreno

- [x] Instalacija do § 5: preflight, `10-host-setup.sh`, `20-install.sh`.
- [ ] § 6 servisi i § 7 sync po [runbooku](04-install-runbook.md).
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
