# 08 — Validator (1 GNO)

> Preduvjet: čvor je sinkroniziran i barem tjedan dana stabilan (`gnosisctl health` je zelen, a pravi restart je prošao).
> Činjenice su provjerene 2026-10-01 ([istraživanje](research/2026-10-01-validator.md)).

## Ekonomija u brojkama

| | |
| --- | --- |
| Ulog | **1 GNO** po validatoru, na Gnosis Chainu (ne na Ethereumu) |
| Prinos | ~**8,6 % godišnje** (mrežni prosjek 2026-09-30), otprilike 0,086 GNO na godinu |
| Ispad (laptop offline) | gubi se otprilike koliko bi se zaradilo, oko 0,0004 GNO dnevno; nema gubitka uloga dok mreža finalizira |
| Slashing | samo za dvostruko potpisivanje: isti ključ na dva mjesta |
| Red za aktivaciju | prazan (2026-10-01); churn je 2 GNO po epohi |
| MEV-boost | **ne postoji na Gnosisu**, ne instalirati |

Validator koji radi više od 42,5 % vremena je u plusu. Prijetnja nije downtime nego **slashing**.

## 1. Generiranje ključeva (offline) ✋

Alat je [ethstaker-deposit-cli](https://github.com/ethstaker/ethstaker-deposit-cli) v1.3.0, `darwin-amd64`. Stari `gnosischain/validator-data-generator` se **ne koristi** (posljednji release 2022, samo 0x01).

1. Na mrežnom računalu skinuti `ethstaker_deposit-cli-d8016bc-darwin-amd64.tar.gz` i njegov `.sha256`, pa provjeriti:
   ```bash
   shasum -a 256 ethstaker_deposit-cli-*-darwin-amd64.tar.gz     # mora odgovarati .sha256
   gh attestation verify ethstaker_deposit-cli-*-darwin-amd64.tar.gz --repo ethstaker/ethstaker-deposit-cli
   ```
2. Prebaciti alat na USB i generirati ključeve na **offline** stroju: Wi-Fi isključen i kabel izvučen, ili Tails live USB.
   ```bash
   ./deposit new-mnemonic --chain gnosis --num_validators 1 \
     --withdrawal_address 0xTVOJA_HW_WALLET_ILI_SAFE_ADRESA \
     --compounding --amount 1 --folder ./validator_keys
   ```
   - `--compounding` daje 0x02 credentials ([ADR-006](02-decisions.md#adr-006)).
   - `--amount` je izražen u GNO.
   - Lozinku i mnemonic **ne pisati u naredbu**. Alat ih traži interaktivno.
3. Mnemonic (24 riječi) zapisati **na papir ili metal** i čuvati na dva fizička mjesta. Nikad ga ne spremati u fajl, foto, password manager ni repo.
4. Na čvor ide samo `validator_keys/keystore-*.json`. `deposit_data-*.json` treba samo za uplatu i nije tajna.

**Withdrawal adresa se ne može promijeniti.** Treba je tri puta provjeriti: na nju idu svi isplaćeni GNO.

## 2. Uvoz na čvor

```bash
# config/node.env:
#   VALIDATOR_ENABLED=true
#   FEE_RECIPIENT=0x…        (adresa za napojnice iz predloženih blokova)
sudo scripts/40-validator.sh import /Volumes/USB/validator_keys
sudo scripts/30-services.sh install validator
scripts/gnosisctl logs validator
```

- Ključevi idu u `/opt/gnosis/validator/keys`, a lozinka u `passwords/<ime>.txt`. Oba su `_gnosis` 600.
- Doppelganger zaštita prve 2–3 epohe (oko 4 minute) samo osluškuje ima li isti ključ negdje drugdje u mreži, pa tek onda potpisuje.
- U logu treba vidjeti `Loaded 1 Validators` i da nema `FATAL`.

## 3. Depozit ✋

Tek kad VC radi i čvor je u syncu:

1. Na Gnosis Chainu treba imati 1 GNO i malo xDAI za gas. GNO s Ethereuma se prebacuje preko Omnibridgea.
2. Otvoriti [validators.gnosischain.com](https://validators.gnosischain.com/) (`deposit.gnosischain.com` preusmjerava tamo) i spojiti novčanik.
3. Učitati `deposit_data-*.json` i potpisati transakciju.
   - Transakcija zove `transferAndCall` na GNO tokenu `0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb`.
   - Deposit ugovor je `0x0B98057eA310F4d31F2a452B414647007d1645d9`.
   - Adrese treba provjeriti u novčaniku prije potpisa.
4. Aktivacija: dokumentacija kaže oko 1,5 h. S praznim redom je vjerojatno brže.
5. Validator pratiti na [beaconchain.gnosischain.com](https://beaconchain.gnosischain.com/) (po pubkeyu).
6. Prijaviti withdrawal adresu u Telegram bot [@gbc_validators_bot](https://t.me/gbc_validators_bot) za obavijesti o ispadima.

## 4. Rad

- Validator radi kao servis `tv.domovina.gnosis.validator` (Teku VC). Kroz REST na 5052 govori s Teku beacon nodeom.
- Nagrade se s 0x02 slažu u validator. Isplata dijela nagrada je zahtjev s withdrawal adrese (EIP-7002, mala naknada).
  - Isplaćeni GNO ne stiže sam na adresu: ide u deposit ugovor.
  - Preuzima se na validators.gnosischain.com (Claim) ili s autoclaimom.
- Prije svakog forka treba nadograditi Teku ([docs/05](05-operations.md#hard-forkovi)).

## 5. Selidba na drugi stroj (ili reinstalacija)

Ovo je jedini realan put do slashinga. Redoslijed je obavezan:

1. `scripts/gnosisctl stop validator` na starom stroju.
2. `sudo scripts/40-validator.sh slashing-export ~/slashing.json`.
3. **Fizički onemogućiti** stari VC: `sudo scripts/30-services.sh uninstall validator`, obrisati ključeve i ugasiti stroj.
4. Pričekati barem **2 epohe** (otprilike 3 minute; bolje 15 min) i na exploreru provjeriti da validator propušta atestacije.
5. Na novom stroju: prvo `slashing-import`, zatim `import` ključeva, zatim `30-services.sh install validator`.

Nikad se ne radi „backup validator koji čeka”. Dva VC-a s istim ključem znače slashing, a doppelganger zaštita nije garancija.

## 6. Izlaz (exit)

```bash
sudo scripts/40-validator.sh exit
```

Izlaz je trajan. Nakon izlaza slijedi 256 epoha (otprilike 5,7 h), zatim sweep, a 1 GNO se preuzima preko validators.gnosischain.com. Izlaz se može napraviti i iz web aplikacije, s withdrawal adrese.

## 7. Rizici specifični za kućni validator

| Rizik | Mjera |
| --- | --- |
| IP ureda se može povezati s validatorom (timing analiza P2P prometa) | ne objavljivati koji je validator naš; posljedica je ciljani DoS, ne krađa ([docs/09](09-security.md)) |
| Nestanak struje | baterija pokriva Mac, ali ne router; kratki ispadi koštaju malo |
| FileVault restart bez nadzora | validator stoji dok netko ne upiše lozinku ([docs/03](03-macbook-host.md#filevault)) |
| Propušten fork | release notifikacije, nadogradnja tjedan dana ranije |
