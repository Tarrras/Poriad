// Куди веде QR-код сайту (poriad.app/app): одразу в стор телефона, на комп’ютері — на лендинг.
// Мітка джерела для App Store Connect і Play Console (див. poriad.js): QR — qr, сторінка події — ?from=event.
var ua = navigator.userAgent, from = new URLSearchParams(location.search).get("from") || "";
var ct = /^[a-z]{1,12}$/.test(from) ? from : "qr";
var ios = /iPhone|iPad|iPod/.test(ua) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
if (ios) location.replace("https://apps.apple.com/app/apple-store/id6813543772?pt=129478154&mt=8&ct=" + ct);
// Решта: Android — у Google Play, щойно його ввімкнено в poriad.js (PLAY_LIVE); поки ні, і на комп'ютері — лендинг.
// Звичайний скрипт, щоб iOS пішов у стор, не чекаючи модуля; import() — відносно цього файлу.
else import("./poriad.js?v=23").then(function (m) { location.replace((/Android/.test(ua) && m.playUrl(ct)) || "./#download"); });
