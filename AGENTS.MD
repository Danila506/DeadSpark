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
- LAN-мир: `res://World/network_test_world.tscn`, инстанцирует `res://LanMap.tscn` (ручной статический наследник основного уровня без процедурной генерации во время игры, с посёлком, loot-домами, сохранёнными в сцене слоями и `NetworkSpawnPoints`) и добавляет сетевую координацию. Декоративные деревья, группы деревьев и белая/зелёная трава из `PresetsLayer1` запекаются в `Y-Sort_Objects/LanVegetation` через `tools/build_lan_vegetation.gd`, существующий `EnvironmentGenerationPass` и `Resources/WorldGen/lan_vegetation_profile.tres`; ручные клетки сохраняются. Проверка — `tests/lan_vegetation_test.gd`, инструкции — `tools/lan_vegetation.md`.
- Dedicated server: headless-запуск главной сцены с аргументами `--dedicated-server --server-port=<port>`; `Menu/menu.gd` поднимает сервер через `NetworkManager.start_dedicated_server()` и открывает `res://World/network_test_world.tscn` без локального игрока peer 1.
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

- Стыковочные варианты четырёх авторских диагональных углов находятся в `Assets/World/Roads/RoadConnected256.png`, source ID 1 обоих дорожных TileSet. Их создаёт `tools/build_road_connectors.gd`: центральная часть сохраняется, подводка изменяет только 48 px у подключаемых краёв, крайние 8 px совпадают со старой прямой. Нестыковочные оригиналы source 0 (6:0, 7:0, 6:1, 7:1) доступны вручную, но исключены из terrain painting; уже поставленные оригиналы автоматически не заменяются. `tests/road_curve_alignment_test.gd` проверяет все совместимые пары старых и стыковочных тайлов, сохранность центра и непрерывность полотна. Генерация использует прежнюю палитру source 0 через `RoadGenerationProfile`.

- Авторская графика дорог в `Assets/World/Roads/RoadLayer256.png` сохраняется без деформации и перерисовки. Положение четырёх диагональных углов (6:0, 7:0, 6:1, 7:1) задаётся через `TileData.texture_origin` в `RoadTileSet.tres`. `tools/build_road_atlas.ps1` по умолчанию только проверяет текущий PNG; явный `-SourcePath` копирует готовый авторский атлас без изменения пикселей. `RoadAuthoredAtlas.png` — эталон текущей авторской версии для `tests/road_curve_alignment_test.gd`; при намеренной смене рисунков обновлять эталон.

- Ручной `RoadLayer` в `LanMap.tscn` использует `Assets/World/Roads/LanRoadTileSet.tres`: базовые тайлы и сетка 256 px совпадают с `RoadTileSet.tres`, дополнительные manual-only alternatives 1–15 смещают рисунок с шагом 64 px через `texture_origin`. Эти alternatives не участвуют в terrain painting. После изменения палитры базового TileSet пересобрать LAN-ресурс через `tools/build_lan_road_tileset.gd`; инструкции для ручного рисования — `tools/lan_road_painting.md`. Процедурный уровень продолжает использовать исходный `RoadTileSet.tres`.

- `Menu` запускает/продолжает одиночную игру через `GameSaveManager`, а LAN — через `NetworkManager` и сетевой мир.
- `level.tscn` композирует WorldGeneration, Player, HUD, GUI, ItemSpawner, биомы, дороги, фермерство и размещение построек.
- `WorldGenerationOrchestrator` выполняет фазы: terrain → water → POI → road graph → road raster → environment → enemy population → legacy spawners. `WaterGenerationPass` создаёт связные озёра, затем `PoiPlacementPass` детерминированно размещает и резервирует минимум две деревни с точками въезда, совпадающими с центрами ячеек `RoadLayer`; `RoadGraphPass` обязан провести через эти реальные коннекторы разнообразный seed-зависимый ортогональный замкнутый контур без тупиков, а не прямоугольную рамку. Общие занятость и конфликты размещения проходят через `WorldOccupancyMap`. Дорожный атлас и сетка `RoadLayer` используют исходный шаг 256 px, а узкий фактический коридор полотна проецируется в общую occupancy-сетку 60 px после растрирования дороги. Природные объекты могут занимать мягкий `ROAD_CLEARANCE`, но никогда `ROAD`.
- `Player/player.gd` — координатор. Новую изолируемую логику размещай в существующих контроллерах `Player/*_controller.gd`, а не раздувай координатор без необходимости.
- `WeaponController` координирует shooting/reload/melee/noise controllers и использует `InventoryManager`, `ProjectilePool` и `EffectPool`.
- `InventoryManager` хранит экипировку и runtime-состояние предметов; `gui/scripts/inventory_root.gd` отвечает за UI, контейнеры, крафт и сетевые inventory actions.
- Интерактивные объекты обнаруживаются по группам и вызываются через `PlayerInteractionController`.
- Одиночное сохранение запрещено в multiplayer-контексте; сетевой мир использует host-authoritative состояние.

## Обязательные контракты — переиспользовать

Не создавай дублирующие менеджеры или альтернативные контракты, если задачу покрывают следующие системы:

