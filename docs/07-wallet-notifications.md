# 07 — Notifikacije o uplatama i realtime detekcija EURe (listener)

`listener/listener.mjs` je lokalni Node.js proces bez vanjskih npm ovisnosti (Node 24 LTS) koji na samom čvoru (`127.0.0.1`) prati svaki novi blok i u realnom vremenu detektira dolazne **EURe**, ostale **ERC-20** i **native xDAI** uplate na praćene adrese. Za svaku uplatu šalje HMAC-potpisani webhook prema Cloudflare Workeru (ili drugom backendu), koji događaj sprema u bazu podataka (npr. Cloudflare D1 / PostgreSQL) i šalje push notifikaciju preko **Firebase Cloud Messaginga (FCM HTTP v1)** i APNs-a.

Osnovna arhitekturna odluka opisana je u [ADR-008](02-decisions.md#adr-008).

---

## 1. End-to-end arhitektura

```mermaid
flowchart LR
  subgraph Node["MacBook i9 (/opt/gnosis, user _gnosis)"]
    NM["Nethermind<br/>HTTP :8545 / WS :8546"]
    LS["listener.mjs<br/>(LaunchDaemon)"]
    ST["state/listener-state.json<br/>etc/watchlist.json"]
  end

  subgraph Backend["Cloudflare Worker / Backend"]
    WH["POST /webhook/payment<br/>(HMAC-SHA256 provjera)"]
    DB[("Baza podataka<br/>(D1 / Postgres)<br/>payment_events + fcm_tokens")]
  end

  subgraph Push["Push & Realtime kanali"]
    FCM["Firebase Cloud Messaging<br/>(FCM HTTP v1 API)"]
    WS_CL["WebSocket / SSE<br/>(POS blagajna / web)"]
  end

  APP["Domovina Wallet /<br/>pay.domovina.ai"]

  NM -->|"1. WS newHeads (~0 ms)"| LS
  LS -->|"2. eth_getBlockByNumber +<br/>eth_getLogs(blockHash) (~3 ms)"| NM
  LS <--> ST
  LS -->|"3. HTTPS POST + HMAC"| WH
  WH -->|"4. Idempotentni INSERT<br/>(deduplikacija po id)"| DB
  WH -->|"5a. OAuth2 JWT → FCM send"| FCM
  WH -->|"5b. Instant status"| WS_CL
  FCM -->|"Push obavijest"| APP
  WS_CL -->|"Realtime UI"| APP
```

### Zašto lokalni listener na čvoru umjesto vanjskog indexera ili pollinga?

1. **Nula latencije i nula rate-limita:** Nethermind i `listener.mjs` komuniciraju preko `127.0.0.1` loopback sučelja. Čim Nethermind uveze novi blok iz P2P mreže, šalje `newHeads` obavijest preko WebSocketa (`ws://127.0.0.1:8546`), a čitanje bloka i svih `Transfer` logova tog bloka lokalno traje **2–5 ms**.
2. **Neovisnost o trećim stranama:** Nema ovisnosti o Blockscoutu, Gnosisscanu, Alchemyju ili TheGraphu. Čak i ako svi javni eksploreri kasne ili padnu, naš čvor vidi blok čim ga mreža proizvede.
3. **Otpornost na ispade i reorgove:** Za razliku od golih `eth_subscribe("logs")` pretplata koje izgube događaje dok je WebSocket prekinut i ne znaju za reorganizacije lanca, `listener.mjs` vodi redoslijedno stanje (`state/listener-state.json`) po broju i hashu bloka.

---

## 2. Unutarnji tok obrade bloka i reorg zaštita

```mermaid
flowchart TD
  WS["WS newHeads (ws://127.0.0.1:8546)<br/>instant budilica + provjera tip reorga"] --> T["tick()"]
  P["Timer svakih 5 s (POLL_MS)<br/>rezerva ako WS padne"] --> T
  T --> H["head = eth_blockNumber<br/>target = head − CONFIRMATIONS"]
  H --> LOOP{"lastBlock < target?"}
  LOOP -->|da| B["n = lastBlock + 1<br/>eth_getBlockByNumber(n, true)<br/>+ eth_getLogs(blockHash, Transfer)"]
  B --> R{"parentHash == state.hashes[n−1]?"}
  R -->|ne: reorg| RW["Premotaj: lastBlock = n − 2"] --> LOOP
  R -->|da| E["Filtriraj native xDAI i ERC-20 Transfer<br/>prema watchlisti i TOKEN_ALLOWLIST"]
  E --> D["POST svakog eventa Workeru<br/>(eksponencijalni retry dok ne vrati 2xx)"]
  D --> S["lastBlock = n, spremi hashes[n]<br/>atomski zapis u listener-state.json"] --> LOOP
  LOOP -->|ne| END["Čekaj idući blok"]
```

### Brzina detekcije: `CONFIRMATIONS=0` (instant) naspram `CONFIRMATIONS=2`

Gnosis Chain proizvodi blok svakih **5 sekundi**. U `/opt/gnosis/etc/listener.env` ponašanje se bira varijablom `CONFIRMATIONS`:

| Postavka | Latencija od uvoza bloka | Ukupno od slanja tx-a (prosjek) | Sigurnost od reorga | Kada koristiti |
| --- | --- | --- | --- | --- |
| **`CONFIRMATIONS=0`** | **~50–200 ms** (uključujući webhook i FCM) | **~2,5 s** (pola slota od 5 s) | Moguć rijedak reorg od 1 bloka (single-slot reorg kad kasni blok prethodnog validatora) | **Instant / POS detekcija** („Uplata viđena u bloku #…”) i trenutna FCM obavijest |
| **`CONFIRMATIONS=1`** | ~5 s | ~7,5 s | Visoka (preživljava single-slot kašnjenje) | Brza potvrda za manje iznose |
| **`CONFIRMATIONS=2`** *(default)* | ~10 s | ~12,5 s | Vrlo visoka (2 uzastopna validatora potvrdila lanac) | Knjiženje konačne uplate bez naknadnog poništavanja |

> **Kako `listener.mjs` rješava reorg kad je `CONFIRMATIONS=0`:**
> Čak i s `CONFIRMATIONS=0`, `listener.mjs` pamti zadnjih 64 hasha blokova (`state.hashes`). Ako na istoj visini `N` stigne zamjenski blok `N'` s drugačijim hashom (ili kad stigne blok `N+1` čiji se `parentHash` ne poklapa sa spremljenim `state.hashes[N]`), listener automatski premotava `state.lastBlock` unatrag i obrađuje kanonski blok.

---

## 3. Specifičnost EURe na Gnosis Chainu (Monerium v1 vs. v2 zamka)

Na Gnosis Chainu postoje **dva** službena Monerium EURe ugovora (provjereno na našem čvoru `i9`, 2026-10-24):

| Ugovor | Naziv (`name()`) | Simbol | Decimale | Uloga na lancu |
| --- | --- | --- | --- | --- |
| **`0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430`** | `Monerium EURe` | `EURe` | `18` | **Kanonski EURe v2 ugovor** (drži sva stanja i emitira `Transfer` za svaku EURe transakciju) |
| `0xcB444e90D8198415266c6a2724b7900fb12FC56E` | `Monerium EUR emoney` | `EURe` | `18` | **Legacy EURe v1 adapter/proxy** (starija adresa koju još koriste mnogi novčanici, CowSwap i bridgevi) |

### Što se događa na lancu kad netko pošalje EURe?

- Kad pošiljatelj pozove **v2 ugovor (`0x420CA0…`)**, emitira se **jedan** `Transfer(from, to, value)` log s adrese `0x420CA0…`.
- Kad pošiljatelj pozove **stari v1 ugovor (`0xcB444e…`)**, v1 ugovor interno prosljeđuje poziv v2 ugovoru, pa se u **istoj transakciji** emitiraju **dva identična `Transfer(from, to, value)` loga**:
  1. `logIndex: N` s kanonskog v2 ugovora `0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430`,
  2. `logIndex: N+1` sa starog v1 ugovora `0xcB444e90D8198415266c6a2724b7900fb12FC56E`.

> **Dokaz s lanca (`i9`, uzorak od 1.000 blokova):** Od 1.013 EURe transfera, njih 619 išlo je preko v1 ugovora i **svih 619 (100 %)** emitiralo je odgovarajući `Transfer` log i na v2 ugovoru (`0x420CA0…`).
>
> Zato `listener/listener.mjs` u `IGNORED_TOKENS` automatski preskače legacy v1 adresu `0xcB444e90D8198415266c6a2724b7900fb12FC56E`. Time svaka EURe uplata — bez obzira je li poslana preko v1 ili v2 sučelja — proizvodi **točno jedan** `ERC20_RECEIVED` događaj s kanonskom adresom tokena `0x420ca0f9b9b604ce0fd9c18ef134c705e5fa3430`.

Ako želiš da listener prati **isključivo EURe** (i native xDAI), u `/opt/gnosis/etc/listener.env` postavi:

```ini
TOKEN_ALLOWLIST=0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430
```

Ako želiš pratiti EURe, sDAI i GNO, navedi ih odvojene zarezom:

```ini
TOKEN_ALLOWLIST=0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430,0xaf204776c7245bF4147c2612BF6e5972Ee483701,0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb
```

---

## 4. Ugovor između listenera i Workera (Webhook Payload)

`POST $WEBHOOK_URL`, `content-type: application/json`

### HTTP zaglavlja

```http
content-type: application/json
x-domovina-timestamp: 1792803600
x-domovina-signature: sha256=<hex(HMAC_SHA256(WEBHOOK_SECRET, timestamp + "." + rawBody))>
```

### JSON tijelo (`ERC20_RECEIVED` — npr. EURe uplata)

```json
{
  "id": "0x92c38d01afac75b730934b6dc8a5f8a3cafcbe524fd8673641036382aba71059:13",
  "type": "ERC20_RECEIVED",
  "blockNumber": 48901172,
  "blockHash": "0x6a9d8e5c1f3c0a8b4d2e9f1a7c5b3d8e2f4a6c8b0d1e3f5a7c9b2d4e6f8a0b1c",
  "timestamp": 1792751235,
  "txHash": "0x92c38d01afac75b730934b6dc8a5f8a3cafcbe524fd8673641036382aba71059",
  "from": "0xe33954c8ad776f5b2204f40185be03101d7512ba",
  "to": "0x449abcef4e29a7dd8d98db451af2c463561baf2e",
  "token": "0x420ca0f9b9b604ce0fd9c18ef134c705e5fa3430",
  "symbol": "EURe",
  "decimals": 18,
  "amountRaw": "25000000000000000000",
  "amount": "25"
}
```

### Razlike po tipu događaja

- `type` je `"ERC20_RECEIVED"` ili `"NATIVE_RECEIVED"`.
- Za `"NATIVE_RECEIVED"` (izravna uplata xDAI):
  - `id` je `"<txHash>:native"`,
  - `token` je `null`,
  - `symbol` je `"xDAI"`, `decimals` je `18`.
- Sve adrese (`from`, `to`, `token`, `txHash`, `blockHash`) su uvijek **lowercase** s prefiksom `0x`.

### Pravila isporuke i sigurnosti na strani Workera

1. **Zaštita od replay napada:** odbiti zahtjev (`HTTP 401`) ako je `|now − timestamp| > 300` sekundi.
2. **Provjera potpisa u konstantnom vremenu:** izračunati HMAC-SHA256 nad `${timestamp}.${rawBody}` koristeći `crypto.subtle.verify`.
3. **Idempotentnost / deduplikacija po `id`:** isporuka iz listenera je *at-least-once* (ako Worker vrati 5xx/429 ili pukne mreža, listener ponavlja slanje s eksponencijalnim backoffom do 60 s dok ne dobije `2xx`). Zato je `id` (`<txHash>:<logIndex>`) primarni ključ u bazi: duplikat se tiho ignorira i vraća `200 OK`.
4. **Zamjena bloka kod `CONFIRMATIONS=0`:** ako koristiš `CONFIRMATIONS=0` i dogodi se reorg, nova transakcija imat će novi `blockHash` (ili se ista transakcija pojavi u idućem bloku s istim `txHash`, a u rijetkom slučaju poništenja uplate u reorgu može se provjeriti status nakon 2 bloka).

---

## 5. Baza podataka i Firebase Cloud Messaging (FCM HTTP v1)

### 5.1. SQL shema (Cloudflare D1 / SQLite / PostgreSQL)

```sql
-- 1. Praćene adrese novčanika / blagajni
CREATE TABLE IF NOT EXISTS watched_addresses (
  address TEXT PRIMARY KEY,              -- lowercase 0x...
  label TEXT,                            -- npr. "MPT Safe", "Korisnik #1042"
  created_at INTEGER NOT NULL DEFAULT (unixepoch())
);

-- 2. Registrirani Firebase Cloud Messaging (FCM) tokeni uređaja po adresi
CREATE TABLE IF NOT EXISTS device_tokens (
  fcm_token TEXT PRIMARY KEY,
  address TEXT NOT NULL,                 -- lowercase 0x...
  platform TEXT NOT NULL DEFAULT 'web',  -- 'android' | 'ios' | 'web'
  updated_at INTEGER NOT NULL DEFAULT (unixepoch())
);
CREATE INDEX IF NOT EXISTS idx_device_tokens_address ON device_tokens(address);

-- 3. Primljene uplate (id = "<txHash>:<logIndex>" ili "<txHash>:native")
CREATE TABLE IF NOT EXISTS payment_events (
  id TEXT PRIMARY KEY,
  event_type TEXT NOT NULL,              -- 'ERC20_RECEIVED' | 'NATIVE_RECEIVED'
  block_number INTEGER NOT NULL,
  block_hash TEXT NOT NULL,
  block_timestamp INTEGER NOT NULL,
  tx_hash TEXT NOT NULL,
  sender TEXT NOT NULL,
  recipient TEXT NOT NULL,
  token TEXT,                            -- NULL za xDAI, 0x420ca0... za EURe
  symbol TEXT,
  decimals INTEGER,
  amount_raw TEXT NOT NULL,
  amount TEXT,
  received_at INTEGER NOT NULL DEFAULT (unixepoch()),
  fcm_pushed_at INTEGER
);
CREATE INDEX IF NOT EXISTS idx_payment_events_recipient ON payment_events(recipient, block_number DESC);
CREATE INDEX IF NOT EXISTS idx_payment_events_tx ON payment_events(tx_hash);
```

### 5.2. Referentna implementacija Cloudflare Workera (D1 + FCM HTTP v1)

Firebase je ugasio stari legacy FCM API s `Server key` zaglavljem; aktualni **FCM HTTP v1 API** (`https://fcm.googleapis.com/v1/projects/<PROJECT_ID>/messages:send`) koristi kratkotrajni OAuth2 Bearer token potpisan privatnim ključem iz Firebase Service Account JSON-a (`scope: https://www.googleapis.com/auth/firebase.messaging`).

Sljedeći kod za Cloudflare Worker radi potpuno nativno preko Web Crypto API-ja (bez ikakvih vanjskih paketa):
1. provjerava HMAC potpis čvora `i9`,
2. idempotentno sprema uplatu u D1 bazu (`INSERT OR IGNORE`),
3. dohvaća FCM tokene primatelja iz baze i šalje instant push notifikaciju preko FCM HTTP v1 API-ja (i uklanja zastarjele `UNREGISTERED` tokene):

```ts
export interface Env {
  DB: D1Database;
  WEBHOOK_SECRET: string;          // isti kao u /opt/gnosis/etc/listener.env
  FCM_PROJECT_ID: string;          // npr. "domovina-wallet"
  FCM_CLIENT_EMAIL: string;        // iz Firebase Service Account JSON-a
  FCM_PRIVATE_KEY: string;         // "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
}

interface PaymentEvent {
  id: string;
  type: 'ERC20_RECEIVED' | 'NATIVE_RECEIVED';
  blockNumber: number;
  blockHash: string;
  timestamp: number;
  txHash: string;
  from: string;
  to: string;
  token: string | null;
  symbol: string | null;
  decimals: number | null;
  amountRaw: string;
  amount: string | null;
}

// Cache OAuth2 tokena u memoriji isolatea (vrijedi 1 h, obnavljamo nakon 50 min)
let cachedAccessToken: { token: string; expiresAt: number } | null = null;

function base64url(input: ArrayBuffer | Uint8Array | string): string {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : new Uint8Array(input);
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function getFcmAccessToken(env: Env): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && cachedAccessToken.expiresAt - 600 > now) {
    return cachedAccessToken.token;
  }

  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claim = base64url(
    JSON.stringify({
      iss: env.FCM_CLIENT_EMAIL,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );
  const unsignedJwt = `${header}.${claim}`;

  const pemContents = env.FCM_PRIVATE_KEY
    .replace(/\\n/g, '\n')
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const binaryDer = Uint8Array.from(atob(pemContents), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryDer.buffer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    cryptoKey,
    new TextEncoder().encode(unsignedJwt),
  );
  const assertion = `${unsignedJwt}.${base64url(signature)}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`OAuth2 token error: HTTP ${res.status}`);
  const data = (await res.json()) as { access_token: string; expires_in: number };
  cachedAccessToken = { token: data.access_token, expiresAt: now + data.expires_in };
  return data.access_token;
}

