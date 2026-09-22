# Dead Spark — карта проекта для Codex

## Роль и порядок работы

- Работай как опытный разработчик игр на Godot, используй актуальные возможности Godot 4 и современные решения.
- Перед началом изменения сначала продумай реализацию и кратко сообщи, как будешь проверять результат.
- Пиши масштабируемый код и развивай существующую архитектуру вместо создания параллельных систем.
- Godot для локальных тестов находится в `D:\personal_D\godot`.
- Береги пользовательские изменения в рабочем дереве: не перезаписывай и не откатывай несвязанные правки.

## Назначение и точки входа

Dead Spark — 2D survival-action в заснеженном постапокалиптическом мире: исследование процедурного мира, лут, экипировка, крафт, выживание, бой и LAN-кооператив PC/Android.

- Главная сцена: `res://Menu/Menu.tscn`.
- Одиночная игра: `res://level.tscn` + `res://level.gd`.
- LAN-мир: `res://World/network_test_world.tscn`, инстанцирует основной уровень и добавляет сетевую координацию.
- Генерация мира: `res://World/world_generation.tscn`.
- Игрок/UI: `res://Player/player.tscn`, `res://gui/GUI.tscn`, `res://HUD/hud.tscn`.

## Структура

- `Player/` — игрок, движение, vitals/status effects, взаимодействия, timed actions, смерть, оружие, тепловизор и LAN-синхронизация.
- `Enemies/AI/` — общий `EnemyAI`, `EnemyConfig`, state machine и состояния; `Enemies/Bandits/`, `Enemies/Wolf/` — конкретные варианты.
- `Animals/Deer/` — отдельное поведение оленя, разделка и persistence популяции.
- `World/` — игровой мир, здания, контейнеры, фермерство, погода и сетевой мир.
- `World/Generation/` — seed/hash-контракты, дороги, POI, occupancy, окружение, лут и популяции.
- `Villages/` — генерация содержимого и размещение деревень.
- `items/` — определения и runtime-экземпляры предметов, pickup/spawner и глобальный инвентарь.
- `Resources/` — ItemData, EnemyConfig, loot/worldgen-профили и другие data-driven ресурсы.
- `gui/`, `HUD/`, `Menu/`, `Smartphone/` — inventory/craft/loot UI, HUD, меню и мобильное управление.
- `Projectile/`, `Effects/` — снаряды и эффекты; использовать существующие пулы.
- `tests/`, `tools/` — headless-интеграционные проверки и LAN smoke runner.
- `addons/` — плагины, включая Godot MCP; не смешивать plugin-код с игровой архитектурой.

## Архитектурные связи

- `Menu` запускает/продолжает одиночную игру через `GameSaveManager`, а LAN — через `NetworkManager` и сетевой мир.
- `level.tscn` композирует WorldGeneration, Player, HUD, GUI, ItemSpawner, биомы, дороги, фермерство и размещение построек.
- `WorldGenerationOrchestrator` выполняет фазы: terrain → road graph → road raster → POI → environment → enemy population → legacy spawners. Общие занятость и конфликты размещения проходят через `WorldOccupancyMap`.
- `Player/player.gd` — координатор. Новую изолируемую логику размещай в существующих контроллерах `Player/*_controller.gd`, а не раздувай координатор без необходимости.
- `WeaponController` координирует shooting/reload/melee/noise controllers и использует `InventoryManager`, `ProjectilePool` и `EffectPool`.
- `InventoryManager` хранит экипировку и runtime-состояние предметов; `gui/scripts/inventory_root.gd` отвечает за UI, контейнеры, крафт и сетевые inventory actions.
- Интерактивные объекты обнаруживаются по группам и вызываются через `PlayerInteractionController`.
- Одиночное сохранение запрещено в multiplayer-контексте; сетевой мир использует host-authoritative состояние.

## Обязательные контракты — переиспользовать

Не создавай дублирующие менеджеры или альтернативные контракты, если задачу покрывают следующие системы:

