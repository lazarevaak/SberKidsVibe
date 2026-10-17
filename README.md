# SberKidsVibe

Прототип для хакатона Сбера «Создаём эмоции», трек «Приколы»: интерактивный слой поверх главного экрана детского банковского приложения. Он не блокирует сценарии и управляется контентом с CDN.

## Что внутри

| Модуль | Что делает |
|---|---|
| [`Packages/MascotKit`](Packages/MascotKit) | Маскот, который живёт на интерфейсе: ходит по карточкам, прыгает, реагирует на наклон, тряску, зарядку и события приложения, говорит реплики и издаёт звуки. Его можно схватить и кинуть |
| [`Packages/VinesKit`](Packages/VinesKit) | Сезонные лианы сверху экрана: качаются и срываются смахом. Паки: матрица, осень, Хэллоуин, Новый год |
| [`cdn/`](cdn) | Контент приколов: конфиги, картинки, звуки. Меняется без релиза приложения |
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

Mascot.contentURL = URL(string: "https://…/cdn/")
Vines.contentURL  = URL(string: "https://…/cdn/")

HomeView()
    .hangingVines()
    .mascot()

avatar.mascotHome().mascotTrigger("avatar", .longPress(), .toggle)
card.mascotSurface()
```

Подробности — в README каждого пакета и в [`cdn/README.md`](cdn/README.md).

## Запуск

Откройте `GreenAlfaKids.xcodeproj` и запустите схему `GreenAlfaKids`.

Аргументы запуска для демо:
- `-MascotAlwaysAppear YES` — маскот приходит при каждом запуске;
- `-CDNBaseURL <url>` — другой адрес CDN;
- `-FunLiteMode YES` — облегчённый режим для слабых устройств.

Тесты пакета: схема `MascotKit` → Test.
