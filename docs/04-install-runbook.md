# 04 — Instalacija korak po korak (i9 MacBook)

Od čistog Maca do sinkroniziranog čvora. Koraci 1–6 traju oko 30 minuta rada, a sinkronizacija nakon toga traje satima. Svaki korak se može ponoviti.

## 0. Prije početka

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

Skripta preuzima Nethermind 2.0.0, Temurin JRE 25 i Teku 26.9.1 (oko 450 MB) i provjerava svaki SHA-256 iz `config/versions.env`. Ako checksum ne odgovara, skripta staje i briše fajl.

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
   - headeri, zatim snap sync stanja, zatim old bodies i receipts;
   - realna procjena je nekoliko sati za stanje plus do dan za povijest (nije izmjereno na ovom stroju);
   - CPU je visoko, a ventilatori rade punom brzinom.
3. **Gotovo:**
   - `eth_syncing` vraća `false`;
   - head je star manje od 30 s;
   - Teku `sync distance` je 0 i nije optimistic.

S `NM_FLATDB=false` se prekid sinkronizacije nastavlja od zadnje točke. Ipak, u tom periodu ne restartati bez razloga.

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
