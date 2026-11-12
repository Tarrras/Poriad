// Перший кадр: клас js вмикає анімації появи (.reveal). Якщо скрипт сторінки за 3 с не стартував (window.poriadReady
// ставить ui.js), клас знімаємо — і сторінка показує все без анімацій. Окремим файлом: CSP сайту не пускає inline.
document.documentElement.classList.add("js");
setTimeout(function () { if (!window.poriadReady) document.documentElement.classList.remove("js"); }, 3000);

// Меню шапки на вузькому екрані (details.nav-more) розкривається й без скрипта; тут лише закриваємо його: тапом повз,
// вибором пункту (якір на цій же сторінці лишив би аркуш відкритим поверх розділу) і Esc — з фокусом назад на кнопку.
document.addEventListener("click", function (e) {
  var open = document.querySelector(".nav-more[open]");
  if (open && (!open.contains(e.target) || e.target.closest(".nav-pop a"))) open.open = false;
});
document.addEventListener("keydown", function (e) {
  var open = document.querySelector(".nav-more[open]");
  if (e.key === "Escape" && open) { open.open = false; open.querySelector("summary").focus(); }
});
