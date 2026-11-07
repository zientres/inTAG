(() => {
  "use strict";

  const CONFIG_URL = new URL("contracts/testnet.config.json", document.baseURI);
  const TONCENTER_URL = "https://testnet.toncenter.com/api/v2/runGetMethod";
  const FNV128_OFFSET = 0x6c62272e07bb014262b821756295c58dn;
  const FNV128_PRIME = 0x0000000001000000000000000000013bn;
  const FNV128_MASK = (1n << 128n) - 1n;
  const AUCTION_MANAGER_CREATE_OPCODE = 0x54474101;
  const AUCTION_CREATE_AMOUNT = "50000000";
  const STARTING_BID = 1000000000n;
  const MINIMUM_BID_STEP = 100000000n;
  const AUCTION_DURATION_SECONDS = 90 * 60;

  async function loadTestnetConfig() {
    const response = await fetch(CONFIG_URL, { cache: "no-store" });
    if (!response.ok) throw new Error("Не удалось загрузить конфигурацию Testnet.");
    const config = await response.json();
    if (config.network !== "testnet") {
      throw new Error("Запрос заблокирован: разрешена только сеть TON Testnet.");
    }
    if (!config.auction_manager) {
      throw new Error("Auction Manager ещё не развёрнут в TON Testnet.");
    }
    return config;
  }

  function canonicalRussianPlate(plate) {
    return String(plate).replace(/\\s+/g, "").toUpperCase();
  }

  async function hashPlate(country, plate) {
    const canonical = country + "|" + canonicalRussianPlate(plate);
    const bytes = new TextEncoder().encode(canonical);
    let hash = FNV128_OFFSET;
    for (const byte of bytes) {
      hash ^= BigInt(byte);
      hash = (hash * FNV128_PRIME) & FNV128_MASK;
    }
    return hash.toString(16).padStart(64, "0");
  }

  async function lookupRussianPlate(plate) {
    const config = await loadTestnetConfig();
    const hash = await hashPlate("RU", plate);
    const response = await fetch(TONCENTER_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        address: config.auction_manager,
        method: "get_plate_status",
        stack: [["num", "0x" + hash]]
      })
    });
    if (!response.ok) throw new Error("TON Testnet API вернул HTTP " + response.status + ".");
    const data = await response.json();
    if (!data.ok || !Array.isArray(data.stack) || !data.stack.length) {
      throw new Error("Не удалось получить статус номера из смарт-контракта.");
    }

    const rawStatus = data.stack[0][1]?.[1] ?? data.stack[0][1];
    const statusCode = BigInt(rawStatus);
    if (statusCode === 0n) return { status: "free" };
    if (statusCode === 1n) return { status: "auction" };
    if (statusCode === 2n) return { status: "minted" };
    return { status: "unknown" };
  }

  async function createRussianAuction(plate) {
    const config = await loadTestnetConfig();
    const tonConnect = window.tagitalSpaceTonConnect;
    if (!tonConnect?.wallet) {
      throw new Error("Сначала подключите TON-кошелёк.");
    }
    if (tonConnect.wallet.account.chain !== "-3") {
      throw new Error("Для создания аукциона подключите кошелёк к TON Testnet.");
    }

    const canonicalPlate = canonicalRussianPlate(plate);
    if (!/^[АВЕКМНОРСТУХ][0-9]{3}[АВЕКМНОРСТУХ]{2}[0-9]{2,3}$/.test(canonicalPlate)) {
      throw new Error("Номер имеет неверный формат.");
    }

    const { beginCell } = await import("https://esm.sh/@ton/core@0.59.0");
    const random = new Uint32Array(2);
    crypto.getRandomValues(random);
    let queryId = (BigInt(random[0]) << 32n) | BigInt(random[1]);
    if (queryId === 0n) queryId = 1n;

    const now = Math.floor(Date.now() / 1000);
    const endTime = now + AUCTION_DURATION_SECONDS;
    const payload = beginCell()
      .storeUint(AUCTION_MANAGER_CREATE_OPCODE, 32)
      .storeUint(queryId, 64)
      .storeStringTail(canonicalPlate)
      .storeCoins(STARTING_BID)
      .storeCoins(MINIMUM_BID_STEP)
      .storeUint(endTime, 32)
      .endCell();

    const result = await tonConnect.sendTransaction({
      validUntil: now + 600,
      messages: [{
        address: config.auction_manager,
        amount: AUCTION_CREATE_AMOUNT,
        payload: payload.toBoc().toString("base64")
      }]
    });

    return { endTime, boc: result.boc };
  }

  window.tagitalSpaceRegistry = { lookupRussianPlate, createRussianAuction };
})();
