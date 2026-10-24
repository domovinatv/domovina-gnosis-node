# 08 — Validator (1 GNO)

> Preduvjet: čvor je sinkroniziran i stabilan (`gnosisctl health` je zelen, a pravi restart je prošao).
> Činjenice su provjerene 2026-10-01 ([istraživanje](research/2026-10-01-validator.md)), a Teku 26.10.0 CLI flagovi i `ethstaker-deposit-cli` v1.3.0 checksumi dodatno potvrđeni 2026-10-24 na `i9`.

## Ekonomija u brojkama

| | |
| --- | --- |
| Ulog | **1 GNO** po validatoru (`32.000.000.000` mGNO Gwei u beacon stanju), na Gnosis Chainu (ne na Ethereumu) |
| Prinos | ~**8,6 % godišnje** (mrežni prosjek), otprilike 0,086 GNO na godinu |
| Korak kompoundiranja (0x02) | `EFFECTIVE_BALANCE_INCREMENT` je **1/32 GNO** (`0,03125 GNO` = `1.000.000.000` mGNO Gwei), do maksimalno 64 GNO po validatoru |
| Ispad (laptop offline) | gubi se otprilike koliko bi se zaradilo, oko 0,0004 GNO dnevno; nema gubitka uloga dok mreža finalizira |
| Slashing | samo za dvostruko potpisivanje: isti ključ na dva mjesta istovremeno |
| Red za aktivaciju | prazan; churn je 2 GNO po epohi (80 s), ~2.160 GNO dnevno |
| MEV-boost | **ne postoji na Gnosisu**, ne instalirati |

Validator koji radi više od 42,5 % vremena je u plusu. Prijetnja nije downtime nego **slashing**.

---

## 0. Kontrolna lista prije početka

Prije generiranja ključeva provjeri ove 4 stavke:

