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

      heroTitle:
        "inTAG — цифровая коллекция номерных знаков со всего мира.",

      collectionEyebrow: "ИДЕЯ КОЛЛЕКЦИИ",
      collectionIntro:
        "inTAG объединяет отдельные коллекции, посвящённые разным странам. В каждой из них собраны номерные знаки, которые можно изучать, коллекционировать и получать в формате NFT.",

      collectionCardOneTitle: "Особенности стран",
      collectionCardOneText:
        "Номерные знаки отражают особенности каждой страны: собственные форматы, символы и обозначения регионов.",

      collectionCardTwoTitle: "Разнообразие сочетаний",
      collectionCardTwoText:
        "Каждое сочетание букв и цифр имеет свой вид и характер, благодаря чему номера отличаются друг от друга.",

      collectionCardThreeTitle: "Коллекция без границ",
      collectionCardThreeText:
        "Коллекция объединяет номерные знаки разных стран, позволяя увидеть их сходства и отличия.",

      systemTitle: "Как устроена коллекция",
      systemText:
        "Сначала пользователь выбирает нужную коллекцию, затем открывает её и знакомится с доступными номерами. Для получения свободного номера предусмотрен отдельный процесс минтинга.",

      flowAllTitle: "Все коллекции",
      flowAllNote: "Общее пространство inTAG",
      flowCountryTitle: "Коллекция страны",
      flowCountryNote: "Отдельный раздел",
      flowNftTitle: "Номерной знак",
      flowNftNote: "Отдельный NFT",

      auctionsEyebrow: "АУКЦИОНЫ",
      auctionsTitle: "Каждый свободный номер можно получить через торги",
      auctionsIntro:
        "Пользователь вводит желаемое сочетание символов. Система проверяет, свободен ли этот номер, и рассчитывает начальную ставку. Если номер доступен, его можно выставить на аукцион продолжительностью полтора часа.",
      auctionsDetail:
        "Начальная ставка будет зависеть от самого сочетания символов: чем привлекательнее номер, тем выше его стартовая стоимость. Это позволит учитывать интерес к разным экземплярам уже на этапе создания аукциона.",

      auctionStepOneTitle: "Ввод номера",
      auctionStepOneText:
        "Пользователь вводит сочетание символов для выбранной коллекции.",
      auctionStepTwoTitle: "Проверка и ставка",
      auctionStepTwoText:
        "Система проверяет наличие NFT и определяет начальную стоимость.",
      auctionStepThreeTitle: "Торги — 1,5 часа",
      auctionStepThreeText:
        "Участники делают ставки. Победивший забирает номер.",

      marketEyebrow: "РЫНОК",
      marketTitle: "Торговля между коллекционерами",
      marketIntro:
        "После получения NFT его владелец сможет предложить номер другим участникам. Покупатели смогут находить интересующие их экземпляры и приобретать их у текущих владельцев.",

      marketplaceLabel: "ВТОРИЧНЫЙ РЫНОК",
      marketplaceTitle: "Getgems — площадка для торговли NFT",
      marketplaceDescription:
        "Уже выпущенные номерные знаки можно будет покупать у их текущих владельцев на внешнем NFT-маркетплейсе.",
      marketplaceCardText:
        "Здесь размещаются NFT, выставленные владельцами на продажу.",
      marketplaceStepOneTitle: "Владелец выставляет номер",
      marketplaceStepOneText:
        "Текущий владелец предлагает свой NFT на Getgems.",
      marketplaceStepTwoTitle: "Покупатель выбирает NFT",
      marketplaceStepTwoText:
        "Другой пользователь находит подходящий номер.",
      marketplaceStepThreeTitle: "Покупка за TON",
      marketplaceStepThreeText:
        "Покупатель приобретает выставленный NFT за TON.",
      marketplacePaymentLabel: "Валюта покупки",

      communityEyebrow: "СООБЩЕСТВО",
      communityTitle: "Проект развивается вместе с участниками",
      communityIntro:
        "Сообщество — место, где можно следить за развитием inTAG, узнавать о новых сериях, обсуждать идеи и получать новости о важных изменениях проекта.",
      communityJoin: "Присоединиться к сообществу ↗",

      communityDiscussionTitle: "Обсуждения",
      communityDiscussionText: "Идеи и предложения участников",
      communityCountriesTitle: "Новые страны",
      communityCountriesText: "Предложения для будущей коллекции",
      communityNewsTitle: "Новости проекта",
      communityNewsText: "Анонсы, обновления и новые серии",

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

      heroTitle:
        "inTAG is a digital collection of license plates from around the world.",

      collectionEyebrow: "THE COLLECTION IDEA",
      collectionIntro:
        "inTAG brings together individual collections dedicated to different countries. Each one contains license plates that can be explored, collected, and obtained as NFTs.",

      collectionCardOneTitle: "Country characteristics",
      collectionCardOneText:
        "License plates reflect the characteristics of each country: its own formats, symbols, and regional designations.",

      collectionCardTwoTitle: "Variety of combinations",
      collectionCardTwoText:
        "Every combination of letters and numbers has its own appearance and character, making each plate different.",

      collectionCardThreeTitle: "A collection without borders",
      collectionCardThreeText:
        "The collection brings together license plates from different countries, making it possible to explore their similarities and differences.",

      systemTitle: "How the collection is organized",
      systemText:
        "First, a user chooses a collection and opens it to explore the available plates. A separate minting process is provided for obtaining an available plate.",

      flowAllTitle: "All collections",
      flowAllNote: "The inTAG collection space",
      flowCountryTitle: "Country collection",
      flowCountryNote: "An individual section",
      flowNftTitle: "License plate",
      flowNftNote: "An individual NFT",

      auctionsEyebrow: "AUCTIONS",
      auctionsTitle: "Every available plate can be obtained through bidding",
      auctionsIntro:
        "A user enters the desired character combination. The system checks whether the plate is available and calculates its starting bid. If the plate is available, it can be listed in an auction lasting one and a half hours.",
      auctionsDetail:
        "The starting bid will depend on the character combination itself: the more desirable the plate, the higher its starting price. This makes it possible to account for interest in different items from the moment an auction is created.",

      auctionStepOneTitle: "Enter a plate",
      auctionStepOneText:
        "The user enters a character combination for the selected collection.",
      auctionStepTwoTitle: "Check and starting bid",
      auctionStepTwoText:
        "The system checks whether the NFT exists and determines the starting price.",
      auctionStepThreeTitle: "Bidding — 1.5 hours",
      auctionStepThreeText:
        "Participants place bids. The winner takes the plate.",

      marketEyebrow: "MARKET",
      marketTitle: "Trading between collectors",
      marketIntro:
        "After obtaining an NFT, its owner will be able to offer the plate to other participants. Buyers will be able to find items they are interested in and purchase them from their current owners.",

      marketplaceLabel: "SECONDARY MARKET",
      marketplaceTitle: "Getgems — an NFT marketplace",
      marketplaceDescription:
        "Already issued license plates can be purchased from their current owners on an external NFT marketplace.",
      marketplaceCardText:
        "NFTs listed for sale by their owners are available here.",
      marketplaceStepOneTitle: "The owner lists a plate",
      marketplaceStepOneText:
        "The current owner offers their NFT on Getgems.",
      marketplaceStepTwoTitle: "The buyer chooses an NFT",
      marketplaceStepTwoText:
        "Another user finds a plate they want.",
      marketplaceStepThreeTitle: "Purchase with TON",
      marketplaceStepThreeText:
        "The buyer purchases the listed NFT using TON.",
      marketplacePaymentLabel: "Payment currency",

      communityEyebrow: "COMMUNITY",
      communityTitle: "The project grows with its participants",
      communityIntro:
        "The community is where people can follow inTAG's progress, learn about new series, discuss ideas, and get updates about important changes to the project.",
      communityJoin: "Join the community ↗",

      communityDiscussionTitle: "Discussions",
      communityDiscussionText: "Ideas and suggestions from participants",
      communityCountriesTitle: "New countries",
      communityCountriesText: "Suggestions for future collections",
      communityNewsTitle: "Project news",
      communityNewsText: "Announcements, updates, and new releases",

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