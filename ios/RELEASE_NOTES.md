Первый релиз Horizon для iOS: Minecraft Java Edition 26.3, переписанный на Rust, теперь на iPhone.

### Новое
- Нативный лаунчер на SwiftUI: вход, импорт файлов игры, настройки
- Сенсорное управление с редактором раскладки и виртуальная мышь для меню и инвентаря
- Пауза и сохранение мира при сворачивании приложения
- При нехватке памяти дальность прорисовки снижается сама, чтобы iOS не закрыла игру
- Доступ к LAN-мирам и серверам в локальной сети

### Исправлено
- Вылет при входе в игру сразу после загрузки (не хватало стека главного потока)
- Курсор кликал правее, чем стоял, на айфонах с вырезом

### Установка
IPA без подписи: ставь через AltStore, SideStore или Sideloadly. Нужен iOS 17+. Файлы игры берутся из своей копии Minecraft Java.

---

First Horizon release for iOS: Minecraft Java Edition 26.3 rewritten in Rust, now on iPhone.

### New
- Native SwiftUI launcher: sign-in, game file import, settings
- Touch controls with a layout editor, and a virtual mouse for menus and inventories
- The game pauses and saves the world when the app goes to the background
- On a memory warning the render distance drops on its own, so iOS doesn't close the game
- LAN worlds and local-network servers can be reached

### Fixed
- Crash when entering the game right after loading (the main thread ran out of stack)
- On notched iPhones the cursor clicked to the right of where it stood

### Install
Unsigned IPA: install with AltStore, SideStore or Sideloadly. Requires iOS 17+. Game files come from your own copy of Minecraft Java.
