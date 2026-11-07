(() => {
  "use strict";

  const CONFIG_URL = new URL("contracts/testnet.config.json", document.baseURI);
  const TONCENTER_URL = "https://testnet.toncenter.com/api/v2/runGetMethod";
  const FNV128_OFFSET = 0x6c62272e07bb014262b821756295c58dn;
  const FNV128_PRIME = 0x0000000001000000000000000000013bn;
  const FNV128_MASK = (1n << 128n) - 1n;
  let tonCorePromise = null;

  function loadTonCore() {
    if (!tonCorePromise) {
      tonCorePromise = import("https://esm.sh/@ton/core@0.59.0");
    }
    return tonCorePromise;
  }
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
    return String(plate).replace(/\s+/g, "").toUpperCase();
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
    const result = data.result;
    if (
      !data.ok ||
      !result ||
      Number(result.exit_code) !== 0 ||
      !Array.isArray(result.stack) ||
      !result.stack.length
    ) {
      throw new Error("Не удалось получить статус номера из смарт-контракта.");
    }

    const rawStatus = result.stack[0][1];
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

    const { beginCell } = await loadTonCore();
    const random = new Uint32Array(2);
    crypto.getRandomValues(random);
    let queryId = (BigInt(random[0]) << 32n) | BigInt(random[1]);
    if (queryId === 0n) queryId = 1n;

    const now = Math.floor(Date.now() / 1000);
    const endTime = now + AUCTION_DURATION_SECONDS;
    const payload = beginCell()
      .storeUint(AUCTION_MANAGER_CREATE_OPCODE, 32)
      .storeUint(queryId, 64)
      .storeStringRefTail(canonicalPlate)
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

  async function runGetMethod(method, stack = []) {
    const config = await loadTestnetConfig();
    const response = await fetch(TONCENTER_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        address: config.auction_manager,
        method,
        stack
      })
    });
    if (!response.ok) throw new Error("TON Testnet API вернул HTTP " + response.status + ".");
    const data = await response.json();
    const result = data.result;
    if (!data.ok || !result || Number(result.exit_code) !== 0 || !Array.isArray(result.stack)) {
      throw new Error("Не удалось прочитать данные аукциона из TON Testnet.");
    }
    return result.stack;
  }

  function randomQueryId() {
    const random = new Uint32Array(2);
    crypto.getRandomValues(random);
    const queryId = (BigInt(random[0]) << 32n) | BigInt(random[1]);
    return queryId === 0n ? 1n : queryId;
  }

  async function getAuctionSummary(auctionId) {
    const stack = await runGetMethod("get_auction_summary", [["num", "0x" + BigInt(auctionId).toString(16)]]);
    const item = stack[0];
    if (!item || item[0] !== "cell" || !item[1]) return null;

    const { Cell } = await loadTonCore();
    const summary = Cell.fromBase64(item[1]);
    const slice = summary.beginParse();
    const itemIndex = Number(slice.loadUintBig(64));
    const plateCell = slice.loadRef();
    const plateSlice = plateCell.beginParse();
    const plateBytes = plateSlice.loadBuffer(Math.ceil(plateSlice.remainingBits / 8));
    const plate = new TextDecoder().decode(plateBytes);
    const startingBid = slice.loadCoins();
    const minimumBidStep = slice.loadCoins();
    const endTime = slice.loadUint(32);
    const highestBid = slice.loadCoins();
    const status = slice.loadUint(8);

    return { auctionId: Number(auctionId), itemIndex, plate, startingBid, minimumBidStep, endTime, highestBid, status };
  }

  async function listAuctions() {
    const stack = await runGetMethod("get_next_item_index");
    const total = Number(BigInt(stack[0][1]));
    const first = Math.max(0, total - 100);
    const auctions = [];
    for (let offset = first; offset < total; offset += 5) {
      const batch = [];
      for (let id = offset; id < Math.min(total, offset + 5); id++) {
        batch.push(getAuctionSummary(id));
      }
      const summaries = await Promise.all(batch);
      for (const auction of summaries) {
        if (auction && [0, 1, 5].includes(auction.status)) auctions.push(auction);
      }
    }
    return auctions.sort((a, b) => a.endTime - b.endTime);
  }

  async function sendManagerMessage(body, attachedAmount) {
    const config = await loadTestnetConfig();
    const tonConnect = window.tagitalSpaceTonConnect;
    if (!tonConnect?.wallet) throw new Error("Сначала подключите TON-кошелёк.");
    if (tonConnect.wallet.account.chain !== "-3") {
      throw new Error("Для участия в аукционе подключите кошелёк к TON Testnet.");
    }
    const now = Math.floor(Date.now() / 1000);
    return tonConnect.sendTransaction({
      validUntil: now + 600,
      messages: [{
        address: config.auction_manager,
        amount: attachedAmount.toString(),
        payload: body.toBoc().toString("base64")
      }]
    });
  }

  async function placeBid(auctionId, amountTon) {
    const amount = String(amountTon).trim();
    if (!/^(?:0|[1-9][0-9]*)(?:\.[0-9]{1,9})?$/.test(amount)) {
      throw new Error("Введите сумму ставки в TON, максимум 9 знаков после запятой.");
    }
    const [whole, fraction = ""] = amount.split(".");
    const bidAmount = BigInt(whole) * 1000000000n + BigInt((fraction + "000000000").slice(0, 9));
    if (bidAmount <= 0n) throw new Error("Ставка должна быть больше нуля.");

    const { beginCell } = await loadTonCore();
    const body = beginCell()
      .storeUint(0x54474102, 32)
      .storeUint(randomQueryId(), 64)
      .storeUint(BigInt(auctionId), 64)
      .storeCoins(bidAmount)
      .endCell();
    return sendManagerMessage(body, bidAmount + 100000000n);
  }

  async function finishAuction(auctionId) {
    const { beginCell } = await loadTonCore();
    const body = beginCell()
      .storeUint(0x54474103, 32)
      .storeUint(randomQueryId(), 64)
      .storeUint(BigInt(auctionId), 64)
      .endCell();
    return sendManagerMessage(body, 200000000n);
  }

  window.tagitalSpaceRegistry = {
    lookupRussianPlate,
    createRussianAuction,
    listAuctions,
    placeBid,
    finishAuction
  };
})();