async function verifyHmac(req: Request, secret: string, rawBody: string): Promise<boolean> {
  const ts = req.headers.get('x-domovina-timestamp') ?? '';
  const sig = req.headers.get('x-domovina-signature') ?? '';
  if (!ts || !sig.startsWith('sha256=')) return false;
  if (Math.abs(Date.now() / 1000 - Number(ts)) > 300) return false;

  const hex = sig.slice(7);
  if (hex.length !== 64 || !/^[0-9a-f]+$/i.test(hex)) return false;
  const mac = Uint8Array.from(hex.match(/../g)!.map((h) => parseInt(h, 16)));

  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['verify'],
  );
  return crypto.subtle.verify('HMAC', key, mac, new TextEncoder().encode(`${ts}.${rawBody}`));
}

async function sendFcmPush(env: Env, fcmToken: string, ev: PaymentEvent): Promise<'ok' | 'unregistered' | 'error'> {
  const accessToken = await getFcmAccessToken(env);
  const symbol = ev.symbol ?? 'Token';
  const amountDisplay = ev.amount ?? ev.amountRaw;
  const title = `Primljeno ${amountDisplay} ${symbol}`;
  const body = `Nova uplata u bloku #${ev.blockNumber} od ${ev.from.slice(0, 6)}…${ev.from.slice(-4)}`;

  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${env.FCM_PROJECT_ID}/messages:send`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${accessToken}`,
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      message: {
        token: fcmToken,
        notification: { title, body },
        data: {
          eventId: ev.id,
          type: ev.type,
          txHash: ev.txHash,
          blockNumber: String(ev.blockNumber),
          from: ev.from,
          to: ev.to,
          token: ev.token ?? '',
          symbol,
          amount: ev.amount ?? '',
          amountRaw: ev.amountRaw,
        },
        android: {
          priority: 'HIGH',
          notification: { channel_id: 'payments_high_importance', sound: 'default' },
        },
        apns: {
          headers: { 'apns-priority': '10' },
          payload: { aps: { sound: 'default', 'content-available': 1 } },
        },
        webpush: {
          headers: { Urgency: 'high' },
        },
      },
    }),
  });

  if (res.ok) return 'ok';
  const errText = await res.text();
  if (res.status === 404 || errText.includes('UNREGISTERED')) return 'unregistered';
  console.error(`FCM send failed (${res.status}): ${errText}`);
  return 'error';
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);

    // 1. Webhook koji zove lokalni listener s i9 čvora
    if (req.method === 'POST' && url.pathname === '/webhook/payment') {
      const rawBody = await req.text();
      if (!(await verifyHmac(req, env.WEBHOOK_SECRET, rawBody))) {
        return new Response('unauthorized', { status: 401 });
      }

      const ev = JSON.parse(rawBody) as PaymentEvent;

      // Idempotentni upis u D1 bazu (duplikat se preskače)
      const ins = await env.DB.prepare(
        `INSERT OR IGNORE INTO payment_events
         (id, event_type, block_number, block_hash, block_timestamp, tx_hash, sender, recipient, token, symbol, decimals, amount_raw, amount)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
        .bind(
          ev.id,
          ev.type,
          ev.blockNumber,
          ev.blockHash,
          ev.timestamp,
          ev.txHash,
          ev.from,
          ev.to,
          ev.token,
          ev.symbol,
          ev.decimals,
          ev.amountRaw,
          ev.amount,
        )
        .run();

      // Ako je event već bio obrađen prije, vrati 200 OK bez ponovnog slanja FCM pusha
      if (ins.meta.changes === 0) {
        return Response.json({ ok: true, duplicate: true });
      }

      // Dohvati sve FCM tokene registrirane za primateljsku adresu
      const { results } = await env.DB.prepare(
        `SELECT fcm_token FROM device_tokens WHERE address = ?`,
      )
        .bind(ev.to)
        .all<{ fcm_token: string }>();

      for (const row of results) {
        const status = await sendFcmPush(env, row.fcm_token, ev);
        if (status === 'unregistered') {
          await env.DB.prepare(`DELETE FROM device_tokens WHERE fcm_token = ?`).bind(row.fcm_token).run();
        }
      }

      await env.DB.prepare(`UPDATE payment_events SET fcm_pushed_at = unixepoch() WHERE id = ?`)
        .bind(ev.id)
        .run();

      return Response.json({ ok: true, pushed: results.length });
    }

    return new Response('not found', { status: 404 });
  },
};
```

---

## 6. Uključivanje i upravljanje na `i9` čvoru

### 6.1. Prva instalacija

1. U `config/node.env` uključi listener:
   ```ini
   LISTENER_ENABLED=true
   ```
2. Instaliraj zakucanu verziju Node.js-a (`v24.21.0` iz `config/versions.env`) i kopiraj listener u `/opt/gnosis/listener`:
   ```bash
   sudo scripts/20-install.sh node listener
   ```
3. Uredi konfiguraciju i tajnu u `/opt/gnosis/etc/listener.env` (`root:_gnosis 640`):
   ```bash
   sudo vi /opt/gnosis/etc/listener.env
   ```
   Primjer za instant EURe detekciju:
   ```ini
   WEBHOOK_URL=https://notify.domovina.ai/webhook/payment
   WEBHOOK_SECRET=<izlaz iz: openssl rand -hex 32>
   CONFIRMATIONS=0
   POLL_MS=5000
   MAX_BACKFILL=720
   TOKEN_ALLOWLIST=0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430
   ```
4. Dodaj praćene adrese u `/opt/gnosis/etc/watchlist.json`:
   ```bash
   sudo tee /opt/gnosis/etc/watchlist.json <<'EOF'
   [
     "0x449abcef4e29a7dd8d98db451af2c463561baf2e"
   ]
   EOF
   ```
   *(Adrese u `watchlist.json` mogu biti pisane malim ili velikim slovima; `listener.mjs` ih pri učitavanju normalizira u lowercase i automatski ponovno učita fajl čim se promijeni `mtime`, **bez restarta servisa**.)*
5. Generiraj i pokreni LaunchDaemon `tv.domovina.gnosis.listener`:
   ```bash
   sudo scripts/30-services.sh install listener
   scripts/gnosisctl status
   scripts/gnosisctl health
   scripts/gnosisctl logs listener
   ```

### 6.2. Nadogradnja listenera nakon promjene koda

Daemon izvršava kopiju u `/opt/gnosis/listener/listener.mjs`, a ne fajl iz git radnog direktorija, kako `git pull` nikad ne bi neplanirano promijenio živi servis:

```bash
cd ~/git/domovinatv/domovina-gnosis-node && git pull
sudo scripts/20-install.sh listener
scripts/gnosisctl restart listener
```

### 6.3. Lokalni test na `i9` (bez Workera, ispis u terminal)

Za trenutnu provjeru nad živim blokovima na `i9` (bez podizanja daemona i bez `WEBHOOK_URL`-a, samo ispis detektiranih događaja):

```bash
echo '["0x449abcef4e29a7dd8d98db451af2c463561baf2e"]' > /tmp/watch.json
CONFIRMATIONS=0 WATCHLIST_FILE=/tmp/watch.json STATE_FILE=/tmp/state.json \
  TOKEN_ALLOWLIST=0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430 \
  node listener/listener.mjs
```

---

## 7. Ograničenja i buduće nadogradnje {#ograničenja}

- **Internal xDAI transferi:** xDAI koji šalje pametni ugovor (npr. isplata iz Safea ili DEX swap u native xDAI) ne stvara top-level `tx.to` s `value > 0` niti ERC-20 `Transfer` log. Za **ERC-20 tokene poput EURe** to **nije ograničenje** jer svaki EURe transfer (pa i iz Safea, CowSwapa ili relayera) uvijek emitira standardni ERC-20 `Transfer` log koji `listener.mjs` vidi. Za internal xDAI transfere u budućnosti se može uključiti Nethermindov `Trace` modul (`trace_block`).
- **Automatska sinkronizacija watchliste iz baze Workera:** trenutno se adrese čitaju iz `/opt/gnosis/etc/watchlist.json`. Kad broj korisničkih adresa naraste ili se adrese dinamički kreiraju u aplikaciji, Worker može izložiti `GET /watchlist` (potpisan istim `WEBHOOK_SECRET`-om) ili pushnuti novu listu, ili listener može slati sve `EURe` transfere u bloku Workeru (u prosjeku ~1 EURe transfer po bloku na cijelom Gnosis Chainu!), pa Worker filtrira primatelje izravno u D1 bazi bez održavanja lokalnog `watchlist.json` fajla.
