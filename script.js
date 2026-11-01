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
      heroTitle: "inTAG — цифровая коллекция номерных знаков со всего мира",
      collectionEyebrow: "КОЛЛЕКЦИЯ",
      collectionIntro: "Каждая страна представлена отдельной коллекцией со своим форматом номеров и региональными обозначениями.",
      auctionsEyebrow: "АУКЦИОНЫ",
      auctionsTitle: "Выберите номер и запустите аукцион",
      auctionsIntro: "Пользователь вводит желаемое сочетание символов. Система проверяет, свободен ли этот номер, и рассчитывает начальную ставку. Если номер доступен, его можно выставить на аукцион продолжительностью полтора часа.",
      auctionsDetail: "Начальная ставка будет зависеть от самого сочетания символов: чем привлекательнее номер, тем выше его стартовая стоимость.",
      auctionVisualCaption: "Победитель получает номерной знак после завершения торгов",
      marketEyebrow: "РЫНОК",
      marketTitle: "Вторичный рынок на Getgems",
      marketIntro: "Выпущенные NFT можно будет покупать и продавать на Getgems — внешнем маркетплейсе TON. Ссылки на Getgems можно найти в каждой коллекции",
      marketVisualCaption: "Покупайте и продавайте номерные знаки",
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
      auctionsDetail: "The starting bid depends on the character combination. Mirrored patterns, repeated characters, and sequential letters or numbers receive a higher starting bid.",
      auctionVisualCaption: "The winner receives the license plate NFT when the auction ends",
      marketEyebrow: "MARKET",
      marketTitle: "The secondary market on Getgems",
      marketIntro: "Issued NFTs will be available to buy and sell on Getgems, an external TON marketplace. You can find Getgems links in each collection.",
      marketVisualCaption: "Buy and sell license plates",
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