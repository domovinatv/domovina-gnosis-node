# 12 — DOMOVINA lanac: vlastiti EVM L1 po uzoru na Gnosis

> **Status: prijedlog.** Odluka je [ADR-015](02-decisions.md#adr-015) (predloženo). Činjenice i izvori su u [istraživanju 2026-11-04](research/2026-11-04-domovina-chain.md). Ništa od ovoga još nije pokrenuto.

## Vizija

DOMOVINA je vlastiti EVM lanac koji je **tehnički identičan Gnosis Chainu**, ali kreće od nule:

- isti klijenti (Nethermind + Teku) i isti `gnosis` preset (slot 5 s);
- isti model native tokena kao xDAI, samo u eurima: **native xEUR**, pokriven EURe-om zaključanim na Gnosisu;
- kad Gnosis dobije novu verziju klijenata, ista se verzija ručno uvodi i na DOMOVINA lanac;
- prvi čvor je `acutis` (i9), a cilj je mreža operatera po županijama ([ADR-012](02-decisions.md#adr-012)).

## 1. Što se preuzima od Gnosisa

| Sloj | Gnosis | DOMOVINA |
|---|---|---|
| EL klijent | Nethermind, chainspec `genesis.json` | isti binarij, vlastiti chainspec |
| CL klijent | Teku, `PRESET_BASE: 'gnosis'`, `SECONDS_PER_SLOT: 5` | isti binarij, vlastiti `config.yaml` i `genesis.ssz` |
| Chain ID | 100 | vlastiti (§ 7) |
| Deposit ugovor | `0x0B98…45d9`, staking u GNO | vlastiti, u genesisu |
| Povijest | AuRa (xDai) → merge | **PoS od bloka 0**, svi forkovi na timestampu 0 |
| Gas token | xDAI, kuje ga bridge iz USDS-a na Ethereumu | xEUR, kuje ga bridge iz EURe-a na Gnosisu |
| Base fee | `eip1559FeeCollector`, ne spaljuje se | isto, **obavezno** (§ 2.3) |
| Explorer | Blockscout | Blockscout |

Konfiguracija lanca objavljuje se u zasebnom repou (npr. `domovina-chain/configs`) iste strukture kao `gnosischain/configs/mainnet`:

- `config.yaml`, `genesis.ssz`, `genesis.json` (chainspec);
- `bootnodes*.yaml`, `boot_enr.yaml`, `bootstrap_nodes*.txt`;
- `deposit_contract.txt`, `deposit_contract_block.txt`, `deposit_contract_block_hash.txt`.

Ovaj repo onda dobiva izbor mreže (npr. `NETWORK=gnosis|domovina`), a skripte ostaju iste. Klijente se ne forka.

## 2. Native xEUR: bridge `erc20_to_native`

### 2.1 Kako to radi Gnosis

xDAI nije ERC-20 nego saldo računa na razini protokola, kao ETH. Kuje ga samo klijent, kad mu to kaže Block Reward ugovor:

```
Ethereum                                   Gnosis Chain
1. relayTokens(USDS)  → USDS zaključan
   event UserRequestForAffirmation
                │
2. validatori (4/7) ─────────────────────► executeAffirmation() na Home bridgeu
                                            │
3.                                          Home bridge → Block Reward: „X dobiva N”
                                            │
4.                                          sljedeći blok: klijent dopiše N xDAI na X
```

Povratak ide obrnuto. xDAI poslan Home bridgeu se spali, validatori potpišu poruku, a ugovor na Ethereumu oslobodi USDS. Detalji su u [istraživanju § 3](research/2026-11-04-domovina-chain.md#3-kako-se-kuje-xdai-docsgnosischaincom-xdai-bridge-provjereno-2026-11-02).

„Kupiti xDAI za USDC” na Gnosisu je swap s nekim tko xDAI već ima. Novi xDAI nastaje samo zaključavanjem USDS-a na Ethereumu.

### 2.2 Preslikavanje na DOMOVINA lanac

```
Gnosis danas:   Ethereum ──USDS zaključan──► Gnosis    (xDAI native)
DOMOVINA:       Gnosis   ──EURe zaključan──► DOMOVINA  (xEUR native)
                "Foreign"                    "Home"
```

| Dio | Gnosis xDAI | DOMOVINA |
|---|---|---|
| Foreign ugovor | `XDaiForeignBridge` (Ethereum) | **generički** `ForeignBridgeErcToNative` na Gnosisu, token = EURe v2 `0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430` |
| Home ugovor | `HomeBridgeErcToNative` | isti |
| Kovanje | `BlockRewardBridge` + `blockRewardContractAddress` u chainspecu | isto |
| Validatori bridgea | oracle iz `gnosischain/tokenbridge`, 4/7 | isti softver, N-od-M operatera |
| Governance | Safe 8/15 | Safe multisig operatera |
| Nadzor | `monitor`, `alm` | isto |

**Ne koristi se `XDaiForeignBridge`.** On ima tvrdo zakucan DAI (`require(_erc20token == address(daiToken()))`), kamatni `CompoundConnector` i GSN. Generički `ForeignBridgeErcToNative` prima bilo koji ERC-20 i nema kamatnu logiku.

### 2.3 Invarijanta pokrića

```
ukupna xEUR zaliha na DOMOVINA lancu == EURe na Foreign bridgeu na Gnosisu
```

- Base fee ide na `eip1559FeeCollector` (blagajna lanca), a ne u spaljivanje. Spaljivanje ne bi ugrozilo pokriće. Ali EURe koji odgovara spaljenom xEUR-u ostao bi zauvijek zaključan na Gnosisu, bez ikoga tko ga može podići, a zaliha i pokriće bi se stalno razilazili. S fee collectorom taj novac ostaje u optjecaju kao prihod blagajne.
- Nagrade validatora dolaze kroz deposit ugovor u staking tokenu (§ 3), pa ne kuju xEUR.
- Monitor stalno uspoređuje dvije strane i alarmira na svako odstupanje.

### 2.4 Rezervni model: zaliha u genesisu (Vault)

Ako se na devnetu pokaže da Nethermind ne poziva Block Reward ugovor na lancu koji je PoS od bloka 0 (§ 8, pitanje 1), Home ugovor se mijenja tako da ne kuje nego isplaćuje iz zalihe:

- cijela xEUR zaliha (npr. 10⁹) je u genesisu na adresi Home ugovora;
- zaključavanje EURe-a na Gnosisu oslobađa xEUR iz zalihe, a povratak ga vraća u zalihu;
- ne treba nikakvo kovanje u klijentu, a ekonomski je isto.

### 2.5 Ime tokena

Native token **nije EURe**. EURe je Moneriumov brend i Moneriumova obveza, a xEUR je potraživanje prema DOMOVINA bridgeu. Radno ime je `xEUR`, po uzoru na xDAI ↔ DAI.

## 3. Staking token

Gnosis odvaja gas (xDAI) od stakinga (GNO u deposit ugovoru, nagrade se kuju u GNO). DOMOVINA zadržava to odvajanje:

- **A) vlastiti staking token** (radno ime DOM), u genesisu raspodijeljen operaterima čvorova. **Preporuka.**
- B) staking u xEUR. Traži izmijenjeni deposit ugovor i miješa pokriće eura s rizikom validatora. Ne preporučuje se.

## 4. Decentralizacija

- Finalnost traži da je online više od 2/3 stakea. Lanac na jednom stroju je jedna točka kvara i jedan operater s potpunom kontrolom.
- **Devnet:** sve na `acutis`, uz postojeći Gnosis čvor. Treba vlastiti root (npr. `/opt/domovina`), druge portove (P2P, Engine API, RPC, metrike) i zasebnog servisnog korisnika.
- **Testnet:** barem 4 čvora na barem 3 lokacije.
- **Mainnet:** operateri po županijama ([docs/11](11-imena-cvorova.md)). Svaki drži dio validatora i jedan ključ potpisnika bridgea.
- Validatorski ključevi DOMOVINA lanca potpuno su odvojeni od Gnosis ključeva, a vrijedi i isto pravilo protiv slashinga (nikad isti ključ na dva mjesta).

## 5. Ažuriranja klijenata

Novi Nethermind i Teku nose timestampove forkova samo za Gnosis i Chiado. Za DOMOVINA lanac timestamp forka se upisuje u vlastiti chainspec i `config.yaml`.

1. Izađe release s Gnosis forkom.
2. Nova verzija ide na DOMOVINA devnet i testnet, s forkom postavljenim tamo.
3. Čeka se da Gnosis mainnet prođe fork i bude stabilan nekoliko tjedana.
4. Fork na DOMOVINA mainnetu: novi `configs` release, zatim upgrade svih operatera prije timestampa.

**Glavni tehnički rizik:** dio Gnosis ponašanja u klijentima može biti vezan uz `chainId == 100`, a ne uz chainspec. Zato svaki upgrade ide prvo na devnet.

## 6. Faze

| Faza | Što | Kriterij izlaza |
|---|---|---|
| 0. Odluke | ADR-015 prihvaćen; staking token; chain ID; potpisnici; razgovor s Moneriumom i pravnikom | odgovori na § 8 pitanja 2–4 |
| 1. Devnet (`acutis`) | generiranje genesisa, Nethermind + Teku, jedan čvor sa svim validatorima, Block Reward + Home bridge | lanac finalizira; xEUR se kuje i spaljuje; fee collector prima base fee |
| 2. Testnet | 4+ čvorova; Blockscout; RPC kroz tunel ([ADR-011](02-decisions.md#adr-011)); Foreign bridge na Chiadu; oracle s 3+ validatora | 30 dana bez gubitka finalnosti; uvježban fork, ispad čvora i pauza bridgea |
| 3. Audit | konfiguracija i deployment bridgea, Block Reward, deposit ugovor, chainspec | svi nalazi zatvoreni |
| 4. Genesis ceremonija | operateri predaju deposit podatke; zajedno se generira `genesis.ssz`; potpisani checksumi; tag `v1.0.0` u `domovina-chain/configs` | svi čvorovi startaju na isti `MIN_GENESIS_TIME` |
| 5. Mainnet | bridge s niskim dnevnim limitom i capom koji raste postupno | — |

## 7. Preduvjeti

- **Chain ID.** `385` (pozivni broj Hrvatske) je zauzet („Lisinski”). Slobodni su bili npr. `3850`, `38500` i `385385` (2026-10-30). Prije odluke treba ponovno provjeriti, a zatim registrirati ID PR-om u `ethereum-lists/chains`.
- **Ljudi:**
  - operateri čvorova s pisanim obvezama (uptime, čuvanje ključeva, rok za upgrade prije forka);
  - potpisnici bridgea i governance multisiga s hardverskim novčanicima.
- **Infrastruktura:** bootnodes, Blockscout, javni RPC, monitor bridgea, alarmi.
- **Pravo:**
  - EURe je e-novac pod MiCA-om, a xEUR je potraživanje prema bridgeu. Prije javnog lansiranja treba provjera s pravnikom, HNB-om i HANFA-om.
  - Formulacija „suvereni hrvatski blockchain” ne smije sugerirati državno izdanje.
- **Monerium:**
  - može li zamrznuti adresu Foreign bridgea;
  - bi li izdavao EURe izravno na DOMOVINA lancu. Ako da, bridge ne treba.

## 8. Otvorena pitanja {#otvorena-pitanja}

1. **Poziva li Nethermind Block Reward ugovor na lancu koji je PoS od bloka 0** (`blockRewardContractTransition: 0` u AuRa paramsima, merge na genesisu)? Gnosis do kovanja dolazi preko AuRa povijesti. Prvi test na devnetu. Ako ne, primjenjuje se § 2.4.
2. Koji su chainspec ključevi za forkove poslije mergea (withdrawals contract, blobovi, Prague/Osaka)? Treba ih pročitati iz aktualnog Gnosis ili Chiado chainspeca i Nethermind koda.
3. Koja Gnosis ponašanja Nethermind i Teku vežu uz chain ID umjesto uz konfiguraciju?
4. Ima li EURe v2 funkcije za zamrzavanje ili blacklist, i kakav je stav Moneriuma prema bridgeu koji drži EURe?
5. Kojim alatom generirati `genesis.ssz` s `gnosis` presetom (npr. ethpandaops genesis generator)? Treba provjeriti podršku za `gnosis` preset.
6. Kako raspodijeliti staking token i koliko validatora treba po operateru?

## 9. Alternativa koja nije odabrana: L2 nad Gnosisom

Lanac se može pokrenuti i kao L2 (npr. OP Stack s EURe-om kao gas tokenom):

- prednosti: sigurnost se nasljeđuje od Gnosisa i bridge je ugrađen;
- mane: nije „identično kao Gnosis”, manje je suvereno i drugačije se ažurira.

Odbačeno u [ADR-015](02-decisions.md#adr-015) zbog cilja da DOMOVINA prati Gnosis jedan-na-jedan.
