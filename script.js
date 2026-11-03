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
      auctionsIntro: "Пользователь вводит желаемое сочетание символов. Система проверяет, свободен ли этот номер, и рассчитывает начальную ставку. Если номер доступен, его можно выставить на аукцион продолжительностью полтора часа.",
      auctionsDetail: "Начальная ставка будет зависеть от самого сочетания символов: чем привлекательнее номер, тем выше его стартовая стоимость.",
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
      progressAria: "Смена номерного знака"
    },

    en: {
      pageTitle: "TagitalSpace",
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
      auctionsIntro: "The user enters the desired combination of characters. The system checks whether the plate number is available and calculates the starting bid. If the number is available, it can be listed in an auction lasting one and a half hours.",
      auctionsDetail: "The starting bid will depend on the character combination: the more attractive the number, the higher its starting price.",
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
      progressAria: "License plate rotation"
    }
  };

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

/* Интерактивная коллекция России и тестовый аукцион */
(() => {
  function initRussianCollection() {
    const catalog = document.getElementById("collections-catalog");
    const collection = document.getElementById("russia-collection");
    const backButton = document.getElementById("back-to-collections");
    const startButton = document.getElementById("start-test-auction");
    const stopButton = document.getElementById("stop-test-auction");
    const digitElements = Array.from(document.querySelectorAll(".timer-digit"));
    const registrationInput = document.getElementById("registration-number");
    const registrationCells = Array.from(document.querySelectorAll(".registration-cell"));
    if (!catalog || !collection) return;

    const searchForm = document.getElementById("registration-search");
    const searchButton = document.getElementById("registration-search-button");
    const hint = document.getElementById("registration-hint");
    if (registrationInput && registrationCells.length === 9) {
      const allowedLetters = "АВЕКМНОРСТУХ";
      const allowedDigits = "0123456789";
      const latinToCyrillic = { A:"А", B:"В", E:"Е", K:"К", M:"М", H:"Н", O:"О", P:"Р", C:"С", T:"Т", Y:"У", X:"Х" };
      let hintTimeout = null;
      function showHint() {
        if (!hint) return;
        hint.hidden = false;
        clearTimeout(hintTimeout);
        hintTimeout = setTimeout(() => { hint.hidden = true; }, 3000);
      }
      function normalizeChar(char, position) {
        const upper = char.toLocaleUpperCase("ru-RU");
        const normalized = latinToCyrillic[upper] || upper;
        return [0,4,5].includes(position)
          ? (allowedLetters.includes(normalized) ? normalized : "")
          : (allowedDigits.includes(normalized) ? normalized : "");
      }
      function formatRegistration(value) {
        let result = "";
        let invalidLetter = false;
        for (const char of value) {
          if (char === " " || char === "-" || char === "_") continue;
          const pos = result.length;
          if (pos >= 9) break;
          const normalized = normalizeChar(char,pos);
          if (normalized) result += normalized;
          else if (/[A-Za-zА-Яа-яЁё]/.test(char)) invalidLetter = true;
        }
        if (invalidLetter) showHint();
        return result;
      }
      function renderRegistration() {
        const value = registrationInput.value;
        registrationCells.forEach((cell,index) => {
          const char = value[index] || "";
          cell.textContent = char;
          cell.classList.toggle("is-filled",Boolean(char));
          cell.classList.toggle("is-active",index === value.length && value.length < 9);
        });
        if (searchButton) searchButton.hidden = value.length !== 9;
      }
      registrationInput.addEventListener("input",() => {
        const formatted = formatRegistration(registrationInput.value);
        if (registrationInput.value !== formatted) {
          const cursor = Math.min(formatted.length,registrationInput.selectionStart || formatted.length);
          registrationInput.value = formatted;
          registrationInput.setSelectionRange(cursor,cursor);
        }
        renderRegistration();
      });
      registrationInput.addEventListener("keydown",event => {
        if (["ArrowLeft","ArrowRight","Home","End","Backspace","Delete","Tab","Enter"].includes(event.key)) return;
        if (event.key.length === 1 && !/[A-Za-zА-Яа-яЁё0-9 _-]/.test(event.key)) event.preventDefault();
      });
      registrationInput.addEventListener("focus",renderRegistration);
      registrationInput.addEventListener("blur",() => registrationCells.forEach(cell => cell.classList.remove("is-active")));
      searchForm?.addEventListener("submit",event => {
        event.preventDefault();
        if (registrationInput.value.length !== 9) return;
        // Дальнейшее действие поиска будет добавлено отдельно.
      });
      renderRegistration();
    }

    document.addEventListener("click", (event) => {
      const card = event.target.closest("#open-russia-collection");
      if (!card) return;
      event.preventDefault();
      catalog.hidden = true;
      collection.hidden = false;
      collection.scrollIntoView({ behavior: "smooth", block: "start" });
    });

    backButton?.addEventListener("click", () => {
      collection.hidden = true;
      catalog.hidden = false;
      window.scrollTo({ top: 0, behavior: "smooth" });
    });

    let remainingSeconds = 90 * 60;
    let auctionInterval = null;
    function renderTimer(animate = false) {
      const hours = Math.floor(remainingSeconds / 3600);
      const minutes = Math.floor((remainingSeconds % 3600) / 60);
      const seconds = remainingSeconds % 60;
      const value = String(hours).padStart(2, "0") + String(minutes).padStart(2, "0") + String(seconds).padStart(2, "0");

      digitElements.forEach((element, index) => {
        const nextDigit = value[index];
        let currentDigit = element.querySelector(".timer-digit-current");
        if (!currentDigit) {
          element.innerHTML = '<span class="timer-digit-current"></span>';
          currentDigit = element.firstElementChild;
          currentDigit.textContent = nextDigit;
          return;
        }
        if (currentDigit.textContent === nextDigit) return;

        if (!animate) {
          element.classList.remove("is-rolling");
          element.innerHTML = '<span class="timer-digit-current"></span>';
          element.firstElementChild.textContent = nextDigit;
          return;
        }

        element.classList.remove("is-rolling");
        const oldDigit = element.querySelector(".timer-digit-current");
        const newDigit = document.createElement("span");
        newDigit.className = "timer-digit-next";
        newDigit.textContent = nextDigit;
        element.appendChild(newDigit);
        void element.offsetWidth;
        element.classList.add("is-rolling");
        window.setTimeout(() => {
          element.classList.remove("is-rolling");
          element.innerHTML = '<span class="timer-digit-current"></span>';
          element.firstElementChild.textContent = nextDigit;
        }, 260);
      });
    }
    function stopAuction() {
      if (auctionInterval !== null) { clearInterval(auctionInterval); auctionInterval = null; }
      if (stopButton) stopButton.disabled = true;
    }
    startButton?.addEventListener("click", () => {
      if (auctionInterval !== null) return;
      if (remainingSeconds <= 0) remainingSeconds = 90 * 60;
      if (stopButton) stopButton.disabled = false;
      renderTimer();
      auctionInterval = setInterval(() => {
        remainingSeconds = Math.max(0, remainingSeconds - 1);
        renderTimer(true);
        if (remainingSeconds === 0) stopAuction();
      }, 1000);
    });
    stopButton?.addEventListener("click", stopAuction);
    renderTimer();
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", initRussianCollection, { once: true });
  else initRussianCollection();
})();
