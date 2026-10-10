# 2026-10-10 — Prvi preflight na i9 i čišćenje diska

Prvi put je repo pokrenut na ciljnom stroju. Instalacija još nije krenula, jer je preflight pao na disku.

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

## Otvoreno

- [ ] Do preporučenih 700 GB fali oko 165 GB. Dvije opcije: obrisati cijeli račun `stepanic` (Users & Groups → Delete User; procjena +110 GB) i/ili s `ms` ukloniti Docker.app i njegov kontejner, `~/Library/Developer/CoreSimulator`, Xcode.app (CLT ostaju), Android Studio, FlutterFlow, `fvm`, `.pub-cache`, `.cocoapods` i instalere iz Downloads (procjena do +90 GB). `.nvm` ostaje, jer listener treba Node 22+.
- [ ] Prije brisanja računa `stepanic` provjeriti nepushane commitove u `/Users/stepanic/git` (31 GB).
- [ ] `~/thermal-backup` (root, rujan 2026: backup LaunchAgents/Daemons, „server-mode”) **ne brisati** dok se ne zna što je.
- [ ] Nakon čišćenja: `scripts/00-preflight.sh`, pa `sudo scripts/10-host-setup.sh` po [runbooku](04-install-runbook.md).

## Vezani dokumenti

- [docs/03-macbook-host.md](03-macbook-host.md): disk kao jedino stvarno ograničenje
- [docs/04-install-runbook.md](04-install-runbook.md)
- [2026-10-01 — prepisivanje i otvorene stavke](2026-10-01-prepisivanje-i-otvorene-stavke.md)
