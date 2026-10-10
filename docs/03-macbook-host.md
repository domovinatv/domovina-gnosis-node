# 03 — MacBook kao server

Stroj: MacBook Pro 16" (2019), Intel Core i9 (8 jezgri / 16 dretvi), 64 GB RAM, 1 TB NVMe, T2 čip, macOS 26 Tahoe (zadnji macOS za Intel).

`scripts/10-host-setup.sh` automatski postavlja sve u ovom dokumentu što se dade skriptirati. Ostalo su ručni koraci; svaki je označen s ✋.

## Zahtjevi i stvarnost

| | Minimum za Gnosis | Ovaj stroj |
| --- | --- | --- |
| CPU | 4 dretve | 16 dretvi |
| RAM | 16 GB | 64 GB |
| Disk | NVMe, uglavnom ograničen prostorom | 1 TB NVMe |
| Mreža | ~700 MB/h upload | žičani Ethernet preporučen |

**Disk je jedino stvarno ograničenje.** Nethermind dokumentacija navodi oko 509 GB za Gnosis čvor (podatak bez datuma, stariji backend), uz to Teku desetak GB. Na 1 TB disku s macOS-om ostaje rezerva od oko 300 GB. Pratiti preko `gnosisctl health`, koji javlja grešku ispod 100 GB slobodnog.

✋ Prije instalacije maknuti sve što ne treba s ovog Maca. `00-preflight.sh` traži barem 500 GB slobodnog, a preporučuje 700 GB.

## Napajanje (pmset)

`10-host-setup.sh` postavlja:

```
sleep 0  disksleep 0  displaysleep 10  powernap 0  standby 0  autopoweroff 0
hibernatemode 0  tcpkeepalive 1  womp 1  ttyskeepawake 1
lowpowermode 0           (samo ako `pmset -g cap` to nudi)
autorestartatconnect 1   (samo ako `pmset -g cap` to nudi)
```

- **Low Power Mode** spušta takt CPU-a i na struji. Na i9 je zatečen uključen (`lowpowermode 1`) i za AC i za bateriju.

- Sustav nikad ne spava. Ekran se gasi nakon 10 minuta, a čvor radi i dalje.
- `autorestart` (paljenje nakon nestanka struje) je opcija za desktop računala i na laptopu je nema. **Baterija je UPS**: s njom stroj prebrodi nestanak struje bez gašenja.
- MBP 2019 na macOS-u 26 **nema** ni `autorestart` ni `autorestartatconnect` u `pmset -g cap` (provjereno 2026-10-10). Hoće li se upaliti sam kad se baterija potpuno isprazni pa dobije struju, nije provjereno. Ne oslanjati se na to.

✋ **Poklopac ostaje otvoren.** Clamshell mode traži vanjski monitor, a i9 se zatvoren dodatno grije. Ekran se ugasi ili mu se svjetlina spusti na nulu.

## Baterija na punjaču 24/7

Baterija koja stoji na 100 % i k tome je topla brzo stari i može nabubriti.