- Предметы: `ItemData` (`res://items/scripts/item_data.gd`) — definition; `ItemInstance` — runtime identity/state. Не хранить изменяемое состояние непосредственно в общих `.tres`.
- Предметы, создаваемые внутренними `SpawnMarker` домов, получают через `ItemSpawner` visibility scope с якорем дома и номером этажа. `pickup_item.gd` скрывает их и исключает из `NearbyItemsManager` вне соответствующего дома/этажа; scope сохраняется в LAN pickup payload/snapshot.
- Бункер детерминированно выбирает вариант с ящиком или без него. Ящик использует `bunker_loot_profile.tres` и содержит 1–3 предмета (патроны, оружейные модули, медицина), а внутренние `SpawnMarker` создают один предмет из того же профиля через `ItemSpawner`; вариант без ящика публикует `bunker_empty_loot_profile.tres`.
- Инвентарь/экипировка/патроны/модули/прочность: только через `InventoryManager` и его сигналы `equipment_changed`, `ammo_state_changed`, `item_broken`.
- Ближайшие предметы: `NearbyItemsManager`; UI слушает `nearby_items_changed`.
- Взаимодействия: группа `primary_interactable` + `handle_primary_interaction`, либо `secondary_interactable` + `handle_secondary_interaction`. Выбор ближайшей цели делает `PlayerInteractionController`.
- Persistence узла: стабильный `get_save_key()`, `get_save_data()`, `apply_save_data()`. Регистрация и сериализация — через `GameSaveManager`.
- Обновление контейнеров: абсолютное время принадлежит `HUD`/группе `game_clock`; `LootContainerRestock` отсчитывает 24 игровых часа от открытия конкретного хранилища, активирует цикл только после изъятия предмета и дозаполняет лишь пустые слоты, сохраняя оставшийся лут. Новый лут детерминировать по world seed, stable container ID и времени цикла; в LAN обновляет только сервер.
- Процедурные сохраняемые объекты: детерминированный stable ID, группа `generated_world_object` и существующий generation-state contract. Не использовать нестабильный NodePath как единственную идентичность.
- Генерация: использовать `WorldGenerationOrchestrator`, passes, profiles, `WorldOccupancyMap`, `WorldSeedService`, generation hashes и `WorldGenerationScheduler`; сохранять детерминизм одного seed.
- AI: расширять `EnemyAI`/`EnemyConfig`/`EnemyStateMachine` и существующие states. Общие враги должны использовать группы и сигналы `enemy`, `noise_listener`, `died/state_changed`.
- Попадания по врагам: физическая `CollisionShape2D` персонажа отвечает только за движение; урон от снарядов принимают `Hurtbox`/`HitBoxes` (`Area2D`) на выделенном слое `DamageHurtbox` через существующий контракт `damage_hitbox` и `take_damage_from`.
- Сеть: `NetworkManager`, `NetworkSessionNode/Coordinator` и `network_shared_world`; gameplay-решения на сервере, клиентские RPC валидировать. Клиент передаёт для движения только нормализованный input-вектор; позицию и столкновения authoritative-реплики сервер рассчитывает через `move_and_slide`, клиентская позиция сервером не принимается. HP, вода, еда, выносливость, радиация и status effects каждого LAN-игрока рассчитываются сервером и передаются в player snapshot; HUD всегда перепривязывается к локальной сетевой реплике. LAN-инвентарь после bootstrap-снимка хранится как server-owned per-peer state в `InventoryManager`; броня, её износ, крафт, расходники и боеприпасы мутируются для конкретного peer на сервере и возвращаются клиенту authoritative snapshot. Переносы между общим контейнером и инвентарём принимаются только как атомарная операция с сохранением полного набора runtime-предметов; world drop создаётся лишь из предмета, извлечённого сервером из authoritative слота. Host migration повышает уже синхронизированную клиентскую копию мира без перезагрузки сцены; изменяемое состояние процедурных узлов переносится через их `get_save_data()`/`apply_save_data()` в world snapshot. Не вводить второй сетевой singleton.
- Смерть LAN-игрока обрабатывает сервер: `InventoryManager` атомарно извлекает server-owned экипировку и вложенные предметы peer, `ItemSpawner` создаёт синхронизированные pickups возле точки смерти, а мировая реплика персонажа скрывается и отключает коллизии до завершения клиентского death flow/отключения.
- Пули/эффекты/удаление: `ProjectilePool`, `EffectPool`, `NodeCleanupQueue`; не создавать частые объекты в обход пулов без причины.
- Костры используют общий `World/bonfire_light.gd`: сервер раз в секунду наносит игрокам в зоне ожога урон и через `Player.apply_clothing_endurance_percent_loss()`/`InventoryManager` снимает ровно 1,5% прочности с каждой надетой вещи; клиент не мутирует HP или экипировку самостоятельно.
- UI состояния Player: `stats_changed` и `status_effects_changed` → HUD; не опрашивать дублирующее состояние отдельным глобальным менеджером.
- Общая защита игрока от внедрения в мировые коллайдеры принадлежит `PlayerMovementController`: после authoritative/local `move_and_slide` он проверяет физическую форму, ищет ближайшую свободную точку и при необходимости использует последнюю безопасную позицию. Не добавлять разрозненные anti-stuck телепорты в кусты, деревья и другие отдельные объекты.

## Autoload

Игровые Autoload: `InventoryManager`, `NearbyItemsManager`, `GameSaveManager`, `NPCManager`, `LocalizationManager`, `ProjectilePool`, `EffectPool`, `StutterMonitor`, `ChunkProfiler`, `WorldGenerationScheduler`, `NetworkManager`, `NodeCleanupQueue`, `FpsOverlay`.

`NPCManager` — реестр и координатор дружественных NPC: проверяет стабильные `npc_id`, маршрутизирует локальные/LAN-взаимодействия и владеет общим диалоговым UI. Движение, здоровье, state machine, отношения, ассортимент и persistence остаются на конкретном NPC; `GameSaveManager` остаётся владельцем сериализации.

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
