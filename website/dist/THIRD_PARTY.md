# Основа сайта и лицензии

Оформление адаптировано под Horizon iOS из [playhorizon.dev](https://playhorizon.dev/)
и его открытого репозитория [horizon-rust/horizon-site](https://github.com/horizon-rust/horizon-site).
Референс исходников: `df8a595b9da4ff87716be7f3ea0fcba2ac198d16`.
Разработчик исходного сайта — Anthony S / [DezerX](https://dezerx.com/).

## Пиксельная сцена

`design/scene.ts` основан на `components/horizon-scene.tsx` исходного сайта.
Сохранены рисунок, палитра, генератор случайных чисел, звёзды, солнце, облака,
светлячки, горы и деревья. React lifecycle заменён обычным DOM-кодом.
Добавлены обработка изменения reduced motion и пауза при скрытой вкладке.
`dist/scene.js` — скомпилированная браузерная версия без зависимостей.

[LEGAL.md исходного сайта](https://github.com/horizon-rust/horizon-site/blob/df8a595b9da4ff87716be7f3ea0fcba2ac198d16/LEGAL.md)
описывает код сайта и программную пиксельную графику как оригинальную работу
Horizon под MIT. Уведомление и текст лицензии сохранены в
`dist/assets/HORIZON-LICENSE.txt`:

Copyright (c) 2026 Ludovic Marie and the Horizon contributors.

## Компоновка

Первый экран, плавающая навигация, типографика, акцент, кнопки, полупрозрачная
панель справа и блок About адаптированы по `components/hero.tsx`,
`components/about.tsx` и `app/globals.css`. Тексты, ссылки на скачивание,
скриншоты и инструкция относятся к iOS-порту neosay-dev. Основной сайт Horizon
и DezerX указаны в подвале страницы.

## Шрифты, знак и скриншоты

- Geist и Geist Mono взяты из `crates/horizon-theme/fonts/`; лицензия —
  `dist/assets/OFL-Geist.txt`.
- Bricolage Grotesque SemiBold взят из того же каталога; лицензия —
  `dist/assets/OFL-BricolageGrotesque.txt`.
- Шрифты конвертированы из TTF в WOFF2; исходные шрифтовые рисунки сохранены.
- Знак и favicon — оригинальные SVG из `docs/media/brand/` Horizon, MIT.
- Иконка iOS — `ios/Horizon/Assets.xcassets/AppIcon.appiconset/`.
- Скриншоты — `docs/media/ios/gameplay.jpg` и `settings.jpg`, без изменений.
  Отдельные текстуры и игровые файлы Minecraft в сайт не включены.

## Участники порта

Карточка neosay-dev относится к разработке iOS-порта. Отметка о Claude повторяет
приём `components/contributors.tsx` исходного сайта; значок взят из его
`components/icons.tsx`. Участие Claude подтверждено полями `Co-Authored-By`
в коммитах каталога `ios/`. Авторы исходного Rust-движка указаны отдельно.

`dist/assets/neosay-dev-avatar.png` — публичный аватар GitHub-профиля neosay-dev
(id 282819958), сохранён локально; страница не загружает его с GitHub во время просмотра.

## Полная структура главной

Сохранены порядок и компоновка Hero, About, большой плашки, Community,
Gallery, Contributors, таблицы с двумя колонками и SiteFooter. Плашка
предлагает установку через сертификат спонсора Dark IPA; карточки ведут к материалам iOS-порта.
Вместо переноса результатов тестов движка таблица перечисляет документированные
возможности и ограничения iOS. Установка вынесена в отдельную страницу.

`design/aurora.ts` основан на `components/pixel-aurora.tsx` той же ревизии
исходного сайта, MIT. Сохранены палитра, пиксельная луна, звёзды и алгоритм
сияния. React lifecycle заменён обычным DOM-кодом; добавлена реакция на
изменение reduced motion и скрытие вкладки. Браузерная версия — `dist/aurora.js`.

Галерея-мозаика использует два исходных снимка iOS-порта и их фрагменты,
обрезанные средствами CSS. Фрагменты подписаны. Для промоблока используются
только иконка iOS-приложения и собственный скриншот порта.

## Dark IPA

Плашка спонсора использует `dist/assets/dark-ipa-avatar.jpg`: публичный аватар
бота со страницы https://t.me/ipa_certificate_bot, извлечённый из `og:image`
и сохранённый локально без изменений (JPEG, 320 × 320). Круглая форма задана
через CSS. Название спонсора и ссылка указаны по инструкции владельца сайта.
Фоновый снимок Minecraft — прежний `docs/media/ios/gameplay.jpg`.
