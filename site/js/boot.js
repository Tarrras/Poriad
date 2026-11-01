// Перший кадр: клас js вмикає анімації появи (.reveal). Якщо скрипт сторінки за 3 с не стартував (window.poriadReady
// ставить ui.js), клас знімаємо — і сторінка показує все без анімацій. Окремим файлом: CSP сайту не пускає inline.
document.documentElement.classList.add("js");
setTimeout(function () { if (!window.poriadReady) document.documentElement.classList.remove("js"); }, 3000);
