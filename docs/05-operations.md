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

## Dnevnik

Ovdje kronološki upisivati događaje na čvoru: instalaciju, upgradeove, ispade i promjene konfiguracije.

| Datum | Događaj |
| --- | --- |
| 2026-10-01 | Repo prepisan od nule (Claude Code), čvor još nije instaliran |
| 2026-10-10 | Prvi `00-preflight.sh` na i9: sve OK osim diska (226 GB slobodno). Disk očišćen na 534 GB. Odluka: prva instalacija je namjerni test s ~500 GB diska i na Wi-Fi (428/424 Mbps), čišćenje po potrebi tijekom synca. [Detalji](2026-10-10-prvo-pokretanje-i9-disk.md) |
| 2026-10-10 | Verzije prije instalacije: Nethermind 2.0.0 → 2.1.0, Teku 26.9.1 → 26.10.0 (provjereno na i9). `config/node.env` iz primjera, preflight prolazi (warn: disk 533 GB, FileVault OFF). `10-host-setup.sh` prošao u 17:32. Zatečen `lowpowermode 1` na AC; skripta ga sada gasi. [Detalji](2026-10-10-prvo-pokretanje-i9-disk.md#host-setup-10-host-setupsh) |
| 2026-10-10 | `20-install.sh` u 17:54–17:55: Nethermind 2.1.0, JRE 25.0.4.1, Teku 26.10.0, SHA-256 u redu. gpg kao root zagadio `~/.gnupg`, ispravljeno u skripti. [Detalji](2026-10-10-prvo-pokretanje-i9-disk.md#instalacija-klijenata-20-installsh) |
