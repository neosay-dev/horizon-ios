Horizon iOS 0.2.1: производительность, защита от перегрева и удобнее моды.

### Новое
- Игра собрана с LTO (профиль `ios`): быстрее на процессоре
- 120 Гц на iPhone с ProMotion (раньше iOS держала игру на 60 Гц)
- Настройки → «Режим производительности»: мир рисуется в 75 % разрешения и поднимается до 100 %, пока хватает кадров (включён по умолчанию)
- Настройки → «Генерация кадров» (FSR 3.1), выключена по умолчанию
- Настройки → «Защита от перегрева»: на горячем телефоне дальность прорисовки временно 6 или 4 чанка, потом возвращается
- Моды: вкладка «В игре» открывается первой, кнопки «Включить все» и «Выключить все» для Rust-модов
- Вкладки лаунчера крупнее, с откликом при переключении

### Исправлено
- Версия приложения в iOS и AltStore теперь настоящая (раньше 1.0)

Полный список: ios/CHANGELOG.md

### Установка
IPA без подписи: ставь через AltStore, SideStore или Sideloadly. Нужен iOS 17+. Источник для AltStore / SideStore: `https://github.com/neosay-dev/horizon-ios/releases/latest/download/altstore.json`. Файлы игры берутся из своей копии Minecraft Java.

---

Horizon iOS 0.2.1: performance, a heat guard and handier mods.

### New
- The game is built with LTO (the `ios` profile): faster on the CPU
- 120 Hz on ProMotion iPhones (iOS held the game at 60 Hz)
- Settings → "Performance mode": the world renders at 75 % and rises to 100 % while the frame rate holds (on by default)
- Settings → "Frame generation" (FSR 3.1), off by default
- Settings → "Heat guard": on a hot phone the render distance drops to 6 or 4 chunks for a while, then comes back
- Mods: the "In game" tab opens first; "Enable all" and "Disable all" for Rust mods
- Bigger launcher tabs that respond when switched

### Fixed
- The app's version in iOS and AltStore is the real one (it said 1.0)

Full list: ios/CHANGELOG.md

### Install
Unsigned IPA: install with AltStore, SideStore or Sideloadly. Requires iOS 17+. AltStore / SideStore source: `https://github.com/neosay-dev/horizon-ios/releases/latest/download/altstore.json`. Game files come from your own copy of Minecraft Java.
