# Backup playbook

Бэкап — это JSON-документ `.montra`: конверт `MontraBackup` + `BackupPayload`.
Конверт хранит формат, версию схемы, версию приложения и SHA-256 payload.
Payload хранит счета, категории, операции, планы, периоды, настройки, курсы и
настройки локального API. Суммы — десятичные строки, даты — ISO 8601 с
миллисекундами.

Файлы:

- `Montra/Backup/BackupArchive.swift` — структуры и кодирование;
- `Montra/Backup/BackupService.swift` — capture, restore, apply, проверка ссылок;
- `Montra/Backup/BackupFile.swift` — панели и расширение `.montra`;
- `Montra/Features/Settings/BackupRestoreSheet.swift` — подтверждение и применение
  курсов/API-настроек после restore;
- `Montra/Snapshot/SelfTest.swift` — backup-блок самопроверки.

## 1. Новое поле модели

Пример: у счёта появляется `isPinned`.

### Модель

```swift
@Model
final class Account {
    // ...
    var isPinned: Bool = false

    init(
        // ...
        isPinned: Bool = false,
        // ...
    ) {
        // ...
        self.isPinned = isPinned
    }
}
```

Дефолт обязателен: SwiftData делает лёгкую миграцию, а старый store открывается.

### Формат

```swift
struct AccountBackup: Codable, Equatable {
    // ...
    /// Optional: файл, записанный до появления флага, восстановится как false.
    var isPinned: Bool?
}
```

Почему optional: `JSONDecoder` синтезирует `decode`, и отсутствующий ключ для
non-optional поля — ошибка. Optional превращает отсутствие в `nil`, а restore
подставляет дефолт.

### Capture

```swift
private extension AccountBackup {
    init(_ account: Account) {
        self.init(
            // ...
            isPinned: account.isPinned
        )
    }
}
```

### Restore

```swift
let account = Account(
    // ...
    isPinned: row.isPinned ?? false
)
```

Не забудь про `PreparedPayload`, если поле — ссылка (`UUID`) на другую сущность.
Там же проверяется, что ссылка существует, до удаления текущих данных.

### Версии

```swift
enum BackupCoding {
    static let currentFormatVersion = 2   // payload изменился
    static let currentSchemaVersion = 2   // модель получила stored property
}
```

- Новая Montra читает старые файлы: диапазон `1...current` и optional-поля.
- Старая Montra, встретив новый `formatVersion`, скажет «обновите Montra», а не
  «файл повреждён».
- Меняешь смысл существующего поля — bump обоих и опиши миграцию.

### Self-test

Добавляй проверку в существующий backup-блок `SelfTest.swift`, не создавай второй
набор фикстур.

```swift
let pinned = Account(
    name: "Закреплённый", currency: .byn, initialAmount: 10,
    iconName: "creditcard.fill", color: .blue
)
pinned.isPinned = true
backupContext.insert(pinned)

// после capture:
check(
    archive.payload.accounts.first { $0.id == pinned.id }?.isPinned == true,
    "флаг закрепления попал в копию"
)

// после restore:
let restoredPinned = accounts.first { $0.id == pinned.id }
check(restoredPinned?.isPinned == true, "флаг закрепления восстановлен")
```

Обязательный минимум: значение в payload, encode/decode, restore в новый контекст.

## 2. Новая настройка

```swift
// SettingsStore.swift
@Published var showCents: Bool {
    didSet { defaults.set(showCents, forKey: Key.showCents) }
}
```

```swift
// BackupArchive.swift
struct SettingsBackup: Codable, Equatable {
    // ...
    var showCents: Bool?
}
```

```swift
// BackupService.swift — capture
private extension SettingsBackup {
    init(_ settings: SettingsStore) {
        self.init(
            // ...
            showCents: settings.showCents
        )
    }
}
```

```swift
// BackupService.swift — restore
private static func apply(_ backup: SettingsBackup, hasAccounts: Bool, to settings: SettingsStore) {
    // ...
    settings.showCents = backup.showCents ?? true
}
```

Дефолт должен совпадать с дефолтом `SettingsStore.init`: иначе старый бэкап
незаметно поменяет поведение.

`lastBackupAt` — исключение: это дата последней копии на этом Mac, а не деньги.
Она не входит в `SettingsBackup` и живёт в allowlist.

## 3. Состояние вне SwiftData

Примеры: таблица курсов, настройки локального API.

1. `BackupService.Environment` — то, что живёт в рантайме.
2. `BackupPayload` — optional-секция (`RatesBackup?`, `IntegrationBackup?`).
3. `BackupService.capture` — заполнение секции.
4. `BackupService.RestoreReport` — что вернуть в UI.
5. `BackupRestoreSheet.performRestore` — применить после восстановления.
6. `LocalIntegration.applyBackup` / `RateStore.applyBackup` — если есть готовая
   точка применения.
7. Оба вызова `BackupService.capture`: `SettingsView.backupEnvironment` и
   `BackupRestoreSheet.environment`. Если добавил поле в `Environment` и забыл
   второй вызов — приложение не соберётся, это хорошо; но проверь оба.

Секреты (токен API) не включаются. Новый Mac получает новый токен.

## 4. Новая сущность

Порядок:

1. `BackupPayload`: `var tags: [TagBackup]?` — optional для старых файлов, при
   чтении `?? []`.
2. `BackupSummary`: `tags: Int`, `records` включает её.
3. `capture`: fetch, стабильная сортировка, `map(TagBackup.init)`.
4. `restore.insert`: создание и вставка в правильном порядке.
5. `PreparedPayload`: проверка всех внешних ключей до удаления.
6. `deleteAll`: удалить новую сущность до родителей.
7. `BackupRestoreSheet`: строка счётчика + ключ локализации.
8. `SelfTest`: фикстура, capture, restore, проверка ссылок.
9. `Docs/Feature-Inventory.md`: persistence-сценарий.

Ссылки восстанавливай в два прохода, как категории и родители: сначала вставь
все записи, потом свяжи по ID. Порядок в файле не должен иметь значения.

## 5. Проверка ссылок

`PreparedPayload` уже проверяет:

- parent категории существует и не ссылается на себя;
- account/category у операции существуют;
- account/category у плана существуют.

Если добавляешь ссылку — добавь такую же проверку и бросай `BackupError.corrupted`
до первого удаления. Иначе битый файл оставит полупустой store.

## 6. Старые файлы

- Старый файл без нового optional-поля → `nil` → дефолт.
- Старый файл с `formatVersion 1`, новый код с `2` → проходит guard
  `1...currentFormatVersion`.
- Новый файл в старой Montra → `unsupportedVersion` (после bump формата).
- Повреждённый checksum → `corrupted`, данные не трогаются.
- Никогда не пересчитывай checksum вручную и не отключай проверку.

## 7. Быстрый чек-лист

- [ ] Поле в модели с дефолтом.
- [ ] Поле в `*Backup` (optional).
- [ ] Capture-extension.
- [ ] Restore `insert` с дефолтом.
- [ ] `PreparedPayload`, если ссылка.
- [ ] Bump `currentFormatVersion`/`currentSchemaVersion`.
- [ ] Счётчик в `BackupSummary`/UI, если новая сущность.
- [ ] Новая проверка в `SelfTest.swift`.
- [ ] `-selftest` — `ALL CHECKS PASSED`.
- [ ] `python3 Scripts/audit-feature-sync.py` — backup зелёный.
- [ ] Ручной round-trip, если менял формат.
