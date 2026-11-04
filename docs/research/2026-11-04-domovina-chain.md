# Istraživanje: vlastiti EVM lanac po uzoru na Gnosis, xDAI bridge (2026-10-30 – 2026-11-02)

> Sirovi nalazi provjereni na primarnim izvorima: `gnosischain/configs`, GitHub API, izvorni kod `gnosischain/tokenbridge-contracts`, docs.gnosischain.com, chainid.network. Plan koji iz njih slijedi je u [docs/12](../12-domovina-chain.md), odluka u [ADR-015](../02-decisions.md#adr-015).

## 1. Gnosis konfiguracija (`gnosischain/configs/mainnet`, provjereno 2026-10-30)

Fajlovi u direktoriju `mainnet/`: `boot_enr.yaml`, `bootnodes.yaml`, `bootnodes_execution.yaml`, `bootstrap_nodes.txt`, `bootstrap_nodes_execution.txt`, `config.yaml`, `deposit_contract.txt`, `deposit_contract_block.txt`, `deposit_contract_block_hash.txt`, `genesis.json`, `genesis.ssz`.

`config.yaml` (CL):

| Ključ | Vrijednost |
|---|---|
| `PRESET_BASE` | `'gnosis'` |
| `SECONDS_PER_SLOT` | `5` |
| `MIN_GENESIS_ACTIVE_VALIDATOR_COUNT` | `4096` |
| `MIN_GENESIS_TIME` | `1638968400` |
| `DEPOSIT_CHAIN_ID` | `100` |
| `DEPOSIT_CONTRACT_ADDRESS` | `0x0B98057eA310F4d31F2a452B414647007d1645d9` |

`genesis.json` je Nethermind/OpenEthereum chainspec (ključevi `name`, `engine`, `params`, `genesis`, `nodes`, `accounts`), a ne geth genesis.

- `engine.authorityRound.params` ima ključeve `stepDuration`, `blockReward`, `maximumUncleCountTransition`, `maximumUncleCount`, `validators`, `blockRewardContractAddress`, `blockRewardContractTransition`, `blockRewardContractTransitions`, `randomnessContractAddress`, `posdaoTransition` i `rewriteBytecode`.
- Vrijednosti kovanja:
  - `blockReward: 0x0`;
  - `blockRewardContractAddress: 0x867305d19606aadba405ce534e303d0e225f9556`;
  - `blockRewardContractTransition: 1310`;
  - `blockRewardContractTransitions: {9186425: 0x481c034c6d9441db23Ea48De68BCAe812C5d39bA}`.
- U `params`:
  - `eip1559FeeCollector: 0x6BBe78ee9e474842Dbd4AB4987b3CeFE88426A92` (od bloka 19040000), dakle base fee se ne spaljuje nego ide na tu adresu;
  - `eip1559BaseFeeMaxChangeDenominator: 0x8`, `eip1559ElasticityMultiplier: 0x2`;
  - `transactionPermissionContract` (od 9186425) i `registrar` (naslijeđe iz AuRa/POSDAO doba).
- Forkovi poslije mergea nisu traženi pod imenima `*withdraw*`, `*deposit*` ni `*blob*` u `params`. Te ključeve treba pronaći na devnetu, vidi [docs/12 § Otvorena pitanja](../12-domovina-chain.md#otvorena-pitanja).

## 2. Chain ID (chainid.network/chains.json, provjereno 2026-10-30)

- `385` je zauzet: „Lisinski”.
- Slobodni su bili: `3850`, `38500`, `385385`, `1991`, `10385`, `4385`.

## 3. Kako se kuje xDAI (docs.gnosischain.com, xDai Bridge, provjereno 2026-11-02)

**Ethereum → Gnosis:**

1. Korisnik na Ethereumu poziva `relayTokens(recipient, value)` na Foreign xDAI bridgeu. Emitira se `UserRequestForAffirmation`.
2. Bridge validatori pozivaju `executeAffirmation` na Home bridgeu na Gnosisu.
3. Kad 4 od 7 potvrde, Home bridge u Block Reward ugovor upiše primatelja i iznos (`AddedReceiver`).
4. U sljedećem bloku consensus engine pozove Block Reward ugovor i klijent dopiše native xDAI na saldo primatelja.

**Gnosis → Ethereum:**

1. Korisnik šalje xDAI Home bridgeu i xDAI se spali (`UserRequestForSignature`).
2. Validatori pozivaju `submitSignature`, nakon čega se emitira `CollectedSignatures`.
3. Bilo tko poziva `executeSignatures` na Ethereumu i primatelj dobiva USDS (ili DAI preko Bridge Routera).

**Pokriće:** stranica kaže „DAI is replaced with USDS as the default accepted token on Ethereum”, ali odjeljak o sDAI-ju još opisuje DAI. Dokumentacija nije usklađena. Stranica o migraciji (`usds-xdaibridge-migration`) navodi rok za aplikacije do 8. 6. 2025.

**Povjerenje:**

- validatori bridgea su 4-od-7;
- governance je multisig 8-od-15 (validatori, dnevni limiti, naknade).

**Kamata:** većina pokrića leži u sDAI vaultu (Spark) na Ethereumu. Kamata se šalje na Gnosis, gdje je Interest Receiver ulaže u sDAI. Keeper (Karpatkey) poziva `investDAI()`, `refillBridge()` i `payInterest()`, a `minimumCashThreshold` čuva rezervu za isplate.

Izvori:

- https://docs.gnosischain.com/bridges/About%20Token%20Bridges/xdai-bridge
- https://docs.gnosischain.com/bridges/About%20Token%20Bridges/usds-xdaibridge-migration
- https://www.theblock.co/post/313867/gnosis-chain-community-members-evaluate-gas-token-choices-amid-makerdaos-pivot-to-sky

## 4. Izvorni kod bridgea (GitHub API, provjereno 2026-11-02)

**Repozitoriji:**

| Repo | Licenca | Zadnji push | Archived |
|---|---|---|---|
| `gnosischain/tokenbridge-contracts` | GPL-3.0 | 2025-11-10 | ne |
| `gnosischain/tokenbridge` | GPL-3.0 | 2026-10-23 | ne |

- `gnosischain/tokenbridge` je monorepo s direktorijima `oracle`, `monitor`, `alm`, `deployment` i `commons`.
- Stari `poanetwork/*` repoi su preseljeni (301).

**Ugovori u `contracts/upgradeable_contracts/erc20_to_native/`:**

- `ForeignBridgeErcToNative.sol`
- `HomeBridgeErcToNative.sol`
- `RewardableHomeBridgeErcToNative.sol`
- `FeeManagerErcToNative.sol` i `FeeManagerErcToNativePOSDAO.sol`
- `XDaiForeignBridge.sol`

Uz njih su `upgradeable_contracts/BlockRewardBridge.sol`, `BlockRewardFeeManager.sol` i `interfaces/IBlockReward.sol`. Deploy skripte su `deploy/src/utils/deployBlockReward.js` i `setBlockReward.js`.

**Nalazi u kodu:**

- Svi ugovori su `pragma solidity 0.4.24` i upgradeable (proxy).
- `ForeignBridgeErcToNative` je općenit: nasljeđuje `ERC20Bridge` i `OtherSideBridgeStorage`, ima `initialize` s dnevnim i po-transakcijskim limitima te `relayTokens(_receiver, _amount)` i `claimTokens`. Nema tvrdo zakucanog tokena.
- `XDaiForeignBridge is ForeignBridgeErcToNative, CompoundConnector, GSNForeignERC20Bridge`. Specifičnosti za DAI:
  - `require(_erc20token == address(daiToken()))`;
  - `investDai()`, `upgradeTo530(_interestReceiver)` (`_setMinCashThreshold(dai, 1000000 ether)`);
  - GSN isplata (`onExecuteMessageGSN`).
- `deploy/.env.example` ima `BRIDGE_MODE`, `BLOCK_REWARD_ADDRESS` i `HOME_REWARDABLE`.

## 5. EURe na Gnosisu (iz ovog repoa, [docs/07](../07-wallet-notifications.md))

- Kanonski EURe v2: `0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430`, 18 decimala.
- EURe v1 `0xcB444e90D8198415266c6a2724b7900fb12FC56E` prosljeđuje transfere na v2.
- Nije provjereno: ima li EURe v2 funkcije za zamrzavanje ili blacklist adresa. To je otvoreno pitanje u [docs/12](../12-domovina-chain.md#otvorena-pitanja).
