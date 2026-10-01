# Istraživanje: Gnosis validator (2026-10-01)

> Sirovi nalaz istraživačkog agenta. UNVERIFIED/DERIVED oznake su namjerne.

I verified this on 2026-10-01 against the Gnosis docs (pulled from the `gnosischain/documentation` repo, last commit 2026-09-24), `gnosischain/configs` mainnet, the GitHub releases API, the Lighthouse book source and live API calls. Anything I could not confirm is marked **UNVERIFIED** or **DERIVED** (my own calculation).

## 1. Key generation

- **Tool:** Gnosis now points to **ethstaker-deposit-cli**, with Wagyu Key Gen as the GUI option ([generate-keys partial](https://github.com/gnosischain/documentation/blob/main/docs/node/manual/validator/_partials/_generate_validator_keys_cli.md)). `gnosischain/validator-data-generator` (last release v2.3.0-gbc, 2022-11-18) is legacy and only creates 0x01 keys. Don't use it.
- **Release:** latest stable is **v1.3.0** (2026-04-30); v1.3.1 (2026-08-29) is a pre-release (`api.github.com/repos/ethstaker/ethstaker-deposit-cli/releases`). Trail of Bits audited it in March 2026.
  - It ships both `darwin-amd64` and `darwin-arm64` binaries, e.g. `ethstaker_deposit-cli-d8016bc-darwin-amd64.tar.gz`. The amd64 build runs on a `macos15-intel` runner, so very old macOS versions may not run it (**UNVERIFIED**).
- **Verifying the download:** each archive has a `.sha256` file containing only the hash (for darwin-amd64 it is `27405566a8d2…f07196d`).
  - Check it with `shasum -a 256 <file>` and compare.
  - Also run `gh attestation verify <file> --repo ethstaker/ethstaker-deposit-cli` and continue only if it prints "Verification succeeded". This needs a network connection, so do it on an online machine ([quick_setup](https://github.com/ethstaker/ethstaker-deposit-cli/blob/main/docs/src/quick_setup.md)).
  - On macOS you have to right-click → Open once to get past Gatekeeper.
- **Command for 1 validator** ([new_mnemonic docs](https://github.com/ethstaker/ethstaker-deposit-cli/blob/main/docs/src/new_mnemonic.md), [Gnosis withdrawals page](https://github.com/gnosischain/documentation/blob/main/docs/node/management/withdrawals/withdrawals.md)):
  ```
  ./deposit new-mnemonic --chain gnosis --num_validators 1 \
    --withdrawal_address 0xYOUR_ADDRESS --compounding --amount 1 --folder ./validator_keys
  ```
  On Gnosis `--amount` is in GNO, defaults to 1 and can go up to 64. Since v1.2.0 compounding (0x02) is the default whenever a withdrawal address is given; `--regular_withdrawal` gives 0x01. Leave the password and mnemonic off the command line and enter them at the prompts so they stay out of shell history.
- **0x01 vs 0x02: pick 0x02.** Gnosis docs call it "Compounding — recommended":
  - **Compounding:** the maximum effective balance is 64 GNO, and rewards stay in the validator and compound.
  - **Small steps:** the Gnosis preset has `EFFECTIVE_BALANCE_INCREMENT` = 1e9 against `MAX_EFFECTIVE_BALANCE` 32e9 (1 GNO = 32e9 units), so the effective balance grows in 1/32-GNO steps. At about 8.6% the first step comes after roughly 5–6 months (**DERIVED**). Source: [lighthouse gnosis preset](https://github.com/sigp/lighthouse/tree/stable/consensus/types/presets/gnosis).
  - **One-way choice:** you can top up later, and 0x01→0x02 is possible later by self-consolidation, but there is no way back from 0x02 to 0x01.
  - **Cost of 0x02:** to take rewards out you send an EIP-7002 request from the withdrawal address, which costs a small fee. With 0x01, anything above 1 GNO is swept out automatically and never compounds.
- **Air-gapped generation on a Mac:** both ethstaker and Gnosis recommend generating offline, ideally from a Tails live USB.
  - Practical route: verify the binary online, copy it to USB, boot the Intel MacBook (or a spare machine) with networking off, or from Tails, and generate there. Write the mnemonic on paper or steel.
  - Copy only `keystore-*.json` and `deposit_data-*.json` to the node.
  - Booting Tails on a T2 Mac requires allowing external boot in Startup Security Utility (**UNVERIFIED** for your exact model).

## 2. Deposit

- `deposit.gnosischain.com` returns **301 → https://validators.gnosischain.com/** (checked with curl today).
- Flow ([deposit.md](https://github.com/gnosischain/documentation/blob/main/docs/node/manual/validator/deposit.md)):
  1. Connect a web3 wallet (MetaMask is the example; a Safe works when the app is added as a custom app).
  2. Upload `deposit_data.json`.
  3. Send the transaction. It calls `transferAndCall` on the GNO token, whose data includes the deposit contract address.
- **1 GNO per validator, and it must be GNO on Gnosis Chain.** GNO on Ethereum has to be bridged first (Omnibridge or transferto.xyz). You also need a little xDAI for gas.
- **Addresses** (also in `configs/mainnet/config.yaml`):
  - GNO token: `0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb`
  - Deposit contract: `0x0B98057eA310F4d31F2a452B414647007d1645d9`
- Gnosis says to deposit only after the EL and CL are synced and the VC is running with keys imported.
- 0x02 deposits with variable amounts are accepted since the contract's `batchDeposit` upgrade on 2025-05-02.

## 3. Queue, APR, withdrawals, exit

- **Queue right now:** empty. `beaconchain.gnosischain.com/api/v1/validators/queue` returned `entering:0, exiting:0, validatorscount:33387`. Total stake is about 298.6k GNO, from `api/v1/epoch/latest` at epoch 1898473.
- **Churn:** the config sets `MAX_PER_EPOCH_ACTIVATION_EXIT_CHURN_LIMIT` = 64e9, i.e. **2 GNO per 80-second epoch**, about 2,160 GNO/day. That is the queue throughput (**DERIVED**).
- **Activation time:** the docs still say "~1.5 h" (1024 blocks + up to 64 epochs). That is the pre-Electra mechanism; with an empty queue it is probably faster (**UNVERIFIED**).
- **APR:** 8.59% network-wide validator APY, as of 2026-09-30, from `curl https://api.analytics.gnosis.io/v1/consensus/validators_apy/latest`. That is roughly 0.086 GNO per year on 1 GNO.
- **Withdrawals:** they are paid in GNO but **not pushed to your wallet**. The sweep moves GNO into the deposit contract, and you then claim it from validators.gnosischain.com, with `claimWithdrawal(address)` (anyone can call it), or with the app's optional Autoclaim. Source: [claiming-your-gno](https://github.com/gnosischain/documentation/blob/main/docs/node/management/withdrawals/claiming-your-gno.md).
  - 0x01: everything above 1 GNO is swept automatically.
  - 0x02: there is no sweep below 64 GNO; partial withdrawals happen only when you request them (EIP-7002).
- **Exit:** easiest from the validators app (Withdraw → MAX → "Exit validator"), sent from the withdrawal address. Alternatively `lighthouse --network gnosis account validator exit --keystore … --beacon-node http://localhost:5052`.
  - After the exit there is a fixed 256-epoch delay, about 5.7 h, then the sweep, then you claim. Typically claimable within 1–2 days ([voluntary-exit](https://github.com/gnosischain/documentation/blob/main/docs/node/management/voluntary-exit.md)).

## 4. Running the validator client

- **Lighthouse on an Intel Mac must be built from source.** v8.2.3 (released 2026-10-01) has binaries only for `aarch64-apple-darwin` and Linux. Homebrew `lighthouse` 8.2.3 has no x86_64 macOS bottle either, so it also compiles.
- **Nethermind** 2.0.0 (2026-09-22) ships a `macos-x64` zip with a `.asc` signature.
- **Teku** 26.9.1 is a Java tarball and runs anywhere.
- **Nimbus** v26.9.1 has a macOS arm64 binary only.
- **Lighthouse import and run** ([Gnosis lighthouse partial](https://github.com/gnosischain/documentation/blob/main/docs/node/manual/validator/_partials/clients/_install_validator_lighthouse.md)):
  ```
  lighthouse account validator import --network gnosis --directory keystores \
    --password-file keystores/password.txt --reuse-password --datadir validators
  lighthouse vc --network gnosis --datadir validators --beacon-nodes http://localhost:5052 \
    --suggested-fee-recipient 0xYOUR_ADDR --enable-doppelganger-protection --graffiti "…" --metrics
  ```
  If no fee recipient is set, transaction tips are burned.
  - Doppelganger protection keeps the VC silent for 2–3 epochs. The book says 12–20 min for Ethereum; on Gnosis that is about 3–4 min (**DERIVED**).
- **Slashing protection** ([book](https://github.com/sigp/lighthouse/blob/stable/book/src/validator_slashing_protection.md)): the database is `$datadir/validators/slashing_protection.sqlite`. EIP-3076 export and import, with the VC stopped:
  ```
  lighthouse account validator slashing-protection export file.json
  lighthouse account validator slashing-protection import file.json
  ```
  Keystores are imported separately. Never use `--init-slashing-protection` casually.
- **Teku:**
  ```
  teku validator-client --network=gnosis --beacon-node-api-endpoint=… --validator-keys=KEYS:PASSWORDS
  ```
  plus `--validators-proposer-default-fee-recipient`. Each password file must be named like its keystore with `.txt`. Exit with `teku voluntary-exit`.
  - From memory, not checked against Teku docs today (**UNVERIFIED**): `teku slashing-protection export --data-path=… --to=file.json` / `import --from=…`, and `--doppelganger-detection-enabled`.
- **MEV-boost: there is none on Gnosis.** The Gnosis FAQ says: "There is no MEV-Boost on Gnosis Chain currently" ([runningNode.md](https://github.com/gnosischain/documentation/blob/main/docs/faq/Node%20FAQs/runningNode.md)). The "Agnostic Gnosis" relay is for Ethereum mainnet. Don't run mev-boost.

## 5. Downtime vs slashing

- **Being offline costs about what being online earns.** Missed source/target votes are penalised, while missed head votes, proposals and sync duties only lose the reward. At 8.59% that is about 0.00024 GNO/day earned, so a day offline swings roughly 0.0004 GNO (**DERIVED**). You stay net positive with more than 42.5% uptime ([rewards-penalties](https://github.com/gnosischain/documentation/blob/main/docs/node/rewards-penalties.md)).
- **Inactivity leak** happens only when the whole network fails to finalize, i.e. more than 1/3 offline (`MIN_EPOCHS_TO_INACTIVITY_PENALTY` 4). Isolated downtime does not leak. Ejection is at 0.5 GNO (`EJECTION_BALANCE` 16e9).
- **Slashing:** post-Electra the immediate penalty is EB/4096 (`MIN_SLASHING_PENALTY_QUOTIENT_ELECTRA` 4096), plus a correlation penalty, plus a forced exit after about 4096 epochs (≈3.8 days).
  - Gnosis docs still say "1/32 is burned", which is pre-Electra and **outdated**.
  - The only realistic cause is running the same keys twice: on two machines, or when migrating without moving the slashing DB.
- **Home and laptop risks:**
  - **Sleep:** stop the Mac sleeping (`pmset`/`caffeinate`) and turn off automatic macOS updates.
  - **Outages:** the battery acts as a UPS, but not for the router or ISP.
  - **IP:** your home IP is visible through p2p and can be linked to your proposals, which makes you a DoS target. Don't publish which validator is yours.
  - **Forks:** update clients before each fork epoch. Fulu activated 2026-04-14 and no further fork is scheduled in `configs/mainnet/config.yaml` today.
  - **Restarts:** every VC restart with doppelganger protection on costs about 3 epochs.

## 6. Monitoring

- **Explorer:** `beaconchain.gnosischain.com` is beaconcha.in-powered (its page title says so) and has the notifications UI; whether those alerts actually work for Gnosis is **UNVERIFIED**. `gnosis.beaconcha.in` and `gnosischa.in` did not resolve from here (**UNVERIFIED** whether they are retired or this was a local DNS problem).
- **Official alerting:** the free Telegram bot by node-sentinel.xyz (`t.me/gbc_validators_bot`) — register your withdrawal address and it alerts on status changes and performance drops ([monitoring-validators](https://github.com/gnosischain/documentation/blob/main/docs/node/management/monitoring-validators.md)).
- **Local:** Lighthouse `--metrics` on port 5064 with Prometheus and Grafana.

**Caveat:** some Gnosis docs pages mix pre- and post-Electra facts (activation timing, the 1/32 slashing figure). Where they conflicted I trusted the config and preset values.
