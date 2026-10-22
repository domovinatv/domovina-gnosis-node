# Provjera dugoročne stabilnosti, resursa i životnog ciklusa čvora (2026-10-22)

**Datum:** 2026-10-22 09:00 CEST  
**Stroj:** MacBook Pro 16" (2019, Intel Core i9, 64 GB RAM, 1 TB SSD, macOS 26)  
**Čvor:** Domovina Gnosis Node (Nethermind 2.1.0 + Teku 26.10.0)  
**Uptime procesa:** 11 dana, 7 sati neprekidnog rada (isti PID-ovi od 2026-10-11: Nethermind `3951`, Teku `18876`)

---

## 1. Mjerenja resursa nakon 11.5 dana rada

### 1.1. CPU profil
Nakon što su 2026-10-11 primijenjene zaobilaznice za thread-pool spin (`DOTNET_ThreadPool_UnfairSemaphoreSpinLimit=0`) i filtriranje nedavnih IP adresa (`--Network.FilterPeersByRecentIp false`), CPU je potpuno miran i stabilan:

- **Nethermind (`PID 3951`):**
  - Ukupno kumulativno CPU vrijeme: 9.433 minute kroz 271 sat rada.
  - Prosječno opterećenje od starta: **~58 % jedne CPU jezgre** (od 16 dostupnih virtualnih jezgri).
  - Trenutno opterećenje u mirovanju: ~31 % jedne jezgre.
- **Teku (`PID 18876`):**
  - Ukupno kumulativno CPU vrijeme: 3.964 minute kroz 278 sati rada.
  - Prosječno opterećenje od starta: **~24 % jedne CPU jezgre**.
  - Trenutno opterećenje u mirovanju: ~3 % jedne jezgre.
- **Cjelokupni sustav:** Sustav je konstantno **>80 % do 90 % idle**, load average je stabilan na ~2.4 – 3.0. Nisu zabilježeni CPU spikeovi.

### 1.2. Radna memorija (RAM i Swap)
- **Nethermind RSS:** **7,55 GB** (ispod zadanog limita prunera od 8 GB, `Pruning.CacheMb 8192`).
  - U logovima je vidljivo redovito okidanje `TrieStore` memory prunera (svakih ~30 min smanjuje dirty memory s ~210 MB na ~65 MB u ~750 ms).
- **Teku RSS:** **9,50 GB** (definiran `-Xmx6g` JVM heapom + off-heap / RocksDB slojem). Potpuno ravna potrošnja bez memory leaka (8,9 GB izmjereno 13. 10. vs 9,5 GB danas).
- **Zauzeto RAM-a za oba klijenta:** ~17 GB od 64 GB dostupnih na Macu.
- **Swap iskorištenost:** macOS `vm.swapusage`: iskorišteno **samo 6,5 MB swap-a**. Pritisak na memoriju je trajno zelen.

### 1.3. Disk i dinamika rasta
- **Nethermind baza:**
  - 2026-10-11 (nakon synca): **304 GB**
  - 2026-10-22 (nakon 11.5 dana): **311 GB**
  - Ukupni porast u 11.5 dana: **+7 GB** (prosječni rast samo **~0,6 GB dnevno**).
- **Teku baza:** **7,1 GB** (rast +0,4 GB u 11.5 dana).
- **Logovi:** 223 MB (rotacija uredno radi).
- **Slobodan prostor na disku:** **209 GiB (~224 GB)**.

---

## 2. Verifikacija pomičnog prozora od 367 dana (ADR-010)

U Nethermind logu (`/opt/gnosis/logs/nethermind/gnosis.log`) potvrđeno je aktivno izvršavanje `History.HistoryPruner` komponente:

