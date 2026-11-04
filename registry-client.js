(() => {
  "use strict";

  const CONFIG_URL = new URL("contracts/testnet.config.json", document.baseURI);
  const TONCENTER_URL = "https://testnet.toncenter.com/api/v2/runGetMethod";

  function toHex(buffer) {
    return Array.from(new Uint8Array(buffer), byte => byte.toString(16).padStart(2, "0")).join("");
  }

  async function hashPlate(country, plate) {
    const canonical = country + "|" + plate.replace(/\\s+/g, "").toUpperCase();
    const bytes = new TextEncoder().encode(canonical);
    return toHex(await crypto.subtle.digest("SHA-256", bytes));
  }

  async function lookupRussianPlate(plate) {
    const configResponse = await fetch(CONFIG_URL, { cache: "no-store" });
    if (!configResponse.ok) throw new Error("Не удалось загрузить конфигурацию Testnet.");
    const config = await configResponse.json();

    if (config.network !== "testnet") throw new Error("Запрос заблокирован: разрешена только сеть TON Testnet.");
    const address = config.auction_manager;
    if (!address) {
      throw new Error("Поиск подключён к TON Testnet, но реестр ещё не развёрнут. Адрес Auction Manager появится здесь после сборки, тестирования и публикации контракта.");
    }

    const hash = await hashPlate("RU", plate);
    const response = await fetch(TONCENTER_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        address,
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

  window.tagitalSpaceRegistry = { lookupRussianPlate };
})();