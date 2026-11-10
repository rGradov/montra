# Подключение iCloud

Синхронизация в Montra **ещё не включена**, но всё для неё подготовлено. Этот файл —
точная последовательность шагов, когда решите её включить.

## Что уже сделано

1. **Модели CloudKit-совместимы.** У всех атрибутов есть значения по умолчанию, связи
   опциональные, обратные связи объявлены, нет `@Attribute(.unique)`. Ничего переписывать
   не нужно.
2. **Одна точка хранения.** `ModelContainerFactory` в `Montra/App/MontraApp.swift` —
   единственное место, где создаётся контейнер.
3. **Записи через репозитории.** `AccountRepository`, `OperationRepository`,
   `CategoryRepository`, `PeriodService`. Синхронизация цепляется к ним, а не к вьюхам.
4. **Статус и интерфейс.** `SyncService` со `CloudSyncState`, честный статус «iCloud не
   подключён» в сайдбаре и лист с объяснением в настройках.
5. **Шаблон прав.** `Docs/Montra.entitlements`.
6. **Настройки отдельно.** `SettingsStore` пишет в `UserDefaults`; для синхронизации
   достаточно заменить хранилище на `NSUbiquitousKeyValueStore` + `synchronize()`.

## Шаги

1. **Контейнер.** Укажите команду Apple и зарегистрированный идентификатор
   приложения в `Montra.local.xcconfig`, как описано в
   [инструкции по подписи](Feature-Workflow.md#dmg-для-установки-на-других-mac).
   В Apple Developer → Certificates, Identifiers & Profiles → iCloud Containers
   создайте контейнер с префиксом `iCloud.` и этим идентификатором,
   например `iCloud.com.example.montra`.

2. **Права.** В таргете Montra → Signing & Capabilities добавьте **iCloud**:
   - CloudKit;
   - созданный iCloud-контейнер;
   - галочка CloudKit включена.
   Xcode создаст `Montra.entitlements`; можно взять готовый шаблон:
   ```bash
   cp Docs/Montra.entitlements Montra/Montra.entitlements
   ```
   и указать `CODE_SIGN_ENTITLEMENTS = Montra/Montra.entitlements` в
   `Montra.local.xcconfig`. Для подписи iCloud entitlement нужна команда разработчика.

3. **Хранилище.** В `Montra/App/MontraApp.swift` в `ModelContainerFactory.make()`
   замените:
   ```swift
   cloudKitDatabase: .none
   ```
   на:
   ```swift
   cloudKitDatabase: .private(SyncService.containerIdentifier)
   ```
   Это единственная обязательная правка кода.

4. **Схема CloudKit.** Запустите приложение с включённым контейнером: SwiftData создаст
   записи в development-окружении. Проверьте их в CloudKit Console
   (Developer → CloudKit → Database). Затем переведите окружение в production перед
   распространением сборки.

5. **Статус.** `SyncService` по умолчанию отдаёт `.notConfigured`. Чтобы интерфейс
   показывал реальное состояние, передайте провайдер:
   ```swift
   await SyncService.shared.start(provider: CloudKitProvider())
   ```
   где `CloudKitProvider: SyncProvider` запускает `NSPersistentCloudKitContainer`-подобную
   инициализацию SwiftData (контейнер уже создаётся с CloudKit-конфигурацией, провайдер
   нужен для статуса и повторов).

6. **Проверка.** Создайте операцию на одном Mac, подождите несколько секунд и проверьте
   появление на другом устройстве под тем же Apple ID. Если запись не приходит:
   - проверьте, что оба устройства в одном контейнере;
   - в Console.app отфильтруйте по `CloudKit` и `Montra`;
   - убедитесь, что схема развёрнута.

## Ограничения, о которых стоит помнить

- CloudKit не поддерживает уникальные ограничения — их нет и в моделях.
- Переводы между счетами и слияние конфликтов не реализованы; при одновременном
  редактировании побеждает последняя запись (стандартное поведение SwiftData).
- Демо-данные создаются на каждом устройстве отдельно; после включения синхронизации
  лучше сразу очистить данные на одном из них.
