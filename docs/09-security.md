# 09 — Sigurnost i model prijetnji

## Što štitimo

| Imovina | Gdje je | Ako procuri |
| --- | --- | --- |
| Validator mnemonic | papir ili metal, offline | napadač može potpisivati (namjerni slashing) i napraviti izlaz; ulog ne može preusmjeriti jer je withdrawal adresa fiksirana u 0x02 credentials. Uz napadačevu withdrawal adresu bio bi to potpuni gubitak, zato se adresa triput provjerava |
| Validator keystore + lozinka | `/opt/gnosis/validator`, `_gnosis` 600 | napadač može potpisivati, odnosno namjerno izazvati slashing. Ulog ne može ukrasti, jer withdrawal adresa je fiksna |
| `WEBHOOK_SECRET` | `/opt/gnosis/etc/listener.env` + Worker | lažne push notifikacije korisnicima („primili ste 1000 xDAI”). **Ozbiljno**: phishing vektor |
| Access service token | Worker secret | izravan pristup RPC originu mimo rate limita |
| Engine JWT | `/opt/gnosis/secrets/jwt.hex` | samo lokalno (127.0.0.1); vrijednost je mala |
| Korisničke adrese (watchlista) | `etc/watchlist.json`, Worker D1 | veza korisnik ↔ adresa, odnosno gubitak privatnosti |

## Površine napada

- **Mreža.**
  - Dolazno su otvoreni samo P2P portovi (30313, 9010, 9001), [ADR-009](02-decisions.md#adr-009). RPC, Engine API i REST nisu dostupni izvana. Firewall je uključen.
  - Sve lokalne usluge su na 127.0.0.1.
  - P2P je javan po definiciji: napadač može otkriti da na IP-u ureda radi Gnosis čvor.
- **RPC preko tunela.**
  - Worker propušta samo dopuštene metode i ima rate limit.
  - Origin je iza Accessa.
  - Nethermind ionako nema admin i debug module.
- **Lokalni korisnik.**
  - Servisi rade kao `_gnosis`, a binariji su root vlasništvo.
  - Kompromitirani admin korisnik sa sudo i dalje može sve. Mac zato ne služi i za svakodnevni rad (browser, mail).
- **Supply chain.** Svaka komponenta ima zakucan SHA-256 ([ADR-007](02-decisions.md#adr-007)), a Nethermind i GPG potpis. Checksumi se mijenjaju samo nakon čitanja release notesa.

## P2P privatnost: ispravljene tvrdnje

Antigravityjev nacrt je tvrdio da „čvor koji nije validator ne otkriva ništa” i da geolokacija IP-a „štiti lokaciju”. Ispravno je ovo:

- **Full node bez validatora:** iz P2P prometa se ne može povezati s korisnicima novčanika. Upiti novčanika ne idu u P2P mrežu, nego kroz Worker do našeg RPC-a.
- **S validatorom:**
  - napadač s mnogo peerova može statistički povezati IP ureda s indeksom validatora, preko vremena prvog pojavljivanja atestacija;
  - posljedica je moguć ciljani DoS na IP ureda u trenutku predlaganja bloka;
  - to nije krađa ni slashing;
  - mjera: ne objavljivati koji je validator naš.
- **Geolokacija IP-a** je gruba, na razini grada ili telekomovog čvora. Ali **ISP zna točnog korisnika IP-a**, pa sudski nalog ili curenje kod ISP-a otkriva lokaciju. Lokacija se zato ne smatra tajnom.
- **Transakcije poslane kroz naš čvor** (`eth_sendRawTransaction`) ulaze u P2P mrežu s našeg IP-a. Promatrač može zaključiti da su prvo viđene kod nas. Za novčanik s mnogo korisnika to otkriva „Domovina čvor”, a ne pojedinca.

## Što vidi Cloudflare

Sav promet novčanika prema RPC-u i sve notifikacije prolaze kroz Cloudflare. To je kompromis prihvaćen u [ADR-005](02-decisions.md#adr-005). Dobivamo vlastiti čvor, vlastita pravila i nema profiliranja po API ključevima pružatelja usluge, ali imamo jednog posrednika. Ako se to promijeni, alternativa je vlastiti VPS kao reverse proxy preko WireGuarda. Tada radimo svoj DDoS zaštitni sloj.

## Kontrolna lista

- [ ] FileVault odluka zapisana ([docs/03](03-macbook-host.md#filevault))
- [ ] Mac ne služi za svakodnevni rad; admin lozinka je jaka; uključen je auto-lock ekrana
- [ ] `WEBHOOK_SECRET` je generiran s `openssl rand -hex 32` i nije u gitu
- [ ] Mnemonic je na papiru, na dva mjesta, i nikad nije bio na mrežnom računalu
- [ ] Withdrawal adresa je hardverski novčanik ili Safe
- [ ] Release notifikacije su uključene za Nethermind i Teku
