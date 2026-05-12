# SE3 — Extended Documentation

Подробные гайды по компонентам движка. Каждый документ — самодостаточный: быстрый старт, API-справочник, паттерны использования, edge cases.

Для общего обзора и краткого справочника — см. основной [../README.md](../README.md) в корне проекта.

---

## Сцены и загрузка

- **[SESceneLoader.md](./SESceneLoader.md)** — декларативные манифесты: ресурсы, prefabs через `include`, `@`-ссылки, контроллеры сцен, хуки жизненного цикла.
- **[SESceneManager.md](./SESceneManager.md)** — роутер между сценами: асинхронные переходы, общие ресурсы, standalone-microapp паттерн.
- **[CustomPreloader.md](./CustomPreloader.md)** — собственный прогресс-бар, сглаживание прогресса, три уровня сложности от `love.graphics.rectangle` до полноценного экрана с логотипом.

## Базовые классы

- **[SObject.md](./SObject.md)** — базовый класс, `SGroup` (z-сортировка), `SCanvas` (рендер в canvas), миксины `SMouseObject` / `SKeyboardObject`. Трансформы, пивот, события.
- **[SSprite.md](./SSprite.md)** — `SSprite`, `SStretchedSprite`, `SAnimationSprite`, `SComplexAnimSprite`, `SAnimator`. Кадровые анимации, шаблоны последовательностей, работа с атласом.
- **[SText.md](./SText.md)** — `SText`, `STextObject` миксин. Шрифты, выравнивание, перенос по ширине.
- **[SButton.md](./SButton.md)** — `SButton`, `SSpriteButton`, `SEmptyButton`, `SButtonEngine`. 5 состояний с fallback-ом, долгие нажатия, автоповтор, per-state стилизация текста.

## Расширенная функциональность

- **[SAnimatedObject.md](./SAnimatedObject.md)** — state machine, tween-скрипты (`wait`/`easyng`/`custom`/`shake`), кастомные типы, Penner easings (`SEEasings`).
- **[SAnimatedSpine.md](./SAnimatedSpine.md)** — state machine поверх `SESpinePlayer`: `show`/`hide`/`idle` декларативно через `scripts` (`play`/`queue`/`wait`/`set`/`fire`/`call`/`goto`), интеграция с `$state`, мульти-трек.
- **[SEInputController.md](./SEInputController.md)** — именованные actions, фазы press/click/longpress/repeat, привязка кнопок через `bindAction`.
- **[SEModel.md](./SEModel.md)** — реактивная модель: per-scene + `globalModel`, декларативный `$` / `$$` / `$?` / `$$?` в манифестах, императивный `node:bind`, подклассы с `bind_Foo` / `override_Foo`, канал событий `fire`/`on`/`off`.
- **[SEFSM.md](./SEFSM.md)** — state machine сцены: классы состояний на `SEFSMState`, авто-биндеры `onModel_` / `onEvent_` / `onUI`, таймеры `once`/`every`, история состояний `back()`, UI-события через `ui_` префикс.

## Ассеты

- **[SLoader.md](./SLoader.md)** — `SLoader` (очередь + инкрементальная загрузка), `SEEnvironment` (стек именованных слотов), поиск `resource:get()`.
- **[SSound_SShader_SAtlas.md](./SSound_SShader_SAtlas.md)** — `SSoundManager` (пул звуковых источников), `SShader` (GLSL на поддерево), `SAtlas` (TexturePacker).
- **[SESpinePlayer.md](./SESpinePlayer.md)** — Spine 4.2: декларативное объявление на сцене, `setAnimation`/`setSkin`/`setSpine`, followers, z-order, ASTC.

## Паттерны

- **[Inheritance.md](./Inheritance.md)** — как расширять классы SE3 и собирать композитные объекты из нескольких спрайтов (health bar, карточка героя, персонаж с отдельными глазами).
- **[Signals.md](./Signals.md)** — `Signal.emit`/`Signal.register`, имена сигналов от движка (`"click"`, `"input"`, `"animation.stop"`), неймспейсы, утечки подписок.
- **[EventPropagation.md](./EventPropagation.md)** — `__eventname`/`eventname`, флаг `used`, `off`/`eventoff`/`hidden`, модалки, собственные event-типы.
- **[Architecture.md](./Architecture.md)** — структура проекта, где хранить state, как сцены общаются, Signal vs handler vs controller, антипаттерны.

## Оптимизация и отладка

- **[Performance.md](./Performance.md)** — стоимость обхода, `SCanvas`-кэш, атласы, z-сорт, текст, шейдеры, память, `love.graphics.getStats`.
- **[Debugging.md](./Debugging.md)** — печать дерева, bbox-overlay, live-reload, инспектор узлов, диагностика событий, утечек и трансформов.

## Сборники рецептов

- **[Recipes.md](./Recipes.md)** — cookbook: таймеры, tween без state machine, fade-переходы, toast, модалки, параллакс, drag&drop, tooltip, скроллинг, dropdown, screen shake, pause overlay, timer-bar, слайдер, кастомный курсор.

---

## С чего начать

**Новичок в SE3:**
1. [../QUICK_START.md](../QUICK_START.md) — минимальная сцена за 5 минут.
2. [SObject.md](./SObject.md) — понять модель scene graph-а.
3. [SSprite.md](./SSprite.md) + [SButton.md](./SButton.md) — добавить содержимое.

**Проект начинает разрастаться:**
1. [SLoader.md](./SLoader.md) — упорядочить загрузку ассетов.
2. [SESceneLoader.md](./SESceneLoader.md) — вынести сцены в манифесты.
3. [SESceneManager.md](./SESceneManager.md) — сделать переходы между сценами.
4. [SEModel.md](./SEModel.md) — избавиться от ручного проталкивания данных в ноды.

**Делаете анимированных персонажей/объекты:**
1. [SSprite.md](./SSprite.md) §3 — формат sequence-ов и шаблоны кадров.
2. [SAnimatedObject.md](./SAnimatedObject.md) — state machine с tween-скриптами.
3. [SAnimatedSpine.md](./SAnimatedSpine.md) — то же, но для Spine-скелетов: `show`/`hide`/`idle` вместо ручного `setAnimation` + listener.

**Делаете UI с горячими клавишами:**
1. [SButton.md](./SButton.md) — кнопки.
2. [SEInputController.md](./SEInputController.md) — named-actions + `bindAction`.

**Пишете кастомные виджеты:**
1. [Inheritance.md](./Inheritance.md) — наследование и композиция: health bar, карточки, персонажи из нескольких спрайтов.
2. [Recipes.md](./Recipes.md) — готовые решения частых задач (слайдеры, модалки, drag&drop, тосты).

**Проектируете структуру среднего проекта:**
1. [Architecture.md](./Architecture.md) — слои, где живёт state, коммуникация между сценами.
2. [SEModel.md](./SEModel.md) — реактивное связывание данных и UI вместо ручного glue-кода.
3. [SEFSM.md](./SEFSM.md) — state machine вместо спагетти-флагов в контроллерах.
4. [Signals.md](./Signals.md) — когда что использовать.
5. [EventPropagation.md](./EventPropagation.md) — детали работы событий, о чём надо знать.

**Что-то тормозит или ведёт себя странно:**
1. [Debugging.md](./Debugging.md) — инструменты диагностики.
2. [Performance.md](./Performance.md) — куда смотреть и что оптимизировать.
