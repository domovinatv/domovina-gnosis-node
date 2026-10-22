# 05 — Operacije

## gnosisctl

| Naredba | Što radi |
| --- | --- |
| `gnosisctl status` | launchd stanje, PID i zadnji exit code svakog instaliranog servisa |
| `gnosisctl health` | EL sync, starost head bloka, peeri, CL sync distance, validator greške, listener zaostatak, disk, sat, struja. Exit 1 ako nešto ne valja. |
| `gnosisctl logs <servis>` | `tail -F` glavnog loga servisa |
| `gnosisctl stop all` | gasi redom validator, listener, CL, EL i čeka čisto gašenje |
| `gnosisctl start all` | pali redom EL, CL, validator, listener |
| `gnosisctl restart <servis>` | `launchctl kickstart -k` |

Gdje su logovi:

| Servis | Log | Rotacija |
| --- | --- | --- |
| nethermind | `/opt/gnosis/logs/nethermind/*.txt` | NLog, 32 MB × 10 |
| teku | `/opt/gnosis/logs/teku/teku.log` | log4j |
| validator | `/opt/gnosis/logs/validator/validator.log` | log4j |
| listener | `/opt/gnosis/logs/listener.log` | newsyslog, 20 MB × 10 (SIGHUP) |
| svi | `/opt/gnosis/logs/<servis>.stderr.log` | samo greške pri startu; ručno |

## Upgrade klijenta

1. Ovdje, ne na čvoru: u `config/versions.env` promijeni verziju i SHA-256, zatim commit i push.
   - Checksum se uzima iz release assets na GitHubu, ili sa `shasum -a 256` nad preuzetim fajlom.
   - Release notes se čitaju **prije** upgradea, posebno sekcija „breaking changes” i config ključevi.
2. Na čvoru:
   ```bash
   cd ~/domovina-gnosis-node && git pull
   sudo scripts/20-install.sh teku              # instalira pored stare verzije, prebaci current
   sudo scripts/30-services.sh install teku     # regenerira plist (Teku JVM opcije se čitaju iz nove verzije)
   scripts/gnosisctl health
   ```
   Za Nethermind je dovoljno `20-install.sh nethermind`, pa zatim `gnosisctl restart nethermind`. Plist ostaje isti, osim ako su se mijenjali flagovi.
3. Rollback:
   ```bash
   sudo ln -sfn <stara-verzija> /opt/gnosis/<komponenta>/current
   scripts/gnosisctl restart <servis>
   ```

**Validator:** svaki restart VC-a znači oko 3 epohe (otprilike 4 min) šutnje zbog doppelganger zaštite. To je namjerno. Upgradeovi se ne rade u nizu bez razloga.

## Hard forkovi {#hard-forkovi}

Klijent koji nije nadograđen prije fork epohe prestaje pratiti lanac, i RPC tada vraća staro stanje.

