// poriad.app/ua.html: що бачить сайт у вбудованому браузері й куди ведуть «Відкрити в браузері» (перевірка 4 у
// docs/organizers-1.5.md). Обидва посилання — на цю ж сторінку: у справжньому браузері вона скаже «Ні».
import { inAppBrowser, browserLinks } from "./auth.js?v=13";

const links = browserLinks(location.href);
document.querySelector("[data-inapp]").textContent = inAppBrowser()
  ? "Так. Кнопку Google тут сховаємо й запропонуємо відкрити сторінку в браузері."
  : "Ні, звичайний браузер: вхід через Google працюватиме.";
document.querySelector("[data-ua]").textContent = navigator.userAgent;
document.querySelector("[data-android]").href = links.android;
document.querySelector("[data-ios]").href = links.ios;