```text
2026-10-22 08:31:05.1553|INFO|History.HistoryPruner|52|Pruning historical blocks up to #42538368 (512 estimated) and block access lists up to #48767072 (512 estimated). 
2026-10-22 08:31:05.1574|INFO|History.HistoryPruner|52|Reclaimed historical blocks #42537856 to #42538367, 0 remaining. 
2026-10-22 08:31:05.1574|INFO|History.HistoryPruner|52|Completed block pruning up to #42538368. Reclaimed 512 heights. 
2026-10-22 08:31:05.1574|INFO|History.HistoryPruner|52|Completed block access list pruning up to #48767072. Reclaimed 512 access lists. 
```

### Provjera matematike:
- Trenutni blok (head): `#48879xxx`
- Postavka: `NM_HISTORY_RETENTION_EPOCHS=198180`
- Nethermind 2.1.0 računa epohu kao 32 bloka: $198.180 \times 32 = 6.341.760$ blokova.
- Granica brisanja: $48.879.000 - 6.341.760 = 42.537.240$.
- To točno odgovara bloku `#42538368` koji pruner briše.
- Svaki prolaz prunera traje **~2 milisekunde**.
- **Zaključak:** Povijest tijela blokova i potvrda (receipts) uspješno je zaustavljena na fiksnoj veličini prozora (~150 GB) i više ne raste.

---

## 3. Životni ciklus i operativni plan za godinu dana

- **Što se događa nakon godinu dana rada?**
  Pomični prozor automatski nastavlja kliziti naprijed (uvijek čuvajući zadnjih 367 dana od trenutnog dana). Najstariji dan se automatski briše kako novi stiže.
- **Rast stanja (State Trie):**
  Jedini stvarni rast baze dolazi od rasta stanja (novi ugovori, nove adrese na mreži), po stopi od ~0,6 GB/dan. Kroz godinu dana to je rast od ~200 GB.
- **Kada i kako intervenirati:**
  1. `gnosisctl health` javlja grešku čim slobodan disk padne ispod **100 GB**.
  2. Kad disk padne ispod tog praga (procijenjeno za 12–18 mjeseci), **preporučena procedura je brzi planski resync**:
     - Na ovom hardveru početni snap sync s godinom povijesti trajao je svega **6 sati i 15 minuta**.
     - Brisanje baze i svježi resync vraća slobodan prostor na početnih **~300+ GB**, uz automatski prelazak na zreliji Nethermind FlatDB.

---

## 4. Analiza autoupdatea i notifikacija

- **Zašto autoupdate NIJE uključen:**
  U blockchain infrastrukturi automatska ažuriranja klijenata se ne koriste:
  1. *Zaštita od slashinga:* Nekontrolirani restart ili neusklađenost validator procesa može dovesti do trajnog gubitka uloga.
  2. *Breaking changes i zakrpe:* Verzije klijenata često mijenjaju CLI argumente ili uvode regresije (kao što je bio 1500% CPU thread-pool bug u 2.1.0).
  3. *Hard Fork rokovi:* Nadogradnje se planiraju tjednima ranije prema rasporedu hard forkova mreže.
- **Postupak nadogradnje:**
  Ostaje ručan, siguran i trenutan: promjena u `config/versions.env` + `sudo scripts/20-install.sh <klijent>` + `scripts/gnosisctl restart <klijent>`. Stara verzija se čuva pored nove, pa je rollback trenutan.
- **Notifikacije o stanju čvora:**
  Trenutno ne postoji asinkroni push alarm za ispad servisa ili pad diska. Preporučeno je u budućnosti dodati periodični cron/launchd skript koji u slučaju `gnosisctl health != 0` šalje lokalnu macOS notifikaciju (`display notification`) ili webhook prema Telegramu/Discordu.

---

## Vezani dokumenti

- [2026-10-22 — neovisna review analiza repozitorija, Git povijesti i stanja čvora (Gemini 4 Argon)](2026-10-22-review-analiza.md)
- [2026-10-10 — prva instalacija na i9: disk, sync, CPU](2026-10-10-prvo-pokretanje-i9-disk.md)
- [docs/05 — operacije i dnevnik](05-operations.md#dnevnik)
