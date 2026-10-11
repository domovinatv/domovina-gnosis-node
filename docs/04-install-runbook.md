# 04 — Instalacija korak po korak (i9 MacBook)

Od čistog Maca do sinkroniziranog čvora. Koraci 1–6 traju oko 30 minuta rada, a sinkronizacija nakon toga traje satima. Svaki korak se može ponoviti.

## 0. Prije početka

Prvo pročitaj [otvorene stavke iz 2026-10-01](2026-10-01-prepisivanje-i-otvorene-stavke.md#otvorene-stavke-na-i9): to je popis onoga što pri ovoj instalaciji treba provjeriti i zapisati.

Prva stvarna instalacija na i9 (2026-10-10/11) je opisana u [dnevniku](2026-10-10-prvo-pokretanje-i9-disk.md). Svi problemi koje je pogodila su ispravljeni u skriptama ili navedeni u [poznatim problemima](05-operations.md#poznati-problemi). Ovaj runbook ih uzima u obzir.

Za `sudo` korake: naredbu pokreni sam u terminalu i pritisni Enter. Zalijepljen blok od više redova u iTermu zna ostaviti zadnji red neizvršen.


- [ ] Mac je na struji i na žičanom Ethernetu, poklopac je otvoren, stroj stoji na postolju.
- [ ] Na disku je barem 500 GB slobodnog, poželjno 700 GB ([docs/03](03-macbook-host.md)).
- [ ] Odlučeno je o FileVaultu ([docs/03](03-macbook-host.md#filevault)).
- [ ] macOS je ažuriran ručno sada, kako ne bi tražio restart usred sinkronizacije.
- [ ] Instaliran je AlDente s limitom 80 %.

## 1. Command Line Tools i repo

```bash
xcode-select --install          # git, python3, make; potvrdi dijalog
git clone https://github.com/domovinatv/domovina-gnosis-node.git ~/domovina-gnosis-node
cd ~/domovina-gnosis-node
```

Homebrew nije potreban. Od verzije 7.0 Intel je kod Homebrewa tier 3, pa se paketi kompajliraju iz izvornog koda. Sve komponente se zato preuzimaju kao službeni binariji s provjerom checksuma.

## 2. Konfiguracija

```bash
cp config/node.env.example config/node.env
open -e config/node.env
```

Za prvo pokretanje defaulti su dobri:

- `CL_CLIENT=teku`
- `NM_FLATDB=false`
- `VALIDATOR_ENABLED=false`
- `LISTENER_ENABLED=false`

`config/node.env` je u `.gitignore`. Promjene defaulta koje vrijede za sve unose se u `node.env.example`.

## 3. Preflight

```bash
scripts/00-preflight.sh
```

Skripta samo čita. Sve oznake `FAIL` treba riješiti prije nastavka, a `warn` pročitati.

## 4. Priprema hosta

```bash
sudo scripts/10-host-setup.sh
```

Skripta:

- stvara skrivenog korisnika `_gnosis` (uid 470) i dodaje tebe u njegovu grupu;
- stvara `/opt/gnosis/…` s ispravnim vlasnicima;
- generira `secrets/jwt.hex`;
- postavlja pmset, gasi automatske updateove i uključuje firewall;
- postavlja newsyslog za listener.

Odjavi se i ponovno prijavi, kako bi članstvo u grupi `_gnosis` počelo vrijediti za čitanje logova.

✋ System Settings → Software Update → Automatic Updates: isključi automatsku instalaciju.

## 5. Instalacija klijenata

```bash
sudo scripts/20-install.sh
```

Skripta preuzima Nethermind, Temurin JRE i Teku u verzijama iz `config/versions.env` (oko 450 MB) i provjerava svaki SHA-256 iz `config/versions.env`. Ako checksum ne odgovara, skripta staje i briše fajl.

Prije pokretanja provjeri ima li novijih verzija (CLAUDE.md, pravilo 1). Svježa instalacija je najjeftiniji trenutak za upgrade.

Opcionalno, GPG provjera Netherminda (treba `gpg`):

```bash
gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys AD1279765093C6759CD8A40024A774616F1E617E
sudo scripts/20-install.sh nethermind   # sad ispisuje i "Good signature"
```

## 6. Servisi

```bash
sudo scripts/30-services.sh install
scripts/gnosisctl status
```

- ✋ Za svaki daemon stigne obavijest „Allow in the Background”: dopusti je.
- Teku povuče checkpoint za ~1 min i onda čeka EL (`EXECUTION_CLIENT_OFFLINE`). To je normalno.
- Nethermind na praznoj bazi starta za ~10 s. **Nakon svakog kasnijeg restarta šuti u logu ~4,5–5 min** dok otvara bazu od nekoliko stotina GB. To nije zastoj.
- Ako `status` pokazuje `not loaded`, ili servis stalno ima novi PID i `last exit` različit od 0, pogledaj:
  ```bash
  cat /opt/gnosis/logs/<servis>.stderr.log
  scripts/gnosisctl logs <servis>
  ```

## 7. Sinkronizacija

```bash
scripts/gnosisctl health          # ponavljati
scripts/gnosisctl logs teku       # u drugom prozoru
scripts/gnosisctl logs nethermind
```

Očekivani tijek:

1. **Teku, prvih nekoliko minuta:** povuče finalizirano stanje s `checkpoint.gnosischain.com` i počne pratiti vrh lanca. Javlja `is_optimistic: true` dok EL ne sustigne.
2. **Nethermind, satima:**
   - headeri i snap sync stanja paralelno, zatim old bodies i receipts;
   - izmjereno na i9 (Wi-Fi, bez port forwarda, 4–8 EL peerova): **stanje 4 h 13 min, cijeli sync s godinom povijesti 6 h 15 min**. Detalji po fazama su u [dnevniku](2026-10-10-prvo-pokretanje-i9-disk.md);
   - prvih ~2 h snap ide sporo, jer EL peerove zauzimaju headeri. Nakon headera ubrza;
   - povijest se preuzima samo od `NM_HISTORY_FROM_BLOCK`, a pomični prozor (`NM_HISTORY_RETENTION_EPOCHS`) briše stariju ([ADR-010](02-decisions.md#adr-010)). **Oba broja treba izračunati za datum instalacije**: blok od prije godinu dana nađi preko `eth_getBlockByNumber` i `timestamp` (Gnosis prosjek je ~5,2 s po bloku, a ne točno 5 s);
   - CPU je visoko, a ventilatori rade punom brzinom.
3. **Gotovo:**
   - `eth_syncing` vraća `false`;
   - head je star manje od 30 s;
   - Teku `sync distance` je 0 i nije optimistic.

S `NM_FLATDB=false` se prekid sinkronizacije nastavlja od zadnje točke. Ipak, u tom periodu ne restartati bez razloga.

### Nakon synca: CPU mora pasti

Kad je čvor na vrhu lanca, obrada bloka traje ~35 ms svakih 5 s. Ako Nethermind i dalje troši stotine posto CPU-a, uzrok je jedan od [poznatih problema](05-operations.md#poznati-problemi). Uzrok se nalazi ovako:

```bash
sudo scripts/20-install.sh diagtools       # jednom
scripts/gnosisctl dotnet-trace 30          # pa raspodjela CPU-a po metodama
```

## 8. Pravi restart

Ovo je jedini način da se potvrdi da Background Task Management ne blokira daemone:

```bash
scripts/gnosisctl stop all
sudo fdesetup authrestart      # s FileVaultom; bez njega: sudo shutdown -r now
# nakon boota, BEZ logina pričekaj 2–3 minute, zatim se ulogiraj:
scripts/gnosisctl status
sudo sfltool dumpbtm | grep -A8 tv.domovina
```

## 9. Zabilježi

U ovaj repo, u `docs/05-operations.md` pod „Dnevnik”, upiši:

- datum instalacije;
- stvarno trajanje sinkronizacije;
- zauzeće diska nakon sinkronizacije (`du -sh /opt/gnosis/data/*`);
- sve što je odstupalo od ovog runbooka.

Sljedeći koraci:

- payment listener: [docs/07](07-wallet-notifications.md);
- RPC prema van: [docs/06](06-rpc-exposure.md);
- validator: [docs/08](08-validator.md).
