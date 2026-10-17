# SberKidsVibe

Прототип для хакатона Сбера «Создаём эмоции», трек «Приколы»: интерактивный слой поверх главного экрана детского банковского приложения. Он не блокирует сценарии и управляется контентом с CDN.

## Что внутри

| Модуль | Что делает |
|---|---|
| [`Packages/MascotKit`](Packages/MascotKit) | Маскот, который живёт на интерфейсе: ходит по карточкам, прыгает, реагирует на наклон, тряску, зарядку и события приложения, говорит реплики и издаёт звуки. Его можно схватить и кинуть. Персонажа (хоть машинку) художник собирает из картинок по JSON — без кода |
| [`Packages/VinesKit`](Packages/VinesKit) | Сезонные лианы сверху экрана: качаются и срываются смахом. Паки: матрица, осень, Хэллоуин, Новый год |
| [`karablik27/sberkids-cdn`](https://github.com/karablik27/sberkids-cdn) | Контент приколов в отдельном публичном репозитории: конфиги, персонажи, звуки, картинки. Раздаётся через GitHub Pages — `https://karablik27.github.io/sberkids-cdn/` — и меняется без релиза приложения |
| [`GreenAlfaKids/`](GreenAlfaKids) | Демо-приложение: главный экран по макету и встраивание обоих модулей |

## Требования стека

- Swift 6 (strict concurrency), SwiftUI;
- iOS 15+;
- только фреймворки Apple, без сторонних зависимостей и без бэкенда;
- не нужны разрешения;
- контент весит меньше 1 МБ.

## Встраивание

```swift
import MascotKit
import VinesKit

Mascot.contentURL = URL(string: "https://karablik27.github.io/sberkids-cdn/")
Vines.contentURL  = URL(string: "https://karablik27.github.io/sberkids-cdn/")

HomeView()
    .hangingVines()
    .mascot()

avatar.mascotHome().mascotTrigger("avatar", .longPress(), .toggle)
card.mascotSurface()
```

Подробности — в README каждого пакета и в [README CDN-репозитория](https://github.com/karablik27/sberkids-cdn#readme).

## Запуск

Откройте `GreenAlfaKids.xcodeproj` и запустите схему `GreenAlfaKids`.

Аргументы запуска для демо:
- `-MascotAlwaysAppear YES` — маскот приходит при каждом запуске;
- `-CDNBaseURL <url>` — другой адрес CDN; для проверки правок до публикации — локальная копия CDN-репозитория: `file:///…/sberkids-cdn/` (только в симуляторе);
- `-FunLiteMode YES` — облегчённый режим для слабых устройств.

Тесты пакета: схема `MascotKit` → Test.
