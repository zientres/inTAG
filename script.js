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
    "inTAG: не найдены элементы HTML:",
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
      pageTitle: "inTAG",
      navCollection: "Коллекции",
      navAuctions: "Аукционы",
      navMarket: "Рынок",
      navCommunity: "Сообщество",
      connectWallet: "Подключить кошелёк",
      settingsTitle: "Настройки",
      languageLabel: "Язык сайта",
      heroTitle: "inTAG — цифровая NFT-коллекция номерных знаков со всего мира.",
      collectionEyebrow: "КОЛЛЕКЦИЯ",
      collectionIntro: "Коллекции сгруппированы по странам. В каждой собраны номерные знаки с характерными для неё форматами и обозначениями.",
      auctionsEyebrow: "АУКЦИОНЫ",
      auctionsTitle: "Выберите номер и запустите аукцион",
      auctionsIntro: "Введите номер в поиске коллекции. Система проверит его историю: если NFT уже существует, покажет сведения о нём и текущем владельце. Если такого NFT ещё нет, можно будет создать аукцион.",
      auctionsDetail: "Начальная ставка зависит от сочетания символов. Зеркальные комбинации, повторяющиеся цифры и последовательности букв или цифр будут оцениваться выше.",
      auctionSummaryLabel: "ОТКРЫТЫЕ ТОРГИ",
      auctionSummaryHours: "часа",
      auctionSummaryText: "После запуска аукцион становится доступен всем участникам. Победитель получает номерной знак.",
      marketEyebrow: "РЫНОК",
      marketTitle: "Вторичный рынок на Getgems",
      marketIntro: "Полученный номерной знак можно будет выставить на продажу на Getgems. Другие пользователи смогут приобрести его напрямую у текущего владельца.",
      marketplaceLabel: "МАРКЕТПЛЕЙС TON",
      marketplaceTitle: "Коллекции inTAG на Getgems",
      marketplaceDescription: "На Getgems будут размещены коллекции проекта. Ссылки на них появятся здесь позже.",
      marketplaceCardText: "Покупка и продажа номерных знаков между владельцами.",
      communityEyebrow: "СООБЩЕСТВО",
      communityTitle: "Следите за развитием inTAG",
      communityIntro: "В Telegram-канале будут выходить новости о ходе проекта, важных обновлениях и новых коллекциях.",
      communityJoin: "Telegram-канал скоро откроется",
      openSettings: "Открыть настройки",
      closeSettings: "Закрыть настройки",
      homeAria: "inTAG — главная",
      logoAlt: "Логотип inTAG",
      plateAria: "Номерной знак",
      progressAria: "Смена номерного знака"
    },

    en: {
      pageTitle: "inTAG",
      navCollection: "Collections",
      navAuctions: "Auctions",
      navMarket: "Market",
      navCommunity: "Community",
      connectWallet: "Connect wallet",
      settingsTitle: "Settings",
      languageLabel: "Website language",
      heroTitle: "inTAG is a digital NFT collection of license plates from around the world.",
      collectionEyebrow: "THE COLLECTION",
      collectionIntro: "Collections are grouped by country. Each one brings together plates with formats and designations characteristic of that country.",
      auctionsEyebrow: "AUCTIONS",
      auctionsTitle: "Choose a plate and start an auction",
      auctionsIntro: "Enter a plate number in the collection search. The system checks its history: if the NFT already exists, its details and current owner will be shown. If it does not exist yet, an auction can be created.",
      auctionsDetail: "The starting bid depends on the character combination. Mirrored patterns, repeated digits, and sequences of letters or numbers will have higher starting bids.",
      auctionSummaryLabel: "OPEN AUCTION",
      auctionSummaryHours: "hours",
      auctionSummaryText: "Once launched, the auction is open to all participants. The winner receives the license plate NFT.",
      marketEyebrow: "MARKET",
      marketTitle: "The secondary market on Getgems",
      marketIntro: "An acquired license plate can be listed for sale on Getgems. Other users will be able to buy it directly from its current owner.",
      marketplaceLabel: "TON MARKETPLACE",
      marketplaceTitle: "inTAG collections on Getgems",
      marketplaceDescription: "The project's collections will be available on Getgems. Links will appear here later.",
      marketplaceCardText: "Buy and sell license plates directly between owners.",
      communityEyebrow: "COMMUNITY",
      communityTitle: "Follow the progress of inTAG",
      communityIntro: "The Telegram channel will feature project updates, important announcements, and news about new collections.",
      communityJoin: "Telegram channel coming soon",
      openSettings: "Open settings",
      closeSettings: "Close settings",
      homeAria: "inTAG — Home",
      logoAlt: "inTAG logo",
      plateAria: "License plate",
      progressAria: "License plate rotation"
    }
  };

  const drawer = document.getElementById("settings-drawer");
  const overlay = document.getElementById("settings-overlay");
  const openButton = document.getElementById("settings-open");
  const closeButton = document.getElementById("settings-close");
  const languageButtons = document.querySelectorAll("[data-language]");

  if (!drawer || !overlay || !openButton || !closeButton) {
    console.error("inTAG: не найдены элементы меню настроек.");
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
    document.title = dictionary.pageTitle;

    document.querySelectorAll("[data-i18n]").forEach((element) => {
      const key = element.dataset.i18n;

      if (dictionary[key] !== undefined) {
        element.textContent = dictionary[key];
      }
    });

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
})();