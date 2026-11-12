"use strict";

/* Номерные знаки */

const plates = [
  {
    prefix: "",
    number: "А777АА",
    region: "77",
    regionCountry: "RUS",
    className: "plate--ru"
  },
  {
    prefix: "KZ",
    number: "777ААА",
    region: "07",
    regionCountry: "",
    className: "plate--kz"
  }
];

const DISPLAY_TIME = 3000;
const FADE_TIME = 300;

const elements = {
  plate: document.getElementById("license-plate"),
  prefix: document.getElementById("plate-prefix"),
  number: document.getElementById("plate-main"),
  region: document.getElementById("plate-region"),
  regionCountry: document.getElementById("plate-region-country"),
  progressBar: document.getElementById("plate-progress-bar")
};

const missingElements = Object.entries(elements)
  .filter(([, element]) => !element)
  .map(([name]) => name);

if (missingElements.length > 0) {
  console.error(
    "TagitalSpace: не найдены элементы HTML:",
    missingElements.join(", ")
  );
} else {
  let currentPlateIndex = 0;
  let changeTimer = null;
  let isChanging = false;

  function renderPlate(item) {
    elements.prefix.textContent = item.prefix;
    elements.prefix.hidden = item.prefix === "";

    elements.number.textContent = item.number;
    elements.region.textContent = item.region;
    elements.regionCountry.textContent = item.regionCountry;

    elements.regionCountry.style.display =
      item.regionCountry ? "flex" : "none";

    elements.plate.classList.remove("plate--ru", "plate--kz");
    elements.plate.classList.add(item.className);

    elements.plate.setAttribute(
      "aria-label",
      item.regionCountry
        ? `${item.number}, регион ${item.region}, ${item.regionCountry}`
        : `${item.prefix} ${item.number}, регион ${item.region}`
    );

    elements.number.style.opacity = "1";
    elements.region.style.opacity = "1";
  }

  function startProgress() {
    elements.progressBar.classList.remove("play");
    void elements.progressBar.offsetWidth;
    elements.progressBar.classList.add("play");
  }

  function scheduleNextPlate() {
    clearTimeout(changeTimer);

    changeTimer = setTimeout(
      nextPlate,
      DISPLAY_TIME - FADE_TIME
    );
  }

  function nextPlate() {
    if (isChanging) return;

    isChanging = true;

    elements.number.style.opacity = "0";
    elements.region.style.opacity = "0";

    changeTimer = setTimeout(() => {
      currentPlateIndex =
        (currentPlateIndex + 1) % plates.length;

      renderPlate(plates[currentPlateIndex]);
      startProgress();

      isChanging = false;
      scheduleNextPlate();
    }, FADE_TIME);
  }

  renderPlate(plates[currentPlateIndex]);
  startProgress();
  scheduleNextPlate();
}

/* Настройки и смена языка */

