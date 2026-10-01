# Upute za AI agente (Claude Code, Antigravity, Codex…)

Ovaj repo je **single source of truth** za Domovina Gnosis čvor na MacBook Pro i9 (Intel). Prije svake promjene pročitaj [README](README.md) i [docs/02-decisions.md](docs/02-decisions.md).

## Pravila

1. **Činjenice se provjeravaju, ne pamte.** Verzije klijenata, imena release fajlova, CLI flagovi, fork epohe i adrese ugovora mijenjaju se svakih nekoliko mjeseci. Prije pisanja provjeri izvor:
   - GitHub API (`curl -s https://api.github.com/repos/<org>/<repo>/releases/latest`);
   - `--help` stvarnog binarija;
   - `gnosischain/configs`;
   - docs.gnosischain.com.

   Prva verzija ovog repoa je pala upravo na tome: zastarjele verzije, URL-ovi koji ne postoje, Lighthouse bez Intel builda.
2. **Verzije i checksumi žive samo u `config/versions.env`.** Ne ponavljaj ih u skriptama ni dokumentima, osim u tablicama koje izričito navode datum.
3. **Postavke čvora žive samo u `config/node.env.example`.** launchd plistovi se generiraju (`scripts/30-services.sh`) i ne commitaju se.
4. **Skripte su za bash 3.2** (macOS):
   - bez asocijativnih nizova, `${var,,}` i `mapfile`;
   - prazni nizovi pod `set -u` idu kao `${a[@]+"${a[@]}"}`.
5. **Ciljna arhitektura je x86_64.** Razvojni Mac može biti arm64. Za testiranje koristi `GNOSIS_TEST=1 GNOSIS_ROOT=<scratch> GNOSIS_CONFIG=<test.env>`: skripte tada ne traže root i ne rade chown.
6. **Odluka = ADR.** Nova ili promijenjena arhitekturna odluka ide u `docs/02-decisions.md`, s kontekstom i posljedicama.
7. **Tajne nikad u git:** JWT, `WEBHOOK_SECRET`, keystorei, lozinke, mnemonic, Access tokeni.
8. **Validator:** ništa što može pokrenuti iste ključeve na dva mjesta. Svaka promjena oko `40-validator.sh` ili servisa `validator` mora čuvati slashing-protection bazu.
9. Dokumentacija je na hrvatskom, a kod i komentari u kodu na engleskom.

## Provjera prije commita

```bash
bash -n scripts/*.sh scripts/gnosisctl
shellcheck scripts/*.sh scripts/gnosisctl           # ako je instaliran
node --check listener/listener.mjs
GNOSIS_TEST=1 GNOSIS_ROOT=/tmp/gn GNOSIS_CONFIG=config/node.env.example scripts/30-services.sh render /tmp/gn/plists
```

## Gdje je što

- `docs/research/`: sirovi istraživački nalazi s izvorima. Ne mijenjaju se; novo istraživanje ide u novi datirani fajl.
- `docs/05-operations.md` § Dnevnik: kronologija događaja na stvarnom čvoru.
