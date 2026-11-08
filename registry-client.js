(() => {
  "use strict";

  const CONFIG_URL = new URL("contracts/testnet.config.json", document.baseURI);
  const TONCENTER_URL = "https://testnet.toncenter.com/api/v2/runGetMethod";
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
    const digest = await crypto.subtle.digest("SHA-256", bytes);
    return Array.from(new Uint8Array(digest), byte =>
      byte.toString(16).padStart(2, "0")
    ).join("");
  }

  async function lookupRussianPlate(plate) {
    const config = await loadTestnetConfig();
    const canonicalPlate = canonicalRussianPlate(plate);
    const hash = await hashPlate("RU", canonicalPlate);
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

    const statusCode = BigInt(result.stack[0][1]);
    if (statusCode === 0n) return { status: "free" };
    if (statusCode === 2n) return { status: "minted" };
    if (statusCode === 1n) {
      const auctions = await listAuctions();
      const auction = auctions.find(item =>
        canonicalRussianPlate(item.plate) === canonicalPlate
      ) || null;
      return { status: "auction", auction };
    }
    return { status: "unknown" };
  }

  function logTonConnectFailure(stage, error, transaction) {
    const tonConnect = window.tagitalSpaceTonConnect;
    const wallet = tonConnect?.wallet;
    const details = {
      stage,
      errorName: error?.name,
      errorMessage: error?.message || String(error),
      errorCode: error?.code,
      errorData: error?.data,
      errorCause: error?.cause ? {
        name: error.cause.name,
        message: error.cause.message,
        code: error.cause.code,
        data: error.cause.data
      } : undefined,
      sdkErrorCodes: error?.constructor?.name,
      connected: Boolean(tonConnect?.connected),
      network: wallet?.account?.chain,
      walletApp: wallet?.device?.appName,
      walletVersion: wallet?.device?.appVersion,
      provider: wallet?.provider,
      transaction: transaction ? {
        validUntil: transaction.validUntil,
        messageCount: transaction.messages?.length,
        messages: transaction.messages?.map(message => ({
          address: message.address,
          amount: message.amount,
          hasPayload: Boolean(message.payload)
        }))
      } : undefined
    };

    console.group("[TagitalSpace] TON Connect transaction failed");
    console.error("Diagnostic details:", details);
    console.error("Original TON Connect error:", error);
    console.error("Original error JSON:", (() => {
      try {
        return JSON.stringify(error, Object.getOwnPropertyNames(error), 2);
      } catch {
        return String(error);
      }
    })());
    console.groupEnd();
  }

  async function sendTransactionWithDiagnostics(stage, tonConnect, transaction) {
    console.info("[TagitalSpace] Sending TON Connect transaction:", {
      stage,
      network: tonConnect?.wallet?.account?.chain,
      walletApp: tonConnect?.wallet?.device?.appName,
      provider: tonConnect?.wallet?.provider,
      messageCount: transaction.messages?.length,
      destination: transaction.messages?.[0]?.address,
      amount: transaction.messages?.[0]?.amount,
      validUntil: transaction.validUntil
    });

    try {
      const result = await tonConnect.sendTransaction(transaction);
      console.info("[TagitalSpace] TON Connect transaction request returned successfully:", stage);
      return result;
    } catch (error) {
      logTonConnectFailure(stage, error, transaction);
      throw error;
    }
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

    const transaction = {
      validUntil: now + 600,
      messages: [{
        address: config.auction_manager,
        amount: AUCTION_CREATE_AMOUNT,
        payload: payload.toBoc().toString("base64")
      }]
    };
    const result = await sendTransactionWithDiagnostics(
      "create-russian-auction",
      tonConnect,
      transaction
    );

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

  async function decodeAuctionSummary(summary) {
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
    return { auctionId: itemIndex, itemIndex, plate, startingBid, minimumBidStep, endTime, highestBid, status };
  }

  async function getAuctionSummary(auctionId) {
    const stack = await runGetMethod("get_auction_summary", [["num", "0x" + BigInt(auctionId).toString(16)]]);
    const item = stack[0];
    if (!item || item[0] !== "cell" || !item[1]) return null;
    const cellBoc = typeof item[1] === "string" ? item[1] : item[1].bytes;
    if (!cellBoc) throw new Error("TON Testnet вернул некорректные данные аукциона.");
    const { Cell } = await loadTonCore();
    return decodeAuctionSummary(Cell.fromBase64(cellBoc));
  }

  async function listAuctions() {
    const stack = await runGetMethod("get_active_auctions");
    const item = stack[0];
    if (!item || item[0] !== "cell" || !item[1]) return [];
    const cellBoc = typeof item[1] === "string" ? item[1] : item[1].bytes;
    if (!cellBoc) throw new Error("TON Testnet вернул некорректный список аукционов.");
    const { Cell } = await loadTonCore();
    const auctions = [];
    let current = Cell.fromBase64(cellBoc);
    while (current) {
      const node = current.beginParse();
      if (node.remainingRefs === 0) break;
      if (node.remainingRefs !== 2) {
        throw new Error("Реестр вернул некорректный список аукционов.");
      }
      const summary = node.loadRef();
      current = node.loadRef();
      auctions.push(await decodeAuctionSummary(summary));
    }
    return auctions.sort((a, b) => a.endTime - b.endTime);
  }

  async function waitForAuction(plate, timeoutMs = 90000) {
    const deadline = Date.now() + timeoutMs;
    let lastError = null;
    while (Date.now() < deadline) {
      try {
        const lookup = await lookupRussianPlate(plate);
        if (lookup.status === "auction" && lookup.auction) return lookup.auction;
      } catch (error) {
        lastError = error;
      }
      await new Promise(resolve => setTimeout(resolve, 2500));
    }
    const error = new Error(
      "Аукцион мог уже создаться, но подтверждение пока не появилось в реестре. Не запускайте его повторно — обновите поиск через несколько секунд."
    );
    error.cause = lastError;
    error.auctionCreated = true;
    throw error;
  }

  async function startRussianAuctionWithFirstBid(plate) {
    await createRussianAuction(plate);
    let auction;
    try {
      auction = await waitForAuction(plate);
    } catch (error) {
      error.auctionCreated = true;
      throw error;
    }

    try {
      await placeBid(auction.auctionId, "1");
      await waitForBid(auction.auctionId, STARTING_BID);
    } catch (error) {
      error.auctionCreated = true;
      throw error;
    }

    return { auctionId: auction.auctionId, endTime: auction.endTime };
  }

  async function sendManagerMessage(body, attachedAmount) {
    const config = await loadTestnetConfig();
    const tonConnect = window.tagitalSpaceTonConnect;
    if (!tonConnect?.wallet) throw new Error("Сначала подключите TON-кошелёк.");
    if (tonConnect.wallet.account.chain !== "-3") {
      throw new Error("Для участия в аукционе подключите кошелёк к TON Testnet.");
    }
    const now = Math.floor(Date.now() / 1000);
    const transaction = {
      validUntil: now + 600,
      messages: [{
        address: config.auction_manager,
        amount: attachedAmount.toString(),
        payload: body.toBoc().toString("base64")
      }]
    };
    return sendTransactionWithDiagnostics(
      "auction-manager-message",
      tonConnect,
      transaction
    );
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

  async function waitForBid(auctionId, expectedBid, timeoutMs = 60000) {
    const deadline = Date.now() + timeoutMs;
    let lastError = null;
    while (Date.now() < deadline) {
      try {
        const auction = await getAuctionSummary(auctionId);
        if (auction && auction.highestBid >= expectedBid) return auction;
      } catch (error) {
        lastError = error;
      }
      await new Promise(resolve => setTimeout(resolve, 2500));
    }
    const error = new Error(
      "Первая ставка отправлена, но её подтверждение пока не появилось в сети. Проверьте статус номера повторным поиском."
    );
    error.cause = lastError;
    error.bidSubmitted = true;
    throw error;
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
    startRussianAuctionWithFirstBid,
    listAuctions,
    placeBid,
    finishAuction
  };
})();