(() => {
  const translations = {
    ru: {
      pageTitle: "TagitalSpace",
      collectionPageTitle: "TagitalSpace — Коллекции", communityPageTitle: "TagitalSpace — Сообщество", auctionsPageTitle: "TagitalSpace — Аукционы",
      navCollection: "Коллекции",
      navAuctions: "Аукционы",
      navMarket: "Рынок",
      navCommunity: "Сообщество",
      connectWallet: "Подключить кошелёк",
      settingsTitle: "Настройки",
      languageLabel: "Язык сайта",
      heroTitle: "TagitalSpace — цифровое пространство коллекций номерных знаков со всего мира",
      collectionEyebrow: "КОЛЛЕКЦИИ",
      collectionIntro: "Каждая страна представлена отдельной коллекцией со своим форматом номерных знаков",
      auctionsEyebrow: "АУКЦИОНЫ",
      auctionsTitle: "Выберите номер и запустите аукцион",
      auctionsIntro: "Пользователь вводит желаемое сочетание символов. Система проверяет, свободен ли номер в реестре TagitalSpace. Любой пользователь может запустить аукцион со своего кошелька: начальная ставка — 1 TON, минимальный шаг — 0.1 TON, продолжительность — 90 минут.",
      auctionsDetail: "После запуска аукциона любой пользователь может предложить более высокую ставку. Победитель получает NFT с выбранным номерным знаком.",
      refreshAuctions: "Обновить",
      loadingAuctions: "Загружаю аукционы…",
      noActiveAuctions: "Сейчас нет активных аукционов.",
      auctionLoadError: "Не удалось загрузить аукционы.",
      auctionStartingBid: "Начальная ставка",
      auctionHighestBid: "Текущая ставка",
      auctionNextBid: "Минимальная следующая ставка",
      auctionEnds: "Окончание",
      auctionBidPlaceholder: "Сумма в TON",
      auctionBidButton: "Сделать ставку",
      auctionFinishButton: "Завершить аукцион",
      auctionStatusActive: "Торги идут",
      auctionStatusMint: "Подтверждается выпуск NFT",
      auctionStatusSkip: "Завершается без ставок",
      auctionBidSent: "Запрос ставки отправлен в кошелёк.",
      auctionFinishSent: "Запрос завершения отправлен в кошелёк.",
      auctionBidError: "Не удалось отправить ставку.",
      auctionFinishError: "Не удалось завершить аукцион.",
      auctionVisualCaption: "Победитель получает номерной знак после завершения торгов",
      marketEyebrow: "РЫНОК",
      marketTitle: "Вторичный рынок на Getgems",
      marketIntro: "Выпущенные NFT можно будет покупать и продавать на Getgems — внешнем маркетплейсе TON. Ссылки на Getgems можно найти в каждой коллекции.",
      marketVisualCaption: "Покупайте и продавайте номерные знаки",
      communityEyebrow: "СООБЩЕСТВО",
      communityTitle: "Следите за развитием TagitalSpace",
      communityIntro: "В Telegram-канале будут выходить новости о ходе проекта, важных обновлениях и новых коллекциях.",
      communityJoin: "Telegram-канал",
      openSettings: "Открыть настройки",
      closeSettings: "Закрыть настройки",
      homeAria: "TagitalSpace — главная",
      logoAlt: "Логотип TagitalSpace",
      plateAria: "Номерной знак",
      progressAria: "Смена номерного знака", countryRussia: "Россия", openRussiaCollection: "Открыть коллекцию России", backToCollections: "Вернуться к коллекциям", collectionSections: "Разделы коллекции", tabMint: "Минт", tabAuctions: "Аукционы", tabMarket: "Рынок", registerRussiaPlate: "Зарегистрировать номерной знак России", registrationSubtitle: "Вводите комбинацию вашего номера в поле снизу", plateInputLabel: "Введите номер в формате А777АА 777", viewRegions: "Посмотреть регионы России", invalidLettersHint: "Используйте русские буквы: А В Е К М Н О Р С Т У Х", search: "Поиск", regionCodesDialog: "Коды регионов России", close: "Закрыть", regionCodesImageAlt: "Таблица разрешённых автомобильных кодов регионов России", invalidRegion: "Такого кода региона нет в списке"
    },

    en: {
      pageTitle: "TagitalSpace",
      collectionPageTitle: "TagitalSpace — Collections", communityPageTitle: "TagitalSpace — Community", auctionsPageTitle: "TagitalSpace — Auctions",
      navCollection: "Collections",
      navAuctions: "Auctions",
      navMarket: "Market",
      navCommunity: "Community",
      connectWallet: "Connect wallet",
      settingsTitle: "Settings",
      languageLabel: "Website language",
      heroTitle: "TagitalSpace — a digital space for license plate collections from around the world",
      collectionEyebrow: "COLLECTIONS",
      collectionIntro: "Each country is represented by a separate collection with its own license plate format",
      auctionsEyebrow: "AUCTIONS",
      auctionsTitle: "Choose a plate and start an auction",
      auctionsIntro: "The user enters a desired plate combination. The registry checks whether it is available. Anyone can start an auction from their wallet: the starting bid is 1 TON, the minimum increment is 0.1 TON, and the auction lasts 90 minutes.",
      auctionsDetail: "After an auction starts, anyone can place a higher bid. The winner receives an NFT of the selected license plate.",
      refreshAuctions: "Refresh",
      loadingAuctions: "Loading auctions…",
      noActiveAuctions: "There are no active auctions right now.",
      auctionLoadError: "Could not load auctions.",
      auctionStartingBid: "Starting bid",
      auctionHighestBid: "Current bid",
      auctionNextBid: "Minimum next bid",
      auctionEnds: "Ends",
      auctionBidPlaceholder: "Amount in TON",
      auctionBidButton: "Place bid",
      auctionFinishButton: "Finish auction",
      auctionStatusActive: "Bidding is open",
      auctionStatusMint: "NFT mint confirmation pending",
      auctionStatusSkip: "Closing without bids",
      auctionBidSent: "Bid request sent to your wallet.",
      auctionFinishSent: "Finish request sent to your wallet.",
      auctionBidError: "Could not submit the bid.",
      auctionFinishError: "Could not finish the auction.",
      auctionVisualCaption: "The winner receives the license plate NFT when the auction ends",
      marketEyebrow: "MARKET",
      marketTitle: "The secondary market on Getgems",
      marketIntro: "Issued NFTs will be available to buy and sell on Getgems — an external TON marketplace. You can find Getgems links in each collection.",
      marketVisualCaption: "Buy and sell license plates",
      communityEyebrow: "COMMUNITY",
      communityTitle: "Follow the progress of TagitalSpace",
      communityIntro: "The Telegram channel will feature project updates, important announcements, and news about new collections.",
      communityJoin: "Telegram channel",
      openSettings: "Open settings",
      closeSettings: "Close settings",
      homeAria: "TagitalSpace — Home",
      logoAlt: "TagitalSpace logo",
      plateAria: "License plate",
      progressAria: "License plate rotation", countryRussia: "Russia", openRussiaCollection: "Open the Russia collection", backToCollections: "Back to collections", collectionSections: "Collection sections", tabMint: "Mint", tabAuctions: "Auctions", tabMarket: "Market", registerRussiaPlate: "Register a Russian license plate", registrationSubtitle: "Enter your plate combination in the field below", plateInputLabel: "Enter a plate in the format A777AA 777", viewRegions: "View Russian region codes", invalidLettersHint: "Use Russian letters: А В Е К М Н О Р С Т У Х", search: "Search", regionCodesDialog: "Russian region codes", close: "Close", regionCodesImageAlt: "Table of permitted Russian vehicle registration region codes", invalidRegion: "This region code is not in the list"
    }
  };

  const walletButton = document.getElementById("connect-wallet");
  let connectedWalletAddress = null;

  const drawer = document.getElementById("settings-drawer");
  const overlay = document.getElementById("settings-overlay");
  const openButton = document.getElementById("settings-open");
  const closeButton = document.getElementById("settings-close");
  const languageButtons = document.querySelectorAll("[data-language]");

  if (!drawer || !overlay || !openButton || !closeButton) {
    console.error("TagitalSpace: не найдены элементы меню настроек.");
    return;
  }

  function openSettings() {
    drawer.inert = false;
    drawer.setAttribute("aria-hidden", "false");
    overlay.setAttribute("aria-hidden", "false");
    overlay.classList.add("is-open");
    drawer.classList.add("is-open");
    document.body.classList.add("settings-open");
    openButton.setAttribute("aria-expanded", "true");

    closeButton.focus({ preventScroll: true });
  }

  function closeSettings() {
    drawer.classList.remove("is-open");
    overlay.classList.remove("is-open");
    document.body.classList.remove("settings-open");
    drawer.setAttribute("aria-hidden", "true");
    overlay.setAttribute("aria-hidden", "true");
    drawer.inert = true;
    openButton.setAttribute("aria-expanded", "false");

    openButton.focus({ preventScroll: true });
  }

  function setLanguage(language) {
    const dictionary = translations[language];
    if (!dictionary) return;

    document.documentElement.lang = language;
    const titleKey = document.querySelector("title")?.dataset.i18n;
    document.title = titleKey && dictionary[titleKey] ? dictionary[titleKey] : dictionary.pageTitle;

    document.querySelectorAll("[data-i18n]").forEach((element) => {
      const key = element.dataset.i18n;
      if (dictionary[key] !== undefined) element.textContent = dictionary[key];
    });
    ["aria-label", "alt", "placeholder", "title"].forEach((attribute) => {
      const dataAttribute = `data-i18n-${attribute}`;
      document.querySelectorAll(`[${dataAttribute}]`).forEach((element) => {
        const key = element.getAttribute(dataAttribute);
        if (dictionary[key] !== undefined) element.setAttribute(attribute, dictionary[key]);
      });
    });
    const registrationHint = document.getElementById("registration-hint");
    if (registrationHint && dictionary.invalidLettersHint) registrationHint.textContent = dictionary.invalidLettersHint;
    const invalidRegionCell = document.querySelector(".registration-region-cell.is-invalid");
    if (invalidRegionCell && dictionary.invalidRegion) invalidRegionCell.setAttribute("title", dictionary.invalidRegion);

    document.querySelector(".brand")?.setAttribute(
      "aria-label",
      dictionary.homeAria
    );

    document.querySelector(".brand-logo")?.setAttribute(
      "alt",
      dictionary.logoAlt
    );

    openButton.setAttribute("aria-label", dictionary.openSettings);
    closeButton.setAttribute("aria-label", dictionary.closeSettings);
    drawer.setAttribute("aria-label", dictionary.settingsTitle);

    document.getElementById("license-plate")?.setAttribute(
      "aria-label",
      dictionary.plateAria
    );

    document.querySelector(".plate-progress")?.setAttribute(
      "aria-label",
      dictionary.progressAria
    );

    languageButtons.forEach((button) => {
      const active = button.dataset.language === language;

      button.classList.toggle("is-active", active);
      button.setAttribute("aria-pressed", String(active));
    });

    if (walletButton) {
      walletButton.textContent = connectedWalletAddress || dictionary.connectWallet;
    }

    if (window.tagitalSpaceTonConnect) {
      window.tagitalSpaceTonConnect.uiOptions = {
        language,
        uiPreferences: { theme: "DARK" }
      };
    }
  }

  openButton.addEventListener("click", openSettings);
  closeButton.addEventListener("click", closeSettings);
  overlay.addEventListener("click", closeSettings);

  languageButtons.forEach((button) => {
    button.addEventListener("click", () => {
      setLanguage(button.dataset.language);
    });
  });

  document.addEventListener("keydown", (event) => {
    if (
      event.key === "Escape" &&
      drawer.classList.contains("is-open")
    ) {
      closeSettings();
    }
  });

  setLanguage("ru");

  /* TON Connect — только тестовая сеть TON Testnet */
  if (walletButton && window.TON_CONNECT_UI?.TonConnectUI) {
    try {
      const manifestUrl = new URL("tonconnect-manifest.json", document.baseURI).href;
      const tonConnectUI = new window.TON_CONNECT_UI.TonConnectUI({ manifestUrl });

      // Сеть фиксируется до открытия окна выбора кошелька.
      tonConnectUI.setConnectionNetwork("-3");
      tonConnectUI.uiOptions = {
        language: document.documentElement.lang || "ru",
        uiPreferences: { theme: "DARK" }
      };

      walletButton.addEventListener("click", async () => {
        if (tonConnectUI.wallet) {
          walletButton.disabled = true;
          try {
            await tonConnectUI.disconnect();
          } catch (error) {
            console.error("TagitalSpace: не удалось отключить TON-кошелёк.", error);
          } finally {
            walletButton.disabled = false;
          }
          return;
        }
        tonConnectUI.openModal();
      });

      tonConnectUI.onStatusChange((wallet) => {
        if (!wallet) {
          connectedWalletAddress = null;
          walletButton.removeAttribute("title");
        } else if (wallet.account.chain !== "-3") {
          console.error("TagitalSpace: подключён не TON Testnet. Соединение будет закрыто.");
          tonConnectUI.disconnect();
          return;
        } else {
          const address = wallet.account.address;
          connectedWalletAddress = address.length > 13
            ? address.slice(0, 6) + "..." + address.slice(-4)
            : address;
          walletButton.title = address + " — нажмите, чтобы отключить кошелёк";
        }

        const language = document.documentElement.lang || "ru";
        walletButton.textContent =
          connectedWalletAddress || translations[language]?.connectWallet || translations.ru.connectWallet;
      });

      window.tagitalSpaceTonConnect = tonConnectUI;
    } catch (error) {
      console.error("TagitalSpace: не удалось запустить TON Connect для Testnet.", error);
    }
  } else if (walletButton) {
    console.error("TagitalSpace: библиотека TON Connect UI не загрузилась.");
  }
})();