1. **Test pravog restarta Maca ([docs/05](05-operations.md#planirani-restart)):**
   ```bash
   scripts/gnosisctl stop all
   sudo shutdown -r now
   # nakon boota:
   scripts/gnosisctl status && scripts/gnosisctl health
   ```
   Time potvrđujemo da macOS Background Task Management (BTM) sam podigne LaunchDaemone nakon restarta.
2. **Odabir `withdrawal_address` i `FEE_RECIPIENT` adrese:**
   - **Withdrawal adresa (`0x…`)**: hardverski novčanik (Ledger/Trezor) ili Safe (npr. MPT Safe). **Nikad se ne može promijeniti nakon generiranja ključa.** Na nju idu nagrade i ulog pri izlazu.
   - **`FEE_RECIPIENT` (`0x…`)**: adresa na koju idu transakcijske napojnice (priority fees u xDAI) kad naš validator predloži blok. Može biti ista adresa kao withdrawal adresa, a u `config/node.env` se može promijeniti bilo kada.
3. **1 GNO + malo xDAI za gas na Gnosis Chainu:**
   - Uplata depozita može ići s **bilo kojeg novčanika** (npr. hot wallet s točno 1 GNO i 0,1 xDAI), jer vlasništvo nad validatorom određuje isključivo `withdrawal_address` ugrađena u `deposit_data-*.json`, a ne adresa uplatitelja.
   - Ako je GNO na Ethereumu, prebacuje se preko [bridge.gnosischain.com](https://bridge.gnosischain.com/).
4. **USB stick + papir/metal** (dvije fizičke kopije za 24 riječi mnemonica).

---

## 1. Generiranje ključeva (offline) ✋

Alat je [ethstaker-deposit-cli](https://github.com/ethstaker/ethstaker-deposit-cli) v1.3.0 (auditirao Trail of Bits). Stari `gnosischain/validator-data-generator` se **ne koristi** (posljednji release 2022, zna samo 0x01).

Verzija i SHA-256 checksumi su u [`config/versions.env`](../config/versions.env) (ima i `darwin-amd64` za Intel Mac i `darwin-arm64` za Apple Silicon Mac ako se ključevi generiraju na drugom Macu):

1. Na mrežnom računalu skinuti odgovarajući arhiv i provjeriti checksum iz `config/versions.env`:
   ```bash
   source config/versions.env
   # Za Intel Mac (darwin-amd64):
   curl -fLO "https://github.com/ethstaker/ethstaker-deposit-cli/releases/download/$ETHSTAKER_DEPOSIT_CLI_VERSION/$ETHSTAKER_DEPOSIT_CLI_FILE"
   echo "$ETHSTAKER_DEPOSIT_CLI_SHA256  $ETHSTAKER_DEPOSIT_CLI_FILE" | shasum -a 256 -c -

   # Ili za Apple Silicon Mac (darwin-arm64):
   curl -fLO "https://github.com/ethstaker/ethstaker-deposit-cli/releases/download/$ETHSTAKER_DEPOSIT_CLI_VERSION/$ETHSTAKER_DEPOSIT_CLI_ARM64_FILE"
   echo "$ETHSTAKER_DEPOSIT_CLI_ARM64_SHA256  $ETHSTAKER_DEPOSIT_CLI_ARM64_FILE" | shasum -a 256 -c -
   ```
   Dodatna provjera potpisa (ako je instaliran `gh`):
   ```bash
   gh attestation verify ethstaker_deposit-cli-*.tar.gz --repo ethstaker/ethstaker-deposit-cli
   ```
2. Raspakirati arhiv, ukloniti macOS Gatekeeper karantenu i prebaciti na USB:
   ```bash
   tar -xzf ethstaker_deposit-cli-*.tar.gz
   xattr -dr com.apple.quarantine ethstaker_deposit-cli-*
   ```
3. Generirati ključeve na **offline** stroju (Wi-Fi isključen i mrežni kabel izvučen, ili Tails live USB):
   ```bash
   ./deposit new-mnemonic --chain gnosis --num_validators 1 \
     --withdrawal_address 0xTVOJA_HW_WALLET_ILI_SAFE_ADRESA \
     --compounding --amount 1 --folder ./validator_keys
   ```
   - `--compounding` daje `0x02` credentials ([ADR-006](02-decisions.md#adr-006)).
   - `--amount 1` je izražen u GNO (u `deposit_data-*.json` bit će zapisano `32000000000`, što je 1 GNO u Gnosis beacon jedinicama).
   - Lozinku za keystore i mnemonic **ne pisati u naredbu**. Alat ih traži interaktivno (lozinku spremiti u password manager tek nakon generiranja).
4. **Mnemonic (24 riječi)** zapisati **na papir ili metal** i čuvati na dva fizička mjesta. Nikad ga ne spremati u fajl, fotografiju, cloud, password manager ni git repo.
5. Na USB kopirati samo mapu `validator_keys/` (`keystore-*.json` i `deposit_data-*.json`), a lokalnu kopiju na offline stroju sigurno obrisati (`rm -P validator_keys/* && rmdir validator_keys`).

---

## 2. Provjera i uvoz na čvor (`i9`)

Prije uvoza i prije uplate depozita, pokreni `verify` nad mapom s ključevima (ne traži `sudo`, samo čita JSON fajlove):

```bash
scripts/40-validator.sh verify /Volumes/USB/validator_keys
```

Skripta provjerava i ispisuje:
- da svaki `keystore-*.json` odgovara zapisu u `deposit_data-*.json`,
- da je mreža `gnosis` i `fork_version` `0x00000064` (sprječava slučajno generiranje ključa za Ethereum mainnet),
- da su credentials `0x02` (compounding) i da je iznos `1 GNO`,
- **točnu withdrawal adresu (`0x…`)** izvučenu iz `withdrawal_credentials` — usporedi je znak po znak s adresom svog hardverskog novčanika ili Safea!

Zatim u `config/node.env` postavi `VALIDATOR_ENABLED=true` i `FEE_RECIPIENT=0x…`, uvezi ključ i instaliraj servis:

```bash
# U config/node.env:
#   VALIDATOR_ENABLED=true
#   FEE_RECIPIENT=0xTVOJA_ADRESA_ZA_NAPOJNICE

sudo scripts/40-validator.sh import /Volumes/USB/validator_keys
sudo scripts/30-services.sh install teku validator
scripts/gnosisctl logs validator
```

> **Zašto `install teku validator`, a ne samo `validator`:** Teku beacon node također prima `--validators-proposer-default-fee-recipient=$FEE_RECIPIENT` kao rezervnu adresu za Engine API pri izradi blokova. Regeneriranjem oba plista i beacon node i validator client imaju istu adresu.

- Ključevi idu u `/opt/gnosis/validator/keys`, a lozinka u `/opt/gnosis/validator/passwords/<ime>.txt` (`_gnosis` `600`, direktoriji `700`).
- Doppelganger zaštita (`--doppelganger-detection-enabled=true`) prve 2–3 epohe (oko 4 minute) samo osluškuje ima li isti ključ negdje drugdje u mreži, pa tek onda počinje potpisivati.
- U logu treba vidjeti `Loaded 1 Validators` i da nema `FATAL` ni `ERROR`.
- Provjeri i lokalni status:
  ```bash
  scripts/gnosisctl status
  scripts/gnosisctl health
  sudo scripts/40-validator.sh status
  ```
  Prije uplate depozita `40-validator.sh status` ispisat će `status: not_on_chain_yet (awaiting deposit or ~1.5h activation)`.

---

## 3. Depozit (1 GNO) ✋

Tek kad `validator` servis radi na `i9` i `gnosisctl health` je zelen:

1. Na Gnosis Chainu pripremi novčanik s **1 GNO** i malo **xDAI** za gas.
2. Otvori [validators.gnosischain.com](https://validators.gnosischain.com/) (`deposit.gnosischain.com` preusmjerava tamo) i spoji novčanik (MetaMask, Rabby ili Safe kroz WalletConnect / Custom App).
3. Učitaj `deposit_data-*.json` i provjeri prikazane podatke.
4. Prije potpisa u novčaniku provjeri adrese ugovora:
   - Transakcija zove `transferAndCall` na **GNO tokenu** `0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb`.
   - **Deposit ugovor** je `0x0B98057eA310F4d31F2a452B414647007d1645d9`.
5. Aktivacija: nakon što beacon lanac obradi depozit (~1–1,5 h uz prazan red), validator prelazi iz `pending_initialized` → `pending_queued` → `active_ongoing`.
   Stanje možeš pratiti izravno sa svog čvora bez vanjskog explorera:
   ```bash
   sudo scripts/40-validator.sh status
   ```
   ili na [beaconchain.gnosischain.com](https://beaconchain.gnosischain.com/) (pretraga po pubkeyu).
6. Prijavi withdrawal adresu u Telegram bot [@gbc_validators_bot](https://t.me/gbc_validators_bot) za obavijesti o statusu i eventualno propuštenim atestacijama.

---

## 4. Redovni rad i isplata nagrada

- Validator radi kao LaunchDaemon `tv.domovina.gnosis.validator` (Teku VC, `-Xmx2g`). Kroz lokalni REST API na `127.0.0.1:5052` razgovara s Teku beacon nodeom.
- `scripts/gnosisctl health` automatski provjerava i `validator.log` (ima li `ERROR`/`FATAL` u zadnjih 500 linija i ispisuje zadnju objavljenu atestaciju ili blok).
- **Kako rade nagrade s `0x02` (compounding):**
  - Consensus nagrade (atestacije, prijedlozi blokova, sync committee) ostaju u balansu validatora na beacon lancu.
  - Kad balans naraste za `0,03125 GNO` (`1/32 GNO`, uz malo histereze), `effective_balance` automatski raste s `1,00000 GNO` na `1,03125 GNO`, pa validator zarađuje nagrade na veći ulog.
  - Execution napojnice (priority fees u xDAI iz predloženih blokova) sjedaju izravno na `FEE_RECIPIENT` adresu u istom bloku.
- **Djelomična isplata nagrada (bez gašenja validatora):**
  - Budući da je ključ `0x02`, nema automatskog sweepa ispod 64 GNO.
  - Kad želiš povući nagomilane nagrade iznad 1 GNO, spojiš se s `withdrawal_address` na [validators.gnosischain.com](https://validators.gnosischain.com/) i pošalješ EIP-7002 zahtjev za djelomičnu isplatu (Partial Withdrawal).
  - Nakon što sweep prebaci GNO u deposit ugovor (`0x0B98057eA310F4d31F2a452B414647007d1645d9`), preuzmeš ga klikom na **Claim** (ili pozoveš `claimWithdrawal(withdrawal_address)`).
- Prije svakog Gnosis hard forka obavezno nadogradi Nethermind i Teku ([docs/05](05-operations.md#hard-forkovi)).

---

## 5. Selidba na drugi stroj (ili reinstalacija)

Ovo je jedini realan put do slashinga. Redoslijed je **obavezan**:

1. `scripts/gnosisctl stop validator` na starom stroju.
2. `sudo scripts/40-validator.sh slashing-export ~/slashing.json`.
3. **Fizički onemogućiti** stari VC: `sudo scripts/30-services.sh uninstall validator`, obrisati `/opt/gnosis/validator/keys/*` i ugasiti stari stroj.
4. Pričekati barem **2 epohe** (otprilike 3 minute; sigurnije 15 min) i provjeriti (`40-validator.sh status` ili explorer) da validator propušta atestacije — to je dokaz da nijedan proces više ne potpisuje.
5. Na novom stroju:
   - prvo `sudo scripts/40-validator.sh slashing-import ~/slashing.json`,
   - zatim `sudo scripts/40-validator.sh import /putanja/do/keys`,
   - zatim `sudo scripts/30-services.sh install teku validator`.

Nikad se ne radi „backup validator koji čeka u pripravnosti”. Dva VC-a s istim ključem znače slashing, a doppelganger zaštita je dodatni osigurač, ne apsolutna garancija.

---

## 6. Dobrovoljni izlaz (Voluntary Exit)

```bash
sudo scripts/40-validator.sh exit
```

Ili iz web sučelja [validators.gnosischain.com](https://validators.gnosischain.com/) (Withdraw → MAX → Exit validator) potpisom s `withdrawal_address`.

Izlaz je **trajan**: izašli validator ne može se ponovno aktivirati istim ključem. Nakon izlaza slijedi period od 256 epoha (~5,7 h), zatim sweep u deposit ugovor, nakon čega se cijeli ulog + nagrade preuzimaju preko **Claim** na `validators.gnosischain.com`.

---

## 7. Rizici specifični za kućni/uredski validator {#7-rizici-specificni-za-kucni-validator}

| Rizik | Mjera |
| --- | --- |
| IP ureda se može povezati s validatorom (timing analiza P2P prometa) | ne objavljivati javno koji je validator index/pubkey naš; posljedica je ciljani DoS, ne krađa sredstava ([docs/09](09-security.md)) |
| Nestanak struje | baterija MacBooka drži sam čvor satima, ali ako router nema UPS, čvor gubi internet; kratki ispadi koštaju ~0,0004 GNO/dan |
| FileVault restart bez nadzora | ako je FileVault uključen, običan restart čeka lozinku prije boota; za planirani restart koristiti `sudo fdesetup authrestart` ([docs/03](03-macbook-host.md#filevault)) |
| Propušten hard fork | pretplata na GitHub Releases (`NethermindEth/nethermind`, `Consensys-Incorporated/teku`), nadogradnja barem tjedan dana prije forka |