- „Battery health management” na Intelu je uključen po defaultu. On smanjuje maksimalno punjenje, ali **ne postavlja tvrdi limit**. Fiksni „Charge Limit” u postavkama macOS 26.4 postoji samo na Apple Siliconu.
- ✋ Instalirati [AlDente](https://apphousekitchen.com/) i postaviti limit na **75–80 %**.
  - Besplatna verzija ima limiter i podržava macOS 26.
  - AlDente je GUI aplikacija, pa treba ulogiranog korisnika. Čvor radi i bez logina, ali limiter tada ne radi.
- `bclm` ne radi na macOS-u 15 i novijem bez gašenja SIP-a, pa ga ne koristiti.
- ✋ Jednom mjesečno provjeriti stanje baterije:
  ```bash
  system_profiler SPPowerDataType | grep -E 'Condition|Cycle Count|Maximum Capacity'
  ```
  Ako se trackpad počne izdizati, baterija buja: stroj ugasiti i servisirati.

## Toplina

- Prva sinkronizacija drži CPU visoko satima, pa ventilatori rade punom brzinom. U normalnom radu opterećenje je nisko.
- ✋ Stroj staviti na tvrdu podlogu ili postolje s protokom zraka, nikad u ladicu ili na tkaninu.

## FileVault: svjesna odluka {#filevault}

S uključenim FileVaultom **svaki neplanirani restart staje na ekranu za lozinku**, a čvor ne radi dok netko ne upiše lozinku. To vrijedi za panic, update ili potpuno ispražnjenu bateriju.

| | FileVault ON | FileVault OFF |
| --- | --- | --- |
| Neplanirani restart | čvor stoji do fizičkog unosa lozinke | čvor se sam digne |
| Planirani restart | `sudo fdesetup authrestart` preskoči unos jednom | normalno |
| Ukraden laptop | disk zaštićen | T2 kriptira disk, ali ključ nije vezan za lozinku; zaštićen je samo izvađeni disk |

**Preporuka: FileVault ON**, jer će na stroju biti validatorski ključevi, a stroj stoji u uredu.

- Validator koji ne radi samo propušta nagrade (oko 0,0004 GNO dnevno) i ne gubi ulog.
- Uz to keystorei su ionako kriptirani, a lozinke čita samo `_gnosis`.
- Ako je važnije da RPC za novčanik radi bez prekida, FileVault OFF je legitiman izbor. Zapisati ga kao novi ADR.

Planirani restart s uključenim FileVaultom:
```bash
scripts/gnosisctl stop all          # čisto gašenje baza
sudo fdesetup authrestart
```

## Automatski updateovi

macOS koji se sam restarta noću znači prekid rada. Uz FileVault čvor nakon toga stoji dok netko ne upiše lozinku. `10-host-setup.sh` isključuje automatsku instalaciju:

```
softwareupdate --schedule off
com.apple.SoftwareUpdate AutomaticDownload=false, AutomaticallyInstallMacOSUpdates=false
com.apple.commerce AutoUpdate=false
```

✋ U System Settings → General → Software Update → Automatic Updates (ⓘ) isključiti „Install macOS updates” i „Install application updates”. Nije potvrđeno da Tahoe poštuje gornje `defaults` ključeve.

✋ Updateove instalirati ručno, jednom mjesečno, uz planirani restart ([docs/05](05-operations.md#planirani-restart)).

## Firewall

`10-host-setup.sh` uključuje application firewall i stealth mode. Firewall filtrira samo dolazne veze. Za P2P ingress ([ADR-009](02-decisions.md#adr-009)) `nethermind` i `java` moraju imati „Allow incoming connections” (`/usr/libexec/ApplicationFirewall/socketfilterfw --listapps`).

## Background Task Management {#background-task-management}

macOS 13+ prati sve pozadinske servise.

- Pri prvom `30-services.sh install` za svaki daemon stigne obavijest „Allow in the Background”. ✋ Dopustiti je, ili kasnije u System Settings → General → Login Items & Extensions.
- Na novijim verzijama BTM može **tiho** blokirati daemon čiji izvršni fajl nije potpisan Apple Developer ID-jem. To je razlog zašto plist za Teku pokreće `java` izravno, a ne shell skriptu.
- Provjera:
  ```bash
  sudo sfltool dumpbtm | grep -B2 -A8 tv.domovina
  ```
  Ako piše `disallowed`, servis treba dopustiti u Login Items.
- ✋ **Nakon instalacije napraviti jedan pravi restart** i provjeriti `gnosisctl status`. Ručni `bootstrap` može raditi do prvog bootanja i tek tada pasti.

## Vrijeme

Validator treba sat točan na manje od 0,5 s, a poželjno ispod 100 ms. macOS `timed` je obično unutar desetaka milisekundi.

- `00-preflight.sh` i `gnosisctl health` mjere odstupanje prema `time.cloudflare.com`.
- Ako je stalno iznad 100 ms, instalirati chrony (izvan opsega ovog repoa).

## Mreža

- ✋ Za prvu sinkronizaciju koristiti USB-C Gigabit Ethernet.
- U normalnom radu Wi-Fi radi, ali žica je stabilnija.
- Statička IP adresa i port forwarding nisu nužni, ali s forwardom P2P portova čvor ima više peerova ([ADR-009](02-decisions.md#adr-009)).
