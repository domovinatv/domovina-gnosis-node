# 2026-10-01 — Prepisivanje repoa: što je provjereno, zamke, otvorene stavke

Prva verzija repoa (Antigravity / Gemini) je zamijenjena. Ovaj dokument bilježi ono što se ne vidi iz koda: što je stvarno testirano, koje su zamke koštale vremena i što se još mora provjeriti na i9.

## Zašto je prva verzija odbačena

Nijedan od ovih problema ne bi javio grešku pri pokretanju. Čvor bi se jednostavno zaglavio.

- **Verzije su bile zakucane na 2024.** Lighthouse v5.3.0 i Nethermind 1.30.0 su stariji od Pectre (2025-04-30) i Fusake (2026-04-14), pa stanu na prvom forku.
- **URL-ovi za download nisu postojali.** Nethermind zip se zove `nethermind-<ver>-<commit>-macos-x64.zip`. `latest/download/...` fallbackovi su vraćali 404.
- **Lighthouse nema Intel macOS build od v8.0.0.** Iz izvornog koda radi samo s `--features gnosis` ([ADR-003](02-decisions.md#adr-003)).
- **„Zero ingress” i „mobilni RPC ide na naš čvor” su se isključivali.** Rješenje je tunel ([ADR-005](02-decisions.md#adr-005)).
- **LaunchAgenti** ne rade bez logina. **FileVault** blokira automatski restart.
- **Listener** nije vidio native xDAI, nije radio backfill i imao je hardkodiran fallback secret.
- **Validator alat** (`validator-data-generator`) je iz 2022. i zna samo 0x01.
- **Povijest:** stari commit sadrži stvarnu statičku IP adresu ureda s lokacijom. Zato je čuvan **samo lokalno** na grani `antigravity-original` i ne smije se pushati.

## Što je stvarno testirano (na arm64 M4 Pro, test mod)

| Test | Rezultat |
| --- | --- |
| Teku 26.9.1 BN s točnim argumentima iz generiranog plista (Java pokrenuta izravno) | pokrenut, povukao checkpoint stanje s `checkpoint.gnosischain.com` |
| Teku VC iz plista | pokrenut; FATAL samo zbog nepostojećih ključeva (očekivano) |
| Nethermind 2.0.0 flagovi | provjereni protiv `--help` stvarnog x64 binarija (pod Rosettom) |
| `20-install.sh node listener`, `10-host-setup.sh` pod `/bin/bash` 3.2 | prolaze; SHA-256 provjera radi |
| Listener protiv `rpc.gnosischain.com` | detektira ERC-20 uplate; HMAC ispravan na test serveru; 503 pa retry, isti `id` |
| Listener: rotacija loga (mv + SIGHUP) | novi fajl preuzima pisanje |
| Svi plistovi | `plutil -lint` prolazi |

**Nije testirano:** ništa što traži root ili pravi launchd. To su `dscl` korisnik, `launchctl bootstrap`, pmset, BTM i Nethermind kao servis.

## Zamke otkrivene u ovoj sesiji

| Zamka | Posljedica | Gdje je riješeno |
| --- | --- | --- |
| `NumberOfFiles` u system daemonu postavlja i kernelske `kern.maxfiles`/`maxfilesperproc` | servisi s različitim vrijednostima prepisuju jedni druge | ista vrijednost (524288) za sve, `30-services.sh` |
| `tar` pokrenut kao root čuva numeričke vlasnike iz arhive | binariji bi pripali nasumičnom UID-u (možda 501 = admin) | `--no-same-owner` + `chown root:wheel` u `activate_version` |
| `launchctl bootstrap` odmah nakon `bootout` | `5: Input/output error` | retry petlja u `30-services.sh install` |
| `node --env-file` **ne prepisuje** varijable koje je već postavio launchd | RPC URL u `listener.env` ne bi imao učinka | uklonjeno iz primjera, dolazi iz plista |
| Teku launcher je shell skripta | BTM na macOS 26 može tiho blokirati daemon koji je skripta | plist pokreće `java` izravno; JVM opcije se čitaju iz launchera |
| Nethermind `JsonRpc.WebSocketsPort` je po defaultu **isti** kao HTTP (8545) | WS i HTTP na istom portu, a listener očekuje 8546 | eksplicitno 8546 |
| Nethermind 2.0 flat DB: snap sync se ne nastavlja nakon restarta | prekid prve sinkronizacije baca sate rada | `NM_FLATDB=false` ([ADR-002](02-decisions.md#adr-002)) |
| `Metrics.ExposeHost` default je `+` (sva sučelja) | metrics bi se izložili na LAN | metrics za Nethermind nisu uključeni |
| Homebrew 7.0: Intel je tier 3, nema bottlea | `brew install` kompajlira iz izvornog koda | sve komponente su službeni binariji iz `versions.env` |
| Prvo pokretanje x64 Node-a pod Rosettom je sporo (> 10 s) | lažni neuspjeh testa | samo na razvojnom Macu; na i9 nema Rosette |

## Otvorene stavke (na i9)

- [ ] **Background Task Management:** nakon pravog restarta svi daemoni su `running` (`gnosisctl status`, `sudo sfltool dumpbtm`).
- [ ] **Nethermind piše pored binarija?** Install dir je u vlasništvu roota. Ako se servis ruši s `Permission denied`, iz loga uzeti putanju i preusmjeriti je flagom u `data/`.
- [ ] **NLog naziv log fajla** u `logs/nethermind/`. `gnosisctl logs` pretpostavlja `*.txt`.
- [ ] **Stvarno trajanje sinkronizacije i zauzeće diska** upisati u Dnevnik u `docs/05`.
- [ ] **`pmset -g cap`:** postoji li `autorestartatconnect` na MBP 2019 s macOS-om 26.
- [ ] **Poštuje li Tahoe `defaults` ključeve za automatske updateove.** Svejedno ih isključiti i u GUI-ju.
- [ ] **FileVault odluka** zapisana kao ADR.
- [ ] Peer count bez port forwardinga je dovoljan (EL ≥ 10, CL stabilan).
- [ ] Kasnije: oba Cloudflare Workera (RPC proxy, notify), ugovor je u `docs/06` i `docs/07`. Uz to watchlista iz Workera i `trace_block` za internal xDAI transfere.

## Vezani dokumenti

- [docs/04-install-runbook.md](04-install-runbook.md): postupak na i9
- [docs/02-decisions.md](02-decisions.md): ADR-001 do ADR-008
- [docs/research/](research/): sirovi nalazi s izvorima