- Предметы: `ItemData` (`res://items/scripts/item_data.gd`) — definition; `ItemInstance` — runtime identity/state. Не хранить изменяемое состояние непосредственно в общих `.tres`.
- Инвентарь/экипировка/патроны/модули/прочность: только через `InventoryManager` и его сигналы `equipment_changed`, `ammo_state_changed`, `item_broken`.
- Ближайшие предметы: `NearbyItemsManager`; UI слушает `nearby_items_changed`.
- Взаимодействия: группа `primary_interactable` + `handle_primary_interaction`, либо `secondary_interactable` + `handle_secondary_interaction`. Выбор ближайшей цели делает `PlayerInteractionController`.
- Persistence узла: стабильный `get_save_key()`, `get_save_data()`, `apply_save_data()`. Регистрация и сериализация — через `GameSaveManager`.
- Процедурные сохраняемые объекты: детерминированный stable ID, группа `generated_world_object` и существующий generation-state contract. Не использовать нестабильный NodePath как единственную идентичность.
- Генерация: использовать `WorldGenerationOrchestrator`, passes, profiles, `WorldOccupancyMap`, `WorldSeedService`, generation hashes и `WorldGenerationScheduler`; сохранять детерминизм одного seed.
- AI: расширять `EnemyAI`/`EnemyConfig`/`EnemyStateMachine` и существующие states. Общие враги должны использовать группы и сигналы `enemy`, `noise_listener`, `died/state_changed`.
- Сеть: `NetworkManager`, `NetworkSessionNode/Coordinator` и `network_shared_world`; gameplay-решения на сервере, клиентские RPC валидировать. Клиент передаёт для движения только нормализованный input-вектор; позицию и столкновения authoritative-реплики сервер рассчитывает через `move_and_slide`, клиентская позиция сервером не принимается. HP, вода, еда, выносливость, радиация и status effects каждого LAN-игрока рассчитываются сервером и передаются в player snapshot; HUD всегда перепривязывается к локальной сетевой реплике. LAN-инвентарь после bootstrap-снимка хранится как server-owned per-peer state в `InventoryManager`; броня, её износ, крафт, расходники и боеприпасы мутируются для конкретного peer на сервере и возвращаются клиенту authoritative snapshot. Переносы между общим контейнером и инвентарём принимаются только как атомарная операция с сохранением полного набора runtime-предметов; world drop создаётся лишь из предмета, извлечённого сервером из authoritative слота. Host migration повышает уже синхронизированную клиентскую копию мира без перезагрузки сцены; изменяемое состояние процедурных узлов переносится через их `get_save_data()`/`apply_save_data()` в world snapshot. Не вводить второй сетевой singleton.
- Пули/эффекты/удаление: `ProjectilePool`, `EffectPool`, `NodeCleanupQueue`; не создавать частые объекты в обход пулов без причины.
- UI состояния Player: `stats_changed` и `status_effects_changed` → HUD; не опрашивать дублирующее состояние отдельным глобальным менеджером.

## Autoload

Игровые Autoload: `InventoryManager`, `NearbyItemsManager`, `GameSaveManager`, `LocalizationManager`, `ProjectilePool`, `EffectPool`, `StutterMonitor`, `ChunkProfiler`, `WorldGenerationScheduler`, `NetworkManager`, `NodeCleanupQueue`, `FpsOverlay`.

MCP bridge-autoload относятся к инструменту разработки, а не к gameplay API. При изменении списка или путей Autoload синхронно обновляй `project.godot` и этот файл.

## Правила изменений и проверки

- Сначала находи существующего владельца состояния и точки интеграции; не дублируй inventory, interaction, save, network, generation, pooling или AI state systems.
- Для новых предметов предпочитай data-driven `.tres`; для генерации — profiles/passes, а не ветвление по конкретным сценам в координаторах.
- Сохраняй обратную совместимость save schema либо добавляй явную миграцию. Проверяй вложенные предметы, runtime IDs, батареи, attachments и боезапас.
- Для multiplayer проверяй host/client authority, стабильные пути/ID узлов, порядок spawn/despawn и повторные запросы без дублирования.
- Для worldgen проверяй одинаковые hashes/результаты для фиксированного seed, occupancy-конфликты и frame budgets.
- Существенные изменения persistence, LAN или generation сопровождай подходящим тестом из `tests/`; для LAN используй `tools/lan_smoke.ps1`.
- Базовая headless-проверка: `powershell -ExecutionPolicy Bypass -File tools/check_project.ps1 -GodotPath "D:\personal_D\godot\Godot_v4.6.2-stable_win64_console.exe"` (если имя бинарника изменилось — найди актуальный в указанной папке).

## Godot MCP

- Godot MCP уже настроен и доступен; не переустанавливай и не создавай второй MCP-плагин.
- Используй MCP для актуальной проверки сцен, node tree, зависимостей, Autoload, ошибок редактора и runtime-состояния.
- После значимых изменений по возможности проверяй затронутую сцену через MCP: `get_project_info`/`get_project_settings`, `get_scene_tree`/`get_scene_dependencies`, `validate_script`, затем при необходимости `play_scene`, `get_game_scene_tree`, `get_autoload`, `get_editor_errors`.
- После запуска тестовой сцены обязательно вызови `stop_scene`, в том числе после неуспешной проверки.
- Не используй MCP без необходимости, если задача надёжно решается простым чтением или редактированием файлов. Не запускай игру только ради статического поиска.
- MCP дополняет, но не заменяет файловые тесты и проверку реальных resource/scene dependencies.

## Незавершённые области

Зомби, полноценная карта и Settings пока не являются завершёнными системами. Перед развитием сначала проверь их фактическую интеграцию. Квестовой, диалоговой и отдельной NPC-системы сейчас нет.

## Актуальность карты

После существенного изменения архитектуры, путей ключевых систем, Autoload, save/network/generation contracts или основных entry points обязательно обновляй `AGENTS.MD`.