- Najave: [Gnosis forum](https://forum.gnosis.io/), [blog.validategnosis.com](https://blog.validategnosis.com/) i [gnosischain/configs](https://github.com/gnosischain/configs) (`*_FORK_EPOCH`).
- Nadograditi barem **tjedan dana prije** forka.
- Stanje 2026-10-10: zadnji fork je Fulu (2026-04-14), a sljedeći nije zakazan.

Koliko je verzija iznad minimuma za Fusaku (stanje 2026-10-10):

| Klijent | Minimum za Fusaku | Zakucano ovdje |
| --- | --- | --- |
| Nethermind | 1.36.2 | 2.1.0 |
| Teku | 26.4.0 | 26.10.0 |

✋ Pretplatiti se na GitHub release notifikacije za `NethermindEth/nethermind` i `Consensys/teku` (Watch → Custom → Releases).

## Planirani restart (macOS update) {#planirani-restart}

```bash
scripts/gnosisctl stop all
softwareupdate -l                       # što ima
sudo softwareupdate -ia                 # ili kroz System Settings
sudo fdesetup authrestart               # s FileVaultom; inače sudo shutdown -r now
# nakon boota:
scripts/gnosisctl status && scripts/gnosisctl health
```

Zašto prvo `stop all`: launchd pri gašenju sustava ne mora poštovati `ExitTimeOut` od 180 s, a Nethermind treba vremena za flush baze.

## Backup

| Što | Backup? | Kako |
| --- | --- | --- |
| Blockchain baze (`data/nethermind`, `data/teku`) | **ne** | uvijek se mogu ponovno sinkronizirati |
| `secrets/jwt.hex` | ne | `10-host-setup.sh` generira novi |
| `config/node.env` | da | kratak fajl; kopija u password manager ili u privatni repo |
| `etc/listener.env` (`WEBHOOK_SECRET`) | da | isti secret je u Workeru; password manager |
| Validator mnemonic | **da, offline** | papir ili metal, nikad digitalno ([docs/08](08-validator.md)) |
| Validator keystore + lozinka | da | mogu se regenerirati iz mnemonica; kopija lozinke u password manager |
| Slashing protection DB | **da, pri svakoj selidbi** | `40-validator.sh slashing-export` dok VC stoji |

## Troubleshooting

| Simptom | Uzrok / rješenje |
| --- | --- |
| Servis `not loaded` nakon restarta Maca | BTM blokirao ([docs/03](03-macbook-host.md#background-task-management)); `sudo sfltool dumpbtm` |
| Servis se vrti u krug (novi PID svakih 30 s) | `logs/<servis>.stderr.log`; najčešće dozvole u `/opt/gnosis/data` ili zauzet port |
| Nethermind: `Permission denied` u svom direktoriju | pokušava pisati pored binarija (root vlasnik); javi putanju, pa se doda flag koji je preusmjerava u `data/` |
| Teku: `el_offline` / „execution client offline” | Nethermind ne radi ili se JWT razlikuje; obje strane čitaju isti `secrets/jwt.hex` |
| Teku stalno `is_optimistic` | EL se još sinkronizira; normalno u prvim satima |
| Head star > 30 s, a EL kaže da nije u syncu | malo peera; provjeri mrežu, `gnosisctl health` peere i sat |
| `checksum mismatch` u 20-install | pogrešan checksum u `versions.env` ili pokvaren download; nikad ne preskakati |
| Disk se puni | `du -sh /opt/gnosis/data/*`; nakon toga Nethermind full pruning ([docs](https://docs.nethermind.io/fundamentals/pruning)), samo na trie backendu |
| Sat odstupa > 100 ms | `sntp time.cloudflare.com`; razmisliti o chronyju |

## Dijagnostika Netherminda (.NET) {#dijagnostika}

Kad Nethermind troši CPU, a ne vidi se zašto, `sudo sample <pid>` pokazuje samo nativne funkcije. JIT-kompilirani kod vidi kao `???`. Imena metoda daju .NET alati:

```bash
sudo scripts/20-install.sh diagtools   # jednom: .NET runtime + dotnet-stack/dotnet-trace u /opt/gnosis/tools
scripts/gnosisctl dotnet-stack         # managed stog svih niti, sa imenima metoda
scripts/gnosisctl dotnet-trace 30      # CPU trace 30 s → /tmp/nethermind-trace-*.speedscope.json
```

- Trace se otvara na <https://www.speedscope.app> (fajl se učitava lokalno u browser, ništa se ne šalje).
- Alati se spajaju preko socketa u temp diru korisnika `_gnosis`, pa ih `gnosisctl` pokreće kao `_gnosis` (`sudo -u`).
- Za `sample` koristiti `pgrep -x nethermind`, nikad `pgrep -f …nethermind…`. `-f` pogađa i druge procese čija naredba sadrži taj tekst, a `sample` onda drugi PID shvati kao trajanje.
- Nethermind je release build. Debug build iz izvornog koda mijenja tajming i ne pokazuje isti problem.

## Poznati problemi {#poznati-problemi}

Pogođeni pri prvoj instalaciji na i9 (Nethermind 2.1.0, Teku 26.10.0, macOS 26). Gdje piše „ispravljeno”, skripte to već rade. [Dnevnik](2026-10-10-prvo-pokretanje-i9-disk.md) ima mjerenja i dokaze.

| Simptom | Uzrok | Stanje |
| --- | --- | --- |
| Nethermind se ruši, `last exit 159`, stderr: `DOTNET_BUNDLE_EXTRACT_BASE_DIR is not set` | .NET single-file bundle se raspakira u `$HOME`, a `_gnosis` ima `/var/empty` | ispravljeno: plist postavlja `HOME` i `DOTNET_BUNDLE_EXTRACT_BASE_DIR` u `state/nethermind` |
| Nakon synca Nethermind ~1.500 % CPU, 60 % sys, `sample` pokazuje `swtch_pri`/`SpinWait` | idle .NET thread-pool niti se vrte prije spavanja (Nethermind PR #14162, nije u 2.1.0) | zaobiđeno: `DOTNET_ThreadPool_UnfairSemaphoreSpinLimit=0`; ukloniti nakon upgradea |
| I dalje ~460 % CPU, `dotnet-trace` pokazuje `PeerManager` + thread pool + finalizer | PeerManager u petlji bira kandidate koje odbije filtar nedavnih IP-ova, kad je malo peerova (PR #14190, nije u 2.1.0) | zaobiđeno: `--Network.FilterPeersByRecentIp false` (Nethermind pao na ~16 % CPU, EL peerova 8 → 12); ukloniti nakon upgradea |
| Pomični prozor povijesti čuva dvostruko dulje nego što je zadano | Nethermind 2.1.0 računa `History.RetentionEpochs` kao 32 bloka, a Gnosis ima 16 slotova po epohi | ispravljeno: 198.180 = 367 dana (32 × 5 s po „epohi”) |
| Cijela povijest ne stane na 1 TB disk | default Gnosis barrier je 2022: ~260 GB bodies + ~220 GB receipts | ADR-010: povijest samo za zadnju godinu |
| Nakon restarta Nethermind ~5 min ništa ne piše u log | otvaranje RocksDB baze od ~300 GB | normalno, pričekati |
| `eth_getTransactionByHash` vraća `null` za blok koji ima tijelo | indeks hash → blok nastaje s receiptsima | normalno dok Old Receipts ne dođu do tog bloka |
| Prvi minuti receiptsa pokazuju ~58 KB/blok | RocksDB piše nesažeto | nakon kompakcije ~15 KB/blok; o disku ne zaključivati iz prvih minuta |
| `sudo sample $(pgrep -f …nethermind…)` traje satima | `pgrep -f` pogodi i druge procese, pa `sample` drugi PID uzme kao trajanje | koristiti `pgrep -x nethermind` |
| `sudo 20-install.sh` ostavi root fajlove u `~/.gnupg` i root `dirmngr` | `sudo` na macOS-u zadržava `HOME` | ispravljeno: gpg se pokreće kao `$SUDO_USER` |
| `lowpowermode 1` i na struji | macOS postavka | ispravljeno: `10-host-setup.sh` ga gasi |
| Samo 4–8 EL peerova | nema dolaznih veza (router) | radi, ali sporije; port forward po [ADR-009](02-decisions.md#adr-009) |

## Dnevnik

Ovdje kronološki upisivati događaje na čvoru: instalaciju, upgradeove, ispade i promjene konfiguracije.

| Datum | Događaj |
| --- | --- |
| 2026-10-01 | Repo prepisan od nule (Claude Code), čvor još nije instaliran |
| 2026-10-10 | Prvi `00-preflight.sh` na i9: sve OK osim diska (226 GB slobodno). Disk očišćen na 534 GB. Odluka: prva instalacija je namjerni test s ~500 GB diska i na Wi-Fi (428/424 Mbps), čišćenje po potrebi tijekom synca. [Detalji](2026-10-10-prvo-pokretanje-i9-disk.md) |
| 2026-10-10 | Verzije prije instalacije: Nethermind 2.0.0 → 2.1.0, Teku 26.9.1 → 26.10.0 (provjereno na i9). `config/node.env` iz primjera, preflight prolazi (warn: disk 533 GB, FileVault OFF). `10-host-setup.sh` prošao u 17:32. Zatečen `lowpowermode 1` na AC; skripta ga sada gasi. [Detalji](2026-10-10-prvo-pokretanje-i9-disk.md#host-setup-10-host-setupsh) |
| 2026-10-10 | `20-install.sh` u 17:54–17:55: Nethermind 2.1.0, JRE 25.0.4.1, Teku 26.10.0, SHA-256 u redu. gpg kao root zagadio `~/.gnupg`, ispravljeno u skripti. [Detalji](2026-10-10-prvo-pokretanje-i9-disk.md#instalacija-klijenata-20-installsh) |
| 2026-10-10 | `30-services.sh install` u 18:08. Teku odmah radi (checkpoint). Nethermind exit 159 (.NET bundle bez pisivog HOME), ispravljeno; radi od 18:11:52, sync krenuo u 18:12:48. EL samo 4 peera nakon 30 min. [Detalji](2026-10-10-prvo-pokretanje-i9-disk.md#sinkronizacija-prvi-sat) |
| 2026-10-10 | 22:25: stanje sinkronizirano za 4 h 13 min (snap, 4–8 EL peerova, Wi-Fi, bez port forwarda). Čvor prati vrh lanca, Teku nije optimistic. Baza ~166 GB. Povijest (bodies/receipts) u tijeku. [Detalji](2026-10-10-prvo-pokretanje-i9-disk.md#sinkronizacija-stanje-gotovo-4-h-13-min) |
| 2026-10-10 | 23:27: restart Nethermind s granicom povijesti 42.550.000 ([ADR-010](02-decisions.md#adr-010)). Start nakon restarta traje ~4,5 min (otvaranje baze). Old Receipts samo za zadnju godinu, procjena ~90 GB. [Detalji](2026-10-10-prvo-pokretanje-i9-disk.md#restart-s-adr-010-2327) |
| 2026-10-11 | 00:27:33: **sync gotov** (ukupno 6 h 15 min). Baza 304 GB, slobodno 227 GiB. Mreža i disk u mirovanju niski, ali Nethermind i dalje ~1.500 % CPU (60 % sys), uzrok otvoren. [Detalji](2026-10-10-prvo-pokretanje-i9-disk.md#sync-gotov-2026-10-11-002733) |
| 2026-10-11 | 01:02 i 01:35: restarti. Nethermind CPU s ~1.500 % na ~530 % uz `DOTNET_ThreadPool_UnfairSemaphoreSpinLimit=0` (thread-pool spin, PR #14162). Ostatak je lock contention u 37 thread-pool niti, uzrok otvoren. Pomični prozor: `RetentionEpochs` se računa po 32 bloka, ispravno 198.180 = 367 dana. Pruner obrisao 4.180.854 blokova (do #42.350.605). Dodani `diagtools` (`gnosisctl dotnet-stack|dotnet-trace`). |
| 2026-10-11 | 01:54: restart s `--Network.FilterPeersByRecentIp false` (PeerManager petlja, Nethermind PR #14190, nađeno s `dotnet-trace`). Nethermind ~16 % CPU, sustav 95 % idle, 12 EL peerova. Čvor sinkroniziran i u mirovanju. [Detalji](2026-10-10-prvo-pokretanje-i9-disk.md#ostatak-cpu-a-peermanager-petlja-dotnet-stack-dotnet-trace) |
| 2026-10-11 | 12:46: provjera nakon ~11 h rada. Sinkroniziran, 46 EL / 46 CL peerova. Od 02:00 nijedan preskočen slot u Teku logu i nijedan WARN/ERROR u Nethermindu. Rupe u 01:02, 01:35 i 01:54 su planirani restarti. CL peerovi rastu postupno: 30 u ponoć, ~50 od 05 h. Slobodno 222 GB. Mac ide na Wi-Fi (`en0`), a USB Ethernet (AX88179B) je u redoslijedu servisa iza dva mobitela (tethering), treba ga staviti na vrh. |
| 2026-10-12 | 19:13: provjera nakon ~43 h bez restarta (isti PID-ovi). Nethermind od 10-11 12:40 bez rupa > 30 s u obradi blokova i bez WARN/ERROR. Teku 38–54 peera, 21 × „Late Block Import” (bezopasno). Slobodno 220 GB. Teku log se rotira u ponoć i čuva samo tekući dan, zato je za starija razdoblja izvor Nethermind log. |
| 2026-10-13 | 09:14: mjerenje. Nethermind 55 h, Teku 63 h bez restarta. Head 1 s star, 49 EL / 48 CL peerova, bez rupa i bez WARN/ERROR od 10-12 19:00. CPU prosjek od starta: Nethermind ~46 %, Teku ~22 % jedne jezgre. Sustav ~77 % idle. RSS: Nethermind 4,0 GB, Teku 8,9 GB. Disk: baza Nethermind 303 GB, Teku 6,7 GB, slobodno 218 GB (−4 GB od 10-11, ~2 GB/dan). **Mreža je veća od očekivanog:** `en0` od 10-11 12:46 primio 421 GB i poslao 175 GB (prosjek ~21 Mbit/s dolje, ~9 Mbit/s gore, ~230 GB/dan dolje). U uzorku od 30 s: ~31 Mbit/s dolje i ~12,5 Mbit/s gore, gotovo sve Nethermind (`nettop`). Teku troši samo ~0,5 Mbit/s. Vjerojatno tx gossip, koji raste s brojem EL peerova (12 → 49). Za sada ništa ne mijenjamo, promatramo. Ako zatreba, rješenje je smanjiti `--Network.MaxActivePeers`. |
| 2026-10-14 | 13:37: provjera. Nethermind 3 d 12 h, Teku 3 d 19 h bez restarta. Mac radi 4 dana. Head 4 s star, 48 EL / 61 CL peerova. Od 10-13 09:00 nema rupa u blokovima ni WARN/ERROR u Nethermindu. Teku danas nije preskočio nijedan slot: 6 × „Late Block Import” i 1 × fork choice 281 ms (bezopasno). Od 10-13 09:14 (28,4 h): Nethermind ~50 %, Teku ~19 % jedne jezgre, sustav ~88 % idle. Baza Nethermind 303 → 305 GB, slobodno 216 GB. Mreža `en0`: 302 GB primljeno, 130 GB poslano, prosjek ~24 Mbit/s dolje i ~10 Mbit/s gore (~255 GB/dan dolje, ~110 GB/dan gore). Promet stabilan, bez rasta. |
| 2026-10-22 | 08:54: provjera i neovisna review analiza (Gemini 4 Argon). Nethermind 11 d 7 h (PID 3951), Teku 11 d 14 h (PID 18876) bez ijednog restarta. Head 0 s star (#48.880.396), 48 EL / 37 CL peerova, clock offset +58 ms. RSS: Nethermind 7,1 GiB, Teku 9,1 GiB. Disk: `state` 148 GB (+2 GB u 11 dana, ~5,5 GB/mj.), `blocks` 99 GB, `receipts` 41 GB, `headers` 16 GB, Teku 7,1 GB, slobodno 208 GiB. Upstream: izašli Nethermind 2.2.0 (sadrži PR #14190, ali NE i #14162 koji je zatvoren) i Teku 26.10.1 (repo preimenovan u `Consensys-Incorporated/teku`). [Cijela review analiza](2026-10-22-review-analiza.md) |
| 2026-10-22 | 09:00: detaljna provjera stabilnosti nakon 11,5 dana neprekidnog rada bez restarta (isti procesi od 10-11: Nethermind PID 3951, Teku PID 18876). Uptime hosta 11 d 3 h. Prosječni CPU od starta: Nethermind ~58 % jedne jezgre, Teku ~24 %, sustav stalno >80 % idle. RSS: Nethermind 7,55 GB (unutar 8 GB cache budžeta), Teku 9,5 GB, swap samo 6,5 MB. Disk: Nethermind 311 GB (+7 GB u 11,5 dana, rast ~0,6 GB/dan), Teku 7,1 GB, slobodno 209 GiB (~224 GB). Dokazan rad pomičnog prozora od 367 dana (ADR-010): `History.HistoryPruner` u pozadini briše blokove i receipts starije od 367 dana (do #42.538.xxx, točno `head − 198.180 × 32`), svaki prolaz traje ~2 ms. U svim rotiranim Nethermind logovima 0 grešaka; Teku ima samo 2 bezopasna timeouta zbog kašnjenja bloka na mreži. Analizirana dugoročna strategija (resync nakon ~1 god kad disk padne ispod 100 GB) te zašto je autoupdate namjerno isključen. |
| 2026-10-22 | 11:13–15:22: **port forwarding na oba routera** (dvostruki NAT Zyxel → TP-Link → i9, [docs/10](10-network.md)). UDP 30303/9000 na TP-Linku javljaju konflikt (skrivena UPnP mapiranja), pa su P2P portovi premješteni na 30313 (Nethermind) i 9010 (Teku), QUIC 9001 ostaje ([ADR-009, dopuna](02-decisions.md#adr-009)). Prije: 48 EL / 35 CL peerova, 0 dolaznih. Nethermind restart u 12:23, sinkroniziran u 12:27, enode `89.201.137.96:30313`. Teku na 9010 je objavio NAT-om prepisan `udp/23756`, pa je dodan `P2P_ADVERTISED_IP` (restart 12:46, ENR ispravan `udp/9010`). Nakon dva restarta Teku je imao 4–5 peerova i zapeo na DATA_NOT_AVAILABLE od 12:39 do 13:05:18 (~26 min, head zastario). Zatim se oporavio bez intervencije: 10 peerova u 13:10, 49 u 14:00, 78–80 od 14:20. U 15:22: 47 EL / 78 CL peerova, **61 dolazni**, sync distance 0, head 3 s star. |
| 2026-10-22 | 19:15: provjera ~7 h nakon port forwarda. `gnosisctl health` zelen: head 0 s, 49 EL / 80 CL peerova. CPU prosjek od restarta isti kao prije forwarda: Nethermind ~57 % jedne jezgre (235 min CPU / 6 h 52 min), Teku ~24 %, sustav ~90 % idle, load 2,3–2,5. RSS: Nethermind 3,2 GB (puni se natrag nakon restarta u 12:23), Teku 9,7 GB, swap 8,75 MB. Slobodno 214 GiB; Nethermind 306 GiB, Teku 6,6 GiB. Nethermind 0 ERROR; Teku 35 ERROR, od toga 33 u 12:23–12:27 (Nethermind restart, Engine API nedostupan), 2 izolirana (00:58, 05:46). Uzorak prometa 30 s: ~2,4 Mbit/s dolje, ~2,3 gore (premalo za zaključak; mjerenje 24 h otvoreno). |
| 2026-10-22 | 20:13: **RPC tunel, prvi dio** ([ADR-011](02-decisions.md#adr-011)). `cloudflared` 2026.10.3 instaliran u `/opt/gnosis/cloudflared`. `tunnel login` (zona `mpt.hr`), tunel `acutis` (`f751f6fe-8a00-4895-a2d4-79e175a90b6d`), CNAME `acutis-rpc.mpt.hr` i `acutis-ws.mpt.hr`. Lokalni `config/node.env` ima `TUNNEL_*`. Servis **nije pokrenut** dok Cloudflare Access ne bude postavljen ([predaja](2026-10-22-predaja-acutis-tunel.md)). Na računu postoji i stari neaktivni tunel `macbook-i9-64GB` (2026-06-30), nediran. Ime čvora `acutis` ([ADR-012](02-decisions.md#adr-012), [docs/11](11-imena-cvorova.md)). |
| 2026-10-22 | 22:14: **Cloudflare Access za tunel `acutis`** (račun D.O.M., [ADR-011](02-decisions.md#adr-011)). Service token `eure-reader` i self-hosted aplikacija `acutis-rpc` s hostnameovima `acutis-rpc.mpt.hr` i `acutis-ws.mpt.hr`, jedna politika `workers` (Service Auth, Include Service Token `eure-reader`), bez politike za ljude. Provjera izvana prije pokretanja tunela: bez tokena oba hostnamea **403**; s tokenom **530 / error 1033** (Access propušta, tunel još nema veza). Sljedeće: korak 2 predaje na i9 ([predaja](2026-10-22-predaja-acutis-tunel.md)). |
| 2026-10-22 | 22:28: **tunel `acutis` pokrenut** (servis `tv.domovina.gnosis.tunnel`, [predaja](2026-10-22-predaja-acutis-tunel.md)). 4 veze tunela (vie05, lju01 ×2, vie06), QUIC. Izvana bez tokena: `acutis-rpc` i `acutis-ws` **403**. Ingress: nepoznati hostname → 404. Lokalno je `admin_peers` odbijen (namespace Admin isključen). Credentials su u `/opt/gnosis/secrets/cloudflared/`. Obrisani su stari tunel `macbook-i9-64GB` i `~ms/.cloudflared/cert.pem`. Testovi s tokenom (chain id, WS) čekaju Mac Mini. |
