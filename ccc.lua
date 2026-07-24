if not game:IsLoaded() then game.Loaded:Wait() end

local RUNTIME_KEY = "__KAITUN_RUNTIME"

local function cloneTable(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do
        copy[cloneTable(k, seen)] = cloneTable(v, seen)
    end
    return copy
end

local function disableLegacyActions(cfg)
    if type(cfg) ~= "table" then
        return
    end
    for _, section in pairs(cfg) do
        if type(section) == "table" and section.Enabled ~= nil then
            section.Enabled = false
        end
    end
end

local oldConfig = getgenv().ConfigsKaitun
local newConfig = cloneTable(oldConfig)
local oldRuntime = getgenv()[RUNTIME_KEY]

if oldRuntime and type(oldRuntime.Stop) == "function" then
    pcall(oldRuntime.Stop, "new kaitun loaded")
elseif oldConfig then
    disableLegacyActions(oldConfig)
    print("[KAITUN]", "Disabled legacy action config from older script.")
end

if newConfig then
    getgenv().ConfigsKaitun = newConfig
end

local Runtime = {
    Active = true,
    MigratingLegacyRuntime = oldRuntime ~= nil,
    Tasks = {},
    Cleanups = {},
    TaskStatus = {},
    StartedAt = os.clock(),
}

function Runtime.Stop(reason)
    if not Runtime.Active then
        return
    end
    Runtime.Active = false
    print("[KAITUN]", "Stop runtime:", tostring(reason or "manual"))
    -- Runtime cu co the bi dung giua dot turbo; tra FPS cap lai truoc khi huy task.
    if (Runtime.TurboDepth or 0) > 0 and type(Runtime.EndTurboFps) == "function" then
        Runtime.TurboDepth = 1
        pcall(Runtime.EndTurboFps)
    end
    for _, thread in ipairs(Runtime.Tasks) do
        if type(thread) == "thread" and coroutine.status(thread) ~= "dead" then
            pcall(task.cancel, thread)
        end
    end
    for _, cleanup in ipairs(Runtime.Cleanups) do
        if type(cleanup) == "function" then
            pcall(cleanup)
        end
    end
end

getgenv()[RUNTIME_KEY] = Runtime
getgenv().StopKaitun = function(reason)
    local runtime = getgenv()[RUNTIME_KEY]
    if runtime and type(runtime.Stop) == "function" then
        runtime.Stop(reason or "manual")
    end
end

if getgenv().ConfigsKaitun == nil then
    getgenv().ConfigsKaitun = {
        ActionLogEnabled = true,

        -- CONG TAC DEBUG: false (mac dinh) = KHONG in log ra console -> het spam -> nhe RAM, het lag/loi.
        -- Khi can soi loi thi dat true: getgenv().ConfigsKaitun.Debug = true  (GUI van hien status binh thuong).
        Debug = false,

        -- Mua hạt giống ở Seed Shop
        AutoBuySeed = {
            Enabled = true,
            Delay   = 0.35,
            Mode    = "Smart", -- Smart: uu tien seed xin con stock va du tien; List: mua theo List
            MinRarity = "Common",
            KeepSheckles = 0,
            MaxPerSeedPerCycle = 50,
            List = {},
        },

        -- Tự trồng mọi hạt đang có trong túi vào ô PlantArea của plot mình
        AutoPlant = {
            Enabled        = true,
            Delay          = 0.25,
            PlantPerSeed   = 50,   -- số lần thử trồng tối đa cho mỗi tool hạt
            -- TRỒNG TỐI ƯU: thay vì rải NGẪU NHIÊN (chỗ chụm chỗ thưa), trồng theo LƯỚI ĐỀU
            -- để phủ kín ô -> trồng được NHIỀU NHẤT. Spacing nhỏ = dày = nhiều cây hơn.
            -- (source ko có khoảng cách tối thiểu thật -> hạ PlantSpacing dần tới khi game bắt đầu
            --  chặn/cây chồng xấu thì dừng lại ở mức đó.)
            PlantGridMode  = true,  -- false = trồng random như cũ
            PlantSpacing   = 2,     -- khoảng cách giữa 2 cây (studs). Nhỏ hơn = trồng dày hơn
            GridMargin     = 0.9,   -- dùng 90% diện tích ô (chừa mép ô)
            -- LỘ TRÌNH TRỒNG: mỗi loại seed chỉ trồng tối đa N cây trong plot. Đủ quota -> không
            -- trồng thêm loại đó. Seed không có trong bảng -> trồng bình thường. Chồng chỉnh số
            -- tuỳ ý ở đây. UsePlantQuota=false để trồng hết như cũ.
            UsePlantQuota  = true,
            PlantQuota = {
                ["Carrot"] = 10,
                ["Strawberry"] = 4,
                ["Blueberry"] = 4,
                ["Tulip"] = 4,
                ["Tomato"] = 4,
                ["Apple"] = 4,
                ["Bamboo"] = 50,
                ["Corn"] = 4,
                ["Cactus"] = 4,
                ["Pineapple"] = 4,
                ["Mushroom"] = 50,
                ["Green Bean"] = 50,
                ["Banana"] = 50,
                ["Grape"] = 50,
                ["Coconut"] = 50,
                ["Mango"] = 50,
                ["Dragon Fruit"] = 50,
                ["Acorn"] = 50,
                ["Cherry"] = 50,
                ["Sunflower"] = 50,
                ["Venus Fly Trap"] = 50,
                ["Pomegranate"] = 50,
                ["Poison Apple"] = 50,
                ["Moon Bloom"] = 50,
                ["Dragon's Breath"] = 50,
            },
        },

        -- Khi vườn ĐẦY mà trong túi có hạt xịn hơn cây đang trồng thì cầm Shovel
        -- đào cây dỏm nhất đi, để AutoPlant trồng cây xịn vào chỗ trống.
        -- Đào cây bằng remote thật Networking.Shovel.UseShovel (ShovelController).
        AutoShovelReplace = {
            Enabled          = false,  -- MẶC ĐỊNH TẮT: đào cây là KHÔNG hoàn lại được
            Delay            = 5,
            OnlyWhenPlotFull = true,   -- TOGGLE: true = chỉ đào-thay khi vườn đã đầy
            -- Số cây coi là "đầy". Source game (client) KHÔNG có hằng số max cây
            -- (server giữ logic đó), nên CHỒNG phải tự set theo plot của mình.
            -- 0 = chưa set -> module sẽ bỏ qua và nhắc set.
            PlotFullCount    = 0,
            -- Không bao giờ đào cây có mutation nằm trong danh sách này.
            -- "Gold"/"Rainbow" là mutation thật trong MutationData.
            KeepMutations    = { "Gold", "Rainbow" },
            MaxReplacePerCycle = 1,    -- mỗi vòng chỉ đào tối đa 1 cây dỏm (an toàn)
            -- Hạt mới phải xịn hơn cây dỏm ít nhất bao nhiêu LẦN giá thì mới đào.
            -- 1.0 = chỉ cần xịn hơn; 1.2 = phải hơn 20% giá mới đào.
            MinScoreGain     = 1.0,
            -- SAFE PLANT: [tên cây] = số cây tối thiểu LUÔN chừa lại khi đào.
            -- Nhập 1 = luôn để lại 1 cây loại đó. Nhập 0 = GIỮ TOÀN BỘ (không đào loại đó).
            -- Loại KHÔNG có trong bảng = đào tự do.
            SafePlants = {
                ["Moon Bloom"] = 1,
                ["Dragon's Breath"] = 1,
                ["Venus Fly Trap"] = 1,
                ["Sunflower"] = 1,
                ["Cherry"] = 1,
                ["Pomegranate"] = 1,
                ["Poison Apple"] = 1,
            },
        },

        -- Mua gear ở Gear Shop
        AutoBuyGear = {
            Enabled = true,
            Delay   = 0.5,
            Mode    = "Smart",
            MinRarity = "Rare",
            KeepSheckles = 0,
            MaxPerItemPerCycle = 10,
            PrioritizeSprinklers = true,
            AllowPriorityBelowMinRarity = true,
            PriorityList = {
                "Super Sprinkler",
                "Legendary Sprinkler",
                "Rare Sprinkler",
                "Uncommon Sprinkler",
                "Common Sprinkler",
            },
            ExcludeList = {
                "Jump Mushroom",
                "Speed Mushroom",
                "Shrink Mushroom",
            },
            List = {
                "Super Sprinkler",
                "Legendary Sprinkler",
                "Super Watering Can",
                "Rare Sprinkler",
            },
        },

        -- Equip 1 gear theo tên (đồ equippable: Carpet, Vine Wrapper, ...)
        AutoBuyCrate = {
            Enabled = true,
            Delay = 0.5,
            Mode = "Smart",
            MinRarity = "Epic",
            KeepSheckles = 0,
            MaxPerItemPerCycle = 3,
            List = {},
        },

        AutoEquipGear = {
            Enabled = false,
            Gear    = "",
        },

        -- Tự thu hoạch quả chín trong plot mình
        AutoCollect = {
            Enabled = true,
            Delay   = 0.1,
            RemoteOnly = true,
            TeleportToFruit = false,
            TeleportDistance = 4,
            TeleportYOffset = 2,
            TeleportWait = 0.05,
            TriggerPromptFallback = false,
            MaxPerCycle = 120,
            MaxTeleportsPerCycle = 0,
            ReturnHomeAfterCollect = false,
            StayInGarden = true,
            BetweenCollect = 0.03,
            PauseWhenFull = true,   -- đầy túi thì NGỪNG nhặt (nhặt nữa cũng phí), để đi bán
            -- Hái quả ĐÁNG TIỀN trước (theo giá bán thật FruitValueCalc), thay vì cứ hái quả gần.
            PrioritizeValuable = true,
            TeleportToValuable = false, -- mặc định KHÔNG teleport (remote hái được từ xa); bật nếu muốn chắc quả trên cao
            MaxValuableTeleports = 8,   -- nếu bật teleport: mỗi vòng tối đa bao nhiêu lần
            MinFruitScore = 0,          -- >0: bỏ qua quả rẻ dưới ngưỡng giá này (0 = hái hết)
        },

        NightNotifier = {
            Enabled = true,
            ShowGui = true,
            LogChanges = true,
            BlockSellAtNight = true,
        },

        AntiSteal = {
            Enabled = true,
            Delay = 0.3,
            OnlyAtNight = true,
            EquipShovel = true,
            RequireShovel = true,
            TeleportToIntruder = true,
            TeleportDistance = 5,        -- server yeu cau khoang cach <= 12 (ShovelController)
            TeleportYOffset = 0,
            HitsPerTarget = 3,           -- so cu danh moi lan vao ke trom
            BetweenHits = 0.6,           -- >= 0.5 de qua duoc cooldown moi-muc-tieu cua server
            TargetCooldown = 0.5,        -- re-engage nhanh: cu 0.5s lai danh lai neu con trong vuon
            ReturnAfterDefend = true,
        },

        Dashboard = {
            Enabled = true,
            Visible = true,
            ToggleKey = "RightShift",
            RefreshRate = 0.5,
            MaxLogs = 18,
        },

        AutoStartGame = {
            Enabled = true,
            Delay = 2,
            MaxReadyFires = 8,
            ForceLoadingAttributes = false,
            FireTutorialReady = true,
            TapToPlay = true,
            TapClickCount = 5,
            TapHold = 0.08,
            UseVirtualInput = true,
            UseTouchInput = true,
            UseVirtualUser = false,
            UseMouseFallback = false,
            StopWhenReady = true,
            ReadyStableSeconds = 3,
            InitialGraceDelay = 0.5,
            ForceLoadingAfter = 180,
            FireReadyAfter = 0.5,
            HideTapScreenAfter = 0,
            ForceHideLoadingAfter = 0,
            ForceTapWithoutText = false,   -- khong tap ep khi chua xac nhan prompt/load state
            ForceOnlyAfterPrompt = false,  -- KHÔNG chờ thấy prompt: tự set LoadingScreenDone + fire Tutorial.Ready
            SkipOfflineCutscene = true,    -- tự skip màn "Hold to skip" (cây mọc offline)
            OfflineSkipHold = 1.15,        -- thời gian giữ chuột để skip (game cần >= 1s)
        },

        -- Auto sell inventory; teleports to Steven before SellAll by default.
        AutoSell = {
            Enabled                    = true,
            Delay                      = 20,   -- nhịp bán tối thiểu (giây)
            DelayMax                   = 60,   -- nhịp bán tối đa; mỗi lần random trong [Delay, DelayMax]
            TeleportToStevenBeforeSell = false,
            TeleportDistance           = 5,
            TeleportWait               = 0.75,
            PostPreviewWait            = 0.25,
            PreSellWait                = 0.5,
            SellWhenFull               = true,   -- đầy túi thì bán ngay khỏi đợi Delay
            FullThreshold              = 0.95,   -- đầy >= 95% sức chứa là bán
            FullCheckDelay             = 1,      -- nhịp kiểm tra đầy túi
            SellAtNight                = true,   -- ĐÊM CŨNG BÁN (bán nhanh, không sợ bị trộm)
            ReturnHomeAfterSell        = false,  -- ban tu xa, khong teleport qua lai gay giat
            -- AUTO DOUBLE OR NOTHING (đánh bạc ở Steven, THAY cho bán thường khi bật):
            -- true = bán kiểu hên xui (gấp đôi or MẤT TRẮNG cả túi); false (mặc định) = bán thường.
            -- LƯU Ý: kết quả do SERVER random -> KHÔNG thể 100% thắng. Bật = chấp nhận rủi ro mất túi.
            DoubleOrNothing            = false,
            -- Chốt lời khi thắng đủ N lượt (1-5): 1=2x, 2=4x, 3=8x, 4=16x, 5=32x giá bán.
            DoubleOrNothingTargetWins  = 1,
        },

        -- Tự ấp trứng đang cầm trong túi (OpenEgg)
        AutoClaimMailbox = {
            Enabled = true,
            Delay = 60,
            MaxPerCycle = 20,
        },

        AutoSnapPets = {
            Enabled = true,
            Delay = 15,
        },

        AutoHatchEgg = {
            Enabled = true,
            Delay   = 0.5,
        },

        -- Tự equip pet theo tên
        AutoEquipPet = {
            Enabled = true,
            Delay   = 5,
            Mode    = "Smart",
            List = {
                -- "Starfish",
            },
        },

        -- Tự nhặt drop trong workspace.DroppedItems bằng prompt/teleport gần item
        AutoCollectDrops = {
            Enabled = true,
            Delay = 0.1,                     -- detect NHANH: quét seed mỗi 0.1s (ImportantLoopTask, ko bị FPS kéo dãn)
            -- DYNAMIC SCAN: chỉ quét nhanh khi sắp/đang event; xa event quét chậm IdleScanDelay cho nhẹ FPS.
            EventDynamicScan = true,         -- false = luôn quét Delay (như cũ)
            EventActiveDelay = 0.05,          -- TURBO khi có seed spawn thật (0.1 = 10 lần/s, đủ nhanh + nhẹ máy)
            IdleScanDelay = 0.4,             -- delay lúc XA event (quả rơi thường vẫn nhặt nhưng chậm hơn)
            PreEventWindow = 240,            -- còn <= 240s (4 phút) tới đêm đặc biệt thì bắt đầu quét nhanh
            MaxPerCycle = 200,
            TeleportDistance = 5,
            TeleportYOffset = 2,
            TeleportWait = 0.2,              -- chờ sau teleport drop thường
            IncludeSeedPackSpawns = true,
            PrioritizeRainbowSeed = true,
            SeedSpawnYOffset = 3,
            SeedSpawnWait = 0.12,
            SeedClaimNoPromptWait = 1.0,     -- chờ tối đa khi KHÔNG có prompt
            SeedClaimHoldExtra = 0.5,        -- fire instant (clamp 0.3) -> giữ ngắn; blast lo việc chắc ăn
            SeedClaimHoldExtraRainbow = 0.5, -- claim Rainbow Seed
            SeedClaimHoldExtraGold = 0.5,    -- claim Gold Seed
            SeedClaimPostPromptWait = 2,   -- chờ verify item biến mất sau khi fire
            SeedClaimGrace = 0.1,            -- nghỉ giữa 2 seed (cho server kịp claim)
            FreezeDuringSeedClaim = true,
            -- KẸP THÊM "bắn diện rộng" lúc claim seed spawn (event): sau khi teleport tới,
            -- fire MỌI ProximityPrompt trong bán kính BlastPromptRadius quanh nhân vật để chắc 100%.
            -- CHỈ chạy trong nhánh claim seed spawn -> hết event tự ngừng, tránh bắn nhầm prompt khác.
            BlastPromptsDuringSeedClaim = true,
            BlastPromptRadius = 20,
            BlastPromptOnlyRainbowGold = false, -- true: chỉ bắn diện rộng khi seed là Rainbow/Gold
            ReturnHomeAfterCollect = false,
        },

        -- Tự tưới nước cây trong plot (Networking.WateringCan.UseWateringCan)
        AutoWater = {
            Enabled  = true,
            Delay    = 2,
            PerCycle = 20,   -- số điểm tưới mỗi vòng
        },

        -- Tự đặt sprinkler đang có trong túi xuống ô PlantArea (Networking.Place.PlaceSprinkler)
        AutoSprinkler = {
            Enabled  = true,
            Delay    = 0.5,
            PerCycle = 5,
        },

        -- Tự mở Crate đang cầm (Networking.Crate.OpenCrate)
        AutoOpenCrate = {
            Enabled = true,
            Delay   = 0.5,
        },

        -- Tự mở Seed Pack đang cầm (Networking.SeedPack.OpenSeedPack)
        AutoOpenSeedPack = {
            Enabled = true,
            Delay   = 0.5,
        },

        -- Tự cộng điểm kỹ năng (Networking.SkillPoints.SpendSkillPoint)
        AutoSpendSkill = {
            Enabled  = true,
            Delay    = 0.3,
            Priority = { "MaxBackpack", "ShovelPower", "BaseSpeed", "BaseJump" },
        },

        -- Tự mở rộng vườn (Networking.Actions.ExpandGarden) - TỐN TIỀN, mặc định tắt
        -- Giá thật (ExpansionPrices.lua MỚI): moc1=$500, moc2=$40k, moc3=$1tr, moc4=$40tr, moc5=$200tr.
        -- (kaitun đọc giá runtime từ game nên luôn đúng dù game đổi số.)
        AutoExpandGarden = {
            Enabled      = true,
            Delay        = 10,
            KeepSheckles = 0,
            MaxExpansions = 0,   -- mua tới mốc này là DỪNG (0 = không giới hạn, mua hết 5 mốc)
            IgnoreSeedFirst = true,  -- true = mua expand NGAY (ko nhường mua seed). Expand chỉ vài mốc nên ưu tiên.
        },

        -- ===== AUTO TIER (Zero -> Pro): MODE TỰ ĐỘNG đổi cây trồng theo TIỀN =====
        -- Enabled=true: script TỰ chọn cây + quota theo tiền (acc nghèo trồng cây rẻ, giàu trồng cây xịn)
        --   -> KHÔNG cần nhập PlanQuota/Seed tay nữa (AutoTier ghi đè).
        -- Enabled=false: dùng PlanQuota/Seed config như cũ.
        AutoTier = {
            Enabled   = false,
            Delay     = 45,           -- quét tiền mỗi 45s
            MoneyMid  = 50000,        -- >= 50k  -> tier 2 (Mid)
            MoneyPro  = 1000000,      -- >= 1tr  -> tier 3 (Pro)
            DownMid   = 30000,        -- tụt dưới 30k -> về tier 1 (chống đổi qua lại liên tục)
            DownPro   = 700000,       -- tụt dưới 700k -> về tier 2
        },

        -- Tự mua thêm ô pet (Networking.Pets.RequestPurchasePetSlot) - TỐN TIỀN, mặc định tắt
        AutoPurchasePetSlot = {
            Enabled      = true,
            Delay        = 15,
            KeepSheckles = 0,
        },

        -- Tự tame/buy wild pet trong workspace.Map.WildPetRef
        AutoTameWildPet = {
            Enabled = true,
            Delay = 2,
            MinRarity = "Legendary",
            PriorityMinRarity = "Legendary",
            PriorityYieldSeconds = 1.5,
            KeepSheckles = 0,
            MaxPerCycle = 3,
            TeleportToPet = true,
            TeleportDistance = 5,
            TeleportYOffset = 1,
            ReturnHomeAfterTame = true,
        },

        -- ESP highlight (chỉ client, không remote)
        ESP = {
            ReadyPlants = false,   -- highlight cây có quả chín
            Players     = false,   -- highlight người chơi khác
            RefreshRate = 1,
        },

        -- Giảm đồ hoạ cho mượt (chỉ client)
        FpsBoost = {
            Enabled = true,
            TargetFPS = 10,
            CapRefreshDelay = 5,
            MuteAudio = true,
            DisableEffects = true,
            DisablePostEffects = true,
        },

        ClientLight = {
            Enabled = true,
            Delay = 10,
            HideOtherGardens = true,
            DisableOtherGardenEffects = true,
        },

        LowFpsMode = {
            Enabled = true,
            Threshold = 25,
            CriticalThreshold = 15,
            DelayMultiplier = 1.6,
            CriticalDelayMultiplier = 2.4,
            ImportantDelayMultiplier = 1.25,
            MinDelay = 0.2,
            StartupStagger = 0.12,
            WatchdogDelay = 8,
        },

        Webhook = {
            Enabled = true,
            Url = "https://discord.com/api/webhooks/1446104321757286471/r1b1AbDIk2EXQ8OW_X6k_1mtriZ3hU5NkZT72sTXYCI24GoxtXUZxllYlYId0LAe7ze9",
            Mention = "<@1378019320126509147>",
            Cooldown = 2,
            MaxQueue = 80,
        },

        ValuableWatcher = {
            Enabled = true,
            Delay = 2,
            MinPetRarity = "Legendary",
            NotifyHighPet = false,
            NotifyRainbowSeed = true,
            KeepRainbowSeed = true,
            PersistSeen = true, -- nhớ pet/seed đã báo xuống file, relog không gửi trùng
        },

        -- Phát hiện rainbow seed trong người -> gửi qua Mailbox cho 1 acc.
        -- Remote thật: Networking.Mailbox.SendBatch / LookupPlayer (Networking.lua:379-380).
        -- LƯU Ý: Mailbox trừ seed từ Inventory.Seeds (data), KHÔNG trừ Tool trong Backpack.
        KeepSeeds = {
            Enabled = true,
            List = {
                "Rainbow",
                "Gold",
                "Moon Bloom",
                "Dragon's Breath",
                "Bamboo",
            },
        },

        AutoMailSeeds = {
            Enabled           = true,
            RecipientUsername = "chuideptrai1209",
            RecipientUserId   = 0,
            Note              = "chuideptraiqua",
            SeedNames = {
                "Rainbow",
                "Gold",
                "Moon Bloom",
                "Dragon's Breath",
                "Bamboo",
            },
            MaxPerBatch       = 20,
            DelayBeforeSend   = 5,
            Delay             = 30,
        },

        AutoMailRainbow = {
            Enabled           = true,
            RecipientUsername = "chuideptrai1209", -- acc nhận seed
            RecipientUserId   = 0,                 -- >0: dùng luôn (bỏ qua LookupPlayer); 0: tự lookup theo username
            Note              = "chuideptraiqua",  -- ghi chú (tham số thứ 3 của SendBatch)
            SendCount         = 1,                 -- số lượng seed gửi mỗi lần
            DelayBeforeSend   = 30,                -- đợi bao nhiêu giây sau khi PHÁT HIỆN mới gửi
            Delay             = 30,                -- nhịp quét của vòng loop
            SkipResentKey     = true,              -- true: 1 key đã gửi thành công thì không gửi lại trong phiên này
        },

        -- Acc chỉ định: mỗi phút update 1 webhook RIÊNG, báo đang giữ bao nhiêu Rainbow Seed.
        RainbowAccountReport = {
            Enabled    = true,
            Username   = "chuideptrai1209", -- chỉ acc này mới gửi report ("" = mọi acc)
            WebhookUrl = "https://discord.com/api/webhooks/1506142435309391934/5F4iIYLiuhgbyq5zzamoIoXAPPXMOUunuNIUKxbbltGucYyHjTMb1bcL_49Yo9fpI0F8",                -- DÁN URL webhook riêng vào đây
            Mention    = "<@1378019320126509147>",
            Interval   = 60,                -- giây (mỗi phút)
        },

    }
end

local CFG = getgenv().ConfigsKaitun

local function setDefault(tbl, key, value)
    if type(tbl) == "table" and tbl[key] == nil then
        tbl[key] = value
    end
end

-- ============================================================
-- CONFIG VIẾT GỌN: cho phép Feature = true/false (thay cho { Enabled = ... }),
-- và gộp toàn bộ MAIL vào 1 mục CFG.Mail. Quy đổi về cấu trúc đầy đủ TRƯỚC setDefault.
-- (gói trong do/end nên không tốn local ở main scope)
-- ============================================================
do
    -- 1) Feature = true/false  ->  { Enabled = true/false }
    for _, k in ipairs({
        "AutoBuySeed","AutoPlant","AutoShovelReplace","AutoBuyGear","AutoBuyCrate",
        "AutoEquipGear","AutoCollect","NightNotifier","AntiSteal","Dashboard","AutoStartGame",
        "AutoSell","AutoSnapPets","AutoHatchEgg","AutoEquipPet","AutoCollectDrops","AutoWater",
        "AutoSprinkler","AutoOpenCrate","AutoOpenSeedPack","AutoSpendSkill","AutoExpandGarden",
        "AutoPurchasePetSlot","AutoTameWildPet","FpsBoost","ClientLight","LowFpsMode",
        "ValuableWatcher","AutoClaimMailbox","AutoMailRainbow","AutoMailSeeds","AutoMailPets",
        "RainbowAccountReport","TrimToQuota","KillGameControllers",
    }) do
        if type(CFG[k]) == "boolean" then
            CFG[k] = { Enabled = CFG[k] }
        end
    end

    -- 2) Gộp MAIL: CFG.Mail = { Recipient, ClaimMail, SendRainbow, SendSeeds={..}, SendPets={..} }
    --    -> map sang AutoClaimMailbox / AutoMailRainbow / AutoMailSeeds / AutoMailPets.
    local m = CFG.Mail
    if type(m) == "table" then
        local recip = type(m.Recipient) == "string" and m.Recipient ~= "" and m.Recipient or nil
        local function ensure(name)
            CFG[name] = type(CFG[name]) == "table" and CFG[name] or {}
            return CFG[name]
        end
        local claim = ensure("AutoClaimMailbox")
        claim.Enabled = m.ClaimMail ~= false

        local rb = ensure("AutoMailRainbow")
        rb.Enabled = m.SendRainbow ~= false
        if recip then rb.RecipientUsername = recip end

        local sd = ensure("AutoMailSeeds")
        local seeds = type(m.SendSeeds) == "table" and m.SendSeeds or nil
        sd.Enabled = seeds ~= nil and #seeds > 0
        if seeds then sd.SeedNames = seeds end
        if recip then sd.RecipientUsername = recip end

        local pt = ensure("AutoMailPets")
        local pets = type(m.SendPets) == "table" and m.SendPets or nil
        pt.Enabled = pets ~= nil and #pets > 0
        if pets then pt.PetNames = pets end
        if recip then pt.RecipientUsername = recip end
    end
end

-- ============================================================
-- SCHEMA GỌN ("bản chất kaitun"): chỉ để lộ thứ cần chỉnh, còn lại chạy mặc định NGẦM.
-- Dịch schema gọn -> cấu trúc internal (GIỮ NGUYÊN logic đã test). Mục không khai = mặc định.
-- (gói trong do/end nên không tốn local ở main scope)
-- ============================================================
do
    local function ensure(name)
        CFG[name] = type(CFG[name]) == "table" and CFG[name] or {}
        return CFG[name]
    end

    -- Cooldown_sell: bán khi đầy túi HOẶC mỗi N giây.
    -- Alias cho config chong hay dung: totalplant/TotalPlant/Total Plant.
    -- No chi set tong moc tinh %, khong tu bat trim neu chong dang tat trim.
    local totalPlantAlias = tonumber(CFG.TotalPlant)
        or tonumber(CFG.totalPlant)
        or tonumber(CFG.totalplant)
        or tonumber(CFG["Total Plant"])
        or tonumber(CFG["total plant"])
    if totalPlantAlias and totalPlantAlias > 0 then
        CFG.TotalPlots = totalPlantAlias
        local tqAlias = ensure("TrimToQuota")
        if tqAlias.Limit == nil or tqAlias.Limit == 0 then
            tqAlias.Limit = "100%"
        end
    end

    local cd = tonumber(CFG.Cooldown_sell)
    if cd then
        local s = ensure("AutoSell")
        s.Enabled = true
        s.Delay = cd
        s.DelayMax = cd
    end

    -- Sell At Night (NIGHT - SELL FAST): true = ĐÊM CŨNG BÁN (bán nhanh). false = đêm KHÔNG bán (đợi sáng).
    if type(CFG["Sell At Night"]) == "boolean" then
        ensure("AutoSell").SellAtNight = CFG["Sell At Night"]
    end

    -- Auto Double Or Nothing: bán kiểu HÊN XUI ở Steven (gấp đôi or MẤT TRẮNG) THAY cho bán thường.
    -- true = bật; false/không khai = bán thường. Target Wins (1-5) = thắng đủ N lượt thì chốt.
    if type(CFG["Auto Double Or Nothing"]) == "boolean" then
        ensure("AutoSell").DoubleOrNothing = CFG["Auto Double Or Nothing"]
    end
    local donWins = tonumber(CFG["Double Or Nothing Target Wins"])
    if donWins then
        ensure("AutoSell").DoubleOrNothingTargetWins = math.clamp(math.floor(donWins), 1, 5)
    end

    -- Autobuyplot: tự mua mở rộng vườn.
    -- true  = bật, mua HẾT các mốc.
    -- false = tắt.
    -- SỐ (vd 3) = bật + chỉ mua tới mốc đó là DỪNG (MaxExpansions), ko mua mốc đắt hơn.
    if type(CFG.Autobuyplot) == "boolean" then
        ensure("AutoExpandGarden").Enabled = CFG.Autobuyplot
    elseif type(CFG.Autobuyplot) == "number" then
        ensure("AutoExpandGarden").Enabled = CFG.Autobuyplot > 0
        ensure("AutoExpandGarden").MaxExpansions = CFG.Autobuyplot
    end

    -- Low Cpu: gộp FpsBoost + LowFpsMode + ClientLight.
    -- true/false = bật/tắt; HOẶC để 1 SỐ = bật + đặt luôn FPS Cap = số đó.
    local lowcpu = CFG["Low Cpu"]
    if type(lowcpu) == "boolean" then
        ensure("FpsBoost").Enabled = lowcpu
        ensure("LowFpsMode").Enabled = lowcpu
        ensure("ClientLight").Enabled = lowcpu
    elseif type(lowcpu) == "number" then
        ensure("FpsBoost").Enabled = true
        ensure("FpsBoost").TargetFPS = lowcpu
        ensure("LowFpsMode").Enabled = true
        ensure("ClientLight").Enabled = true
    end
    -- FPS Cap (Performance): trần khung hình. 3-10 lý tưởng để farm nhiều acc. Ưu tiên hơn mặc định 30.
    if tonumber(CFG["FPS Cap"]) then
        local fb = ensure("FpsBoost")
        fb.Enabled = true
        fb.TargetFPS = tonumber(CFG["FPS Cap"])
    end

    -- Limit Tree: chạm Limit cây -> đào cây TIER THẤP NHẤT xuống "Destroy Untill". Safe Tree giữ lại.
    local lt = CFG["Limit Tree"]
    if type(lt) == "table" then
        local sr = ensure("AutoShovelReplace")
        sr.Enabled = true
        sr.OnlyWhenPlotFull = true
        sr.PlotFullCount = tonumber(lt["Limit"]) or sr.PlotFullCount or 400
        sr.DestroyUntil = tonumber(lt["Destroy Untill"]) or tonumber(lt["Destroy Until"]) or sr.DestroyUntil
        -- Safe Tree: phần MẢNG (chuỗi tên trần) = giữ TOÀN BỘ (0); phần [tên]=N = giữ N cây.
        local st = lt["Safe Tree"]
        if type(st) == "table" then
            local safe = {}
            for k, v in pairs(st) do
                if type(k) == "number" and type(v) == "string" and v ~= "" then
                    safe[v] = 0
                elseif type(k) == "string" and k ~= "" then
                    safe[k] = tonumber(v) or 0
                end
            end
            sr.SafePlants = safe
        end
    end

    -- PlanQuota (mục 5,6): bảng quota DÙNG CHUNG cho trồng (AutoPlant) + cleanup (TrimToQuota) + GUI.
    -- PlanQuota = "danh sách trồng": cây CÓ trong list -> trồng tới N + giữ N; cây NGOÀI list -> KHÔNG
    -- trồng (OnlyQuota) + ĐÀO (TrimToQuota.DigUnlisted). Đây là rule "safe tree" theo ý chồng.
    if type(CFG.PlanQuota) == "table" and next(CFG.PlanQuota) then
        local ap = ensure("AutoPlant")
        ap.PlantQuota = CFG.PlanQuota
        ap.UsePlantQuota = true
        ap.OnlyQuota = true                       -- chỉ trồng cây trong PlanQuota
        local t = ensure("TrimToQuota")
        t.Quota = CFG.PlanQuota
        t.DigUnlisted = true                      -- đào cây ngoài PlanQuota
    end

    -- FRESH ACC (chong yeu cau): "Fresh Acc"=true + "Plant switch"=N -> DUOI N cay: MUA HET + TRONG HET
    -- (bo qua PlanQuota/OnlyQuota + cap OwnLimit mua hat), VAN ton trong Seed.Place Lock (KeepSeeds ->
    -- KHONG trong Rainbow/Gold/Mega). Cay TRONG-1-LAN (SeedData.IsSingleHarvest: bamboo/mushroom...) LUON
    -- trong het bat ke quota (tu bien mat sau khi hai). >= N cay -> ve che do quota binh thuong.
    if CFG["Fresh Acc"] == true then
        local switch = tonumber(CFG["Plant switch"]) or 0
        local ap = ensure("AutoPlant"); ap.FreshAcc = true; ap.PlantSwitch = switch
        local bs = ensure("AutoBuySeed"); bs.FreshAcc = true; bs.PlantSwitch = switch
    end
    -- Trim To Quota (mục 6): đào cây DƯ về quota. boolean = bật/tắt; table = chỉnh sâu (Limit/DestroyUntil hỗ trợ "%").
    local tq = CFG["Trim To Quota"]
    if type(tq) == "boolean" then
        ensure("TrimToQuota").Enabled = tq
    elseif type(tq) == "table" then
        local t = ensure("TrimToQuota")
        t.Enabled = tq.Enabled ~= false
        if tq.Quota ~= nil then t.Quota = tq.Quota end
        if tq["Limit"] ~= nil then t.Limit = tq["Limit"] end
        if tq["Destroy Untill"] ~= nil then t.DestroyUntil = tq["Destroy Untill"] end
        if tq["Destroy Until"] ~= nil then t.DestroyUntil = tq["Destroy Until"] end
        if tq.DestroyUntil ~= nil then t.DestroyUntil = tq.DestroyUntil end
        if tonumber(tq.Delay) then t.Delay = tonumber(tq.Delay) end
        if tonumber(tq.MaxPerCycle) then t.MaxPerCycle = tonumber(tq.MaxPerCycle) end
        if tonumber(tq.DigDelay) then t.DigDelay = tonumber(tq.DigDelay) end
        if type(tq.KeepMutations) == "table" then t.KeepMutations = tq.KeepMutations end
        if type(tq.DigUnlisted) == "boolean" then t.DigUnlisted = tq.DigUnlisted end
    end

    -- Seed.Buy (Auto=mua hết / Custom=mua theo list) + Seed.Place (Lock/Select hạt được trồng).
    if type(CFG.Seed) == "table" then
        local seed = CFG.Seed
        if type(seed.Buy) == "table" then
            local b = ensure("AutoBuySeed")
            b.Enabled = true
            -- List/Custom có thể là MẢNG {tên} HOẶC MAP {tên=số lượng}. Map -> mua đúng các tên đó,
            -- mỗi loại tới SỐ trong map (OwnLimitPerSeed). Đây là "mua theo list + số lượng".
            local buyList = seed.Buy.List or seed.Buy.Custom
            if type(buyList) == "table" and next(buyList) ~= nil then
                local isMap = false
                for k in pairs(buyList) do if type(k) == "string" then isMap = true break end end
                local names = {}
                if isMap then
                    local caps = {}
                    for name, cnt in pairs(buyList) do
                        if type(name) == "string" and name ~= "" then
                            table.insert(names, name)
                            if tonumber(cnt) then caps[name] = tonumber(cnt) end
                        end
                    end
                    b.OwnLimitPerSeed = caps
                else
                    for _, name in ipairs(buyList) do
                        if type(name) == "string" and name ~= "" then table.insert(names, name) end
                    end
                end
                b.Mode = "List"
                b.List = names
            elseif tostring(seed.Buy.Mode or "Auto"):lower() == "custom" then
                b.Mode = "List"
                b.List = type(seed.Buy.Custom) == "table" and seed.Buy.Custom or {}
            else
                b.Mode = "Smart"
            end
            -- Limit: số hạt tối đa SỞ HỮU mỗi loại (chung). Max = { [tên]=số } để cap riêng từng hạt.
            if tonumber(seed.Buy.Limit) then b.OwnLimit = tonumber(seed.Buy.Limit) end
            if type(seed.Buy.Max) == "table" then b.OwnLimitPerSeed = seed.Buy.Max end

            -- RICH LIST: list seed XỊN chỉ mua khi DƯ TIỀN (tiền > MinMoney), và LUÔN chừa Reserve để dành mua pet.
            -- seed.Buy.RichList = { MinMoney=số, Reserve=số, List = { ["Apple"]=5, ... } hoặc { "Apple", ... } }.
            -- Cap riêng từng seed (số trong map) gộp vào OwnLimitPerSeed -> mua tới đủ cap thì dừng.
            if type(seed.Buy.RichList) == "table" then
                local r = seed.Buy.RichList
                local rl = r.List or r.Seeds
                if type(rl) == "table" and next(rl) ~= nil then
                    local isMapR = false
                    for k in pairs(rl) do if type(k) == "string" then isMapR = true break end end
                    local richNames = {}
                    b.OwnLimitPerSeed = b.OwnLimitPerSeed or {}
                    if isMapR then
                        for name, cnt in pairs(rl) do
                            if type(name) == "string" and name ~= "" then
                                table.insert(richNames, name)
                                if tonumber(cnt) then b.OwnLimitPerSeed[name] = tonumber(cnt) end
                            end
                        end
                    else
                        for _, name in ipairs(rl) do
                            if type(name) == "string" and name ~= "" then table.insert(richNames, name) end
                        end
                    end
                    if #richNames > 0 then
                        b.Mode = "List"   -- bảo đảm chạy nhánh list để xử lý RichList
                        b.RichList = {
                            MinMoney = tonumber(r.MinMoney) or 0,
                            Reserve  = tonumber(r.Reserve) or 0,
                            List     = richNames,
                        }
                    end
                end
            end

            -- Seed.Buy.Keep (chồng yêu cầu): seed MUA XONG ĐỂ GIỮ, KHÔNG TRỒNG từ túi (seed giá trị cao,
            -- cầm đặt xuống thì phí; cây đó chỉ nên ra từ random Gold/Rainbow/Mega seed). Dạng MAP
            -- { ["Dragon's Breath"]=10 } (mua tới 10 hạt) hoặc LIST { "Dragon's Breath" }.
            -- Cơ chế: (1) thêm vào list mua + cap OwnLimitPerSeed như Buy thường;
            --         (2) GHÉP tên vào KeepSeeds.List -> AutoPlant/AutoShovelReplace/AutoOpenSeedPack bỏ qua
            --             (Runtime.ShouldKeepSeed check TRƯỚC PlanQuota - fixtrongcay AutoPlant vòng seeds),
            --             còn CÂY cùng tên random ra từ Gold/Mega vẫn được PlanQuota giữ bình thường.
            -- Ghép KeepSeeds làm SAU block Seed.Place vì Place.Lock THAY THẾ KeepSeeds.List (sẽ đè mất).
            if type(seed.Buy.Keep) == "table" and next(seed.Buy.Keep) ~= nil then
                local keepBuy = seed.Buy.Keep
                local isMapK = false
                for k in pairs(keepBuy) do if type(k) == "string" then isMapK = true break end end
                local keepNames = {}
                if isMapK then
                    b.OwnLimitPerSeed = b.OwnLimitPerSeed or {}
                    b.OwnLimitStrict = b.OwnLimitStrict or {}   -- cap các seed này THẮNG cả Fresh Acc (xem buySeed)
                    for name, cnt in pairs(keepBuy) do
                        if type(name) == "string" and name ~= "" then
                            table.insert(keepNames, name)
                            if tonumber(cnt) then
                                b.OwnLimitPerSeed[name] = tonumber(cnt)
                                b.OwnLimitStrict[name] = true
                            end
                        end
                    end
                else
                    for _, name in ipairs(keepBuy) do
                        if type(name) == "string" and name ~= "" then table.insert(keepNames, name) end
                    end
                end
                if #keepNames > 0 then
                    if b.Mode == "List" and type(b.List) == "table" then
                        local have = {}
                        for _, n in ipairs(b.List) do
                            if type(n) == "string" then have[string.lower(n)] = true end
                        end
                        for _, n in ipairs(keepNames) do
                            if not have[string.lower(n)] then table.insert(b.List, n) end
                        end
                    end
                    CFG.__SeedBuyKeepNames = keepNames   -- ghép vào KeepSeeds SAU block Seed.Place bên dưới
                end
            end
        end
        if type(seed.Place) == "table" then
            local pl = ensure("AutoPlant")
            pl.Enabled = true
            if tostring(seed.Place.Mode or "Lock"):lower() == "select" then
                pl.OnlyPlant = type(seed.Place.Select) == "table" and seed.Place.Select or {}
            else
                local keep = ensure("KeepSeeds")
                keep.Enabled = true
                keep.List = type(seed.Place.Lock) == "table" and seed.Place.Lock or {}
            end
        end
        -- Seed.Buy.Keep -> GHÉP vào KeepSeeds.List (đặt SAU Seed.Place vì Place.Lock thay thế cả list).
        -- Nhờ đó "mua để giữ" sống chung với Lock cũ: Lock={"Rainbow","Mega"} + Keep={["Dragon's Breath"]=10}
        -- -> KeepSeeds.List = {Rainbow, Mega, Dragon's Breath}; PlanQuota["Dragon's Breath"] vẫn giữ CÂY
        -- random ra từ Gold/Mega (quota đếm cây ĐANG TRỒNG, không liên quan hạt trong túi).
        if type(CFG.__SeedBuyKeepNames) == "table" and #CFG.__SeedBuyKeepNames > 0 then
            local keep = ensure("KeepSeeds")
            keep.Enabled = true
            if type(keep.List) ~= "table" then keep.List = {} end
            local have = {}
            for _, n in ipairs(keep.List) do
                if type(n) == "string" then have[string.lower(n)] = true end
            end
            for _, n in ipairs(CFG.__SeedBuyKeepNames) do
                if not have[string.lower(n)] then table.insert(keep.List, n) end
            end
            CFG.__SeedBuyKeepNames = nil
        end
    end

    -- Gear.Buy + Gear.Lock (gear KHÔNG XÀI -> giữ trong kho để GỬI MAIL).
    -- Gear.Buy nhận 2 dạng:
    --   MAP { ["Common Sprinkler"]=5 }  -> mua MỖI gear tới SỐ LƯỢNG đó (BuyQuantities).
    --   LIST { "Common Sprinkler" }      -> mua mỗi gear 1 cái/vòng (như cũ).
    if type(CFG.Gear) == "table" then
        local g = ensure("AutoBuyGear")
        local hasGearBuy = false
        if type(CFG.Gear.Buy) == "table" then
            local buy = CFG.Gear.Buy
            local isMap = false
            for k in pairs(buy) do if type(k) == "string" then isMap = true break end end
            if isMap then
                local names, qty = {}, {}
                for name, n in pairs(buy) do
                    local target = tonumber(n) or 0
                    if type(name) == "string" and name ~= "" and target > 0 then
                        table.insert(names, name)
                        qty[name] = target
                    end
                end
                if #names > 0 then
                    hasGearBuy = true
                    g.Mode = "List"
                    g.List = names
                    g.BuyQuantities = qty
                end
            elseif #buy > 0 then
                hasGearBuy = true
                g.Mode = "List"
                g.List = buy
                g.BuyQuantities = nil
            end
        end
        g.Enabled = hasGearBuy
        if not hasGearBuy then
            g.Mode = "List"
            g.List = {}
            g.BuyQuantities = nil
        end
        -- Gear.Lock = gear KHÔNG được tự XÀI (không đặt sprinkler / không dùng watering can) -> giữ kho để GỬI MAIL.
        -- (giống pet trong AutoMailPets thì không equip). 1 danh sách lo CẢ: không xài + là danh sách gửi gear (OnlyThese).
        if type(CFG.Gear.Lock) == "table" and next(CFG.Gear.Lock) ~= nil then
            ensure("AutoSprinkler").LockGear = CFG.Gear.Lock
            ensure("AutoWater").LockGear = CFG.Gear.Lock
            ensure("AutoMailGear").OnlyThese = CFG.Gear.Lock
        end
    end

    -- Prop.Buy = mua CRATE/PROP (CrateShop) theo SỐ LƯỢNG. Dạng MAP { ["Ladder Crate"]=5 } hoặc LIST { "Ladder Crate" }.
    -- (Remote thật: Networking.CrateShop.PurchaseCrate -> route vào AutoBuyCrate.)
    if type(CFG.Prop) == "table" then
        local p = ensure("AutoBuyCrate")
        local hasPropBuy = false
        if type(CFG.Prop.Buy) == "table" then
            local buy = CFG.Prop.Buy
            local isMap = false
            for k in pairs(buy) do if type(k) == "string" then isMap = true break end end
            if isMap then
                local names, qty = {}, {}
                for name, n in pairs(buy) do
                    local target = tonumber(n) or 0
                    if type(name) == "string" and name ~= "" and target > 0 then
                        table.insert(names, name)
                        qty[name] = target
                    end
                end
                if #names > 0 then
                    hasPropBuy = true
                    p.Mode = "List"
                    p.List = names
                    p.BuyQuantities = qty
                end
            elseif #buy > 0 then
                hasPropBuy = true
                p.Mode = "List"
                p.List = buy
                p.BuyQuantities = nil
            end
        end
        p.Enabled = hasPropBuy
        if not hasPropBuy then
            p.Mode = "List"
            p.List = {}
            p.BuyQuantities = nil
        end
        if type(CFG.Prop.Lock) == "table" and next(CFG.Prop.Lock) ~= nil then
            ensure("AutoOpenCrate").LockCrate = CFG.Prop.Lock
        end
        -- Prop.Lock: hiện CHƯA có logic "xài crate" trong source -> chỉ lưu lại, không tự gửi mail crate (tránh bịa remote).
    end

    -- Pets.Buy: tame wild pet theo TÊN. Upgrade Slot: tự mua thêm ô pet.
    if type(CFG.Pets) == "table" then
        if type(CFG.Pets.Buy) == "table" then
            local t = ensure("AutoTameWildPet")
            local buy = CFG.Pets.Buy
            -- Dạng MAP { ["Tên"]=số } -> mua tới số đó (OwnLimit). Dạng LIST { "Tên" } -> mua không giới hạn số.
            local isMap = false
            for k in pairs(buy) do if type(k) == "string" then isMap = true break end end
            if isMap then
                t.OwnLimit = buy
                local names = {}
                for k in pairs(buy) do if type(k) == "string" then table.insert(names, k) end end
                t.PetNames = names
                t.Enabled = #names > 0
            else
                t.OwnLimit = nil
                t.PetNames = buy
                t.Enabled = #buy > 0
            end
        end
        -- Pets.BuyAll = true -> MUA MOI wild pet tren map (giong hic.lua), khong can khai ten. Bat luon AutoTameWildPet.
        if type(CFG.Pets.BuyAll) == "boolean" then
            local t = ensure("AutoTameWildPet")
            t.BuyAllWildPets = CFG.Pets.BuyAll
            if CFG.Pets.BuyAll then t.Enabled = true end
        end
        -- Pets.BuyHoldSeconds = số giây đứng tại pet bắn mua liên tục (mặc định 4).
        if tonumber(CFG.Pets.BuyHoldSeconds) then
            ensure("AutoTameWildPet").BuyHoldSeconds = tonumber(CFG.Pets.BuyHoldSeconds)
        end
        -- Pets.WalkToPet = true -> đi bộ (Humanoid:MoveTo) tới pet; false -> neo + kéo CFrame (cũ).
        if type(CFG.Pets.WalkToPet) == "boolean" then
            ensure("AutoTameWildPet").UseWalkToPet = CFG.Pets.WalkToPet
        end
        -- Pets.BuyMaxWait = số giây tối đa đứng bám pet bắn mua trước khi bỏ (về nhà trồng cây).
        if tonumber(CFG.Pets.BuyMaxWait) then
            ensure("AutoTameWildPet").BuyMaxWait = tonumber(CFG.Pets.BuyMaxWait)
        end
        if type(CFG.Pets["Upgrade Slot"]) == "boolean" then
            ensure("AutoPurchasePetSlot").Enabled = CFG.Pets["Upgrade Slot"]
        end
        -- Pets.Equip = { ["Tên pet"] = { soLuong, uuTien } }  (uuTien NHỎ = ưu tiên CAO).
        -- ROUTE thẳng vào PRIORITY-mode mới của AutoEquipPet: rót slot cho pet ưu tiên cao TRƯỚC theo tổng sở hữu,
        -- và tự THÁO pet ưu tiên thấp khi mua được con cao hơn (vd đang 3 Deer, có Golden Dragonfly -> tháo 1 Deer
        -- mang GD vào; có thêm Unicorn -> tháo thêm 1 Deer mang Unicorn vào). Trước đây chỉ bung thành List +
        -- cap mỗi pet = slot nên KHÔNG tháo Deer ra được -> kẹt slot full (đúng lỗi chồng gặp).
        if type(CFG.Pets.Equip) == "table" and next(CFG.Pets.Equip) ~= nil then
            local ep = ensure("AutoEquipPet")
            ep.Enabled = true
            ep.Mode = "Priority"
            ep.Priority = CFG.Pets.Equip
        end
        -- Pets.EventPet = "Deer" -> khi co WEATHER mutation active thi thao pet dang mang, deo Deer day het slot
        -- (giup cay lon nhanh kip catch mutation); het weather deo lai theo Equip. "" = tat.
        if type(CFG.Pets.EventPet) == "string" then
            ensure("AutoEquipPet").EventPet = CFG.Pets.EventPet
        end
        -- Pets.Buy = { ["Unicorn"] = { Normal=0, Big=0, Huge=9, Rainbow=9 } } -> mua đủ số mỗi size, 0=ko mua.
        -- CỜ TỔNG AUTO-DETECT (chồng yêu cầu): Pets.BuyBig / Pets.BuyHuge / Pets.BuyRainbow / Pets.BuyNormal = true
        -- -> mua MỌI wild pet có size/loại đó (KHÔNG cần khai tên). Detect bằng attribute thật PetSize/PetType
        -- trên WildPetRef (xác nhận SpawnPetController:552-553; PetSizes "Big"/"Huge"; PetTypes.Rainbow="Rainbow").
        do
            local bv = {}
            if CFG.Pets.BuyBig == true then bv.Big = true end
            if CFG.Pets.BuyHuge == true then bv.Huge = true end
            if CFG.Pets.BuyRainbow == true then bv.Rainbow = true end
            if CFG.Pets.BuyNormal == true then bv.Normal = true end
            if next(bv) ~= nil then
                local t = ensure("AutoTameWildPet")
                t.BuyVariants = bv
                t.Enabled = true
            end
        end
    end

    -- Automail: To + Seeds + Pets (theo tên). Claim mail luôn bật ngầm, loop mặc định.
    if type(CFG.Automail) == "table" then
        local am = CFG.Automail
        -- To: 1 tên (string) -> LUÔN gửi acc đó.  HOẶC list {tên1,tên2,...} -> RANDOM 1 tên mỗi lần gửi.
        local to, toList = nil, nil
        if type(am.To) == "string" and am.To ~= "" then
            to = am.To
        elseif type(am.To) == "table" then
            toList = {}
            for _, nm in ipairs(am.To) do
                if type(nm) == "string" and nm ~= "" then table.insert(toList, nm) end
            end
            if #toList == 0 then
                toList = nil
            elseif #toList == 1 then            -- chỉ 1 tên trong list = coi như gửi cố định 1 acc
                to = toList[1]; toList = nil
            end
        end
        local function applyTo(cfg)
            if to then cfg.RecipientUsername = to end
            if toList then cfg.RecipientUsernames = toList end
        end
        -- NGƯỠNG GỬI: Seeds/Pets có thể là MAP {Tên=số} -> chỉ gửi khi SỐ LƯỢNG >= số đó.
        -- (dạng mảng {"Tên"} -> ngưỡng = 1, có là gửi). normalize key: chữ thường + bỏ space.
        local function buildMinCountMap(list)
            local out = {}
            if type(list) == "table" then
                for key, value in pairs(list) do
                    if type(key) == "string" and tonumber(value) then
                        out[(key:lower():gsub("^%s+", ""):gsub("%s+$", ""))] = tonumber(value)
                    end
                end
            end
            return out
        end
        ensure("AutoClaimMailbox").Enabled = true
        local sd2 = ensure("AutoMailSeeds")
        sd2.Enabled = type(am.Seeds) == "table" and next(am.Seeds) ~= nil
        if type(am.Seeds) == "table" then
            sd2.SeedNames = am.Seeds
            sd2.MinCount = buildMinCountMap(am.Seeds)
        end
        -- BatchSize: số seed gửi MỖI LẦN SendBatch (mở khóa giới hạn 20 của UI). Mặc định 20.
        if tonumber(am.BatchSize) then sd2.MaxPerBatch = tonumber(am.BatchSize) end
        applyTo(sd2)
        local pt = ensure("AutoMailPets")
        pt.Enabled = type(am.Pets) == "table" and next(am.Pets) ~= nil
        if type(am.Pets) == "table" then
            pt.PetNames = am.Pets
            pt.MinCount = buildMinCountMap(am.Pets)
        end
        applyTo(pt)
        applyTo(ensure("AutoMailRainbow"))
        -- Mail Fruits (trái cây): Fruits = LIST tên (giống Pets/Gear) -> gửi đúng quả đó; = true -> gửi MỌI quả;
        -- rỗng/false -> không gửi. Min Fruits=đợi đủ; Instead Of Sell.
        local fr = ensure("AutoMailFruits")
        if am.Fruits == true then
            fr.Enabled = true
        elseif type(am.Fruits) == "table" and #am.Fruits > 0 then
            fr.Enabled = true
            fr.OnlyThese = am.Fruits
        else
            fr.Enabled = false
        end
        applyTo(fr)
        if am.Note ~= nil then fr.Note = am.Note end
        if type(am["Only Fruits"]) == "table" then fr.OnlyThese = am["Only Fruits"] end
        if tonumber(am["Min Fruits"]) then fr.MinFruits = tonumber(am["Min Fruits"]) end
        if type(am["Instead Of Sell"]) == "boolean" then fr.InsteadOfSell = am["Instead Of Sell"] end
        -- Gửi GEAR: Automail.Gear = true -> BẬT gửi gear (gửi đúng các gear đã LOCK ở Gear.Lock = giữ-để-gửi).
        -- HOẶC Automail.Gear = list {"tên"} -> khai thẳng danh sách gửi (ghi đè Gear.Lock).
        local gr = ensure("AutoMailGear")
        if am.Gear == true then
            gr.Enabled = true                     -- OnlyThese đã set sẵn từ Gear.Lock
        elseif type(am.Gear) == "table" and #am.Gear > 0 then
            gr.Enabled = true
            gr.OnlyThese = am.Gear
        end
        applyTo(gr)
        if am.Note ~= nil then gr.Note = am.Note end
    end

    -- Webhook: Url (rỗng = tắt) + Rarity (áp cho pet & seed báo về).
    if type(CFG.Webhook) == "table" then
        local w = CFG.Webhook
        if type(w.Url) == "string" then
            w.Enabled = w.Url ~= ""
        end
        if type(w.Rarity) == "string" and w.Rarity ~= "" then
            local vw = ensure("ValuableWatcher")
            vw.MinPetRarity = w.Rarity
            vw.NotifyHighPet = type(w.Url) == "string" and w.Url ~= ""
        end
    end

    -- ===== Các tính năng MỚI (gọn) =====
    -- Keep Money: SÀN tiền chung -> áp KeepSheckles cho mọi task tiêu tiền.
    local keepMoney = tonumber(CFG["Keep Money"])
    if keepMoney and keepMoney > 0 then
        for _, name in ipairs({ "AutoBuySeed", "AutoBuyGear", "AutoBuyCrate",
            "AutoExpandGarden", "AutoPurchasePetSlot", "AutoTameWildPet" }) do
            ensure(name).KeepSheckles = keepMoney
        end
    end
    -- Stop Buy Seed At: tiền >= mức này thì ngừng mua hạt.
    local stopBuy = tonumber(CFG["Stop Buy Seed At"])
    if stopBuy then ensure("AutoBuySeed").StopBuyAt = stopBuy end
    -- Anti AFK (chống treo máy)
    if type(CFG["Anti AFK"]) == "boolean" then ensure("AntiAfk").Enabled = CFG["Anti AFK"] end
    -- Codes: danh sách code -> AutoRedeemCode
    if type(CFG.Codes) == "table" then
        local rc = ensure("AutoRedeemCode")
        rc.List = CFG.Codes
        rc.Enabled = #CFG.Codes > 0
    end
    -- Wait Mutations: chỉ hái quả có mutation trong list
    if type(CFG["Wait Mutations"]) == "table" then
        ensure("AutoCollect").WaitForMutations = CFG["Wait Mutations"]
    end
    -- KEEP CROPS FOR SELL (top-level): cay trong list TRONG BINH THUONG roi GIU, khi gia ban x4 thi CHI hai
    -- cay/qua DOT BIEN roi ban (an gia cao). Doc key moi KeepCropsForSell/KeepCropsForSellMulti; van nhan
    -- key cu KeepSeedForSell/KeepSeedForSellMulti (tuong thich nguoc).
    if type(CFG.KeepCropsForSell) == "table" then
        ensure("AutoCollect").KeepCropsForSell = CFG.KeepCropsForSell
    elseif type(CFG.KeepSeedForSell) == "table" then
        ensure("AutoCollect").KeepCropsForSell = CFG.KeepSeedForSell
    end
    if tonumber(CFG.KeepCropsForSellMulti) then
        ensure("AutoCollect").KeepCropsForSellMulti = tonumber(CFG.KeepCropsForSellMulti)
    elseif tonumber(CFG.KeepSeedForSellMulti) then
        ensure("AutoCollect").KeepCropsForSellMulti = tonumber(CFG.KeepSeedForSellMulti)
    end
    -- SELL ALL KHI x4 (top-level): cay trong list -> gia >= x4 thi BAN SACH (bo dieu kien dot bien) de tieu
    -- thu seed. Hoat dong doc lap voi KeepCropsForSell. Doc top-level -> AutoCollect.
    if type(CFG.SellAllForMultipliers) == "table" then
        ensure("AutoCollect").SellAllForMultipliers = CFG.SellAllForMultipliers
    end
    -- SellCenterPos / SellFirstMinSave (top-level): áp cho cả claim seed + mua pet (teleport qua nút Sell=tâm).
    -- Khai 1 chỗ ở config -> chắc chắn nạp (không phụ thuộc default theo version kaitun).
    if CFG.SellCenterPos ~= nil then
        ensure("AutoCollectDrops").SellCenterPos = CFG.SellCenterPos
        ensure("AutoTameWildPet").SellCenterPos = CFG.SellCenterPos
    end
    if tonumber(CFG.SellFirstMinSave) then
        ensure("AutoCollectDrops").SellFirstMinSave = tonumber(CFG.SellFirstMinSave)
        ensure("AutoTameWildPet").SellFirstMinSave = tonumber(CFG.SellFirstMinSave)
    end
    -- Lock Fruit: khóa (favorite) quả theo tên -> game không bán/không gửi. Nhận {"tên",...} hoặc {tên=true}.
    if type(CFG["Lock Fruit"]) == "table" then
        local t = ensure("LockFruits")
        local names = {}
        for k, v in pairs(CFG["Lock Fruit"]) do
            if type(v) == "string" and v ~= "" then names[#names + 1] = v
            elseif type(k) == "string" and k ~= "" and v ~= false then names[#names + 1] = k end
        end
        t.List = names
        t.Enabled = #names > 0
    end
    -- Gear.SprinklerStack: số sprinkler đặt chồng cùng vị trí
    if type(CFG.Gear) == "table" and tonumber(CFG.Gear.SprinklerStack) then
        ensure("AutoSprinkler").Stack = tonumber(CFG.Gear.SprinklerStack)
    end
    -- Gear.PlaceAtDensest / Gear.DensityRadius: đặt sprinkler ở VÙNG MẬT ĐỘ cây cao nhất (không đặt bậy).
    if type(CFG.Gear) == "table" then
        if type(CFG.Gear.PlaceAtDensest) == "boolean" then ensure("AutoSprinkler").PlaceAtDensest = CFG.Gear.PlaceAtDensest end
        if tonumber(CFG.Gear.DensityRadius) then ensure("AutoSprinkler").DensityRadius = tonumber(CFG.Gear.DensityRadius) end
    end
    -- Pets: Max Slots / Unequip Others / Enable (công tắc tổng pet)
    if type(CFG.Pets) == "table" then
        if tonumber(CFG.Pets["Max Slots"]) then
            ensure("AutoPurchasePetSlot").MaxSlots = tonumber(CFG.Pets["Max Slots"])
        end
        if type(CFG.Pets["Unequip Others"]) == "boolean" then
            ensure("AutoEquipPet").UnequipOthers = CFG.Pets["Unequip Others"]
        end
        if CFG.Pets.Enable == false then
            for _, name in ipairs({ "AutoEquipPet", "AutoTameWildPet", "AutoHatchEgg",
                "AutoPurchasePetSlot", "AutoSnapPets" }) do
                ensure(name).Enabled = false
            end
        end
    end
end

setDefault(CFG, "ActionLogEnabled", true)
setDefault(CFG, "SideTaskMinDelay", 1.5)   -- delay tối thiểu cho tác vụ phụ (mua seed/gear/crate/egg/sprinkler...) -> nhẹ FPS
-- TURBO FPS (trick cua chong): task NANG (nuke/xoa do/quet lon) mo cap len muc nay chay VU roi khoa lai cap cu.
setDefault(CFG, "WaitAlivePollInterval", 1)
setDefault(CFG, "ForceFullGc", false)
setDefault(CFG, "TurboFps", 120)
setDefault(CFG, "TurboMaxSeconds", 45)
-- BOOT TUAN TU (chong yeu cau "chay tung flow, chap nhan ~60s chuan bi cho on dinh"):
setDefault(CFG, "BootSequential", true)   -- false = kieu cu (tat ca task xong vao ngay sau fps boost)
setDefault(CFG, "BootDataWait", 45)       -- doi DATA vuon (SyncAllGardens) toi da N giay truoc khi tha wave 1
setDefault(CFG, "BootWaveGap", 5)         -- nghi giua cac wave (giay)
setDefault(CFG, "BootMaxWait", 90)        -- chot an toan: task doi qua N giay thi tu tha (phong sequencer loi)
-- SIEU TOI UU RAM (dot 3): MemWatch do heap Lua cua script moi MemWatchDelay giay -> GUI hien "Lua xxMB".
-- Heap vuot LuaHeapSoftMB -> tu purge cache dung-lai-duoc + GC full ngay (khong doi MemJanitor 60s).
setDefault(CFG, "LuaHeapSoftMB", 150)
setDefault(CFG, "MemWatchDelay", 20)
-- CPU SAVER (đợt 10 - chạy Linux nhiều acc): giãn nhịp TOÀN BỘ loop qua AdaptiveDelay + rã pha.
-- Delay số nguyên (2/5/10/15/30s) hay TRÙNG PHA -> nhiều task thức dậy cùng giây = CPU spike;
-- Jitter ±15% làm lệch pha ngẫu nhiên -> CPU phẳng. Task quan trọng (hái/bán/guard) nhân ÍT hơn
-- (ImportantMultiplier) để không mất tốc farm; webhook (ExactDelayTasks) giữ nguyên nhịp.
-- Viết tắt: CpuSaver = true (bật mặc định) hoặc CpuSaver = <số> (số = DelayMultiplier).
if type(CFG.CpuSaver) == "boolean" then
    CFG.CpuSaver = { Enabled = CFG.CpuSaver }
elseif type(CFG.CpuSaver) == "number" then
    CFG.CpuSaver = { Enabled = true, DelayMultiplier = CFG.CpuSaver }
end
CFG.CpuSaver = CFG.CpuSaver or {}
setDefault(CFG.CpuSaver, "Enabled", false)
setDefault(CFG.CpuSaver, "DelayMultiplier", 2)       -- task phụ: delay x2
setDefault(CFG.CpuSaver, "ImportantMultiplier", 1.3) -- task quan trọng (ImportantLoopTasks): x1.3
setDefault(CFG.CpuSaver, "MinLoopDelay", 1)          -- sàn delay cho task PHỤ (giây); task quan trọng không ép sàn
setDefault(CFG.CpuSaver, "Jitter", 0.15)             -- ±15% ngẫu nhiên rã pha; 0 = tắt

CFG.AutoBuySeed = CFG.AutoBuySeed or {}
setDefault(CFG.AutoBuySeed, "Enabled", true)
setDefault(CFG.AutoBuySeed, "Delay", 0.35)
setDefault(CFG.AutoBuySeed, "Mode", "Smart")
setDefault(CFG.AutoBuySeed, "MinRarity", "Common")
setDefault(CFG.AutoBuySeed, "KeepSheckles", 0)
setDefault(CFG.AutoBuySeed, "MaxPerSeedPerCycle", 50)
setDefault(CFG.AutoBuySeed, "List", {})
-- LoopGap: số giây CỘNG THÊM vào nhịp vòng mua (trước hardcode +3). Giảm = quét dày hơn.
-- Lưu ý nhịp thật còn nhân CriticalDelayMultiplier (2.4 khi FPS cap<15) + sàn SideTaskMinDelay (3s khi critical).
setDefault(CFG.AutoBuySeed, "LoopGap", 3)
-- InstantRestockBuy: watch StockValues.SeedShop.Items[*].Value -> restock là mua NGAY (không chờ vòng loop).
setDefault(CFG, "InstantRestockBuy", true)

CFG.AutoPlant = CFG.AutoPlant or {}
setDefault(CFG.AutoPlant, "Enabled", true)
setDefault(CFG.AutoPlant, "Delay", 0.25)
setDefault(CFG.AutoPlant, "PlantPerSeed", 50)
setDefault(CFG.AutoPlant, "PauseWhenPlotFull", true)
setDefault(CFG.AutoPlant, "PlantGridMode", true)
setDefault(CFG.AutoPlant, "PlantSpacing", 2)
setDefault(CFG.AutoPlant, "GridMargin", 0.9)
-- LỘ TRÌNH TRỒNG (PlantQuota): mỗi loại seed chỉ trồng tối đa N cây trong plot.
-- Đếm cây đang trồng theo attribute SeedName của model trong plot.Plants (xác nhận kaitun.lua:4296).
-- Trồng nhiều cây xịn (cao cấp = 50), ít cây phổ thông (Carrot 10, đám common 4) -> tối ưu tiền.
-- Đủ quota thì KHÔNG trồng thêm loại đó (seed dư nằm lại trong túi). Bật/tắt bằng UsePlantQuota.
setDefault(CFG.AutoPlant, "UsePlantQuota", true)
setDefault(CFG.AutoPlant, "OnlyQuota", false)   -- true = CHỈ trồng cây có trong PlantQuota (ngoài list không trồng)
-- RAINBOW SEED (chồng báo: "rainbow seed trong túi mà không thấy trồng"): GỐC LỖI = ValuableWatcher.
-- KeepRainbowSeed mặc định true -> ShouldKeepSeed() trả TRUE cho mọi seed rainbow -> AutoPlant SKIP
-- "keep seed" -> không bao giờ trồng. Nhưng trồng rainbow seed = ra CÂY RAINBOW (giá trị nhất) nên phải
-- trồng. Bật (mặc định): rainbow seed LUÔN được trồng - bỏ qua cả keep LẪN OnlyQuota (rainbow hiếm,
-- không làm ngập vườn). false = tôn trọng KeepRainbowSeed như cũ (giữ trong túi, không trồng).
setDefault(CFG.AutoPlant, "PlantRainbowSeeds", true)
setDefault(CFG.AutoPlant, "FreshAcc", false)    -- FRESH ACC: dưới PlantSwitch cây -> trồng HẾT (bỏ quota); cây single-harvest luôn trồng hết
setDefault(CFG.AutoPlant, "PlantSwitch", 0)     -- ngưỡng cây: dưới số này = chế độ fresh (mua+trồng hết), >= = quota. 0 = tắt fresh
-- FIX BUG (chồng báo: "set 0 mà vẫn trồng carrot"): trước đây cây TRỒNG-1-LẦN (IsSingleHarvest:
-- Carrot/Tulip/Bamboo/Mushroom - xác nhận SeedData.lua) BỎ QUA quota + OnlyQuota ("luôn trồng hết")
-- -> set Carrot=0 / không khai trong PlanQuota vẫn bị trồng đầy vườn. Giờ MẶC ĐỊNH quota THẮNG:
-- khai số nào trồng đúng số đó (0 = CẤM), ngoài list + OnlyQuota = không trồng, TrimToQuota cũng đào
-- được. true = quay lại kiểu cũ (single-harvest trồng hết bất kể quota; FreshAcc vẫn luôn bỏ quota).
setDefault(CFG.AutoPlant, "SinglePlantIgnoreQuota", false)
-- SINGLE-FILL (chồng 2026-07: "seed 1-lần tồn đọng trong túi, không thấy tuột"): cây TRỒNG-1-LẦN
-- tự BIẾN MẤT sau khi hái -> không chiếm slot lâu dài. Quota số nhỏ (vd Tulip=3) làm tiêu thụ chậm
-- hơn tốc độ mua cả trăm lần -> seed chất đống. Bật (mặc định): seed 1-lần có quota DƯƠNG trong
-- PlanQuota + nằm trong LIST MUA -> trồng LẤP KÍN chỗ trống (bỏ số quota), xoay vòng mua->trồng->
-- hái->bán liên tục. VẪN TÔN TRỌNG Ý CHỒNG: không khai trong PlanQuota (vd Carrot) = KHÔNG trồng;
-- khai 0 = CẤM; seed đặc biệt (Gold/Rainbow/Mega) không có trong list mua = không bị fill.
setDefault(CFG.AutoPlant, "SinglesFillFreeSlots", true)
setDefault(CFG.AutoPlant, "SingleFillOnlyBought", true)  -- fill CHỈ seed có trong list MUA (chặn seed đặc biệt)
setDefault(CFG.AutoPlant, "SingleFillList", {})          -- ép fill thêm loại khai tay (bất kể list mua; quota=0 vẫn cấm)
setDefault(CFG.AutoPlant, "SingleFillReserve", 0)        -- chừa N slot trống không fill (0 = fill hết chỗ trống)
setDefault(CFG.AutoPlant, "PlantQuota", {
    ["Carrot"] = 10,
    ["Strawberry"] = 4,
    ["Blueberry"] = 4,
    ["Tulip"] = 4,
    ["Tomato"] = 4,
    ["Apple"] = 4,
    ["Bamboo"] = 50,
    ["Corn"] = 4,
    ["Cactus"] = 4,
    ["Pineapple"] = 4,
    ["Mushroom"] = 50,
    ["Green Bean"] = 50,
    ["Banana"] = 50,
    ["Grape"] = 50,
    ["Coconut"] = 50,
    ["Mango"] = 50,
    ["Dragon Fruit"] = 50,
    ["Acorn"] = 50,
    ["Cherry"] = 50,
    ["Sunflower"] = 50,
    ["Venus Fly Trap"] = 50,
    ["Pomegranate"] = 50,
    ["Poison Apple"] = 50,
    ["Moon Bloom"] = 50,
    ["Dragon's Breath"] = 50,
})

CFG.AutoShovelReplace = CFG.AutoShovelReplace or {}
setDefault(CFG.AutoShovelReplace, "Enabled", false)
setDefault(CFG.AutoShovelReplace, "Delay", 5)
setDefault(CFG.AutoShovelReplace, "OnlyWhenPlotFull", true)
setDefault(CFG.AutoShovelReplace, "PlotFullCount", 0)
setDefault(CFG.AutoShovelReplace, "KeepMutations", { "Gold", "Rainbow" })
setDefault(CFG.AutoShovelReplace, "MaxReplacePerCycle", 1)
setDefault(CFG.AutoShovelReplace, "MinScoreGain", 1.0)
setDefault(CFG.AutoShovelReplace, "PlotFullSignalWindow", 30)
-- SAFE PLANT: [tên cây] = số cây tối thiểu LUÔN chừa lại khi đào. 0 = giữ TOÀN BỘ (không đào loại đó).
setDefault(CFG.AutoShovelReplace, "SafePlants", {
    ["Moon Bloom"] = 1,
    ["Dragon's Breath"] = 1,
    ["Venus Fly Trap"] = 1,
    ["Sunflower"] = 1,
    ["Cherry"] = 1,
    ["Pomegranate"] = 1,
    ["Poison Apple"] = 1,
})

CFG.AutoBuyGear = CFG.AutoBuyGear or {}
setDefault(CFG.AutoBuyGear, "Enabled", true)
setDefault(CFG.AutoBuyGear, "Delay", 0.5)
setDefault(CFG.AutoBuyGear, "Mode", "Smart")
setDefault(CFG.AutoBuyGear, "MinRarity", "Rare")
setDefault(CFG.AutoBuyGear, "KeepSheckles", 0)
setDefault(CFG.AutoBuyGear, "MaxPerItemPerCycle", 10)
setDefault(CFG.AutoBuyGear, "PrioritizeSprinklers", true)
setDefault(CFG.AutoBuyGear, "AllowPriorityBelowMinRarity", true)
setDefault(CFG.AutoBuyGear, "IgnoreSeedFirst", true)
setDefault(CFG.AutoBuyGear, "PriorityList", {
    "Super Sprinkler",
    "Legendary Sprinkler",
    "Rare Sprinkler",
    "Uncommon Sprinkler",
    "Common Sprinkler",
})
setDefault(CFG.AutoBuyGear, "ExcludeList", {
    "Jump Mushroom",
    "Speed Mushroom",
    "Shrink Mushroom",
})
setDefault(CFG.AutoBuyGear, "List", {})

CFG.AutoBuyCrate = CFG.AutoBuyCrate or {}
setDefault(CFG.AutoBuyCrate, "Enabled", true)
setDefault(CFG.AutoBuyCrate, "Delay", 0.5)
setDefault(CFG.AutoBuyCrate, "Mode", "Smart")
setDefault(CFG.AutoBuyCrate, "MinRarity", "Epic")
setDefault(CFG.AutoBuyCrate, "KeepSheckles", 0)
setDefault(CFG.AutoBuyCrate, "MaxPerItemPerCycle", 3)
setDefault(CFG.AutoBuyCrate, "IgnoreSeedFirst", true)
setDefault(CFG.AutoBuyCrate, "IgnoreGearFirst", true)
setDefault(CFG.AutoBuyCrate, "List", {})

CFG.AutoEquipGear = CFG.AutoEquipGear or {}
setDefault(CFG.AutoEquipGear, "Enabled", false)
setDefault(CFG.AutoEquipGear, "Gear", "")

CFG.AutoCollect = CFG.AutoCollect or {}
setDefault(CFG.AutoCollect, "Enabled", true)
setDefault(CFG.AutoCollect, "Delay", 1)
setDefault(CFG.AutoCollect, "IdleDelay", 0.5)
setDefault(CFG.AutoCollect, "ContinuousDelay", 0.05)  -- còn quả -> lặp NGAY ~0.1s (hái liên tục, ko "roẹt rồi ngắt")
-- THỨ TỰ HÁI (chồng chốt): "rarity" = ĐỘ HIẾM GIẢM DẦN — cây hiếm cao hái trước (rarity lấy từ
-- SeedData[].Rarity, xác nhận trong source; cùng độ hiếm -> quả đáng tiền trước, rồi gần trước).
-- Kết hợp PrioritizeSingleHarvest=true bên dưới: cây 1-LẦN-HÁI luôn xếp TRƯỚC hết.
-- Mode cũ vẫn dùng được: "oldest" = chín lâu nhất trước; "valuable" = giá trị cao trước; "near" = gần trước.
setDefault(CFG.AutoCollect, "SortMode", "rarity")
setDefault(CFG.AutoCollect, "RipeBucket", 5)         -- gom quả chín cách nhau < 5s vào 1 nhóm tuổi (rồi xịn trước)
setDefault(CFG.AutoCollect, "RemoteOnly", true)
setDefault(CFG.AutoCollect, "TeleportToFruit", false)
setDefault(CFG.AutoCollect, "TeleportDistance", 4)
setDefault(CFG.AutoCollect, "TeleportYOffset", 2)
setDefault(CFG.AutoCollect, "TeleportWait", 0.05)
setDefault(CFG.AutoCollect, "TriggerPromptFallback", false)
setDefault(CFG.AutoCollect, "MaxPerCycle", 120)
setDefault(CFG.AutoCollect, "MaxTeleportsPerCycle", 0)
setDefault(CFG.AutoCollect, "ReturnHomeAfterCollect", false)
setDefault(CFG.AutoCollect, "StayInGarden", true)
setDefault(CFG.AutoCollect, "BetweenCollect", 0.03)
setDefault(CFG.AutoCollect, "PauseWhenFull", true)
setDefault(CFG.AutoCollect, "PrioritizeValuable", true)
setDefault(CFG.AutoCollect, "TeleportToValuable", false)
setDefault(CFG.AutoCollect, "MaxValuableTeleports", 8)
setDefault(CFG.AutoCollect, "MinFruitScore", 0)
-- CHONG LAG (chong yeu cau): DataHarvestBatch = cap so qua hai MOI VONG (trai deu tai theo thoi gian
-- thay vi don 120 qua/lan -> muot hon). 0 = tat (dung MaxPerCycle nhu cu).
-- DataHarvestDelay = nhip cho giua tung qua trong vong; 0 = dung BetweenCollect cu.
setDefault(CFG.AutoCollect, "DataHarvestBatch", 0)
setDefault(CFG.AutoCollect, "DataHarvestDelay", 0)
-- OPTION cach hai: false = ban thang remote Garden.CollectFruit (mac dinh, nhanh nhat).
-- true = kich fireproximityprompt (game tu fire CollectFruit ho). LUU Y: van ton remote do +
-- cooldown ~0.025s/prompt -> thuong CHAM hon; de cho user tu chon thu.
setDefault(CFG.AutoCollect, "UsePromptHarvest", false)
-- PrioritizeSingleHarvest: DA WIRE ca 2 che do (sort prompt trong doAutoCollect + hai CAY truoc trong
-- doDataHarvest) theo SOURCE SeedData.IsSingleHarvest.
-- MAC DINH BAT (chong chot): cay 1-LAN-HAI luon hai TRUOC (hai xong cay bien mat -> mo o trong som),
-- roi moi toi qua thuong theo SortMode="rarity" (do hiem giam dan). Dat false neu muon tat.
setDefault(CFG.AutoCollect, "PrioritizeSingleHarvest", true)
-- DATA-HARVEST FALLBACK: het prompt workspace (Nuke All xoa cay/prompt) -> hai bang DU LIEU vuon doc tu remote
-- Garden (SyncAllGardens/Plant±/Fruit±) -> KHONG can vat the cay/prompt. Bat mac dinh de Nuke All van hai duoc.
setDefault(CFG.AutoCollect, "UseDataHarvestFallback", true)
-- ForceDataHarvest=true: LUON dung data-harvest (che do 3) ke ca khi con prompt workspace (khong can Nuke All).
-- false (mac dinh): chi data-harvest khi het prompt (Nuke All); con prompt thi theo UsePromptHarvest.
setDefault(CFG.AutoCollect, "ForceDataHarvest", false)
-- moi (plant,fruit) chi ban lai sau ngan giay nay -> chong spam remote (qua chua chin van se thu lai sau).
setDefault(CFG.AutoCollect, "DataHarvestDedup", 4)
-- FIX "treo ~3 phut collect cham dan": CHI ban CollectFruit vao qua DA CHIN (Age >= MaxAge, y het dieu kien
-- game gan HarvestPrompt - FruitVisualizerController:389). Truoc day ban vao MOI qua ke ca qua non moi 4s
-- -> lu remote vo ich nghen kenh len server, cang treo cang cham; rejoin het vi hang doi mang reset.
-- false = quay ve kieu cu (chi dung khi data MaxAge loi).
setDefault(CFG.AutoCollect, "DataHarvestRipeOnly", true)
-- Tu xin server BAN LAI toan bo vuon moi N giay (Garden.RequestGardens - remote client fire duoc,
-- GardenSyncController:48 game tu fire luc boot). SyncAllGardens ve la FULL RESYNC -> xoa ghost/data cu
-- (nguyen nhan "rejoin lai hai vu vu": rejoin = duoc ban lai data tuoi). 0 = tat.
setDefault(CFG.AutoCollect, "DataResyncEvery", 90)
-- RIPE CHUAN (chong yeu cau): mac dinh dung Age server-sync THUC de xet chin (Age>=MaxAge), khong uoc
-- luong troi giua 2 sync -> het "false-ripe" (qua chua chin bi tinh chin -> ban truot -> ket). Dat false
-- = quay ve uoc luong (hai som ~1 sync nhung co the ban truot qua gan chin). DataResyncEvery cang nho
-- (vd 45) thi Age cang tuoi -> hai chin nhanh hon ma van chuan.
setDefault(CFG.AutoCollect, "DataHarvestUseRawAge", true)
CFG.AutoCollect.RemoteOnly = true
CFG.AutoCollect.TeleportToFruit = false
CFG.AutoCollect.TriggerPromptFallback = false
CFG.AutoCollect.MaxTeleportsPerCycle = 0
CFG.AutoCollect.ReturnHomeAfterCollect = false

CFG.NightNotifier = CFG.NightNotifier or {}
setDefault(CFG.NightNotifier, "Enabled", true)
setDefault(CFG.NightNotifier, "ShowGui", true)
setDefault(CFG.NightNotifier, "LogChanges", true)
setDefault(CFG.NightNotifier, "BlockSellAtNight", true)

CFG.AntiSteal = CFG.AntiSteal or {}
setDefault(CFG.AntiSteal, "Enabled", true)
setDefault(CFG.AntiSteal, "Delay", 0.35)
setDefault(CFG.AntiSteal, "OnlyAtNight", true)
setDefault(CFG.AntiSteal, "EquipShovel", true)
setDefault(CFG.AntiSteal, "RequireShovel", true)
setDefault(CFG.AntiSteal, "TeleportToIntruder", true)
setDefault(CFG.AntiSteal, "TeleportDistance", 5)
setDefault(CFG.AntiSteal, "TeleportYOffset", 0)
setDefault(CFG.AntiSteal, "HitsPerTarget", 3)
setDefault(CFG.AntiSteal, "BetweenHits", 0.6)
setDefault(CFG.AntiSteal, "TargetCooldown", 0.5)
setDefault(CFG.AntiSteal, "ReturnAfterDefend", true)
-- MAC DINH TAT (chong yeu cau): Guard CHI teleport khi co TROM, KHONG tu "dung giua o" luc ranh -> het bi keo giat
-- khi dang collect. Muon bat lai kieu dung-o thi set CFG.AntiSteal.StandInGardenWhenIdle = true.
setDefault(CFG.AntiSteal, "StandInGardenWhenIdle", false)

-- ANTI-PUSH: chống người khác dùng Wheelbarrow / va chạm đẩy mình ra khỏi plot.
-- Cú đẩy là VẬT LÝ (không có remote chặn trong source) -> chỉ khóa client: zero vận tốc + kéo về nhà.
CFG.AntiPush = CFG.AntiPush or {}
setDefault(CFG.AntiPush, "Enabled", true)
setDefault(CFG.AntiPush, "OnlyAtNight", true)   -- true = chỉ chống đẩy ban đêm (lúc bị trộm). false = chống cả ngày.
setDefault(CFG.AntiPush, "MaxDrift", 6)         -- lệch khỏi nhà > N studs thì kéo về
setDefault(CFG.AntiPush, "CheckInterval", 0.15) -- khong can zero van toc moi frame

CFG.Dashboard = CFG.Dashboard or {}
setDefault(CFG.Dashboard, "Enabled", true)
setDefault(CFG.Dashboard, "Visible", true)
setDefault(CFG.Dashboard, "ToggleKey", "RightShift")
setDefault(CFG.Dashboard, "RefreshRate", 0.5)
setDefault(CFG.Dashboard, "MinRefreshRate", 2)
setDefault(CFG.Dashboard, "MaxLogs", 18)
CFG.Dashboard.MaxLogs = math.min(tonumber(CFG.Dashboard.MaxLogs) or 18, 24)

CFG.AutoStartGame = CFG.AutoStartGame or {}
setDefault(CFG.AutoStartGame, "Enabled", true)
setDefault(CFG.AutoStartGame, "Delay", 2)
setDefault(CFG.AutoStartGame, "MaxReadyFires", 8)
setDefault(CFG.AutoStartGame, "ForceLoadingAttributes", false)
setDefault(CFG.AutoStartGame, "FireTutorialReady", true)
setDefault(CFG.AutoStartGame, "TapToPlay", true)
setDefault(CFG.AutoStartGame, "TapClickCount", 5)
setDefault(CFG.AutoStartGame, "TapHold", 0.08)
setDefault(CFG.AutoStartGame, "UseVirtualInput", true)
setDefault(CFG.AutoStartGame, "UseTouchInput", true)
setDefault(CFG.AutoStartGame, "UseVirtualUser", false)
setDefault(CFG.AutoStartGame, "UseMouseFallback", false)
setDefault(CFG.AutoStartGame, "StopWhenReady", true)
setDefault(CFG.AutoStartGame, "ReadyStableSeconds", 3)
setDefault(CFG.AutoStartGame, "InitialGraceDelay", 0.5)
setDefault(CFG.AutoStartGame, "ForceLoadingAfter", 180)
setDefault(CFG.AutoStartGame, "FireReadyAfter", 0.5)
setDefault(CFG.AutoStartGame, "HideTapScreenAfter", 0)
setDefault(CFG.AutoStartGame, "ForceHideLoadingAfter", 0)
setDefault(CFG.AutoStartGame, "ForceTapWithoutText", false)
setDefault(CFG.AutoStartGame, "ForceOnlyAfterPrompt", false)
setDefault(CFG.AutoStartGame, "SkipOfflineCutscene", true)
setDefault(CFG.AutoStartGame, "OfflineSkipHold", 1.15)
CFG.AutoStartGame.ForceLoadingAttributes = false
CFG.AutoStartGame.ForceTapWithoutText = false
CFG.AutoStartGame.ForceHideLoadingAfter = 0

CFG.AutoSell = CFG.AutoSell or {}
setDefault(CFG.AutoSell, "Enabled", true)
setDefault(CFG.AutoSell, "Delay", 30)
setDefault(CFG.AutoSell, "DelayMax", 90)
setDefault(CFG.AutoSell, "TeleportToStevenBeforeSell", false)
setDefault(CFG.AutoSell, "TeleportDistance", 5)
setDefault(CFG.AutoSell, "TeleportWait", 0.75)
setDefault(CFG.AutoSell, "PostPreviewWait", 0.25)
setDefault(CFG.AutoSell, "PreSellWait", 0.5)
setDefault(CFG.AutoSell, "SellWhenFull", true)
setDefault(CFG.AutoSell, "FullThreshold", 0.95)
setDefault(CFG.AutoSell, "FullCheckDelay", 1)
setDefault(CFG.AutoSell, "UseDailyDeal", true)

CFG.AutoClaimMailbox = CFG.AutoClaimMailbox or {}
setDefault(CFG.AutoClaimMailbox, "Enabled", true)
setDefault(CFG.AutoClaimMailbox, "Delay", 10)
setDefault(CFG.AutoClaimMailbox, "MaxPerCycle", 20)

-- MAILBOX TUTORIAL GATE (mục 2): game chặn gift khi đang tutorial.
setDefault(CFG, "MailboxEnabled", true)          -- false = tắt cứng toàn bộ mailbox
setDefault(CFG, "AutoTutorialCheck", true)        -- true = thử bắn Tutorial.Complete khi đang tutorial
setDefault(CFG, "SkipMailboxIfTutorial", true)    -- true = bỏ qua mailbox khi chưa xong tutorial
-- TotalPlots (mục 1,4): tổng plots để tính %/hiển thị "Plants: x/total".
-- 0 = auto đếm part PlantArea (source KHÔNG có hằng số max cây thật -> chồng set số đúng của acc).
setDefault(CFG, "TotalPlots", 0)

-- TRIM TO QUOTA (mục 6): đào cây DƯ so với PlanQuota về đúng quota (KHÔNG xoá hết plot).
CFG.TrimToQuota = CFG.TrimToQuota or {}
setDefault(CFG.TrimToQuota, "Enabled", false)              -- mặc định TẮT (đào là mất vĩnh viễn)
setDefault(CFG.TrimToQuota, "Limit", 0)                     -- 0 = trim liên tục; "100%" hoặc số = chỉ trim khi tổng cây >= mức này
setDefault(CFG.TrimToQuota, "DestroyUntil", 0)             -- 0 = trim hết phần dư; "90%"/số = dừng khi tổng cây <= mức này
setDefault(CFG.TrimToQuota, "Delay", 8)
setDefault(CFG.TrimToQuota, "MaxPerCycle", 20)             -- mỗi vòng đào tối đa N cây. 0 = KHÔNG giới hạn (đào hết tới Destroy Until)
setDefault(CFG.TrimToQuota, "DigDelay", 0.3)              -- nghỉ giữa mỗi nhát đào (giây). Nhỏ = đào nhanh hơn (đừng < 0.05 dễ bị server chặn)
setDefault(CFG.TrimToQuota, "KeepMutations", { "Gold", "Rainbow" })
setDefault(CFG.TrimToQuota, "DigUnlisted", false)  -- true = đào luôn cây KHÔNG có trong quota (ngoài PlanQuota)

CFG.AutoSnapPets = CFG.AutoSnapPets or {}
setDefault(CFG.AutoSnapPets, "Enabled", true)
setDefault(CFG.AutoSnapPets, "Delay", 15)

CFG.AutoHatchEgg = CFG.AutoHatchEgg or {}
setDefault(CFG.AutoHatchEgg, "Enabled", true)
setDefault(CFG.AutoHatchEgg, "Delay", 0.5)

CFG.AutoEquipPet = CFG.AutoEquipPet or {}
setDefault(CFG.AutoEquipPet, "Enabled", true)
setDefault(CFG.AutoEquipPet, "Delay", 5)
setDefault(CFG.AutoEquipPet, "Mode", "Smart")
setDefault(CFG.AutoEquipPet, "List", {})
-- Smart: equip pet XỊN nhất trước (sort theo rarity*price). MinRarity = chỉ equip pet >= bậc này.
-- "Common" = equip mọi pet để lấp slot; đặt "Legendary" nếu chỉ muốn equip legendary+.
setDefault(CFG.AutoEquipPet, "MinRarity", "Common")
-- true: KHÔNG equip pet có tên trong AutoMailPets.PetNames -> để chúng nằm trong túi
-- (Equipped=false) cho AutoMailPets gửi đi. Pet đã equip thì game KHÔNG cho gift.
setDefault(CFG.AutoEquipPet, "SkipMailRarity", true)

setDefault(CFG.AutoSell, "SellAtNight", true)
setDefault(CFG.AutoSell, "ReturnHomeAfterSell", false)
CFG.AutoSell.TeleportToStevenBeforeSell = false
CFG.AutoSell.ReturnHomeAfterSell = false

CFG.AutoCollectDrops = CFG.AutoCollectDrops or {}
setDefault(CFG.AutoCollectDrops, "Enabled", true)
setDefault(CFG.AutoCollectDrops, "Delay", 0.05)
setDefault(CFG.AutoCollectDrops, "EventDynamicScan", true)
setDefault(CFG.AutoCollectDrops, "EventActiveDelay", 0.03)
setDefault(CFG.AutoCollectDrops, "IdleScanDelay", 0.2)   -- giảm 0.5->0.2: detect Gold/Rainbow seed NHANH hơn (scan SeedPackSpawn rất nhẹ)
setDefault(CFG.AutoCollectDrops, "PreEventWindow", 240)
setDefault(CFG.AutoCollectDrops, "MaxPerCycle", 200)
setDefault(CFG.AutoCollectDrops, "TeleportDistance", 3)
setDefault(CFG.AutoCollectDrops, "TeleportYOffset", 4)   -- bay CAO hơn (chống dính sàn/kẹt khi tween tới drop)
setDefault(CFG.AutoCollectDrops, "TeleportWait", 0.05)
setDefault(CFG.AutoCollectDrops, "IncludeSeedPackSpawns", true)
setDefault(CFG.AutoCollectDrops, "PrioritizeRainbowSeed", true)
-- ĐỘC CHIẾM KHI CLAIM SEED (chồng đợt 20): khi có seed spawn / đang claim -> MỌI task khác DỪNG (defer qua
-- loopTask), KHÔNG chèn gì vào; nhặt hết seed spam mới cho task khác chạy lại. Chỉ chừa chính AutoCollectDrops.
-- Mục đích: 10fps dồn hết nhịp cho claim -> nhặt kịp nhiều cục (không bị task khác giành CPU/kéo nhân vật).
setDefault(CFG.AutoCollectDrops, "ExclusiveSeedClaim", true)
-- INSTANT SPAWN DETECT: hook ChildAdded tren SeedPackSpawnServerLocations (dung nguon game nghe:
-- SpawnSeedPackController.lua:255) -> seed Rainbow/Gold/Mega VUA xuat hien la claim NGAY, khong doi
-- nhip quet (idle 0.2-0.4s + FPS thap keo dai -> truoc day cham chan nguoi khac).
setDefault(CFG.AutoCollectDrops, "InstantSpawnDetect", true)
-- TOUCH-CLAIM ("bluetooth"): firetouchinterest (API EXECUTOR) gia cham HRP vao part tu XA.
-- CHI ban khi part co TouchTransmitter (= server co nghe .Touched that - thay duoc tu client).
-- Server nhan touch co check khoang cach khong thi CHUA XAC NHAN (khong co script server trong dump)
-- -> best-effort: an thi claim khong can teleport, khong an van fallback teleport/prompt nhu cu.
setDefault(CFG.AutoCollectDrops, "UseTouchClaim", true)
setDefault(CFG.AutoCollectDrops, "SeedSpawnYOffset", 6)  -- bay CAO hơn tới seed (chồng: bay thấp dính sàn -> kẹt tween)
setDefault(CFG.AutoCollectDrops, "SeedSpawnWait", 0.12)
-- CACH DI CHUYEN toi seed (rainbow/gold) khi claim:
--   UseRespawnTeleport=true : CHET -> respawn -> spam CFrame toi seed. Server reset vi tri khi respawn nen
--                             KHONG bi keo ve (may yeu/lag). Chac an nhung CHAM hon (moi seed 1 lan chet+respawn).
--   false                   : dung CFrame/tween nhu cu (xem UseTweenTeleport).
-- Default lay theo CFG.UseRespawnTeleport o cap goc (config_with_notes.lua dat = true).
setDefault(CFG.AutoCollectDrops, "UseRespawnTeleport", CFG.UseRespawnTeleport == true)
setDefault(CFG.AutoCollectDrops, "RespawnSpamFrames", tonumber(CFG.RespawnSpamFrames) or 20)  -- so frame ghim vi tri sau respawn; claim hut thi tang 25-30
setDefault(CFG.AutoCollectDrops, "RespawnSettleWait", tonumber(CFG.RespawnSettleWait) or 0.1) -- cho on dinh sau respawn roi moi ghim
-- ====================================================================================
-- >>> CHINH TOC DO TWEEN O DAY (1 cho duy nhat, ap cho ca claim seed + mua pet) <<<
-- studs/giay: CAO = nhanh, THAP = muot/it bi keo lui. Muon giam thi ha so 30 ngay duoi (vd 20, 16, 12).
setDefault(CFG, "TweenSpeed", 22)
-- ====================================================================================
-- ON DINH CAMERA: chong loi "tween toi seed -> goc nhin bay ra xa". Khi nhan vat ra giua map (khong gian
-- mo) camera tu phong ve khoang zoom XA cua nguoi choi -> nhin nhu bay ra xa. Khoa CameraMaxZoomDistance
-- ve mot khoang GAN co dinh -> camera luon bam sat nhan vat suot tween. La PROPERTY CLIENT chuan Roblox.
CFG.CameraStable = CFG.CameraStable or {}
setDefault(CFG.CameraStable, "Enabled", true)
setDefault(CFG.CameraStable, "MaxZoom", 18)   -- studs: camera khong phong xa hon ngan nay (12-25 hop ly)
-- ====================================================================================
-- TWEEN TELEPORT: di chuyển MƯỢT tới seed (chống giật/kéo về) thay vì set CFrame nhảy. Mặc định BẬT.
setDefault(CFG.AutoCollectDrops, "UseTweenTeleport", true)
setDefault(CFG.AutoCollectDrops, "TweenSpeed", CFG.TweenSpeed)   -- lay tu nut tong CFG.TweenSpeed o tren
-- TAT tween-buoc-nho (no tween 50 studs roi nghi 0.05s moi buoc -> GIAT KHUNG tung nac). Dung 1 TWEEN LIEN MACH
-- (TweenMoveTo) GIONG teleporrrrr.lua -> muot. Muon thu lai kieu buoc-nho thi set = true.
setDefault(CFG.AutoCollectDrops, "UseSpamTweenTeleport", false)
setDefault(CFG.AutoCollectDrops, "ReachDistance", 10)
setDefault(CFG.AutoCollectDrops, "SpamTweenStep", 50)
setDefault(CFG.AutoCollectDrops, "SpamTweenDuration", 0.1)
setDefault(CFG.AutoCollectDrops, "SpamTweenDelay", 0.05)
setDefault(CFG.AutoCollectDrops, "TeleportButtons", { "Sell", "Garden" })  -- nút xét: Sell (tâm) + Garden (về nhà). Bỏ Seeds shop.
setDefault(CFG.AutoCollectDrops, "SellPressTimeout", 5)   -- bấm nút LẶP tới khi tới, tối đa N giây
setDefault(CFG.AutoCollectDrops, "SellPressInterval", 0.8) -- nhịp bấm lại nút (game lag phải bấm mấy lần)
setDefault(CFG.AutoCollectDrops, "UseSellFirst", true)    -- bấm nút Garden/Seeds/Sell rút ngắn đường rồi tween nốt
setDefault(CFG.AutoCollectDrops, "SellCenterPos", Vector3.new(269.75, 146.56, -127.07))  -- tọa độ TÂM (nút Sell) để tính rút ngắn (dùng dù part bị xóa)
setDefault(CFG.AutoCollectDrops, "SellFirstMinSave", 12)  -- nút phải rút ngắn >= ngần này studs mới bấm
setDefault(CFG.AutoCollectDrops, "SellFirstMinSave", 12)  -- nút phải rút ngắn >= ngần này studs mới bấm (seed xa = bấm)
-- Chờ ổn định sau khi TỚI seed rồi mới bắn. Tween đã tới mượt + đứng đúng chỗ -> để NHỎ (0.1) để bắn claim NGAY,
-- không chờ lâu (chồng: tới nơi phải bắn liên tục luôn). Tăng lên nếu server cần thời gian ghi nhận.
setDefault(CFG.AutoCollectDrops, "SeedSettleWait", 0.1)
setDefault(CFG.AutoCollectDrops, "SeedClaimMinStand", 2.5) -- đứng tại seed bắn liên tục tối thiểu 2.5s (chồng yêu cầu)
-- BAN TOI KHI SEED BIEN MAT moi qua cai khac, NHUNG toi da 3.5s/seed roi qua cai khac (chong yeu cau) -> khong ket lau.
setDefault(CFG.AutoCollectDrops, "SeedClaimMaxWait", 3.5)
setDefault(CFG.AutoCollectDrops, "SeedClaimFireInterval", 0.05)  -- nhip spam fire prompt: 0.05s/lan (chong duyet: FPS cap 60 du suc ban day gap doi)
setDefault(CFG.AutoCollectDrops, "SeedClaimNoPromptWait", 2.5)
setDefault(CFG.AutoCollectDrops, "SeedClaimHoldExtra", 0.35)
setDefault(CFG.AutoCollectDrops, "SeedClaimHoldExtraRainbow", 4)
setDefault(CFG.AutoCollectDrops, "SeedClaimHoldExtraGold", 4)
setDefault(CFG.AutoCollectDrops, "SeedClaimPostPromptWait", 1.5)
setDefault(CFG.AutoCollectDrops, "SeedClaimGrace", 0.5)
setDefault(CFG.AutoCollectDrops, "DropClaimPreWait", 0.05)
setDefault(CFG.AutoCollectDrops, "DropClaimFireInterval", 0.05)
setDefault(CFG.AutoCollectDrops, "DropClaimMaxWait", 5)
setDefault(CFG.AutoCollectDrops, "DropClaimNoPromptWait", 0.35)
setDefault(CFG.AutoCollectDrops, "BlastPromptsDuringSeedClaim", true)
setDefault(CFG.AutoCollectDrops, "BlastPromptRadius", 10)
setDefault(CFG.AutoCollectDrops, "BlastPromptOnlyRainbowGold", false)
-- FAST CLAIM seed EVENT (Mega/Rainbow/Gold/seed dac biet): TRUOC KHI respawn-teleport (ton ~1-2s chet+hoi sinh),
-- thu fire THANG ProximityPrompt cua seed do TU CHO DANG DUNG (khong teleport). fireproximityprompt la instant;
-- seed bien mat trong FastEventSeedTryWindow -> claim xong, BO teleport (nhat duoc NHIEU, rat nhanh). Neu het
-- cua so ma seed con -> FALLBACK y het cach cu (respawn-teleport). CHUA XAC NHAN server co check khoang cach
-- cho prompt seed hay khong (script server khong co trong dump) -> that bai thi tu ha ve cach cu, KHONG mat gi.
setDefault(CFG.AutoCollectDrops, "FastEventSeedClaim", true)
setDefault(CFG.AutoCollectDrops, "FastEventSeedTryWindow", 0.4)   -- khi DA trong tam: fire thang toi da ~0.4s roi moi fallback teleport
setDefault(CFG.AutoCollectDrops, "FastEventSeedFireInterval", 0.05)
setDefault(CFG.AutoCollectDrops, "FastEventSeedRange", 55)        -- chi fast-claim khi cach seed <= 55 studs (ngoai tam -> teleport luon)
setDefault(CFG.AutoCollectDrops, "ReturnHomeAfterCollect", true)
setDefault(CFG.AutoCollectDrops, "FreezeDuringSeedClaim", true)
setDefault(CFG.AutoCollectDrops, "StayHomeAtNight", true)   -- đêm: chỉ ra lấy Rainbow/Gold, còn lại ở nhà chống trộm
-- DANG EVENT O NGOAI LUON (chong duyet: "dang event thi cu lo di lay seed, khong can ve nha bao ve,
-- het event roi bao ve sau"): trong cua so event (dem + vua thay seed event trong EventStayOutSeconds)
-- -> KHONG teleport ve nha giua cac seed (AutoCollectDrops/AutoCollect/AntiPush deu ton trong) -> seed
-- ke tiep spawn gan cho dang dung co the fast-claim/touch ngay, khoi ton 1 luot respawn (~1.5-3s).
-- Hai/ban van chay binh thuong tu xa (data-harvest + SellAll deu la remote, khong can dung o plot).
setDefault(CFG.AutoCollectDrops, "StayOutDuringEvent", true)
setDefault(CFG.AutoCollectDrops, "EventStayOutSeconds", 150)
-- Ép tối thiểu nhỏ (0.2s) để không bị 0/âm; KHÔNG ép lên 4 nữa vì đã có blast lo việc chắc ăn,
-- và fireproximityprompt là instant nên giữ lâu vô nghĩa -> để giá trị config "nhanh" có hiệu lực.
CFG.AutoCollectDrops.SeedClaimHoldExtraRainbow = math.max(tonumber(CFG.AutoCollectDrops.SeedClaimHoldExtraRainbow) or 0, 0.2)
CFG.AutoCollectDrops.SeedClaimHoldExtraGold = math.max(tonumber(CFG.AutoCollectDrops.SeedClaimHoldExtraGold) or 0, 0.2)

CFG.AutoWater = CFG.AutoWater or {}
setDefault(CFG.AutoWater, "Enabled", true)
setDefault(CFG.AutoWater, "Delay", 2)
setDefault(CFG.AutoWater, "PerCycle", 20)
-- Ngân sách THỜI GIAN mỗi vòng tưới: ở FPS cap thấp (7-10) mỗi waitAlive(0.15) thực tế >= 1 frame ~0.14s
-- -> 20 phát ~ 3-6s GIỮ ToolLock -> AutoPlant/Collect bị SKIP liên tục = "đơ, vòng lặp không làm được gì".
-- Quá budget -> nhả lock, vòng sau tưới tiếp (không mất lượt, chỉ chia nhỏ).
setDefault(CFG.AutoWater, "MaxCycleSeconds", 1.5)

CFG.AutoSprinkler = CFG.AutoSprinkler or {}
setDefault(CFG.AutoSprinkler, "Enabled", true)
setDefault(CFG.AutoSprinkler, "Delay", 0.5)
setDefault(CFG.AutoSprinkler, "PerCycle", 5)
setDefault(CFG.AutoSprinkler, "MaxCycleSeconds", 2)   -- như AutoWater.MaxCycleSeconds (chống giữ ToolLock lâu ở FPS thấp)

-- GEAR FX KILL (fix "sài gear tuột FPS/đơ" - xác nhận source):
--   WateringcanController.lua:104-203: MỖI phát tưới = 1 vũng nước sống ~10s (EffectTime) + 3 tween,
--     Super Watering Can thêm 1 connection RenderStepped đổi màu cầu vồng SUỐT ~10.5s/vũng (dòng 133-139);
--     PlayWaterStream (dòng 207-328): +12 part giọt nước bay theo RenderStepped ~1s + tween + Debris.
--     AutoWater 20 phát/vòng + FX người khác tưới cũng replicate về -> chồng connection/part -> tuột FPS.
--     -> KillWateringFx: destroy part FX ("WateringCanFx"/"Stud_Part" trong workspace.Temporary) NGAY khi spawn.
--   SprinklerVisualizerController.lua:163-240: model sprinkler do CLIENT TỰ CLONE từ Assets.Sprinklers theo
--     data GardenSync -> XÓA client-side KHÔNG ảnh hưởng buff (server tính theo data). Mỗi model = 1 Sound
--     loop + PivotTo xoay 5 lần/s + update text timer mỗi frame + là mục tiêu hover-raycast (10 ray/frame).
--     -> HideSprinklers: sweep xóa model trong Gardens.Plot*.Sprinklers (GardenSync re-clone khi resync nên sweep định kỳ).
CFG.GearFxKill = CFG.GearFxKill or {}
setDefault(CFG.GearFxKill, "Enabled", true)
setDefault(CFG.GearFxKill, "KillWateringFx", true)
setDefault(CFG.GearFxKill, "HideSprinklers", true)
setDefault(CFG.GearFxKill, "Delay", 5)   -- nhịp sweep sprinkler (giây)

CFG.AutoOpenCrate = CFG.AutoOpenCrate or {}
setDefault(CFG.AutoOpenCrate, "Enabled", true)
setDefault(CFG.AutoOpenCrate, "Delay", 0.5)

CFG.AutoOpenSeedPack = CFG.AutoOpenSeedPack or {}
setDefault(CFG.AutoOpenSeedPack, "Enabled", true)
setDefault(CFG.AutoOpenSeedPack, "Delay", 0.5)

-- FAST CONFIRM SEED PACK (method "nhặt siêu nhanh" - XÁC NHẬN SOURCE): SeedPackOpenController.lua:595-609
-- server bắn ReplicateOpenSeedPack(player, id, packName, seedName, pos) -> client game chạy HẾT animation
-- SeedPackEffect.Open (~4.8s thường, ~8.6s nếu seed Legendary/Mythic - SeedPackEffect.lua:145-295) rồi MỚI
-- Fire ConfirmSeedPack(id, packName, seedName). Thời điểm confirm do CLIENT quyết -> mình fire NGAY khi nhận
-- event = nhận seed liền, bỏ 5-9s animation. Mega seed hay ra seed hiếm (animation dài nhất) -> lợi nhất.
CFG.FastSeedPackConfirm = CFG.FastSeedPackConfirm or {}
setDefault(CFG.FastSeedPackConfirm, "Enabled", true)

CFG.AutoSpendSkill = CFG.AutoSpendSkill or {}
setDefault(CFG.AutoSpendSkill, "Enabled", true)
setDefault(CFG.AutoSpendSkill, "Delay", 0.3)
setDefault(CFG.AutoSpendSkill, "Priority", { "MaxBackpack", "ShovelPower", "BaseSpeed", "BaseJump" })

CFG.AutoExpandGarden = CFG.AutoExpandGarden or {}
setDefault(CFG.AutoExpandGarden, "Enabled", true)
setDefault(CFG.AutoExpandGarden, "Delay", 10)
setDefault(CFG.AutoExpandGarden, "KeepSheckles", 0)
setDefault(CFG.AutoExpandGarden, "MaxExpansions", 0)
setDefault(CFG.AutoExpandGarden, "IgnoreSeedFirst", true)

CFG.AutoTier = CFG.AutoTier or {}
setDefault(CFG.AutoTier, "Enabled", false)
setDefault(CFG.AutoTier, "Delay", 45)
setDefault(CFG.AutoTier, "MoneyMid", 50000)
setDefault(CFG.AutoTier, "MoneyPro", 1000000)
setDefault(CFG.AutoTier, "DownMid", 30000)
setDefault(CFG.AutoTier, "DownPro", 700000)
setDefault(CFG.AutoTier, "NoDowngrade", true)   -- true = CHI LEN tier, khong tut (chong dao sach cay xin khi tien tut tam thoi)

CFG.AutoPurchasePetSlot = CFG.AutoPurchasePetSlot or {}
setDefault(CFG.AutoPurchasePetSlot, "Enabled", true)
setDefault(CFG.AutoPurchasePetSlot, "Delay", 15)
setDefault(CFG.AutoPurchasePetSlot, "KeepSheckles", 0)
setDefault(CFG.AutoPurchasePetSlot, "MaxSlots", 0)   -- 0 = mua tới max game; >0 = dừng ở số ô này
setDefault(CFG.AutoPurchasePetSlot, "IgnoreSeedFirst", true)   -- true = mua slot NGAY (ko nhuong mua seed) -> fix "du tien ma ko mua slot"

-- ===== Defaults cho các tính năng MỚI bổ sung =====
CFG.AutoRedeemCode = CFG.AutoRedeemCode or {}
setDefault(CFG.AutoRedeemCode, "Enabled", false)
setDefault(CFG.AutoRedeemCode, "Delay", 1.5)
setDefault(CFG.AutoRedeemCode, "List", {})
CFG.AntiAfk = CFG.AntiAfk or {}
setDefault(CFG.AntiAfk, "Enabled", true)             -- chống treo máy, mặc định BẬT
setDefault(CFG.AntiAfk, "JiggleInterval", 60)        -- giây: jiggle input định kỳ phòng Idled không bắn (gia cố)
-- ===== KILL GAME CONTROLLERS (đợt 9 - opt-in, ý tưởng "giảm scheduler Lua VM" đa tab): game có 186
-- controller client (PlayerScripts.Controllers), 110 con nối RenderStepped/Heartbeat -> MỖI FRAME Lua VM
-- resume hàng trăm callback DÙ ĐÃ tắt render 3D (tắt render chỉ tắt phần VẼ). Destroy controller
-- visual/tick -> giảm CPU mỗi frame + RAM churn (PlantVisualizer/FruitVisualizer không còn clone cây/quả
-- liên tục). FARM SỐNG vì mọi flow mua/trồng/hái/claim/mail = REMOTE tự fire + hook riêng của script
-- (đã chứng minh chạy ổn với Nuke All). GIỮ LẠI các con BƠM DATA (Keep bên dưới). MẶC ĐỊNH TẮT —
-- bật thử 1-2 tab trước khi lên đủ tab. PlayerModule (điều khiển char/camera) nằm NGOÀI folder
-- Controllers -> không bị đụng.
CFG.KillGameControllers = CFG.KillGameControllers or {}
setDefault(CFG.KillGameControllers, "Enabled", false)
setDefault(CFG.KillGameControllers, "Delay", 10)           -- giây chờ SAU LoadingScreenDone rồi mới giết
setDefault(CFG.KillGameControllers, "Keep", {
    "GardenSyncController",      -- BƠM data vườn: nhận SyncAllGardens + update Age TẠI CHỖ (data-harvest cần)
    "PlayerStateController",     -- BƠM replica tiền/kho (PlayerStateClient) - cap mua/stock đọc từ đây
    "PlantVisualizerController", -- tạo model cây plot.Plants (client-clone) - đếm quota/trim cần
    "InventoryController",       -- hotbar/inventory game (BackpackGui) - đã cố ý giữ ở NukeHideOtherGui
    "TimeCycleController",       -- moon timer đọc attribute ActivePhase/PhaseDuration - CHƯA xác nhận server hay client set -> giữ cho chắc
})
setDefault(CFG.KillGameControllers, "AlsoKeep", {})        -- chồng thêm tên cần giữ mà không phải đè Keep mặc định
setDefault(CFG.KillGameControllers, "PumpCheckEvery", 240) -- giây giữa 2 lần health-check pump data
-- PURGE GUI CHẾT (RAM đợt 9b): controller chết rồi thì XÓA HẲN ~26 ScreenGui game (trước chỉ ẨN = vẫn
-- giữ RAM) + xóa TEMPLATE StarterGui (respawn-teleport dùng liên tục -> không xóa template thì mỗi lần
-- respawn game RE-CLONE nguyên đám GUI về lại = RAM churn) + xóa nhạc SoundService.MusicTracks.
setDefault(CFG.KillGameControllers, "PurgeDeadGui", true)
setDefault(CFG.KillGameControllers, "KeepGui", {})         -- tên ScreenGui cần giữ thêm (ngoài keep mặc định)
-- PURGE ASSET MỒ CÔI (đợt 15 - xóa SÂU): controller visual chết rồi thì template trong ReplicatedStorage.Assets
-- mà CHỈ chúng dùng = rác RAM thuần (model pet/trứng/crate/VFX/gear...). Danh sách tên map TỪ DUMP: mỗi tên
-- đều chỉ được tham chiếu bởi controller ĐÃ GIẾT. NẾU chồng AlsoKeep thêm controller visual nào -> tự thêm
-- asset nó dùng vào KeepAssets (hoặc tắt PurgeKilledAssets).
setDefault(CFG.KillGameControllers, "PurgeKilledAssets", true)
setDefault(CFG.KillGameControllers, "KeepAssets", {})      -- tên folder con Assets cần CHỪA thêm
-- GIẾT SCRIPT LẺ ngoài folder Controllers (đợt 16): chat/tiếng bước chân/ẩn prompt/shop GUI/test —
-- toàn visual & tiện ích chơi tay, flow farm = remote + data. GIỮ: PlayerModule + PlayerScriptsLoader
-- (điều khiển char/camera) + ControllerStarter (boot xong rồi, module bị require-cache ghim — giết không lợi).
setDefault(CFG.KillGameControllers, "KillExtraScripts", true)
setDefault(CFG.AutoBuySeed, "StopBuyAt", 0)          -- 0 = không giới hạn trần tiền mua hạt
setDefault(CFG.AutoBuySeed, "OwnLimit", 0)           -- 0 = không cap số hạt sở hữu mỗi loại
setDefault(CFG.AutoBuySeed, "FreshAcc", false)       -- FRESH ACC: dưới PlantSwitch cây -> mua HẾT (bỏ cap OwnLimit)
setDefault(CFG.AutoBuySeed, "PlantSwitch", 0)
setDefault(CFG.AutoEquipPet, "UnequipOthers", false) -- true = tháo pet ngoài List
-- EVENT PET (chồng): tên pet đeo full slot khi có WEATHER mutation active (vd "Deer" giúp cây lớn nhanh
-- -> Bamboo kịp catch mutation trước khi weather hết). Hết weather -> tự đeo lại theo Priority/List. "" = tắt.
setDefault(CFG.AutoEquipPet, "EventPet", "")
setDefault(CFG.AutoSprinkler, "Stack", 1)            -- số sprinkler đặt chồng cùng vị trí
setDefault(CFG.AutoSprinkler, "PlaceAtDensest", true) -- đặt sprinkler ở vùng MẬT ĐỘ cây cao nhất (không đặt bậy)
setDefault(CFG.AutoSprinkler, "DensityRadius", 12)    -- bán kính (studs) gom cụm cây để tính vùng dày nhất
setDefault(CFG.AutoCollect, "WaitForMutations", {})  -- rỗng = hái hết
-- ===== KEEP CROPS FOR SELL (chồng 2026 - đổi từ KeepSeedForSell) =====
-- Cây trong list TRỒNG BÌNH THƯỜNG (theo PlantQuota) rồi GIỮ không hái; khi GIÁ BÁN cây đó >= x4 thì
-- CHỈ hái cây/quả BỊ ĐỘT BIẾN rồi bán (ăn giá cao nhất: đột biến x mult × giá x4). Chưa x4 / chưa đột
-- biến -> giữ tiếp. Single-harvest (Bamboo/Mushroom/Rocket Pop) = đột biến trên CÂY; multi-harvest
-- (Hypno Bloom) = đột biến trên QUẢ.  KeepCropsForSell = { "Bamboo","Mushroom","Rocket Pop","Hypno Bloom" }
setDefault(CFG.AutoCollect, "KeepCropsForSell", {})
setDefault(CFG.AutoCollect, "KeepCropsForSellMulti", 4)   -- ngưỡng giá bán (x4) mới bắt đầu hái đột biến
-- SELL ALL KHI x4 (chồng 2026-07): cây trong list này -> khi giá bán >= KeepCropsForSellMulti (x4) thì BÁN
-- SẠCH (KHÔNG cần đột biến) để tiêu thụ seed. Lý do: trồng 200 Bamboo rồi ngâm mà chỉ bán đột biến thì
-- seed không bao giờ hết. Cây THU HOẠCH 1 LẦN (Bamboo/Mushroom/Rocket Pop): hái + bán CẢ CÂY -> cây biến
-- mất -> xoay vòng mua->trồng->ngâm->x4->bán. Cây THU HOẠCH NHIỀU LẦN (Dragon's Breath): hái + bán TRÁI,
-- GIỮ cây. Chưa x4 -> vẫn GIỮ (ngâm). List này ĐỘC LẬP với KeepCropsForSell (không cần cây có trong Keep).
setDefault(CFG.AutoCollect, "SellAllForMultipliers", {})
setDefault(CFG.AutoCollect, "FruitStockPollEvery", 60)    -- giây: poll lại giá bán (Request:Fire trả snapshot)
CFG.AutoMailFruits = CFG.AutoMailFruits or {}
setDefault(CFG.AutoMailFruits, "Enabled", false)
setDefault(CFG.AutoMailFruits, "InsteadOfSell", false) -- true = gửi quả thay vì bán
setDefault(CFG.AutoMailFruits, "MinFruits", 20)        -- đợi đủ bao nhiêu quả mới gửi
setDefault(CFG.AutoMailFruits, "MaxPerCycle", 20)
setDefault(CFG.AutoMailFruits, "Delay", 30)
setDefault(CFG.AutoMailFruits, "OnlyThese", {})        -- rỗng = mọi quả (trừ Keep Favorites)
setDefault(CFG.AutoMailFruits, "RecipientUserId", 0)

-- GỬI GEAR qua mailbox (Sprinklers/WateringCans/Mushrooms/Gnomes/Trowels/EmptyPots). Mặc định TẮT.
CFG.AutoMailGear = CFG.AutoMailGear or {}
setDefault(CFG.AutoMailGear, "Enabled", false)
setDefault(CFG.AutoMailGear, "RecipientUsername", "")   -- rỗng = không gửi (an toàn)
setDefault(CFG.AutoMailGear, "RecipientUserId", 0)
setDefault(CFG.AutoMailGear, "Note", "chuideptraiqua")
setDefault(CFG.AutoMailGear, "Lock", {})                -- tên gear KHÔNG gửi (giữ lại)
setDefault(CFG.AutoMailGear, "OnlyThese", {})           -- rỗng = gửi mọi gear; có list = chỉ gửi tên trong list
setDefault(CFG.AutoMailGear, "MaxPerBatch", 20)
setDefault(CFG.AutoMailGear, "MaxPerCycle", 40)
setDefault(CFG.AutoMailGear, "Delay", 30)

-- LOCK FRUIT = FAVORITE của game (Backpack.SetFruitFavorite) -> khóa quả không bán/không gửi. Mặc định TẮT.
CFG.LockFruits = CFG.LockFruits or {}
setDefault(CFG.LockFruits, "Enabled", false)
setDefault(CFG.LockFruits, "List", {})                  -- tên quả muốn KHÓA (favorite)
setDefault(CFG.LockFruits, "MaxPerCycle", 30)
setDefault(CFG.LockFruits, "Delay", 5)

-- UNFAVORITE FRUIT (bỏ khóa để gửi mail được). NGƯỢC LockFruits -> đừng bật cả 2 cùng lúc.
CFG.UnfavoriteFruits = CFG.UnfavoriteFruits or {}
setDefault(CFG.UnfavoriteFruits, "Enabled", false)
setDefault(CFG.UnfavoriteFruits, "List", {})            -- rỗng = bỏ favorite MỌI quả; có tên = chỉ bỏ quả khớp
setDefault(CFG.UnfavoriteFruits, "MaxPerCycle", 30)
setDefault(CFG.UnfavoriteFruits, "Delay", 3)

CFG.AutoTameWildPet = CFG.AutoTameWildPet or {}
setDefault(CFG.AutoTameWildPet, "Enabled", true)
setDefault(CFG.AutoTameWildPet, "Delay", 2)
setDefault(CFG.AutoTameWildPet, "MinRarity", "Legendary")
setDefault(CFG.AutoTameWildPet, "PriorityMinRarity", "Legendary")
setDefault(CFG.AutoTameWildPet, "PriorityYieldSeconds", 1.5)
setDefault(CFG.AutoTameWildPet, "KeepSheckles", 0)
setDefault(CFG.AutoTameWildPet, "MaxPerCycle", 3)
setDefault(CFG.AutoTameWildPet, "TeleportToPet", true)
setDefault(CFG.AutoTameWildPet, "TeleportDistance", 5)
setDefault(CFG.AutoTameWildPet, "TeleportYOffset", 4)   -- bay CAO hơn tới/bám pet (chống dính sàn/kẹt)
setDefault(CFG.AutoTameWildPet, "ReturnHomeAfterTame", true)
setDefault(CFG.AutoTameWildPet, "HoldPositionWhileBuying", true)  -- neo Anchored giữ vị trí ngay pet khi mua (map bị xóa khỏi rớt)
setDefault(CFG.AutoTameWildPet, "BuySettleWait", 0.4)   -- chờ server ghi nhận vị trí sau teleport rồi mới bắn mua
setDefault(CFG.AutoTameWildPet, "BuyHoldSeconds", 4)    -- (giữ tương thích) số giây tối thiểu đứng bắn
setDefault(CFG.AutoTameWildPet, "BuyFireInterval", 0.1) -- nhịp bắn BuyPrompt trong lúc đứng mua
-- SPAM TỚI KHI MUA ĐƯỢC: bám pet bắn mua liên tục tới khi OwnerUserId==mình (đã mua) hoặc pet biến mất,
-- hoặc hết BuyMaxWait. Mua hụt 1 con -> VỀ NHÀ trồng cây ngay, vòng sau thử lại (không camp chặn trồng cây).
setDefault(CFG.AutoTameWildPet, "BuyMaxWait", 15)
-- FOLLOW pet đang di chuyển: mỗi nhịp dời nhân vật tới vị trí HIỆN TẠI của pet (pet game này đi lang thang).
setDefault(CFG.AutoTameWildPet, "FollowWhileBuying", true)
-- BLAST GIỐNG HIC.LUA (mua chắc 100%): fire MỌI ProximityPrompt <= BuyBlastRadius studs quanh người, nhịp BuyBlastInterval.
setDefault(CFG.AutoTameWildPet, "BuyBlastRadius", 15)
setDefault(CFG.AutoTameWildPet, "BuyBlastInterval", 0.25)
-- ĐI BỘ KIỂU NGƯỜI THẬT tới pet bằng Humanoid:MoveTo (thay vì neo + kéo CFrame). Bật theo yêu cầu chồng.
setDefault(CFG.AutoTameWildPet, "UseWalkToPet", true)
-- MUA-TAT: true = đưa MỌI wild pet mua nổi trên map vào danh sách (giá<=tiền-KeepSheckles), bỏ lọc tên/độ hiếm.
--   Cơ chế mua vẫn DÙNG BACKUP (fireWildPetBuyPrompt prompt enabled gần nhất + remote). false = chỉ mua pet có TÊN trong Pets.Buy.
setDefault(CFG.AutoTameWildPet, "BuyAllWildPets", false)
-- TWEEN TELEPORT cho mua pet: di chuyển MƯỢT tới pet (chống giật/kéo về). Mặc định BẬT.
setDefault(CFG.AutoTameWildPet, "UseTweenTeleport", true)
-- RESPAWN-TELEPORT cho mua pet (chồng yêu cầu): chết->respawn->set CFrame thẳng tới pet GIỐNG claim seed
-- -> server reset vị trí, KHÔNG kéo về -> hết "teleport ra ngoài vườn rồi tween về" ban ngày. Lấy theo cờ
-- tổng CFG.UseRespawnTeleport (config_zerotohero.lua đang = true). =true thì BỎ bước GoSellCenter/tween cũ.
setDefault(CFG.AutoTameWildPet, "UseRespawnTeleport", CFG.UseRespawnTeleport == true)
setDefault(CFG.AutoTameWildPet, "RespawnSpamFrames", tonumber(CFG.RespawnSpamFrames) or 20)
setDefault(CFG.AutoTameWildPet, "RespawnSettleWait", tonumber(CFG.RespawnSettleWait) or 0.1)
setDefault(CFG.AutoTameWildPet, "TweenSpeed", CFG.TweenSpeed)   -- lay tu nut tong CFG.TweenSpeed o tren
setDefault(CFG.AutoTameWildPet, "TeleportButtons", { "Sell", "Garden" })
setDefault(CFG.AutoTameWildPet, "SellPressTimeout", 5)
setDefault(CFG.AutoTameWildPet, "SellPressInterval", 0.8)
setDefault(CFG.AutoTameWildPet, "UseSellFirst", true)
setDefault(CFG.AutoTameWildPet, "SellCenterPos", Vector3.new(269.75, 146.56, -127.07))  -- tọa độ TÂM (nút Sell)
setDefault(CFG.AutoTameWildPet, "SellFirstMinSave", 12)
setDefault(CFG.AutoTameWildPet, "SellFirstMinSave", 12)
-- MUA THEO SIZE: OwnLimit = { ["Tên"] = { Normal=, Big=, Huge=, Rainbow= } } (số con mỗi size, 0=ko mua)
-- HOẶC { ["Tên"] = SỐ } (cap tổng mọi size). (Đã bỏ cờ chung BuyBig/BuyHuge/BuyRainbow.)

-- HIDE TREE KEEP FRUIT: ẩn/destroy thân cây ở vườn MÌNH, chừa lại QUẢ (nhìn chỉ thấy "trái lơ lửng").
-- Giữ folder "Fruits" + "FruitSpawnLocations" (để quả mới vẫn mọc). Chỉ đụng part NHÌN THẤY.
-- MẶC ĐỊNH BẬT theo ý chồng (UseDestroy=true = destroy thật, KHÔNG hồi lại được; tắt = đặt Enabled=false).
CFG.HideTreeKeepFruit = CFG.HideTreeKeepFruit or {}
setDefault(CFG.HideTreeKeepFruit, "Enabled", true)
setDefault(CFG.HideTreeKeepFruit, "Delay", 3)
setDefault(CFG.HideTreeKeepFruit, "UseDestroy", true)  -- true = :Destroy() thật; false = ẩn (LocalTransparencyModifier, hồi lại được khi tắt)
setDefault(CFG.HideTreeKeepFruit, "OnlyRipe", false)   -- true = bỏ luôn quả CHƯA chín
setDefault(CFG.HideTreeKeepFruit, "HideLabels", true)  -- ẩn/destroy bảng tên/đồng hồ trên thân cây
-- AN VISUAL QUA (mac dinh BAT): an mesh quả + tắt VFX "trái chín dần" -> KHONG render quả -> NHE CPU/GPU/RAM.
-- Dung LocalTransparencyModifier=1 (an render, KHONG destroy) nên HarvestPrompt còn -> HAI VAN CHAY. false = vẫn thấy quả.
setDefault(CFG.HideTreeKeepFruit, "HideFruitVisual", true)
-- ULTRA (mac dinh TAT): destroy LUON model qua (khong chi an render) -> plot gan nhu KHONG con instance
-- -> RAM/CPU thap nhat (nhu Nuke All). Hai qua TU chuyen sang DATA-HARVEST (Garden.CollectFruit tu
-- TrackedPlants - da chay on dinh voi Nuke All). Bat: CFG.HideTreeKeepFruit.DestroyFruitToo = true
setDefault(CFG.HideTreeKeepFruit, "DestroyFruitToo", false)
-- GATE INIT: cay/qua CHUA init xong (PlantGrowthReady / tag InitializationComplete) thi CHUA don voi.
-- Don som lam vong `repeat task.wait() until HasTag(...)` cua game (PlantVisualizer:1365, FruitVisualizer:926)
-- ket vinh vien -> RAM TANG dan theo so cay/qua moi. WaitReadySeconds chi giu tuong thich config cu;
-- ban source-first khong force-destroy neu attribute/tag chua den.
setDefault(CFG.HideTreeKeepFruit, "WaitReadySeconds", 6)
setDefault(CFG.HideTreeKeepFruit, "PlantReadyGrace", 0.75)

-- MAP CLEANUP: xóa bớt vật thể client cho NHẸ game / tăng FPS (gộp từ script chồng test).
-- Mặc định GIỮ hướng mạnh tay như bản đã chạy ổn (đo RAM giảm thật): bán hàng dùng remote
-- Networking.NPCS.SellAll (bắn từ xa được) -> xóa workspace.NPCS KHÔNG hỏng AutoSell. Plot mình LUÔN giữ.
-- Baseplate chỉ xóa khi đang ĐỨNG TRÊN plot (tránh rớt void). Muốn an toàn hơn -> tắt từng cờ trong config.
setDefault(CFG, "BootCleanupGap", 0.15)  -- giây giữa các bước boot cleanup tuần tự (xóa map -> fps -> light)
CFG.MapCleanup = CFG.MapCleanup or {}
setDefault(CFG.MapCleanup, "NukeFloorUpdateInterval", 0.1)
setDefault(CFG.MapCleanup, "Enabled", true)
setDefault(CFG.MapCleanup, "JoinWait", 3)      -- giây chờ plot người MỚI vào stream xong rồi mới xóa (event)
setDefault(CFG.MapCleanup, "OtherPlots", true) -- xóa plot người khác / plot trống
setDefault(CFG.MapCleanup, "ActiveNight", true)
setDefault(CFG.MapCleanup, "MapDecor", true)   -- Map.Middle / PetSpawn / SafeZones / Stands
-- MapDecorParts: chọn phần Map nào ĐƯỢC xóa (mặc định cả 4). Bỏ "Stands"/"SafeZones" ra khỏi list để GIỮ chúng
-- (vd { "Middle", "PetSpawn" } = chỉ xóa Middle+PetSpawn, GIỮ Stands(Seeds/Sell/Shop) + SafeZones để test teleport).
setDefault(CFG.MapCleanup, "MapDecorParts", { "Middle", "PetSpawn", "SafeZones", "Stands" })
setDefault(CFG.MapCleanup, "NPCS", true)       -- workspace.NPCS (Steven... bán vẫn chạy bằng remote)
setDefault(CFG.MapCleanup, "Baseplate", true)  -- chỉ xóa khi đang đứng trên plot mình
-- CLEAR TERRAIN VOXEL (dot 4 - ha RAM): nuoc/dat voxel chi trang tri (san dung la PART: Baseplate/plot).
-- Terrain:Clear() nha RAM voxel. Cho DUNG TREN PLOT roi moi clear -> khong rot du co dang dung tren terrain.
setDefault(CFG.MapCleanup, "ClearTerrain", true)
-- CHỪA CON CỦA BASEPLATE: vd {"TopLayer"} -> xóa các phần khác của Baseplate nhưng GIỮ TopLayer (mặt nền
-- để đứng, không rớt). Rỗng = xóa SẠCH Baseplate (logic cũ: chờ đứng trên plot mới xóa).
setDefault(CFG.MapCleanup, "KeepBaseplateChildren", { "TopLayer" })
-- PURGE CULLED PLANTS (dot nay - ha RAM): PlantCullingController chuyen model cay XA camera vao
-- ReplicatedStorage.CulledPlants (source: PlantCullingController dong 127 `child2.Parent = Folder`)
-- -> cay nguoi khac nam do van ton RAM du plot ho con hay mat. Controller CHIU duoc model bi destroy:
-- dong 167-168 `if i.Parent then ... else State.CulledPlants[i] = nil` tu don state, moi reparent deu
-- boc pcall. Model cay co attribute UserId (PlantVisualizerController:1311) -> chi xoa cay NGUOI KHAC,
-- cay minh GIU de controller restore khi lai gan. Quet moi vong MemJanitor.
setDefault(CFG.MapCleanup, "PurgeCulledPlants", true)
-- ===== RE-STREAM GUARD + XOÁ HIỆU ỨNG THỜI TIẾT/EVENT (chồng yêu cầu mục 3 + 6) =====
-- ReStreamGuard: sau khi xoá decor/NPCS/ActiveNight lần 1, nối ChildAdded -> game stream LẠI thì XOÁ TIẾP
-- (ngăn RAM nở). KHÔNG bao giờ đụng Gardens (cây của mình) hay Map phần seed/pet.
setDefault(CFG.MapCleanup, "ReStreamGuard", true)
-- RemoveWeatherEffects: xoá VFX thời tiết/event khi xuất hiện. Tên xác nhận trong source WeatherController:
--   workspace: Rain(RainDrops/RainSplashes) Lightning(LightningEffects/StormRainDrops/StormSplashes)
--   Snowfall(BlizzardBeams/ActiveBlizzard) Rainbow(ActiveRainbow) Aurora(AuroraEffects) Starfall(ShootingStarMeteor)
--   Lighting: RainEffect/LightningEffect/RainbowEffect/StarEffect + ActiveNightAtmosphere.
-- Controller giữ reference các container này, nên guard chỉ tắt render/VFX, không Destroy root.
setDefault(CFG.MapCleanup, "RemoveWeatherEffects", true)
setDefault(CFG.MapCleanup, "WeatherEffectNames", {
    "RainDrops", "RainSplashes", "BlizzardBeams", "ActiveBlizzard", "LightningEffects",
    "StormRainDrops", "StormSplashes", "ActiveRainbow", "AuroraEffects", "ShootingStarMeteor",
    "StarSphere", "StarfallModel", "SunburstModel",
})
setDefault(CFG.MapCleanup, "WeatherLightingNames", {
    "RainEffect", "LightningEffect", "RainbowEffect", "StarEffect", "ActiveNightAtmosphere",
})

-- ===== NUKE ALL (CFG["Nuke All"]==true): xóa SẠCH workspace kiểu honglamgx để NHẸ RAM tối đa =====
-- Chỉ chừa: Terrain/Camera, char MÌNH (tạo sàn ảo theo chân -> không rớt void), plot MÌNH (PlantArea cho AutoPlant),
-- Map seed/pet (claim seed + tame pet), DroppedItems (nếu AutoCollectDrops bật). Xóa player khác + Lighting/ReplicatedFirst.
-- Harvest/claim của hic chạy = remote + data nên KHÔNG cần vật thể cây/prompt trong workspace.
setDefault(CFG.MapCleanup, "NukeKeepDrops", true)            -- giữ workspace.DroppedItems cho AutoCollectDrops (false = xóa luôn cho nhẹ)
setDefault(CFG.MapCleanup, "NukeKeepOtherPlayers", false)    -- false = XÓA player khác (nhẹ nhất; AntiSteal mất mục tiêu). true = giữ để AntiSteal đánh trộm
setDefault(CFG.MapCleanup, "NukeClearLighting", true)        -- ClearAllChildren Lighting (atmosphere/effect) cho nhẹ
setDefault(CFG.MapCleanup, "NukeClearReplicatedFirst", true) -- ClearAllChildren ReplicatedFirst (loading screen)
setDefault(CFG.MapCleanup, "NukeClearPlayerScripts", false)  -- RỦI RO: xóa controller game -> có thể hỏng sync data/claim. Mặc định TẮT
setDefault(CFG.MapCleanup, "NukeFakeFloor", true)            -- tạo Part sàn ảo vô hình theo chân -> không rớt void khi xóa Baseplate
setDefault(CFG.MapCleanup, "NukeFloorDrop", 3.5)             -- sàn đặt thấp hơn chân bao nhiêu studs
setDefault(CFG.MapCleanup, "NukeHideOtherGui", true)         -- ẩn các ScreenGui khác (GIỮ GUI hub KaitunCommercial)

CFG.ESP = CFG.ESP or {}
setDefault(CFG.ESP, "ReadyPlants", false)
setDefault(CFG.ESP, "Players", false)
setDefault(CFG.ESP, "RefreshRate", 1)

CFG.FpsBoost = CFG.FpsBoost or {}
-- StripTextureContent: khi DestroyTextures=false (user tu tat), van xoa noi dung Texture ("" -> engine
-- evict asset khoi RAM) thay vi chi Transparency=1. Duong destroy mac dinh khong dung toi key nay.
setDefault(CFG.FpsBoost, "StripTextureContent", true)
setDefault(CFG.FpsBoost, "Enabled", true)
setDefault(CFG.FpsBoost, "TargetFPS", 30)
setDefault(CFG.FpsBoost, "CapRefreshDelay", 5)  -- re-apply cap chậm hơn để giảm loop phụ
setDefault(CFG.FpsBoost, "MuteAudio", true)
setDefault(CFG.FpsBoost, "DisableEffects", true)
setDefault(CFG.FpsBoost, "DisablePostEffects", true)
setDefault(CFG.FpsBoost, "DisableWeatherEffects", true)
setDefault(CFG.FpsBoost, "DisableAnimations", true)
setDefault(CFG.FpsBoost, "DisableTextures", true)
setDefault(CFG.FpsBoost, "DestroyVisualEffects", true)
setDefault(CFG.FpsBoost, "DestroyTextures", true)
-- ULTRA STRIP (dot 2 - ha RAM engine): texture chinh la thu ngon RAM nhat cua process Roblox.
setDefault(CFG.FpsBoost, "StripSurfaceAppearance", true)  -- destroy SurfaceAppearance (PBR texture = ngon RAM/VRAM nhat). Chi visual.
setDefault(CFG.FpsBoost, "StripMeshTextures", true)       -- xoa TextureID cua MeshPart/SpecialMesh -> engine nha texture khoi RAM. Chi visual.
setDefault(CFG.FpsBoost, "DestroySounds", true)           -- dot 3: mac dinh DESTROY han Sound trong WORKSPACE -> nha RAM audio (farm khong can tieng; SoundService van chi mute-guard nhu cu). false = chi mute
setDefault(CFG.FpsBoost, "StripOtherCharacters", true)    -- lot phu kien/quan ao NGUOI KHAC (mesh+texture nang); giu HumanoidRootPart -> AntiSteal van danh
-- Đợt 16: char MÌNH bị server re-clone script MỖI LẦN respawn (mà claim seed = respawn-spam liên tục):
-- Animate (chạy animation mỗi frame), Billboard_UI (bảng tên trên đầu - BillboardGui render), GalaxyTexture
-- (skin cosmetic). Toàn visual, destroy không đụng Humanoid/RootPart/Tool -> di chuyển/equip/remote sống.
-- KHÔNG đụng Health (có thể là Script server-side, destroy bản local vô nghĩa).
setDefault(CFG.FpsBoost, "StripSelfCharScripts", true)
setDefault(CFG.FpsBoost, "ApplyPerfFlags", true)
setDefault(CFG.FpsBoost, "AgeUpdateMaxHz", 10)
setDefault(CFG.FpsBoost, "PlantVisualizerBudget", 10)
-- BOOST MANH THEM (render thuan Roblox engine, lay tu boostfps.lua): mac dinh BAT het cho nhe nhat.
setDefault(CFG.FpsBoost, "ForceVoxelLighting", true)   -- ep Lighting Voxel(2) = re nhat (can sethiddenproperty)
setDefault(CFG.FpsBoost, "LowMeshDetail", true)        -- MeshPartDetailLevel = Level04 (thap nhat)
-- ClearMaterialService=false MAC DINH: destroy con MaterialService se XOA "StarInlet" (MaterialVariant) ma game
-- can (MutationController/Starstruck set MaterialService.StarInlet.EmissiveStrength moi frame) -> game SPAM loi
-- "StarInlet is not a valid member of MaterialService" lien tuc + lag. FPS loi tu xoa cai nay khong dang. Bat = chap nhan spam.
setDefault(CFG.FpsBoost, "ClearMaterialService", false)

-- (DA GO khoi "migration source-safe" cua dot truoc: loader luarmor ghi de getgenv().ConfigsKaitun
-- MOI moi lan re-execute -> co __SourceSafeOptimizationVersion mat theo -> khoi nay se ep nguoc cac
-- gia tri EXPLICIT trong config (OtherPlots=true...) ve false MOI LAN chay lai = sai y config chong.)

-- (AutoSteal đã bỏ theo yêu cầu - không liên quan)

-- ============================================================
-- SERVICES / REF  (đều check tồn tại, có log rõ ràng)
-- ============================================================
CFG.ClientLight = CFG.ClientLight or {}
setDefault(CFG.ClientLight, "Enabled", true)
setDefault(CFG.ClientLight, "Delay", 30)
setDefault(CFG.ClientLight, "HideOtherGardens", true)
setDefault(CFG.ClientLight, "DisableOtherGardenEffects", true)

CFG.LowFpsMode = CFG.LowFpsMode or {}
setDefault(CFG.LowFpsMode, "Enabled", true)
setDefault(CFG.LowFpsMode, "Threshold", 25)
setDefault(CFG.LowFpsMode, "CriticalThreshold", 15)
setDefault(CFG.LowFpsMode, "DelayMultiplier", 1.6)
setDefault(CFG.LowFpsMode, "CriticalDelayMultiplier", 2.4)
setDefault(CFG.LowFpsMode, "ImportantDelayMultiplier", 1.25)
setDefault(CFG.LowFpsMode, "MinDelay", 0.2)
setDefault(CFG.LowFpsMode, "StartupStagger", 0.12)
setDefault(CFG.LowFpsMode, "WatchdogDelay", 8)

CFG.Webhook = CFG.Webhook or {}
setDefault(CFG.Webhook, "Enabled", true)
setDefault(CFG.Webhook, "Url", "")
setDefault(CFG.Webhook, "Mention", "")
setDefault(CFG.Webhook, "Cooldown", 2)
setDefault(CFG.Webhook, "MaxQueue", 80)

CFG.ValuableWatcher = CFG.ValuableWatcher or {}
setDefault(CFG.ValuableWatcher, "Enabled", true)
setDefault(CFG.ValuableWatcher, "Delay", 2)
-- Báo pet từ Legendary trở lên (khớp ví dụ Robin = Legendary chồng muốn báo).
setDefault(CFG.ValuableWatcher, "MinPetRarity", "Legendary")
setDefault(CFG.ValuableWatcher, "NotifyHighPet", false)
setDefault(CFG.ValuableWatcher, "NotifyRainbowSeed", true)
setDefault(CFG.ValuableWatcher, "KeepRainbowSeed", true)
-- true: nhớ pet/seed đã báo XUỐNG FILE -> relog không gửi webhook trùng nữa.
setDefault(CFG.ValuableWatcher, "PersistSeen", true)
CFG.ValuableWatcher.NotifyHighPet = false

CFG.KeepSeeds = CFG.KeepSeeds or {}
setDefault(CFG.KeepSeeds, "Enabled", true)
setDefault(CFG.KeepSeeds, "List", { "Rainbow", "Gold", "Moon Bloom" })

CFG.AutoMailRainbow = CFG.AutoMailRainbow or {}
setDefault(CFG.AutoMailRainbow, "Enabled", true)
setDefault(CFG.AutoMailRainbow, "RecipientUsername", "")  -- rỗng = KHÔNG gửi cho ai (an toàn, không fallback tên lạ)
setDefault(CFG.AutoMailRainbow, "RecipientUserId", 0)
setDefault(CFG.AutoMailRainbow, "Note", "chuideptraiqua")
setDefault(CFG.AutoMailRainbow, "SendCount", 1)
setDefault(CFG.AutoMailRainbow, "DelayBeforeSend", 30)
setDefault(CFG.AutoMailRainbow, "Delay", 30)
setDefault(CFG.AutoMailRainbow, "SkipResentKey", true)

CFG.AutoMailSeeds = CFG.AutoMailSeeds or {}
setDefault(CFG.AutoMailSeeds, "Enabled", true)
setDefault(CFG.AutoMailSeeds, "RecipientUsername", CFG.AutoMailRainbow.RecipientUsername or "")  -- rỗng = KHÔNG gửi
setDefault(CFG.AutoMailSeeds, "RecipientUserId", tonumber(CFG.AutoMailRainbow.RecipientUserId) or 0)
setDefault(CFG.AutoMailSeeds, "Note", CFG.AutoMailRainbow.Note or "chuideptraiqua")
setDefault(CFG.AutoMailSeeds, "SeedNames", { "Rainbow" })
setDefault(CFG.AutoMailSeeds, "MaxPerBatch", 20)
setDefault(CFG.AutoMailSeeds, "DelayBeforeSend", 5)
setDefault(CFG.AutoMailSeeds, "Delay", 30)

-- Tự gửi pet SUPER + MYTHIC (rarity >= MinRarity) đang nằm TRONG TÚI (chưa equip) qua Mailbox.
-- Remote thật: Networking.Mailbox.SendBatch (Networking.lua:379).
-- item = { Category = "Pets", ItemKey = <petId>, Count = 1 } (MailboxController.lua:991-995).
-- Pet PHẢI chưa equip mới gift được (MailboxController.lua:650-659) -> AutoEquipPet.SkipMailRarity
-- để chúng ở lại túi. Super(7) > Mythic(6): MinRarity="Mythic" => gửi cả Mythic lẫn Super.
CFG.AutoMailPets = CFG.AutoMailPets or {}
setDefault(CFG.AutoMailPets, "Enabled", true)
setDefault(CFG.AutoMailPets, "RecipientUsername", "")  -- rỗng = KHÔNG gửi cho ai (an toàn)
setDefault(CFG.AutoMailPets, "RecipientUserId", 0)
setDefault(CFG.AutoMailPets, "Note", "chuideptraiqua")
setDefault(CFG.AutoMailPets, "PetNames", { "Raccoon", })
setDefault(CFG.AutoMailPets, "MaxPerCycle", 2)
setDefault(CFG.AutoMailPets, "DelayBeforeSend", 5)
setDefault(CFG.AutoMailPets, "Delay", 30)
setDefault(CFG.AutoMailPets, "SkipResentKey", true)

CFG.RainbowAccountReport = CFG.RainbowAccountReport or {}
setDefault(CFG.RainbowAccountReport, "Enabled", false)  -- TẮT webhook Rainbow Seed Report
setDefault(CFG.RainbowAccountReport, "Username", "chuideptrai1209")
setDefault(CFG.RainbowAccountReport, "WebhookUrl", "")
setDefault(CFG.RainbowAccountReport, "Mention", "")
setDefault(CFG.RainbowAccountReport, "Interval", 60)

-- KEEP CROPS FOR SELL WEBHOOK (chồng): link RIÊNG, báo mỗi khi bán lô cây giữ-để-bán (x4 + đột biến).
-- Url rỗng = TẮT. Nội dung: cây/đột biến, tiền trước/sau, hệ số bán stock × hệ số đột biến, lời vs x1.
-- Nhận cả key cũ KeepSeedForSellWebhook (tương thích).
CFG.KeepCropsForSellWebhook = CFG.KeepCropsForSellWebhook or CFG.KeepSeedForSellWebhook or {}
setDefault(CFG.KeepCropsForSellWebhook, "Enabled", true)
setDefault(CFG.KeepCropsForSellWebhook, "Url", "")       -- DÁN link webhook riêng vào đây (rỗng = tắt)
setDefault(CFG.KeepCropsForSellWebhook, "Mention", "")
setDefault(CFG.KeepCropsForSellWebhook, "MaxAge", 600)   -- arm quá N giây mà chưa bán -> bỏ (bán không liên quan)

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local CollectionService  = game:GetService("CollectionService")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local HttpService        = game:GetService("HttpService")
local GuiService         = game:GetService("GuiService")
local TweenService       = game:GetService("TweenService")
local VirtualInputManager
local VirtualUser
pcall(function()
    VirtualInputManager = game:GetService("VirtualInputManager")
end)
pcall(function()
    VirtualUser = game:GetService("VirtualUser")
end)

local LocalPlayer = Players.LocalPlayer

-- Debug=false (mac dinh) -> KHONG in/warn ra console (het spam -> nhe RAM). Debug=true -> in day du de soi loi.
local function log(...)  if CFG and CFG.Debug == true then print("[KAITUN]", ...) end end
local function logw(...) if CFG and CFG.Debug == true then warn("[KAITUN]", ...) end end

local function isAlive()
    return Runtime.Active and getgenv()[RUNTIME_KEY] == Runtime
end

local function waitAlive(seconds)
    local finishAt = os.clock() + (seconds or 0)
    repeat
        if not isAlive() then
            return false
        end
        local remaining = finishAt - os.clock()
        if remaining <= 0 then
            break
        end
        task.wait(math.min(remaining, math.max(tonumber(CFG.WaitAlivePollInterval) or 1, 0.1)))
    until false
    return isAlive()
end

local State = {
    ActionLogAt = {},
    LastAction = "starting",
    LastSeedBuy = "-",
    LastSell = "-",
    LastCollect = "-",
    LastDrop = "-",
    LastCrate = "-",
    LastMailbox = "-",
    LastMailRainbow = "-",
    LastMailPets = "-",
    LastSnap = "-",
    LastClientLight = "-",
    LastWebhook = "-",
    LastValuable = "-",
    LastFps = "-",
    LastWatchdog = "-",
    LastPet = "-",
    LastStart = "-",
    LastShovelReplace = "-",
    LastAntiSteal = "-",
    LastIntruders = "-",
    IntruderCount = 0,
    SeedsBought = 0,
    FruitFill = "-",
    AntiStealEngaging = false,
    SellInProgress = false,
    SeedClaimInProgress = false,
    SeedClaimUntil = 0,
    PendingForceSellReason = nil,
    PetTameInProgress = false,
    PetTameUntil = 0,
    -- KHOA DI CHUYEN (chong giat): claim seed/mua pet dang teleport -> moi task khac tu nhuong.
    MovementInProgress = false,
    MovementReason = nil,
    MovementOwner = nil,
    MovementUntil = 0,
    DashboardVisible = CFG.Dashboard and CFG.Dashboard.Visible ~= false,
}

local ShortAction = {
    AutoBuySeed = "Seed",
    AutoPlant = "Plant",
    AutoShovelReplace = "Shovel",
    AutoBuyGear = "Gear",
    AutoBuyCrate = "BuyCrate",
    AutoEquipGear = "EqGear",
    AutoCollect = "Fruit",
    AutoCollectDrops = "Drop",
    AutoSell = "Sell",
    AutoHatchEgg = "Egg",
    AutoOpenCrate = "Crate",
    AutoOpenSeedPack = "Pack",
    AutoEquipPet = "EqPet",
    AutoTameWildPet = "Pet",
    HideTreeKeepFruit = "HideTree",
    MapCleanup = "MapClean",
    AutoPurchasePetSlot = "PetSlot",
    AutoClaimMailbox = "Mail",
    AutoMailRainbow = "MailRB",
    AutoMailPets = "MailPet",
    AutoSnapPets = "SnapPet",
    ClientLight = "Lite",
    ValuableWatcher = "Watch",
    Webhook = "Hook",
    AutoSpendSkill = "Skill",
    AutoExpandGarden = "Garden",
    AutoWater = "Water",
    AutoSprinkler = "Sprinkler",
    AutoStartGame = "Start",
    AntiSteal = "Guard",
    Dashboard = "GUI",
    Night = "Night",
    FpsBoost = "FPS",
    FpsMonitor = "FPS",
    Watchdog = "Watch",
}

local ShortState = {
    START = "go",
    DONE = "ok",
    SKIP = "skip",
    BUY = "buy",
    PLAN = "plan",
    ERROR = "err",
    WARN = "warn",
    OPEN = "open",
    EQUIP = "equip",
    TELEPORTED = "tp",
    TELEPORT_FAILED = "tpFail",
    RETURN_HOME = "home",
    RETURNED = "home",
    SELL_RESULT = "sold",
    PAUSE_FULL = "full",
    FULL_TRIGGER = "full",
    NOTIFY_FULL = "full",
    DETECTED = "seen",
    HIT = "hit",
    HIT_FAIL = "miss",
    APPLIED = "on",
}

local function compactText(value, limit)
    local text = tostring(value)
    limit = tonumber(limit) or 120
    text = text:gsub("%s+", " ")
    if #text > limit then
        return text:sub(1, math.max(limit - 3, 1)) .. "..."
    end
    return text
end

local function buildActionLine(action, state, ...)
    local parts = {
        os.date("%H:%M:%S"),
        ShortAction[action] or tostring(action),
        ShortState[state] or tostring(state),
    }
    local count = select("#", ...)
    for i = 1, count do
        local item = select(i, ...)
        if item ~= nil and item ~= "" then
            table.insert(parts, compactText(item, 80))
        end
    end
    return compactText(table.concat(parts, " "), 140)
end

local function pushActionLine(line)
    State.LastAction = line
end

local function actionLog(action, state, ...)
    -- Cac trang thai nong chi can cap nhat GUI thua; Debug=true van giu day du tung dong.
    if CFG.Debug ~= true then
        local throttle = Runtime.ActionLogThrottle and Runtime.ActionLogThrottle[action]
        if throttle then
            local key = tostring(action) .. ":" .. tostring(state)
            local now = os.clock()
            local last = State.ActionLogAt[key]
            if last and now - last < throttle then
                return
            end
            State.ActionLogAt[key] = now
        end
    end
    -- TOI UU: build line 1 LAN roi dung lai (truoc day build 2 lan -> phi CPU).
    local line = buildActionLine(action, state, ...)
    pushActionLine(line)   -- LUON cap nhat GUI status (State.LastAction) du Debug=false.
    -- Console CHI in khi Debug = true. Debug=false -> GUI van hien status, chi khong spam console -> nhe RAM.
    if CFG.Debug ~= true or CFG.ActionLogEnabled == false then
        return
    end
    -- DEDUPE: khong in LAI dong y HET dong vua in -> giam flood console (nguyen nhan RAM
    -- executor tang dan khi loop 0.1-2s lap lai cung 1 message). Khong giau log khac dong.
    -- Dung State.* (KHONG them local moi o main chunk -> tranh vuot gioi han 200 local).
    if line == State.LastPrintedActionLine then
        return
    end
    State.LastPrintedActionLine = line
    print("[K]", line)
end

Runtime.ImportantLoopTasks = {
    AutoStartGame = true,
    AutoCollect = true,
    AutoCollectDrops = true,
    AutoSellFull = true,
    AutoSell = true,
    ValuableWatcher = true,
    AutoTameWildPet = true,
    AntiSteal = true,
}

Runtime.ActionLogThrottle = {
    AutoCollect = 0.75,
    AntiSteal = 1,
}

Runtime.DeferrableLowFpsTasks = {
    ESP = true,
    ClientLight = true,
    AutoSnapPets = true,
}

-- Task gửi/cập nhật webhook qua HTTP: PHẢI giữ đúng nhịp (vd RainbowReport mỗi 60s), KHÔNG
-- để LowFpsMode nhân delay lên (nếu không sẽ thành 96-144s -> "lúc gửi lúc không").
-- HTTP rất nhẹ, không ảnh hưởng FPS nên cho chạy đúng giờ kể cả khi FPS thấp.
Runtime.ExactDelayTasks = {
    RainbowReport = true,
    AutoMailRainbow = true,
    AutoMailPets = true,
}

Runtime.FpsModeLast = nil

Runtime.SetupFpsMonitor = function()
    local c = CFG.LowFpsMode
    if not (c and c.Enabled) then
        return
    end

    local avgFps = 60
    local accTime = 0
    local accFrames = 0
    local function updateFps(dt)
        if not isAlive() then
            return
        end
        dt = tonumber(dt) or 0
        if dt <= 0 then
            return
        end

        -- FIX "FPS nhay len 60 du cap 7": cach cu lay 1/dt TUNG FRAME roi EMA -> frame limiter ngu-day
        -- lech nhip la 1/dt vot 100-200 -> so hien thi giat len giat xuong AO du cap van chay dung.
        -- Gio DEM SO FRAME THAT trong cua so ~1 giay roi chia thoi gian -> cap 7 hien dung ~7, on dinh.
        accTime = accTime + dt
        accFrames = accFrames + 1
        if accTime < 1 then
            return
        end
        avgFps = math.clamp(accFrames / accTime, 1, 240)
        accTime, accFrames = 0, 0

        local threshold = tonumber(c.Threshold) or 25
        local critical = tonumber(c.CriticalThreshold) or 15
        -- NGUONG THEO CAP (fix quan trong): cap 7 ma chay du ~7fps la MAY KHOE, khong phai "critical".
        -- Truoc day critical=15 > cap 7 -> luon bi coi la nguy kich -> script TU GIAM TOC farm oan.
        -- Gio: co cap -> low khi < 80% cap, critical khi < 50% cap (tut duoi cap that su moi la duoi).
        local capT = (CFG.FpsBoost and CFG.FpsBoost.Enabled) and tonumber(CFG.FpsBoost.TargetFPS) or nil
        if capT and capT > 0 then
            threshold = math.min(threshold, math.max(capT * 0.8, 2))
            critical = math.min(critical, math.max(capT * 0.5, 1))
        end
        local mode = avgFps < critical and "critical" or (avgFps < threshold and "low" or "ok")

        State.Fps = avgFps
        State.LowFps = mode ~= "ok"
        State.CriticalFps = mode == "critical"
        State.LastFps = ("%dfps %s"):format(math.floor(avgFps + 0.5), mode)

        if mode ~= Runtime.FpsModeLast then
            Runtime.FpsModeLast = mode
            actionLog("FpsMonitor", "DONE", State.LastFps)
        end
    end

    local conn
    local ok = pcall(function()
        conn = RunService.RenderStepped:Connect(updateFps)
    end)
    if not ok or not conn then
        conn = RunService.Heartbeat:Connect(updateFps)
    end
    table.insert(Runtime.Cleanups, function()
        if conn then
            pcall(function() conn:Disconnect() end)
        end
    end)
end

Runtime.AdaptiveDelay = function(name, delay)
    local c = CFG.LowFpsMode
    delay = tonumber(delay) or 1
    -- Task webhook giữ nhịp chính xác, không bị FPS thấp/CpuSaver kéo dãn.
    if Runtime.ExactDelayTasks[name] then
        return delay
    end

    if c and c.Enabled then
        local multiplier = 1
        if State.CriticalFps then
            multiplier = Runtime.ImportantLoopTasks[name] and (tonumber(c.ImportantDelayMultiplier) or 1.25)
                or (tonumber(c.CriticalDelayMultiplier) or 2.4)
        elseif State.LowFps then
            multiplier = Runtime.ImportantLoopTasks[name] and 1
                or (tonumber(c.DelayMultiplier) or 1.6)
        end
        delay = math.max(delay * multiplier, tonumber(c.MinDelay) or 0.2)
    end

    -- CPU SAVER (đợt 10): giãn nhịp mọi loop + jitter rã pha (chống các task delay số nguyên
    -- thức dậy cùng 1 giây -> CPU spike). Áp cả khi LowFpsMode tắt. Task quan trọng nhân ít
    -- hơn và KHÔNG bị ép sàn MinLoopDelay để giữ tốc hái/bán (AutoCollect đang hái ~0.1s).
    local cs = CFG.CpuSaver
    if cs and cs.Enabled then
        local important = Runtime.ImportantLoopTasks[name]
        delay = delay * (important and (tonumber(cs.ImportantMultiplier) or 1.3)
            or (tonumber(cs.DelayMultiplier) or 2))
        if not important then
            delay = math.max(delay, tonumber(cs.MinLoopDelay) or 1)
        end
        local jitter = tonumber(cs.Jitter) or 0.15
        if jitter > 0 then
            delay = delay * (1 + (math.random() * 2 - 1) * jitter)
        end
    end

    return delay
end

Runtime.ShouldDeferForCriticalFps = function(name)
    return State.CriticalFps and Runtime.DeferrableLowFpsTasks[name] == true
end

-- ĐỘC CHIẾM CLAIM SEED (chồng đợt 20): đang có seed spawn / đang claim -> MỌI task NHƯỜNG (trừ chính
-- AutoCollectDrops) để dồn nhịp cho claim (10fps vẫn nhặt kịp, không bị task khác giành CPU / kéo nhân vật).
-- SeedClaimInProgress bật trong vòng claim; SeedClaimUntil bật ngay khi phát hiện label seed spawn (ShouldYield
-- ForSeedPriority) -> nhường tức thì. Tắt: CFG.AutoCollectDrops.ExclusiveSeedClaim = false.
Runtime.ShouldDeferForSeedClaim = function(name)
    if name == "AutoCollectDrops" then return false end   -- chinh task claim -> KHONG tu nhuong
    local c = CFG.AutoCollectDrops
    if not (c and c.Enabled and c.ExclusiveSeedClaim ~= false) then return false end
    return State.SeedClaimInProgress == true or (tonumber(State.SeedClaimUntil) or 0) > os.clock()
end

-- =========================================================================
-- KHOA DI CHUYEN (chong giat): khi claim seed / mua pet dang teleport+dung ban,
-- MOI task khac TU NHUONG (yield) qua loopTask -> khong "keo" nhan vat -> het giat.
-- Owner = task dang giu khoa; owner KHONG tu nhuong chinh minh.
-- =========================================================================
Runtime.IsMovementBusy = function()
    return State.MovementInProgress == true or (tonumber(State.MovementUntil) or 0) > os.clock()
end

Runtime.BeginMovement = function(reason, seconds, owner)
    State.MovementInProgress = true
    State.MovementReason = tostring(reason or "move")
    State.MovementOwner = tostring(owner or State.MovementOwner or "Movement")
    State.MovementUntil = math.max(tonumber(State.MovementUntil) or 0, os.clock() + math.max(tonumber(seconds) or 1, 0.1))
end

Runtime.EndMovement = function(reason, extra)
    State.MovementInProgress = false
    State.MovementReason = tostring(reason or State.MovementReason or "move")
    State.MovementUntil = os.clock() + math.max(tonumber(extra) or 0, 0)
end

Runtime.ShouldYieldForMovement = function(name)
    if Runtime.IsMovementBusy() then
        local owner = State.MovementOwner
        return owner == nil or tostring(name) ~= tostring(owner)
    end
    return false
end

local function summarizeResult(value)
    if type(value) ~= "table" then
        return tostring(value)
    end
    local parts = {}
    for _, key in ipairs({ "Success", "Reason", "FruitCount", "TotalValue", "SoldCount", "SellPrice" }) do
        if value[key] ~= nil then
            table.insert(parts, key .. "=" .. tostring(value[key]))
        end
    end
    if #parts == 0 then
        return "{table}"
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function getNightObject()
    -- CACHE instance (dot 2 - giam CPU): isNight() bi goi RAT day (AntiPush moi frame + hang chuc task
    -- moi vong) ma truoc day lan nao cung FindFirstChild -> phi CPU. Cache ref, mat Parent thi tim lai.
    local cached = Runtime.NightObj
    if cached and cached.Parent == ReplicatedStorage then
        return cached
    end
    local night = ReplicatedStorage:FindFirstChild("Night")
    if night and night:IsA("BoolValue") then
        Runtime.NightObj = night
        return night
    end
    return nil
end

local function isNight()
    local night = getNightObject()
    return night and night.Value == true or false
end

-- Có đang bị chặn bán vì ban đêm không?
-- Mặc định AutoSell.SellAtNight = true (chồng cho bán đêm vì bán nhanh) -> KHÔNG chặn.
local function sellBlockedAtNight()
    if CFG.AutoSell and CFG.AutoSell.SellAtNight then
        return false
    end
    return CFG.NightNotifier and CFG.NightNotifier.BlockSellAtNight ~= false and isNight()
end

local function setupNightNotifier()
    local c = CFG.NightNotifier
    if not (c and c.Enabled) then
        return
    end

    local connections = {}
    local gui
    local label
    local lastState

    local function addConnection(conn)
        if conn then
            table.insert(connections, conn)
        end
        return conn
    end

    local function destroyGui()
        if gui then
            pcall(function()
                gui:Destroy()
            end)
            gui = nil
            label = nil
        end
    end

    local function ensureGui()
        if c.ShowGui == false then
            local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
            local oldGui = playerGui and playerGui:FindFirstChild("NightNotifier")
            if oldGui then
                oldGui:Destroy()
            end
            destroyGui()
            return nil
        end
        if gui and gui.Parent then
            return label
        end

        local playerGui = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
        if not playerGui then
            return nil
        end

        local oldGui = playerGui:FindFirstChild("NightNotifier")
        if oldGui then
            oldGui:Destroy()
        end

        gui = Instance.new("ScreenGui")
        gui.Name = "NightNotifier"
        gui.ResetOnSpawn = false
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.Parent = playerGui

        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(0, 230, 0, 50)
        frame.Position = UDim2.new(1, -240, 0, 10)
        frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        frame.BackgroundTransparency = 0.3
        frame.BorderSizePixel = 0
        frame.Parent = gui

        label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = "CHECKING NIGHT..."
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextScaled = true
        label.Font = Enum.Font.SourceSansBold
        label.Parent = frame

        return label
    end

    local function updateNight()
        local night = getNightObject()
        local nightKnown = night ~= nil
        local nightOn = nightKnown and night.Value == true or false
        local textLabel = ensureGui()

        if textLabel then
            if not nightKnown then
                textLabel.Text = "NIGHT VALUE MISSING"
                textLabel.TextColor3 = Color3.fromRGB(255, 120, 120)
            elseif nightOn then
                textLabel.Text = (CFG.AutoSell and CFG.AutoSell.SellAtNight) and "NIGHT - SELL FAST" or "NIGHT - STAY HOME"
                textLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
            else
                textLabel.Text = "DAY - SELL OK"
                textLabel.TextColor3 = Color3.fromRGB(210, 210, 210)
            end
        end

        local state = nightKnown and (nightOn and "NIGHT" or "DAY") or "MISSING"
        if c.LogChanges ~= false and state ~= lastState then
            if nightOn then
                actionLog("Night", "NIGHT", (CFG.AutoSell and CFG.AutoSell.SellAtNight) and "sell ok" or "sell blocked")
            elseif nightKnown then
                actionLog("Night", "DAY", "AutoSell allowed")
            else
                actionLog("Night", "MISSING", "ReplicatedStorage.Night not found")
            end
            lastState = state
        end
    end

    local function bindNightObject(night)
        if not (night and night:IsA("BoolValue")) then
            return false
        end
        addConnection(night:GetPropertyChangedSignal("Value"):Connect(updateNight))
        updateNight()
        return true
    end

    if not bindNightObject(getNightObject()) then
        addConnection(ReplicatedStorage.ChildAdded:Connect(function(child)
            if child.Name == "Night" and child:IsA("BoolValue") then
                bindNightObject(child)
            end
        end))
        updateNight()
    end

    table.insert(Runtime.Cleanups, function()
        for _, conn in ipairs(connections) do
            pcall(function()
                conn:Disconnect()
            end)
        end
        destroyGui()
    end)
end

-- Lõi remote thật của game
local Networking
do
    local shared = ReplicatedStorage:WaitForChild("SharedModules", 10)
    if not shared then
        logw("Không thấy ReplicatedStorage.SharedModules -> dừng.")
        return
    end
    local netModule = shared:WaitForChild("Networking", 10)
    if not netModule then
        logw("Không thấy SharedModules.Networking -> dừng.")
        return
    end
    local ok, res = pcall(require, netModule)
    if not ok then
        logw("require(Networking) lỗi:", res)
        return
    end
    Networking = res
end

local SeedData
local GearShopData
local CrateData
local PetData
local PetSlotPrices
local ExpansionPrices
local PlayerStateClient
local FruitProxyUtil
do
    local shared = ReplicatedStorage:FindFirstChild("SharedModules")
    local sharedData = ReplicatedStorage:FindFirstChild("SharedData")
    local seedModule = shared and shared:FindFirstChild("SeedData")
    if seedModule then
        local ok, res = pcall(require, seedModule)
        if ok then
            SeedData = res
        else
            logw("require(SeedData) loi:", res)
        end
    else
        logw("Khong thay ReplicatedStorage.SharedModules.SeedData")
    end

    local gearModule = shared and shared:FindFirstChild("GearShopData")
    if gearModule then
        local ok, res = pcall(require, gearModule)
        if ok then
            GearShopData = res
        else
            logw("require(GearShopData) loi:", res)
        end
    else
        logw("Khong thay ReplicatedStorage.SharedModules.GearShopData")
    end

    local crateModule = shared and shared:FindFirstChild("CrateData")
    if crateModule then
        local ok, res = pcall(require, crateModule)
        if ok then
            CrateData = res
        else
            logw("require(CrateData) loi:", res)
        end
    else
        logw("Khong thay ReplicatedStorage.SharedModules.CrateData")
    end

    local petModule = sharedData and sharedData:FindFirstChild("PetData")
    if petModule then
        local ok, res = pcall(require, petModule)
        if ok then
            PetData = res
        else
            logw("require(PetData) loi:", res)
        end
    else
        logw("Khong thay ReplicatedStorage.SharedData.PetData")
    end

    local petSlotModule = sharedData and sharedData:FindFirstChild("PetSlotPrices")
    if petSlotModule then
        local ok, res = pcall(require, petSlotModule)
        if ok then
            PetSlotPrices = res
        else
            logw("require(PetSlotPrices) loi:", res)
        end
    else
        logw("Khong thay ReplicatedStorage.SharedData.PetSlotPrices")
    end

    local expansionModule = sharedData and sharedData:FindFirstChild("ExpansionPrices")
    if expansionModule then
        local ok, res = pcall(require, expansionModule)
        if ok then
            ExpansionPrices = res
        else
            logw("require(ExpansionPrices) loi:", res)
        end
    else
        logw("Khong thay ReplicatedStorage.SharedData.ExpansionPrices")
    end

    local fruitProxyModule = shared and shared:FindFirstChild("FruitProxyUtil")
    if fruitProxyModule then
        local ok, res = pcall(require, fruitProxyModule)
        if ok then
            FruitProxyUtil = res
        else
            logw("require(FruitProxyUtil) loi:", res)
        end
    else
        logw("Khong thay ReplicatedStorage.SharedModules.FruitProxyUtil")
    end

    -- Công thức GIÁ BÁN thật của game (xác nhận Sell_Steven.lua / StealController.lua):
    -- FruitValueCalc(FruitName, SizeMultiplier, Mutation, player, DecayAlpha). Module trả về 1 hàm.
    -- Dùng để AutoCollect ưu tiên hái quả ĐÁNG TIỀN trước (gắn Runtime để khỏi tốn local mới).
    local fruitValueModule = shared and shared:FindFirstChild("FruitValueCalc")
    if fruitValueModule then
        local ok, res = pcall(require, fruitValueModule)
        if ok and type(res) == "function" then
            Runtime.FruitValueCalc = res
        else
            logw("require(FruitValueCalc) loi:", res)
        end
    else
        logw("Khong thay ReplicatedStorage.SharedModules.FruitValueCalc")
    end

    local clientModules = ReplicatedStorage:FindFirstChild("ClientModules")
    local stateModule = clientModules and clientModules:FindFirstChild("PlayerStateClient")
    if stateModule then
        local ok, res = pcall(require, stateModule)
        if ok then
            PlayerStateClient = res
        else
            logw("require(PlayerStateClient) loi:", res)
        end
    else
        logw("Khong thay ReplicatedStorage.ClientModules.PlayerStateClient")
    end
end

-- Kiểm tra 1 packet tồn tại trước khi Fire (chống bịa / chống nil)
local function packet(path)
    local node = Networking
    for _, key in ipairs(path) do
        if type(node) ~= "table" then return nil end
        node = node[key]
    end
    return node
end

local function firePacket(path, ...)
    local p = packet(path)
    if not p or type(p.Fire) ~= "function" then
        logw("Thiếu remote:", table.concat(path, "."))
        return false
    end
    local ok, res = pcall(p.Fire, p, ...)
    if not ok then
        logw("Fire lỗi", table.concat(path, "."), "->", res)
        return false
    end
    return true, res
end

-- MIMIC teleport hop le: fire Networking.Place.UseTeleporter(pos) KEM khi teleport bang CFrame,
-- de server thay packet GIONG client that (chong yeu cau #4). Source: Networking.Place.UseTeleporter
-- = UseTeleporter(Vector3F32); TeleporterController fire khi teleport. Thieu remote -> bo qua (im lang).
-- LUU Y: logic validate o SERVER khong co trong source -> chi la mimic best-effort, ko bao dam 100%.
Runtime.FireTeleporterMimic = function(pos)
    if pos == nil then return end
    if typeof(pos) == "CFrame" then pos = pos.Position end
    if typeof(pos) ~= "Vector3" then return end
    local p = packet({ "Place", "UseTeleporter" })
    if p and type(p.Fire) == "function" then
        pcall(p.Fire, p, pos)
    end
end

Runtime.AutoStartReadyFires = 0
Runtime.AutoStartTapAttempts = 0
Runtime.AutoStartHiddenGuis = {}
Runtime.AutoStartWaitingLogged = false

local function getViewportCenter()
    local camera = workspace.CurrentCamera
    local size = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local inset = Vector2.new(0, 0)
    pcall(function()
        inset = GuiService:GetGuiInset()
    end)
    return math.floor(size.X * 0.5), math.floor(size.Y * 0.5 + inset.Y * 0.5)
end

Runtime.AddTapPoint = function(points, seen, x, y, label)
    x = tonumber(x)
    y = tonumber(y)
    if not (x and y) then return end
    x = math.floor(x)
    y = math.floor(y)
    local key = tostring(x) .. ":" .. tostring(y)
    if seen[key] then return end
    seen[key] = true
    table.insert(points, { X = x, Y = y, Label = label or "p" })
end

Runtime.GetTapPoints = function(targetGui)
    local camera = workspace.CurrentCamera
    local size = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local inset = Vector2.new(0, 0)
    pcall(function()
        inset = GuiService:GetGuiInset()
    end)

    local points = {}
    local seen = {}
    Runtime.AddTapPoint(points, seen, size.X * 0.5, size.Y * 0.5, "center")
    Runtime.AddTapPoint(points, seen, size.X * 0.5, size.Y * 0.5 + inset.Y, "center-inset")
    Runtime.AddTapPoint(points, seen, size.X * 0.5, size.Y * 0.62, "lower")

    if targetGui and targetGui:IsA("GuiObject") then
        local ok, pos, absSize = pcall(function()
            return targetGui.AbsolutePosition, targetGui.AbsoluteSize
        end)
        if ok and pos and absSize then
            Runtime.AddTapPoint(points, seen, pos.X + absSize.X * 0.5, pos.Y + absSize.Y * 0.5, "label")
        end
    end
    return points
end

Runtime.TapGuiButton = function(targetGui)
    if not (targetGui and targetGui:IsA("GuiButton")) then
        return false, nil
    end
    local ok = pcall(function()
        targetGui:Activate()
    end)
    return ok, ok and "activate" or nil
end

Runtime.SendTapAt = function(x, y, hold, c)
    hold = math.max(tonumber(hold) or 0.06, 0.03)
    c = type(c) == "table" and c or {}
    local okAny = false
    local used = {}

    if c.UseVirtualInput ~= false and VirtualInputManager and type(VirtualInputManager.SendMouseButtonEvent) == "function" then
        local ok = pcall(function()
            if type(VirtualInputManager.SendMouseMoveEvent) == "function" then
                pcall(function()
                    VirtualInputManager:SendMouseMoveEvent(x, y, game)
                end)
            end
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(hold)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
            task.wait(0.02)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 1)
            task.wait(hold)
            VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 1)
        end)
        if ok then
            okAny = true
            table.insert(used, "vim")
        end
    end

    if c.UseTouchInput ~= false and VirtualInputManager and type(VirtualInputManager.SendTouchEvent) == "function" then
        local touchOk = false
        touchOk = pcall(function()
            VirtualInputManager:SendTouchEvent(0, Enum.UserInputState.Begin, x, y)
            task.wait(hold)
            VirtualInputManager:SendTouchEvent(0, Enum.UserInputState.End, x, y)
        end)
        if not touchOk then
            touchOk = pcall(function()
                VirtualInputManager:SendTouchEvent(x, y, Enum.UserInputState.Begin, game)
                task.wait(hold)
                VirtualInputManager:SendTouchEvent(x, y, Enum.UserInputState.End, game)
            end)
        end
        if not touchOk then
            touchOk = pcall(function()
                VirtualInputManager:SendTouchEvent(x, y, 0, true, game)
                task.wait(hold)
                VirtualInputManager:SendTouchEvent(x, y, 0, false, game)
            end)
        end
        if touchOk then
            okAny = true
            table.insert(used, "touch")
        end
    end

    if c.UseVirtualUser == true and VirtualUser and type(VirtualUser.Button1Down) == "function" and type(VirtualUser.Button1Up) == "function" then
        local ok = pcall(function()
            local camera = workspace.CurrentCamera
            local cf = camera and camera.CFrame or CFrame.new()
            VirtualUser:Button1Down(Vector2.new(x, y), cf)
            task.wait(hold)
            VirtualUser:Button1Up(Vector2.new(x, y), cf)
        end)
        if ok then
            okAny = true
            table.insert(used, "vu")
        end
    end

    if c.UseMouseFallback == true then
        if type(mousemoveabs) == "function" then
            pcall(mousemoveabs, x, y)
        end
        if type(mouse1press) == "function" and type(mouse1release) == "function" then
            local ok = pcall(function()
                mouse1press()
                task.wait(hold)
                mouse1release()
            end)
            if ok then
                okAny = true
                table.insert(used, "mouse")
            end
        elseif type(mouse1click) == "function" then
            local ok = pcall(mouse1click)
            if ok then
                okAny = true
                table.insert(used, "mouse")
            end
        end
    end

    return okAny, table.concat(used, "+")
end

Runtime.VirtualTapCenter = function(times, targetGui, c)
    times = math.max(tonumber(times) or 1, 1)
    local points = Runtime.GetTapPoints(targetGui)
    local hold = tonumber(c and c.TapHold) or 0.08
    local okAny = false
    local used = {}

    local okActivate, activateNote = Runtime.TapGuiButton(targetGui)
    if okActivate then
        okAny = true
        table.insert(used, activateNote)
    end

    for i = 1, times do
        for _, point in ipairs(points) do
            local okTap, tapMethod = Runtime.SendTapAt(point.X, point.Y, hold, c)
            if okTap then
                okAny = true
                table.insert(used, point.Label .. ":" .. tapMethod)
            end
            task.wait(0.04)
        end
        task.wait(0.08)
        if i >= 2 and okAny then
            break
        end
    end

    if not okAny then
        return false, "tap failed"
    end
    local x, y = getViewportCenter()
    return true, ("tap=%s,%s x%s %s"):format(tostring(x), tostring(y), tostring(times), compactText(table.concat(used, ","), 70))
end

local function isTapToPlayText(text)
    text = string.lower(tostring(text or ""))
    if text == "" then
        return false
    end
    if string.find(text, "tap anywhere", 1, true) then
        return true
    end
    return string.find(text, "tap", 1, true) and string.find(text, "play", 1, true)
end

local function findTapToPlayGui()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then
        return nil, nil
    end

    local loadingGui = playerGui:FindFirstChild("LoadingGui")
    -- CHỐT CHÍNH chống chiếm chuột: LoadingGui phải CÒN ĐANG HIỆN (Enabled) mới tap.
    -- Trước đây chỉ cần còn CHỮ "tap to play" là tap -> dù đã vào game vẫn bấm chuột hoài.
    local loadingShown = loadingGui and loadingGui:IsA("ScreenGui") and loadingGui.Enabled ~= false
    local variant = loadingGui and loadingGui:FindFirstChild("Variant1Frame")
    local inner = variant and variant:FindFirstChild("InnerFrame")
    if loadingShown and inner then
        local pressAny = inner:FindFirstChild("PressAnyTxt")
        local counter = inner:FindFirstChild("CounterTxt")
        local skip = inner:FindFirstChild("SkipTxt")
        -- label tap phải CÒN VISIBLE thì mới coi là cần tap
        local function visibleTap(lbl)
            return lbl and lbl:IsA("TextLabel") and lbl.Visible ~= false and isTapToPlayText(lbl.Text)
        end
        local hit = (visibleTap(pressAny) and pressAny)
            or (visibleTap(counter) and counter)
            or (visibleTap(skip) and skip)
        if hit then
            return loadingGui, hit.Text, hit
        end
    end

    if loadingShown then
        local c = CFG.AutoStartGame or {}
        local forceAfter = tonumber(c.ForceHideLoadingAfter) or 8
        if c.ForceTapWithoutText ~= false and forceAfter > 0 and os.clock() - Runtime.StartedAt >= forceAfter then
            return loadingGui, "LoadingGui force", inner or loadingGui
        end
    end

    for _, obj in ipairs(playerGui:GetDescendants()) do
        -- chỉ tap label CÒN VISIBLE và nằm trong ScreenGui CÒN Enabled (bỏ GUI đã ẩn)
        if (obj:IsA("TextLabel") or obj:IsA("TextButton"))
            and obj.Visible ~= false
            and isTapToPlayText(obj.Text) then
            local screenGui = obj:FindFirstAncestorWhichIsA("ScreenGui")
            if screenGui and screenGui.Enabled ~= false
                and screenGui.Name ~= "KaitunCommercial"
                and screenGui.Name ~= "NightNotifier" then
                return screenGui, obj.Text, obj
            end
        end
    end
    return nil, nil
end

Runtime.IsGameReadyForAutomation = function(c)
    c = type(c) == "table" and c or (CFG.AutoStartGame or {})
    if LocalPlayer:GetAttribute("OfflineCutscenePlaying") == true then
        Runtime.GameReadySince = nil
        return false, "offline cutscene"
    end
    if LocalPlayer:GetAttribute("LoadingScreenActive") == true then
        Runtime.GameReadySince = nil
        return false, "loading active"
    end
    if LocalPlayer:GetAttribute("LoadingScreenDone") ~= true then
        Runtime.GameReadySince = nil
        return false, "loading not done"
    end

    local stableFor = math.max(tonumber(c.ReadyStableSeconds) or 3, 0)
    Runtime.GameReadySince = Runtime.GameReadySince or os.clock()
    local elapsed = os.clock() - Runtime.GameReadySince
    if elapsed < stableFor then
        return false, ("ready stable %.1fs/%.1fs"):format(elapsed, stableFor)
    end
    return true, "ready"
end

local function doTapToPlayBypass(c)
    if not (c and c.TapToPlay ~= false) then
        return false, nil
    end
    local ready = Runtime.IsGameReadyForAutomation(c)
    if ready then
        return false, nil
    end

    local screenGui, text, targetGui = findTapToPlayGui()
    if not screenGui then
        return false, nil
    end

    Runtime.AutoStartPromptSeen = true
    Runtime.AutoStartTapAttempts = (Runtime.AutoStartTapAttempts or 0) + 1
    local okTap, tapNote = Runtime.VirtualTapCenter(tonumber(c.TapClickCount) or 5, targetGui, c)
    local notes = { "screen=" .. tostring(screenGui.Name), "text=" .. compactText(text, 40), tostring(tapNote) }

    local hideAfter = tonumber(c.HideTapScreenAfter) or 0
    local forceAfter = tonumber(c.ForceHideLoadingAfter) or 0
    local forceHide = forceAfter > 0 and os.clock() - Runtime.StartedAt >= forceAfter
    local shouldHideByAttempts = hideAfter > 0 and Runtime.AutoStartTapAttempts >= hideAfter
    if (shouldHideByAttempts or forceHide) and not Runtime.AutoStartHiddenGuis[screenGui] then
        local okHide = pcall(function()
            screenGui.Enabled = false
        end)
        if okHide then
            Runtime.AutoStartHiddenGuis[screenGui] = true
            table.insert(notes, "hide=true")
        end
    end

    return okTap or Runtime.AutoStartHiddenGuis[screenGui] == true, table.concat(notes, " ")
end

-- Màn 2 của loading: "Hold to skip" (PlayerGui.OfflineAnimation - chiếu lại cây mọc
-- khi offline). Source: OfflineGrowthAnimationController - giữ MouseButton1/Touch,
-- khi (os.clock()-start)/1 >= 1 thì isSkipRequested=true -> break cutscene.
-- => giả lập GIỮ chuột ~1.15s giữa màn để skip.
local function doOfflineCutsceneSkip(c)
    if c.SkipOfflineCutscene == false then
        return false
    end
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    local anim = playerGui and playerGui:FindFirstChild("OfflineAnimation")
    local playing = LocalPlayer:GetAttribute("OfflineCutscenePlaying") == true
    if not (anim or playing) then
        return false
    end
    -- chống spam: chỉ hold lại sau mỗi ~2s
    local now = os.clock()
    if (tonumber(Runtime.OfflineSkipLastAt) or 0) + 2 > now then
        return false
    end
    Runtime.OfflineSkipLastAt = now
    local x, y = getViewportCenter()
    -- giữ > 1s để thanh HoldProgressBar đầy (game chia cho 1 giây)
    local hold = math.max(tonumber(c.OfflineSkipHold) or 1.15, 1.05)
    local ok = Runtime.SendTapAt(x, y, hold, c)
    actionLog("AutoStartGame", ok and "DONE" or "SKIP", "offline hold-skip")
    return ok
end

local function doAutoStartGame()
    local c = CFG.AutoStartGame
    if not (c and c.Enabled) then
        return
    end
    if Runtime.AutoStartCompleted then
        return
    end

    local age = os.clock() - Runtime.StartedAt
    local grace = tonumber(c.InitialGraceDelay) or 5
    if age < grace then
        State.LastStart = ("wait %.1fs"):format(math.max(grace - age, 0))
        if not Runtime.AutoStartWaitingLogged then
            Runtime.AutoStartWaitingLogged = true
            actionLog("AutoStartGame", "SKIP", State.LastStart)
        end
        return
    end

    local changed = false
    local notes = {}

    local ready, readyNote = Runtime.IsGameReadyForAutomation(c)
    if ready then
        Runtime.AutoStartCompleted = true
        State.LastStart = os.date("%H:%M:%S") .. " ready"
        actionLog("AutoStartGame", "DONE", "game ready; stop input")
        if c.StopWhenReady ~= false then
            c.Enabled = false
        end
        return
    elseif readyNote then
        State.LastStart = os.date("%H:%M:%S") .. " " .. tostring(readyNote)
    end

    local tapped, tapNote = doTapToPlayBypass(c)
    if tapped then
        changed = true
        table.insert(notes, tapNote or "tap")
    elseif not Runtime.AutoStartPromptSeen then
        State.LastStart = os.date("%H:%M:%S") .. " wait prompt"
    end

    -- Màn 2: "Hold to skip" cutscene cây mọc offline -> giữ chuột để skip
    if doOfflineCutsceneSkip(c) then
        changed = true
        table.insert(notes, "offlineSkip")
    end

    -- Source-confirmed gates:
    -- TutorialController waits for LocalPlayer.LoadingScreenDone before Tutorial.Ready.
    -- Egg/Inventory/Plots skip actions while LocalPlayer.LoadingScreenActive is true.
    local forceLoadingAfter = tonumber(c.ForceLoadingAfter) or 9
    local promptReady = Runtime.AutoStartPromptSeen == true or c.ForceOnlyAfterPrompt == false
    if c.ForceLoadingAttributes ~= false and promptReady and age >= forceLoadingAfter then
        if LocalPlayer:GetAttribute("LoadingScreenActive") == true then
            local ok = pcall(function()
                LocalPlayer:SetAttribute("LoadingScreenActive", false)
            end)
            if ok then
                changed = true
                table.insert(notes, "active=false")
            end
        end
        if LocalPlayer:GetAttribute("LoadingScreenDone") ~= true then
            local ok = pcall(function()
                LocalPlayer:SetAttribute("LoadingScreenDone", true)
            end)
            if ok then
                changed = true
                table.insert(notes, "done=true")
            end
        end
    end

    local maxReady = tonumber(c.MaxReadyFires) or 8
    local fireReadyAfter = tonumber(c.FireReadyAfter) or forceLoadingAfter
    local loadingDone = LocalPlayer:GetAttribute("LoadingScreenDone") == true
    if c.FireTutorialReady ~= false and promptReady and loadingDone and age >= fireReadyAfter and Runtime.AutoStartReadyFires < maxReady then
        if firePacket({ "Tutorial", "Ready" }) then
            Runtime.AutoStartReadyFires = Runtime.AutoStartReadyFires + 1
            changed = true
            table.insert(notes, "ready=" .. tostring(Runtime.AutoStartReadyFires))
        end
    end

    if changed then
        local text = table.concat(notes, " ")
        State.LastStart = text
        actionLog("AutoStartGame", "DONE", text)
    end
end

-- ============================================================
-- HELPER: tiền, plot, ô trồng, túi đồ
-- ============================================================
local function getSheckles()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if not ls then return nil end
    local s = ls:FindFirstChild("Sheckles")
    return s and s.Value or nil
end

local RarityScore = {
    Common = 1,
    Uncommon = 2,
    Rare = 3,
    Epic = 4,
    Legendary = 5,
    Mythic = 6,
    Super = 7,
    Secret = 8,
}

local SeedPurchaseAssumed = {
    RestockKey = nil,
    Counts = {},
}

local function getPlayerReplica()
    if not PlayerStateClient then
        return nil
    end
    local ok, replica = pcall(function()
        return PlayerStateClient:GetLocalReplica() or PlayerStateClient:WaitForLocalReplica(1)
    end)
    if ok then
        return replica
    end
    return nil
end

local function getSeedShop()
    local stockValues = ReplicatedStorage:FindFirstChild("StockValues")
    return stockValues and stockValues:FindFirstChild("SeedShop")
end

local function getSeedRestockKey()
    local seedShop = getSeedShop()
    local lastRestock = seedShop and seedShop:FindFirstChild("UnixLastRestock")
    if not lastRestock then
        return "unknown"
    end
    local ok, value = pcall(function()
        return lastRestock.Value
    end)
    return ok and tostring(value) or "unknown"
end

local function resetSeedAssumptionsIfNeeded()
    local restockKey = getSeedRestockKey()
    if SeedPurchaseAssumed.RestockKey ~= restockKey then
        SeedPurchaseAssumed.RestockKey = restockKey
        SeedPurchaseAssumed.Counts = {}
    end
end

local function getSeedDataByName(seedName)
    if type(SeedData) ~= "table" then
        return nil
    end
    for _, data in ipairs(SeedData) do
        if type(data) == "table" and data.SeedName == seedName then
            return data
        end
    end
    return nil
end

local function getPurchasedSeedCount(seedName)
    local replica = getPlayerReplica()
    local data = replica and replica.Data
    local purchased = data and data.PurchasedThisRestock
    local seeds = purchased and purchased.Seeds
    if not seeds then
        return nil
    end
    return tonumber(seeds[seedName]) or 0
end

local function getSeedStockValue(seedName)
    local seedShop = getSeedShop()
    local items = seedShop and seedShop:FindFirstChild("Items")
    local item = items and items:FindFirstChild(seedName)
    if not item then
        return nil
    end
    local ok, value = pcall(function()
        return item.Value
    end)
    if not ok then
        return nil
    end
    return tonumber(value)
end

local function getRemainingSeedStock(seedName)
    resetSeedAssumptionsIfNeeded()
    local maxStock = getSeedStockValue(seedName)
    local purchased = getPurchasedSeedCount(seedName)
    if maxStock == nil then
        return nil, maxStock, purchased
    end
    purchased = purchased or 0
    local assumed = SeedPurchaseAssumed.Counts[seedName] or 0
    return math.max(maxStock - purchased - assumed, 0), maxStock, purchased
end

local function noteSeedPurchase(seedName)
    resetSeedAssumptionsIfNeeded()
    SeedPurchaseAssumed.Counts[seedName] = (SeedPurchaseAssumed.Counts[seedName] or 0) + 1
end

local function rarityAllowed(rarity, minRarity)
    return (RarityScore[rarity] or 0) >= (RarityScore[minRarity or "Common"] or 1)
end

local function buildSeedCandidates(c)
    local out = {}
    if type(SeedData) ~= "table" then
        return out, "missing SeedData"
    end
    local money = tonumber(getSheckles()) or 0
    local keep = tonumber(c.KeepSheckles) or 0
    local budget = math.max(money - keep, 0)
    local minRarity = c.MinRarity or "Common"

    for _, data in ipairs(SeedData) do
        if type(data) == "table" and data.RestockShop and type(data.SeedName) == "string" then
            local price = tonumber(data.PurchasePrice)
            local rarity = tostring(data.Rarity or "")
            if price and price <= budget and rarityAllowed(rarity, minRarity) then
                local remaining = getRemainingSeedStock(data.SeedName)
                if remaining and remaining > 0 then
                    table.insert(out, {
                        Name = data.SeedName,
                        Price = price,
                        Rarity = rarity,
                        RarityScore = RarityScore[rarity] or 0,
                        Order = tonumber(data.SeedShopDisplayOrder) or 0,
                        Stock = remaining,
                    })
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if a.RarityScore ~= b.RarityScore then
            return a.RarityScore > b.RarityScore
        end
        if a.Order ~= b.Order then
            return a.Order > b.Order
        end
        return a.Price > b.Price
    end)

    return out
end

local function getPlot()
    local id = LocalPlayer:GetAttribute("PlotId")
    if not id then return nil end
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return nil end
    return gardens:FindFirstChild("Plot" .. tostring(id))
end

-- Lấy danh sách part "PlantArea" thuộc plot mình (xác nhận ở SprinklerController/PlantController)
-- TOI UU RAM/CPU: truoc day MOI LAN goi la plot:GetDescendants() (quet ca tram cay = cap phat bang
-- khong lo) ma ham nay bi goi LIEN TUC (AutoWater 20 lan/vong, GetStandCF, GUI, sprinkler, home...)
-- -> churn RAM khung khiep + giat. Gio: (1) doc tu CollectionService:GetTagged("PlantArea") (chi tra
-- part CO TAG, it hon GetDescendants ca ngan lan), (2) CACHE 10s (o PlantArea chi doi khi mua
-- expansion -> TTL 10s la du nhay). Cac caller CHI DOC list, khong ai mutate -> share cache an toan.
local function getPlantAreaParts()
    local plot = getPlot()
    if not plot then return {} end
    local cache = Runtime.PlantAreaCache
    if cache and cache.Plot == plot and (os.clock() - cache.At) < 10 then
        return cache.Parts
    end
    local parts = {}
    for _, part in ipairs(CollectionService:GetTagged("PlantArea")) do
        if part:IsA("BasePart") and part:IsDescendantOf(plot) then
            parts[#parts + 1] = part
        end
    end
    Runtime.PlantAreaCache = { Plot = plot, Parts = parts, At = os.clock() }
    return parts
end

-- Đếm ô PlantArea NHÌN THẤY: bỏ part ẨN (Transparency=1) như PlantAreaColumn1/2 (vùng cột ẩn của game),
-- chỉ đếm các ô luống hiện (BedSection.Part) -> khớp số ô mắt thấy. Dùng cho hiển thị GUI "Plants: x/total".
local function countVisiblePlantAreas()
    local n = 0
    for _, p in ipairs(getPlantAreaParts()) do
        if p.Transparency < 1 then n = n + 1 end
    end
    return n
end

-- Một điểm Vector3 ngẫu nhiên trên mặt 1 ô PlantArea (để gửi vào PlantSeed)
local function randomPlantPosition()
    local parts = getPlantAreaParts()
    if #parts == 0 then return nil end
    local part = parts[math.random(1, #parts)]
    local half = part.Size * 0.5
    local offX = (math.random() * 2 - 1) * (half.X * 0.85)
    local offZ = (math.random() * 2 - 1) * (half.Z * 0.85)
    -- điểm trên mặt trên của ô, đưa về world-space
    local localPoint = Vector3.new(offX, half.Y, offZ)
    return part.CFrame:PointToWorldSpace(localPoint)
end

-- Vị trí (Vector3) các cây ĐANG trồng trong plot.Plants -> để lưới NÉ, không trồng đè.
local function getPlantedPositions()
    local plot = getPlot()
    local pf = plot and plot:FindFirstChild("Plants")
    local out = {}
    if pf then
        for _, m in ipairs(pf:GetChildren()) do
            if m:IsA("Model") then
                local ok, p = pcall(function() return m:GetPivot().Position end)
                if ok and typeof(p) == "Vector3" then out[#out + 1] = p end
            end
        end
    end
    return out
end

-- TRỒNG TỐI ƯU: sinh điểm theo LƯỚI ĐỀU trên các ô PlantArea, BỎ điểm gần cây đã trồng.
-- Dùng spatial hash (cell = spacing) nên nhanh O(n). Trả về list Vector3 phủ kín ô.
local function buildGridPlantPositions(spacing, margin)
    spacing = math.max(tonumber(spacing) or 2, 0.25)
    margin = math.clamp(tonumber(margin) or 0.9, 0.1, 1)
    local parts = getPlantAreaParts()
    if #parts == 0 then return {} end

    local cell = spacing
    local occupied = {}
    local minSqr = (spacing * 0.9) * (spacing * 0.9)  -- né nếu khoảng cách < 0.9*spacing
    local function keyOf(x, z) return math.floor(x / cell) .. "," .. math.floor(z / cell) end
    local function mark(x, z)
        local k = keyOf(x, z)
        local b = occupied[k]; if not b then b = {}; occupied[k] = b end
        b[#b + 1] = { x, z }
    end
    local function tooClose(x, z)
        local cx, cz = math.floor(x / cell), math.floor(z / cell)
        for dx = -1, 1 do
            for dz = -1, 1 do
                local b = occupied[(cx + dx) .. "," .. (cz + dz)]
                if b then
                    for _, q in ipairs(b) do
                        local ddx, ddz = q[1] - x, q[2] - z
                        if (ddx * ddx + ddz * ddz) < minSqr then return true end
                    end
                end
            end
        end
        return false
    end

    for _, p in ipairs(getPlantedPositions()) do mark(p.X, p.Z) end

    local out = {}
    local scanned = 0   -- STAGGER chong freeze: plot to = ca ngan diem luoi -> nha frame moi 500 diem
    for _, part in ipairs(parts) do
        local half = part.Size * 0.5
        local usableX = half.X * 2 * margin
        local usableZ = half.Z * 2 * margin
        local nx = math.max(math.floor(usableX / spacing), 0)
        local nz = math.max(math.floor(usableZ / spacing), 0)
        for ix = 0, nx do
            for iz = 0, nz do
                scanned = scanned + 1
                if scanned % 500 == 0 then task.wait() end
                local lx = -usableX * 0.5 + ix * spacing
                local lz = -usableZ * 0.5 + iz * spacing
                local world = part.CFrame:PointToWorldSpace(Vector3.new(lx, half.Y, lz))
                if not tooClose(world.X, world.Z) then
                    out[#out + 1] = world
                    mark(world.X, world.Z)
                end
            end
        end
    end
    return out
end

-- VỊ TRÍ MẬT ĐỘ CÂY CAO NHẤT (để ĐẶT sprinkler/gear đúng chỗ, không đặt bậy). Dùng cây ĐANG trồng
-- (getPlantedPositions) gom vào bucket lưới cạnh = radius; bucket nhiều cây nhất = vùng dày nhất; trả
-- về tâm bucket đó CHIẾU lên mặt ô PlantArea gần nhất (để PlaceSprinkler hợp lệ). Không có cây -> random.
-- O(n) nên không gây giật dù nhiều cây. Gắn Runtime.* để tránh thêm local main-scope.
Runtime.DensestPlantPosition = function(radius)
    radius = math.max(tonumber(radius) or 12, 2)
    local plants = getPlantedPositions()
    if #plants == 0 then return randomPlantPosition() end
    local cell = radius
    local buckets = {}
    local bestKey, bestN = nil, 0
    for _, p in ipairs(plants) do
        local key = math.floor(p.X / cell) .. "," .. math.floor(p.Z / cell)
        local b = buckets[key]
        if not b then b = { n = 0, sx = 0, sz = 0 }; buckets[key] = b end
        b.n = b.n + 1; b.sx = b.sx + p.X; b.sz = b.sz + p.Z
        if b.n > bestN then bestN = b.n; bestKey = key end
    end
    local b = buckets[bestKey]
    local cx0, cz0 = b.sx / b.n, b.sz / b.n            -- tâm (centroid) của cụm dày nhất
    local parts = getPlantAreaParts()
    local bestPart, bestD = nil, math.huge
    for _, part in ipairs(parts) do
        local dx, dz = part.Position.X - cx0, part.Position.Z - cz0
        local d = dx * dx + dz * dz
        if d < bestD then bestD = d; bestPart = part end
    end
    if bestPart then
        local lp = bestPart.CFrame:PointToObjectSpace(Vector3.new(cx0, bestPart.Position.Y, cz0))
        local half = bestPart.Size * 0.5
        local lx = math.clamp(lp.X, -half.X * 0.85, half.X * 0.85)
        local lz = math.clamp(lp.Z, -half.Z * 0.85, half.Z * 0.85)
        return bestPart.CFrame:PointToWorldSpace(Vector3.new(lx, half.Y, lz))
    end
    return Vector3.new(cx0, plants[1].Y, cz0)
end

local function getCharacter()
    return LocalPlayer.Character
end

local function getHumanoid()
    local char = getCharacter()
    return char and char:FindFirstChildOfClass("Humanoid")
end

-- Lấy mọi Tool (cả Backpack lẫn đang cầm) thỏa điều kiện attr
local function getToolsWithAttribute(attrName)
    local out = {}
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and t:GetAttribute(attrName) ~= nil then
                table.insert(out, t)
            end
        end
    end
    local char = getCharacter()
    if char then
        for _, t in ipairs(char:GetChildren()) do
            if t:IsA("Tool") and t:GetAttribute(attrName) ~= nil then
                table.insert(out, t)
            end
        end
    end
    return out
end

local function getMyPlantModels()
    local out = {}
    local plot = getPlot()
    local plantsFolder = plot and plot:FindFirstChild("Plants")
    if not plantsFolder then
        return out, nil
    end
    for _, m in ipairs(plantsFolder:GetChildren()) do
        if m:IsA("Model") then
            table.insert(out, m)
        end
    end
    return out, plantsFolder
end

local function countMyPlants()
    local plantModels = getMyPlantModels()
    return #plantModels
end

local function isFruitTool(tool)
    if not (tool and tool:IsA("Tool")) then
        return false
    end
    if FruitProxyUtil and type(FruitProxyUtil.IsFruitTool) == "function" then
        local ok, res = pcall(FruitProxyUtil.IsFruitTool, tool)
        if ok then
            return res == true
        end
    end
    return tool:GetAttribute("HarvestedFruit") == true
end

local function getAllTools()
    local out = {}
    local seen = {}
    local function scan(container)
        if not container then
            return
        end
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") and not seen[item] then
                seen[item] = true
                table.insert(out, item)
            end
        end
    end
    scan(LocalPlayer:FindFirstChildOfClass("Backpack"))
    scan(getCharacter())
    return out
end

local function hasRainbowText(value)
    if type(value) ~= "string" then
        return false
    end
    return string.find(string.lower(value), "rainbow", 1, true) ~= nil
end

local function isRainbowSeedTool(tool)
    if not (tool and tool:IsA("Tool")) then
        return false
    end
    local hasSeedSignal = tool:GetAttribute("SeedTool") ~= nil
        or tool:GetAttribute("SeedPack") ~= nil
        or tool:GetAttribute("RainbowSeed") == true
    if not hasSeedSignal then
        return false
    end
    if tool:GetAttribute("RainbowSeed") == true then
        return true
    end
    if hasRainbowText(tool.Name) then
        return true
    end
    if hasRainbowText(tool:GetAttribute("SeedTool")) then
        return true
    end
    if hasRainbowText(tool:GetAttribute("SeedPack")) then
        return true
    end
    return false
end

local function normalizeItemName(value)
    local text = string.lower(tostring(value or ""))
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return text
end

local function addConfiguredNames(target, list)
    if type(list) ~= "table" then
        return
    end
    for key, value in pairs(list) do
        if type(value) == "string" and value ~= "" then
            target[normalizeItemName(value)] = true
        elseif type(key) == "string" and value ~= false then
            target[normalizeItemName(key)] = true
        end
    end
end

local function nameMatchesConfiguredSet(value, names)
    local text = normalizeItemName(value)
    if text == "" or type(names) ~= "table" then
        return false
    end
    for name in pairs(names) do
        if name ~= "" and (text == name or string.find(text, name, 1, true)) then
            return true
        end
    end
    return false
end

Runtime.ShouldKeepSeed = function(seedName, tool)
    local c = CFG.KeepSeeds
    local names = {}
    if c and c.Enabled ~= false then
        addConfiguredNames(names, c.List or c.Seeds or c.SeedNames)
    end
    if CFG.ValuableWatcher and CFG.ValuableWatcher.KeepRainbowSeed ~= false then
        names[normalizeItemName("Rainbow")] = true
    end
    if next(names) == nil then
        return false
    end
    if nameMatchesConfiguredSet(seedName, names) then
        return true
    end
    if tool then
        if nameMatchesConfiguredSet(tool.Name, names)
            or nameMatchesConfiguredSet(tool:GetAttribute("SeedTool"), names)
            or nameMatchesConfiguredSet(tool:GetAttribute("SeedPack"), names)
            or (names[normalizeItemName("Rainbow")] and isRainbowSeedTool(tool)) then
            return true
        end
        -- KHOP THEO ATTRIBUTE "<Ten>Seed"=true tren tool theo dung quy uoc source (SpawnSeedPackController doc
        -- RainbowSeed/GoldSeed/MegaSeed). Vd Lock "Mega" -> check MegaSeed, "Gold" -> GoldSeed, "Rainbow" -> RainbowSeed.
        -- Dam bao lock seed dac biet AN CHAC du tool co ten chung chung; tu future-proof seed moi.
        local rawList = c and (c.List or c.Seeds or c.SeedNames)
        if type(rawList) == "table" then
            for _, entry in ipairs(rawList) do
                if type(entry) == "string" and entry ~= "" then
                    local ok, val = pcall(function() return tool:GetAttribute(entry .. "Seed") end)
                    if ok and val == true then return true end
                end
            end
        end
    end
    return false
end

local function normalizeRarity(rarity)
    rarity = tostring(rarity or "Common")
    if rarity == "Mythical" then
        return "Mythic"
    end
    return rarity
end

-- DANH SÁCH PET RARITY (theo SHOP LIVE chồng cung cấp) — TRA THEO TÊN, không phụ thuộc dump PetData.
-- key đã normalize: chữ thường + bỏ khoảng trắng -> khớp cả Display name ("Golden Dragonfly")
-- lẫn key nội bộ ("GoldenDragonfly").
local PetRarityByName = {
    frog = "Common",  bunny = "Common",
    owl = "Uncommon",
    deer = "Rare",
    robin = "Legendary",  bee = "Legendary",
    monkey = "Mythic",  goldendragonfly = "Mythic",  unicorn = "Mythic",
    raccoon = "Super",  blackdragon = "Super",  iceserpent = "Super",
}
local function lookupPetRarityByName(petName)
    if type(petName) ~= "string" or petName == "" then return nil end
    return PetRarityByName[(petName:lower():gsub("%s+", ""))]
end

-- Chuẩn hoá tên pet để KHỚP dù viết "Golden Dragonfly" hay "GoldenDragonfly" (thường + bỏ khoảng trắng).
local function normPetKey(name)
    return (tostring(name or ""):lower():gsub("%s+", ""))
end

local function getPetRarityFromSource(petName, tool)
    -- ƯU TIÊN danh sách cứng theo tên (chuẩn live), rồi mới tới attribute / PetData (dump).
    local byName = lookupPetRarityByName(petName)
    if byName then return normalizeRarity(byName) end
    local attrRarity = tool and tool:GetAttribute("Rarity")
    if type(attrRarity) == "string" and attrRarity ~= "" then
        return normalizeRarity(attrRarity)
    end
    local data = PetData and PetData[petName]
    return normalizeRarity(data and data.Rarity or "Common")
end

local function isHighPetRarity(rarity, minRarity)
    rarity = normalizeRarity(rarity)
    minRarity = normalizeRarity(minRarity or "Mythic")
    return (RarityScore[rarity] or 0) >= (RarityScore[minRarity] or RarityScore.Mythic or 6)
end

-- AUTO-DETECT seed dac biet MOI (khong can update code): tra ten attribute boolean ten *Seed = true
-- KHONG nam trong cac loai da biet {SeedPack,RainbowSeed,GoldSeed,MegaSeed}. Vd tuong lai game them "UltraSeed=true"
-- thi van bat duoc -> coi la seed dac biet de uu tien lay. nil neu khong co. (Source: SpawnSeedPackController.u11
-- doc attribute SeedPack/RainbowSeed/GoldSeed/MegaSeed tren part o SeedPackSpawnServerLocations.)
Runtime.GetSeedSpawnSpecialAttr = function(spawn)
    local ok, attrs = pcall(function() return spawn:GetAttributes() end)
    if not (ok and type(attrs) == "table") then return nil end
    for attr, val in pairs(attrs) do
        if val == true and type(attr) == "string"
            and attr ~= "SeedPack" and attr ~= "RainbowSeed" and attr ~= "GoldSeed" and attr ~= "MegaSeed"
            and string.find(attr, "Seed", 1, true) then
            return attr
        end
    end
    return nil
end

Runtime.GetPrioritySeedSpawnLabel = function()
    local c = CFG.AutoCollectDrops
    if not (c and c.Enabled and c.IncludeSeedPackSpawns ~= false) then
        return nil
    end
    -- CACHE 0.25s (dot 2 - giam CPU): ham nay bi MOI task goi moi vong (yield check) + delay fn ->
    -- truoc day quet folder spawn lien tuc. 0.25s van du nhay de bat event tuc thi.
    local cache = Runtime.SeedLabelCache
    if cache and (os.clock() - cache.At) < 0.25 then
        return cache.Label
    end
    local map = workspace:FindFirstChild("Map")
    local folder = map and map:FindFirstChild("SeedPackSpawnServerLocations")
    if not folder then
        return nil
    end

    local bestLabel
    local bestPriority = -1
    for _, spawn in ipairs(folder:GetChildren()) do
        local seedPack = spawn:GetAttribute("SeedPack")
        local isRainbow = spawn:GetAttribute("RainbowSeed") == true
        local isGold = spawn:GetAttribute("GoldSeed") == true
        local isMega = spawn:GetAttribute("MegaSeed") == true   -- source: SpawnSeedPackController u11
        local label
        local priority = 0
        if isRainbow then
            label = "Rainbow Seed"
            priority = 300
        elseif isMega then
            label = "Mega Seed"
            priority = 280
        elseif isGold then
            label = "Gold Seed"
            priority = 200
        elseif type(seedPack) == "string" and seedPack ~= "" then
            label = seedPack
            priority = 100
        else
            local special = Runtime.GetSeedSpawnSpecialAttr(spawn)  -- auto-detect seed dac biet moi
            if special then label = special; priority = 250 end
        end
        if label and priority > bestPriority then
            bestLabel = label
            bestPriority = priority
        end
    end
    Runtime.SeedLabelCache = { Label = bestLabel, At = os.clock() }
    return bestLabel
end

Runtime.GetPriorityWildPetCandidate = function()
    local c = CFG.AutoTameWildPet
    if not (c and c.Enabled) then
        return nil
    end
    -- CACHE 1s (dot 2 - FIX DO NANG): ham nay bi ~12 task goi MOI VONG qua ShouldYieldForPetPriority,
    -- ma ben trong (khi co Pets.Buy map) con dem pet so huu = FIRE REMOTE cho server tra loi -> truoc
    -- day moi vong cua moi task deu block cho remote -> nghen CPU + giat khi nhieu tab. Cache 1s + xoa
    -- cache ngay khi mua duoc pet (watcher) -> van nhay, nhung chi ton 1 lan scan/giay cho CA script.
    local cache = Runtime.PetPriorityCache
    if cache and (os.clock() - cache.At) < 1 then
        return cache.Best
    end
    local map = workspace:FindFirstChild("Map")
    local folder = map and map:FindFirstChild("WildPetRef")
    if not folder then
        return nil
    end

    local keep = tonumber(c.KeepSheckles) or 0
    local budget = math.max((tonumber(getSheckles()) or 0) - keep, 0)
    local minRarity = normalizeRarity(c.PriorityMinRarity or c.MinRarity or "Legendary")

    -- CHỈ ưu tiên pet mà AutoTameWildPet THỰC SỰ mua (khớp Buy map / PetNames). Nếu config chỉ mua
    -- Unicorn/GD/Monkey/Deer thì thấy Robin KHÔNG được bắt task khác nhường (tránh kẹt vô hạn).
    -- capMap = OwnLimit { [tên] = max muốn sở hữu }. ĐỦ cap (equip+túi) -> KHÔNG flag ưu tiên nữa
    -- (sửa loop "skip pet first Deer": đủ 3 con Deer mà vẫn báo ưu tiên mua Deer hoài).
    local nameSet, capByName, ownedTotal, ownedVar
    if type(c.OwnLimit) == "table" and next(c.OwnLimit) ~= nil then
        nameSet, capByName = {}, {}
        for kName, spec in pairs(c.OwnLimit) do
            if type(kName) == "string" then
                local k = normPetKey(kName)
                nameSet[k] = true
                local _, vmap, total = Runtime.ParsePetSizeSpec(spec)
                if vmap then capByName[k] = { variants = vmap }
                elseif total then capByName[k] = { total = total } end
            end
        end
        ownedTotal = Runtime.GetOwnedPetCounts()
        ownedVar   = Runtime.GetOwnedPetVariantCounts()
    elseif type(c.PetNames) == "table" and #c.PetNames > 0 then
        nameSet = {}
        for _, n in ipairs(c.PetNames) do
            if type(n) == "string" and n ~= "" then nameSet[normPetKey(n)] = true end
        end
    end

    local best
    for _, ref in ipairs(folder:GetChildren()) do
        if ref:IsA("BasePart") then
            local petName = ref:GetAttribute("PetName")
            local ownerUserId = ref:GetAttribute("OwnerUserId")
            local price = tonumber(ref:GetAttribute("Price")) or 0
            if type(petName) == "string" and petName ~= "" and ownerUserId ~= LocalPlayer.UserId and price <= budget then
                local rarity = normalizeRarity(lookupPetRarityByName(petName) or ref:GetAttribute("Rarity") or (PetData and PetData[petName] and PetData[petName].Rarity) or "Common")
                local lname = normPetKey(petName)
                local variant = Runtime.ClassifyPetVariant(ref:GetAttribute("PetSize"), ref:GetAttribute("PetType"))
                -- có Buy list -> tên phải nằm trong list (+ còn THIẾU theo size/total mới ưu tiên); không có -> theo độ hiếm.
                local allow
                if nameSet then
                    allow = nameSet[lname] == true
                    if allow and capByName and capByName[lname] then
                        local capE = capByName[lname]
                        if capE.variants then
                            local cap = tonumber(capE.variants[variant]) or 0
                            allow = cap > 0 and ((ownedVar[lname] or {})[variant] or 0) < cap
                        elseif capE.total then
                            allow = capE.total > 0 and (ownedTotal[lname] or 0) < capE.total
                        end
                    end
                else
                    allow = rarityAllowed(rarity, minRarity)
                end
                if allow then
                    local score = ((RarityScore[rarity] or 0) * 100000000) + price
                    if not best or score > best.Score then
                        best = {
                            Ref = ref,
                            Name = petName,
                            Rarity = rarity,
                            Price = price,
                            Score = score,
                        }
                    end
                end
            end
        end
    end
    Runtime.PetPriorityCache = { Best = best, At = os.clock() }
    return best
end

Runtime.ShouldYieldForSeedPriority = function(action)
    local now = os.clock()
    if State.SeedClaimInProgress or (tonumber(State.SeedClaimUntil) or 0) > now then
        return true
    end
    local label = Runtime.GetPrioritySeedSpawnLabel()
    if label then
        State.SeedClaimUntil = now + math.max((tonumber(CFG.AutoCollectDrops and CFG.AutoCollectDrops.Delay) or 0.5) + 0.75, 1)
        actionLog(action or "Priority", "SKIP", "seed first " .. tostring(label))
        return true
    end
    return false
end

Runtime.ShouldYieldForPetPriority = function(action)
    local now = os.clock()
    if State.PetTameInProgress or (tonumber(State.PetTameUntil) or 0) > now then
        return true
    end
    local pet = Runtime.GetPriorityWildPetCandidate()
    if pet then
        State.PetTameUntil = now + math.max(tonumber(CFG.AutoTameWildPet and CFG.AutoTameWildPet.PriorityYieldSeconds) or 1.5, 0.5)
        State.LastPet = os.date("%H:%M:%S") .. " priority " .. tostring(pet.Name) .. " " .. tostring(pet.Rarity)
        actionLog(action or "Priority", "SKIP", ("pet first %s %s $%s"):format(tostring(pet.Name), tostring(pet.Rarity), tostring(pet.Price)))
        return true
    end
    return false
end

-- ĐANG TRIM (đào cây) -> các tác vụ phụ NHƯỜNG (trim thì lo trim). State.TrimActiveUntil được
-- doTrimToQuota refresh mỗi nhát đào, set 0 khi trim xong (tự hết hạn sau ~15s nếu lỡ miss clear).
Runtime.ShouldYieldForTrim = function(action)
    if (tonumber(State.TrimActiveUntil) or 0) > os.clock() then
        actionLog(action or "Priority", "SKIP", "trim first")
        return true
    end
    return false
end

-- ============================================================
-- KHOA TOOL DUNG CHUNG (fix XUNG DOT LUONG "tua lua"): truoc day AutoPlant (hat) / AutoWater (binh) /
-- AutoSprinkler / Trim + ShovelReplace (xeng) / HatchEgg / OpenCrate / OpenSeedPack / EquipPet /
-- AntiSteal cung equip tool DE NHAU -> tool nhay qua lai, thao tac hong giua chung (trong fail, tuoi
-- hut...), nhin giat "tua lua". Gio: task PHAI xin khoa TRUOC khi equip; task khac dang giu -> SKIP
-- luot nay (vong sau tu thu lai, khong mat gi). Khoa TU HET HAN (expiry) -> lo quen release (return
-- giua chung) cung KHONG ket vinh vien. force=true (AntiSteal/Trim = viec khan) -> cuop khoa ngay.
-- ============================================================
Runtime.ToolLockBy = nil
Runtime.ToolLockUntil = 0
Runtime.TryToolLock = function(name, seconds, force)
    local nowc = os.clock()
    if not force and Runtime.ToolLockBy and Runtime.ToolLockBy ~= name
        and (tonumber(Runtime.ToolLockUntil) or 0) > nowc then
        return false
    end
    Runtime.ToolLockBy = name
    Runtime.ToolLockUntil = nowc + math.max(tonumber(seconds) or 3, 0.5)
    return true
end
Runtime.ExtendToolLock = function(name, seconds)
    if Runtime.ToolLockBy == name then
        Runtime.ToolLockUntil = os.clock() + math.max(tonumber(seconds) or 2, 0.5)
    end
end
Runtime.ReleaseToolLock = function(name)
    if Runtime.ToolLockBy == name then
        Runtime.ToolLockBy = nil
        Runtime.ToolLockUntil = 0
    end
end

-- ============================================================
-- TURBO FPS (dot 5 - trick cua chong, XAC NHAN docs Potassium: "use a very large value (e.g. 2000)
-- to effectively uncap"; VoltBZ cung co setfpscap/getfpscap): task NANG (nuke/xoa do/quet lon) ->
-- MO CAP 9999 cho chay VU (o cap 7 moi task.wait giua cac batch phai doi 1 frame ~143ms -> xoa ca
-- ngan vat keo dai ca phut = "DO"; turbo thi frame chi vai ms -> xong trong vai giay), xong viec
-- KHOA LAI cap cu ngay. Dem depth -> nhieu task nang chong nhau van dung; ApplyFpsCap tu BO QUA
-- khi dang turbo (khong ghi de nguoc).
-- ============================================================
Runtime.TurboDepth = 0
Runtime.GetFpsCapFn = function()
    return (type(setfpscap) == "function" and setfpscap)
        or (type(set_fps_cap) == "function" and set_fps_cap)
        or nil
end
Runtime.BeginTurboFps = function(reason)
    Runtime.TurboDepth = (Runtime.TurboDepth or 0) + 1
    Runtime.TurboDeadline = os.clock() + math.max(tonumber(CFG.TurboMaxSeconds) or 45, 5)
    if Runtime.TurboDepth > 1 then return end
    local capFn = Runtime.GetFpsCapFn()
    if not capFn then return end
    -- nho cap hien tai (neu executor co getfpscap) de tra lai dung ke ca khi FpsBoost tat
    if type(getfpscap) == "function" then
        pcall(function() Runtime.PreTurboCap = getfpscap() end)
    end
    pcall(capFn, tonumber(CFG.TurboFps) or 9999)
    State.FpsCapStatus = "TURBO " .. tostring(reason or "")
    actionLog("FpsBoost", "TURBO", tostring(reason or "heavy task"))
end
Runtime.EndTurboFps = function()
    Runtime.TurboDepth = math.max((Runtime.TurboDepth or 1) - 1, 0)
    if Runtime.TurboDepth > 0 then return end
    Runtime.TurboDeadline = nil
    local c = CFG.FpsBoost
    if c and c.Enabled and type(Runtime.ApplyFpsCap) == "function" then
        pcall(Runtime.ApplyFpsCap)   -- KHOA lai cap cau hinh (vd 7)
    elseif tonumber(Runtime.PreTurboCap) then
        local capFn = Runtime.GetFpsCapFn()
        if capFn then pcall(capFn, tonumber(Runtime.PreTurboCap)) end
        State.FpsCapStatus = "cap=" .. tostring(Runtime.PreTurboCap)
    end
end

-- TỐI ƯU FPS: ép delay TỐI THIỂU cho các tác vụ phụ (mặc định 1.5s) -> bớt chạy chồng chéo.
-- Các task ưu tiên/nặng (AutoCollect, AutoCollectDrops, AutoSell, claim event...) KHÔNG bị ép.
-- Knob: CFG.SideTaskMinDelay (giây).
Runtime.SideTaskSet = {
    AutoBuySeed = true, AutoBuyGear = true, AutoBuyCrate = true, AutoHatchEgg = true,
    AutoSprinkler = true, AutoWater = true, AutoOpenCrate = true, AutoOpenSeedPack = true,
}
Runtime.ApplySideTaskMinDelay = function(name, delay)
    if Runtime.SideTaskSet[name] then
        local floor = tonumber(CFG.SideTaskMinDelay) or 1.5
        -- FPS NGUY KICH (nhieu tab): ep san task phu len >= 3s -> nhuong CPU cho harvest/claim/sell,
        -- het do. FPS hoi lai la tu ve nhip cu (State.CriticalFps do FpsMonitor cap nhat lien tuc).
        if State.CriticalFps then
            floor = math.max(floor, 3)
        end
        return math.max(tonumber(delay) or 1, floor)
    end
    return delay
end

Runtime.WebhookSeen = {}
Runtime.WebhookPending = {}
Runtime.WebhookLastAt = 0
Runtime.WebhookQueue = {}
Runtime.WebhookWorkerRunning = false

-- BOUND Runtime.WebhookSeen (chong leak RAM lau dai khi farm 24/7): key dedup (seed:/gold:/petbuy:) la duy nhat
-- moi su kien nen set nay phinh dan. Toi 1500 key -> xoa sach (dedup gan day la du; persist SeenStore lo
-- chong gui lai sau relog). Gan vao Runtime de KHONG them local main-chunk (file sat gioi han 200 local).
Runtime.WebhookSeenCount = 0
Runtime.MarkWebhookSeen = function(key)
    if Runtime.WebhookSeen[key] == nil then
        Runtime.WebhookSeenCount = (Runtime.WebhookSeenCount or 0) + 1
        if Runtime.WebhookSeenCount > 1500 then
            for k in pairs(Runtime.WebhookSeen) do Runtime.WebhookSeen[k] = nil end
            Runtime.WebhookSeenCount = 1
        end
    end
    Runtime.WebhookSeen[key] = true
end

-- ============================================================
-- SeenStore: nhớ những key đã gửi webhook XUỐNG FILE (ổ đĩa executor),
-- lưu theo UserId từng acc -> relog / reload script vẫn không gửi TRÙNG.
-- Sửa lỗi: acc đã có pet/seed rồi, out ra vào lại, script tưởng mới -> báo lại.
-- Dùng pcall + type-check vì không phải executor nào cũng có file API.
-- ============================================================
Runtime.SeenStore = {}
do
    local SeenStore = Runtime.SeenStore
    local hasFs = type(writefile) == "function"
        and type(readfile) == "function"
        and type(isfile) == "function"
    local folder = "Kaitun"
    local userTag = tostring((LocalPlayer and LocalPlayer.UserId) or "unknown")
    local path = folder .. "/seen_" .. userTag .. ".json"
    local data = {}
    local loaded = false
    local dirty = false

    local function ensureFolder()
        if type(makefolder) == "function" and type(isfolder) == "function" then
            pcall(function()
                if not isfolder(folder) then
                    makefolder(folder)
                end
            end)
        end
    end

    function SeenStore.load()
        if loaded then return end
        loaded = true
        if not hasFs then return end
        ensureFolder()
        local ok, raw = pcall(function()
            if isfile(path) then
                return readfile(path)
            end
            return nil
        end)
        if ok and type(raw) == "string" and raw ~= "" then
            local okDecode, decoded = pcall(function()
                return HttpService:JSONDecode(raw)
            end)
            if okDecode and type(decoded) == "table" then
                data = decoded
            end
        end
    end

    function SeenStore.has(key)
        if not key then return false end
        return data[tostring(key)] == true
    end

    function SeenStore.flush()
        if not hasFs or not dirty then return end
        local okEncode, body = pcall(function()
            return HttpService:JSONEncode(data)
        end)
        if okEncode then
            local okWrite = pcall(function()
                writefile(path, body)
            end)
            if okWrite then
                dirty = false
            end
        end
    end

    function SeenStore.add(key)
        if not key then return end
        key = tostring(key)
        if data[key] == true then return end
        data[key] = true
        dirty = true
        SeenStore.flush()
    end
end
Runtime.SeenStore.load()
Runtime.WebhookNoRequestLogged = false

Runtime.getWebhookRequest = function()
    if type(request) == "function" then
        return request
    end
    if type(http_request) == "function" then
        return http_request
    end
    if type(syn) == "table" and type(syn.request) == "function" then
        return syn.request
    end
    if type(http) == "table" and type(http.request) == "function" then
        return http.request
    end
    return nil
end

local function getAccountName()
    return tostring(LocalPlayer and LocalPlayer.Name or "unknown")
end

Runtime.HideBlockingPopups = function()
    local playerGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then
        return
    end
    local needles = {
        "pet info",
        "dig this up",
        "shovel will permanently",
    }
    for _, gui in ipairs(playerGui:GetChildren()) do
        if gui:IsA("ScreenGui")
            and gui.Name ~= "KaitunCommercial"
            and gui.Name ~= "NightNotifier" then
            local shouldHide = gui.Name == "EquipPet"
                or string.find(normalizeItemName(gui.Name), "petinfo", 1, true) ~= nil
            if not shouldHide then
                for _, obj in ipairs(gui:GetDescendants()) do
                    if obj:IsA("TextLabel") or obj:IsA("TextButton") then
                        local text = normalizeItemName(obj.Text)
                        for _, needle in ipairs(needles) do
                            if string.find(text, needle, 1, true) then
                                shouldHide = true
                                break
                            end
                        end
                    end
                    if shouldHide then
                        break
                    end
                end
            end
            if shouldHide then
                pcall(function()
                    gui.Enabled = false
                end)
            end
        end
    end
end

-- Đếm tổng Rainbow Seed đang có: ưu tiên kho thật (Inventory.Seeds), fallback tool trong người.
function Runtime.CountRainbowSeeds()
    local total = 0
    local counted = false
    local replica = getPlayerReplica()
    if replica and replica.Data and type(replica.Data.Inventory) == "table" then
        local seeds = replica.Data.Inventory.Seeds
        if type(seeds) == "table" then
            counted = true
            for key, count in pairs(seeds) do
                if type(key) == "string" and hasRainbowText(key) then
                    total = total + (tonumber(count) or 0)
                end
            end
        end
    end
    if not counted then
        for _, t in ipairs(getAllTools()) do
            if isRainbowSeedTool(t) then
                total = total + 1
            end
        end
    end
    return total
end

-- Gửi/sửa payload tới 1 webhook URL bất kỳ (riêng, khác CFG.Webhook). Trả ok, response.
function Runtime.HttpSend(method, url, payload)
    if type(url) ~= "string" or url == "" then
        return false, "no url"
    end
    local httpRequest = Runtime.getWebhookRequest()
    if not httpRequest then
        return false, "no request"
    end
    local okEncode, body = pcall(function()
        return HttpService:JSONEncode(payload)
    end)
    if not okEncode then
        return false, "encode"
    end
    local ok, res = pcall(function()
        return httpRequest({
            Url = url,
            Method = method,
            Headers = { ["Content-Type"] = "application/json" },
            Body = body,
        })
    end)
    if not ok then
        return false, tostring(res)
    end
    return true, res
end

-- Acc chỉ định (mặc định chuideptrai1209): mỗi phút UPDATE 1 message webhook riêng,
-- cho biết acc đang giữ bao nhiêu Rainbow Seed. Edit lại đúng 1 message thay vì spam.
function Runtime.DoRainbowAccountReport()
    local c = CFG.RainbowAccountReport
    if not (c and c.Enabled) then return end
    if type(c.Username) == "string" and c.Username ~= "" and getAccountName() ~= c.Username then
        return -- chỉ acc được chỉ định mới báo
    end
    if type(c.WebhookUrl) ~= "string" or c.WebhookUrl == "" then
        if not Runtime.RainbowReportNoUrlLogged then
            Runtime.RainbowReportNoUrlLogged = true
            actionLog("RainbowReport", "SKIP", "chua dien CFG.RainbowAccountReport.WebhookUrl")
        end
        return
    end

    local count = Runtime.CountRainbowSeeds()
    local payload = {
        content = tostring(c.Mention or ""),
        embeds = { {
            title = "🌈 Rainbow Seed Report",
            description = ("Acc **%s** đang giữ **%d** Rainbow Seed."):format(getAccountName(), count),
            color = 0x9B59B6,
            fields = {
                { name = "👤 Tài khoản", value = getAccountName(), inline = true },
                { name = "🆔 UserId", value = tostring(LocalPlayer.UserId), inline = true },
                { name = "🌈 Rainbow Seed", value = "x" .. tostring(count), inline = true },
            },
            footer = { text = "Kaitun Rainbow Report • cập nhật mỗi phút" },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        } },
    }

    -- Đã có message -> PATCH để update. Hỏng (message bị xóa) -> tạo mới.
    local id = Runtime.RainbowReportMsgId
    if id then
        local ok, res = Runtime.HttpSend("PATCH", c.WebhookUrl .. "/messages/" .. id, payload)
        local code = type(res) == "table" and tonumber(res.StatusCode) or nil
        if ok and (code == nil or code < 300) then
            State.LastRainbowReport = os.date("%H:%M:%S") .. " upd=" .. tostring(count)
            return
        end
        Runtime.RainbowReportMsgId = nil -- patch fail -> sẽ tạo lại
    end

    -- Tạo mới với ?wait=true để lấy message id (để lần sau edit).
    local sep = string.find(c.WebhookUrl, "?", 1, true) and "&" or "?"
    local ok, res = Runtime.HttpSend("POST", c.WebhookUrl .. sep .. "wait=true", payload)
    if ok then
        local rawBody = type(res) == "table" and res.Body
        if type(rawBody) == "string" and rawBody ~= "" then
            local okD, decoded = pcall(function() return HttpService:JSONDecode(rawBody) end)
            if okD and type(decoded) == "table" and decoded.id then
                Runtime.RainbowReportMsgId = tostring(decoded.id)
            end
        end
        State.LastRainbowReport = os.date("%H:%M:%S") .. " new=" .. tostring(count)
        actionLog("RainbowReport", "DONE", "count=" .. tostring(count))
    else
        actionLog("RainbowReport", "ERROR", tostring(res))
    end
end

Runtime.startWebhookWorker = nil
Runtime.enqueueWebhook = function(payload, title, key, persist)
    local c = CFG.Webhook
    if not (c and c.Enabled ~= false and type(c.Url) == "string" and c.Url ~= "") then
        return false
    end
    local maxQueue = tonumber(c.MaxQueue) or 80
    while #Runtime.WebhookQueue >= maxQueue do
        local dropped = table.remove(Runtime.WebhookQueue, 1)
        if dropped and dropped.Key then
            Runtime.WebhookPending[dropped.Key] = nil
        end
    end
    table.insert(Runtime.WebhookQueue, {
        Payload = payload,
        Title = tostring(title or "Webhook"),
        Tries = 0,
        Key = key,
        Persist = persist == true,
    })
    State.LastWebhook = os.date("%H:%M:%S") .. " queued=" .. tostring(#Runtime.WebhookQueue)
    if Runtime.startWebhookWorker then
        Runtime.startWebhookWorker()
    end
    return true
end

Runtime.startWebhookWorker = function()
    if Runtime.WebhookWorkerRunning then
        return
    end
    Runtime.WebhookWorkerRunning = true
    task.spawn(function()
        while isAlive() and #Runtime.WebhookQueue > 0 do
            local job = table.remove(Runtime.WebhookQueue, 1)
            local c = CFG.Webhook or {}
            local cooldown = math.max(tonumber(c.Cooldown) or 2, 0)
            local waitFor = cooldown - (os.clock() - Runtime.WebhookLastAt)
            if waitFor > 0 and not waitAlive(waitFor) then
                table.insert(Runtime.WebhookQueue, 1, job)
                break
            end

            local ok, res = Runtime.HttpSend("POST", c.Url, job.Payload)
            local code = type(res) == "table" and tonumber(res.StatusCode) or nil
            if ok and (not code or code < 300) then
                Runtime.WebhookLastAt = os.clock()
                State.LastWebhook = os.date("%H:%M:%S") .. " sent"
                if job.Key then
                    Runtime.MarkWebhookSeen(job.Key)
                    Runtime.WebhookPending[job.Key] = nil
                    if job.Persist then
                        Runtime.SeenStore.add(job.Key)
                    end
                end
                actionLog("Webhook", "DONE", job.Title)
            else
                job.Tries = (tonumber(job.Tries) or 0) + 1
                if job.Tries < 3 then
                    table.insert(Runtime.WebhookQueue, job)
                    State.LastWebhook = os.date("%H:%M:%S") .. " retry=" .. tostring(job.Tries)
                    if not waitAlive(math.min(2 * job.Tries, 6)) then
                        break
                    end
                else
                    State.LastWebhook = os.date("%H:%M:%S") .. " send fail"
                    if job.Key then
                        Runtime.WebhookPending[job.Key] = nil
                    end
                    actionLog("Webhook", "ERROR", compactText(res, 90))
                end
            end
        end
        Runtime.WebhookWorkerRunning = false
        if isAlive() and #Runtime.WebhookQueue > 0 then
            Runtime.startWebhookWorker()
        end
    end)
end

local function sendWebhookOnce(key, title, description, fields, color, opts)
    local c = CFG.Webhook
    if not (c and c.Enabled ~= false and type(c.Url) == "string" and c.Url ~= "") then
        return false
    end
    -- CHỈ gửi các loại webhook: MUA PET thành công ("petbuy:") + lấy RAINBOW/GOLD/MEGA SEED
    -- ("seed:"/"gold:"/"mega:"). Mọi loại khác (mail gửi "mailseed:/mailrb:/mailpet:", mail nhận
    -- "mailclaim:", high pet "pet:") -> KHÔNG gửi.
    -- (FIX: truoc day thieu "mega:" -> claim Mega Seed bi chan im lang o day, khong bao ve webhook.)
    if not (type(key) == "string"
        and (key:sub(1, 7) == "petbuy:" or key:sub(1, 5) == "seed:" or key:sub(1, 5) == "gold:"
            or key:sub(1, 5) == "mega:")) then
        return false
    end
    opts = type(opts) == "table" and opts or {}
    if key then
        if Runtime.WebhookSeen[key] or Runtime.WebhookPending[key] then
            return false
        end
        -- persist=true: đã gửi ở phiên TRƯỚC (lưu file) thì không gửi lại sau relog.
        if opts.persist and Runtime.SeenStore.has(key) then
            Runtime.MarkWebhookSeen(key)
            return false
        end
    end

    local embed = {
        title = tostring(title or "Kaitun Alert"),
        description = tostring(description or ""),
        color = tonumber(color) or 5814783,
        fields = fields or {},
        footer = { text = tostring(opts.footer or "Kaitun Valuable Watcher") },
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    }
    if type(opts.footerIcon) == "string" and opts.footerIcon ~= "" then
        embed.footer.icon_url = opts.footerIcon
    end
    if type(opts.author) == "string" and opts.author ~= "" then
        embed.author = { name = opts.author }
        if type(opts.authorIcon) == "string" and opts.authorIcon ~= "" then
            embed.author.icon_url = opts.authorIcon
        end
    end
    if type(opts.thumbnail) == "string" and opts.thumbnail ~= "" then
        embed.thumbnail = { url = opts.thumbnail }
    end
    if type(opts.image) == "string" and opts.image ~= "" then
        embed.image = { url = opts.image }
    end
    local payload = {
        content = tostring(opts.content ~= nil and opts.content or (c.Mention or "")),
        embeds = { embed },
    }

    local okEncode = pcall(function()
        return HttpService:JSONEncode(payload)
    end)
    if not okEncode then
        State.LastWebhook = os.date("%H:%M:%S") .. " encode fail"
        actionLog("Webhook", "ERROR", "encode")
        return false
    end

    if key then
        Runtime.WebhookPending[key] = true
    end

    if not Runtime.enqueueWebhook(payload, title, key, opts.persist == true) then
        if key then
            Runtime.WebhookPending[key] = nil
        end
        return false
    end

    actionLog("Webhook", "QUEUE", tostring(title or "alert"))
    return true
end

local function countFruitTools()
    local count = 0
    local function scan(container)
        if not container then
            return
        end
        for _, item in ipairs(container:GetChildren()) do
            if isFruitTool(item) then
                count = count + 1
            end
        end
    end
    scan(LocalPlayer:FindFirstChildOfClass("Backpack"))
    scan(getCharacter())
    return count
end

-- Sức chứa quả THẬT của game (xác nhận InventoryController/Main.lua dòng 2687:
-- UI hiện "{FruitCount}/{MaxFruitCapacity} Fruits"). Đầy = FruitCount >= MaxFruitCapacity.
local function getFruitCount()
    return tonumber(LocalPlayer:GetAttribute("FruitCount"))
end

local function getMaxFruitCapacity()
    return tonumber(LocalPlayer:GetAttribute("MaxFruitCapacity")) or 100
end

-- Tỉ lệ đầy túi (0..1) kèm count, max. nil nếu game chưa set FruitCount.
local function getFruitFill()
    local count = getFruitCount()
    if not count then
        return nil
    end
    local max = getMaxFruitCapacity()
    if max <= 0 then
        return nil
    end
    return count / max, count, max
end

-- Túi đã đầy chưa (theo ngưỡng FullThreshold của AutoSell). nil-safe.
local function isInventoryFull()
    local ratio = getFruitFill()
    if not ratio then
        return false
    end
    local threshold = tonumber(CFG.AutoSell and CFG.AutoSell.FullThreshold) or 0.95
    return ratio >= threshold
end

local function getEquippedTool()
    local char = getCharacter()
    if not char then return nil end
    for _, item in ipairs(char:GetChildren()) do
        if item:IsA("Tool") then
            return item
        end
    end
    return nil
end

local function unequipTools()
    local hum = getHumanoid()
    if not hum then return false end
    local ok = pcall(function()
        hum:UnequipTools()
    end)
    if ok then
        waitAlive(0.05)
    end
    return ok
end

local function unequipSeedTool(action)
    local held = getEquippedTool()
    if not (held and held:GetAttribute("SeedTool") ~= nil) then
        return false
    end
    local seedName = held:GetAttribute("SeedTool") or held.Name
    if unequipTools() then
        actionLog(action or "Tool", "UNEQUIP", tostring(seedName))
        return true
    end
    return false
end

local function equipTool(tool)
    local hum = getHumanoid()
    local char = getCharacter()
    if not (hum and char and tool and tool.Parent) then return false end
    if tool.Parent ~= char then
        local held = getEquippedTool()
        if held and held ~= tool then
            unequipTools()
        end
        local ok = pcall(function() hum:EquipTool(tool) end)
        if not ok then return false end
        waitAlive(0.08)
    end
    return tool.Parent == getCharacter()
end

local function getRootPart()
    local char = getCharacter()
    if not char then
        return nil
    end
    return char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
end

local function getGardenHomeCFrame()
    -- ƯU TIÊN: SpawnPoint thật của plot — vị trí game cho player đứng khi bấm nút "Garden".
    -- Xác nhận: PlantVisualizerController.GetSpawnPoint (plot.SpawnPoint) + TeleportButtons
    -- ButtonHandler:84-93 (teleport tới plot.SpawnPoint.Position). Dùng cái này để KHÔNG bị
    -- kẹt dưới đất / đứng giữa đường đi như khi chọn "ô PlantArea gần nhất" (gây giật giật).
    do
        local plot = getPlot()
        if plot then
            local sp = plot:FindFirstChild("SpawnPoint")
            if sp and sp:IsA("BasePart") then
                return CFrame.new(sp.Position + Vector3.new(0, 3, 0))
            end
        end
    end

    local root = getRootPart()
    local parts = getPlantAreaParts()
    local bestPart
    local bestDistance = math.huge
    for _, part in ipairs(parts) do
        if part and part:IsA("BasePart") then
            local distance = root and (root.Position - part.Position).Magnitude or 0
            if not bestPart or distance < bestDistance then
                bestPart = part
                bestDistance = distance
            end
        end
    end
    if bestPart then
        local y = math.max((bestPart.Size.Y * 0.5) + 4, 5)
        return bestPart.CFrame * CFrame.new(0, y, 0)
    end

    local plot = getPlot()
    if plot then
        local ok, cf = pcall(function()
            local boxCf, boxSize = plot:GetBoundingBox()
            return boxCf * CFrame.new(0, math.max((boxSize.Y * 0.5) + 4, 6), 0)
        end)
        if ok and cf then
            return cf
        end
    end
    return nil
end

local function teleportToGardenHome(reason, waitSeconds)
    local root = getRootPart()
    -- DUNG CHUNG dich voi StandInOwnGardenCell/AntiPush (State.StandCF = o plot da nho). Truoc day Drop/Fruit/Pet
    -- ve SpawnPoint con Guard ve o plot -> 2 dich khac nhau -> keo qua lai -> "giat giat ve nha hoai".
    -- Gio tat ca ve CUNG o plot -> ve toi noi la dung yen, het giat.
    local homeCF = Runtime.GetStandCF() or getGardenHomeCFrame()
    if not (root and homeCF) then
        return false
    end
    local minMove = tonumber(CFG.HomeTeleportMinDistance) or 8
    if (root.Position - homeCF.Position).Magnitude <= minMove then
        return true
    end
    -- TWEEN MƯỢT VỀ PLOT (chồng: claim seed xong phải thấy tween về plot, KHÔNG snap tức thì).
    -- Dùng đúng TweenMoveTo như lúc ĐI (noclip + chốt đúng đích). Tắt = CFG.TweenHome=false -> snap như cũ.
    if CFG.TweenHome ~= false and type(Runtime.TweenMoveTo) == "function" then
        Runtime.TweenMoveTo(homeCF.Position, nil, CFG.TweenSpeed, reason or "home")
        local r = getRootPart()
        if r then pcall(function() r.CFrame = homeCF end) end   -- chốt đúng ô plot (giữ hướng đứng)
    else
        root.CFrame = homeCF
    end
    Runtime.FireTeleporterMimic((getRootPart() or root).Position)
    if reason then
        actionLog(reason, "RETURN_HOME")
    end
    return waitAlive(waitSeconds or 0.08)
end

-- ĐỨNG GIỮA 1 Ô PLANTAREA RANDOM CỦA PLOT MÌNH (thay vì đứng spawn ban đêm dễ bị trộm).
-- Ô PlantArea là part ĐẶC -> dù chồng xóa Baseplate/Map thì đứng trên ô vẫn KHÔNG rớt.
-- Nhớ ô đã chọn (State.StandCell) để không nhảy ô liên tục gây giật; chọn lại nếu ô biến mất.
-- Đích đứng = GIỮA 1 ô PlantArea random (đứng TRÊN mặt ô). Nhớ ô + CFrame đích (State.StandCF) để
-- AntiPush dùng CHUNG 1 vị trí -> KHÔNG đánh nhau gây giật. CHỈ teleport khi đang ở XA đích.
Runtime.GetStandCF = function()
    local cell = State.StandCell
    if not (cell and cell.Parent) then
        local cells = {}
        for _, p in ipairs(getPlantAreaParts()) do
            if p:IsA("BasePart") and p.Transparency < 1 then  -- chỉ luống NHÌN THẤY, bỏ cột ẩn
                cells[#cells + 1] = p
            end
        end
        if #cells == 0 then State.StandCell, State.StandCF = nil, nil; return nil end
        cell = cells[math.random(1, #cells)]
        State.StandCell = cell
        State.StandCF = cell.CFrame * CFrame.new(0, (cell.Size.Y * 0.5) + 3, 0)
    end
    return State.StandCF
end

Runtime.StandInOwnGardenCell = function()
    local root = getRootPart()
    if not root then return false end
    local target = Runtime.GetStandCF()
    if not target then return false end
    -- CHỈ teleport khi ở XA đích (>6 studs) -> đứng đúng chỗ rồi thì THÔI, không teleport lặp gây giật.
    if (root.Position - target.Position).Magnitude > 6 then
        root.CFrame = target
        Runtime.FireTeleporterMimic(root.Position)
        return true
    end
    return false
end

-- ============================================================
-- TWEEN TELEPORT (mượt, chống giật/kéo về) — bám source:
--   * 3 nút Garden/Seeds/Sell = Networking.TeleportButton.Request:Fire(name) -> server tự dời HỢP LỆ (không giật).
--   * Di chuyển MƯỢT bằng TweenService (server thấy "đi nhanh" chứ không "đột biến vị trí") -> không kéo về.
-- Dùng cho claim seed + mua pet. Opt-in qua config c.UseTweenTeleport. Giữ đường set-CFrame cũ làm fallback.
-- ============================================================
-- Chuyển config tọa độ (Vector3 / {x,y,z} / {X=,Y=,Z=}) -> Vector3. nil nếu không hợp lệ.
local function toVector3(v)
    if typeof(v) == "Vector3" then return v end
    if type(v) == "table" then
        local x = tonumber(v.X or v.x or v[1])
        local y = tonumber(v.Y or v.y or v[2])
        local z = tonumber(v.Z or v.z or v[3])
        if x and y and z then return Vector3.new(x, y, z) end
    end
    return nil
end

Runtime.GetTeleportButtonDest = function(name)
    if name == "Sell" or name == "Seeds" then
        local t = workspace:FindFirstChild("Teleports")
        local part = t and t:FindFirstChild(name)
        return part and part.Position
    elseif name == "Garden" then
        local plotId = LocalPlayer:GetAttribute("PlotId")
        local gardens = workspace:FindFirstChild("Gardens")
        local plot = gardens and plotId and gardens:FindFirstChild("Plot" .. tostring(plotId))
        local sp = plot and plot:FindFirstChild("SpawnPoint")
        return sp and sp.Position
    end
    return nil
end

Runtime.FireTeleportButton = function(name)
    local p = packet({ "TeleportButton", "Request" })
    if not (p and type(p.Fire) == "function") then return false end
    return (pcall(function() p:Fire(name) end))
end

-- ============================================================
-- TELEPORT MUOT (port tu hi.lua, chong giat). Truoc khi claim/mua -> BAM NUT Sell nhay ve TAM map
-- (GoSellCenter) roi tween NGAN. Cac ham tu giu KHOA di chuyen (BeginMovement/EndMovement) suot luc di
-- -> moi task khac TU NHUONG -> khong "keo" nhan vat -> het giat. Log "Teleport" TU TAT khi co
-- c.__MovementOwner (luc claim/mua pet) de khong in rac; teleport khac van log binh thuong.
-- ============================================================
Runtime.GetSellCenterPos = function(c)
    local pos = c and toVector3(c.SellCenterPos)
    return pos or Runtime.GetTeleportButtonDest("Sell")
end

Runtime.GetRouteButtonDest = function(c, name)
    if name == "Sell" then
        return Runtime.GetSellCenterPos(c)
    end
    return Runtime.GetTeleportButtonDest(name)
end

Runtime.GetRouteButtons = function(c)
    local src = type(c) == "table" and type(c.TeleportButtons) == "table" and c.TeleportButtons or nil
    local out = {}
    if src and #src > 0 then
        for _, name in ipairs(src) do
            if name == "Sell" or name == "Garden" then
                out[#out + 1] = name
            end
        end
    end
    if #out == 0 then
        out[1] = "Sell"
        out[2] = "Garden"
    end
    return out
end

Runtime.ReleaseRootForMove = function(root)
    root = root or getRootPart()
    if not root then return false end
    pcall(function()
        root.Anchored = false
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
    return true
end

-- BAM NUT teleport (Sell/Garden) GIONG teleporrrrr.lua: FIRE DUNG 1 LAN roi CHO toi gan nut.
-- KHONG fire lap (fire lap = dang tween thi 1 cu fire toi tre -> server keo ve diem nut -> THUT LUI/back man hinh).
-- KHONG dung velocity/anchor (server coi la teleport dot ngot -> keo ve).
Runtime.GoTeleportButton = function(name, c, reason)
    local quiet = c and c.__MovementOwner ~= nil
    local center = Runtime.GetRouteButtonDest(c, name)
    local root = getRootPart()
    if not center then
        if not quiet then actionLog("Teleport", "BUTTON_FAIL", "missing " .. tostring(name)) end
        return false, nil
    end
    local reachDistance = math.max(tonumber(c and c.TeleportButtonReachDistance) or 25, 1)
    if root and (root.Position - center).Magnitude <= reachDistance then
        return true, center   -- da o gan nut roi -> khoi bam
    end
    local timeout = math.max(tonumber(c and c.TeleportButtonWaitTimeout) or 3, 0.25)
    Runtime.BeginMovement("button " .. tostring(name), timeout + 1, c and c.__MovementOwner)
    Runtime.FireTeleportButton(name)   -- FIRE 1 LAN (giong pressSell) -> server dời mình tới nút HỢP LỆ
    local reached = false
    local untilT = os.clock() + timeout
    while isAlive() and os.clock() < untilT do                 -- waitNearSell: chỉ CHỜ, KHÔNG fire thêm
        local r = getRootPart()
        if r and (r.Position - center).Magnitude <= reachDistance then
            reached = true
            break
        end
        task.wait(0.1)
    end
    waitAlive(tonumber(c and c.TeleportButtonPostWait) or 0.2)   -- settle giống task.wait(0.2) bên teleporrrrr
    Runtime.EndMovement("button " .. tostring(name), tonumber(c and c.MovementLockExtra) or 0.4)
    return reached, center
end

Runtime.GoSellCenter = function(c, reason)
    return Runtime.GoTeleportButton("Sell", c, reason)
end

Runtime.PickRouteButton = function(targetPos, c, targetFromButton)
    local root = getRootPart()
    if not (root and typeof(targetPos) == "Vector3") then
        return nil
    end
    local curDist = (root.Position - targetPos).Magnitude
    local bestName, bestDest, bestDist
    local detail = {}
    for _, name in ipairs(Runtime.GetRouteButtons(c)) do
        local dest = Runtime.GetRouteButtonDest(c, name)
        if dest then
            local buttonTarget = type(targetFromButton) == "function" and targetFromButton(dest) or targetPos
            local d = buttonTarget and (dest - buttonTarget).Magnitude or (dest - targetPos).Magnitude
            detail[#detail + 1] = ("%s=%d"):format(name, math.floor(d))
            if not bestDist or d < bestDist then
                bestName, bestDest, bestDist = name, dest, d
            end
        end
    end
    local save = bestDist and (curDist - bestDist) or 0
    return bestName, bestDest, bestDist, save, table.concat(detail, " ")
end

-- NOCLIP TẠM khi tween (chống nhân vật DÍNH SÀN/địa hình -> kẹt/freeze giữa đường như chồng thấy).
-- Set mọi BasePart của nhân vật CanCollide=false; trả về hàm KHÔI PHỤC lại đúng những part đã đổi.
Runtime.BeginNoclip = function()
    local char = LocalPlayer.Character
    if not char then return function() end end
    local saved = {}
    for _, v in ipairs(char:GetDescendants()) do
        if v:IsA("BasePart") and v.CanCollide then
            saved[#saved + 1] = v
            pcall(function() v.CanCollide = false end)
        end
    end
    return function()
        for _, v in ipairs(saved) do
            if v and v.Parent then pcall(function() v.CanCollide = true end) end
        end
    end
end

-- Tween HRP MUOT GIONG fixtrongcay (ban GOC chay OK): tween thang CFrame, CHO Completed chay HET tu nhien.
-- KHONG dung anchor (anchor lam SERVER khong cap nhat vi tri -> tween toi nhung server tuong con o xa ->
-- CLAIM HUT). KHONG Cancel, chot CFrame cuoi nhe nhang theo huong tween nen server ko keo ve. Chong "bay
-- goc nhin" da co CameraStable (khoa zoom) lo, KHONG can anchor.
Runtime.TweenMoveTo = function(targetPos, faceTarget, speed, owner)
    local root = getRootPart()
    if not (root and typeof(targetPos) == "Vector3") then return false end
    speed = math.max(tonumber(speed) or 35, 5)
    local dist = (root.Position - targetPos).Magnitude
    if dist <= 6 then return true end   -- da toi noi (giong REACH_DISTANCE) -> khoi tween
    local goalCF = (typeof(faceTarget) == "Vector3") and CFrame.lookAt(targetPos, faceTarget) or CFrame.new(targetPos)
    local dur = math.max(dist / speed, 0.05)
    Runtime.BeginMovement("tween", dur + 2, owner)
    local stopNoclip = Runtime.BeginNoclip()   -- NOCLIP suot tween -> ko dinh san/dia hinh -> het ket/freeze
    pcall(function() root.AssemblyLinearVelocity = Vector3.zero end)  -- ZERO van toc truoc -> ko bi keo XEO khi tween
    local tw = TweenService:Create(root, TweenInfo.new(dur, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), { CFrame = goalCF })
    local done = false
    tw.Completed:Once(function() done = true end)
    local ok = pcall(function() tw:Play() end)
    if not ok then
        stopNoclip()
        Runtime.EndMovement("tween fail", 0.2)
        return false
    end
    -- CHO tween chay HET (giong Completed:Wait) - chot an toan theo thoi gian + isAlive, KHONG cat ngang.
    local deadline = os.clock() + dur + 2
    while isAlive() and not done and os.clock() < deadline do task.wait(0.05) end
    -- CHOT DUNG DICH: tween co the bi cat ngang / bi trong luc keo lech -> set CFrame cuoi cho TOI CHUAN
    -- vi tri + zero van toc (khoi troi tiep). Nhe nhang theo huong tween nen server ko keo ve.
    local r2 = getRootPart()
    if r2 then pcall(function() r2.CFrame = goalCF; r2.AssemblyLinearVelocity = Vector3.zero end) end
    stopNoclip()
    Runtime.EndMovement("tween", 0.2)
    return true
end

Runtime.SpamTweenMoveTo = function(targetPos, faceTarget, c, owner)
    local root = getRootPart()
    if not (root and typeof(targetPos) == "Vector3") then return false end

    local reach = math.max(tonumber(c and c.ReachDistance) or 10, 1)
    local step = math.max(tonumber(c and c.SpamTweenStep) or 50, 1)
    local duration = math.max(tonumber(c and c.SpamTweenDuration) or 0.1, 0.02)
    local delay = math.max(tonumber(c and c.SpamTweenDelay) or 0.05, 0)
    local speed = math.max(tonumber(c and c.TweenSpeed) or 35, 5)
    local firstDist = (root.Position - targetPos).Magnitude
    if firstDist <= reach then return true end

    local maxTime = math.max(tonumber(c and c.SpamTweenMaxTime) or (firstDist / speed + 8), 3)
    local deadline = os.clock() + maxTime
    Runtime.BeginMovement("spam tween", maxTime + 1, owner)
    local stopNoclip = Runtime.BeginNoclip()   -- NOCLIP suot tween -> ko dinh san/dia hinh -> het ket/freeze

    while isAlive() and os.clock() < deadline do
        root = getRootPart()
        if not root then break end

        local currentPos = root.Position
        local remaining = (currentPos - targetPos).Magnitude
        if remaining <= reach then
            stopNoclip()
            Runtime.EndMovement("spam tween", 0.2)
            return true
        end

        local delta = targetPos - currentPos
        if delta.Magnitude < 0.001 then
            stopNoclip()
            Runtime.EndMovement("spam tween", 0.2)
            return true
        end

        local stepTarget = currentPos + delta.Unit * math.min(step, remaining)
        local goalCF = (typeof(faceTarget) == "Vector3") and CFrame.lookAt(stepTarget, faceTarget) or CFrame.new(stepTarget)
        local tw = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out), { CFrame = goalCF })
        local done = false
        tw.Completed:Once(function() done = true end)
        local ok = pcall(function() tw:Play() end)
        if not ok then break end

        local stepDeadline = os.clock() + duration + 0.3
        while isAlive() and not done and os.clock() < stepDeadline do
            task.wait(0.02)
        end

        if delay > 0 and not waitAlive(delay) then
            stopNoclip()
            Runtime.EndMovement("spam tween", 0.2)
            return false
        end
    end

    stopNoclip()
    Runtime.EndMovement("spam tween", 0.2)
    root = getRootPart()
    return root and (root.Position - targetPos).Magnitude <= reach
end

-- SMART: xet Sell/Garden, nut nao rut duong tot hon thi bam roi tween not.
Runtime.SmartApproach = function(targetPos, faceTarget, c)
    local root = getRootPart()
    if not (root and typeof(targetPos) == "Vector3") then return false end
    if not (c and c.UseSellFirst == false) then
        local curDist = (root.Position - targetPos).Magnitude
        local minSave = tonumber(c and c.SellFirstMinSave) or 12
        local bestName, _, bestDist, save, detail = Runtime.PickRouteButton(targetPos, c)
        if not (c and c.__MovementOwner) then
            actionLog("Teleport", (bestName and save > minSave) and "BUTTON" or "TWEEN",
                ("cur=%d %s best=%s save=%d"):format(math.floor(curDist), tostring(detail or ""), tostring(bestName or "-"), math.floor(save or 0)))
        end
        if bestName and bestDist and save > minSave then
            Runtime.GoTeleportButton(bestName, c, "shorten")
        end
    end
    if c and c.UseSpamTweenTeleport then
        return Runtime.SpamTweenMoveTo(targetPos, faceTarget, c, c.__MovementOwner)
    end
    return Runtime.TweenMoveTo(targetPos, faceTarget, c and c.TweenSpeed, c and c.__MovementOwner)
end

Runtime.GetNearTargetPos = function(pos, c, fromPos)
    local root = getRootPart()
    local origin = (typeof(fromPos) == "Vector3" and fromPos) or (root and root.Position)
    if not (typeof(pos) == "Vector3" and origin) then
        return nil
    end
    local distance = tonumber(c and c.TeleportDistance) or 4
    local yOffset = tonumber(c and c.TeleportYOffset) or 2
    local delta = origin - pos
    local flat = Vector3.new(delta.X, 0, delta.Z)
    if flat.Magnitude < 0.001 then
        flat = Vector3.new(0, 0, -1)
    end
    return pos + flat.Unit * distance + Vector3.new(0, yOffset, 0)
end

Runtime.SmartApproachNear = function(pos, c)
    local root = getRootPart()
    if not (root and typeof(pos) == "Vector3") then return false end
    local targetPos = Runtime.GetNearTargetPos(pos, c, root.Position)
    if not targetPos then return false end
    if not (c and c.UseSellFirst == false) then
        local curDist = (root.Position - targetPos).Magnitude
        local minSave = tonumber(c and c.SellFirstMinSave) or 12
        local bestName, _, bestDist, save, detail = Runtime.PickRouteButton(targetPos, c, function(dest)
            return Runtime.GetNearTargetPos(pos, c, dest)
        end)
        if not (c and c.__MovementOwner) then
            actionLog("Teleport", (bestName and save > minSave) and "BUTTON" or "TWEEN",
                ("cur=%d %s best=%s save=%d near"):format(math.floor(curDist), tostring(detail or ""), tostring(bestName or "-"), math.floor(save or 0)))
        end
        if bestName and bestDist and save > minSave then
            Runtime.GoTeleportButton(bestName, c, "near target")
            local r = getRootPart()
            targetPos = Runtime.GetNearTargetPos(pos, c, r and r.Position or Runtime.GetRouteButtonDest(c, bestName)) or targetPos
        end
    end
    if c and c.UseSpamTweenTeleport then
        return Runtime.SpamTweenMoveTo(targetPos, pos, c, c.__MovementOwner)
    end
    return Runtime.TweenMoveTo(targetPos, pos, c and c.TweenSpeed, c and c.__MovementOwner)
end

local function teleportNearPosition(pos, c)
    local root = getRootPart()
    if not (root and pos) then
        return false
    end
    -- TWEEN MUOT (chong giat) neu bat; KHONG thi set CFrame nhu cu.
    if c and c.UseTweenTeleport then
        Runtime.SmartApproachNear(pos, c)
        return waitAlive(tonumber(c and c.TeleportWait) or 0.05)
    end
    local targetPos = Runtime.GetNearTargetPos(pos, c, root.Position)
    if not targetPos then return false end
    root.CFrame = CFrame.lookAt(targetPos, pos)
    Runtime.FireTeleporterMimic(root.Position)
    return waitAlive(tonumber(c and c.TeleportWait) or 0.05)
end

local function getStevenRootPart()
    -- Path chuẩn: workspace.NPCS.Steven.HumanoidRootPart (xác nhận Sell_Steven.lua:3-4).
    local npcs = workspace:FindFirstChild("NPCS")
    local steven = npcs and npcs:FindFirstChild("Steven")
    if steven then
        local hrp = steven:FindFirstChild("HumanoidRootPart")
        if hrp then return hrp end
    end
    -- Fallback: 1 số server NPC stream chậm / nằm lồng sâu -> tìm đệ quy theo tên "Steven".
    local found = workspace:FindFirstChild("Steven", true)
    if found then
        if found:IsA("BasePart") then return found end
        local hrp = found:FindFirstChild("HumanoidRootPart")
            or found:FindFirstChild("HumanoidRootPart", true)
        if hrp then return hrp end
    end
    return nil
end

local function teleportToStevenForSell()
    local c = CFG.AutoSell or {}
    if c.TeleportToStevenBeforeSell == false then
        actionLog("AutoSell", "TELEPORT_SKIPPED", "disabled")
        return true
    end

    local root = getRootPart()
    if not root then
        actionLog("AutoSell", "TELEPORT_FAILED", "missing character root")
        return false
    end

    local stevenRoot = getStevenRootPart()
    if not stevenRoot then
        actionLog("AutoSell", "TELEPORT_FAILED", "missing workspace.NPCS.Steven.HumanoidRootPart")
        return false
    end

    local distance = tonumber(c.TeleportDistance) or 5
    root.CFrame = stevenRoot.CFrame * CFrame.new(0, 0, -distance)
    Runtime.FireTeleporterMimic(root.Position)
    actionLog("AutoSell", "TELEPORTED", "to Steven")
    return waitAlive(tonumber(c.TeleportWait) or 0.35)
end

local AntiStealCooldown = {}

local function getGardenZoneData()
    return ReplicatedStorage:FindFirstChild("GardenZoneData")
end

local function isPlayerInMyGarden(player)
    if not player or player == LocalPlayer then
        return false
    end
    local plotId = LocalPlayer:GetAttribute("PlotId")
    if not plotId then
        return false
    end
    local zoneData = getGardenZoneData()
    local value = zoneData and zoneData:FindFirstChild(player.Name)
    if not value then
        return false
    end
    local ok, zoneValue = pcall(function()
        return value.Value
    end)
    return ok and zoneValue == plotId or false
end

local function getPlayersInMyGarden()
    local intruders = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if isPlayerInMyGarden(player) then
            table.insert(intruders, player)
        end
    end
    return intruders
end

local function getPlayerRoot(player)
    local char = player and player.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function getShovelTool()
    local tools = getToolsWithAttribute("Shovel")
    return tools[1]
end

local function teleportToIntruder(player)
    local c = CFG.AntiSteal or {}
    if c.TeleportToIntruder == false then
        return true
    end

    local root = getRootPart()
    local targetRoot = getPlayerRoot(player)
    if not root or not targetRoot then
        actionLog("AntiSteal", "SKIP", "missing root for " .. tostring(player and player.Name))
        return false
    end

    local distance = tonumber(c.TeleportDistance) or 5
    local offsetY = tonumber(c.TeleportYOffset) or 0
    local targetPos = targetRoot.Position
    local direction = targetRoot.CFrame.LookVector
    if direction.Magnitude < 0.001 then
        direction = Vector3.new(0, 0, -1)
    end
    local myPos = targetPos - direction.Unit * distance + Vector3.new(0, offsetY, 0)
    root.CFrame = CFrame.lookAt(myPos, targetPos)
    actionLog("AntiSteal", "TELEPORTED", tostring(player.Name))
    return waitAlive(0.08)
end

local function equipShovelForAntiSteal()
    local c = CFG.AntiSteal or {}
    if c.EquipShovel == false then
        return true
    end
    Runtime.TryToolLock("AntiSteal", 6, true)   -- FORCE: chong trom la viec KHAN -> cuop khoa tool ngay

    local shovel = getShovelTool()
    if not shovel then
        actionLog("AntiSteal", c.RequireShovel == false and "WARN" or "SKIP", "missing shovel tool")
        return c.RequireShovel == false
    end

    if not equipTool(shovel) then
        actionLog("AntiSteal", "SKIP", "cannot equip shovel")
        return false
    end
    return waitAlive(0.05)
end

local function hitIntruderWithShovel(player)
    local c = CFG.AntiSteal or {}
    if not packet({ "Shovel", "HitPlayer" }) then
        actionLog("AntiSteal", "ERROR", "missing Networking.Shovel.HitPlayer")
        c.Enabled = false
        return false
    end

    if not equipShovelForAntiSteal() then
        return false
    end
    if not teleportToIntruder(player) then
        return false
    end

    local hits = math.max(tonumber(c.HitsPerTarget) or 2, 1)
    for i = 1, hits do
        if not isAlive() then
            return false
        end
        if not isPlayerInMyGarden(player) then
            actionLog("AntiSteal", "DONE", tostring(player.Name) .. " left garden")
            return true
        end

        local targetRoot = getPlayerRoot(player)
        local root = getRootPart()
        if root and targetRoot then
            root.CFrame = CFrame.lookAt(root.Position, targetRoot.Position)
        end

        if packet({ "Shovel", "SwingShovel" }) then
            firePacket({ "Shovel", "SwingShovel" })
        end
        local ok = firePacket({ "Shovel", "HitPlayer" }, player.UserId)
        actionLog("AntiSteal", ok and "HIT" or "HIT_FAIL", tostring(player.Name) .. " #" .. tostring(i))
        State.LastAntiSteal = os.date("%H:%M:%S") .. " hit " .. tostring(player.Name)
        if not waitAlive(tonumber(c.BetweenHits) or 0.55) then
            return false
        end
    end
    return true
end

-- ============================================================
-- CÁC TÁC VỤ
-- ============================================================

-- Mua hạt
function Runtime.doAutoBuySeedInner()
    local c = CFG.AutoBuySeed
    if not (c and c.Enabled) then return end
    if Runtime.ShouldYieldForSeedPriority("AutoBuySeed") or Runtime.ShouldYieldForPetPriority("AutoBuySeed") or Runtime.ShouldYieldForTrim("AutoBuySeed") then
        return
    end
    actionLog("AutoBuySeed", "START")
    if not packet({ "SeedShop", "PurchaseSeed" }) then
        logw("AutoBuySeed: thiếu Networking.SeedShop.PurchaseSeed -> tắt.")
        c.Enabled = false
        return
    end

    if type(SeedData) ~= "table" then
        actionLog("AutoBuySeed", "SKIP", "missing SeedData")
        return
    end
    -- Stop Buying Seeds At: tiền hiện tại >= ngưỡng -> ngừng mua hạt (0 = tắt).
    local stopAt = tonumber(c.StopBuyAt) or 0
    if stopAt > 0 and (tonumber(getSheckles()) or 0) >= stopAt then
        actionLog("AutoBuySeed", "SKIP", "money >= StopBuyAt " .. tostring(stopAt))
        return
    end
    local spentThisCycle = 0
    local keep = tonumber(c.KeepSheckles) or 0
    local maxPerSeed = math.max(tonumber(c.MaxPerSeedPerCycle) or 50, 1)
    -- FRESH ACC (chong yeu cau): duoi nguong "Plant switch" cay -> mua KHONG cap OwnLimit (mua HET cho day
    -- vuon, van gioi han boi stock + tien). >= nguong -> theo cap OwnLimit binh thuong.
    local freshBuy = c.FreshAcc == true and (tonumber(c.PlantSwitch) or 0) > 0 and countMyPlants() < (tonumber(c.PlantSwitch) or 0)

    local function availableMoney()
        return math.max((tonumber(getSheckles()) or 0) - spentThisCycle - keep, 0)
    end

    local function buySeed(seedName, data)
        if type(seedName) ~= "string" or seedName == "" then
            return false
        end
        data = data or getSeedDataByName(seedName)
        if not (data and data.RestockShop) then
            actionLog("AutoBuySeed", "SKIP", tostring(seedName) .. " not in RestockShop SeedData")
            return false
        end

        local price = tonumber(data.PurchasePrice)
        if not price then
            actionLog("AutoBuySeed", "SKIP", tostring(seedName) .. " missing PurchasePrice")
            return false
        end

        -- Seeds To Buy LIMIT: đã SỞ HỮU đủ số hạt này thì không mua thêm (chống mua dư cháy túi).
        -- OwnLimitPerSeed[tên] ưu tiên; nếu không có thì dùng OwnLimit (áp chung mọi hạt). 0 = không cap.
        local cap = 0
        if type(c.OwnLimitStrict) == "table" and c.OwnLimitStrict[seedName]
            and type(c.OwnLimitPerSeed) == "table" and tonumber(c.OwnLimitPerSeed[seedName]) then
            -- Seed.Buy.Keep ("mua để GIỮ"): cap riêng THẮNG cả Fresh Acc. Seed này giá cao + không trồng
            -- -> Fresh Acc "mua hết" mà không cap là cháy túi vô ích (chồng chỉ muốn giữ đúng N hạt).
            cap = tonumber(c.OwnLimitPerSeed[seedName])
        elseif freshBuy then
            cap = 0   -- FRESH ACC: bo cap so huu -> mua het (van gioi han boi stock + tien)
        elseif type(c.OwnLimitPerSeed) == "table" and tonumber(c.OwnLimitPerSeed[seedName]) then
            cap = tonumber(c.OwnLimitPerSeed[seedName])
        elseif tonumber(c.OwnLimit) then
            cap = tonumber(c.OwnLimit)
        end
        if cap > 0 then
            local rep = getPlayerReplica()
            local inv = rep and rep.Data and rep.Data.Inventory
            local ownedSeeds = inv and inv.Seeds
            local have = ownedSeeds and tonumber(ownedSeeds[seedName]) or 0
            if have >= cap then
                actionLog("AutoBuySeed", "SKIP", ("%s owned %d >= limit %d"):format(seedName, have, cap))
                return false
            end
        end

        local remaining = getRemainingSeedStock(seedName)
        if not remaining then
            actionLog("AutoBuySeed", "SKIP", tostring(seedName) .. " missing stock")
            return false
        end
        if remaining < 1 then
            actionLog("AutoBuySeed", "SKIP", tostring(seedName) .. " no stock")
            return false
        end

        local money = availableMoney()
        if money < price then
            actionLog("AutoBuySeed", "SKIP", ("%s need=%s have=%s"):format(seedName, tostring(price), tostring(money)))
            return false
        end

        actionLog("AutoBuySeed", "BUY", ("%s rarity=%s price=%s stock=%s money=%s"):format(
            seedName,
            tostring(data.Rarity),
            tostring(price),
            tostring(remaining),
            tostring(money)
        ))
        local ok = firePacket({ "SeedShop", "PurchaseSeed" }, seedName)
        if ok then
            noteSeedPurchase(seedName)
            spentThisCycle = spentThisCycle + price
            State.SeedsBought = (State.SeedsBought or 0) + 1
            State.LastSeedBuy = os.date("%H:%M:%S") .. " " .. seedName .. " $" .. tostring(price)
            return true
        end
        actionLog("AutoBuySeed", "ERROR", "PurchaseSeed failed: " .. tostring(seedName))
        return false
    end

    local mode = string.lower(tostring(c.Mode or "Smart"))
    local bought = 0

    if mode == "list" or mode == "custom" then
        -- Mua MỖI loại trong List tới đủ số (cap riêng OwnLimitPerSeed) trong 1 vòng, không phải 1 con/vòng.
        for _, seedName in ipairs(c.List or {}) do
            local n = 0
            while n < maxPerSeed do
                if not buySeed(seedName) then break end   -- buySeed tự dừng khi đã đủ cap / hết stock / hết tiền
                bought = bought + 1
                n = n + 1
                if not waitAlive(tonumber(c.Delay) or 0.35) then return end
            end
        end

        -- RICH LIST: seed XỊN chỉ mua khi DƯ TIỀN. Điều kiện: tiền hiện tại (đã trừ chi tiêu vòng này) > MinMoney.
        -- Khi mua nhóm này LUÔN chừa Reserve (để dành mua pet) -> nâng keep tạm cho buySeed.availableMoney tự tôn trọng.
        local rich = c.RichList
        if type(rich) == "table" and type(rich.List) == "table" and #rich.List > 0 then
            local moneyNow = (tonumber(getSheckles()) or 0) - spentThisCycle
            local minMoney = tonumber(rich.MinMoney) or 0
            if moneyNow <= minMoney then
                actionLog("AutoBuySeed", "SKIP", ("rich: money %s <= min %s"):format(tostring(moneyNow), tostring(minMoney)))
            else
                keep = math.max(keep, tonumber(rich.Reserve) or 0)   -- chừa Reserve (mua pet) -> không tiêu xuống dưới mức này
                actionLog("AutoBuySeed", "RICH", ("money=%s min=%s reserve=%s"):format(tostring(moneyNow), tostring(minMoney), tostring(keep)))
                for _, seedName in ipairs(rich.List) do
                    local n = 0
                    while n < maxPerSeed do
                        if not buySeed(seedName) then break end   -- buySeed tự dừng khi đủ cap / hết stock / chạm Reserve
                        bought = bought + 1
                        n = n + 1
                        if not waitAlive(tonumber(c.Delay) or 0.35) then return end
                    end
                end
            end
        end

        actionLog("AutoBuySeed", "DONE", "bought=" .. tostring(bought))
        return
    end

    local candidates, reason = buildSeedCandidates(c)
    if #candidates == 0 then
        actionLog("AutoBuySeed", "SKIP", tostring(reason or ("no affordable stocked seeds; money=" .. tostring(getSheckles()))))
        return
    end

    actionLog("AutoBuySeed", "PLAN", ("candidates=%s money=%s keep=%s minRarity=%s"):format(
        tostring(#candidates),
        tostring(getSheckles()),
        tostring(keep),
        tostring(c.MinRarity or "Common")
    ))

    for _, seed in ipairs(candidates) do
        local boughtThisSeed = 0
        while boughtThisSeed < maxPerSeed do
            local remaining = getRemainingSeedStock(seed.Name)
            if not remaining or remaining < 1 then
                break
            end
            if availableMoney() < seed.Price then
                break
            end
            local data = getSeedDataByName(seed.Name)
            if not buySeed(seed.Name, data) then
                break
            end
            bought = bought + 1
            boughtThisSeed = boughtThisSeed + 1
            if not waitAlive(tonumber(c.Delay) or 0.35) then return end
        end
    end

    actionLog("AutoBuySeed", "DONE", "bought=" .. tostring(bought))
end

-- BUSY-GUARD mua hạt: instant-restock + loopTask cùng gọi -> 2 luồng mua chạy đè nhau là
-- double-spend (spentThisCycle/assumed-stock mỗi luồng đếm riêng). Chỉ cho 1 lượt chạy 1 lúc.
function Runtime.doAutoBuySeed()
    if State.BuySeedBusy then return end
    State.BuySeedBusy = true
    local ok, err = pcall(Runtime.doAutoBuySeedInner)
    State.BuySeedBusy = false
    if not ok then error(err, 0) end   -- ném lại cho loopTask log/đếm Errors như cũ
end

-- INSTANT RESTOCK BUY (chồng: "sợ quét xong mua không kịp"): server restock -> Items[seed].Value
-- đổi -> mua NGAY, không chờ vòng loop. Signal này chính GUI shop game cũng watch
-- (PremiumSeedShop GenerateItems.lua:358 GetPropertyChangedSignal("Value") - source xác nhận).
-- Value CHỈ đổi lúc restock (stock = suất cá nhân: Value - PurchasedThisRestock, người khác mua
-- không ảnh hưởng, mình mua cũng không đổi Value) -> không tự kích hoạt lặp.
Runtime.KickBuySeed = function(reason)
    if State.BuySeedKickPending then return end
    State.BuySeedKickPending = true
    task.spawn(function()
        -- debounce: restock đổi hàng loạt Value gần như cùng lúc -> gom về 1 lượt mua
        if not waitAlive(1) then State.BuySeedKickPending = false return end
        local tries = 0
        while State.BuySeedBusy and tries < 20 and Runtime.Active do
            if not waitAlive(0.5) then break end
            tries = tries + 1
        end
        State.BuySeedKickPending = false
        if Runtime.Active then
            actionLog("AutoBuySeed", "RESTOCK", tostring(reason or "stock changed"))
            pcall(Runtime.doAutoBuySeed)
        end
    end)
end

function Runtime.SetupInstantRestockBuy()
    if CFG.InstantRestockBuy == false then return end
    if not (CFG.AutoBuySeed and CFG.AutoBuySeed.Enabled) then return end
    task.spawn(function()
        local items = nil
        local waited = 0
        while Runtime.Active and waited < 30 do
            local shop = getSeedShop()
            items = shop and shop:FindFirstChild("Items")
            if items then break end
            if not waitAlive(1) then return end
            waited = waited + 1
        end
        if not items then
            logw("InstantRestockBuy: khong thay StockValues.SeedShop.Items -> chi mua theo vong loop.")
            return
        end
        local conns = {}
        local function watch(child)
            conns[#conns + 1] = child:GetPropertyChangedSignal("Value"):Connect(function()
                if (tonumber(child.Value) or 0) > 0 then
                    Runtime.KickBuySeed(child.Name)
                end
            end)
        end
        for _, ch in ipairs(items:GetChildren()) do
            watch(ch)
        end
        conns[#conns + 1] = items.ChildAdded:Connect(function(ch)
            watch(ch)
            Runtime.KickBuySeed(ch.Name)
        end)
        table.insert(Runtime.Cleanups, function()
            for _, cn in ipairs(conns) do
                pcall(function() cn:Disconnect() end)
            end
        end)
        actionLog("AutoBuySeed", "WATCH", "instant restock detect ON")
    end)
end

-- Trồng mọi hạt trong túi
-- Cờ "vườn đầy" theo TÍN HIỆU THẬT của game (server bắn Notification "can't plant more").
-- PlotFullWatcher set; AutoPlant ngừng trồng; AutoShovelReplace đào xong xoá cờ để trồng lại.
Runtime.PlotFullAt = 0
function Runtime.MarkPlotFull()
    Runtime.PlotFullAt = os.clock()
end
function Runtime.ClearPlotFull()
    Runtime.PlotFullAt = 0
end
function Runtime.IsPlotFullSignal()
    local win = tonumber(CFG.AutoShovelReplace and CFG.AutoShovelReplace.PlotFullSignalWindow) or 30
    return (os.clock() - (tonumber(Runtime.PlotFullAt) or 0)) < win
end

local function shouldPausePlantForTrimLimit()
    local trim = CFG.TrimToQuota
    if not (trim and trim.Enabled) then return false end
    local plantTotal = countMyPlants()
    if plantTotal <= 0 then return false end

    local totalPlots = Runtime.GetTotalPlots and Runtime.GetTotalPlots() or (tonumber(CFG.TotalPlots) or 0)
    local limit = Runtime.ResolvePlotCount and Runtime.ResolvePlotCount(trim.Limit, totalPlots) or tonumber(trim.Limit)
    if limit and limit > 0 and plantTotal >= limit then
        unequipSeedTool("AutoPlant")
        actionLog("AutoPlant", "SKIP", ("trim limit %d/%d"):format(plantTotal, limit))
        return true
    end
    return false
end

-- ============================================================
-- GATE BOOT/DATA (chong yeu cau): fps boost chay TRUOC, va TRONG CAY/TRIM chi chay khi DA NHAN
-- data vuon (remote Garden.SyncAllGardens -> Runtime.GardenDataReady). Tranh trong vuot quota luc
-- data chua ve, va tranh chay task nang truoc khi fps boost ap dung.
-- ============================================================
Runtime.FpsBootDone = Runtime.FpsBootDone == true
Runtime.GardenDataReady = Runtime.GardenDataReady == true
Runtime.IsGardenDataReady = function()
    if Runtime.GardenDataReady == true then return true end
    -- Tracker da THU setup nhung THIEU remote Garden.* -> khong bao gio co data -> KHONG gate (tranh ket vinh vien).
    if Runtime.GardenTrackerTried == true and Runtime.GardenTrackerReady ~= true then return true end
    -- Het thoi gian an toan tinh tu luc fps boost xong -> cho chay (fallback, phong remote ban data cham).
    local since = tonumber(Runtime.FpsBootDoneAt)
    if since and (os.clock() - since) > (tonumber(CFG.GardenDataMaxWait) or 25) then return true end
    return false
end
-- Farm task NANG (trong cay / trim): doi fps boost xong + data vuon san sang. true = DUOC phep chay.
Runtime.FarmGateReady = function(taskName)
    if Runtime.FpsBootDone ~= true then
        actionLog(taskName or "Farm", "WAIT", "fps boost chua xong")
        return false
    end
    if not Runtime.IsGardenDataReady() then
        actionLog(taskName or "Farm", "WAIT", "cho data vuon (SyncAllGardens)")
        return false
    end
    return true
end

function Runtime.doAutoPlant()
    local c = CFG.AutoPlant
    if not (c and c.Enabled) then return end
    if not Runtime.FarmGateReady("AutoPlant") then return end   -- fps boost xong + data vuon ve roi moi trong
    if Runtime.ShouldYieldForSeedPriority("AutoPlant") or Runtime.ShouldYieldForPetPriority("AutoPlant") then
        return
    end
    if Runtime.ShouldYieldForTrim("AutoPlant") then
        unequipSeedTool("AutoPlant")
        return
    end
    actionLog("AutoPlant", "START")
    if not packet({ "Plant", "PlantSeed" }) then
        logw("AutoPlant: thiếu Networking.Plant.PlantSeed -> tắt.")
        c.Enabled = false
        return
    end
    if not getPlot() then
        actionLog("AutoPlant", "SKIP", "missing plot")
        return
    end

    -- Vườn ĐẦY (game báo "can't plant more") -> ngừng trồng để khỏi spam remote + spam thông báo.
    -- Bật AutoShovelReplace thì nó sẽ đào cây dỏm rồi xoá cờ -> vòng sau trồng tiếp.
    if shouldPausePlantForTrimLimit() then
        return
    end

    if c.PauseWhenPlotFull ~= false and Runtime.IsPlotFullSignal() then
        unequipSeedTool("AutoPlant")
        actionLog("AutoPlant", "SKIP", "plot full (game: can't plant more)")
        return
    end

    local seeds = getToolsWithAttribute("SeedTool")
    if #seeds == 0 then
        actionLog("AutoPlant", "SKIP", "no seed tools")
        return
    end

    -- FRESH ACC (chong yeu cau): duoi nguong "Plant switch" cay -> trong HET (bo qua quota + OnlyQuota),
    -- VAN ton trong KeepSeeds/Lock + OnlyPlant (da check o vong duoi). >= nguong -> quota binh thuong.
    local plantSwitch = tonumber(c.PlantSwitch) or 0
    local myPlantsNow = countMyPlants()   -- dem 1 lan, dung lai cho freshFill + single-fill allowance
    local freshFill = c.FreshAcc == true and plantSwitch > 0 and myPlantsNow < plantSwitch

    -- TRỒNG TỐI ƯU theo lưới đều: build LAZY (chỉ khi THẬT SỰ có cây cần trồng) để KHÔNG tốn CPU
    -- khi quota đã đầy (tránh đơ/crash lúc treo nhiều tab máy yếu). Build 1 lần rồi dùng dần.
    local gridPositions, gridIndex

    -- LỘ TRÌNH TRỒNG: đếm số cây ĐANG trồng mỗi loại (attribute SeedName của model trong plot.Plants,
    -- xác nhận kaitun.lua:4296) để không trồng quá quota mỗi loại.
    local useQuota = c.UsePlantQuota ~= false and type(c.PlantQuota) == "table"
    local plantedCounts = {}
    if useQuota then
        local plot = getPlot()
        local plantsFolder = plot and plot:FindFirstChild("Plants")
        if plantsFolder then
            for _, m in ipairs(plantsFolder:GetChildren()) do
                if m:IsA("Model") then
                    local sName = m:GetAttribute("SeedName")
                    if type(sName) == "string" and sName ~= "" then
                        plantedCounts[sName] = (plantedCounts[sName] or 0) + 1
                    end
                end
            end
        end
    end
    local plantedThisRun = {}
    local plantedTotalRun = 0   -- tong da trong trong VONG NAY (moi loai) - tru vao slot trong cua single-fill
    local plantedAny = false

    -- Seed.Place "Select": CHỈ trồng hạt có tên trong OnlyPlant. Rỗng = trồng tất cả (trừ KeepSeeds).
    local onlyPlant = nil
    if type(c.OnlyPlant) == "table" and next(c.OnlyPlant) ~= nil then
        onlyPlant = {}
        addConfiguredNames(onlyPlant, c.OnlyPlant)
    end

    for _, tool in ipairs(seeds) do
        local seedName = tool:GetAttribute("SeedTool")
        -- RAINBOW SEED luôn trồng (chồng): bỏ qua keep + Select + OnlyQuota. Rainbow ra cây rainbow quý nhất.
        local plantRainbow = c.PlantRainbowSeeds ~= false and isRainbowSeedTool(tool)
        -- KeepCropsForSell (doi 2026): KHONG con GIU SEED -> cay trong list TRONG BINH THUONG (theo
        -- quota/lock/select nhu moi cay). Viec "giu de ban khi x4" chuyen sang khau HAI (ShouldHoldCropHarvest).
        if Runtime.ShouldKeepSeed(seedName, tool) and not plantRainbow then
            actionLog("AutoPlant", "SKIP", "keep seed " .. tostring(seedName or tool.Name))
            State.LastValuable = os.date("%H:%M:%S") .. " keep seed " .. tostring(seedName or tool.Name)
        elseif onlyPlant and not nameMatchesConfiguredSet(seedName, onlyPlant) and not plantRainbow then
            actionLog("AutoPlant", "SKIP", "not in Select " .. tostring(seedName or tool.Name))
        else
            if plantRainbow then
                actionLog("AutoPlant", "RAINBOW", "trong rainbow seed " .. tostring(seedName or tool.Name))
            end
            -- Quota cho loại này (chỉ giới hạn khi seedName có trong bảng PlantQuota).
            local maxTry = tonumber(c.PlantPerSeed) or 50
            -- FIX BUG "set 0 van trong carrot": cay TRONG-1-LAN (IsSingleHarvest: Carrot/Tulip/Bamboo/
            -- Mushroom) truoc day LUON bo qua quota+OnlyQuota -> set 0 vo dung. Gio QUOTA THANG mac dinh;
            -- chi con bypass khi chong bat AutoPlant.SinglePlantIgnoreQuota=true (kieu cu).
            -- FRESH ACC (freshFill) van bo cap nhu cu (dung nghia mode do).
            local isSingle = type(seedName) == "string" and Runtime.IsSingleHarvestSeed(seedName)
            local singleBypass = isSingle and c.SinglePlantIgnoreQuota == true   -- kieu cu: bo qua het
            local explicitQuota = (useQuota and type(seedName) == "string")
                and tonumber(c.PlantQuota[seedName]) or nil
            -- SINGLE-FILL (chong: "seed 1-lan ton dong khong tuot"): seed 1-lan quota DUONG + trong list
            -- MUA -> trong LAP KIN cho trong thay vi dung o quota so (3 cay/luot tieu thu cham hon mua
            -- ca tram lan). Quota 0 = CAM (giu fix cu); KHONG khai (vd Carrot) = KHONG trong (y chong).
            local singleFill = isSingle and not singleBypass and not freshFill
                and c.SinglesFillFreeSlots ~= false
                and explicitQuota ~= 0
                and Runtime.IsSingleFillSeed(seedName, explicitQuota)
            if useQuota and type(seedName) == "string" and not freshFill
                and not singleBypass and not singleFill and not plantRainbow then
                local quota = explicitQuota
                if quota then
                    local already = (plantedCounts[seedName] or 0) + (plantedThisRun[seedName] or 0)
                    local allowed = quota - already
                    if allowed <= 0 then
                        actionLog("AutoPlant", "SKIP", ("quota %s %d/%d"):format(tostring(seedName), already, quota))
                        maxTry = 0
                    else
                        maxTry = math.min(maxTry, allowed)
                    end
                elseif c.OnlyQuota then
                    -- OnlyQuota: cây KHÔNG nằm trong PlantQuota -> KHÔNG trồng (để dành slot cho cây trong list).
                    actionLog("AutoPlant", "SKIP", "ngoai PlanQuota " .. tostring(seedName))
                    maxTry = 0
                end
            end
            -- single-fill: cap theo SO SLOT TRONG con lai (TotalPlots - cay dang co - da trong vong nay
            -- - Reserve). Khong biet TotalPlots -> khong cap (server tu chan bang "can't plant more").
            if singleFill and maxTry > 0 then
                local totalPlots = Runtime.GetTotalPlots and Runtime.GetTotalPlots() or tonumber(CFG.TotalPlots)
                if type(totalPlots) == "number" and totalPlots > 0 then
                    local reserve = math.max(tonumber(c.SingleFillReserve) or 0, 0)
                    local free = totalPlots - reserve - myPlantsNow - plantedTotalRun
                    if free <= 0 then
                        actionLog("AutoPlant", "SKIP",
                            ("single-fill %s: het slot (%d/%d)"):format(tostring(seedName), myPlantsNow + plantedTotalRun, totalPlots))
                        maxTry = 0
                    else
                        maxTry = math.min(maxTry, free)
                    end
                end
            end

            if maxTry > 0 then
                -- KHOA TOOL: task khac dang cam tool (tuoi/sprinkler/xeng...) -> nhuong luot, vong sau trong tiep
                if not Runtime.TryToolLock("AutoPlant", 4) then
                    actionLog("AutoPlant", "SKIP", "tool busy " .. tostring(Runtime.ToolLockBy))
                    return
                end
                if not equipTool(tool) then break end
                -- LAZY build lưới: chỉ build LẦN ĐẦU khi thật sự có cây cần trồng (ko build khi quota đầy).
                if c.PlantGridMode ~= false and not gridPositions then
                    gridPositions = buildGridPlantPositions(c.PlantSpacing, c.GridMargin)
                    gridIndex = 0
                    actionLog("AutoPlant", "GRID", ("points=%d sp=%s"):format(#gridPositions, tostring(c.PlantSpacing or 2)))
                end
                actionLog("AutoPlant", "TOOL", tostring(tool.Name), "seed=" .. tostring(seedName))
                for _ = 1, maxTry do
                    -- tool có thể bị huỷ khi hết hạt
                    if not (tool and tool.Parent) then break end
                    -- Lưới đều (tối ưu): lấy điểm kế tiếp; hết điểm -> fallback random như cũ.
                    local pos
                    if gridPositions then
                        gridIndex = gridIndex + 1
                        pos = gridPositions[gridIndex] or randomPlantPosition()
                    else
                        pos = randomPlantPosition()
                    end
                    if not pos then break end
                    firePacket({ "Plant", "PlantSeed" }, pos, seedName, tool)
                    Runtime.ExtendToolLock("AutoPlant", 3)   -- con dang trong -> giu khoa tool
                    plantedAny = true
                    plantedTotalRun = plantedTotalRun + 1
                    if type(seedName) == "string" then
                        plantedThisRun[seedName] = (plantedThisRun[seedName] or 0) + 1
                    end
                    if not waitAlive(c.Delay or 0.25) then return end
                end
            end
        end
    end
    if not plantedAny then
        unequipSeedTool("AutoPlant")
    end
    Runtime.ReleaseToolLock("AutoPlant")
    actionLog("AutoPlant", "DONE")
end

-- Điểm "xịn" của 1 hạt/cây theo SeedName: lấy giá mua thật trong SeedData.
-- Không có giá thì fallback theo bậc Rarity. Không có gì -> 0.
function Runtime.SeedValueScore(seedName)
    if type(seedName) ~= "string" or seedName == "" then
        return 0
    end
    local data = getSeedDataByName(seedName)
    if not data then
        return 0
    end
    local price = tonumber(data.PurchasePrice)
    if price then
        return price
    end
    local rarity = tostring(data.Rarity or "Common")
    return (RarityScore[rarity] or 0) * 1000
end

-- Vườn đầy mà có hạt xịn hơn cây dỏm -> đào cây dỏm bằng Shovel (UseShovel),
-- để vòng AutoPlant kế tiếp trồng cây xịn vào chỗ trống. KHÔNG đào cây Gold/Rainbow.
function Runtime.doAutoShovelReplace()
    local c = CFG.AutoShovelReplace
    if not (c and c.Enabled) then return end
    if State.AntiStealEngaging or State.SellInProgress then return end
    if Runtime.ShouldYieldForSeedPriority("AutoShovelReplace")
        or Runtime.ShouldYieldForPetPriority("AutoShovelReplace")
        or Runtime.ShouldYieldForTrim("AutoShovelReplace") then
        return
    end

    -- remote thật để đào cây (ShovelController dòng 465/487)
    if not packet({ "Shovel", "UseShovel" }) then
        logw("AutoShovelReplace: thiếu Networking.Shovel.UseShovel -> tắt.")
        c.Enabled = false
        return
    end

    local plot = getPlot()
    if not plot then
        actionLog("AutoShovelReplace", "SKIP", "missing plot")
        return
    end
    local plantsFolder = plot:FindFirstChild("Plants")
    if not plantsFolder then
        actionLog("AutoShovelReplace", "SKIP", "missing Plants folder")
        return
    end

    -- mỗi child trong Plants là 1 cây đã trồng (PlantVisualizerController)
    local plantModels = {}
    for _, m in ipairs(plantsFolder:GetChildren()) do
        if m:IsA("Model") then
            table.insert(plantModels, m)
        end
    end
    local plantCount = #plantModels

    -- LIMIT TREE mode: chạm Limit (PlotFullCount) cây -> đào cây TIER THẤP NHẤT xuống DestroyUntil,
    -- KHÔNG cần hạt xịn trong túi (chỉ dọn bớt cho nhẹ + chừa cây xịn). Chỉ scan nặng khi đã chạm Limit.
    local destroyUntil = tonumber(c.DestroyUntil)
    local limitTarget = tonumber(c.PlotFullCount) or 0
    local limitMode = destroyUntil ~= nil and limitTarget > 0 and plantCount >= limitTarget and plantCount > destroyUntil

    -- Xác định "vườn đầy". Client source KHÔNG có hằng số max cây nên dùng 2 nguồn:
    --   (1) TÍN HIỆU THẬT game: server bắn "can't plant more" -> Runtime.IsPlotFullSignal()
    --   (2) ngưỡng tay PlotFullCount (>0). PlotFullCount=0 => chỉ dựa vào tín hiệu game.
    if c.OnlyWhenPlotFull ~= false and not limitMode then
        local threshold = tonumber(c.PlotFullCount) or 0
        local fullByCount = threshold > 0 and plantCount >= threshold
        local fullBySignal = Runtime.IsPlotFullSignal()
        if not (fullByCount or fullBySignal) then
            if threshold > 0 then
                actionLog("AutoShovelReplace", "SKIP", "not full " .. tostring(plantCount) .. "/" .. tostring(threshold))
            else
                actionLog("AutoShovelReplace", "SKIP", "cho tin hieu 'can't plant more'")
            end
            return
        end
    end

    -- hạt xịn nhất trong túi mà AutoPlant sẽ trồng (bỏ qua rainbow seed nếu đang giữ)
    local bestSeedScore, bestSeedName = -1, nil
    for _, tool in ipairs(getToolsWithAttribute("SeedTool")) do
        local seedName = tool:GetAttribute("SeedTool")
        if not Runtime.ShouldKeepSeed(seedName, tool) then
            local score = Runtime.SeedValueScore(seedName)
            if score > bestSeedScore then
                bestSeedScore = score
                bestSeedName = seedName
            end
        end
    end
    -- Replace mode cần hạt xịn để trồng vào; Limit mode chỉ dọn bớt nên không cần.
    if not bestSeedName and not limitMode then
        actionLog("AutoShovelReplace", "SKIP", "no seed to plant")
        return
    end

    -- tập mutation cần GIỮ (không đào)
    local keepMut = {}
    for _, name in ipairs(c.KeepMutations or {}) do
        keepMut[tostring(name)] = true
    end

    -- SAFE PLANT: chừa lại tối thiểu mỗi loại khi đào. [tên]=N -> luôn để lại >= N cây.
    -- N = 0 -> GIỮ TOÀN BỘ (không đào loại đó). Loại không có trong bảng -> đào tự do.
    local safe = {}
    for k, v in pairs(c.SafePlants or {}) do
        if type(k) == "string" then safe[k] = tonumber(v) or 0 end
    end
    local dugSpecies = {}  -- đếm số cây mỗi loại đã đào trong vòng này

    -- tìm các cây dỏm nhất (đủ điều kiện đào), bỏ cây Gold/Rainbow.
    -- đồng thời đếm TỔNG số cây mỗi loại đang trồng (để biết còn được đào bao nhiêu).
    local speciesCount = {}
    local diggable = {}
    for _, plant in ipairs(plantModels) do
        local sName = plant:GetAttribute("SeedName")
        if type(sName) == "string" and sName ~= "" then
            speciesCount[sName] = (speciesCount[sName] or 0) + 1
        end
        local mut = plant:GetAttribute("Mutation")
        -- SINGLE-FILL: cay 1-lan dang xoay vong (AutoPlant chu dong trong lap kin) -> KHONG dao.
        -- Dao = phi seed vua trong (no sap tu bien mat sau hai); dao xong AutoPlant lai fill single
        -- khac vao dung cho do = vong lap dao-trong vo nghia, ton remote + ton seed.
        local fillSingle = type(sName) == "string"
            and CFG.AutoPlant ~= nil
            and CFG.AutoPlant.SinglesFillFreeSlots ~= false
            and Runtime.IsSingleHarvestSeed(sName)
            and Runtime.IsSingleFillSeed(sName,
                type(CFG.AutoPlant.PlantQuota) == "table" and tonumber(CFG.AutoPlant.PlantQuota[sName]) or nil)
        -- KEEP CROP WEATHER: cay dang giu cho weather mutation -> KHONG dao (giong TrimToQuota).
        if not (type(mut) == "string" and keepMut[mut]) and not fillSingle
            and not Runtime.IsManagedHoldCrop(sName) then
            table.insert(diggable, {
                Plant = plant,
                Name = plant.Name,
                Score = Runtime.SeedValueScore(sName),
                SeedName = sName,
            })
        end
    end
    if #diggable == 0 then
        actionLog("AutoShovelReplace", "SKIP", "no diggable plant (all kept)")
        return
    end
    table.sort(diggable, function(a, b) return a.Score < b.Score end)

    local minGain = tonumber(c.MinScoreGain) or 1.0
    local shovel = getShovelTool()
    if not shovel then
        actionLog("AutoShovelReplace", "SKIP", "missing shovel tool")
        return
    end
    local shovelAttr = shovel:GetAttribute("Shovel")
    -- KHOA TOOL: task khac dang cam tool -> nhuong luot nay
    if not Runtime.TryToolLock("AutoShovelReplace", 5) then
        actionLog("AutoShovelReplace", "SKIP", "tool busy " .. tostring(Runtime.ToolLockBy))
        return
    end

    -- Limit mode: đào tới khi còn DestroyUntil cây (plantCount - DestroyUntil con). Replace mode: 1 cây/vòng.
    local maxReplace
    if limitMode then
        maxReplace = math.max(plantCount - destroyUntil, 0)
    else
        maxReplace = math.max(tonumber(c.MaxReplacePerCycle) or 1, 1)
    end
    local dug = 0
    for _, entry in ipairs(diggable) do
        if dug >= maxReplace then break end
        -- Replace mode: chỉ đào nếu hạt mới xịn hơn cây dỏm (MinScoreGain). Limit mode: đào để dọn,
        -- không cần hạt xịn -> bỏ qua điều kiện này.
        if not limitMode and bestSeedScore <= entry.Score * minGain then
            break -- danh sách đã sort tăng dần -> các cây sau còn xịn hơn
        end

        -- SAFE PLANT: kiểm tra còn được đào loại này không (giữ tối thiểu).
        local canDig = true
        local keep = entry.SeedName and safe[entry.SeedName]
        if keep ~= nil then
            local remain = (speciesCount[entry.SeedName] or 0) - (dugSpecies[entry.SeedName] or 0)
            if keep <= 0 or remain <= keep then
                canDig = false  -- 0 = giữ toàn bộ; hoặc đào nữa là dưới mức chừa
                actionLog("AutoShovelReplace", "SAFE", ("keep %s (con %d, chua %d)"):format(
                    tostring(entry.SeedName), remain, keep <= 0 and remain or keep))
            end
        end

        if canDig and entry.Plant and entry.Plant.Parent then
            if not equipTool(shovel) then
                actionLog("AutoShovelReplace", "SKIP", "cannot equip shovel")
                return
            end
            -- fruitId = "" -> đào cả cây (ShovelController truyền u99 = fruitId or "")
            local ok = firePacket({ "Shovel", "UseShovel" }, entry.Name, "", shovelAttr, shovel)
            Runtime.ExtendToolLock("AutoShovelReplace", 3)
            dug = dug + 1
            if entry.SeedName then
                dugSpecies[entry.SeedName] = (dugSpecies[entry.SeedName] or 0) + 1
            end
            local target = limitMode and ("limit->" .. tostring(destroyUntil)) or tostring(bestSeedName)
            State.LastShovelReplace = os.date("%H:%M:%S")
                .. (" dig %s($%s)->%s"):format(
                    tostring(entry.SeedName or "?"), tostring(math.floor(entry.Score)), target)
            actionLog("AutoShovelReplace", ok and "DONE" or "ERROR",
                ("dig %s -> %s"):format(tostring(entry.SeedName or "?"), target))
            if not waitAlive(0.3) then return end
        end
    end

    Runtime.ReleaseToolLock("AutoShovelReplace")
    if dug > 0 then
        -- Đã đào -> còn chỗ trống, xoá cờ đầy để AutoPlant trồng cây xịn vào ngay vòng sau.
        Runtime.ClearPlotFull()
    else
        actionLog("AutoShovelReplace", "SKIP", limitMode and "all remaining safe" or "seed not better than weakest plant")
    end
end

-- ============================================================
-- TỔNG PLOTS + parse "%" (mục 1). Source client KHÔNG có hằng số max cây thật -> dùng:
--   CFG.TotalPlots (chồng set) HOẶC số part PlantArea (tag PlantArea, raycast trồng).
-- ============================================================
Runtime.GetTotalPlots = function()
    local n = tonumber(CFG.TotalPlots) or 0
    if n > 0 then return n end
    return #getPlantAreaParts()
end
-- "X%" -> làm tròn X% * totalPlots ; số -> số ; khác -> nil. Resolve lúc RUNTIME (plot đã load).
Runtime.ResolvePlotCount = function(value, totalPlots)
    if type(value) == "string" then
        local pct = value:match("^%s*([%d%.]+)%s*%%%s*$")
        if pct then
            totalPlots = totalPlots or Runtime.GetTotalPlots()
            if totalPlots and totalPlots > 0 then
                return math.floor((tonumber(pct) / 100) * totalPlots + 0.5)
            end
            return nil
        end
    end
    return tonumber(value)
end

-- ============================================================
-- TRIM TO QUOTA (mục 6): loại nào ĐANG trồng VƯỢT PlanQuota -> đào DƯ cho về đúng quota.
-- KHÔNG xoá hết plot. Gate tuỳ chọn bằng Limit/DestroyUntil (số HOẶC "%", tính theo TotalPlots):
--   - Limit: chỉ bắt đầu cleanup khi tổng cây >= Limit (0/nil = trim liên tục).
--   - DestroyUntil: dừng cleanup khi tổng cây <= DestroyUntil.
-- Quota: CFG.PlanQuota -> TrimToQuota.Quota -> AutoPlant.PlantQuota. KHÔNG đào cây Gold/Rainbow.
-- Remote thật: Shovel.UseShovel (giống AutoShovelReplace).
-- ============================================================
function Runtime.doTrimToQuota()
    local c = CFG.TrimToQuota
    if not (c and c.Enabled) then return end
    if not Runtime.FarmGateReady("TrimToQuota") then return end   -- fps boost xong + data vuon ve roi moi trim
    if State.AntiStealEngaging or State.SellInProgress then return end
    if Runtime.ShouldYieldForSeedPriority and Runtime.ShouldYieldForSeedPriority("TrimToQuota") then return end
    if not packet({ "Shovel", "UseShovel" }) then
        logw("TrimToQuota: thieu Networking.Shovel.UseShovel -> tat.")
        c.Enabled = false
        return
    end

    local quota = (type(CFG.PlanQuota) == "table" and next(CFG.PlanQuota) and CFG.PlanQuota)
        or (type(c.Quota) == "table" and next(c.Quota) and c.Quota)
        or (CFG.AutoPlant and type(CFG.AutoPlant.PlantQuota) == "table" and CFG.AutoPlant.PlantQuota)
    if not (quota and next(quota)) then
        actionLog("TrimToQuota", "SKIP", "khong co PlanQuota")
        return
    end

    local plot = getPlot()
    local plantsFolder = plot and plot:FindFirstChild("Plants")
    if not plantsFolder then
        actionLog("TrimToQuota", "SKIP", "missing Plants folder")
        return
    end

    -- mutation cần GIỮ (không bao giờ đào)
    local keepMut = {}
    local kmList = (type(c.KeepMutations) == "table" and c.KeepMutations)
        or (CFG.AutoShovelReplace and CFG.AutoShovelReplace.KeepMutations)
        or { "Gold", "Rainbow" }
    for _, name in ipairs(kmList) do keepMut[tostring(name)] = true end

    -- Gia tri 1 cay de XEP HANG khi BUOC PHAI dao dot bien (dot bien gia thap dao truoc). Dung cong thuc ban
    -- that FruitValueCalc(SeedName, SizeMulti, Mutation, player, DecayAlpha) neu module da load; thieu -> fallback
    -- SeedValueScore + bonus co/khong mutation. Chi de SO SANH tuong doi (khong can dung tuyet doi).
    local function plantValue(m)
        local sName = m:GetAttribute("SeedName")
        local mut = m:GetAttribute("Mutation")
        if type(Runtime.FruitValueCalc) == "function" and type(sName) == "string" then
            local sizeMult = tonumber(m:GetAttribute("SizeMulti")) or tonumber(m:GetAttribute("SizeMultiplier")) or 1
            local decay = tonumber(m:GetAttribute("DecayAlpha"))
            local ok, v = pcall(Runtime.FruitValueCalc, sName, sizeMult, mut, LocalPlayer, decay)
            if ok and type(v) == "number" then return v end
        end
        local base = (Runtime.SeedValueScore and Runtime.SeedValueScore(sName)) or 0
        return base + ((type(mut) == "string" and mut ~= "") and 1e6 or 0)  -- co mutation -> gia tri cao hon -> dao SAU
    end

    -- đếm tổng + theo loại + gom MỌI cây kèm cờ (có mutation / có phải mutation GIỮ = Gold/Rainbow).
    -- KHÔNG loại sẵn cây mutation: việc giữ/đào quyết định ở vòng đào theo 3 luật của chồng.
    local plantTotal, bySpecies = 0, {}
    for _, m in ipairs(plantsFolder:GetChildren()) do
        if m:IsA("Model") then
            local sName = m:GetAttribute("SeedName")
            if type(sName) == "string" and sName ~= "" then
                plantTotal = plantTotal + 1
                local b = bySpecies[sName]
                if not b then b = { count = 0, plants = {} }; bySpecies[sName] = b end
                b.count = b.count + 1
                local mut = m:GetAttribute("Mutation")
                local hasMut = type(mut) == "string" and mut ~= ""
                b.plants[#b.plants + 1] = {
                    model = m,
                    hasMut = hasMut,
                    keep = hasMut and (keepMut[mut] == true),   -- Gold/Rainbow: HARD-GIỮ (chỉ áp cho loại CÓ trong plan)
                }
            end
        end
    end

    -- Gate Limit/DestroyUntil (số hoặc "%").
    local totalPlots = Runtime.GetTotalPlots()
    local limit = Runtime.ResolvePlotCount(c.Limit, totalPlots) or 0
    local destroyUntil = Runtime.ResolvePlotCount(c.DestroyUntil, totalPlots)
    if limit > 0 and plantTotal < limit then
        actionLog("TrimToQuota", "SKIP", ("chua cham Limit %d/%d"):format(plantTotal, limit))
        return
    end

    local trimHoldSeconds = math.max(tonumber(c.TrimHoldSeconds) or 15, 5)
    State.TrimActiveUntil = os.clock() + trimHoldSeconds
    unequipSeedTool("TrimToQuota")

    local shovel = getShovelTool()
    if not shovel then
        State.TrimActiveUntil = 0
        actionLog("TrimToQuota", "SKIP", "missing shovel tool")
        return
    end
    local shovelAttr = shovel:GetAttribute("Shovel")
    Runtime.TryToolLock("TrimToQuota", 8, true)   -- FORCE: trim la uu tien (task khac da yield ShouldYieldForTrim)

    local maxPerCycle = tonumber(c.MaxPerCycle) or 20   -- 0 = KHÔNG giới hạn (1 vòng quét đào hết phần dư tới khi chạm Destroy Until)
    local digDelay = math.max(tonumber(c.DigDelay) or 0.3, 0)   -- nghỉ giữa mỗi nhát đào (config: TrimToQuota.DigDelay)
    local liveTotal = plantTotal
    local dug = 0
    State.TrimActiveUntil = os.clock() + trimHoldSeconds   -- BÁO: đang trim -> tác vụ phụ nhường (ShouldYieldForTrim)
    for sName, b in pairs(bySpecies) do
        if maxPerCycle > 0 and dug >= maxPerCycle then break end   -- maxPerCycle=0 -> bỏ giới hạn
        if destroyUntil and liveTotal <= destroyUntil then break end   -- đã về DestroyUntil -> dừng
        -- FIX BUG "set 0 van trong carrot": cay TRONG-1-LAN truoc day KHONG BAO GIO bi trim -> dam carrot
        -- da lo trong (bug bypass quota cu) nam li do. Gio ap CUNG LUAT voi AutoPlant: quota khai so nao
        -- giu so do (0/ngoai list + DigUnlisted = dao sach); mien-trim khi AutoPlant dang o che do
        -- SinglePlantIgnoreQuota (kieu cu) HOAC SINGLE-FILL (AutoPlant chu dong trong qua quota de xoay
        -- vong mua->trong->hai->ban; dao = phi seed vua trong, cay tu bien mat sau hai nen khong can trim).
        -- Cay single KHONG du dieu kien fill (vd Carrot khong khai quota, Gold khong trong list mua)
        -- van theo luat quota/DigUnlisted binh thuong.
        local isSingle = Runtime.IsSingleHarvestSeed(sName)
            and CFG.AutoPlant ~= nil
            and (CFG.AutoPlant.SinglePlantIgnoreQuota == true
                or (CFG.AutoPlant.SinglesFillFreeSlots ~= false
                    and Runtime.IsSingleFillSeed(sName, tonumber(quota[sName]))))
        local cap = isSingle and nil or tonumber(quota[sName])
        local unlisted = false
        if cap == nil and c.DigUnlisted and not isSingle then
            cap = 0; unlisted = true   -- NGOÀI PlanQuota -> đào SẠCH loại đó (KỂ CẢ đột biến: "cây ko có trong plan thì xúc dù là đột biến")
        end
        -- GIU crop (KeepCropWeather cho mutation / SellMultiWait cho gia sell) -> KHONG dao (du ngoai
        -- PlanQuota / PurgeUnlisted). cap=nil + unlisted=false -> "if cap and b.count > cap" bo qua.
        if Runtime.IsManagedHoldCrop(sName) then
            cap = nil; unlisted = false
        end
        if cap and b.count > cap then
            local need = b.count - cap
            -- XÂY DANH SÁCH ĐÀO theo 3 luật của chồng:
            --   * unlisted: đào TẤT cả con loại đó (kể cả mutation + Gold/Rainbow).
            --   * listed:   bỏ con HARD-GIỮ (Gold/Rainbow). Đào cây THƯỜNG trước; hết cây thường mới đào
            --               đột biến KHÁC theo GIÁ TRỊ TĂNG DẦN (đột biến rẻ đào trước) -> "vượt quota giữ đột biến;
            --               nếu toàn đột biến thì ưu tiên xoá đột biến giá trị thấp".
            local pool = {}
            for _, p in ipairs(b.plants) do
                if unlisted or not p.keep then pool[#pool + 1] = p end
            end
            if not unlisted then
                for _, p in ipairs(pool) do p.value = plantValue(p.model) end
                table.sort(pool, function(x, y)
                    if x.hasMut ~= y.hasMut then return (not x.hasMut) end   -- cây THƯỜNG (không mutation) đào TRƯỚC
                    return (x.value or 0) < (y.value or 0)                   -- cùng nhóm -> giá trị THẤP đào trước
                end)
            end
            local excess = math.min(need, #pool)
            for i = 1, excess do
                -- EVENT rainbow/gold seed nổ -> DỪNG đào ngay đi claim (event ưu tiên nhất)
                if Runtime.ShouldYieldForSeedPriority and Runtime.ShouldYieldForSeedPriority("TrimToQuota") then
                    State.TrimActiveUntil = 0
                    return
                end
                if maxPerCycle > 0 and dug >= maxPerCycle then break end   -- maxPerCycle=0 -> bỏ giới hạn
                if destroyUntil and liveTotal <= destroyUntil then break end
                local entry = pool[i]
                local plant = entry and entry.model
                if plant and plant.Parent then
                    if not equipTool(shovel) then
                        actionLog("TrimToQuota", "SKIP", "cannot equip shovel")
                        State.TrimActiveUntil = 0
                        return
                    end
                    -- fruitId="" -> đào cả cây
                    local ok = firePacket({ "Shovel", "UseShovel" }, plant.Name, "", shovelAttr, shovel)
                    Runtime.ExtendToolLock("TrimToQuota", 5)
                    if ok then
                        dug = dug + 1
                        liveTotal = liveTotal - 1
                        State.TrimActiveUntil = os.clock() + trimHoldSeconds   -- refresh: vẫn đang trim
                        State.LastShovelReplace = os.date("%H:%M:%S") .. (" trim %s ->%d"):format(tostring(sName), cap)
                        actionLog("TrimToQuota", "DIG", ("%s con %d/%d%s"):format(tostring(sName), b.count - i, cap, entry.hasMut and " (mut)" or ""))
                    end
                    if not waitAlive(digDelay) then State.TrimActiveUntil = 0; return end
                end
            end
        end
    end

    State.TrimActiveUntil = 0   -- trim xong -> tác vụ phụ chạy lại ngay
    Runtime.ReleaseToolLock("TrimToQuota")
    if dug > 0 then
        Runtime.ClearPlotFull()   -- còn chỗ trống -> AutoPlant trồng lại đúng quota
        actionLog("TrimToQuota", "DONE", ("dug=%d plants=%d/%s"):format(dug, liveTotal, tostring(totalPlots)))
    end
end

-- Mua gear

local GearPurchaseAssumed = {
    RestockKey = nil,
    Counts = {},
}

local function getGearShop()
    local stockValues = ReplicatedStorage:FindFirstChild("StockValues")
    return stockValues and stockValues:FindFirstChild("GearShop")
end

local function getGearRestockKey()
    local gearShop = getGearShop()
    local lastRestock = gearShop and gearShop:FindFirstChild("UnixLastRestock")
    if not lastRestock then
        return "unknown"
    end
    local ok, value = pcall(function()
        return lastRestock.Value
    end)
    return ok and tostring(value) or "unknown"
end

local function resetGearAssumptionsIfNeeded()
    local restockKey = getGearRestockKey()
    if GearPurchaseAssumed.RestockKey ~= restockKey then
        GearPurchaseAssumed.RestockKey = restockKey
        GearPurchaseAssumed.Counts = {}
    end
end

local function getPurchasedRestockCount(key, itemName)
    local replica = getPlayerReplica()
    local data = replica and replica.Data
    local purchased = data and data.PurchasedThisRestock
    local bucket = purchased and purchased[key]
    if not bucket then
        return nil
    end
    return tonumber(bucket[itemName]) or 0
end

local function getGearStockValue(itemName)
    local gearShop = getGearShop()
    local items = gearShop and gearShop:FindFirstChild("Items")
    local item = items and items:FindFirstChild(itemName)
    if not item then
        return nil
    end
    local ok, value = pcall(function()
        return item.Value
    end)
    return ok and tonumber(value) or nil
end

local function getRemainingGearStock(itemName)
    resetGearAssumptionsIfNeeded()
    local maxStock = getGearStockValue(itemName)
    local purchased = getPurchasedRestockCount("Gears", itemName)
    if maxStock == nil then
        return nil
    end
    purchased = purchased or 0
    local assumed = GearPurchaseAssumed.Counts[itemName] or 0
    return math.max(maxStock - math.max(purchased, assumed), 0)
end

local function noteGearPurchase(itemName)
    resetGearAssumptionsIfNeeded()
    GearPurchaseAssumed.Counts[itemName] = (GearPurchaseAssumed.Counts[itemName] or 0) + 1
end

local function getEquippableGearState()
    if not packet({ "GearShop", "RequestEquippableState" }) then
        return nil
    end
    local ok, state = firePacket({ "GearShop", "RequestEquippableState" })
    if ok and type(state) == "table" then
        return state
    end
    return nil
end

local function listToSet(list)
    local set = {}
    if type(list) == "table" then
        for _, name in ipairs(list) do
            if type(name) == "string" and name ~= "" then
                set[name] = true
            end
        end
    end
    return set
end

local function listToPriority(list)
    local priority = {}
    if type(list) == "table" then
        local total = #list
        for index, name in ipairs(list) do
            if type(name) == "string" and name ~= "" then
                priority[name] = (total - index + 1) * 100
            end
        end
    end
    return priority
end

local function getInventoryStackCount(itemName, categories)
    if type(itemName) ~= "string" or itemName == "" then
        return 0
    end
    local replica = getPlayerReplica()
    local inv = replica and replica.Data and replica.Data.Inventory
    if type(inv) ~= "table" then
        return 0
    end

    local total = 0
    local function countBucket(bucket)
        if type(bucket) ~= "table" then return end
        total = total + (tonumber(bucket[itemName]) or 0)
    end

    if type(categories) == "table" then
        for _, cat in ipairs(categories) do
            countBucket(inv[cat])
        end
    else
        for _, bucket in pairs(inv) do
            countBucket(bucket)
        end
    end
    return total
end

local function getGearDataByName(itemName)
    if not (GearShopData and type(GearShopData.Data) == "table") then
        return nil
    end
    for _, data in ipairs(GearShopData.Data) do
        if type(data) == "table" and data.ItemName == itemName then
            return data
        end
    end
    return nil
end

local function getOwnedGearCount(itemName, gearState)
    local count = getInventoryStackCount(itemName)
    local data = getGearDataByName(itemName)
    if data and data.EquippableGear == true then
        local owned = gearState and gearState.OwnedEquippableGears
        if type(owned) == "table" and owned[itemName] then
            count = math.max(count, 1)
        end
    end
    return count
end

local function isSprinklerGear(data)
    if type(data) ~= "table" then
        return false
    end
    return string.find(tostring(data.ItemName or ""), "Sprinkler", 1, true) ~= nil
        or string.find(tostring(data.ItemType or ""), "Sprinkler", 1, true) ~= nil
end

local function getGearPriority(data, priorityMap, c)
    local itemName = data and data.ItemName
    local priority = itemName and priorityMap[itemName] or 0
    if c and c.PrioritizeSprinklers ~= false and isSprinklerGear(data) then
        priority = math.max(priority, 50)
    end
    return priority
end

local function buildGearCandidates(c, gearState)
    local out = {}
    if not (GearShopData and type(GearShopData.Data) == "table") then
        return out, "missing GearShopData"
    end
    local money = tonumber(getSheckles()) or 0
    local keep = tonumber(c.KeepSheckles) or 0
    local budget = math.max(money - keep, 0)
    local minRarity = c.MinRarity or "Common"
    local owned = gearState and gearState.OwnedEquippableGears
    local excluded = listToSet(c.ExcludeList)
    local priorityMap = listToPriority(c.PriorityList)

    for _, data in ipairs(GearShopData.Data) do
        if type(data) == "table" and not data.RobuxOnly and type(data.ItemName) == "string" and not excluded[data.ItemName] then
            local price = tonumber(data.Cost)
            local rarity = tostring(data.Rarity or "")
            local priority = getGearPriority(data, priorityMap, c)
            local rarityOk = rarityAllowed(rarity, minRarity)
            local priorityOk = priority > 0 and c.AllowPriorityBelowMinRarity ~= false
            if price and price <= budget and (rarityOk or priorityOk) then
                local remaining = nil
                if data.EquippableGear == true then
                    if type(owned) == "table" then
                        remaining = owned[data.ItemName] and 0 or 1
                    end
                elseif data.RestockChance then
                    remaining = getRemainingGearStock(data.ItemName)
                end
                if remaining and remaining > 0 then
                    table.insert(out, {
                        Name = data.ItemName,
                        Price = price,
                        Rarity = rarity,
                        RarityScore = RarityScore[rarity] or 0,
                        Stock = remaining,
                        Equippable = data.EquippableGear == true,
                        Priority = priority,
                    })
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if a.Priority ~= b.Priority then
            return a.Priority > b.Priority
        end
        if a.RarityScore ~= b.RarityScore then
            return a.RarityScore > b.RarityScore
        end
        return a.Price > b.Price
    end)
    return out
end

function Runtime.doAutoBuyGear()
    local c = CFG.AutoBuyGear
    if not (c and c.Enabled) then return end
    if Runtime.ShouldYieldForSeedPriority("AutoBuyGear") or Runtime.ShouldYieldForPetPriority("AutoBuyGear") or Runtime.ShouldYieldForTrim("AutoBuyGear") then
        return
    end
    if not packet({ "GearShop", "PurchaseGear" }) then
        logw("AutoBuyGear: thieu Networking.GearShop.PurchaseGear -> tat.")
        c.Enabled = false
        return
    end
    if c.IgnoreSeedFirst ~= true and CFG.AutoBuySeed and CFG.AutoBuySeed.Enabled then
        local seedCandidates = buildSeedCandidates(CFG.AutoBuySeed)
        if type(seedCandidates) == "table" and #seedCandidates > 0 then
            actionLog("AutoBuyGear", "SKIP", "seed first " .. tostring(seedCandidates[1].Name))
            return
        end
    end

    local gearState = getEquippableGearState()
    local spentThisCycle = 0
    local keep = tonumber(c.KeepSheckles) or 0
    local maxPerItem = math.max(tonumber(c.MaxPerItemPerCycle) or 10, 1)
    local excludedGear = listToSet(c.ExcludeList)
    local function availableMoney()
        return math.max((tonumber(getSheckles()) or 0) - spentThisCycle - keep, 0)
    end
    local function buyGear(name, price, targetCount)
        if type(name) ~= "string" or name == "" then return false end
        if excludedGear[name] then
            actionLog("AutoBuyGear", "SKIP", "blocked " .. tostring(name))
            return false
        end
        targetCount = tonumber(targetCount) or 0
        if targetCount > 0 then
            local ownedCount = getOwnedGearCount(name, gearState)
            if ownedCount >= targetCount then
                actionLog("AutoBuyGear", "SKIP", ("%s owned %d >= target %d"):format(name, ownedCount, targetCount))
                return false
            end
        end
        price = tonumber(price)
        if not price or price <= 0 then
            local data = getGearDataByName(name)
            price = tonumber(data and data.Cost) or 0
        end
        if price > 0 and availableMoney() < price then
            return false
        end
        actionLog("AutoBuyGear", "BUY", price > 0 and (name .. " $" .. tostring(price)) or name)
        local ok = firePacket({ "GearShop", "PurchaseGear" }, name)
        if ok then
            noteGearPurchase(name)
            spentThisCycle = spentThisCycle + price
            return true
        end
        return false
    end

    local mode = string.lower(tostring(c.Mode or "Smart"))
    local bought = 0
    if mode == "list" or mode == "custom" then
        -- MUA THEO SO LUONG: BuyQuantities[ten]=so -> mua moi gear toi SO do (cap MaxPerItemPerCycle, het stock thi dung).
        -- Khong khai so -> mac dinh 1 (giu hanh vi cu cho dang LIST ten thuan).
        local qty = type(c.BuyQuantities) == "table" and c.BuyQuantities or nil
        for _, gearName in ipairs(c.List or {}) do
            local target = qty and math.max(tonumber(qty[gearName]) or 1, 1) or 1
            local ownedCount = getOwnedGearCount(gearName, gearState)
            local want = math.min(math.max(target - ownedCount, 0), maxPerItem)
            if want <= 0 then
                actionLog("AutoBuyGear", "SKIP", ("%s owned %d >= target %d"):format(tostring(gearName), ownedCount, target))
            end
            local boughtThis = 0
            while boughtThis < want do
                local remaining = getRemainingGearStock(gearName)  -- nil cho gear equip; so cho gear restock
                if remaining ~= nil and remaining < 1 then break end -- het stock restock -> dung
                if not buyGear(gearName, 0, target) then break end
                bought = bought + 1
                boughtThis = boughtThis + 1
                if not waitAlive(tonumber(c.Delay) or 0.5) then return end
            end
        end
        actionLog("AutoBuyGear", "DONE", "b=" .. tostring(bought))
        return
    end

    local candidates, reason = buildGearCandidates(c, gearState)
    if #candidates == 0 then
        actionLog("AutoBuyGear", "SKIP", tostring(reason or "no gear"))
        return
    end
    actionLog("AutoBuyGear", "PLAN", ("n=%s money=%s"):format(tostring(#candidates), tostring(getSheckles())))

    for _, gear in ipairs(candidates) do
        local boughtThis = 0
        while boughtThis < maxPerItem do
            local remaining = gear.Equippable and (boughtThis == 0 and 1 or 0) or getRemainingGearStock(gear.Name)
            if not remaining or remaining < 1 then break end
            if availableMoney() < gear.Price then break end
            if not buyGear(gear.Name, gear.Price) then break end
            bought = bought + 1
            boughtThis = boughtThis + 1
            if gear.Equippable then break end
            if not waitAlive(tonumber(c.Delay) or 0.5) then return end
        end
    end

    actionLog("AutoBuyGear", "DONE", "b=" .. tostring(bought))
end

Runtime.CratePurchaseAssumed = {
    RestockKey = nil,
    Counts = {},
}

Runtime.getCrateShop = function()
    local stockValues = ReplicatedStorage:FindFirstChild("StockValues")
    return stockValues and stockValues:FindFirstChild("CrateShop")
end

Runtime.getCrateRestockKey = function()
    local crateShop = Runtime.getCrateShop()
    local lastRestock = crateShop and crateShop:FindFirstChild("UnixLastRestock")
    if not lastRestock then
        return "unknown"
    end
    local ok, value = pcall(function()
        return lastRestock.Value
    end)
    return ok and tostring(value) or "unknown"
end

Runtime.resetCrateAssumptionsIfNeeded = function()
    local restockKey = Runtime.getCrateRestockKey()
    if Runtime.CratePurchaseAssumed.RestockKey ~= restockKey then
        Runtime.CratePurchaseAssumed.RestockKey = restockKey
        Runtime.CratePurchaseAssumed.Counts = {}
    end
end

Runtime.getCrateStockValue = function(crateName)
    local crateShop = Runtime.getCrateShop()
    local items = crateShop and crateShop:FindFirstChild("Items")
    local item = items and items:FindFirstChild(crateName)
    if not item then
        return nil
    end
    local ok, value = pcall(function()
        return item.Value
    end)
    return ok and tonumber(value) or nil
end

Runtime.getRemainingCrateStock = function(crateName)
    Runtime.resetCrateAssumptionsIfNeeded()
    local maxStock = Runtime.getCrateStockValue(crateName)
    local purchased = getPurchasedRestockCount("Crates", crateName)
    if maxStock == nil then
        return nil
    end
    purchased = purchased or 0
    local assumed = Runtime.CratePurchaseAssumed.Counts[crateName] or 0
    return math.max(maxStock - math.max(purchased, assumed), 0)
end

Runtime.noteCratePurchase = function(crateName)
    Runtime.resetCrateAssumptionsIfNeeded()
    Runtime.CratePurchaseAssumed.Counts[crateName] = (Runtime.CratePurchaseAssumed.Counts[crateName] or 0) + 1
end

Runtime.getCrateDataByName = function(crateName)
    if not (CrateData and type(CrateData.GetData) == "function") then
        return nil
    end
    local ok, data = pcall(CrateData.GetData, crateName)
    if ok then
        return data
    end
    return nil
end

Runtime.getOwnedCrateOrPropCount = function(crateName)
    return getInventoryStackCount(crateName, { "Crates" })
end

Runtime.buildCrateCandidates = function(c)
    local out = {}
    if not (CrateData and type(CrateData.GetAllCrates) == "function") then
        return out, "missing CrateData"
    end
    local ok, crates = pcall(CrateData.GetAllCrates)
    if not ok or type(crates) ~= "table" then
        return out, "bad CrateData"
    end

    local money = tonumber(getSheckles()) or 0
    local keep = tonumber(c.KeepSheckles) or 0
    local budget = math.max(money - keep, 0)
    local minRarity = c.MinRarity or "Common"

    for _, data in ipairs(crates) do
        if type(data) == "table" and data.RestockChance and type(data.Name) == "string" then
            local price = tonumber(data.Cost)
            local rarity = tostring(data.Rarity or "")
            if price and price <= budget and rarityAllowed(rarity, minRarity) then
                local remaining = Runtime.getRemainingCrateStock(data.Name)
                if remaining and remaining > 0 then
                    table.insert(out, {
                        Name = data.Name,
                        Price = price,
                        Rarity = rarity,
                        RarityScore = RarityScore[rarity] or 0,
                        Stock = remaining,
                        RestockChance = tonumber(data.RestockChance) or 0,
                    })
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if a.RarityScore ~= b.RarityScore then
            return a.RarityScore > b.RarityScore
        end
        if a.RestockChance ~= b.RestockChance then
            return a.RestockChance < b.RestockChance
        end
        return a.Price > b.Price
    end)
    return out
end

function Runtime.doAutoBuyCrate()
    local c = CFG.AutoBuyCrate
    if not (c and c.Enabled) then return end
    if Runtime.ShouldYieldForSeedPriority("AutoBuyCrate") or Runtime.ShouldYieldForPetPriority("AutoBuyCrate") or Runtime.ShouldYieldForTrim("AutoBuyCrate") then
        return
    end
    if not packet({ "CrateShop", "PurchaseCrate" }) then
        logw("AutoBuyCrate: thieu Networking.CrateShop.PurchaseCrate -> tat.")
        c.Enabled = false
        return
    end

    if c.IgnoreSeedFirst ~= true and CFG.AutoBuySeed and CFG.AutoBuySeed.Enabled then
        local seedCandidates = buildSeedCandidates(CFG.AutoBuySeed)
        if type(seedCandidates) == "table" and #seedCandidates > 0 then
            actionLog("AutoBuyCrate", "SKIP", "seed first " .. tostring(seedCandidates[1].Name))
            return
        end
    end
    if c.IgnoreGearFirst ~= true and CFG.AutoBuyGear and CFG.AutoBuyGear.Enabled then
        local gearCandidates = buildGearCandidates(CFG.AutoBuyGear, getEquippableGearState())
        if type(gearCandidates) == "table" and #gearCandidates > 0 then
            actionLog("AutoBuyCrate", "SKIP", "gear first " .. tostring(gearCandidates[1].Name))
            return
        end
    end

    local spentThisCycle = 0
    local keep = tonumber(c.KeepSheckles) or 0
    local maxPerItem = math.max(tonumber(c.MaxPerItemPerCycle) or 3, 1)
    local function availableMoney()
        return math.max((tonumber(getSheckles()) or 0) - spentThisCycle - keep, 0)
    end
    local function buyCrate(crateName, price, targetCount)
        if type(crateName) ~= "string" or crateName == "" then return false end
        local data = Runtime.getCrateDataByName(crateName)
        targetCount = tonumber(targetCount) or 0
        if targetCount > 0 then
            local ownedCount = Runtime.getOwnedCrateOrPropCount(crateName)
            if ownedCount >= targetCount then
                actionLog("AutoBuyCrate", "SKIP", ("%s owned %d >= target %d"):format(crateName, ownedCount, targetCount))
                return false
            end
        end
        price = tonumber(price)
        if not price or price <= 0 then
            price = tonumber(data and data.Cost) or 0
        end
        if price > 0 and availableMoney() < price then
            return false
        end
        local remaining = Runtime.getRemainingCrateStock(crateName)
        if remaining and remaining < 1 then
            return false
        end
        actionLog("AutoBuyCrate", "BUY", price > 0 and (crateName .. " $" .. tostring(price)) or crateName)
        local ok = firePacket({ "CrateShop", "PurchaseCrate" }, crateName)
        if ok then
            Runtime.noteCratePurchase(crateName)
            spentThisCycle = spentThisCycle + price
            State.LastCrate = os.date("%H:%M:%S") .. " " .. crateName
            return true
        end
        return false
    end

    local bought = 0
    local mode = string.lower(tostring(c.Mode or "Smart"))
    if mode == "list" or mode == "custom" then
        -- MUA THEO SO LUONG: BuyQuantities[ten]=so -> mua moi crate/prop toi SO do (cap MaxPerItemPerCycle, het stock thi dung).
        local qty = type(c.BuyQuantities) == "table" and c.BuyQuantities or nil
        for _, crateName in ipairs(c.List or {}) do
            local target = qty and math.max(tonumber(qty[crateName]) or 1, 1) or 1
            local ownedCount = Runtime.getOwnedCrateOrPropCount(crateName)
            local want = math.min(math.max(target - ownedCount, 0), maxPerItem)
            if want <= 0 then
                actionLog("AutoBuyCrate", "SKIP", ("%s owned %d >= target %d"):format(tostring(crateName), ownedCount, target))
            end
            local boughtThis = 0
            while boughtThis < want do
                local remaining = Runtime.getRemainingCrateStock(crateName)
                if remaining ~= nil and remaining < 1 then break end -- het stock -> dung
                if not buyCrate(crateName, 0, target) then break end
                bought = bought + 1
                boughtThis = boughtThis + 1
                if not waitAlive(tonumber(c.Delay) or 0.5) then return end
            end
        end
        if bought > 0 then
            actionLog("AutoBuyCrate", "DONE", "b=" .. tostring(bought))
        end
        return
    end

    local candidates, reason = Runtime.buildCrateCandidates(c)
    if #candidates == 0 then
        actionLog("AutoBuyCrate", "SKIP", tostring(reason or "no crate"))
        return
    end
    actionLog("AutoBuyCrate", "PLAN", ("n=%s money=%s"):format(tostring(#candidates), tostring(getSheckles())))

    for _, crate in ipairs(candidates) do
        local boughtThis = 0
        while boughtThis < maxPerItem do
            local remaining = Runtime.getRemainingCrateStock(crate.Name)
            if not remaining or remaining < 1 then break end
            if availableMoney() < crate.Price then break end
            if not buyCrate(crate.Name, crate.Price) then break end
            bought = bought + 1
            boughtThis = boughtThis + 1
            if not waitAlive(tonumber(c.Delay) or 0.5) then return end
        end
    end

    if bought > 0 then
        actionLog("AutoBuyCrate", "DONE", "b=" .. tostring(bought))
    end
end

-- Equip 1 gear
function Runtime.doAutoEquipGear()
    local c = CFG.AutoEquipGear
    if not (c and c.Enabled) then return end
    if type(c.Gear) ~= "string" or c.Gear == "" then return end
    actionLog("AutoEquipGear", "START", c.Gear)
    if not packet({ "GearShop", "EquipGear" }) then
        logw("AutoEquipGear: thiếu Networking.GearShop.EquipGear -> tắt.")
        c.Enabled = false
        return
    end
    firePacket({ "GearShop", "EquipGear" }, c.Gear)
    actionLog("AutoEquipGear", "DONE", c.Gear)
end

local function getHarvestPromptModel(prompt)
    local parent = prompt and prompt.Parent
    return parent and parent:FindFirstAncestorWhichIsA("Model") or nil
end

local function getHarvestPromptPosition(prompt)
    if not prompt then
        return nil
    end
    local parent = prompt.Parent
    if parent and parent:IsA("BasePart") then
        return parent.Position
    end
    local model = getHarvestPromptModel(prompt)
    if model then
        local ok, pivot = pcall(function()
            return model:GetPivot()
        end)
        if ok and pivot then
            return pivot.Position
        end
    end
    return nil
end

local function teleportToHarvestPrompt(prompt, c)
    if c.TeleportToFruit == false then
        return false
    end

    local root = getRootPart()
    local pos = getHarvestPromptPosition(prompt)
    if not root or not pos then
        return false
    end

    local maxDistance = tonumber(prompt.MaxActivationDistance) or 10
    if (root.Position - pos).Magnitude <= math.max(maxDistance - 1, 3) then
        return false
    end

    local direction = root.Position - pos
    if direction.Magnitude < 0.001 then
        direction = Vector3.new(0, 0, -1)
    end
    local distance = tonumber(c.TeleportDistance) or 4
    local yOffset = tonumber(c.TeleportYOffset) or 2
    local targetPos = pos + direction.Unit * distance + Vector3.new(0, yOffset, 0)
    root.CFrame = CFrame.lookAt(targetPos, pos)
    Runtime.FireTeleporterMimic(root.Position)
    return waitAlive(tonumber(c.TeleportWait) or 0.05)
end

-- "Bắn diện rộng": fire MỌI ProximityPrompt trong bán kính quanh centerPos.
-- Đây ĐÚNG logic AutoFireGui chồng test claim seed event đạt 100% (quét workspace, prompt có
-- Parent là BasePart, distance <= radius -> fireproximityprompt). Trả về số prompt đã fire.
-- Em CHỈ gọi hàm này trong nhánh claim seed spawn (lúc event) để hết event là tự ngừng,
-- tránh bắn nhầm prompt mua/bán/UI khác.
-- BAT prompt cho CLAIM/MUA duoc ma KHONG can an tay (logic chong dua): Enabled=true, HoldDuration=0 (claim tuc thi),
-- MaxActivationDistance>=15 (du xa de fire). Goi truoc khi fireproximityprompt -> cai nao bi disable cung claim/mua duoc.
Runtime.ensurePromptFireable = function(prompt)
    if not (prompt and prompt:IsA("ProximityPrompt")) then return false end
    pcall(function()
        if prompt.Enabled ~= true then prompt.Enabled = true end
        if prompt.HoldDuration ~= 0 then prompt.HoldDuration = 0 end
        if (tonumber(prompt.MaxActivationDistance) or 0) < 15 then prompt.MaxActivationDistance = 15 end
    end)
    return true
end

-- (BAN BACKUP - chay ok nhat): FIRE MOI ProximityPrompt trong workspace cach centerPos <= radius (mac dinh 10).
-- Dung dung logic AutoFireGui/hic.lua chong test 100%: quet ca workspace, prompt co Parent la BasePart,
-- distance <= radius -> fireproximityprompt. Phu het seed/drop/pet. Tra ve so prompt da fire.
-- An toan: KHONG fire cac prompt NGUY HIEM khi ban dien rong (tranh "ban nham" mo Buy item / Gift A Friend).
--   * GrowPrompt -> HarvestPromptController fire DevProductController:PromptPurchase -> TON ROBUX!
--   * Prompt trong NPCS / co chu Buy/Purchase/Gift/Grow/Robux/Upgrade -> shop/gift/mua.
-- CHI ban prompt claim seed/hai (Claim/Collect/Harvest) -> dung muc dich.
local function isDangerBlastPrompt(v)
    if CollectionService:HasTag(v, "GrowPrompt") then return true end
    local npcs = workspace:FindFirstChild("NPCS")
    if npcs and v:IsDescendantOf(npcs) then return true end
    local txt = string.lower(tostring(v.ActionText or "") .. " " .. tostring(v.ObjectText or ""))
    if txt:find("buy") or txt:find("purchase") or txt:find("gift") or txt:find("grow")
        or txt:find("robux") or txt:find("upgrade") or txt:find("donate") then
        return true
    end
    return false
end

-- ============================================================
-- PROMPT REGISTRY (fix DUNG HINH + RAM no luc event): blast truoc day goi workspace:GetDescendants()
-- (CHUC NGHIN instance = cap phat 1 bang khong lo) MOI 0.1s luc claim seed / 0.25s luc mua pet ->
-- freeze + GC khong don kip. Gio: nuoi 1 SET ProximityPrompt SONG bang DescendantAdded/Removing
-- (O(1) moi event, engine API chuan) -> blast chi duyet vai chuc prompt. Seed 1 lan luc boot (co nha
-- frame). KHONG doi logic fire nao: van isDangerBlastPrompt + fireproximityprompt y het cu.
-- ============================================================
Runtime.SetupPromptRegistry = function()
    if Runtime.PromptSet then return Runtime.PromptSet end
    local set = {}
    Runtime.PromptSet = set
    local addConn = workspace.DescendantAdded:Connect(function(inst)
        if inst:IsA("ProximityPrompt") then set[inst] = true end
    end)
    local remConn = workspace.DescendantRemoving:Connect(function(inst)
        if set[inst] then set[inst] = nil end
    end)
    table.insert(Runtime.Cleanups, function()
        pcall(function() addConn:Disconnect() end)
        pcall(function() remConn:Disconnect() end)
        Runtime.PromptSet = nil
    end)
    Runtime.BeginTurboFps("prompt registry seed")   -- TRICK: quet 1 lan luc boot -> mo cap chay vu
    local n = 0
    for _, inst in ipairs(workspace:GetDescendants()) do
        if inst:IsA("ProximityPrompt") then set[inst] = true end
        n = n + 1
        if n % 500 == 0 then task.wait() end   -- seed 1 LAN duy nhat, nha frame -> khong freeze luc boot
    end
    Runtime.EndTurboFps()
    return set
end

local function blastNearbyPrompts(centerPos, radius)
    if type(fireproximityprompt) ~= "function" or not centerPos then
        return 0
    end
    radius = tonumber(radius) or 10
    local set = Runtime.PromptSet or Runtime.SetupPromptRegistry()
    -- snapshot ra mang truoc khi fire: fire co the lam prompt MOI spawn (DescendantAdded them key vao
    -- set giua luc duyet pairs = undefined behavior) -> duyet ban chup thi an toan tuyet doi.
    -- TOI UU RAM (dot 3): TAI DUNG 1 buffer thay vi cap phat mang moi MOI 0.1-0.25s luc event
    -- (GC Luau chay theo frame, cap 7fps GC doi -> mang xa lien tuc lam heap no). Ham nay khong yield
    -- giua build va duyet nen share 1 buffer cho moi caller la an toan.
    local list = Runtime.BlastListBuf
    if not list then list = {}; Runtime.BlastListBuf = list end
    local n = 0
    for v in pairs(set) do n = n + 1; list[n] = v end
    for i = #list, n + 1, -1 do list[i] = nil end
    local count = 0
    for _, v in ipairs(list) do
        if v:IsDescendantOf(workspace) then
            local part = v.Parent
            if part and part:IsA("BasePart") then
                if (centerPos - part.Position).Magnitude <= radius and not isDangerBlastPrompt(v) then
                    if pcall(fireproximityprompt, v) then
                        count = count + 1
                    end
                end
            end
        end
    end
    return count
end

local function triggerHarvestPrompt(prompt, extraHold)
    if not (prompt and prompt:IsA("ProximityPrompt") and prompt:IsDescendantOf(workspace)) then
        return false
    end
    Runtime.ensurePromptFireable(prompt)   -- BAT Enabled=true + HoldDuration=0 + MaxDist=15 -> claim duoc du game disable prompt
    -- ƯU TIÊN fireproximityprompt (executor): claim TỨC THÌ ĐÚNG 1 prompt được truyền vào,
    -- KHÔNG đụng prompt khác (đây là method chồng test "ấn 1 cái claim luôn"). Vì script đã chọn
    -- sẵn ĐÚNG prompt của seed/quả rồi nên fire 1 cái này là an toàn, không kích nhầm mua pet/UI.
    if type(fireproximityprompt) == "function" then
        local ok = pcall(fireproximityprompt, prompt)
        if ok then
            -- nhịp nhỏ cho server xử lý (seed quý đặt extraHold lớn nhưng fireproximityprompt là
            -- instant nên chỉ cần chờ ngắn; verify item biến mất do vòng claim lo).
            waitAlive(math.min(math.max(tonumber(extraHold) or 0.05, 0.05), 0.3))
            return true
        end
    end
    -- Fallback: giả lập GIỮ phím (InputHoldBegin/End) nếu executor không có fireproximityprompt.
    local ok = pcall(function()
        prompt:InputHoldBegin()
    end)
    if not ok then
        return false
    end
    local hold = tonumber(prompt.HoldDuration) or 0
    waitAlive(math.max(hold, 0) + (tonumber(extraHold) or 0.05))
    pcall(function()
        prompt:InputHoldEnd()
    end)
    return true
end

-- Thu hoạch quả chín trong plot mình

-- Chấm "điểm giá trị" 1 quả còn trên cây để AutoCollect ưu tiên hái quả đáng tiền trước.
-- Dùng đúng công thức bán thật của game: Runtime.FruitValueCalc(FruitName, SizeMultiplier, Mutation, player, DecayAlpha)
-- (ReplicatedStorage SharedModules.FruitValueCalc -> load tại Runtime.FruitValueCalc).
-- Attribute trên model quả (xác nhận FruitVisualizerController + HarvestPromptLabelController):
--   CorePartName = tên cây/quả ; SizeMulti = hệ số kích thước ; Mutation = chuỗi mutation ; DecayAlpha = độ héo (có thể nil).
-- Thiếu data hoặc module chưa load -> trả 0 (an toàn: chỉ mất ưu tiên, KHÔNG crash vòng AutoCollect).
Runtime.FruitCollectScore = function(model)
    local calc = Runtime.FruitValueCalc
    if type(calc) ~= "function" or not model then
        return 0
    end
    local fruitName = model:GetAttribute("CorePartName")
        or model:GetAttribute("FruitName")
        or model:GetAttribute("SeedName")
    if type(fruitName) ~= "string" or fruitName == "" then
        return 0
    end
    -- SizeMulti phải là số (FruitValueCalc làm size^2.65, nil sẽ văng lỗi) -> mặc định 1 như game.
    local sizeMult = tonumber(model:GetAttribute("SizeMulti"))
        or tonumber(model:GetAttribute("SizeMultiplier"))
        or 1
    local mutation = model:GetAttribute("Mutation")
    local decay = tonumber(model:GetAttribute("DecayAlpha"))
    local ok, value = pcall(calc, fruitName, sizeMult, mutation, LocalPlayer, decay)
    if ok and type(value) == "number" then
        return value
    end
    return 0
end

-- Cây 1-lần-thu-hoạch theo SOURCE: SeedData[].IsSingleHarvest (ReplicatedStorage.SharedModules.SeedData,
-- xác nhận; PlantVisualizerController.IsSingleHarvestPlant cũng đọc field này). Cache 1 lần thành set
-- tên-seed -> bool. Gắn vào Runtime.* để KHÔNG thêm local main-chunk (file sát giới hạn 200 local).
Runtime.SingleHarvestSet = Runtime.SingleHarvestSet or nil
Runtime.IsSingleHarvestSeed = function(seedName)
    if type(seedName) ~= "string" or seedName == "" then return false end
    local cache = Runtime.SingleHarvestSet
    if not cache then
        if type(SeedData) ~= "table" then return false end  -- module chưa load -> chưa cache, lần sau thử lại
        cache = {}
        for _, d in ipairs(SeedData) do
            if type(d) == "table" and type(d.SeedName) == "string" then
                cache[d.SeedName] = d.IsSingleHarvest == true
            end
        end
        Runtime.SingleHarvestSet = cache
    end
    return cache[seedName] == true
end

-- SINGLE-FILL eligibility: seed 1-lan nao duoc "trong lap kin cho trong"?
--   (1) SingleFillList (ep tay) -> luon duoc (tru quota=0 - check o caller).
--   (2) Mac dinh: PHAI co quota DUONG trong PlanQuota (chong khai = muon trong; KHONG khai = KHONG
--       trong - vd Carrot mua vo tan de do, chong xac nhan la CO Y) + nam trong LIST MUA
--       (SingleFillOnlyBought - chan seed dac biet Gold/Rainbow/Mega: co the la IsSingleHarvest
--       trong SeedData nhung KHONG mua o shop -> khong duoc trong bay via fill).
Runtime.IsSingleFillSeed = function(seedName, explicitQuota)
    local c = CFG.AutoPlant
    if type(seedName) ~= "string" or seedName == "" then return false end
    local low = string.lower(seedName)
    if c and type(c.SingleFillList) == "table" then
        for _, n in ipairs(c.SingleFillList) do
            if type(n) == "string" and string.lower(n) == low then return true end
        end
    end
    if not (type(explicitQuota) == "number" and explicitQuota > 0) then return false end
    if c and c.SingleFillOnlyBought == false then return true end
    local b = CFG.AutoBuySeed
    if type(b) ~= "table" then return false end
    if type(b.List) == "table" then
        for _, n in ipairs(b.List) do
            if type(n) == "string" and string.lower(n) == low then return true end
        end
    end
    if type(b.OwnLimitPerSeed) == "table" then
        for n in pairs(b.OwnLimitPerSeed) do
            if type(n) == "string" and string.lower(n) == low then return true end
        end
    end
    return false
end

-- ĐIỂM ĐỘ HIẾM của 1 cây theo SOURCE: SeedData[].Rarity (cùng module với IsSingleHarvest) -> quy về
-- số qua bảng RarityScore (Common=1..Secret=8). Cache 1 lần thành map tên-seed -> điểm (tra O(1),
-- gọi được trong vòng nóng). Dùng cho ƯU TIÊN HÁI "độ hiếm giảm dần" (chồng chốt). 0 = không rõ.
Runtime.SeedRarityMap = Runtime.SeedRarityMap or nil
Runtime.SeedRarityScore = function(seedName)
    if type(seedName) ~= "string" or seedName == "" then return 0 end
    local cache = Runtime.SeedRarityMap
    if not cache then
        if type(SeedData) ~= "table" then return 0 end  -- module chưa load -> chưa cache, lần sau thử lại
        cache = {}
        for _, d in ipairs(SeedData) do
            if type(d) == "table" and type(d.SeedName) == "string" then
                cache[d.SeedName] = RarityScore[tostring(d.Rarity or "Common")] or 0
            end
        end
        Runtime.SeedRarityMap = cache
    end
    return cache[seedName] or 0
end

-- CACHE TRÁI: giữ sẵn set HarvestPrompt qua tín hiệu CollectionService -> KHÔNG phải GetTagged
-- (quét TOÀN server) mỗi vòng. Nối signal TRƯỚC rồi seed danh sách hiện có -> không sót quả.
-- Quả chín thêm -> InstanceAdded; quả bị hái/destroy -> InstanceRemoved. doAutoCollect duyệt set này.
Runtime.HarvestPrompts = Runtime.HarvestPrompts or {}
Runtime.HarvestRipeAt = Runtime.HarvestRipeAt or {}  -- [prompt] = os.clock() lúc quả CHÍN (mọc HarvestPrompt)
Runtime.HarvestScore = Runtime.HarvestScore or {}    -- [prompt] = diem gia tri (cache: size/mutation co dinh khi qua da chin)
function Runtime.SetupHarvestCache()
    if Runtime.HarvestCacheReady then return end
    Runtime.HarvestCacheReady = true
    local set = Runtime.HarvestPrompts
    local ripeAt = Runtime.HarvestRipeAt
    local score = Runtime.HarvestScore
    local addConn = CollectionService:GetInstanceAddedSignal("HarvestPrompt"):Connect(function(p)
        set[p] = true
        ripeAt[p] = os.clock()  -- thời điểm quả này VỪA chín -> dùng để "chín lâu nhất múc trước"
    end)
    local remConn = CollectionService:GetInstanceRemovedSignal("HarvestPrompt"):Connect(function(p)
        set[p] = nil
        ripeAt[p] = nil
        score[p] = nil  -- qua bi hai/destroy -> xoa diem cache
    end)
    -- Quả ĐÃ chín sẵn lúc script khởi động -> coi là CHÍN LÂU NHẤT (mốc 0) -> múc trước.
    for _, p in ipairs(CollectionService:GetTagged("HarvestPrompt")) do
        set[p] = true
        ripeAt[p] = 0
    end
    table.insert(Runtime.Cleanups, function()
        pcall(function() addConn:Disconnect() end)
        pcall(function() remConn:Disconnect() end)
    end)
    actionLog("AutoCollect", "CACHE_READY", "harvest prompt cache")
end

-- ===== DATA-HARVEST: hai bang DU LIEU vuon tu remote Garden (KHONG can prompt/cay trong workspace) =====
-- Dung khi Nuke All xoa cay/prompt -> doAutoCollect khong con candidate. Source: GardenSyncController luu
-- u2[userId][plantId].Fruits[fruitId]; HarvestPromptController u97 hai = Garden.CollectFruit:Fire(plantId,fruitId).
Runtime.TrackedPlants = Runtime.TrackedPlants or {}        -- [plantId] = plantData cua MINH; plantData.Fruits[fruitId]=fruitData
Runtime.DataHarvestFiredAt = Runtime.DataHarvestFiredAt or {}  -- ["plantId:fruitId"] = os.clock() lan ban gan nhat (dedup)
Runtime.DataHarvestMiss = Runtime.DataHarvestMiss or {}    -- ["key"] = so lan da ban ma muc tieu VAN CON -> backoff (qua favorite/server tu choi)
Runtime.FruitAgeBase = Runtime.FruitAgeBase or {}           -- ["key"] = {a=Age sync gan nhat, t=luc thay Age doi, s=lan dung gan nhat} (MemJanitor don)
function Runtime.SetupGardenTracker()
    if Runtime.GardenTrackerReady then return end
    Runtime.GardenTrackerTried = true   -- da thu setup (du fail) -> gate data KHONG cho doi vo han neu thieu remote
    local sync = packet({ "Garden", "SyncAllGardens" })
    local pAdd = packet({ "Garden", "PlantAdded" })
    local pRem = packet({ "Garden", "PlantRemoved" })
    local fAdd = packet({ "Garden", "FruitAdded" })
    local fRem = packet({ "Garden", "FruitRemoved" })
    if not (sync and pAdd and pRem and fAdd and fRem) then
        logw("GardenTracker: thieu remote Garden.* -> data-harvest tat, dung prompt cu.")
        return
    end
    Runtime.GardenTrackerReady = true
    local tracked = Runtime.TrackedPlants
    local myId = LocalPlayer.UserId
    local function isMine(uid) return (tonumber(uid) or uid) == myId end
    local function purgeFruitCache(plantId, fruitId)
        local key = tostring(plantId) .. ":" .. tostring(fruitId or "")
        Runtime.FruitAgeBase[key] = nil
        Runtime.DataHarvestFiredAt[key] = nil
        Runtime.DataHarvestMiss[key] = nil
    end
    local function purgePlantCache(plantId, plantData)
        purgeFruitCache(plantId, "")
        if type(plantData) == "table" and type(plantData.Fruits) == "table" then
            for fruitId in pairs(plantData.Fruits) do
                purgeFruitCache(plantId, fruitId)
            end
        end
    end
    local function connect(p, fn)
        if p and p.OnClientEvent and type(p.OnClientEvent.Connect) == "function" then
            local conn = p.OnClientEvent:Connect(fn)
            table.insert(Runtime.Cleanups, function() pcall(function() conn:Disconnect() end) end)
        end
    end
    -- SyncAllGardens(allGardens): nap toan bo cay cua MINH (gardens key theo userId; plantData.Fruits = cac qua)
    -- TOI UU RAM (fix leak): day la FULL RESYNC -> sau khi nap, XOA plantId khong con trong sync
    -- (truoc day chi MERGE them, cay cu/ghost nam lai vinh vien -> TrackedPlants phinh dan theo gio choi).
    -- MERGE (chong yeu cau "update data ripe la GHI DE + GOP, khong THAY THE": 500 qua + 200 qua moi = 700,
    -- khong bi tut ve 200): sync GHI DE field cay (Age/MaxAge/Mutation...) + GOP fruits (giu qua cu, them/
    -- ghi de qua moi) -> KHONG mat qua da co (FruitAdded them giua 2 sync khong bi wipe). Xoa qua/cay do
    -- FruitRemoved/PlantRemoved lo (per-item). Muon quay ve FULL RESYNC (xoa cay ngoai sync) thi
    -- CFG.AutoCollect.DataSyncMerge=false.
    connect(sync, function(all)
        if type(all) ~= "table" then return end
        local merge = not (CFG.AutoCollect and CFG.AutoCollect.DataSyncMerge == false)
        local fresh = merge and nil or {}
        for uid, garden in pairs(all) do
            if isMine(uid) and type(garden) == "table" and type(garden.Plants) == "table" then
                for plantId, plantData in pairs(garden.Plants) do
                    if not merge then
                        fresh[plantId] = true
                        tracked[plantId] = plantData
                    else
                        local old = tracked[plantId]
                        if type(old) == "table" and type(plantData) == "table" then
                            local oldFruits = old.Fruits
                            for k, v in pairs(plantData) do old[k] = v end   -- ghi de field cay (Age/MaxAge/Mutation...)
                            if type(oldFruits) == "table" then
                                if type(plantData.Fruits) == "table" then
                                    for fid, fdata in pairs(plantData.Fruits) do oldFruits[fid] = fdata end
                                end
                                old.Fruits = oldFruits   -- giu bang fruits CU da gop (khong thay bang moi = ko mat qua)
                            end
                        else
                            tracked[plantId] = plantData
                        end
                    end
                end
            end
        end
        if not merge then
            for plantId in pairs(tracked) do
                if not fresh[plantId] then
                    purgePlantCache(plantId, tracked[plantId])
                    tracked[plantId] = nil
                end
            end
        end
        -- DA NHAN SyncAllGardens (du vuon rong) -> bao DATA VUON SAN SANG -> AutoPlant/Trim moi chay (chong yeu cau)
        Runtime.GardenDataReady = true
        Runtime.GardenDataReadyAt = os.clock()
    end)
    connect(pAdd, function(uid, plantId, data) if isMine(uid) and plantId then tracked[plantId] = data end end)
    connect(pRem, function(uid, plantId)
        if isMine(uid) and plantId then
            purgePlantCache(plantId, tracked[plantId])
            tracked[plantId] = nil
        end
    end)
    connect(fAdd, function(uid, plantId, fruitId, data)
        if isMine(uid) and plantId and fruitId then
            purgeFruitCache(plantId, fruitId)
            local pl = tracked[plantId]
            if type(pl) ~= "table" then pl = {}; tracked[plantId] = pl end
            pl.Fruits = pl.Fruits or {}
            pl.Fruits[fruitId] = data
        end
    end)
    connect(fRem, function(uid, plantId, fruitId)
        if isMine(uid) and plantId and fruitId then
            purgeFruitCache(plantId, fruitId)
            local pl = tracked[plantId]
            if type(pl) == "table" and type(pl.Fruits) == "table" then pl.Fruits[fruitId] = nil end
        end
    end)
    -- MUTATION LIVE (KeepCropWeather - chong): GardenSyncController.OnFruitMutationUpdated/OnPlantMutationUpdated
    -- CHI fire callback, KHONG luu .Mutation vao data table u2 (khac cac Handle* khac) -> TrackedPlants
    -- se KHONG co mutation moi neu chi dua SyncAllGardens (chi tuoi moi khi RequestGardens). Tu noi 2 event
    -- de .Mutation luon THUC -> loc hai theo weather mutation chinh xac. Thu tu args xac nhan trong source:
    --   FruitMutationUpdated(userId, plantId, fruitId, mutation)  - FruitVisualizerController:371 key {uid}_{plantId}_{fruitId}, Mutation=arg4
    --   PlantMutationUpdated(userId, plantId, mutation)           - PlantVisualizerController:525/548, Mutation=arg3
    connect(packet({ "Garden", "FruitMutationUpdated" }), function(uid, plantId, fruitId, mutation)
        if isMine(uid) and plantId and fruitId then
            local pl = tracked[plantId]
            if type(pl) == "table" and type(pl.Fruits) == "table" and type(pl.Fruits[fruitId]) == "table" then
                pl.Fruits[fruitId].Mutation = (type(mutation) == "string" and mutation ~= "" and mutation) or nil
            end
        end
    end)
    connect(packet({ "Garden", "PlantMutationUpdated" }), function(uid, plantId, mutation)
        if isMine(uid) and plantId then
            local pl = tracked[plantId]
            if type(pl) == "table" then
                pl.Mutation = (type(mutation) == "string" and mutation ~= "" and mutation) or nil
            end
        end
    end)
    -- yeu cau server BAN lai toan bo vuon (game cung fire luc boot; fire them cho chac chan co data).
    firePacket({ "Garden", "RequestGardens" })
    actionLog("AutoCollect", "TRACKER_READY", "garden data tracker")
end

-- Uoc luong tuoi qua GIUA 2 lan server sync: est = Age + (now - luc thay Age doi) * GrowRate.
-- Cong thuc cua chinh game: FruitVisualizerController.UpdateFruitAges (CurrentAge += dt * GrowthRate;
-- GrowRate mac dinh 0.025 theo SpawnFruitFromData "p187.GrowRate or 0.025"). fruitData.Age duoc
-- GardenSyncController cap nhat TAI CHO (cung 1 bang - moi OnClientEvent nhan chung reference)
-- qua FruitGrowthUpdated/FruitAgeSync -> chi can theo doi luc .Age doi de lam moc.
function Runtime.EstFruitAge(key, f, now)
    local age = tonumber(f.Age) or 0
    local base = Runtime.FruitAgeBase[key]
    if not base or base.a ~= age then
        base = { a = age, t = now }
        Runtime.FruitAgeBase[key] = base
    end
    base.s = now
    return age + (now - base.t) * (tonumber(f.GrowRate) or 0.025)
end

-- ===== FRUIT SELL MULTIPLIER (source XAC NHAN LIVE 2026: FruitStockPriceController.lua:275-282 -
-- Networking.FruitStock.Request:Fire() TRA VE snapshot DONG BO {entries[<TenCay>]={multiplier,tier},
-- nextRefreshUnix, cycleSeconds}; Snapshot.OnClientEvent chi PUSH khi thi truong doi giua chu ky ~600s).
-- BUG CU (verify bridge): tracker chi nghe Snapshot -> KHONG BAO GIO co multiplier (Snapshot it khi push,
-- Request return bi bo) -> x4 detect chet. FIX: LAY return cua Request:Fire() + POLL dinh ky. =====
Runtime.FruitStockMulti = Runtime.FruitStockMulti or {}   -- [normName] = multiplier hien tai
function Runtime.SetupFruitStockTracker()
    if Runtime.FruitStockTrackerReady then return end
    local reqPkt = packet({ "FruitStock", "Request" })
    if not (reqPkt and type(reqPkt.Fire) == "function") then
        logw("FruitStockTracker: thieu Networking.FruitStock.Request -> KeepCropsForSell (gia x4) tat.")
        return
    end
    Runtime.FruitStockTrackerReady = true
    local function apply(p)
        if type(p) ~= "table" or type(p.entries) ~= "table" then return end
        local m = Runtime.FruitStockMulti
        table.clear(m)
        for name, v in pairs(p.entries) do
            if type(name) == "string" and type(v) == "table" and type(v.multiplier) == "number" then
                m[normalizeItemName(name)] = v.multiplier
            end
        end
        Runtime.FruitStockNextRefresh = tonumber(p.nextRefreshUnix)
        Runtime.FruitStockAt = os.clock()
    end
    -- Snapshot push (khi thi truong doi giua chu ky) - phu tro
    local snap = packet({ "FruitStock", "Snapshot" })
    if snap and snap.OnClientEvent and type(snap.OnClientEvent.Connect) == "function" then
        local conn = snap.OnClientEvent:Connect(apply)
        table.insert(Runtime.Cleanups, function() pcall(conn.Disconnect, conn) end)
    end
    -- Request:Fire() TRA VE snapshot dong bo -> lay ngay + POLL dinh ky de bat x4 khi thi truong doi.
    local function poll()
        local ok, res = pcall(function() return reqPkt:Fire() end)
        if ok then apply(res) end
    end
    poll()
    Runtime.FruitStockPollThread = task.spawn(function()
        while isAlive() do
            local every = math.max(tonumber(CFG.AutoCollect and CFG.AutoCollect.FruitStockPollEvery) or 60, 15)
            if not waitAlive(every) then break end
            poll()
        end
    end)
    actionLog("AutoCollect", "STOCK_TRACKER", "fruit sell multiplier tracker (Request return + poll)")
end

-- ===== WEATHER MUTATION detect (source: ReplicatedStorage.WeatherValues attribute "<W>_Playing" / "<W>_EndTime"
-- - WeatherController.lua:8/106/147/111). 7 weather ra mutation (KHONG Rain - Rain chi 2x growth). =====
-- Mapping (verify wiki chong): Sunburst->Ignited, Starfall->Starstruck, Aurora->Aurora, Rainbow->Rainbow,
-- Lightning->Electric, Snowfall->Frozen, Eclipse->Eclipsed.
Runtime.MutationWeatherList = { "Sunburst", "Starfall", "Aurora", "Rainbow", "Lightning", "Snowfall", "Eclipse" }
-- Tra ve: active(bool), tenWeather, remainingSeconds (con bao lau het, nil neu ko doc duoc EndTime).
Runtime.GetActiveMutationWeather = function()
    local wv = ReplicatedStorage:FindFirstChild("WeatherValues")
    if not wv then return false end
    local list = (CFG.AutoCollect and type(CFG.AutoCollect.KeepSeedForSellWeathers) == "table"
        and CFG.AutoCollect.KeepSeedForSellWeathers) or Runtime.MutationWeatherList
    for _, w in ipairs(list) do
        if type(w) == "string" then
            local ok, playing = pcall(function() return wv:GetAttribute(w .. "_Playing") end)
            if ok and playing then
                local endT = 0
                pcall(function() endT = tonumber(wv:GetAttribute(w .. "_EndTime")) or 0 end)
                local remaining = endT > 0 and (endT - os.time()) or nil
                return true, w, remaining
            end
        end
    end
    return false
end
Runtime.IsMutationWeatherActive = function()
    return (Runtime.GetActiveMutationWeather())
end

-- ================= KEEP CROPS FOR SELL (chong yeu cau 2026 - DOI TU KeepSeedForSell) =================
-- KHONG con GIU SEED nua: cay trong KeepCropsForSell duoc TRONG BINH THUONG (theo PlantQuota, vd 100 Bamboo).
-- Sau khi trong: GIU (khong hai) toi khi GIA BAN cua cay do >= KeepCropsForSellMulti (x4) -> luc do CHI HAI
-- cay/qua BI DOT BIEN roi ban -> an gia cao nhat (vd Rainbow x30 * gia ban x4 = ~x140 gia tri).
--   * Cay THU HOACH 1 LAN (Bamboo/Mushroom/Rocket Pop): dot bien nam tren CAY (plantData.Mutation) -
--     verify LIVE 2026: plantData.Mutation = "Starstruck"... tren cay da chin (Age>=MaxAge).
--   * Cay THU HOACH NHIEU LAN (Hypno Bloom): dot bien nam tren QUA (fruitData.Mutation = "Gold"...).
-- Chua x4 -> GIU HET (cho cay/qua dinh dot bien qua cac dot weather). x4 nhung KHONG dot bien -> van GIU
-- (cho no dinh dot bien roi ban dot x4 sau). Config: KeepCropsForSell = {...}, KeepCropsForSellMulti = 4.
-- Tuong thich nguoc: van doc key cu KeepSeedForSell/KeepSeedForSellMulti neu config chua doi.
Runtime.KeepCropsForSellHas = function(cropName)
    local ac = CFG.AutoCollect
    local list = ac and (ac.KeepCropsForSell or ac.KeepSeedForSell)
    if type(list) ~= "table" or next(list) == nil or type(cropName) ~= "string" then return false end
    local pn = normalizeItemName(cropName)
    for _, v in ipairs(list) do
        if type(v) == "string" and normalizeItemName(v) == pn then return true end
    end
    return false
end
Runtime.KeepSeedForSellHas = Runtime.KeepCropsForSellHas   -- alias tuong thich (usages cu)
-- SELL ALL khi x4: cropName co trong SellAllForMultipliers khong? Cay trong list -> khi gia >= x4 thi BAN
-- SACH (bo dieu kien dot bien) de tieu thu seed. So sanh chuan hoa ten (normalizeItemName) nhu Keep.
Runtime.SellAllForMultipliersHas = function(cropName)
    local ac = CFG.AutoCollect
    local list = ac and ac.SellAllForMultipliers
    if type(list) ~= "table" or next(list) == nil or type(cropName) ~= "string" then return false end
    local pn = normalizeItemName(cropName)
    for _, v in ipairs(list) do
        if type(v) == "string" and normalizeItemName(v) == pn then return true end
    end
    return false
end
-- GIU-DE-BAN (gop): cay dang duoc GIU cho x4 vi BAT KY ly do nao (KeepCropsForSell HOAC SellAllForMultipliers).
-- Dung cho bao ve khoi trim (IsManagedHoldCrop) -> cay SellAll cung khong bi dao khi dang ngam cho x4.
Runtime.IsHoldForSellCrop = function(cropName)
    return Runtime.KeepCropsForSellHas(cropName) or Runtime.SellAllForMultipliersHas(cropName)
end
-- FRESH ACC PHASE: dang fresh-acc (FreshAcc=true VA so cay < PlantSwitch) -> KeepCropsForSell TAT (trong+hai
-- binh thuong de fill vuon nhanh). >= PlantSwitch -> BAT. Cache countMyPlants 2s (ScanHarvestTargets goi
-- nhieu/giay -> tranh O(N^2)).
Runtime.IsFreshAccPhase = function()
    local ap = CFG.AutoPlant
    if not (ap and ap.FreshAcc == true) then return false end
    local switch = tonumber(ap.PlantSwitch) or 0
    if switch <= 0 then return false end
    local cache = Runtime.FreshAccCache
    local nowc = os.clock()
    if not cache or (nowc - cache.At) > 2 then
        cache = { N = countMyPlants(), At = nowc }
        Runtime.FreshAccCache = cache
    end
    return cache.N < switch
end
-- Gia ban HIEN TAI cua 1 cay da >= x4 chua? Tra: ready(bool), mult hien tai, nguong. FruitStockMulti[norm].
Runtime.CropSellMultReady = function(cropName)
    local ac = CFG.AutoCollect
    local need = tonumber(ac and (ac.KeepCropsForSellMulti or ac.KeepSeedForSellMulti)) or 4
    local cur = Runtime.FruitStockMulti and Runtime.FruitStockMulti[normalizeItemName(cropName)]
    cur = type(cur) == "number" and cur or 0
    return cur >= need, cur, need
end
-- Cay/qua KeepCropsForSell da chin: co GIU (chua hai) khong?
-- HAI khi: gia da x4 VA cay/qua CO dot bien (isMutated=true). Nguoc lai -> GIU. isMutated do caller truyen:
--   cay 1-lan = plantData.Mutation ~= ""; cay nhieu lan = fruitData.Mutation ~= "".
Runtime.ShouldHoldCropHarvest = function(cropName, isMutated)
    local inSellAll = Runtime.SellAllForMultipliersHas(cropName)
    if not (Runtime.KeepCropsForSellHas(cropName) or inSellAll) then return false end   -- khong khai -> hai binh thuong
    if Runtime.IsFreshAccPhase() then return false end                  -- fresh-acc -> hai binh thuong
    local ready = Runtime.CropSellMultReady(cropName)
    if inSellAll then
        -- SellAllForMultipliers (thang tren Keep neu cay o ca 2 list): x4 -> BAN SACH (KHONG can dot bien) de
        -- tieu thu seed; chua x4 -> GIU (ngam). Cay 1-lan hai ca cay; cay nhieu lan hai TRAI (gate goi tung qua).
        return not ready
    end
    if ready and isMutated == true then
        return false   -- KeepCropsForSell: x4 + dot bien -> HAI (ban gia cao nhat)
    end
    return true   -- chua x4 / cay-qua chua dot bien -> GIU
end
-- Bao ve khoi trim: crop trong KeepCropsForSell -> khong dao (dang giu cho x4). Tat: KeepCropsProtectFromTrim=false.
Runtime.IsManagedHoldCrop = function(plantName)
    local ac = CFG.AutoCollect
    if ac and (ac.KeepCropsProtectFromTrim == false or ac.KeepSeedProtectFromTrim == false) then return false end
    if Runtime.IsFreshAccPhase() then return false end   -- fresh-acc: KeepCropsForSell tat -> trim binh thuong
    return Runtime.IsHoldForSellCrop(plantName)   -- bao ve ca cay SellAllForMultipliers (dang ngam cho x4)
end

-- ===== LIST FRUIT DANG GIU (chong dot 20 - thay panel "du doan thoi tiet" tren GUI) =====
-- Quet Runtime.TrackedPlants, gom theo TEN cay cac cay/qua DANG BI GIU cho ban (KeepCropsForSell /
-- SellAllForMultipliers, chua du dieu kien x4) + dem tung loai DOT BIEN. Chi xet cay hold-for-sell (skip
-- nhanh cay thuong) -> nhe. Tra: list { {Name, Total, MutStr}, ... } sort theo so luong giam dan.
Runtime.CollectHeldCropsSummary = function()
    local out = {}
    local tracked = Runtime.TrackedPlants
    if type(tracked) ~= "table" then return out end
    local byName = {}
    local function add(nm, mut)
        local e = byName[nm]
        if not e then e = { Total = 0, Muts = {} }; byName[nm] = e end
        e.Total = e.Total + 1
        if type(mut) == "string" and mut ~= "" then e.Muts[mut] = (e.Muts[mut] or 0) + 1 end
    end
    for _, pl in pairs(tracked) do
        if type(pl) == "table" and pl.IsPotted ~= true then
            local nm = pl.PlantName
            -- SKIP nhanh cay khong nam trong Keep/SellAll (khong giu -> khong hien)
            if type(nm) == "string" and Runtime.IsHoldForSellCrop(nm) then
                -- CAY 1-LAN da chin dang giu: dot bien tren CAY
                if Runtime.IsSingleHarvestSeed(nm) then
                    local ma = tonumber(pl.MaxAge) or 0
                    if ma > 0 and (tonumber(pl.Age) or 0) >= ma then
                        local plMut = type(pl.Mutation) == "string" and pl.Mutation ~= "" and pl.Mutation or nil
                        if Runtime.ShouldHoldCropHarvest(nm, plMut ~= nil) then add(nm, plMut) end
                    end
                end
                -- QUA multi-harvest da chin dang giu: dot bien tren QUA
                local fr = pl.Fruits
                if type(fr) == "table" then
                    for _, f in pairs(fr) do
                        if type(f) == "table" then
                            local ma = tonumber(f.MaxAge) or 0
                            if ma > 0 and (tonumber(f.Age) or 0) >= ma then
                                local fMut = type(f.Mutation) == "string" and f.Mutation ~= "" and f.Mutation or nil
                                if Runtime.ShouldHoldCropHarvest(nm, fMut ~= nil) then add(nm, fMut) end
                            end
                        end
                    end
                end
            end
        end
    end
    for nm, e in pairs(byName) do
        local mparts = {}
        for mut, cnt in pairs(e.Muts) do mparts[#mparts + 1] = mut .. " x" .. cnt end
        table.sort(mparts)
        out[#out + 1] = { Name = nm, Total = e.Total, MutStr = (#mparts > 0 and table.concat(mparts, ", ") or "khong dot bien") }
    end
    table.sort(out, function(a, b) return a.Total > b.Total end)
    return out
end

-- Cap nhat ScrollingFrame list fruit dang giu (tai dung label trong Runtime.HeldPanel.Pool, an phan du).
-- Goi tu vong refresh GUI (thay cho setText(vEvent...)). GUI build luu Runtime.HeldPanel = {Scroll,Title,Pool}.
Runtime.UpdateHeldFruitPanel = function()
    local hp = Runtime.HeldPanel
    if type(hp) ~= "table" or not (hp.Scroll and hp.Scroll.Parent) then return end
    local data = Runtime.CollectHeldCropsSummary()
    local pool = hp.Pool
    if type(pool) ~= "table" then pool = {}; hp.Pool = pool end
    for i, e in ipairs(data) do
        local lbl = pool[i]
        if not lbl then
            lbl = Instance.new("TextLabel")
            lbl.BackgroundTransparency = 1
            lbl.Size = UDim2.new(1, 0, 0, 18)
            lbl.Font = Enum.Font.GothamMedium
            lbl.TextSize = 14
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.TextColor3 = Color3.fromRGB(222, 226, 238)
            lbl.TextTruncate = Enum.TextTruncate.AtEnd
            lbl.LayoutOrder = i
            lbl.Parent = hp.Scroll
            pool[i] = lbl
        end
        lbl.Visible = true
        lbl.Text = ("\u{1F34F} %s  x%d   [%s]"):format(tostring(e.Name), tonumber(e.Total) or 0, tostring(e.MutStr))
    end
    for i = #data + 1, #pool do
        if pool[i] then pool[i].Visible = false end
    end
    if hp.Title then
        hp.Title.Text = ("\u{1F9EC} Fruit dang giu (cho x4): %d loai"):format(#data)
    end
end

-- ================= KEEP SEED FOR SELL — WEBHOOK BAO CAO (link RIENG) =================
-- Chong yeu cau: moi khi bot XAI KeepSeedForSell (giu seed cay single, cho weather/gia x4 -> trong -> hai ->
-- ban) thi gui 1 webhook RIENG bao: tien TRUOC/SAU, he so nhan BAN hien tai (FruitStock), THOI TIET + he so
-- nhan dot bien, va uoc tinh LOI so voi ban gia goc (x1). Co che: ARM khi HAI cay KSF (Runtime.KSFArm) ->
-- BAO CAO khi lan BAN ke tiep thanh cong (Runtime.DoKeepSeedForSellReport goi trong doAutoSell).
-- MAPPING weather->ten-dot-bien: HARDCODE (verify LIVE truoc day, KHONG co trong dump) - cho override qua
-- CFG.AutoCollect.KeepSeedForSellWeatherMut. HE SO nhan doc LIVE tu MutationData.ReturnPriceMultiplier
-- (module co LIVE du khong co trong dump), fallback so hardcode neu khong load duoc.
Runtime.KSFWeatherMut = {
    Sunburst  = { mut = "Ignited",    mult = 60 },
    Starfall  = { mut = "Starstruck", mult = 50 },
    Aurora    = { mut = "Aurora",     mult = 40 },
    Rainbow   = { mut = "Rainbow",    mult = 30 },
    Lightning = { mut = "Electric",   mult = 25 },
    Snowfall  = { mut = "Frozen",     mult = 20 },
    Eclipse   = { mut = "Eclipsed",   mult = 80 },
}
-- Doc he so nhan dot bien LIVE tu MutationData.ReturnPriceMultiplier(mutName). nil neu khong doc duoc.
Runtime.GetMutationMultLive = function(mutName)
    if type(mutName) ~= "string" or mutName == "" then return nil end
    local mod = Runtime.MutationDataModule
    if mod == nil then
        mod = false
        local sm = ReplicatedStorage:FindFirstChild("SharedModules")
        local m = sm and sm:FindFirstChild("MutationData")
        if m then
            local ok, res = pcall(require, m)
            if ok and type(res) == "table" then mod = res end
        end
        Runtime.MutationDataModule = mod   -- cache: table = co, false = da thu ma khong co
    end
    if type(mod) == "table" and type(mod.ReturnPriceMultiplier) == "function" then
        local ok, v = pcall(mod.ReturnPriceMultiplier, mutName)
        if ok and type(v) == "number" and v > 0 then return v end
    end
    return nil
end

-- ARM: goi khi HAI 1 cay/qua KeepCropsForSell (chi xay ra luc x4 + dot bien) -> chup snapshot cho lan BAN ke tiep.
-- An toan: xac nhan lai da x4 (CropSellMultReady) truoc khi arm; fresh-acc thi bo qua. mutName = ten dot bien
-- cua cay/qua vua hai (single = plant.Mutation, multi = fruit.Mutation) -> luu he so dot bien LON NHAT de tinh loi.
Runtime.KSFArm = function(cropName, mutName)
    local wh = CFG.KeepCropsForSellWebhook or CFG.KeepSeedForSellWebhook
    if not (wh and wh.Enabled ~= false and type(wh.Url) == "string" and wh.Url ~= "") then return end
    if Runtime.IsFreshAccPhase() then return end
    local ready, mult = Runtime.CropSellMultReady(cropName)
    if not ready then return end   -- chua x4 -> ban binh thuong -> KHONG bao

    local s = Runtime.KSFState
    if not (s and s.Armed) then
        s = { Armed = true, SellMult = 1, MutMult = 0, Crops = {}, Muts = {}, ArmAt = os.clock() }
        Runtime.KSFState = s
    end
    if type(cropName) == "string" and cropName ~= "" then
        s.Crops[cropName] = true
        if mult > (tonumber(s.SellMult) or 0) then s.SellMult = mult end
    end
    if type(mutName) == "string" and mutName ~= "" then
        s.Muts[mutName] = true
        local mm = Runtime.GetMutationMultLive(mutName)
        if type(mm) == "number" and mm > (tonumber(s.MutMult) or 0) then s.MutMult = mm; s.TopMut = mutName end
    end
end

-- BAO CAO: goi sau khi BAN thanh cong (doAutoSell). Dang arm KSF -> gui webhook RIENG roi clear (1 lan/lo ban).
Runtime.DoKeepSeedForSellReport = function(moneyBefore, gained)
    local s = Runtime.KSFState
    if not (s and s.Armed) then return end
    Runtime.KSFState = nil   -- clear NGAY: chi bao 1 lan / lo ban
    local wh = CFG.KeepCropsForSellWebhook or CFG.KeepSeedForSellWebhook   -- FIX: report doc CUNG key voi KSFArm (truoc doc key cu nil -> khong bao gio gui)
    if not (wh and wh.Enabled ~= false and type(wh.Url) == "string" and wh.Url ~= "") then return end
    if (os.clock() - (tonumber(s.ArmAt) or 0)) > (tonumber(wh.MaxAge) or 600) then return end  -- arm qua cu -> bo (ban khong lien quan)

    moneyBefore = tonumber(moneyBefore) or (tonumber(getSheckles()) or 0)
    gained = math.max(tonumber(gained) or 0, 0)
    local moneyAfter = moneyBefore + gained

    local sellMult = math.max(tonumber(s.SellMult) or 1, 1)
    local mutMult  = math.max(tonumber(s.MutMult) or 1, 1)
    -- KeepCropsForSell ban luc x4 + dot bien -> CA 2 he so ap dung: he so ap dung = sellMult * mutMult.
    local effMult = sellMult * mutMult
    local baseline = (effMult > 1) and (gained / effMult) or gained   -- so tien neu ban gia goc (x1, khong dot bien)
    local profit = math.max(gained - baseline, 0)

    local crops = {}
    for name in pairs(s.Crops or {}) do crops[#crops + 1] = name end
    local cropStr = (#crops > 0) and table.concat(crops, ", ") or "-"
    local muts = {}
    for name in pairs(s.Muts or {}) do muts[#muts + 1] = name end
    local mutStr = (#muts > 0) and table.concat(muts, ", ") or "-"

    local payload = {
        content = tostring(wh.Mention or ""),
        embeds = { {
            title = "🌱 KeepCropsForSell — Da Ban Lo Giu-De-Ban",
            description = ("Acc **%s** vua ban lo cay giu-de-ban (gia x%.2f + dot bien)."):format(getAccountName(), sellMult),
            color = 0x2ECC71,
            fields = {
                { name = "🌱 Cay", value = cropStr, inline = false },
                { name = "🧬 Dot bien", value = mutStr, inline = false },
                { name = "💰 Tien truoc", value = Runtime.FmtMoney(moneyBefore), inline = true },
                { name = "💵 Tien sau", value = Runtime.FmtMoney(moneyAfter), inline = true },
                { name = "📈 Ban duoc", value = "+" .. Runtime.FmtMoney(gained), inline = true },
                { name = "✖️ He so ban (stock)", value = "x" .. string.format("%.2f", sellMult), inline = true },
                { name = "🧬 He so dot bien", value = "x" .. string.format("%.0f", mutMult), inline = true },
                { name = "⚡ He so ap dung", value = "x" .. string.format("%.1f", effMult), inline = true },
                { name = "🏆 Loi nho nhan (uoc tinh)", value = ("+%s  (ban gia goc x1 chi ~%s)"):format(Runtime.FmtMoney(profit), Runtime.FmtMoney(baseline)), inline = false },
            },
            footer = { text = "Kaitun KeepCropsForSell • " .. getAccountName() },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        } },
    }
    local ok, res = Runtime.HttpSend("POST", wh.Url, payload)
    if ok then
        State.LastKSFReport = os.date("%H:%M:%S") .. " +" .. Runtime.FmtMoney(profit)
        actionLog("AutoSell", "KSF_REPORT", ("%s +%s (x%.2f)"):format(cropStr, Runtime.FmtMoney(profit), effMult))
    else
        actionLog("AutoSell", "KSF_REPORT", "webhook fail " .. tostring(res))
    end
end

-- Quet TrackedPlants -> danh sach muc tieu HAI DUOC NGAY + so lieu GUI (State.HarvestStat).
-- QUA: chin khi Age >= MaxAge (dieu kien game gan HarvestPrompt - FruitVisualizerController:389).
-- CAY 1-LAN (bamboo/mushroom... SeedData.IsSingleHarvest): KHONG co qua roi trong .Fruits - game hai
-- bang CollectFruit(plantId, "") khi plantData.Age >= plantData.MaxAge (PlantVisualizerController:202
-- gan prompt len CAY; HarvestPromptController:53 fire voi FruitId RONG). Truoc day doDataHarvest chi
-- duyet .Fruits nen BAMBOO KHONG BAO GIO duoc hai o che do data (TrackStat day bamboo ton) -> da fix.
function Runtime.ScanHarvestTargets(ripeOnly, statsOnly)
    local tracked = Runtime.TrackedPlants
    if type(tracked) ~= "table" then return nil end
    local now = os.clock()
    local miss = Runtime.DataHarvestMiss
    -- TOI UU RAM (dot 3): TAI DUNG buffer + pool entry thay vi cap phat mang/bang MOI moi lan quet.
    -- Ham nay chay toi ~10 lan/giay luc hai lien tuc -> truoc day xa ca ngan bang/giay cho GC,
    -- ma GC Luau chay theo FRAME (cap 7fps = GC bi bo doi) -> heap phinh nhanh = "RAM no".
    -- statsOnly=true (GUI): CHI DEM cho State.HarvestStat, khong build danh sach -> khong cap phat.
    -- Buffer chi do task AutoCollect dung (GUI di duong statsOnly) -> yield giua luc tieu thu van an toan.
    local singles, fruits
    if not statsOnly then
        singles = Runtime.ScanSinglesBuf
        if not singles then singles = {}; Runtime.ScanSinglesBuf = singles end
        fruits = Runtime.ScanFruitsBuf
        if not fruits then fruits = {}; Runtime.ScanFruitsBuf = fruits end
    end
    local totalF, ripeF, stuck, nSingle, held = 0, 0, 0, 0, 0
    for plantId, pl in pairs(tracked) do
        if type(pl) == "table" and pl.IsPotted ~= true then  -- PickFruit source bo qua cay trong chau
            -- DO HIEM cua cay (SeedData[].Rarity) -> uu tien hai "do hiem giam dan" (chong chot).
            -- Chi tra khi build danh sach (statsOnly khong can) -> khong ton cong o duong GUI.
            local plantR = (singles or fruits) and Runtime.SeedRarityScore(pl.PlantName) or 0
            if Runtime.IsSingleHarvestSeed(pl.PlantName) then
                -- tuoi CAY chi co .Age server sync tai cho (PlantGrowthUpdated/PlantAgeSync);
                -- plantData KHONG co GrowRate de tu uoc luong -> DataResyncEvery bu data tuoi dinh ky.
                local ma = tonumber(pl.MaxAge) or 0
                if ma > 0 and (tonumber(pl.Age) or 0) >= ma then
                    -- CAY 1-LAN: dot bien nam tren CAY (plantData.Mutation) - KeepCropsForSell hai khi x4 + dot bien.
                    local plMut = type(pl.Mutation) == "string" and pl.Mutation ~= "" and pl.Mutation or nil
                    if Runtime.ShouldHoldCropHarvest(pl.PlantName, plMut ~= nil) then
                        -- KeepCropsForSell: giu cay (chua x4 / chua dot bien) -> cho dinh dot bien roi x4 moi hai.
                        held = held + 1
                    else
                        local pid = tostring(plantId)
                        nSingle = nSingle + 1
                        if singles then
                            -- entry pool {P=plantId, R=do hiem, KSF=cay KeepCropsForSell, Mut=ten dot bien (webhook)}
                            local e = singles[nSingle]
                            if type(e) ~= "table" then e = {}; singles[nSingle] = e end
                            e.P = pid; e.R = plantR; e.KSF = Runtime.KeepCropsForSellHas(pl.PlantName); e.Name = pl.PlantName; e.Mut = plMut
                        end
                        if (tonumber(miss[pid .. ":"]) or 0) >= 2 then stuck = stuck + 1 end
                    end
                end
            end
            local fr = pl.Fruits
            if type(fr) == "table" then
                for fruitId, f in pairs(fr) do
                    if type(f) == "table" then
                        totalF = totalF + 1
                        local key = tostring(plantId) .. ":" .. tostring(fruitId)
                        local ripe = true
                        if ripeOnly then
                            -- CHIN theo source: FruitVisualizerController:577-579 Age>=MaxAge (OvertimeGrowth
                            -- chi la SO QUA bonus, KHONG doi diem chin). MaxAge nam trong fruit data
                            -- (FruitVisualizer:897 p207.MaxAge). Age cap nhat qua FruitGrowthUpdated/AgeSync.
                            local ma = tonumber(f.MaxAge) or 0
                            if ma <= 0 then
                                -- CHUA biet MaxAge -> KHONG coi la chin (tranh spam CollectFruit qua non =
                                -- goc loi "collect cham dan"); giong het cach cay single-harvest lam o tren.
                                ripe = false
                            elseif CFG.AutoCollect and CFG.AutoCollect.DataHarvestUseRawAge ~= false then
                                -- CHUAN NHAT (chong yeu cau "lay data ripe chuan hon"): dung Age server sync
                                -- THUC, khong uoc luong troi -> het false-ripe (qua chua chin ma bi tinh chin
                                -- roi ban truot -> "ket"). Doi da co server ban Age>=MaxAge la dinh -> hai.
                                ripe = (tonumber(f.Age) or 0) >= ma
                            else
                                -- che do cu (uoc luong troi giua 2 sync) - opt-in neu muon hai som ~1 sync
                                ripe = Runtime.EstFruitAge(key, f, now) >= ma
                            end
                        end
                        -- CAY NHIEU LAN: dot bien nam tren QUA (fruitData.Mutation) - KeepCropsForSell hai qua khi x4 + dot bien.
                        local fMut = type(f.Mutation) == "string" and f.Mutation ~= "" and f.Mutation or nil
                        if ripe and Runtime.ShouldHoldCropHarvest(pl.PlantName, fMut ~= nil) then
                            -- GIU qua: KeepCropsForSell chua x4 / qua chua dot bien -> cho dinh dot bien roi x4 moi hai.
                            -- (Cay fruit thuong ko nam trong KeepCropsForSell -> ham tra false = hai binh thuong.)
                            held = held + 1
                        elseif ripe then
                            ripeF = ripeF + 1
                            if fruits then
                                local e = fruits[ripeF]
                                if type(e) ~= "table" then e = {}; fruits[ripeF] = e end
                                e.P = tostring(plantId); e.F = tostring(fruitId); e.K = key
                                e.R = plantR   -- do hiem cua cay me -> sort "do hiem giam dan"
                                e.KSF = Runtime.KeepCropsForSellHas(pl.PlantName)   -- uu tien hai truoc
                                e.Name = pl.PlantName
                                e.Mut = fMut   -- ten dot bien cua qua (webhook)
                            end
                            -- "ket" = da ban >=2 lan ma van con trong data (qua favorite/server tu choi/
                            -- uoc luong chin som) -> hien GUI de biet vi sao Ripe khong tuot ve 0.
                            if (tonumber(miss[key]) or 0) >= 2 then stuck = stuck + 1 end
                        end
                    end
                end
            end
        end
    end
    -- cat duoi buffer: entry thua tu lan quet truoc -> bo (de #/ipairs dung so luong that)
    if singles then for i = #singles, nSingle + 1, -1 do singles[i] = nil end end
    if fruits then for i = #fruits, ripeF + 1, -1 do fruits[i] = nil end end
    -- HarvestStat cung tai dung 1 bang (bumpStat van mutate binh thuong)
    local hs = State.HarvestStat
    if type(hs) ~= "table" then hs = {}; State.HarvestStat = hs end
    hs.Total, hs.Ripe, hs.Single, hs.Stuck, hs.At = totalF, ripeF, nSingle, stuck, now
    hs.Held = held   -- KeepSeedForSell: so cay chin dang GIU (cho 30s cuoi weather moi hai)
    return singles, fruits
end

function Runtime.doDataHarvest(c)
    local tracked = Runtime.TrackedPlants
    if type(tracked) ~= "table" then return 0 end
    if not packet({ "Garden", "CollectFruit" }) then return 0 end
    local now = os.clock()
    local fired = Runtime.DataHarvestFiredAt
    local miss = Runtime.DataHarvestMiss
    -- guard chong phinh bo nho: dedup table qua to -> reset (chi ban lai 1 luot, vo hai).
    if Runtime.DataHarvestFiredCount and Runtime.DataHarvestFiredCount > 20000 then
        table.clear(fired); table.clear(miss); Runtime.DataHarvestFiredCount = 0
    end

    -- WATCHDOG DATA (fix "treo ~3 phut collect cham dan, rejoin thi lai vu vu"): rejoin nhanh lai vi
    -- client duoc server BAN LAI toan bo vuon (RequestGardens -> SyncAllGardens FULL RESYNC xoa ghost/
    -- data cu do miss event luc FPS thap nhieu tab). Tu lam dieu do dinh ky -> khoi can rejoin.
    local resyncEvery = tonumber(c.DataResyncEvery) or 90
    if resyncEvery > 0 then
        local lastSync = tonumber(Runtime.GardenDataReadyAt) or 0
        local lastReq = tonumber(Runtime.LastGardenResyncReq) or 0
        if (now - lastSync) >= resyncEvery and (now - lastReq) >= resyncEvery then
            Runtime.LastGardenResyncReq = now
            firePacket({ "Garden", "RequestGardens" })
            actionLog("AutoCollect", "RESYNC", "data vuon cu >" .. tostring(resyncEvery) .. "s -> xin server ban lai")
        end
    end

    local dedup = math.max(tonumber(c.DataHarvestDedup) or 4, 0)
    local maxPerCycle = math.max(tonumber(c.DataHarvestBatch) or 0, 0)
    if maxPerCycle <= 0 then maxPerCycle = math.max(tonumber(c.MaxPerCycle) or 120, 1) end
    local betweenDelay = tonumber(c.DataHarvestDelay)
    if not betweenDelay or betweenDelay < 0 then betweenDelay = tonumber(c.BetweenCollect) or 0 end

    -- PASS 1 (chi doc DATA): gom muc tieu CHIN + cap nhat State.HarvestStat cho GUI.
    -- DataHarvestRipeOnly = FIX GOC "cang treo cang cham": het spam remote vao qua non.
    local singles, fruits = Runtime.ScanHarvestTargets(c.DataHarvestRipeOnly ~= false)
    if not singles then return 0 end

    local collected = 0
    -- PASS 2: ban remote theo ngan sach. Muc tieu ban N lan ma van con trong data (qua favorite/
    -- server tu choi) -> gian dedup gap doi moi lan (4,8,16,32,64s) thay vi spam 4s mai mai.
    local function fireTarget(key, pid, fid)
        local m = tonumber(miss[key]) or 0
        -- moc thoi gian LAY MOI tung phat ban: vong dai (wait 1 frame/qua o cap thap) ma dung 'now'
        -- dau vong lam moc -> dedup bi ngan di dung bang do dai vong -> vong sau ban lai som.
        local t = os.clock()
        if (t - (fired[key] or 0)) < dedup * (2 ^ math.min(m, 4)) then return false end
        if fired[key] == nil then Runtime.DataHarvestFiredCount = (Runtime.DataHarvestFiredCount or 0) + 1 end
        fired[key] = t
        miss[key] = m + 1
        return firePacket({ "Garden", "CollectFruit" }, pid, fid)
    end
    -- Tru lui stat NGAY khi ban (optimistic): GUI dong Ripe tuot theo thoi gian thuc thay vi dung yen
    -- toi dau vong sau (vong dai 5-15s o cap thap). Sai so (server tu choi) duoc scan vong sau sua lai.
    local function bumpStat(field)
        local hs = State.HarvestStat
        if type(hs) == "table" then
            hs[field] = math.max((tonumber(hs[field]) or 1) - 1, 0)
            if field == "Ripe" then hs.Total = math.max((tonumber(hs.Total) or 1) - 1, 0) end
        end
    end
    -- UU TIEN HAI (chong chot): (0) cay KeepSeedForSell (KSF) HAI TRUOC HET - luc weather 30s cuoi chi con
    -- it thoi gian, phai hai mutated crop truoc keo weather het (chong yeu cau). (1) roi cay 1-LAN-HAI
    -- (PrioritizeSingleHarvest mac dinh TRUE), (2) trong moi nhom sort DO HIEM GIAM DAN (SeedData.Rarity).
    -- Sort tai cho tren buffer pool (khong cap phat bang moi - giu thanh qua RAM dot 3).
    local function harvestLess(a, b)
        local ak, bk = a.KSF and 1 or 0, b.KSF and 1 or 0
        if ak ~= bk then return ak > bk end   -- KSF truoc
        return (a.R or 0) > (b.R or 0)         -- roi do hiem giam dan
    end
    table.sort(singles, harvestLess)
    table.sort(fruits, harvestLess)
    local passes = (c.PrioritizeSingleHarvest ~= false) and { "S", "F" } or { "F", "S" }
    for _, pass in ipairs(passes) do
        if pass == "S" then
            for _, it in ipairs(singles) do
                if collected >= maxPerCycle then break end
                if fireTarget(tostring(it.P) .. ":", it.P, "") then
                    collected = collected + 1
                    bumpStat("Single")
                    if it.KSF then Runtime.KSFArm(it.Name, it.Mut) end   -- WEBHOOK: hai cay KeepCropsForSell (x4+dot bien) -> arm bao cao
                    if betweenDelay > 0 and not waitAlive(betweenDelay) then return collected end
                end
            end
        else
            for _, it in ipairs(fruits) do
                if collected >= maxPerCycle then break end
                if fireTarget(it.K, it.P, it.F) then
                    collected = collected + 1
                    bumpStat("Ripe")
                    if it.KSF then Runtime.KSFArm(it.Name, it.Mut) end   -- WEBHOOK: hai qua KeepCropsForSell (x4+dot bien) -> arm bao cao
                    if betweenDelay > 0 and not waitAlive(betweenDelay) then return collected end
                end
            end
        end
    end
    return collected
end

-- Override collect flow: stay in own garden, batch CollectFruit remote fires, no fruit teleport.
function Runtime.doAutoCollect()
    local c = CFG.AutoCollect
    if not (c and c.Enabled) then return end
    Runtime.SetupHarvestCache()
    if c.UseDataHarvestFallback ~= false then Runtime.SetupGardenTracker() end  -- tracker fill san -> san sang khi Nuke All xoa prompt
    -- KeepCropsForSell bat -> can tracker gia sell (setup 1 lan; khong khai thi bo qua cho nhe)
    if (type(c.KeepCropsForSell) == "table" and next(c.KeepCropsForSell) ~= nil)
        or (type(c.KeepSeedForSell) == "table" and next(c.KeepSeedForSell) ~= nil) then
        Runtime.SetupFruitStockTracker()
    end
    State.LastCollectCount = 0  -- early-return bên dưới -> nhịp loop dùng Delay đầy đủ (không lặp gấp)
    -- HARVEST nhuong cho CLAIM EVENT (seed spawn) VA MUA PET (chong yeu cau: "nhuong luon mua pet").
    -- Pet uu tien no -> di mua truoc roi hai tiep; con lai hai binh thuong.
    if Runtime.ShouldYieldForSeedPriority("AutoCollect") or Runtime.ShouldYieldForPetPriority("AutoCollect") then
        return
    end
    -- Wait For Mutations: nếu có list, CHỈ hái quả mang 1 trong các mutation này (chờ quả thường mutate).
    -- Rỗng = hái bình thường. So khớp dạng "chứa" để bắt cả combo (vd "Gold+Wet").
    local wantMutList, waitMutActive = {}, false
    for _, m in ipairs(type(c.WaitForMutations) == "table" and c.WaitForMutations or {}) do
        if type(m) == "string" and m ~= "" then
            table.insert(wantMutList, string.lower(m))
            waitMutActive = true
        end
    end
    if not packet({ "Garden", "CollectFruit" }) then
        logw("AutoCollect: thieu Networking.Garden.CollectFruit -> tat.")
        c.Enabled = false
        return
    end

    local plot = getPlot()
    if not plot then
        actionLog("AutoCollect", "SKIP", "no plot")
        return
    end
    if State.AntiStealEngaging or State.SellInProgress then
        actionLog("AutoCollect", "SKIP", State.SellInProgress and "selling" or "guard")
        return
    end
    -- STAY-OUT event (chong duyet): dang o ngoai cho seed -> KHONG keo ve vuon de hai; hai van chay
    -- binh thuong tu xa (data-harvest = remote Garden.CollectFruit, khong can dung trong plot).
    if c.StayInGarden ~= false and LocalPlayer:GetAttribute("IsInOwnGarden") ~= true
        and not Runtime.IsEventStayOut(CFG.AutoCollectDrops) then
        teleportToGardenHome("AutoCollect", 0.1)
    end
    if isInventoryFull() and c.PauseWhenFull ~= false then
        local _, cnt, mx = getFruitFill()
        actionLog("AutoCollect", "PAUSE_FULL", cnt and (tostring(cnt) .. "/" .. tostring(mx)) or "full")
        return
    end

    -- TOI UU RAM (dot 3): TAI DUNG bang candidates + pool entry giua cac vong. Vong hai lien tuc 0.1s
    -- truoc day cap phat 1 bang/qua MOI vong (~ca ngan bang/giay khi vuon day) -> GC theo frame o cap
    -- 7fps don khong kip -> heap no. Buffer chi thuoc task AutoCollect -> yield giua luc duyet van an toan.
    local candidates = Runtime.CollectCandBuf
    if not candidates then candidates = {}; Runtime.CollectCandBuf = candidates end
    local candN = 0
    local root = getRootPart()
    local inPlot = 0
    local tagCount = 0
    -- Duyệt CACHE (set) thay vì GetTagged toàn server mỗi vòng.
    for prompt in pairs(Runtime.HarvestPrompts) do
        tagCount = tagCount + 1
        if prompt:IsDescendantOf(plot) then
            inPlot = inPlot + 1
            local model = getHarvestPromptModel(prompt)
            if model then
                local pos = getHarvestPromptPosition(prompt)
                local promptParent = prompt.Parent
                local plantId = model:GetAttribute("PlantId")
                    or prompt:GetAttribute("PlantId")
                    or (promptParent and promptParent:GetAttribute("PlantId"))
                local fruitId = model:GetAttribute("FruitId")
                    or prompt:GetAttribute("FruitId")
                    or (promptParent and promptParent:GetAttribute("FruitId"))
                local mutOk = not waitMutActive
                if waitMutActive then
                    local mut = model:GetAttribute("Mutation")
                    if type(mut) == "string" then
                        local ml = string.lower(mut)
                        for _, w in ipairs(wantMutList) do
                            if ml:find(w, 1, true) then mutOk = true break end
                        end
                    end
                end
                -- KeepCropsForSell (prompt-path khi KHONG Nuke): GIU cay/qua toi khi x4 + dot bien moi hai.
                if mutOk then
                    local trk = plantId and Runtime.TrackedPlants and Runtime.TrackedPlants[plantId]
                    local cropName = (type(trk) == "table" and trk.PlantName) or model:GetAttribute("SeedName") or nil
                    if cropName then
                        local mutAttr = model:GetAttribute("Mutation")
                        local isMut = type(mutAttr) == "string" and mutAttr ~= ""
                        if Runtime.ShouldHoldCropHarvest(cropName, isMut) then
                            mutOk = false
                        end
                    end
                end
                if mutOk then
                -- CACHE diem gia tri theo prompt: size/mutation co dinh khi qua da chin -> khoi goi
                -- module FruitValueCalc lai 10 lan/giay (giam lag). Chi cache khi module DA san sang
                -- (neu chua, FruitCollectScore tra 0 tam -> khong cache de lan sau tinh lai dung gia).
                local sc = Runtime.HarvestScore[prompt]
                if sc == nil then
                    sc = Runtime.FruitCollectScore(model)
                    if type(Runtime.FruitValueCalc) == "function" then
                        Runtime.HarvestScore[prompt] = sc
                    end
                end
                -- pool entry: lay lai bang cu cua vong truoc, GHI DE DU MOI FIELD (field nil cung gan
                -- de xoa gia tri cu con sot) -> khong cap phat bang moi moi qua moi vong.
                candN = candN + 1
                local e = candidates[candN]
                if type(e) ~= "table" then e = {}; candidates[candN] = e end
                e.Prompt = prompt
                -- PlantId có thể nil (quả trên cây cao to) -> không bắn remote được,
                -- vẫn hái được bằng cách teleport tới + kích prompt thật.
                e.PlantId = plantId
                e.FruitId = fruitId
                e.Pos = pos
                e.Distance = root and pos and (root.Position - pos).Magnitude or 999999
                e.Score = sc
                e.RipeAt = Runtime.HarvestRipeAt[prompt] or 0  -- mốc quả chín (nhỏ = chín lâu hơn)
                local sName = model:GetAttribute("SeedName")
                e.IsSingle = Runtime.IsSingleHarvestSeed(sName)      -- cây single-harvest (SeedData)
                e.Rarity = Runtime.SeedRarityScore(sName)            -- độ hiếm (SeedData.Rarity) -> sort "rarity"
                end
            end
        end
    end
    -- cat duoi buffer: entry thua tu vong truoc -> bo (de #candidates/ipairs/sort dung so luong that)
    for i = #candidates, candN + 1, -1 do candidates[i] = nil end

    -- DATA-HARVEST (che do 3): hai bang DU LIEU vuon (remote Garden.CollectFruit tu TrackedPlants) -> KHONG can prompt.
    --   * #candidates==0 (Nuke All xoa prompt) -> tu dong ganh.
    --   * ForceDataHarvest==true -> ep dung che do 3 ke ca khi con prompt.
    -- Nguoc lai (con prompt + khong force) -> BO QUA, giu y nguyen flow prompt/remote cu ben duoi.
    if (#candidates == 0 or c.ForceDataHarvest == true) and c.UseDataHarvestFallback ~= false then
        Runtime.SetupGardenTracker()
        local got = Runtime.doDataHarvest(c)
        State.LastCollectCount = got
        if got > 0 then
            State.LastCollect = os.date("%H:%M:%S") .. " data=" .. tostring(got)
            actionLog("AutoCollect", "DATA", tostring(got) .. " fruit (no prompt -> remote)")
            if c.ReturnHomeAfterCollect ~= false then teleportToGardenHome("AutoCollect", 0.03) end
        end
        return
    end

    -- THỨ TỰ HÁI theo SortMode (chồng chốt: mặc định "rarity"):
    --   "rarity"   = ĐỘ HIẾM GIẢM DẦN (SeedData.Rarity); cùng độ hiếm -> quả đáng tiền trước, rồi gần trước.
    --   "oldest"   = CHÍN LÂU NHẤT múc trước (gom theo "bucket" thời gian chín; cùng nhóm tuổi thì
    --                quả XỊN trước, rồi gần trước).
    --   "valuable" = quả giá trị cao trước (cũ); cùng giá trị thì gần trước.
    --   "near"     = gần trước.
    local sortMode = tostring(c.SortMode or (c.PrioritizeValuable ~= false and "valuable" or "near")):lower()
    local prioSingle = c.PrioritizeSingleHarvest ~= false   -- MẶC ĐỊNH BẬT: cây single-harvest (SeedData.IsSingleHarvest) hái trước -> giải phóng slot
    local bucket = math.max(tonumber(c.RipeBucket) or 5, 0.1)  -- gom quả chín cách nhau < bucket giây vào 1 nhóm
    table.sort(candidates, function(a, b)
        -- (0) Quả của cây single-harvest hái TRƯỚC (mặc định bật) -> cây biến mất, mở ô trồng mới sớm.
        if prioSingle and a.IsSingle ~= b.IsSingle then
            return a.IsSingle == true
        end
        if sortMode == "rarity" then
            local ra, rb = (a.Rarity or 0), (b.Rarity or 0)
            if ra ~= rb then return ra > rb end          -- độ hiếm CAO hơn -> hái trước
            if a.Score ~= b.Score then return a.Score > b.Score end  -- cùng độ hiếm -> quả đáng tiền trước
            return a.Distance < b.Distance               -- rồi gần trước
        elseif sortMode == "oldest" then
            local ra = math.floor((a.RipeAt or 0) / bucket)
            local rb = math.floor((b.RipeAt or 0) / bucket)
            if ra ~= rb then return ra < rb end          -- nhóm chín CŨ hơn -> trước
            if a.Score ~= b.Score then return a.Score > b.Score end  -- cùng tuổi -> quả XỊN trước
            return a.Distance < b.Distance               -- rồi gần trước
        elseif sortMode == "near" then
            return a.Distance < b.Distance
        else  -- "valuable"
            if a.Score ~= b.Score then return a.Score > b.Score end
            return a.Distance < b.Distance
        end
    end)

    local collected = 0
    local prompted = 0
    local teleported = 0
    local maxPerCycle = math.max(tonumber(c.MaxPerCycle) or 120, 1)
    -- CHONG LAG: DataHarvestBatch > 0 -> chi hai ngan ay qua MOI VONG (trai deu tai cho muot).
    local harvestBatch = tonumber(c.DataHarvestBatch) or 0
    if harvestBatch > 0 then maxPerCycle = math.min(maxPerCycle, harvestBatch) end
    -- Nhip cho giua tung qua: uu tien DataHarvestDelay, khong thi dung BetweenCollect cu.
    local betweenDelay = tonumber(c.DataHarvestDelay)
    if not betweenDelay or betweenDelay <= 0 then betweenDelay = tonumber(c.BetweenCollect) or 0.03 end
    local maxTeleports = math.max(tonumber(c.MaxTeleportsPerCycle) or 4, 0)
    local maxValuableTp = math.max(tonumber(c.MaxValuableTeleports) or 8, 0)
    local minScore = tonumber(c.MinFruitScore) or 0

    for _, item in ipairs(candidates) do
        if collected >= maxPerCycle then break end
        -- Bỏ quả quá rẻ nếu chồng đặt MinFruitScore > 0.
        local tooCheap = (minScore > 0 and item.Score < minScore)
        if tooCheap and sortMode == "valuable" then
            break  -- CHỈ mode "valuable" mới sort giá-giảm-dần -> gặp quả rẻ là dừng luôn. Mode khác chỉ bỏ qua.
        end
        if (not tooCheap) and item.Prompt and item.Prompt:IsDescendantOf(workspace) then
            local pos = item.Pos or getHarvestPromptPosition(item.Prompt)
            local promptRange = tonumber(item.Prompt.MaxActivationDistance) or 10
            local rootNow = getRootPart()
            local dist = rootNow and pos and (rootNow.Position - pos).Magnitude or 999999
            local valuable = (item.Score or 0) > 0
            local farFromFruit = dist > math.max(promptRange - 1, 3)

            -- Quả xịn ở xa/trên cao (cây cao to) -> teleport lại gần để chắc chắn hái được.
            -- Đường này độc lập với TeleportToFruit (đang bị tắt cứng), bật bằng TeleportToValuable.
            if c.TeleportToValuable ~= false and valuable and teleported < maxValuableTp and farFromFruit then
                if teleportToHarvestPrompt(item.Prompt, c) then
                    teleported = teleported + 1
                    rootNow = getRootPart()
                    dist = rootNow and pos and (rootNow.Position - pos).Magnitude or 999999
                end
            elseif c.TeleportToFruit ~= false and teleported < maxTeleports and farFromFruit then
                if teleportToHarvestPrompt(item.Prompt, c) then
                    teleported = teleported + 1
                    rootNow = getRootPart()
                    dist = rootNow and pos and (rootNow.Position - pos).Magnitude or 999999
                end
            end

            if c.UsePromptHarvest == true then
                -- OPTION KIEU PROMPT: kich fireproximityprompt TUC THI (FirePromptFast - KHONG cho noi bo)
                -- -> game (HarvestPromptController:672/51-54) TU fire Garden.CollectFruit ho. Toc do hai =
                -- DataHarvestDelay (HA XUONG = NHANH HON). ensurePromptFireable bat lai prompt neu game disable
                -- (HideCollectProximityPrompts). LUU Y: van ton remote CollectFruit (game fire ho).
                Runtime.ensurePromptFireable(item.Prompt)
                if item.Prompt and Runtime.FirePromptFast(item.Prompt) then
                    collected = collected + 1
                    prompted = prompted + 1
                end
            else
                if item.PlantId and firePacket({ "Garden", "CollectFruit" }, item.PlantId, item.FruitId or "") then
                    collected = collected + 1
                end
                -- Đứng gần thì kích prompt thật (chắc ăn, kể cả khi remote trượt quả trên cao).
                local nearNow = dist <= (promptRange + 1)
                local allowPrompt = c.TriggerPromptFallback ~= false or (c.TeleportToValuable ~= false and valuable)
                if allowPrompt and nearNow and triggerHarvestPrompt(item.Prompt) then
                    prompted = prompted + 1
                end
            end

            if not waitAlive(betweenDelay) then
                return
            end
        end
    end

    State.LastCollectCount = collected  -- >0 -> nhịp loop lặp NGAY (hái liên tục); 0 -> nghỉ Delay
    local summary = ("tag=%s plot=%s id=%s ok=%s pr=%s tp=%s"):format(
        tostring(tagCount),
        tostring(inPlot),
        tostring(#candidates),
        tostring(collected),
        tostring(prompted),
        tostring(teleported)
    )
    State.LastCollect = os.date("%H:%M:%S") .. " " .. summary
    actionLog("AutoCollect", "DONE", summary)
    if collected > 0 and c.ReturnHomeAfterCollect ~= false then
        teleportToGardenHome("AutoCollect", 0.03)
    end
end

local function getDroppedItemPosition(item)
    if not item then return nil end
    if item:IsA("BasePart") then
        return item.Position
    end
    local anchor = item:FindFirstChild("PromptAnchor", true)
    if anchor and anchor:IsA("BasePart") then
        return anchor.Position
    end
    local visual = item:FindFirstChild("Visual", true)
    if visual then
        if visual:IsA("BasePart") then
            return visual.Position
        elseif visual:IsA("Model") then
            local primary = visual.PrimaryPart or visual:FindFirstChildWhichIsA("BasePart")
            if primary then return primary.Position end
        end
    end
    if item:IsA("Model") then
        local primary = item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart")
        if primary then return primary.Position end
        local ok, pivot = pcall(function()
            return item:GetPivot()
        end)
        if ok and pivot then
            return pivot.Position
        end
    end
    return nil
end

Runtime.IsLiveWorkspaceItem = function(item)
    return item and item.Parent and item:IsDescendantOf(workspace)
end

Runtime.GetItemPrompts = function(item)
    Runtime.EmptyItemPrompts = Runtime.EmptyItemPrompts or {}
    Runtime.ItemPromptCache = Runtime.ItemPromptCache or setmetatable({}, { __mode = "k" })
    Runtime.ItemPromptMissAt = Runtime.ItemPromptMissAt or setmetatable({}, { __mode = "k" })
    if item == nil then return Runtime.EmptyItemPrompts end
    if not Runtime.IsLiveWorkspaceItem(item) then
        Runtime.ItemPromptCache[item] = nil
        Runtime.ItemPromptMissAt[item] = nil
        return Runtime.EmptyItemPrompts
    end

    local cached = Runtime.ItemPromptCache[item]
    if cached then
        local valid = true
        for _, prompt in ipairs(cached) do
            if not (prompt and prompt.Parent and prompt:IsDescendantOf(workspace)) then
                valid = false
                break
            end
        end
        if valid then return cached end
        Runtime.ItemPromptCache[item] = nil
    end
    if os.clock() - (Runtime.ItemPromptMissAt[item] or -math.huge) < 0.2 then
        return Runtime.EmptyItemPrompts
    end

    local prompts = {}
    local ok, descendants = pcall(function()
        return item:GetDescendants()
    end)
    if not ok or type(descendants) ~= "table" then
        return Runtime.EmptyItemPrompts
    end

    for _, v in ipairs(descendants) do
        if v:IsA("ProximityPrompt") and v:IsDescendantOf(workspace) then
            prompts[#prompts + 1] = v
        end
    end
    if #prompts > 0 then
        Runtime.ItemPromptCache[item] = prompts
        Runtime.ItemPromptMissAt[item] = nil
    else
        Runtime.ItemPromptMissAt[item] = os.clock()
    end
    return prompts
end

Runtime.FirePromptFast = function(prompt, extraHold)
    if not (prompt and prompt:IsA("ProximityPrompt") and prompt:IsDescendantOf(workspace)) then
        return false
    end
    if type(fireproximityprompt) == "function" then
        return pcall(fireproximityprompt, prompt)
    end
    return triggerHarvestPrompt(prompt, extraHold)
end

-- TOUCH-CLAIM ("bluetooth" - chong nghi dung, xac nhan co so): DroppedItemController.lua KHONG co remote
-- claim tu client (chi RequestDrop=vut do + PickupFx=server bao ve) -> nhat drop/seed spawn deu do SERVER
-- tu detect. Neu server detect bang .Touched thi part se co TouchTransmitter (replicate ve client thay duoc)
-- -> firetouchinterest(HRP, part) gia su kien cham TU XA = toi la nhat lien, khong can teleport sat.
-- firetouchinterest la API EXECUTOR (khong phai remote game); server check khoang cach khi nhan touch hay
-- khong CHUA XAC NHAN trong source (khong co script server) -> best-effort, luon co fallback prompt/teleport.
-- Tra ve true neu DA ban touch (co TouchTransmitter + co ham); false = khong ban duoc (caller fallback).
Runtime.TryTouchClaim = function(item)
    local c = CFG.AutoCollectDrops
    if c and c.UseTouchClaim == false then return false end
    if not (item and item.Parent) then return false end
    local fti = Runtime.__FTI
    if fti == nil then
        fti = firetouchinterest
            or (type(getgenv) == "function" and getgenv().firetouchinterest)
            or false
        Runtime.__FTI = fti
    end
    if type(fti) ~= "function" then return false end
    local root = getRootPart()
    if not root then return false end
    -- CACHE part co TouchTransmitter theo item (weak-key): vong claim goi ham nay moi 0.04-0.05s,
    -- GetDescendants moi lan tren Model la phi CPU (fix "nhat cham"). Scan 1 lan/item roi dung lai;
    -- item destroy -> GC tu don key.
    Runtime.TouchPartCache = Runtime.TouchPartCache or setmetatable({}, { __mode = "k" })
    local parts = Runtime.TouchPartCache[item]
    if parts == nil then
        parts = {}
        if item:IsA("BasePart") then
            if item:FindFirstChildOfClass("TouchTransmitter") then parts[#parts + 1] = item end
        else
            for _, d in ipairs(item:GetDescendants()) do
                if d:IsA("BasePart") and d:FindFirstChildOfClass("TouchTransmitter") then
                    parts[#parts + 1] = d
                end
            end
        end
        Runtime.TouchPartCache[item] = parts
    end
    local fired = false
    for _, p in ipairs(parts) do
        if p.Parent then
            pcall(fti, root, p, 0)
            pcall(fti, root, p, 1)
            fired = true
        end
    end
    return fired
end

Runtime.ClaimDroppedItemUntilGone = function(item, c)
    if not Runtime.IsLiveWorkspaceItem(item) then
        return true, 0, "gone"
    end

    local preWait = math.max(tonumber(c and c.DropClaimPreWait) or 0.05, 0)
    if preWait > 0 and not waitAlive(preWait) then
        return false, 0, "stopped"
    end

    local maxWait = math.max(tonumber(c and c.DropClaimMaxWait) or 5, 0.5)
    local interval = math.max(tonumber(c and c.DropClaimFireInterval) or 0.05, 0.02)
    local noPromptWait = math.max(tonumber(c and c.DropClaimNoPromptWait) or 0.35, 0)
    local deadline = os.clock() + maxWait
    local noPromptDeadline = os.clock() + noPromptWait
    local fired = 0
    local sawPrompt = false

    while Runtime.IsLiveWorkspaceItem(item) and os.clock() < deadline do
        -- TOUCH-CLAIM fire-and-forget moi nhip. FIX "nhat it hon ban cu": truoc day o day con set
        -- sawPrompt=true -> item KHONG prompt (da so drop) khong duoc thoat som theo noPromptDeadline
        -- (0.35s) nua ma treo toi DropClaimMaxWait (5s) MOI ITEM -> ca chu ky nhat duoc it han.
        -- Gio touch chi BAN THEM, KHONG dung den nhip thoat -> timing y het ban cu.
        Runtime.TryTouchClaim(item)
        if not Runtime.IsLiveWorkspaceItem(item) then break end
        local prompts = Runtime.GetItemPrompts(item)
        if #prompts > 0 then
            sawPrompt = true
            for _, prompt in ipairs(prompts) do
                if Runtime.FirePromptFast(prompt) then
                    fired = fired + 1
                end
            end
        elseif sawPrompt or os.clock() >= noPromptDeadline then
            break
        end

        if not Runtime.IsLiveWorkspaceItem(item) then
            break
        end
        if not waitAlive(interval) then
            return false, fired, "stopped"
        end
    end

    local claimed = not Runtime.IsLiveWorkspaceItem(item)
    if claimed then
        if Runtime.ItemPromptCache then Runtime.ItemPromptCache[item] = nil end
        if Runtime.ItemPromptMissAt then Runtime.ItemPromptMissAt[item] = nil end
        if Runtime.TouchPartCache then Runtime.TouchPartCache[item] = nil end
        return true, fired, "claimed"
    end
    return false, fired, fired > 0 and "timeout" or "no prompt"
end

local function beginTemporaryMovementFreeze()
    local root = getRootPart()
    local hum = getHumanoid()
    local saved = {
        Root = root,
        Humanoid = hum,
        Anchored = root and root.Anchored,
        WalkSpeed = hum and hum.WalkSpeed,
        JumpPower = hum and hum.JumpPower,
        JumpHeight = hum and hum.JumpHeight,
        AutoRotate = hum and hum.AutoRotate,
    }
    pcall(function()
        if root then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            root.Anchored = true
        end
        if hum then
            hum.WalkSpeed = 0
            hum.JumpPower = 0
            hum.JumpHeight = 0
            hum.AutoRotate = false
        end
    end)
    return function()
        pcall(function()
            if saved.Root and saved.Root.Parent then
                saved.Root.Anchored = saved.Anchored == true
                saved.Root.AssemblyLinearVelocity = Vector3.zero
                saved.Root.AssemblyAngularVelocity = Vector3.zero
            end
            if saved.Humanoid and saved.Humanoid.Parent then
                if saved.WalkSpeed ~= nil then saved.Humanoid.WalkSpeed = saved.WalkSpeed end
                if saved.JumpPower ~= nil then saved.Humanoid.JumpPower = saved.JumpPower end
                if saved.JumpHeight ~= nil then saved.Humanoid.JumpHeight = saved.JumpHeight end
                if saved.AutoRotate ~= nil then saved.Humanoid.AutoRotate = saved.AutoRotate end
            end
        end)
    end
end

local function getDropText(item, attr)
    local value = item and item:GetAttribute(attr)
    if type(value) == "string" and value ~= "" then
        return value
    end
    return nil
end

local function getDroppedItemInfo(item)
    local display = getDropText(item, "DisplayName")
        or getDropText(item, "ItemName")
        or getDropText(item, "SeedPack")
        or getDropText(item, "SeedTool")
        or (item and item.Name)
        or "drop"
    local category = getDropText(item, "ItemCategory") or ""
    local isRainbow = item and item:GetAttribute("RainbowSeed") == true
        or hasRainbowText(display)
        or hasRainbowText(category)
        or hasRainbowText(getDropText(item, "SeedPack"))
        or hasRainbowText(getDropText(item, "SeedTool"))
    local isSeed = item and (item:GetAttribute("SeedPack") ~= nil or item:GetAttribute("SeedTool") ~= nil)
        or category == "Seeds"
        or category == "SeedPacks"
        or string.find(string.lower(display), "seed", 1, true) ~= nil
    local priority = 0
    if isSeed then
        priority = priority + 1000
    end
    if category == "SeedPacks" then
        priority = priority + 500
    end
    if isRainbow then
        priority = priority + 10000
    end
    return display, priority, isRainbow, isSeed
end

local function getSeedPackSpawnFolder()
    local map = workspace:FindFirstChild("Map")
    return map and map:FindFirstChild("SeedPackSpawnServerLocations")
end

local function getSeedPackSpawnInfo(spawn)
    if not spawn then
        return nil
    end
    local seedPack = spawn:GetAttribute("SeedPack")
    local isRainbow = spawn:GetAttribute("RainbowSeed") == true
    local isGold = spawn:GetAttribute("GoldSeed") == true
    local isMega = spawn:GetAttribute("MegaSeed") == true   -- source: SpawnSeedPackController u11 (seed moi)
    -- AUTO-DETECT seed dac biet TUONG LAI (UltraSeed...) -> van lay ma KHONG can update code.
    local special = nil
    if not (isRainbow or isGold or isMega) then
        special = Runtime.GetSeedSpawnSpecialAttr(spawn)
    end
    if not (isRainbow or isGold or isMega or special or (type(seedPack) == "string" and seedPack ~= "")) then
        return nil
    end

    local label
    local priority = 4000
    if isRainbow then
        label = "Rainbow Seed"
        priority = 20000
    elseif isMega then
        label = "Mega Seed"
        priority = 12000   -- Mega hiem -> uu tien cao (giua Gold va Rainbow)
    elseif isGold then
        label = "Gold Seed"
        priority = 8000
    elseif special then
        label = special     -- seed dac biet moi auto-detect
        priority = 10000
    else
        label = tostring(seedPack)
    end
    -- isEvent = seed dac biet (Rainbow/Gold/Mega/moi) -> dem la "event" de ban dem van di lay.
    local isEvent = isRainbow or isGold or isMega or (special ~= nil)
    if isEvent then
        Runtime.LastEventSeedSeenAt = os.clock()   -- moc "dang event" cho IsEventStayOut (o ngoai lay seed, khong ve nha)
    end
    return label, priority, isRainbow, isGold, isMega, isEvent
end

-- DANG EVENT -> O NGOAI LUON (chong duyet: "dang event thi cu lo di lay seed, khong can ve nha bao ve,
-- het event roi bao ve sau"): dem + vua thay seed event trong EventStayOutSeconds -> cac cho teleport-ve-nha
-- (AutoCollectDrops cuoi vong / AutoCollect StayInGarden / AntiPush keo ve) deu BO QUA -> dung tai cho doi
-- seed ke tiep (co the fast-claim/touch trong 55 studs, khoi ton 1 luot respawn ~1.5-3s). Het cua so
-- (ngay ra / lau khong thay seed event) -> ve nha bao ve nhu cu. Hai/ban van chay (remote tu xa).
Runtime.IsEventStayOut = function(c)
    c = c or CFG.AutoCollectDrops
    if c and c.StayOutDuringEvent == false then return false end
    if not isNight() then return false end
    local last = tonumber(Runtime.LastEventSeedSeenAt) or 0
    return (os.clock() - last) <= (tonumber(c and c.EventStayOutSeconds) or 150)
end

Runtime.RefreshDropRouteCosts = function(items, c)
    local root = getRootPart()
    if not root then
        return
    end

    local minSave = tonumber(c and c.SellFirstMinSave) or 12
    for _, entry in ipairs(items) do
        if typeof(entry.Pos) == "Vector3" then
            entry.Distance = (root.Position - entry.Pos).Magnitude
            entry.SortDistance = entry.Distance

            if c and c.UseSellFirst ~= false then
                local targetPos = Runtime.GetNearTargetPos(entry.Pos, c, root.Position) or entry.Pos
                local bestName, _, bestDist, save = Runtime.PickRouteButton(targetPos, c, function(dest)
                    return Runtime.GetNearTargetPos(entry.Pos, c, dest)
                end)
                if bestName and bestDist and save and save > minSave then
                    entry.SortDistance = bestDist
                    entry.RouteButton = bestName
                    entry.RouteSave = save
                end
            end
        end
    end
end

-- RESPAWN TELEPORT (source RespawnTo cua chong): connect CharacterAdded -> Health=0 -> cho respawn (timeout) ->
-- settle -> spam CFrame toi vi tri. Server reset vi tri khi respawn nen KHONG keo ve (may yeu/lag). Tra true neu xong.
-- onFrame (tuy chon): goi MOI FRAME trong luc spam CFrame -> caller ban claim (touch/prompt) NGAY trong luc
-- ghim vi tri (chong duyet #2: som hon ~0.3-0.5s, dung khoanh khac server ghi nhan minh dung canh seed).
function Runtime.RespawnTeleport(pos, frames, settle, onFrame)
    if typeof(pos) ~= "Vector3" then return false end
    local oldChar = LocalPlayer.Character
    local hum = oldChar and oldChar:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    local newChar
    local conn = LocalPlayer.CharacterAdded:Connect(function(ch) newChar = ch end)
    pcall(function() hum.Health = 0 end)  -- chet -> game auto respawn (CharacterAutoLoads)
    local deadline = os.clock() + 8       -- timeout chong treo neu khong respawn
    while isAlive() and (not newChar) and os.clock() < deadline do task.wait() end
    pcall(function() conn:Disconnect() end)
    if not newChar then return false end
    local hrp = newChar:FindFirstChild("HumanoidRootPart")
    if not hrp then
        local ok, r = pcall(function() return newChar:WaitForChild("HumanoidRootPart", 5) end)
        hrp = ok and r or nil
    end
    if not hrp then return false end
    if not waitAlive(math.max(tonumber(settle) or 0.1, 0)) then return false end
    local n = math.max(tonumber(frames) or 20, 1)
    for _ = 1, n do
        if not isAlive() then break end
        pcall(function() hrp.CFrame = CFrame.new(pos) end)
        if type(onFrame) == "function" then pcall(onFrame) end   -- ban claim ngay trong luc ghim vi tri
        task.wait()
    end
    return true
end

local function teleportToSeedPackSpawn(pos, c, onFrame)
    local root = getRootPart()
    if not (root and pos) then
        return false
    end
    local yOffset = tonumber(c and c.SeedSpawnYOffset) or 3
    local targetPos = pos + Vector3.new(0, yOffset, 0)
    -- RESPAWN teleport (chet->respawn->spam CFrame) neu bat -> server reset vi tri, KHONG bi keo ve.
    -- onFrame: ban claim (touch/prompt) NGAY trong luc spam frame (chong duyet #2).
    if c and c.UseRespawnTeleport == true then
        if Runtime.RespawnTeleport(targetPos, c.RespawnSpamFrames, c.RespawnSettleWait, onFrame) then
            return waitAlive(tonumber(c and c.SeedSpawnWait) or 0.12)
        end
        -- respawn that bai -> fallback xuong CFrame/tween ben duoi (khong bo claim).
    end
    -- TWEEN MƯỢT (chống giật/kéo về) nếu bật; KHÔNG thì set CFrame như cũ.
    if c and c.UseTweenTeleport then
        Runtime.SmartApproach(targetPos, pos, c)
        return waitAlive(tonumber(c and c.SeedSpawnWait) or 0.12)
    end
    root.CFrame = CFrame.new(targetPos)
    Runtime.FireTeleporterMimic(root.Position)
    return waitAlive(tonumber(c and c.SeedSpawnWait) or 0.12)
end

-- FAST CLAIM: fire THANG ProximityPrompt cua seed tu VI TRI HIEN TAI (KHONG teleport, khong respawn).
-- fireproximityprompt (trong triggerHarvestPrompt) la instant. Neu server khong kiem tra khoang cach cho
-- prompt seed thi claim luon -> nhat rat nhanh, khong ton respawn. Tra true neu seed bien mat (claim xong).
-- LUU Y: server co kiem khoang cach hay khong CHUA XAC NHAN trong source (script server khong co trong dump)
-- -> that bai (het cua so ma seed con) thi return false, caller tu fallback ve respawn-teleport cu.
Runtime.TryFastSeedClaim = function(item, c)
    if not (item and Runtime.IsLiveWorkspaceItem(item)) then return false end
    -- TOUCH-CLAIM TU XA fire-and-forget ("bluetooth"): KHONG cho them (giu timing cu). An thi cac
    -- check IsLiveWorkspaceItem ngay sau/vong ban prompt tu thay seed mat -> thoat lien.
    Runtime.TryTouchClaim(item)
    if not Runtime.IsLiveWorkspaceItem(item) then return true end
    local prompt = item:FindFirstChildWhichIsA("ProximityPrompt", true)
    if not prompt then return false end   -- khong co prompt trong workspace client -> khong fire tu xa duoc
    -- CHI thu fire khi DA trong tam server chap nhan claim (mac dinh 55 studs). Ngoai tam -> return false NGAY
    -- -> caller teleport toi (KHONG phi thoi gian fire vo ich). (Nguong ~55 studs la QUAN SAT CU, CHUA xac nhan
    -- trong source hop le hien tai -> chinh FastEventSeedRange neu can.)
    local root = getRootPart()
    local pos = getDroppedItemPosition(item)
    if root and pos and (root.Position - pos).Magnitude > (tonumber(c and c.FastEventSeedRange) or 55) then
        return false
    end
    local tryWindow = math.max(tonumber(c and c.FastEventSeedTryWindow) or 0.4, 0.1)
    local fInterval = math.max(tonumber(c and c.FastEventSeedFireInterval) or 0.05, 0.02)
    local deadline = os.clock() + tryWindow
    while Runtime.IsLiveWorkspaceItem(item) and os.clock() < deadline do
        if not (prompt and prompt:IsDescendantOf(workspace)) then
            prompt = item:FindFirstChildWhichIsA("ProximityPrompt", true)
        end
        if prompt then triggerHarvestPrompt(prompt) end   -- uu tien fireproximityprompt (instant), khong can teleport
        if not Runtime.IsLiveWorkspaceItem(item) then break end
        if not waitAlive(fInterval) then break end
    end
    return not Runtime.IsLiveWorkspaceItem(item)
end

Runtime.ClearDropScanRefs = function()
    if type(Runtime.DropItemsBuf) == "table" then table.clear(Runtime.DropItemsBuf) end
    if type(Runtime.DropEntryPool) == "table" then
        local active = tonumber(Runtime.DropPoolActiveCount) or 0
        for i = 1, active do
            local entry = Runtime.DropEntryPool[i]
            if type(entry) == "table" then table.clear(entry) end
        end
    end
    Runtime.DropPoolActiveCount = 0
end
table.insert(Runtime.Cleanups, Runtime.ClearDropScanRefs)

function Runtime.doAutoCollectDropsBody()
    local c = CFG.AutoCollectDrops
    if not (c and c.Enabled) then Runtime.ClearDropScanRefs(); return end
    c.__MovementOwner = "AutoCollectDrops"   -- task nay GIU khoa di chuyen -> khong tu nhuong, task khac nhuong
    -- UU TIEN CLAIM SEED EVENT (Rainbow/Gold/Mega Moon...): dang co seed spawn tren map thi KHONG de viec
    -- BAN chan claim. Truoc day "State.SellInProgress" chan CA vong nhat lan instant-claim -> dem moon bot
    -- vua hai vua ban lien tuc (SellInProgress bat hoai) -> seed event spawn dung luc dang ban bi BO QUA ->
    -- mat seed vao tay nguoi khac ("nhat rat it luc moon"). SellAll la REMOTE (khong di chuyen nhan vat) nen
    -- nhat seed chay song song an toan. AntiSteal van nhuong (dang danh trom moi that su can dung o cho).
    local hasPrioritySeed = Runtime.GetPrioritySeedSpawnLabel() ~= nil
    if State.AntiStealEngaging or (State.SellInProgress and not hasPrioritySeed) then
        Runtime.ClearDropScanRefs(); return
    end
    if not hasPrioritySeed and Runtime.ShouldYieldForPetPriority("AutoCollectDrops") then
        Runtime.ClearDropScanRefs()
        return
    end

    local root = getRootPart()
    local items = Runtime.DropItemsBuf
    if not items then items = {}; Runtime.DropItemsBuf = items end
    local pool = Runtime.DropEntryPool
    if not pool then pool = {}; Runtime.DropEntryPool = pool end
    local previousCount = #items
    for i = previousCount, 1, -1 do items[i] = nil end
    local previousActive = tonumber(Runtime.DropPoolActiveCount) or 0
    local itemCount = 0
    local folder = workspace:FindFirstChild("DroppedItems")
    if folder then
        for _, item in ipairs(folder:GetChildren()) do
            if item:GetAttribute("OwnerRestricted") ~= true or item:GetAttribute("DroppedBy") == LocalPlayer.UserId then
                local pos = getDroppedItemPosition(item)
                if pos then
                    local label, priority, isRainbow, isSeed = getDroppedItemInfo(item)
                    itemCount = itemCount + 1
                    local entry = pool[itemCount]
                    if not entry then entry = {}; pool[itemCount] = entry end
                    entry.Item = item
                    entry.Pos = pos
                    entry.Distance = root and (root.Position - pos).Magnitude or 999999
                    entry.SortDistance = nil
                    entry.RouteButton = nil
                    entry.RouteSave = nil
                    entry.Priority = priority
                    entry.Label = label
                    entry.Source = "Drop"
                    entry.Rainbow = isRainbow
                    entry.Gold = nil
                    entry.Mega = nil
                    entry.Event = nil
                    entry.Seed = isSeed
                    items[itemCount] = entry
                end
            end
        end
    end

    if c.IncludeSeedPackSpawns ~= false then
        local spawnFolder = getSeedPackSpawnFolder()
        if spawnFolder then
            for _, spawn in ipairs(spawnFolder:GetChildren()) do
                local label, priority, isRainbow, isGold, isMega, isEvent = getSeedPackSpawnInfo(spawn)
                if label then
                    local pos = getDroppedItemPosition(spawn)
                    if pos then
                        itemCount = itemCount + 1
                        local entry = pool[itemCount]
                        if not entry then entry = {}; pool[itemCount] = entry end
                        entry.Item = spawn
                        entry.Pos = pos
                        entry.Distance = root and (root.Position - pos).Magnitude or 999999
                        entry.SortDistance = nil
                        entry.RouteButton = nil
                        entry.RouteSave = nil
                        entry.Priority = priority
                        entry.Label = label
                        entry.Source = "SeedSpawn"
                        entry.Rainbow = isRainbow
                        entry.Gold = isGold
                        entry.Mega = isMega
                        entry.Event = isEvent
                        entry.Seed = true
                        items[itemCount] = entry
                    end
                end
            end
        end
    end

    -- ĐÊM: chỉ ra ngoài lấy Rainbow/Gold seed (event ưu tiên nhất); còn lại Ở NHÀ trong plot
    -- để chống trộm + thu hoạch (ý chồng). Ban ngày lấy bình thường.
    for i = previousActive, itemCount + 1, -1 do
        local old = pool[i]
        if old then table.clear(old) end
    end
    Runtime.DropPoolActiveCount = itemCount

    if c.StayHomeAtNight ~= false and isNight() then
        local keep = 0
        local total = #items
        for i = 1, total do
            local e = items[i]
            if e.Event or e.Rainbow or e.Gold or e.Mega then
                keep = keep + 1
                items[keep] = e
            else
                table.clear(e)
            end
        end
        for i = total, keep + 1, -1 do items[i] = nil end
    end

    if #items == 0 then
        State.LastDrop = os.date("%H:%M:%S") .. (folder and " none" or " no folder")
        return
    end

    local hasSeedSpawn = false
    for _, entry in ipairs(items) do
        if entry.Source == "SeedSpawn" then
            hasSeedSpawn = true
            break
        end
    end
    if hasSeedSpawn then
        State.SeedClaimUntil = math.max(
            tonumber(State.SeedClaimUntil) or 0,
            os.clock() + math.max((tonumber(c.Delay) or 0.5) + 0.75, 1)
        )
    end

    -- NHAY VE TAM MAP (cho Sell) bang cach BAM NUT truoc khi claim seed (giong hi.lua) -> server doi HOP LE,
    -- roi tinh khoang cach seed TU TAM -> tween NGAN toi tung seed -> KHONG di xuyen map -> het giat.
    local useSeedCenterSort = hasSeedSpawn
        and c.UseRespawnTeleport ~= true   -- respawn-teleport reset vi tri tung seed -> KHONG can tween ve tam truoc (thua)
        and c.UseTweenTeleport ~= false
        and c.UseSellFirst ~= false
        and c.UseSellCenterFirst ~= false
    if useSeedCenterSort then
        Runtime.GoSellCenter(c, "seed start")
        local r = getRootPart()
        local origin = (r and r.Position) or Runtime.GetSellCenterPos(c)
        if origin then
            for _, entry in ipairs(items) do
                entry.Distance = (origin - entry.Pos).Magnitude
            end
        end
    end
    Runtime.RefreshDropRouteCosts(items, c)

    table.sort(items, function(a, b)
        if useSeedCenterSort then
            local aSeed = a.Source == "SeedSpawn"
            local bSeed = b.Source == "SeedSpawn"
            if aSeed ~= bSeed then
                return aSeed
            end
            if aSeed and bSeed and c.SortSeedSpawnsByCenter ~= false and a.Distance ~= b.Distance then
                return a.Distance < b.Distance
            end
        end
        if c.PrioritizeRainbowSeed ~= false and a.Priority ~= b.Priority then
            return a.Priority > b.Priority
        end
        return (a.SortDistance or a.Distance) < (b.SortDistance or b.Distance)
    end)

    local picked = 0
    local promptedDrops = 0
    local seedSpawns = 0
    local rainbowSpawns = 0
    local maxPerCycle = math.max(tonumber(c.MaxPerCycle) or 30, 1)
    for _, entry in ipairs(items) do
        if picked >= maxPerCycle then break end
        local item = entry.Item
        if item and item.Parent then
            if entry.Source == "SeedSpawn" then
                State.SeedClaimInProgress = true
                State.SeedClaimUntil = os.clock() + math.max(tonumber(c.SeedClaimNoPromptWait) or 2.5, 1)
                State.LastDrop = os.date("%H:%M:%S") .. " claim " .. tostring(entry.Label or "seed")
                actionLog("AutoCollectDrops", "CLAIM", tostring(entry.Label or "seed"))
                -- FAST CLAIM (nhat mega/event seed nhanh nhu ben khac): seed event (Mega/Rainbow/Gold/dac biet)
                -- -> thu fire THANG prompt cua seed TU CHO DANG DUNG (khong teleport). Claim duoc thi BO qua
                -- respawn-teleport (~1-2s) -> nhat nhieu, rat nhanh. Khong duoc -> fallback teleport cu ben duoi.
                local fastClaimed = false
                if c.FastEventSeedClaim ~= false and entry.Event then
                    fastClaimed = Runtime.TryFastSeedClaim(item, c)
                    if fastClaimed then
                        actionLog("AutoCollectDrops", "FASTCLAIM", tostring(entry.Label or "seed"))
                    end
                end
                -- DI CHUYỂN TỚI SEED (tween mượt nếu UseTweenTeleport, hoặc set CFrame như cũ). Lúc ĐI:
                -- KHÔNG anchor (tween cần di chuyển; chồng đã giữ nền nên không rớt khi chưa anchor).
                -- CHỈ chạy khi fast-claim THẤT BẠI (seed còn) -> chưa claim được từ xa thì mới tới nơi claim.
                local unfreezeSeedClaim = nil
                if not fastClaimed then
                    -- CLAIM-BURST TRONG LUC RESPAWN-SPAM (chong duyet #2): moi frame ghim CFrame canh seed
                    -- -> ban touch + prompt LUON (FirePromptFast khong cho) -> claim som hon ~0.3-0.5s,
                    -- dung luc server ghi nhan vi tri moi. Prompt tim 1 lan, mat thi tim lai.
                    local burstPrompt = item:FindFirstChildWhichIsA("ProximityPrompt", true)
                    teleportToSeedPackSpawn(entry.Pos, c, function()
                        if not Runtime.IsLiveWorkspaceItem(item) then return end
                        Runtime.TryTouchClaim(item)
                        if not (burstPrompt and burstPrompt:IsDescendantOf(workspace)) then
                            burstPrompt = item:FindFirstChildWhichIsA("ProximityPrompt", true)
                        end
                        if burstPrompt then Runtime.FirePromptFast(burstPrompt) end
                    end)
                    -- TỚI NƠI rồi mới ANCHOR để đứng claim ổn định (hết giật). Giữ nền nên anchor KHÔNG rớt.
                    unfreezeSeedClaim = c.FreezeDuringSeedClaim ~= false and beginTemporaryMovementFreeze() or nil
                    -- CHỜ server (~30 khung/giây) ghi nhận vị trí mới rồi MỚI bắn. Trước đây teleport xong bắn liền
                    -- (chỉ 0.12s) -> server chưa thấy mình ở chỗ seed -> claim hụt rồi rời đi. (chồng yêu cầu sửa)
                    if not waitAlive(math.max(tonumber(c.SeedSettleWait) or 0.4, 0)) then
                        if unfreezeSeedClaim then pcall(unfreezeSeedClaim) end
                        State.SeedClaimInProgress = false
                        return
                    end
                    -- KẸP "bắn diện rộng" (logic AutoFireGui chồng test 100%): đã teleport tới sát spawn,
                    -- fire mọi prompt quanh nhân vật để chắc ăn claim được. Chỉ chạy lúc event này.
                    if c.BlastPromptsDuringSeedClaim ~= false
                        and (c.BlastPromptOnlyRainbowGold ~= true or entry.Rainbow or entry.Gold) then
                        local blastRoot = getRootPart()
                        local blastCenter = (blastRoot and blastRoot.Position) or entry.Pos
                        blastNearbyPrompts(blastCenter, c.BlastPromptRadius)   -- (LOG BLAST da tat: chi giu log CLAIM)
                    end
                end
                local function finishSeedClaimLock()
                    State.SeedClaimInProgress = false
                    if unfreezeSeedClaim then
                        unfreezeSeedClaim()
                        unfreezeSeedClaim = nil
                    end
                end
                seedSpawns = seedSpawns + 1
                if entry.Rainbow then
                    rainbowSpawns = rainbowSpawns + 1
                end

                -- Rainbow/Gold quý hơn -> giữ prompt LÂU HƠN cho chắc ăn claim được.
                -- Script tự detect qua attribute RainbowSeed/GoldSeed của spawn.
                local holdExtra = tonumber(c.SeedClaimHoldExtra) or 0.35
                if entry.Rainbow then
                    holdExtra = tonumber(c.SeedClaimHoldExtraRainbow) or holdExtra
                elseif entry.Gold then
                    holdExtra = tonumber(c.SeedClaimHoldExtraGold) or holdExtra
                end

                local prompt = item:FindFirstChildWhichIsA("ProximityPrompt", true)
                -- BAN LIEN TUC toi khi SEED BIEN MAT KHOI WORKSPACE (claim duoc) MOI qua seed khac (chong yeu cau):
                -- re-fire prompt DUNG seed + blast dien rong moi nhip. KHONG bo giua chung vi het gio ngan nhu truoc.
                -- CHI co timeout AN TOAN dai SeedClaimMaxWait de tranh ket vinh vien neu seed loi / bi nguoi khac gianh.
                local fireInterval = math.max(tonumber(c.SeedClaimFireInterval) or 0.04, 0.02)
                local safetyDeadline = os.clock() + math.max(tonumber(c.SeedClaimMaxWait) or 20, 3)
                State.SeedClaimUntil = safetyDeadline
                local firedAny = false
                local claimed = false
                -- seed con ton tai = item.Parent ~= nil VA van nam trong workspace
                while Runtime.IsLiveWorkspaceItem(item) and os.clock() < safetyDeadline do
                    -- TOUCH-CLAIM moi nhip: co TouchTransmitter thi day la kenh claim nhanh nhat
                    -- (khong phu thuoc prompt/khoang cach neu server nhan).
                    if Runtime.TryTouchClaim(item) then
                        firedAny = true
                        if not Runtime.IsLiveWorkspaceItem(item) then break end
                    end
                    if not (prompt and prompt:IsDescendantOf(workspace)) then
                        prompt = item:FindFirstChildWhichIsA("ProximityPrompt", true)
                    end
                    if prompt and triggerHarvestPrompt(prompt, holdExtra) then
                        firedAny = true
                    end
                    if c.BlastPromptsDuringSeedClaim ~= false
                        and (c.BlastPromptOnlyRainbowGold ~= true or entry.Rainbow or entry.Gold) then
                        local blastRoot = getRootPart()
                        local blastCenter = (blastRoot and blastRoot.Position) or entry.Pos
                        blastNearbyPrompts(blastCenter, c.BlastPromptRadius)
                    end
                    if not Runtime.IsLiveWorkspaceItem(item) then break end  -- seed da mat -> qua seed khac NGAY
                    if not waitAlive(fireInterval) then
                        finishSeedClaimLock()
                        return
                    end
                end
                claimed = not Runtime.IsLiveWorkspaceItem(item)
                if firedAny then promptedDrops = promptedDrops + 1 end

                finishSeedClaimLock()
                -- BO GRACE (chong yeu cau khong nghi): claim seed ke tiep NGAY. Giu SeedClaimUntil rat ngan
                -- de vong scan tiep tuc chay nhanh, KHONG pause giua 2 seed.
                State.SeedClaimUntil = os.clock() + 0.03
                picked = picked + 1
                local summary = ("try=%s pr=%s spawn=%s rainbow=%s %s"):format(
                    tostring(picked),
                    tostring(promptedDrops),
                    tostring(seedSpawns),
                    tostring(rainbowSpawns),
                    claimed and "claimed" or "retry"
                )
                State.LastDrop = os.date("%H:%M:%S") .. " " .. summary
                -- (LOG per-seed DONE/RETRY da tat theo yeu cau: claim chi in dung 1 dong CLAIM)
                -- KHÔNG return/teleport-home tại đây -> claim TIẾP các seed còn lại trong CÙNG 1 lượt
                -- (scan nhanh, lấy được nhiều), rồi teleport về nhà 1 LẦN ở cuối hàm.
                if not waitAlive(0.03) then return end
            else
                if not Runtime.IsLiveWorkspaceItem(item) then
                    -- item da bi claim boi nguoi khac trong luc scan -> qua item tiep theo ngay
                else
                    -- TOUCH-CLAIM fire-and-forget roi teleport NGAY (FIX "nhat it hon": truoc day cho
                    -- waitAlive(0.12) MOI ITEM x 200 item/chu ky = +24s/chu ky du touch khong an).
                    -- Touch ma an thi ClaimDroppedItemUntilGone thay item mat o check dau -> thoat lien.
                    Runtime.TryTouchClaim(item)
                    teleportNearPosition(entry.Pos, c)
                end

                local claimed, fireCount = Runtime.ClaimDroppedItemUntilGone(item, c)
                if fireCount > 0 then
                    promptedDrops = promptedDrops + 1
                end
                picked = picked + 1
                State.LastDrop = os.date("%H:%M:%S") .. " " .. tostring(entry.Label or "drop") .. " " .. (claimed and "claimed" or "retry")
                if not waitAlive(0.01) then return end
            end
        end
    end

    if picked > 0 then
        local summary = ("try=%s pr=%s spawn=%s rainbow=%s"):format(
            tostring(picked),
            tostring(promptedDrops),
            tostring(seedSpawns),
            tostring(rainbowSpawns)
        )
        State.LastDrop = os.date("%H:%M:%S") .. " " .. summary
        -- (LOG DONE cuoi chu ky da tat theo yeu cau: chi in dong CLAIM khi di claim)
        -- KHÔNG về nhà GIỮA event (chồng yêu cầu): còn seed spawn -> ở NGOÀI nhặt tiếp cho nhanh.
        -- + STAY-OUT (chồng duyệt): đêm event (vừa thấy seed event trong EventStayOutSeconds) cũng KHÔNG về
        -- dù tạm hết seed -> đứng chờ spawn kế tiếp gần chỗ đứng. Hết event mới về bảo vệ.
        if c.ReturnHomeAfterCollect ~= false and not Runtime.GetPrioritySeedSpawnLabel()
            and not Runtime.IsEventStayOut(c) then
            teleportToGardenHome("AutoCollectDrops", 0.03)
        end
    end
end

-- WRAPPER chong chay CHONG: doAutoCollectDrops gio duoc goi tu 2 nguon (vong quet loopTask +
-- hook InstantSpawnDetect goi TRUC TIEP khi spawn xuat hien) -> busy-flag de 2 nguon khong claim
-- dam nhau (2 luong cung teleport/claim = gianh ToolLock, giat). Nguon goi sau bi bo qua (vo hai:
-- luong dang chay se quet thay spawn moi vi scan lai moi vong).
function Runtime.doAutoCollectDrops()
    if Runtime.CollectDropsBusy then return end
    Runtime.CollectDropsBusy = true
    local ok, err = pcall(Runtime.doAutoCollectDropsBody)
    Runtime.CollectDropsBusy = false
    if not ok then error(err) end   -- nem tiep cho loopTask dem Errors/log nhu cu
end

-- Bán hết túi. force=true (bán do ĐẦY túi) -> bỏ qua nhường ưu tiên pet/seed: đầy túi là phải
-- bán ngay kẻo phí harvest, không đợi tame pet/claim seed nữa.
local function doAutoSell(force)
    local c = CFG.AutoSell
    if not (c and c.Enabled) then return end
    if not force and (Runtime.ShouldYieldForSeedPriority("AutoSell") or Runtime.ShouldYieldForPetPriority("AutoSell")) then
        return
    end
    actionLog("AutoSell", "START")
    if sellBlockedAtNight() then
        actionLog("AutoSell", "STAY_HOME_NIGHT", "Night.Value=true & SellAtNight=false; collect only")
        return
    end
    if not packet({ "NPCS", "SellAll" }) then
        actionLog("AutoSell", "ERROR", "missing Networking.NPCS.SellAll")
        logw("AutoSell: thiếu Networking.NPCS.SellAll -> tắt.")
        c.Enabled = false
        return
    end

    local hasPreview = packet({ "NPCS", "PreviewSellAll" }) ~= nil
    local fruitCount
    local preview
    if hasPreview then
        local ok
        ok, preview = firePacket({ "NPCS", "PreviewSellAll" })
        actionLog("AutoSell", "PREVIEW_HOME", summarizeResult(preview))
        if not ok then
            actionLog("AutoSell", "ERROR", "PreviewSellAll failed")
        elseif type(preview) == "table" then
            fruitCount = tonumber(preview.FruitCount) or 0
        end
    else
        actionLog("AutoSell", "WARN", "missing PreviewSellAll, fallback to local fruit tools")
    end

    if fruitCount == nil then
        fruitCount = countFruitTools()
        actionLog("AutoSell", "LOCAL_FRUIT_TOOLS", "count=" .. tostring(fruitCount))
    end

    if fruitCount <= 0 then
        actionLog("AutoSell", "STAY_HOME", "no fruit to sell")
        return
    end

    -- AUTO DOUBLE OR NOTHING: bật true -> bán kiểu HÊN XUI (gấp đôi or mất trắng) THAY cho bán thường.
    -- Fire TỪ XA giống SellAll (chồng đã xác nhận) -> KHÔNG teleport tới Steven (đỡ giật). Đã có fruit (>0).
    if c.DoubleOrNothing == true then
        Runtime.doDoubleOrNothingSell(c)
        return
    end

    -- QUAN TRỌNG: trước đây teleport tới Steven fail (vd không thấy Steven.HumanoidRootPart trên
    -- 1 số server) sẽ return luôn -> KHÔNG BAO GIỜ bán dù full bag -> acc không có tiền.
    -- PreviewSellAll/SellAll bắn được từ xa (preview ở nhà đã ra FruitCount/TotalValue), nên
    -- teleport CHỈ là best-effort: fail thì vẫn thử bán, không chặn nữa.
    if not teleportToStevenForSell() then
        actionLog("AutoSell", "WARN", "khong teleport duoc toi Steven -> van thu SellAll tu xa")
    end

    if hasPreview and type(preview) ~= "table" then
        local ok, previewNear = firePacket({ "NPCS", "PreviewSellAll" })
        actionLog("AutoSell", "PREVIEW_STEVEN", summarizeResult(previewNear))
        if not ok then
            return
        end
        if type(previewNear) == "table" then
            fruitCount = tonumber(previewNear.FruitCount) or fruitCount
            if fruitCount <= 0 then
                actionLog("AutoSell", "SKIP", "no fruit after teleport")
                return
            end
        end
    end

    if fruitCount > 100 then
        if not waitAlive(0.5) then return end
    end

    if not waitAlive(tonumber(c.PostPreviewWait) or 0.25) then return end
    if not waitAlive(tonumber(c.PreSellWait) or 0.5) then return end

    -- KEEP SEED FOR SELL WEBHOOK: chup tien TRUOC khi ban (dung cho bao cao loi cua lo giu-de-ban).
    local ksfMoneyBefore = tonumber(getSheckles()) or 0

    if c.UseDailyDeal ~= false and packet({ "NPCS", "CheckDailyDeal" }) and packet({ "NPCS", "UseDailyDealAll" }) then
        local okDeal, deal = firePacket({ "NPCS", "CheckDailyDeal" })
        if okDeal and type(deal) == "table" and deal.Available then
            local okDaily, daily = firePacket({ "NPCS", "UseDailyDealAll" })
            actionLog("AutoSell", "SELL_RESULT", "daily " .. summarizeResult(daily))
            if okDaily and type(daily) == "table" and daily.Success then
                State.LastSellAt = os.clock()  -- reset cooldown luồng timer (bán daily cũng tính)
                State.LastSell = os.date("%H:%M:%S") .. " daily sold=" .. tostring(daily.SoldCount) .. " price=" .. tostring(daily.SellPrice)
                actionLog("AutoSell", "DONE", ("daily sold=%s price=%s"):format(tostring(daily.SoldCount), tostring(daily.SellPrice)))
                Runtime.DoKeepSeedForSellReport(ksfMoneyBefore, tonumber(daily.SellPrice) or 0)
                return
            end
        end
    end

    -- RESET COOLDOWN NGAY KHI BAN (truoc khi doc ket qua): SellAll ban tu xa, server van xu ly du response
    -- thieu .Success / ok=false -> neu chi reset khi Success se bi BAN CHONG (double sell) vong sau. Dat moc
    -- TRUOC, neu Success thi refresh lai moc chinh xac ben duoi.
    State.LastSellAt = os.clock()
    local ok, res = firePacket({ "NPCS", "SellAll" })
    actionLog("AutoSell", "SELL_RESULT", summarizeResult(res))
    if ok and type(res) == "table" and res.Success then
        State.LastSellAt = os.clock()  -- mốc bán THẬT -> reset cooldown luồng timer (kể cả khi bán do đầy túi)
        State.LastSell = os.date("%H:%M:%S") .. " sold=" .. tostring(res.SoldCount) .. " price=" .. tostring(res.SellPrice)
        actionLog("AutoSell", "DONE", ("sold=%s price=%s"):format(tostring(res.SoldCount), tostring(res.SellPrice)))
        log(("Đã bán %s món, +%s"):format(tostring(res.SoldCount), tostring(res.SellPrice)))
        Runtime.DoKeepSeedForSellReport(ksfMoneyBefore, tonumber(res.SellPrice) or 0)   -- webhook loi KeepSeedForSell
    else
        State.LastSell = os.date("%H:%M:%S") .. " failed"
        actionLog("AutoSell", "ERROR", "SellAll failed or returned no Success")
    end
end

-- =========================================================================
-- AUTO DOUBLE OR NOTHING — bán kiểu ĐÁNH BẠC ở Steven (THAY cho SellAll thường khi bật).
-- XÁC NHẬN SOURCE:
--   * Remote: Networking.NPCS.DoubleOrNothing / CashOutDoubleOrNothing / AbandonDoubleOrNothing
--     (ReplicatedStorage.SharedModules.Networking.lua:300-302, đều :Response -> server trả kết quả).
--   * Flow client: Players...NPCController/Sell_Steven.lua:1041-1144 -> chỉ :Fire() rồi ĐỌC kết quả
--     server trả về: { Busted, Won, Wins, Pot, Reason }; CashOut trả { Success, Wins, SoldCount, SellPrice }.
-- KẾT QUẢ DO SERVER RANDOM (logic random nằm ở server, KHÔNG có trong source) -> KHÔNG thể 100% thắng.
--   Busted = MẤT TRẮNG cả túi. Won = pot x2 mỗi lượt. Thắng đủ Target Wins -> CashOut chốt lời.
-- =========================================================================
-- Rút gọn số tiền cho gọn (1.23k / 4.56m / 7.89b). Gắn Runtime.* (không thêm local main-chunk).
function Runtime.FmtMoney(v)
    v = tonumber(v)
    if not v then return "-" end
    if v >= 1e9 then return string.format("%.2fb", v / 1e9)
    elseif v >= 1e6 then return string.format("%.2fm", v / 1e6)
    elseif v >= 1e3 then return string.format("%.2fk", v / 1e3) end
    return tostring(math.floor(v))
end

-- TOAST WIN NHỎ: mỗi lần thắng hiện 1 thông báo giữa trên màn hình, 2s sau tự ẩn.
-- TÁI SỬ DỤNG 1 ScreenGui + 1 frame (chỉ bật/tắt Visible) -> KHÔNG tạo/destroy liên tục -> không leak.
-- Token reset: mỗi lần win lại đếm 2s từ đầu, chỉ timer mới nhất mới được ẩn.
function Runtime.ShowWinToast(text, color)
    pcall(function()
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        if not playerGui then return end
        local gui = Runtime.WinToastGui
        if not (gui and gui.Parent) then
            gui = Instance.new("ScreenGui")
            gui.Name = "KaitunWinToast"
            gui.ResetOnSpawn = false
            gui.IgnoreGuiInset = true
            gui.DisplayOrder = 1000
            gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            gui.Parent = playerGui
            Runtime.WinToastGui = gui

            local frame = Instance.new("Frame")
            frame.Name = "Toast"
            frame.AnchorPoint = Vector2.new(0.5, 0)
            frame.Position = UDim2.new(0.5, 0, 0.12, 0)
            frame.Size = UDim2.fromOffset(320, 48)
            frame.BackgroundColor3 = Color3.fromRGB(16, 20, 28)
            frame.BackgroundTransparency = 0.1
            frame.BorderSizePixel = 0
            frame.Visible = false
            frame.Parent = gui
            Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)
            local st = Instance.new("UIStroke", frame)
            st.Color = Color3.fromRGB(94, 234, 212); st.Thickness = 1.5; st.Transparency = 0.3

            local lbl = Instance.new("TextLabel")
            lbl.Name = "Label"
            lbl.BackgroundTransparency = 1
            lbl.Size = UDim2.fromScale(1, 1)
            lbl.Font = Enum.Font.GothamBold
            lbl.TextSize = 19
            lbl.TextColor3 = Color3.fromRGB(94, 234, 212)
            lbl.Text = ""
            lbl.Parent = frame
            Runtime.WinToastFrame = frame
            Runtime.WinToastLabel = lbl
            table.insert(Runtime.Cleanups, function()
                if Runtime.WinToastGui then
                    pcall(function() Runtime.WinToastGui:Destroy() end)
                    Runtime.WinToastGui = nil
                end
            end)
        end

        local frame = Runtime.WinToastFrame
        local lbl = Runtime.WinToastLabel
        if not (frame and lbl) then return end
        lbl.Text = tostring(text)
        lbl.TextColor3 = color or Color3.fromRGB(94, 234, 212)
        frame.Visible = true
        Runtime.WinToastToken = (Runtime.WinToastToken or 0) + 1
        local token = Runtime.WinToastToken
        task.delay(2, function()
            if Runtime.WinToastToken == token and Runtime.WinToastFrame then
                Runtime.WinToastFrame.Visible = false
            end
        end)
    end)
end

function Runtime.doDoubleOrNothingSell(c)
    c = c or CFG.AutoSell or {}
    if not packet({ "NPCS", "DoubleOrNothing" }) then
        actionLog("AutoSell", "ERROR", "missing Networking.NPCS.DoubleOrNothing -> ban thuong")
        logw("DoubleOrNothing: thiếu remote NPCS.DoubleOrNothing -> tắt, quay về bán thường.")
        c.DoubleOrNothing = false
        return
    end
    local target = math.clamp(math.floor(tonumber(c.DoubleOrNothingTargetWins) or 1), 1, 5)
    actionLog("AutoSell", "DON_START", "target=" .. tostring(target) .. " wins (gap doi or mat trang)")

    local guard = 0
    while isAlive() do
        guard = guard + 1
        -- chặn lặp vô hạn: chỉ cần tối đa 'target' lượt thắng + vài lượt đệm.
        if guard > target + 3 then
            actionLog("AutoSell", "DON_ABORT", "vuot so luot du kien -> abandon")
            if packet({ "NPCS", "AbandonDoubleOrNothing" }) then
                pcall(firePacket, { "NPCS", "AbandonDoubleOrNothing" })
            end
            return
        end

        local ok, res = firePacket({ "NPCS", "DoubleOrNothing" })
        if not ok or type(res) ~= "table" then
            -- Có thể server yêu cầu đang trong phiên Steven / điều kiện khác (logic server, ko thấy source).
            actionLog("AutoSell", "DON_ERROR", "fire fail " .. summarizeResult(res))
            return
        end

        if res.Busted then
            State.LastSellAt = os.clock()  -- mat trang ca tui = tui da rong (coi nhu da ban) -> reset cooldown, tranh ban chong
            State.LastSell = os.date("%H:%M:%S") .. " DoubleOrNothing BUSTED (mat trang ca tui)"
            actionLog("AutoSell", "DON_BUSTED", "thua -> mat trang ca tui")
            return
        end

        if not res.Won then
            -- vd Reason = "NoFruits" (hết quả để cược) hoặc lý do server khác.
            actionLog("AutoSell", "DON_STOP", "reason=" .. tostring(res.Reason))
            return
        end

        local wins = tonumber(res.Wins) or 0
        local pot  = tonumber(res.Pot) or 0
        actionLog("AutoSell", "DON_WIN", ("wins=%d/%d pot=%s"):format(wins, target, tostring(pot)))
        -- TOAST: mỗi lần thắng hiện thông báo nhỏ "WIN x.. +tiền", 2s tự ẩn.
        Runtime.ShowWinToast(("\u{1F389} WIN x%d  +%s"):format(wins, Runtime.FmtMoney(pot)))

        -- Đủ số lượt thắng mong muốn -> CHỐT LỜI (cash out), không cược nữa.
        if wins >= target then
            if not packet({ "NPCS", "CashOutDoubleOrNothing" }) then
                actionLog("AutoSell", "DON_ERROR", "missing CashOutDoubleOrNothing remote")
                return
            end
            if not waitAlive(0.3) then return end
            local okC, cashRes = firePacket({ "NPCS", "CashOutDoubleOrNothing" })
            if okC and type(cashRes) == "table" and cashRes.Success then
                State.LastSellAt = os.clock()  -- mốc bán THẬT -> reset cooldown luồng timer.
                State.LastSell = os.date("%H:%M:%S") .. (" DON cashout wins=%s sold=%s price=%s"):format(
                    tostring(cashRes.Wins), tostring(cashRes.SoldCount), tostring(cashRes.SellPrice))
                actionLog("AutoSell", "DON_CASHOUT", ("wins=%s sold=%s price=%s"):format(
                    tostring(cashRes.Wins), tostring(cashRes.SoldCount), tostring(cashRes.SellPrice)))
                log(("DoubleOrNothing chot loi: thang %s luot, ban %s mon, +%s"):format(
                    tostring(cashRes.Wins), tostring(cashRes.SoldCount), tostring(cashRes.SellPrice)))
            else
                actionLog("AutoSell", "DON_ERROR", "cashout fail " .. summarizeResult(cashRes))
            end
            return
        end

        -- Chưa đủ target -> cược tiếp lượt sau (server giữ session theo các lần fire). Nghỉ nhẹ.
        if not waitAlive(0.4) then return end
    end
end

-- Bán an toàn: chặn 2 luồng bán cùng lúc (timer + đầy túi gọi chung 1 chỗ)
-- Bán xong tự teleport về chỗ cũ (về nhà) để anti-steal làm việc liền.
local function runSellSafe(reason, force)
    -- Mail Instead Of Sell: đang bật gửi trái cây kiểu "gửi thay vì bán" -> KHÔNG bán,
    -- để dồn trái cây cho AutoMailFruits gửi đi.
    if CFG.AutoMailFruits and CFG.AutoMailFruits.Enabled and CFG.AutoMailFruits.InsteadOfSell then
        actionLog("AutoSell", "SKIP", "mail instead of sell")
        return
    end
    if not force and (Runtime.ShouldYieldForSeedPriority("AutoSell") or Runtime.ShouldYieldForPetPriority("AutoSell")) then
        return
    end
    if State.SellInProgress then
        actionLog("AutoSell", "BUSY", tostring(reason or ""))
        return
    end
    State.SellInProgress = true
    local c = CFG.AutoSell or {}
    local root = getRootPart()
    -- Ve CUNG o plot (StandCF) voi Guard/AntiPush -> ban xong khong keo ve SpawnPoint roi bi Guard keo lai -> het giat.
    local homeCF = Runtime.GetStandCF() or getGardenHomeCFrame() or (root and root.CFrame)
    local ok, err = pcall(doAutoSell, force)
    if c.ReturnHomeAfterSell ~= false and homeCF then
        local rootAfter = getRootPart()
        if rootAfter then
            rootAfter.CFrame = homeCF
            actionLog("AutoSell", "RETURN_HOME", "garden")
        end
    end
    State.SellInProgress = false
    if not ok then
        logw("AutoSell", err)
    end
end

-- Đầy túi (FruitCount/MaxFruitCapacity) thì bán NGAY, khỏi đợi hết Delay
local function doSellWhenFull()
    local c = CFG.AutoSell
    if not (c and c.Enabled and c.SellWhenFull ~= false) then return end
    -- ĐẦY túi -> bán ngay, KHÔNG nhường ưu tiên pet/seed (force) để khỏi kẹt "full bag mà ko sell".
    if sellBlockedAtNight() then return end
    -- CHONG DOUBLE SELL: vua ban xong (LastSellAt gan day) thi getFruitFill co the con doc gia tri CU (chua ve 0)
    -- -> bo qua force-sell trong MinResellGap giay de tui cap nhat -> khong ban chong lien tuc.
    local lastSellAt = tonumber(State.LastSellAt)
    if lastSellAt and (os.clock() - lastSellAt) < (tonumber(c.MinResellGap) or 3) then return end
    if State.PendingForceSellReason then
        local reason = State.PendingForceSellReason
        State.PendingForceSellReason = nil
        actionLog("AutoSell", "FORCE_TRIGGER", tostring(reason))
        runSellSafe(reason, true)
        return
    end
    local ratio, count, max = getFruitFill()
    if not ratio then return end
    State.FruitFill = tostring(count) .. "/" .. tostring(max)
    if ratio >= (tonumber(c.FullThreshold) or 0.95) then
        actionLog("AutoSell", "FULL_TRIGGER", State.FruitFill)
        runSellSafe("inventory full", true)
    end
end

-- Theo dõi túi đầy bằng tín hiệu THẬT của game:
--   1) attribute FruitCount / MaxFruitCapacity đổi (InventoryController/Main.lua dòng 2687)
--   2) server bắn notification "Your inventory is full" (NotificationController.lua dòng 217+833)
-- -> phản ứng TỨC THÌ, không phải chờ vòng lặp poll.
-- ============================================================
-- STRIP CHAR NGUOI KHAC (dot 4 - ha RAM): phu kien/quan ao/mat cua nguoi choi khac = mesh + texture
-- nang ma minh khong can nhin. Destroy Accessory/Shirt/Pants/Decal/SurfaceAppearance cua HO (TUYET DOI
-- khong dung char MINH; giu nguyen HumanoidRootPart/Humanoid -> AntiSteal van teleport + danh trom
-- binh thuong). Nguoi moi vao / respawn -> strip tiep qua CharacterAdded. Knob: FpsBoost.StripOtherCharacters.
-- ============================================================
Runtime.StripCharacterJunk = function(char)
    if not char then return end
    local myChar = LocalPlayer.Character
    if myChar and char == myChar then return end
    pcall(function()
        for _, d in ipairs(char:GetDescendants()) do
            -- Đợt 16 thêm: BillboardGui (bảng tên/level trên đầu HỌ - có render) + Script/ModuleScript
            -- (dump: Animate/Health/Billboard_UI/GalaxyTexture - LocalScript trong char NGƯỜI KHÁC không
            -- chạy trên client mình = xác trơ chỉ tốn RAM instance). Humanoid/RootPart giữ nguyên.
            if d:IsA("Accessory") or d:IsA("Shirt") or d:IsA("Pants")
                or d:IsA("ShirtGraphic") or d:IsA("CharacterMesh")
                or d:IsA("Decal") or d:IsA("SurfaceAppearance")
                or d:IsA("BillboardGui") or d:IsA("Script") or d:IsA("ModuleScript") then
                pcall(function() d:Destroy() end)
            end
        end
    end)
end
Runtime.SetupCharacterStrip = function()
    if Runtime.CharStripReady then return end
    local c = CFG.FpsBoost
    if not (c and c.Enabled) then return end
    if c.StripOtherCharacters == false and c.StripSelfCharScripts == false then return end
    Runtime.CharStripReady = true
    Runtime.CharStripConnections = Runtime.CharStripConnections or {}
    local function disconnectPlayer(plr)
        local conn = Runtime.CharStripConnections[plr]
        if conn then pcall(conn.Disconnect, conn) end
        Runtime.CharStripConnections[plr] = nil
    end
    local function hookPlayer(plr)
        if plr == LocalPlayer then return end
        disconnectPlayer(plr)
        if plr.Character then Runtime.StripCharacterJunk(plr.Character) end
        local conn = plr.CharacterAdded:Connect(function(ch)
            if waitAlive(1) then Runtime.StripCharacterJunk(ch) end
        end)
        Runtime.CharStripConnections[plr] = conn
    end
    if c.StripOtherCharacters ~= false then
        for _, plr in ipairs(Players:GetPlayers()) do hookPlayer(plr) end
        local pconn = Players.PlayerAdded:Connect(hookPlayer)
        local rconn = Players.PlayerRemoving:Connect(disconnectPlayer)
        table.insert(Runtime.Cleanups, function()
            pcall(pconn.Disconnect, pconn)
            pcall(rconn.Disconnect, rconn)
            for plr in pairs(Runtime.CharStripConnections) do disconnectPlayer(plr) end
        end)
    end
    -- Đợt 16: SCRIPT trong char MÌNH (dump workspace: Animate/Billboard_UI/GalaxyTexture) - server
    -- re-clone MỖI respawn, mà respawn-teleport spam liên tục khi claim seed. Animate chạy animation
    -- mỗi nhịp = CPU; Billboard_UI = BillboardGui render. Destroy theo TÊN, không đụng Humanoid/
    -- RootPart/Tool/Health -> di chuyển + equip tool + chết-respawn vẫn nguyên.
    if c.StripSelfCharScripts ~= false then
        local selfJunk = { Animate = true, Billboard_UI = true, GalaxyTexture = true }
        local function stripSelf(ch)
            if not ch then return end
            pcall(function()
                for _, child in ipairs(ch:GetChildren()) do
                    if selfJunk[child.Name] then
                        pcall(function() child:Destroy() end)
                    end
                end
            end)
        end
        stripSelf(LocalPlayer.Character)
        local sconn = LocalPlayer.CharacterAdded:Connect(function(ch)
            -- đợi 1 nhịp ngắn cho server clone xong đám script rồi lột (respawn-spam vẫn kịp)
            if waitAlive(0.5) then stripSelf(ch) end
        end)
        table.insert(Runtime.Cleanups, function() pcall(sconn.Disconnect, sconn) end)
    end
    actionLog("FpsBoost", "CHAR_STRIP", "lot char nguoi khac + script char minh ON")
end

-- ANTI-PUSH (chống wheelbarrow/va chạm đẩy ra khỏi plot). Push là VẬT LÝ -> khóa client-side.
-- Heartbeat: ban đêm + đang RẢNH (không claim seed/bán/đánh trộm) -> zero vận tốc; bị đẩy lệch nhà -> kéo về.
function Runtime.SetupAntiPush()
    local c = CFG.AntiPush
    if not (c and c.Enabled) then return end
    local conn
    local nextCheckAt = 0
    conn = RunService.Heartbeat:Connect(function()
        local cfg = CFG.AntiPush
        if not (cfg and cfg.Enabled) then return end
        if not isAlive() then return end
        local heartbeatNow = os.clock()
        if heartbeatNow < nextCheckAt then return end
        nextCheckAt = heartbeatNow + math.max(tonumber(cfg.CheckInterval) or 0.15, 0.05)
        if cfg.OnlyAtNight ~= false and not isNight() then return end
        -- ĐANG claim seed / MUA PET / bán / đánh trộm -> KHÔNG ghì-kéo-về (kẻo hỏng claim/mua). Kể cả khoảng
        -- đệm ngắn giữa 2 seed (SeedClaimUntil) + sau mua pet (PetTameUntil) -> không kéo về giữa chừng.
        local nowc = heartbeatNow
        if State.SeedClaimInProgress or State.PetTameInProgress or State.SellInProgress or State.AntiStealEngaging
            or (tonumber(State.SeedClaimUntil) or 0) > nowc or (tonumber(State.PetTameUntil) or 0) > nowc then
            return
        end
        -- STAY-OUT event (chong duyet): dang dung ngoai cho seed event -> KHONG keo ve nha (keo ve la
        -- mat loi the fast-claim seed ke tiep). Het cua so event thi keo ve nhu cu.
        if type(Runtime.IsEventStayOut) == "function" and Runtime.IsEventStayOut(CFG.AutoCollectDrops) then
            return
        end
        local root = getRootPart()
        if not root or root.Anchored then return end
        -- triệt momentum của cú đẩy
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        -- bị đẩy lệch khỏi nhà quá MaxDrift -> kéo về.
        -- DÙNG CHUNG đích với StandInOwnGardenCell (State.StandCF = ô plot) để 2 cơ chế KHÔNG đánh nhau
        -- gây giật/kéo về SpawnPoint. Chưa có StandCF (chưa chọn ô) -> fallback SpawnPoint như cũ.
        local homeCF = State.StandCF or getGardenHomeCFrame()
        if homeCF then
            local drift = (root.Position - homeCF.Position).Magnitude
            if drift > (tonumber(cfg.MaxDrift) or 6) then
                root.CFrame = homeCF
                root.AssemblyLinearVelocity = Vector3.zero
                State.LastAntiPush = os.date("%H:%M:%S") .. (" keo ve %.0f"):format(drift)
            end
        end
    end)
    table.insert(Runtime.Cleanups, function()
        if conn then pcall(function() conn:Disconnect() end) end
    end)
end

local function setupInventoryWatcher()
    local c = CFG.AutoSell or {}
    local connections = {}

    local function triggerSell(reason)
        if c.SellWhenFull == false then return end
        -- ĐẦY túi -> bán ngay (force), không nhường ưu tiên pet/seed.
        if sellBlockedAtNight() then
            actionLog("AutoSell", "FULL_NIGHT", "đầy túi nhưng đêm, chờ sáng (" .. tostring(reason) .. ")")
            return
        end
        State.PendingForceSellReason = reason
        actionLog("AutoSell", "QUEUE_FORCE", tostring(reason))
    end

    -- cập nhật GUI + bán ngay khi quả chạm ngưỡng đầy
    local function onFruitChanged()
        local ratio, count, max = getFruitFill()
        if count then
            State.FruitFill = tostring(count) .. "/" .. tostring(max)
        end
        if ratio and ratio >= (tonumber(c.FullThreshold) or 0.95) then
            triggerSell("đầy túi (FruitCount)")
        end
    end

    table.insert(connections, LocalPlayer:GetAttributeChangedSignal("FruitCount"):Connect(onFruitChanged))
    table.insert(connections, LocalPlayer:GetAttributeChangedSignal("MaxFruitCapacity"):Connect(onFruitChanged))

    -- tín hiệu CHUẨN nhất: server tự báo đầy túi
    local note = packet({ "Notification" })
    local hooked = false
    if note then
        local ok, conn = pcall(function()
            return note.OnClientEvent:Connect(function(message)
                if type(message) == "string" and string.find(message, "Your inventory is full", 1, true) then
                    actionLog("AutoSell", "NOTIFY_FULL", "server báo đầy túi -> đi bán")
                    triggerSell("server báo đầy túi")
                end
            end)
        end)
        if ok and conn then
            table.insert(connections, conn)
            hooked = true
        end
    end
    if not hooked then
        logw("InventoryWatcher: không hook được Networking.Notification.OnClientEvent (vẫn còn poll FruitCount)")
    end

    onFruitChanged()

    table.insert(Runtime.Cleanups, function()
        for _, conn in ipairs(connections) do
            pcall(function()
                conn:Disconnect()
            end)
        end
    end)
end

-- Server báo "You can't plant more" (hoặc tương tự) -> đánh dấu vườn đầy (tín hiệu THẬT).
-- Remote thật: Networking.Notification ("Notify", String, Any) - Networking.lua:16.
-- LƯU Ý: chuỗi text do SERVER gửi, KHÔNG có trong client source nên khớp tương đối
-- (message chứa "plant" + một trong more/full/room/space/limit). An toàn vì chỉ set 1 cờ.
Runtime.SetupPlantFullWatcher = function()
    local note = packet({ "Notification" })
    if not note then
        logw("PlantFullWatcher: không thấy Networking.Notification")
        return
    end
    local ok, conn = pcall(function()
        return note.OnClientEvent:Connect(function(message)
            if type(message) ~= "string" then return end
            local m = string.lower(message)
            if string.find(m, "plant", 1, true)
                and (string.find(m, "more", 1, true)
                    or string.find(m, "full", 1, true)
                    or string.find(m, "room", 1, true)
                    or string.find(m, "space", 1, true)
                    or string.find(m, "limit", 1, true)) then
                Runtime.MarkPlotFull()
                State.LastShovelReplace = os.date("%H:%M:%S") .. " plot full (server)"
                actionLog("AutoPlant", "PLOT_FULL", compactText(message, 60))
            end
        end)
    end)
    if ok and conn then
        table.insert(Runtime.Cleanups, function() pcall(function() conn:Disconnect() end) end)
    else
        logw("PlantFullWatcher: connect lỗi")
    end
end

-- Chống người vào vườn mình ban đêm bằng shovel
function Runtime.doAntiSteal()
    local c = CFG.AntiSteal
    if not (c and c.Enabled) then return end
    if Runtime.ShouldYieldForSeedPriority("AntiSteal") or Runtime.ShouldYieldForPetPriority("AntiSteal") then
        return
    end

    -- ĐỨNG TRÊN PLOT CẢ NGÀY LẪN ĐÊM: nếu KHÔNG bận task dời đi (bán / tame pet / claim seed / đánh trộm)
    -- -> giữ đứng GIỮA 1 ô plot mình. Hàm chỉ teleport khi ở XA đích (đứng đúng chỗ rồi thì thôi -> ko giật).
    if c.StandInGardenWhenIdle ~= false
        and not (State.SellInProgress or State.PetTameInProgress or State.SeedClaimInProgress or State.AntiStealEngaging)
        and Runtime.StandInOwnGardenCell() then
        actionLog("AntiSteal", "STAND_HOME", "giua o plot")
    end

    if #Players:GetPlayers() <= 1 then
        State.IntruderCount = 0
        State.LastIntruders = "solo"
        State.AntiStealEngaging = false
        return
    end
    if State.SellInProgress then return end  -- đang đi bán thì để bán xong đã
    if c.OnlyAtNight ~= false and not isNight() then
        State.IntruderCount = 0
        State.LastIntruders = "-"
        return
    end

    local intruders = getPlayersInMyGarden()
    State.IntruderCount = #intruders
    if #intruders == 0 then
        State.LastIntruders = "-"
        return
    end

    local names = {}
    for _, player in ipairs(intruders) do
        table.insert(names, player.Name)
    end
    local intruderText = table.concat(names, ", ")
    local changed = State.LastIntruders ~= intruderText
    State.LastIntruders = intruderText
    if changed then
        actionLog("AntiSteal", "DETECTED", State.LastIntruders)
    end

    local cooldown = tonumber(c.TargetCooldown) or 0.5
    local now = os.clock()
    local rootBefore = getRootPart()
    local savedCF = rootBefore and rootBefore.CFrame
    local didDefend = false
    State.AntiStealEngaging = true
    local okDefend, errDefend = pcall(function()
        for _, player in ipairs(intruders) do
            local lastHit = AntiStealCooldown[player.UserId] or 0
            if now - lastHit >= cooldown then
                AntiStealCooldown[player.UserId] = now
                State.LastAntiSteal = os.date("%H:%M:%S") .. " defending " .. tostring(player.Name)
                didDefend = true
                hitIntruderWithShovel(player)
            end
        end
    end)
    -- Đánh xong quay lại vị trí cũ để không bị kẹt ở chỗ kẻ trộm (cải thiện flow farm)
    if didDefend and savedCF and c.ReturnAfterDefend ~= false then
        local rootAfter = getRootPart()
        if rootAfter then
            rootAfter.CFrame = savedCF
            actionLog("AntiSteal", "RETURNED", "back to farming spot")
        end
    end
    State.AntiStealEngaging = false
    Runtime.ReleaseToolLock("AntiSteal")
    if not okDefend then
        logw("AntiSteal defend lỗi:", errDefend)
    end
end

-- Ấp trứng đang cầm trong túi
function Runtime.doAutoHatchEgg()
    local c = CFG.AutoHatchEgg
    if not (c and c.Enabled) then return end
    if Runtime.ShouldYieldForSeedPriority("AutoHatchEgg") or Runtime.ShouldYieldForTrim("AutoHatchEgg") then return end
    actionLog("AutoHatchEgg", "START")
    if not packet({ "Egg", "OpenEgg" }) then
        logw("AutoHatchEgg: thiếu Networking.Egg.OpenEgg -> tắt.")
        c.Enabled = false
        return
    end
    local eggs = getToolsWithAttribute("Egg")
    for _, tool in ipairs(eggs) do
        local eggName = tool:GetAttribute("Egg")
        if eggName then
            -- KHOA TOOL: task khac dang cam tool -> nhuong luot nay
            if not Runtime.TryToolLock("AutoHatchEgg", 3) then
                actionLog("AutoHatchEgg", "SKIP", "tool busy " .. tostring(Runtime.ToolLockBy))
                return
            end
            if equipTool(tool) then
                actionLog("AutoHatchEgg", "OPEN", tostring(eggName))
                firePacket({ "Egg", "OpenEgg" }, eggName)
                if not waitAlive(c.Delay or 0.5) then return end
            end
        end
    end
    Runtime.ReleaseToolLock("AutoHatchEgg")
    actionLog("AutoHatchEgg", "DONE")
end

-- Equip pet theo tên

local function getPetInventory()
    local replica = getPlayerReplica()
    local data = replica and replica.Data
    local inventory = data and data.Inventory
    local pets = inventory and inventory.Pets
    return type(pets) == "table" and pets or nil
end

-- Kho pet CHƯA equip = { [tên pet] = SỐ LƯỢNG }. Đọc từ 2 NGUỒN rồi lấy MAX (pet có thể nằm 1 trong 2):
--   (1) replica Data.Inventory.Pets = {tên=số} (xác nhận PetEquipController.lua:113-114).
--   (2) TOOL trong Backpack/nhân vật có attribute "Pet" = tên (như ValuableWatcher quét).
-- Trả về { [tên pet] = số } (chỉ pet còn > 0).
local function getUnequippedPetCounts()
    local out = {}
    -- (1) replica Inventory.Pets {tên=số}
    local pets = getPetInventory()
    if type(pets) == "table" then
        for name, cnt in pairs(pets) do
            if type(name) == "string" and name ~= "" then
                local n = math.floor(tonumber(cnt) or 0)
                if n > 0 then out[name] = n end
            end
        end
    end
    -- (2) pet dạng TOOL (attribute "Pet" = tên) -> lấy MAX để không sót
    local toolCount = {}
    for _, t in ipairs(getAllTools()) do
        local pn = t:GetAttribute("Pet")
        if type(pn) == "string" and pn ~= "" then
            toolCount[pn] = (toolCount[pn] or 0) + 1
        end
    end
    for name, n in pairs(toolCount) do
        if n > (out[name] or 0) then out[name] = n end
    end
    return out
end

-- Đọc ĐÚNG cấu trúc kho pet: Data.Inventory.Pets = { [petId] = {Id,Name,Equipped,Type,...} }
-- (xác nhận MailboxController.lua:773 + u177; PetListController.lua:324).
-- Trả về mảng entry chuẩn hoá để equip/gửi mail (mỗi entry là 1 con pet riêng).
-- Gắn vào Runtime để không thêm local ở main scope (Lua giới hạn 200 local).
Runtime.GetPetInventoryEntries = function()
    local pets = getPetInventory()
    local out = {}
    if not pets then
        return out, "no pet inventory"
    end
    for key, entry in pairs(pets) do
        if type(entry) == "table" and type(entry.Name) == "string" then
            local petId = entry.Id
            if type(petId) ~= "string" or petId == "" then
                petId = type(key) == "string" and key or nil
            end
            local data = PetData and PetData[entry.Name]
            table.insert(out, {
                Id = petId,
                Name = entry.Name,
                Equipped = entry.Equipped == true,
                Type = entry.Type,   -- PetType ("Rainbow"/nil) - xác nhận PetListController u63
                Size = entry.Size,   -- PetSize ("Big"/"Huge"/nil=Normal) - xác nhận PetListController u63 + PetSizes
                -- ƯU TIÊN danh sách cứng theo tên (chuẩn live) rồi mới tới dump PetData
                Rarity = normalizeRarity(lookupPetRarityByName(entry.Name) or (data and data.Rarity) or "Common"),
            })
        end
    end
    return out
end

local function getEquippedPetCounts()
    -- CACHE 2s (dot 2 - FIX DO NANG NHAT): ham nay FIRE REMOTE GetEquippedPets (block cho SERVER tra loi)
    -- ma bi goi gian tiep boi ShouldYieldForPetPriority cua ~12 task MOI VONG + GUI -> truoc day script
    -- lien tuc treo cho remote round-trip -> CPU cao + giat khi FPS thap/nhieu tab. Cache 2s; cac cho doi
    -- so huu pet (mua pet / equip / unequip) se XOA cache (Runtime.EqPetCache = nil) de doc tuoi lai.
    -- Caller CHI DOC bang tra ve (da soat het), khong ai mutate -> share cache an toan.
    local cache = Runtime.EqPetCache
    if cache and (os.clock() - cache.At) < 2 then
        return cache.Counts, cache.Total
    end
    local counts = {}
    local total = 0
    if not packet({ "Pets", "GetEquippedPets" }) then
        return counts, total
    end
    local ok, equipped = firePacket({ "Pets", "GetEquippedPets" })
    if ok and type(equipped) == "table" then
        for _, pet in pairs(equipped) do
            if type(pet) == "table" and type(pet.Name) == "string" then
                counts[pet.Name] = (counts[pet.Name] or 0) + 1
                total = total + 1
            end
        end
    end
    Runtime.EqPetCache = { Counts = counts, Total = total, At = os.clock() }
    return counts, total
end

-- TỔNG sở hữu mỗi pet (theo key chuẩn hoá) = ĐANG equip + CHƯA equip (túi/tool).
-- Đúng ý chồng: 3 con equip + 2 con trong túi = 5. Dùng chung cho cả check ưu tiên lẫn mua thật
-- (1 nguồn đếm -> không lệch logic). Gắn vào Runtime để dùng được ở cả hàm định nghĩa TRƯỚC.
Runtime.GetOwnedPetCounts = function()
    local owned = {}
    for name, cnt in pairs(select(1, getEquippedPetCounts())) do
        local k = normPetKey(name)
        owned[k] = (owned[k] or 0) + (tonumber(cnt) or 0)
    end
    for name, cnt in pairs(getUnequippedPetCounts()) do
        local k = normPetKey(name)
        owned[k] = (owned[k] or 0) + (tonumber(cnt) or 0)
    end
    return owned
end

-- Phân loại 1 pet -> "Rainbow" / "Huge" / "Big" / "Normal" (Rainbow ưu tiên). size=PetSize, ptype=PetType.
-- Xác nhận: PetTypes.Rainbow="Rainbow"; PetSizes.Normalize -> "Big"/"Huge"/nil(=Normal).
Runtime.ClassifyPetVariant = function(size, ptype)
    if ptype == "Rainbow" then return "Rainbow" end
    local s = type(size) == "string" and string.lower(size) or ""
    if s == "huge" then return "Huge" end
    if s == "big" then return "Big" end
    return "Normal"
end

-- Đếm pet SỞ HỮU theo (tên chuẩn hoá) + variant. out[nameKey][variant] = số con.
-- Duyệt Inventory.Pets (có Size/Type; equipped pet vẫn nằm trong đó cờ Equipped=true) -> đủ cả equip lẫn túi.
Runtime.GetOwnedPetVariantCounts = function()
    local out = {}
    for _, e in ipairs(Runtime.GetPetInventoryEntries()) do
        local k = normPetKey(e.Name)
        local v = Runtime.ClassifyPetVariant(e.Size, e.Type)
        out[k] = out[k] or {}
        out[k][v] = (out[k][v] or 0) + 1
    end
    return out
end

-- Chuẩn hoá 1 spec mua/gửi theo size thành { Normal=, Big=, Huge=, Rainbow= } (số). Nhận:
--   - SỐ -> {} + total=number (cap tổng, mọi size).
--   - TABLE {Huge=9,Rainbow=9,...} -> map variant (key chấp nhận hoa/thường: huge/Huge...).
--   - CHUỖI "Raccoon, Huge=0, rainbow=1" -> tách tên + các cặp variant=số.
-- Trả về: name(hoặc nil nếu spec là table/number gắn theo key ngoài), variantMap, totalNum(or nil).
Runtime.ParsePetSizeSpec = function(spec)
    local variantMap, totalNum, nameFromStr
    local function setV(key, num)
        local kl = tostring(key):lower():gsub("%s+", "")
        local canon = (kl == "huge" and "Huge") or (kl == "big" and "Big")
            or (kl == "rainbow" and "Rainbow") or (kl == "normal" and "Normal") or nil
        if canon and tonumber(num) then
            variantMap = variantMap or {}
            variantMap[canon] = tonumber(num)
        end
    end
    if type(spec) == "number" then
        totalNum = spec
    elseif type(spec) == "table" then
        for k, v in pairs(spec) do setV(k, v) end
    elseif type(spec) == "string" then
        -- "Raccoon, Huge=0, rainbow=1"  hoặc  "Raccoon"
        local hasEq = spec:find("=", 1, true) ~= nil
        if not hasEq then
            nameFromStr = (spec:gsub("^%s+", ""):gsub("%s+$", ""))
        else
            -- phần TRƯỚC dấu "=" đầu / dấu phẩy đầu = tên
            local firstSeg = spec:match("^%s*([^,=]+)")
            if firstSeg then nameFromStr = (firstSeg:gsub("%s+$", "")) end
            for key, num in spec:gmatch("([%a]+)%s*=%s*(%d+)") do setV(key, num) end
        end
    end
    return nameFromStr, variantMap, totalNum
end

-- Danh sách pet ĐANG equip kèm Id (remote thật GetEquippedPets trả {Id,Name,Size,Type}).
-- XÁC NHẬN SOURCE: PetListController u92 -> check pet.Id; unequip game dùng RequestUnequip(pet.Id).
local function getEquippedPetList()
    local out = {}
    if not packet({ "Pets", "GetEquippedPets" }) then
        return out
    end
    local ok, equipped = firePacket({ "Pets", "GetEquippedPets" })
    if ok and type(equipped) == "table" then
        for _, pet in pairs(equipped) do
            if type(pet) == "table" and type(pet.Name) == "string" then
                table.insert(out, { Id = pet.Id, Name = pet.Name })
            end
        end
    end
    return out
end

local function getMaxEquippedPets()
    local attr = tonumber(LocalPlayer:GetAttribute("MaxEquippedPets"))
    if attr and attr > 0 then
        return math.floor(attr)
    end
    return (PetSlotPrices and tonumber(PetSlotPrices.BaseMax)) or 3
end

local function getPetScore(petName)
    local data = PetData and PetData[petName]
    local rarity = data and data.Rarity or "Common"
    local price = data and tonumber(data.BasePrice) or 0
    return ((RarityScore[rarity] or 0) * 100000000) + price
end

local function buildPetEquipCandidates()
    local entries, reason = Runtime.GetPetInventoryEntries()
    local out = {}
    if #entries == 0 then
        return out, reason or "no pets"
    end
    local cEq = CFG.AutoEquipPet or {}
    local minRarity = normalizeRarity(cEq.MinRarity or "Common")
    -- Pet nằm trong danh sách gửi mailbox (AutoMailPets.PetNames) thì KHÔNG equip
    -- (để Equipped=false cho AutoMailPets gửi đi). Pet đã equip thì game không cho gift.
    local mail = CFG.AutoMailPets
    local mailActive = cEq.SkipMailRarity ~= false and mail and mail.Enabled
    local mailNames = {}
    if mailActive then
        for _, w in ipairs(type(mail.PetNames) == "table" and mail.PetNames or {}) do
            if type(w) == "string" and w ~= "" then mailNames[string.lower(w)] = true end
        end
    end

    for _, e in ipairs(entries) do
        if not e.Equipped then
            local allowed = rarityAllowed(e.Rarity, minRarity)
            if allowed and mailActive and type(e.Name) == "string" and mailNames[string.lower(e.Name)] then
                allowed = false -- để dành gửi mail
            end
            if allowed then
                table.insert(out, {
                    Name = e.Name,
                    Id = e.Id,
                    Count = 1,
                    Rarity = e.Rarity,
                    Score = getPetScore(e.Name),
                })
            end
        end
    end
    table.sort(out, function(a, b)
        if a.Score ~= b.Score then
            return a.Score > b.Score
        end
        return a.Name < b.Name
    end)
    return out
end

-- Hook Notification: pet nào equip lỗi "No inventory folder for pet X" -> CHẶN equip lại trong 30s.
-- Tránh vòng lặp tháo-rồi-equip-fail liên tục với pet bị mất folder. Tự hết hạn để retry nếu sau có pet.
Runtime.PetEquipBlocked = Runtime.PetEquipBlocked or {}
Runtime.SetupPetEquipWatcher = function()
    if Runtime.PetEquipWatcherReady then return end
    local note = packet({ "Notification" })
    if not note or not note.OnClientEvent then return end
    Runtime.PetEquipWatcherReady = true
    local ok, conn = pcall(function()
        return note.OnClientEvent:Connect(function(message)
            if type(message) ~= "string" then return end
            if string.find(string.lower(message), "no inventory folder", 1, true) then
                local name = message:match('[Pp]et%s+"(.-)"') or message:match("[Pp]et%s+(%S+)")
                if name and name ~= "" then
                    Runtime.PetEquipBlocked[string.lower(name)] = os.clock() + 30
                end
            end
        end)
    end)
    if ok and conn then
        table.insert(Runtime.Cleanups, function() pcall(function() conn:Disconnect() end) end)
    end
end

-- ƯU TIÊN EQUIP (chồng yêu cầu): c.Priority = { ["Tên"] = { count, priority } }  (priority NHỎ = ưu tiên CAO).
-- Rót slot cho pet ưu tiên cao TRƯỚC theo TỔNG SỞ HỮU (equipped + túi), tối đa `count` mỗi loại và tối đa maxEquipped slot.
-- VD slot=3: đang 3 Deer(p3); có thêm 1 Golden Dragonfly(p2) -> want {gd=1, deer=2}; có thêm Unicorn(p1) ->
-- want {unicorn=1, gd=1, deer=1}. Bước UNEQUIP/EQUIP sẵn có tự THÁO Deer thừa rồi MANG con ưu tiên cao vào.
-- Trả về: want (key chữ-thường -> số equip), order (mảng key theo ưu tiên), firstName (key -> tên gốc tìm tool).
Runtime.BuildPriorityEquipPlan = function(c, maxEquipped)
    local want, order, firstName = {}, {}, {}
    local list = {}
    for name, spec in pairs(c.Priority) do
        if type(name) == "string" and name ~= "" then
            local count, prio
            if type(spec) == "table" then
                count = tonumber(spec[1]) or tonumber(spec.Count) or 1
                prio  = tonumber(spec[2]) or tonumber(spec.Priority) or 999
            elseif tonumber(spec) then
                count = tonumber(spec); prio = 999
            end
            if count and count > 0 then
                table.insert(list, { Name = name, Key = string.lower(name), Count = count, Priority = prio or 999 })
            end
        end
    end
    table.sort(list, function(a, b)
        if a.Priority ~= b.Priority then return a.Priority < b.Priority end
        return a.Key < b.Key
    end)
    -- TỔNG sở hữu mỗi tên = đang equip + chưa equip (chỉ rót slot cho pet THỰC SỰ có).
    local ownedByKey = {}
    for nm, cnt in pairs(select(1, getEquippedPetCounts())) do
        local k = string.lower(tostring(nm)); ownedByKey[k] = (ownedByKey[k] or 0) + (tonumber(cnt) or 0)
    end
    for nm, cnt in pairs(getUnequippedPetCounts()) do
        local k = string.lower(tostring(nm)); ownedByKey[k] = (ownedByKey[k] or 0) + (tonumber(cnt) or 0)
    end
    local remaining = math.max(tonumber(maxEquipped) or 0, 0)
    for _, e in ipairs(list) do
        if not firstName[e.Key] then firstName[e.Key] = e.Name; table.insert(order, e.Key) end
        local owned = tonumber(ownedByKey[e.Key]) or 0
        local take = math.min(e.Count, owned, remaining)
        if take < 0 then take = 0 end
        want[e.Key] = take
        remaining = remaining - take
    end
    return want, order, firstName
end

function Runtime.doAutoEquipPet()
    local c = CFG.AutoEquipPet
    if not (c and c.Enabled) then return end
    if not packet({ "Pets", "RequestEquipByName" }) then
        logw("AutoEquipPet: thieu Networking.Pets.RequestEquipByName -> tat.")
        c.Enabled = false
        return
    end
    Runtime.SetupPetEquipWatcher()

    local maxEquipped = getMaxEquippedPets()
    -- ƯU TIÊN (chồng yêu cầu): có c.Priority (map {Tên={count,priority}}) -> dùng kế hoạch ưu tiên: rót slot cho
    -- pet ưu tiên cao trước, tự THÁO pet ưu tiên thấp khi mua được con cao hơn. Không có -> dùng List như cũ.
    local priorityMode = type(c.Priority) == "table" and next(c.Priority) ~= nil
    local listMode = priorityMode or (type(c.List) == "table" and #c.List > 0)
    local want = {}
    local priorityOrder, priorityFirstName
    if priorityMode then
        want, priorityOrder, priorityFirstName = Runtime.BuildPriorityEquipPlan(c, maxEquipped)
    elseif listMode then
        for _, n in ipairs(c.List) do
            if type(n) == "string" and n ~= "" then
                local k = string.lower(n)
                want[k] = (want[k] or 0) + 1
            end
        end
        -- GUARD (chong yeu cau): TU DETECT so slot acc mang duoc (maxEquipped) -> chi mang du slot.
        -- Du config de 99 thi want moi pet cung bi cap = maxEquipped -> khong doi mang qua slot,
        -- het canh log "x0/99" lap mai khi khong con cho/khong co tool du.
        if maxEquipped and maxEquipped > 0 then
            for k in pairs(want) do
                if want[k] > maxEquipped then want[k] = maxEquipped end
            end
        end
    end

    -- ===== EVENT PET SWAP (chong): khi co WEATHER mutation active -> THAO pet dang mang + deo pet EventPet
    -- (vd "Deer" giup cay lon nhanh) DAY het slot -> cay kip catch mutation truoc khi weather het. Het
    -- weather -> vong sau tu deo lai theo config (Priority/List). "Da deo dung roi -> thoi" (want khop -> no-op).
    local eventPet = c.EventPet
    if type(eventPet) == "string" and eventPet ~= "" and Runtime.IsMutationWeatherActive() then
        local slots = (maxEquipped and maxEquipped > 0) and maxEquipped or 1
        local ek = string.lower(eventPet)
        want = { [ek] = slots }
        priorityMode = true
        priorityOrder = { ek }
        priorityFirstName = { [ek] = eventPet }
        listMode = true   -- ep che do list -> buoc unequip (thao pet khac) + equip Deer chay
        if not Runtime.EventPetActive then
            Runtime.EventPetActive = true
            actionLog("AutoEquipPet", "EVENT_ON", "weather -> deo " .. tostring(eventPet) .. " (day het slot)")
        end
    elseif Runtime.EventPetActive then
        Runtime.EventPetActive = nil
        actionLog("AutoEquipPet", "EVENT_OFF", "het weather -> deo lai pet config")
    end

    -- ===== BƯỚC 1: UNEQUIP pet SAI/THỪA TRƯỚC (theo Id - PetListController:262) =====
    local unequippedAny = false
    if listMode and packet({ "Pets", "RequestUnequip" }) then
        local kept = {}
        for _, e in ipairs(getEquippedPetList()) do
            local k = string.lower(tostring(e.Name))
            if (kept[k] or 0) < (want[k] or 0) then
                kept[k] = (kept[k] or 0) + 1   -- đúng pet & còn trong hạn -> GIỮ
            elseif type(e.Id) == "string" and e.Id ~= "" then
                actionLog("AutoEquipPet", "UNEQUIP", ("Wrong/excess: %s"):format(tostring(e.Name)))
                firePacket({ "Pets", "RequestUnequip" }, e.Id)
                unequippedAny = true
                if not waitAlive(0.3) then return end
            end
        end
    end
    -- Vừa gỡ pet -> CHỜ vài giây cho pet rơi về Backpack (thành tool) rồi mới equip (chồng yêu cầu).
    if unequippedAny then
        if not waitAlive(2.5) then return end
    end

    -- ===== BƯỚC 2: pet ĐANG equip (1 lần) + slot trống =====
    Runtime.EqPetCache = nil   -- vua co the unequip o buoc 1 -> doc TUOI, khong dung cache
    local eqCounts, equippedTotal = getEquippedPetCounts()
    local haveEq = {}
    for name, cnt in pairs(eqCounts) do haveEq[string.lower(tostring(name))] = (tonumber(cnt) or 0) end
    if maxEquipped - equippedTotal <= 0 then
        State.LastPet = os.date("%H:%M:%S") .. " slots full " .. tostring(equippedTotal) .. "/" .. tostring(maxEquipped)
        return
    end

    -- Tìm TOOL pet trong Backpack/nhân vật THEO TÊN (tool.Name = tên pet, vd "Bunny"/"Robin"/"Deer";
    -- xác nhận BackpackGui ToolName.Text + script chồng dùng Backpack:FindFirstChild(tên)). Khớp cả attr "Pet".
    local function findPetTool(petName)
        local lname = string.lower(tostring(petName))
        for _, container in ipairs({ LocalPlayer:FindFirstChildOfClass("Backpack"), getCharacter() }) do
            if container then
                local exact = container:FindFirstChild(petName)
                if exact and exact:IsA("Tool") then return exact end
                for _, x in ipairs(container:GetChildren()) do
                    if x:IsA("Tool") then
                        if string.lower(x.Name) == lname then return x end
                        local pa = x:GetAttribute("Pet")
                        if type(pa) == "string" and string.lower(pa) == lname then return x end
                    end
                end
            end
        end
        return nil
    end

    -- EQUIP = CẦM tool lên tay + RequestEquipByName + Activate + click giữa màn hình (cách chồng test chạy được).
    local function holdEquip(tool, petName)
        local char = getCharacter()
        if not (char and tool and tool.Parent) then return false end
        -- KHOA TOOL: task khac dang cam tool -> bo luot equip nay (vong sau thu lai)
        if not Runtime.TryToolLock("AutoEquipPet", 5) then return false end
        local hum = getHumanoid()
        if hum then pcall(function() hum:EquipTool(tool) end) end
        if tool.Parent ~= char then pcall(function() tool.Parent = char end) end  -- CẦM lên tay
        if not waitAlive(0.5) then return false end
        firePacket({ "Pets", "RequestEquipByName" }, petName)
        -- CHI Activate khi tool DA thuc su len tay (Parent=char). Truoc goi thang -> spam warning
        -- "Tool:Activate() called when tool is not equipped" khi EquipTool bi server tu choi/tre nhip.
        if tool.Parent == char then pcall(function() tool:Activate() end) end
        local x, y = getViewportCenter()
        for _ = 1, 3 do
            Runtime.SendTapAt(x, y, 0.08, { UseVirtualInput = true, UseTouchInput = true })
            if not waitAlive(0.2) then break end
        end
        Runtime.HideBlockingPopups()
        return true
    end

    -- ===== BƯỚC 3: EQUIP phần CÒN THIẾU =====
    local equipped = 0
    if listMode then
        local order, firstName = {}, {}
        if priorityMode then
            order, firstName = priorityOrder or {}, priorityFirstName or {}
        else
            for _, n in ipairs(c.List) do
                local k = string.lower(tostring(n))
                if not firstName[k] then firstName[k] = n; table.insert(order, k) end
            end
        end
        for _, k in ipairs(order) do
            local petName = firstName[k]
            while (haveEq[k] or 0) < (want[k] or 0) and equippedTotal < maxEquipped do
                local tool = findPetTool(petName)
                if not tool then
                    actionLog("AutoEquipPet", "SKIP", "khong co tool trong backpack: " .. tostring(petName))
                    break
                end
                actionLog("AutoEquipPet", "EQUIP", ("hold %s %d/%d"):format(tostring(petName), (haveEq[k] or 0) + 1, want[k]))
                if holdEquip(tool, petName) then
                    equipped = equipped + 1
                    equippedTotal = equippedTotal + 1
                    haveEq[k] = (haveEq[k] or 0) + 1
                else
                    break
                end
                if not waitAlive(0.4) then return end
            end
        end
        local parts = {}
        for k, n in pairs(want) do
            table.insert(parts, ("%s x%d/%d"):format(k, haveEq[k] or 0, n))
        end
        if #parts > 0 then
            actionLog("AutoEquipPet", "DONE", "Final valid: " .. table.concat(parts, ", "))
        end
    else
        -- Smart: equip mọi tool pet trong backpack (Name là pet trong PetData), xịn nhất trước.
        local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
        local cands = {}
        if bp then
            for _, x in ipairs(bp:GetChildren()) do
                if x:IsA("Tool") and PetData and PetData[x.Name] then
                    table.insert(cands, { Tool = x, Name = x.Name, Score = getPetScore(x.Name) })
                end
            end
        end
        if #cands == 0 then
            actionLog("AutoEquipPet", "SKIP", "khong co tool pet de equip")
            return
        end
        table.sort(cands, function(a, b) return a.Score > b.Score end)
        for _, pet in ipairs(cands) do
            if equippedTotal >= maxEquipped then break end
            actionLog("AutoEquipPet", "EQUIP", "hold " .. tostring(pet.Name))
            if holdEquip(pet.Tool, pet.Name) then
                equipped = equipped + 1
                equippedTotal = equippedTotal + 1
            end
            if not waitAlive(0.4) then return end
        end
    end

    Runtime.ReleaseToolLock("AutoEquipPet")
    if equipped > 0 then
        Runtime.EqPetCache = nil   -- vua equip -> so pet doi -> xoa cache dem
        State.LastPet = os.date("%H:%M:%S") .. " equip=" .. tostring(equipped)
    end
end

-- Tưới nước cây trong plot mình (xác nhận WateringcanController.lua:576)
local ValuableLastSummary = nil

local function webhookField(name, value, inline)
    return {
        name = tostring(name),
        value = tostring(value == nil and "-" or value),
        inline = inline ~= false,
    }
end

-- ===== WEBHOOK: bao khi CHINH ACC dang chay script claim duoc Rainbow/Gold Seed o EVENT =====
-- Source that: Networking.SeedPackSpawn.Claimed = SeedPackClaimed(String name, String seedType)
--   (Networking.lua:217). NotificationController.lua:892 hien "<name> found a <seedType>!".
-- CHI tinh khi name == ten acc dang chay script (LocalPlayer.Name / DisplayName) -> dung yeu cau chong.
-- Bao NGAY luc claim (theo remote), khong cho quet inventory nen khong bi sot.
do
    local SeedClaimSeq = 0
    local function onSeedClaimed(name, seedType)
        if not isAlive() then return end
        if type(name) ~= "string" or type(seedType) ~= "string" then return end
        local me = LocalPlayer
        local myName = me and me.Name
        local myDisp = me and me.DisplayName
        if name ~= myName and name ~= myDisp then return end   -- chi acc minh moi tinh
        local low = seedType:lower()
        local isRainbow = low:find("rainbow", 1, true) ~= nil
        local isGold = (not isRainbow) and low:find("gold", 1, true) ~= nil
        local isMega = (not isRainbow and not isGold) and low:find("mega", 1, true) ~= nil
        if not (isRainbow or isGold or isMega) then return end   -- chi bao seed dac biet, khong spam seed thuong
        SeedClaimSeq = SeedClaimSeq + 1
        local prefix = isRainbow and "seed:claim:" or (isGold and "gold:claim:" or "mega:claim:")
        local title = isRainbow and "Rainbow Seed -> Da Claim (Event)"
            or (isGold and "Gold Seed -> Da Claim (Event)" or "Mega Seed -> Da Claim (Event)")
        local color = isRainbow and 16711935 or (isGold and 16766720 or 16729344)  -- mega = cam
        sendWebhookOnce(
            prefix .. tostring(SeedClaimSeq) .. ":" .. seedType,
            title,
            ("%s claim %s thanh cong"):format(getAccountName(), seedType),
            {
                webhookField("Acc", getAccountName(), true),
                webhookField("Seed", seedType, true),
            },
            color
        )
    end
    local seedClaimConn
    local ok = pcall(function()
        local p = packet({ "SeedPackSpawn", "Claimed" })
        if p and p.OnClientEvent and type(p.OnClientEvent.Connect) == "function" then
            seedClaimConn = p.OnClientEvent:Connect(onSeedClaimed)
        else
            error("SeedPackSpawn.Claimed.OnClientEvent khong san")
        end
    end)
    if not ok then
        logw("Webhook seed-claim: khong hook duoc SeedPackSpawn.Claimed -> webhook event seed se khong bao.")
    elseif seedClaimConn then
        table.insert(Runtime.Cleanups, function()
            pcall(seedClaimConn.Disconnect, seedClaimConn)
        end)
    end
end

-- FAST CONFIRM SEED PACK (nhat seed pack SIEU NHANH - xac nhan source SeedPackOpenController.lua:595-609):
-- flow game: server claim (proximity) -> ban ReplicateOpenSeedPack(player, id, packName, seedName, pos)
-- -> client cho HET animation SeedPackEffect.Open (4.8s thuong / 8.6s Legendary-Mythic) roi moi
-- ConfirmSeedPack:Fire(id, packName, seedName) -> luc do seed moi vao data. Minh hook event va fire confirm
-- NGAY -> seed vao data lien (dac biet loi voi Mega seed vi hay ra seed hiem = animation dai nhat).
-- LUU Y: controller game VAN fire confirm lan 2 sau animation (khong go duoc connection game khong can
-- getconnections); server xu ly trung ra sao KHONG co trong source client -> chi biet args giong het nhau,
-- fire trung vo hai theo quan sat. Tat bang CFG.FastSeedPackConfirm.Enabled=false neu can.
do
    local fastConfirmConn
    local ok = pcall(function()
        local rep = packet({ "SeedPack", "ReplicateOpenSeedPack" })
        local conf = packet({ "SeedPack", "ConfirmSeedPack" })
        if not (rep and rep.OnClientEvent and type(rep.OnClientEvent.Connect) == "function") then
            error("SeedPack.ReplicateOpenSeedPack.OnClientEvent khong san")
        end
        if not (conf and type(conf.Fire) == "function") then
            error("SeedPack.ConfirmSeedPack.Fire khong san")
        end
        fastConfirmConn = rep.OnClientEvent:Connect(function(plr, packId, packName, seedName)
            if not isAlive() then return end
            local c = CFG.FastSeedPackConfirm
            if not (c and c.Enabled ~= false) then return end
            if plr ~= LocalPlayer then return end   -- source: game chi confirm khi u95 == LocalPlayer
            local fired = pcall(conf.Fire, conf, packId, packName, seedName)
            State.LastValuable = os.date("%H:%M:%S") .. " fast-confirm " .. tostring(seedName or packName)
            actionLog("FastSeedPack", fired and "CONFIRM" or "FAIL",
                tostring(packName), "seed=" .. tostring(seedName))
        end)
    end)
    if not ok then
        logw("FastSeedPackConfirm: khong hook duoc -> van nhan seed theo animation game (cham 5-9s).")
    elseif fastConfirmConn then
        table.insert(Runtime.Cleanups, function()
            pcall(fastConfirmConn.Disconnect, fastConfirmConn)
        end)
    end
end

-- INSTANT SPAWN DETECT (chong: "detect rainbow/gold cham, claim khong lai nguoi khac"):
-- truoc day CHI phat hien seed spawn qua vong quet AutoCollectDrops (idle 0.2-0.4s/nhip + FPS cap thap
-- moi frame ~0.14s + task khac chen ngang -> tre 0.5-2s la thua). Gio hook ChildAdded truc tiep tren
-- SeedPackSpawnServerLocations - DUNG nguon game nghe (SpawnSeedPackController.lua:255) - spawn VUA vao
-- folder la goi doAutoCollectDrops NGAY (wrapper busy-guard tranh dam vong quet). Attribute
-- (SeedPack/RainbowSeed/GoldSeed/MegaSeed) co the set SAU part (source WaitForSeedPackAttributes doi
-- toi 1s) -> doi ngan toi khi co attr roi moi goi (getSeedPackSpawnInfo can attr de nhan dien/uu tien).
do
    local hookThread = task.spawn(function()
        local spawnConn
        local okHook = pcall(function()
            local map = workspace:WaitForChild("Map", 20)
            if not map then error("khong thay workspace.Map") end
            local folder = map:WaitForChild("SeedPackSpawnServerLocations", 20)
            if not folder then error("khong thay SeedPackSpawnServerLocations") end
            if not isAlive() then return end
            spawnConn = folder.ChildAdded:Connect(function(child)
                if not isAlive() then return end
                local c = CFG.AutoCollectDrops
                if not (c and c.Enabled and c.IncludeSeedPackSpawns ~= false) then return end
                if c.InstantSpawnDetect == false then return end
                task.spawn(function()
                    local deadline = os.clock() + 1.2
                    while isAlive() and os.clock() < deadline do
                        if not child.Parent then return end
                        if type(child:GetAttribute("SeedPack")) == "string"
                            or child:GetAttribute("RainbowSeed") == true
                            or child:GetAttribute("GoldSeed") == true
                            or child:GetAttribute("MegaSeed") == true
                            or Runtime.GetSeedSpawnSpecialAttr(child) ~= nil then
                            break
                        end
                        task.wait(0.05)
                    end
                    if not isAlive() or not child.Parent then return end
                    -- seed EVENT (Rainbow/Gold/Mega/dac biet) -> danh dau "dang event" cho stay-out
                    if child:GetAttribute("RainbowSeed") == true or child:GetAttribute("GoldSeed") == true
                        or child:GetAttribute("MegaSeed") == true
                        or Runtime.GetSeedSpawnSpecialAttr(child) ~= nil then
                        Runtime.LastEventSeedSeenAt = os.clock()
                    end
                    actionLog("AutoCollectDrops", "SPAWN-NOW",
                        tostring(child:GetAttribute("SeedPack") or Runtime.GetSeedSpawnSpecialAttr(child)
                            or (child:GetAttribute("RainbowSeed") and "Rainbow")
                            or (child:GetAttribute("GoldSeed") and "Gold")
                            or (child:GetAttribute("MegaSeed") and "Mega") or "?"))
                    pcall(Runtime.doAutoCollectDrops)   -- busy-guard trong wrapper; dang co luong claim thi bo qua
                end)
            end)
            table.insert(Runtime.Cleanups, function()
                pcall(spawnConn.Disconnect, spawnConn)
            end)
        end)
        if not okHook then
            logw("InstantSpawnDetect: khong hook duoc ChildAdded -> detect theo vong quet nhu cu.")
        elseif spawnConn then
            if not isAlive() then
                pcall(spawnConn.Disconnect, spawnConn)
                return
            end
        end
    end)
    table.insert(Runtime.Tasks, hookThread)
end

-- Màu embed theo độ hiếm (nhìn pro hơn, mỗi rarity 1 màu riêng).
-- Gắn vào Runtime để không tốn thêm local ở main chunk (Lua giới hạn 200 local).
do
    local COLORS = {
        common    = 0x95A5A6, -- xám
        uncommon  = 0x2ECC71, -- xanh lá
        rare      = 0x3498DB, -- xanh dương
        epic      = 0x9B59B6, -- tím
        legendary = 0xF1C40F, -- vàng gold
        mythic    = 0xE67E22, -- cam
        mythical  = 0xE67E22,
        divine    = 0xE74C3C, -- đỏ
        prismatic = 0x1ABC9C, -- ngọc
    }
    function Runtime.RarityColor(rarity, fallback)
        local key = tostring(rarity or ""):lower():gsub("%s+", "")
        return COLORS[key] or fallback or 0x5865F2
    end
end

-- ẢNH PET cho embed webhook. LƯU Ý: đây là URL ẢNH NGOÀI (wiki Grow a Garden), KHÔNG nằm trong
-- source game (Workspace/ReplicatedStorage/Players_scripts) -> phần này CHƯA xác nhận trong source,
-- chỉ dùng để hiển thị cho đẹp. Pet nào chưa có URL thì dùng Placeholder.
-- Chồng thêm pet mới: lấy URL ảnh từ wiki rồi nhét vào bảng này theo đúng tên pet.
do
    local PLACEHOLDER = "https://static.wikia.nocookie.net/growagarden27847/images/4/47/Placeholder.png/revision/latest/scale-to-width-down/85?cb=20260402181137"
    local IMG = {
        ["Robin"]            = "https://static.wikia.nocookie.net/growagarden27847/images/1/1b/Robin.png/revision/latest/scale-to-width-down/85?cb=20260612231816",
        ["Bee"]              = "https://static.wikia.nocookie.net/growagarden27847/images/5/56/Bee.png/revision/latest/scale-to-width-down/85?cb=20260612231815",
        ["Monkey"]           = "https://static.wikia.nocookie.net/growagarden27847/images/2/27/Monkey.png/revision/latest/scale-to-width-down/85?cb=20260612231816",
        ["Golden Dragonfly"] = "https://static.wikia.nocookie.net/growagarden27847/images/e/ee/GoldenDragonfly.png/revision/latest/scale-to-width-down/85?cb=20260612231815",
        ["GoldenDragonfly"]  = "https://static.wikia.nocookie.net/growagarden27847/images/e/ee/GoldenDragonfly.png/revision/latest/scale-to-width-down/85?cb=20260612231815",
        ["Unicorn"]          = "https://static.wikia.nocookie.net/growagarden27847/images/7/7e/Unicorn.png/revision/latest/scale-to-width-down/85?cb=20260612212539",
        ["Raccoon"]          = "https://static.wikia.nocookie.net/growagarden27847/images/7/7c/Raccoon.png/revision/latest/scale-to-width-down/85?cb=20260612232005",
    }
    Runtime.PetWikiImage = IMG
    function Runtime.GetPetImage(petName)
        local url = petName and IMG[tostring(petName)]
        if type(url) == "string" and url ~= "" then
            return url
        end
        return PLACEHOLDER
    end
end

local function notifyHighPet(petName, rarity, source, petId, petType, count)
    -- Pet có Id riêng -> key theo Id (mỗi con báo 1 lần). Không có Id mới fallback theo tên.
    local keyId = petId
    if type(keyId) ~= "string" or keyId == "" then
        keyId = tostring(petName) .. ":count=" .. tostring(count or 1)
    end
    local key = "pet:" .. tostring(source or "unknown") .. ":" .. tostring(keyId)
    local sourceLabel = source == "Tool" and "Đang cầm (Tool)"
        or source == "Inventory" and "Trong kho (Inventory)"
        or tostring(source or "-")
    return sendWebhookOnce(
        key,
        "🐾 Pet Hiếm Phát Hiện",
        ("Tìm thấy **%s** • **%s** trên acc này."):format(tostring(petName), tostring(rarity)),
        {
            webhookField("👤 Tài khoản", getAccountName(), true),
            webhookField("🆔 UserId", tostring(LocalPlayer.UserId), true),
            webhookField("🐾 Pet", tostring(petName), true),
            webhookField("⭐ Độ hiếm", tostring(rarity), true),
            webhookField("🧬 Loại", tostring(petType ~= nil and petType ~= "" and petType or "-"), true),
            webhookField("🔢 Số lượng", tostring(count or 1), true),
            webhookField("📦 Nguồn", sourceLabel, false),
        },
        Runtime.RarityColor(rarity, 0xF1C40F),
        {
            author = "Kaitun • Valuable Watcher",
            footer = "Kaitun Valuable Watcher • " .. getAccountName(),
            thumbnail = Runtime.GetPetImage(petName),
            persist = CFG.ValuableWatcher and CFG.ValuableWatcher.PersistSeen ~= false,
        }
    )
end

local function notifyRainbowSeed(tool)
    local seedName = tool:GetAttribute("SeedTool") or tool:GetAttribute("SeedPack") or tool.Name
    local key = "seed:" .. tostring(tool:GetAttribute("Id") or tool.Name) .. ":" .. tostring(seedName)
    -- Đếm tổng rainbow seed đang giữ trong người (Backpack + đang cầm).
    local heldTotal = 0
    for _, t in ipairs(getAllTools()) do
        if isRainbowSeedTool(t) then
            heldTotal = heldTotal + 1
        end
    end
    return sendWebhookOnce(
        key,
        "🌈 Rainbow Seed Đã Giữ",
        ("Đã giữ lại **%s** — không plant / open / use."):format(tostring(seedName)),
        {
            webhookField("👤 Tài khoản", getAccountName(), true),
            webhookField("🆔 UserId", tostring(LocalPlayer.UserId), true),
            webhookField("🌱 Seed", tostring(seedName), true),
            webhookField("🎒 Tool", tostring(tool.Name), true),
            webhookField("🌈 Rainbow", isRainbow and "✅ Có" or "❌ Không", true),
            webhookField("🔢 Đang giữ", "x" .. tostring(heldTotal), true),
            webhookField("📦 Vị trí", tostring(tool.Parent and tool.Parent.Name or "-"), false),
        },
        0x9B59B6, -- tím rainbow
        {
            author = "Kaitun • Valuable Watcher",
            footer = "Kaitun Valuable Watcher • " .. getAccountName(),
            persist = CFG.ValuableWatcher and CFG.ValuableWatcher.PersistSeen ~= false,
        }
    )
end

notifyRainbowSeed = function(tool)
    local seedName = tool:GetAttribute("SeedTool") or tool:GetAttribute("SeedPack") or tool.Name
    local key = "seed:" .. tostring(tool:GetAttribute("Id") or tool.Name) .. ":" .. tostring(seedName)
    local heldTotal = 0
    for _, t in ipairs(getAllTools()) do
        if isRainbowSeedTool(t) then
            heldTotal = heldTotal + 1
        end
    end
    return sendWebhookOnce(
        key,
        "Rainbow Seed -> Dang Giu",
        ("Dang giu %s; khong plant/open/use."):format(tostring(seedName)),
        {
            webhookField("Acc", getAccountName(), true),
            webhookField("Seed", tostring(seedName), true),
            webhookField("Dang giu", "x" .. tostring(heldTotal), true),
        },
        0x9B59B6,
        {
            footer = "Kaitun ValuableWatcher - " .. getAccountName(),
            persist = CFG.ValuableWatcher and CFG.ValuableWatcher.PersistSeen ~= false,
        }
    )
end

local function isGoldSeedTool(tool)
    if not (tool and tool:IsA("Tool")) then return false end
    local hasSeedSignal = tool:GetAttribute("SeedTool") ~= nil
        or tool:GetAttribute("SeedPack") ~= nil
        or tool:GetAttribute("GoldSeed") == true
    if not hasSeedSignal then return false end
    if tool:GetAttribute("GoldSeed") == true then return true end
    local function hasGold(s) return type(s) == "string" and string.find(string.lower(s), "gold", 1, true) ~= nil end
    return hasGold(tool.Name) or hasGold(tool:GetAttribute("SeedTool")) or hasGold(tool:GetAttribute("SeedPack"))
end

local function notifyGoldSeed(tool)
    local seedName = tool:GetAttribute("SeedTool") or tool:GetAttribute("SeedPack") or tool.Name
    local key = "gold:" .. tostring(tool:GetAttribute("Id") or tool.Name) .. ":" .. tostring(seedName)
    return sendWebhookOnce(
        key,
        "Gold Seed -> Dang Giu",
        ("Dang giu %s (Gold); khong plant/open/use."):format(tostring(seedName)),
        {
            webhookField("Acc", getAccountName(), true),
            webhookField("Seed", tostring(seedName), true),
        },
        0xF1C40F, -- vàng gold
        {
            author = "Kaitun • Valuable Watcher",
            footer = "Kaitun Valuable Watcher • " .. getAccountName(),
            persist = CFG.ValuableWatcher and CFG.ValuableWatcher.PersistSeen ~= false,
        }
    )
end

local function doValuableWatcher()
    local c = CFG.ValuableWatcher
    if not (c and c.Enabled) then
        return
    end

    local minPetRarity = c.MinPetRarity or "Mythic"
    local highPets = 0
    local rainbowSeeds = 0

    if c.NotifyHighPet ~= false then
        -- Quét theo ĐÚNG cấu trúc kho pet (id -> entry). Mỗi con pet có Id riêng -> key webhook
        -- theo Id để báo từng con, relog không trùng (persist theo Id).
        for _, e in ipairs(Runtime.GetPetInventoryEntries()) do
            if isHighPetRarity(e.Rarity, minPetRarity) then
                highPets = highPets + 1
                notifyHighPet(e.Name, e.Rarity, "Inventory", e.Id, e.Type, 1)
            end
        end
    end

    for _, tool in ipairs(getAllTools()) do
        if c.NotifyHighPet ~= false then
            local petName = tool:GetAttribute("Pet")
            if type(petName) == "string" and petName ~= "" then
                local rarity = getPetRarityFromSource(petName, tool)
                if isHighPetRarity(rarity, minPetRarity) then
                    highPets = highPets + 1
                    notifyHighPet(
                        petName,
                        rarity,
                        "Tool",
                        tool:GetAttribute("PetId"),
                        tool:GetAttribute("PetType"),
                        1
                    )
                end
            end
        end

        if c.NotifyRainbowSeed ~= false then
            -- CHỈ ĐẾM (cho GUI/summary), KHÔNG gửi webhook "Dang Giu" nữa (trùng với "Da Claim (Event)").
            -- Chồng yêu cầu bỏ loại webhook "Gold/Rainbow Seed -> Dang Giu".
            if isRainbowSeedTool(tool) or isGoldSeedTool(tool) then
                rainbowSeeds = rainbowSeeds + 1
            end
        end
    end

    if highPets > 0 or rainbowSeeds > 0 then
        local summary = ("pet=%s seed=%s"):format(tostring(highPets), tostring(rainbowSeeds))
        State.LastValuable = os.date("%H:%M:%S") .. " " .. summary
        if summary ~= ValuableLastSummary then
            ValuableLastSummary = summary
            actionLog("ValuableWatcher", "DONE", summary)
        end
    end
end

local function doAutoWater()
    local c = CFG.AutoWater
    if not (c and c.Enabled) then return end
    if Runtime.ShouldYieldForSeedPriority("AutoWater") or Runtime.ShouldYieldForPetPriority("AutoWater") or Runtime.ShouldYieldForTrim("AutoWater") then
        return
    end
    if not packet({ "WateringCan", "UseWateringCan" }) then
        logw("AutoWater: thiếu Networking.WateringCan.UseWateringCan -> tắt.")
        c.Enabled = false
        return
    end
    if not getPlot() then
        actionLog("AutoWater", "SKIP", "missing plot")
        return
    end
    local cans = getToolsWithAttribute("WateringCan")
    -- LOCK GEAR: bỏ watering can có tên trong LockGear (giữ trong kho để GỬI MAIL, KHÔNG xài).
    if type(c.LockGear) == "table" and next(c.LockGear) ~= nil then
        local lk = {}
        for _, n in ipairs(c.LockGear) do if type(n) == "string" and n ~= "" then lk[string.lower(n)] = true end end
        local keep = {}
        for _, t in ipairs(cans) do
            local nm = string.lower(tostring(t:GetAttribute("WateringCan") or t.Name))
            if not lk[nm] then keep[#keep + 1] = t end
        end
        cans = keep
    end
    if #cans == 0 then
        actionLog("AutoWater", "SKIP", "no watering can")
        return
    end
    local tool = cans[1]
    -- KHOA TOOL: task khac dang cam tool -> nhuong luot nay (vong sau tuoi tiep)
    if not Runtime.TryToolLock("AutoWater", 4) then
        actionLog("AutoWater", "SKIP", "tool busy " .. tostring(Runtime.ToolLockBy))
        return
    end
    if not equipTool(tool) then
        Runtime.ReleaseToolLock("AutoWater")
        return
    end
    local canName = tool:GetAttribute("WateringCan")
    local n = math.max(tonumber(c.PerCycle) or 20, 1)
    local watered = 0
    -- NGAN SACH THOI GIAN: o FPS cap 7-10, moi waitAlive(0.15) thuc te >= 1 frame (~0.1-0.14s)
    -- -> 20 phat co the giu ToolLock 3-6s lam AutoPlant/Collect doi dai (nguon "do" khi sai gear).
    -- Qua budget -> dung som, nha lock; vong sau tuoi tiep (chia nho, khong mat luot).
    local waterBudgetEnd = os.clock() + math.max(tonumber(c.MaxCycleSeconds) or 1.5, 0.3)
    for _ = 1, n do
        if not (tool and tool.Parent) then break end
        if os.clock() >= waterBudgetEnd then
            actionLog("AutoWater", "BUDGET", "watered=" .. tostring(watered))
            break
        end
        local pos = randomPlantPosition()
        if not pos then break end
        -- source gửi (vị trí trên PlantArea - (0,0.3,0), tên bình, tool)
        firePacket({ "WateringCan", "UseWateringCan" }, pos - Vector3.new(0, 0.3, 0), canName, tool)
        Runtime.ExtendToolLock("AutoWater", 2)
        watered = watered + 1
        if not waitAlive(0.15) then return end
    end
    Runtime.ReleaseToolLock("AutoWater")
    actionLog("AutoWater", "DONE", "watered=" .. tostring(watered))
end

-- Đặt sprinkler đang có trong túi xuống ô PlantArea (xác nhận SprinklerController.lua:432)
local function doAutoSprinkler()
    local c = CFG.AutoSprinkler
    if not (c and c.Enabled) then return end
    if Runtime.ShouldYieldForSeedPriority("AutoSprinkler") or Runtime.ShouldYieldForPetPriority("AutoSprinkler") or Runtime.ShouldYieldForTrim("AutoSprinkler") then
        return
    end
    if not packet({ "Place", "PlaceSprinkler" }) then
        logw("AutoSprinkler: thiếu Networking.Place.PlaceSprinkler -> tắt.")
        c.Enabled = false
        return
    end
    if not getPlot() then
        actionLog("AutoSprinkler", "SKIP", "missing plot")
        return
    end
    local plotId = tonumber(LocalPlayer:GetAttribute("PlotId"))
    if not plotId then
        actionLog("AutoSprinkler", "SKIP", "missing PlotId")
        return
    end
    local sprinklers = getToolsWithAttribute("Sprinkler")
    -- LOCK GEAR: bỏ sprinkler có tên trong LockGear (giữ trong kho để GỬI MAIL, KHÔNG đặt/xài).
    if type(c.LockGear) == "table" and next(c.LockGear) ~= nil then
        local lk = {}
        for _, n in ipairs(c.LockGear) do if type(n) == "string" and n ~= "" then lk[string.lower(n)] = true end end
        local keep = {}
        for _, t in ipairs(sprinklers) do
            local nm = string.lower(tostring(t:GetAttribute("Sprinkler") or t.Name))
            if not lk[nm] then keep[#keep + 1] = t end
        end
        sprinklers = keep
    end
    if #sprinklers == 0 then
        actionLog("AutoSprinkler", "SKIP", "no sprinkler tool")
        return
    end
    -- KHOA TOOL: task khac dang cam tool -> nhuong luot nay
    if not Runtime.TryToolLock("AutoSprinkler", 4) then
        actionLog("AutoSprinkler", "SKIP", "tool busy " .. tostring(Runtime.ToolLockBy))
        return
    end
    local placed = 0
    local maxPlace = math.max(tonumber(c.PerCycle) or 5, 1)
    -- Sprinkler Stack: đặt CHỒNG nhiều sprinkler vào CÙNG 1 vị trí (engine bắn remote thẳng nên
    -- bỏ qua chặn IsTooCloseToSprinkler của client). Stack=1 = như cũ (mỗi cái 1 chỗ).
    local stack = math.max(math.floor(tonumber(c.Stack) or 1), 1)
    local stackPos = nil
    local stackUsed = 0
    -- ngan sach thoi gian (nhu AutoWater.MaxCycleSeconds): khong giu ToolLock qua lau o FPS thap
    local sprBudgetEnd = os.clock() + math.max(tonumber(c.MaxCycleSeconds) or 2, 0.3)
    for _, tool in ipairs(sprinklers) do
        if placed >= maxPlace then break end
        if os.clock() >= sprBudgetEnd then
            actionLog("AutoSprinkler", "BUDGET", "placed=" .. tostring(placed))
            break
        end
        if not (tool and tool.Parent) then break end
        if not equipTool(tool) then break end
        local sprName = tool:GetAttribute("Sprinkler")
        if not stackPos or stackUsed >= stack then
            -- ĐẶT Ở VÙNG MẬT ĐỘ CÂY CAO NHẤT (không đặt bậy) -> sprinkler buff được nhiều cây nhất.
            if c.PlaceAtDensest ~= false then
                stackPos = Runtime.DensestPlantPosition(c.DensityRadius)
            else
                stackPos = randomPlantPosition()
            end
            stackUsed = 0
        end
        local pos = stackPos
        if pos then
            -- PlaceSprinkler:Fire(vịTríTrênPlantArea, tênSprinkler, tool, plotId)
            firePacket({ "Place", "PlaceSprinkler" }, pos, sprName, tool, plotId)
            Runtime.ExtendToolLock("AutoSprinkler", 2)
            placed = placed + 1
            stackUsed = stackUsed + 1
            -- FIX KET LOGIC (chong dot 20): thoat som (chet/respawn giua luc dat gear - claim seed dung
            -- respawn teleport) PHAI nha ToolLock, neu khong tool bi khoa -> AutoPlant/AutoWater/hai deu ket.
            if not waitAlive(tonumber(c.Delay) or 0.5) then
                Runtime.ReleaseToolLock("AutoSprinkler")
                return
            end
        end
    end
    Runtime.ReleaseToolLock("AutoSprinkler")
    actionLog("AutoSprinkler", "DONE", "placed=" .. tostring(placed) .. " stack=" .. tostring(stack))
end

-- Mở Crate đang cầm (xác nhận CrateController.lua:110)
function Runtime.doAutoOpenCrate()
    local c = CFG.AutoOpenCrate
    if not (c and c.Enabled) then return end
    if Runtime.ShouldYieldForSeedPriority("AutoOpenCrate") or Runtime.ShouldYieldForPetPriority("AutoOpenCrate") or Runtime.ShouldYieldForTrim("AutoOpenCrate") then
        return
    end
    if not packet({ "Crate", "OpenCrate" }) then
        logw("AutoOpenCrate: thiếu Networking.Crate.OpenCrate -> tắt.")
        c.Enabled = false
        return
    end
    local locked = {}
    if type(c.LockCrate) == "table" then
        for _, name in ipairs(c.LockCrate) do
            if type(name) == "string" and name ~= "" then
                locked[string.lower(name)] = true
            end
        end
    end
    for _, tool in ipairs(getToolsWithAttribute("Crate")) do
        local crateName = tool:GetAttribute("Crate")
        if crateName and locked[string.lower(tostring(crateName))] then
            actionLog("AutoOpenCrate", "SKIP", "locked " .. tostring(crateName))
        elseif crateName and Runtime.TryToolLock("AutoOpenCrate", 3) and equipTool(tool) then
            actionLog("AutoOpenCrate", "OPEN", tostring(crateName))
            firePacket({ "Crate", "OpenCrate" }, crateName)
            if not waitAlive(tonumber(c.Delay) or 0.5) then return end
        end
    end
    Runtime.ReleaseToolLock("AutoOpenCrate")
end

-- Mở Seed Pack đang cầm (xác nhận SeedPackHandleController.lua:204)
function Runtime.doAutoOpenSeedPack()
    local c = CFG.AutoOpenSeedPack
    if not (c and c.Enabled) then return end
    if Runtime.ShouldYieldForSeedPriority("AutoOpenSeedPack") or Runtime.ShouldYieldForPetPriority("AutoOpenSeedPack") or Runtime.ShouldYieldForTrim("AutoOpenSeedPack") then
        return
    end
    if not packet({ "SeedPack", "OpenSeedPack" }) then
        logw("AutoOpenSeedPack: thiếu Networking.SeedPack.OpenSeedPack -> tắt.")
        c.Enabled = false
        return
    end
    for _, tool in ipairs(getToolsWithAttribute("SeedPack")) do
        local packName = tool:GetAttribute("SeedPack")
        if Runtime.ShouldKeepSeed(packName, tool) then
            actionLog("AutoOpenSeedPack", "SKIP", "keep seed " .. tostring(packName or tool.Name))
            State.LastValuable = os.date("%H:%M:%S") .. " keep seed " .. tostring(packName or tool.Name)
        elseif packName and Runtime.TryToolLock("AutoOpenSeedPack", 3) and equipTool(tool) then
            actionLog("AutoOpenSeedPack", "OPEN", tostring(packName))
            firePacket({ "SeedPack", "OpenSeedPack" }, packName)
            if not waitAlive(tonumber(c.Delay) or 0.5) then return end
        end
    end
    Runtime.ReleaseToolLock("AutoOpenSeedPack")
end

-- Cộng điểm kỹ năng (xác nhận Visiblity.lua: SpendSkillPoint:Fire(tênSkill))
-- Được cộng nếu SkillPoints.Value >= level hiện tại của skill đó.
-- ============================================================
-- MAILBOX TUTORIAL GATE: game CHẶN gift khi đang tutorial ("you can't gift item during the tutorial").
-- Signal THẬT: workspace:GetAttribute("InTutorial") == true (xác nhận RestockStoreController.lua:559).
-- Remote hoàn tất tutorial: Networking.Tutorial.Complete (Networking.lua:425).
-- ============================================================
Runtime.IsInTutorial = function()
    return workspace:GetAttribute("InTutorial") == true
end
-- Trả về true nếu PHẢI BỎ QUA mailbox (tắt cứng MailboxEnabled=false, hoặc đang tutorial).
Runtime.MailboxBlocked = function(action)
    if CFG.MailboxEnabled == false then
        return true
    end
    if CFG.AutoTutorialCheck ~= false and Runtime.IsInTutorial() then
        -- bắn Tutorial.Complete để THOÁT tutorial (workspace.InTutorial=true đang chặn mailbox).
        -- RE-TRY mỗi ~10s thay vì chỉ 1 lần -> KHÔNG cần rejoin để clear tutorial mới gửi mail được
        -- (đúng triệu chứng chồng phản ánh "phải rejoin mail mới gửi"). Remote thật Tutorial.Complete; server bỏ qua nếu đã xong.
        local nowc = os.clock()
        if (not Runtime.TutorialCompleteAt or (nowc - Runtime.TutorialCompleteAt) > 10) and packet({ "Tutorial", "Complete" }) then
            Runtime.TutorialCompleteAt = nowc
            firePacket({ "Tutorial", "Complete" })
            actionLog(action or "Mailbox", "TUTORIAL", "fire Tutorial.Complete (thoat tutorial de gui mail)")
        end
        if CFG.SkipMailboxIfTutorial ~= false then
            if not Runtime.MailboxTutorialLogged then
                Runtime.MailboxTutorialLogged = true
                log("[Mailbox] Tutorial not completed, mailbox disabled for this account.")
            end
            State.LastMailbox = os.date("%H:%M:%S") .. " tutorial (off)"
            actionLog(action or "Mailbox", "SKIP", "in tutorial -> mailbox off")
            return true
        end
    end
    return false
end

function Runtime.doAutoClaimMailbox()
    local c = CFG.AutoClaimMailbox
    if not (c and c.Enabled) then return end
    if Runtime.MailboxBlocked("AutoClaimMailbox") then return end
    if not packet({ "Mailbox", "OpenInbox" }) or not packet({ "Mailbox", "Claim" }) then
        logw("AutoClaimMailbox: thieu Networking.Mailbox.OpenInbox/Claim -> tat.")
        c.Enabled = false
        return
    end

    local ok, inbox = firePacket({ "Mailbox", "OpenInbox" })
    if not ok or type(inbox) ~= "table" then
        actionLog("AutoClaimMailbox", "SKIP", "no inbox")
        return
    end

    -- Tổng số quà thật có trong hộp thư khi mở (để báo webhook).
    local totalGifts = 0
    for giftId, giftData in pairs(inbox) do
        if type(giftId) == "string" and type(giftData) == "table" then
            totalGifts = totalGifts + 1
        end
    end

    local claimed = 0
    local maxPerCycle = math.max(tonumber(c.MaxPerCycle) or 20, 1)
    for giftId, giftData in pairs(inbox) do
        if claimed >= maxPerCycle then break end
        if type(giftId) == "string" and type(giftData) == "table" then
            local okClaim, result = firePacket({ "Mailbox", "Claim" }, giftId)
            if okClaim and result == true then
                claimed = claimed + 1
                actionLog("AutoClaimMailbox", "DONE", giftId)
                if not waitAlive(0.2) then return end
            end
        end
    end

    if claimed > 0 then
        Runtime.MailClaimedTotal = (Runtime.MailClaimedTotal or 0) + claimed
        State.LastMailbox = os.date("%H:%M:%S") .. " claimed=" .. tostring(claimed)
        actionLog("AutoClaimMailbox", "DONE", "claimed=" .. tostring(claimed))
        -- Báo webhook cho chồng: nhận được mấy quà + tổng trong hộp + tổng phiên.
        Runtime.MailClaimSeq = (Runtime.MailClaimSeq or 0) + 1
        sendWebhookOnce(
            "mailclaim:" .. tostring(Runtime.MailClaimSeq),
            "📬 Mailbox → Đã Nhận Quà",
            ("Đã nhận **%d** quà từ hộp thư."):format(claimed),
            {
                webhookField("👤 Tài khoản", getAccountName(), true),
                webhookField("🆔 UserId", tostring(LocalPlayer.UserId), true),
                webhookField("📥 Nhận vòng này", "x" .. tostring(claimed), true),
                webhookField("📨 Quà trong hộp", "x" .. tostring(totalGifts), true),
                webhookField("🧮 Tổng phiên này", "x" .. tostring(Runtime.MailClaimedTotal), true),
            },
            0x3BA55D, -- xanh lá
            {
                author = "Kaitun • AutoClaimMailbox",
                footer = "Kaitun AutoClaimMailbox • " .. getAccountName(),
            }
        )
    else
        State.LastMailbox = os.date("%H:%M:%S") .. " empty"
    end
end

do
local MailSeedSeq = 0
local MailRecipientCache = {}

local function resolveMailboxRecipient(c, actionName)
    if type(c) ~= "table" then
        return nil
    end
    -- NHIỀU NGƯỜI NHẬN: RecipientUsernames là list -> random 1 tên mỗi lần gửi.
    -- (1 tên = luôn gửi acc đó; nhiều tên = chia random). Có list thì BỎ QUA RecipientUserId.
    local username = c.RecipientUsername
    local hasList = false
    if type(c.RecipientUsernames) == "table" then
        local pool = {}
        for _, nm in ipairs(c.RecipientUsernames) do
            if type(nm) == "string" and nm ~= "" then table.insert(pool, nm) end
        end
        if #pool > 0 then
            hasList = true
            username = pool[math.random(1, #pool)]
            if #pool > 1 then
                actionLog(actionName or "AutoMail", "TO", "random -> " .. tostring(username))
            end
        end
    end
    if (not hasList) and type(c.RecipientUserId) == "number" and c.RecipientUserId > 0 then
        return c.RecipientUserId, c.RecipientUsername
    end
    if type(username) ~= "string" or username == "" then
        actionLog(actionName or "AutoMail", "SKIP", "missing recipient")
        return nil
    end
    if MailRecipientCache[username] then
        return MailRecipientCache[username].UserId, MailRecipientCache[username].Name
    end
    local p = packet({ "Mailbox", "LookupPlayer" })
    if not p then
        actionLog(actionName or "AutoMail", "SKIP", "missing Mailbox.LookupPlayer")
        return nil
    end
    local ok, userId, displayName = pcall(function()
        return p:Fire(username)
    end)
    if not ok then
        actionLog(actionName or "AutoMail", "ERROR", "LookupPlayer " .. compactText(userId, 60))
        return nil
    end
    if type(userId) ~= "number" or userId <= 0 then
        actionLog(actionName or "AutoMail", "SKIP", "recipient not found " .. tostring(username))
        return nil
    end
    MailRecipientCache[username] = { UserId = userId, Name = displayName or username }
    return userId, displayName or username
end

local function getSeedInventoryEntries()
    local replica = getPlayerReplica()
    if not (replica and replica.Data and type(replica.Data.Inventory) == "table") then
        return {}, "no replica inventory"
    end
    local seeds = replica.Data.Inventory.Seeds
    if type(seeds) ~= "table" then
        return {}, "no seed inventory"
    end
    local out = {}
    for key, count in pairs(seeds) do
        local n = math.floor(tonumber(count) or 0)
        if type(key) == "string" and key ~= "" and n > 0 then
            table.insert(out, {
                ItemKey = key,
                DisplayName = key,
                Count = n,
            })
        end
    end
    table.sort(out, function(a, b)
        return tostring(a.ItemKey) < tostring(b.ItemKey)
    end)
    return out
end

local function buildAutoMailSeedConfig()
    local base = CFG.AutoMailSeeds or {}
    local rb = CFG.AutoMailRainbow or {}
    local enabled = base.Enabled ~= false or rb.Enabled ~= false
    local names = {}
    addConfiguredNames(names, base.SeedNames or base.Seeds or base.List)
    if rb.Enabled ~= false then
        names[normalizeItemName("Rainbow")] = true
    end
    return {
        Enabled = enabled,
        RecipientUsername = base.RecipientUsername or rb.RecipientUsername,
        RecipientUsernames = base.RecipientUsernames or rb.RecipientUsernames,   -- FIX: copy list nhiều acc (random gửi)
        RecipientUserId = tonumber(base.RecipientUserId) or tonumber(rb.RecipientUserId) or 0,
        Note = base.Note ~= nil and base.Note or rb.Note,
        DelayBeforeSend = tonumber(base.DelayBeforeSend) or tonumber(rb.DelayBeforeSend) or 0,
        MaxPerBatch = math.clamp(math.floor(tonumber(base.MaxPerBatch) or 20), 1, 100000),  -- mở khóa >20 (UI client chặn 20, remote thì không)
        Names = names,
        MinCount = type(base.MinCount) == "table" and base.MinCount or {},   -- ngưỡng số lượng mới gửi
    }
end

local function buildMailSeedCandidates(c)
    local entries, reason = getSeedInventoryEntries()
    local out = {}
    if next(c.Names) == nil then
        return out, "no configured seed names"
    end
    local minCount = type(c.MinCount) == "table" and c.MinCount or {}
    -- ngưỡng cho 1 seed: tên seed khớp key nào trong MinCount thì lấy số đó (mặc định 1).
    local function thresholdFor(entry)
        local text = normalizeItemName(entry.ItemKey) .. " " .. normalizeItemName(entry.DisplayName)
        local th = 1
        for name, n in pairs(minCount) do
            if name ~= "" and string.find(text, name, 1, true) then
                th = math.max(th, tonumber(n) or 1)
            end
        end
        return th
    end
    for _, entry in ipairs(entries) do
        if nameMatchesConfiguredSet(entry.ItemKey, c.Names)
            or nameMatchesConfiguredSet(entry.DisplayName, c.Names) then
            if (tonumber(entry.Count) or 0) >= thresholdFor(entry) then   -- đủ ngưỡng mới gửi
                table.insert(out, entry)
            end
        end
    end
    return out, (#entries == 0 and reason or nil)
end

local function notifyMailSeedSent(seedKey, sentCount, startCount, recipientName, recipientId, note, resultMsg, batches)
    MailSeedSeq = MailSeedSeq + 1
    local remain = math.max((tonumber(startCount) or 0) - (tonumber(sentCount) or 0), 0)
    local title = (hasRainbowText(seedKey) and "Rainbow Seed" or tostring(seedKey)) .. " -> Da Gui Mailbox"
    return sendWebhookOnce(
        "mailseed:" .. tostring(MailSeedSeq) .. ":" .. tostring(seedKey),
        title,
        ("%s x%d -> %s"):format(tostring(seedKey), tonumber(sentCount) or 0, tostring(recipientName or recipientId)),
        {
            webhookField("Acc gui", getAccountName(), true),
            webhookField("Acc nhan", tostring(recipientName or "-"), true),
            webhookField("Seed", tostring(seedKey), true),
            webhookField("So luong", "x" .. tostring(sentCount), true),
            webhookField("Con lai", "x" .. tostring(remain), true),
            webhookField("Batch", tostring(batches or 1), true),
            webhookField("Ket qua", tostring(resultMsg ~= "" and resultMsg or "Gift sent!"), false),
        },
        hasRainbowText(seedKey) and 0x9B59B6 or 0x3BA55D,
        {
            footer = "Kaitun AutoMailSeeds - " .. getAccountName(),
            content = tostring((CFG.Webhook and CFG.Webhook.Mention) or ""),
        }
    )
end

function Runtime.DoAutoMailSeeds()
    local c = buildAutoMailSeedConfig()
    -- LOG 1 LẦN config mail đã RESOLVE (để chồng kiểm chứng config có áp dụng không khi nghi "mail không gửi").
    if not Runtime.MailSeedCfgLogged then
        Runtime.MailSeedCfgLogged = true
        local nameList = {}
        for nm in pairs(c.Names or {}) do table.insert(nameList, nm) end
        actionLog("AutoMailSeeds", "CFG", ("enabled=%s to=%s names=[%s] batch=%s"):format(
            tostring(c.Enabled),
            tostring(c.RecipientUsername or (c.RecipientUserId and ("id:" .. tostring(c.RecipientUserId))) or "-"),
            table.concat(nameList, ","),
            tostring(c.MaxPerBatch)))
    end
    if not c.Enabled then return end
    if Runtime.MailboxBlocked("AutoMailSeeds") then return end
    if not packet({ "Mailbox", "SendBatch" }) then
        logw("AutoMailSeeds: thieu Networking.Mailbox.SendBatch -> tat.")
        if CFG.AutoMailSeeds then CFG.AutoMailSeeds.Enabled = false end
        if CFG.AutoMailRainbow then CFG.AutoMailRainbow.Enabled = false end
        return
    end

    local candidates, reason = buildMailSeedCandidates(c)
    if #candidates == 0 then
        if reason then
            actionLog("AutoMailSeeds", "SKIP", tostring(reason))
        end
        return
    end

    local delayBeforeSend = math.max(tonumber(c.DelayBeforeSend) or 0, 0)
    if delayBeforeSend > 0 then
        State.LastMailRainbow = os.date("%H:%M:%S") .. " wait send seed"
        if not waitAlive(delayBeforeSend) then return end
        candidates = buildMailSeedCandidates(c)
        if #candidates == 0 then
            actionLog("AutoMailSeeds", "SKIP", "no seed after wait")
            return
        end
    end

    local userId, recipientName = resolveMailboxRecipient(c, "AutoMailSeeds")
    if not userId then return end
    if userId == LocalPlayer.UserId then
        actionLog("AutoMailSeeds", "SKIP", "recipient is self")
        return
    end

    local p = packet({ "Mailbox", "SendBatch" })
    local note = tostring(c.Note or "")
    for _, seed in ipairs(candidates) do
        local remaining = math.floor(tonumber(seed.Count) or 0)
        local startCount = remaining
        local sentTotal = 0
        local batches = 0
        while remaining > 0 do
            local chunk = math.min(remaining, c.MaxPerBatch)
            local items = {
                { Category = "Seeds", ItemKey = seed.ItemKey, Count = chunk },
            }
            local ok, success, msg = pcall(function()
                return p:Fire(userId, items, note)
            end)
            if not ok then
                actionLog("AutoMailSeeds", "ERROR", "SendBatch " .. compactText(success, 60))
                break
            end
            if not success then
                actionLog("AutoMailSeeds", "WARN", tostring(msg ~= "" and msg or "Could not send gift"))
                break
            end
            sentTotal = sentTotal + chunk
            remaining = remaining - chunk
            batches = batches + 1
            State.LastMailRainbow = os.date("%H:%M:%S")
                .. (" sent %s x%d -> %s"):format(tostring(seed.ItemKey), sentTotal, tostring(recipientName or userId))
            actionLog("AutoMailSeeds", "DONE", ("%s x%d"):format(tostring(seed.ItemKey), chunk))
            if remaining > 0 and not waitAlive(0.8) then return end
        end
        if sentTotal > 0 then
            notifyMailSeedSent(seed.ItemKey, sentTotal, startCount, recipientName, userId, note, "Gift sent!", batches)
            if not waitAlive(0.6) then return end
        end
    end
end

Runtime.DoAutoMailRainbow = Runtime.DoAutoMailSeeds

-- Mail Fruits: gửi TRÁI CÂY đã thu hoạch qua Mailbox. Category="HarvestedFruits", ItemKey=fruit.Id
-- (xác nhận MailboxController.lua:642-649 -> entry là bảng có .Id; SendBatch dùng ItemKey=Id như Pets).
local function getFruitInventoryEntries()
    local replica = getPlayerReplica()
    if not (replica and replica.Data and type(replica.Data.Inventory) == "table") then
        return {}, "no replica inventory"
    end
    local fruits = replica.Data.Inventory.HarvestedFruits
    if type(fruits) ~= "table" then
        return {}, "no fruit inventory"
    end
    local out = {}
    for key, entry in pairs(fruits) do
        if type(entry) == "table" and entry.Id ~= nil then
            -- tên quả: field FruitName (xác nhận MailboxItemCatalog.lua:293 'p85.FruitName or p85.Name'),
            -- fallback Name/SeedName/CorePartName cho chắc.
            local name = entry.FruitName or entry.Name or entry.SeedName or entry.CorePartName
            table.insert(out, {
                ItemKey = entry.Id,
                DisplayName = type(name) == "string" and name or tostring(key),
                Mutation = entry.Mutation,
                Count = 1,
            })
        end
    end
    return out
end

function Runtime.DoAutoMailFruits()
    local c = CFG.AutoMailFruits
    if not (c and c.Enabled) then return end
    if Runtime.MailboxBlocked("AutoMailFruits") then return end
    if not packet({ "Mailbox", "SendBatch" }) then
        logw("AutoMailFruits: thieu Networking.Mailbox.SendBatch -> tat.")
        c.Enabled = false
        return
    end

    local entries = getFruitInventoryEntries()
    -- Only These Fruits: có list thì chỉ gửi quả tên khớp (best-effort theo field tên ở trên).
    local onlyNames, onlyActive = {}, false
    for _, n in ipairs(type(c.OnlyThese) == "table" and c.OnlyThese or {}) do
        if type(n) == "string" and n ~= "" then onlyNames[string.lower(n)] = true; onlyActive = true end
    end
    -- Keep Favorites: không gửi quả tên nằm trong KeepSeeds.List (để dành).
    local keepFav = {}
    local keepList = CFG.KeepSeeds and type(CFG.KeepSeeds.List) == "table" and CFG.KeepSeeds.List or {}
    for _, n in ipairs(keepList) do
        if type(n) == "string" and n ~= "" then keepFav[string.lower(n)] = true end
    end
    -- LOCK FRUIT: quả tên trong LockFruits.List = KHÓA -> KHÔNG gửi mail (giữ lại như favorite).
    if CFG.LockFruits and type(CFG.LockFruits.List) == "table" then
        for _, n in ipairs(CFG.LockFruits.List) do
            if type(n) == "string" and n ~= "" then keepFav[string.lower(n)] = true end
        end
    end

    local toSend = {}
    for _, e in ipairs(entries) do
        local nm = string.lower(tostring(e.DisplayName))
        local okName = (not onlyActive) or onlyNames[nm] == true
        local favBlocked = false
        for k in pairs(keepFav) do
            if nm:find(k, 1, true) then favBlocked = true break end
        end
        if okName and not favBlocked then table.insert(toSend, e) end
    end

    local minFruits = math.max(math.floor(tonumber(c.MinFruits) or 0), 1)
    if #toSend < minFruits then
        actionLog("AutoMailFruits", "SKIP", ("%d/%d fruit"):format(#toSend, minFruits))
        return
    end

    local userId, recipientName = resolveMailboxRecipient(c, "AutoMailFruits")
    if not userId then return end
    if userId == LocalPlayer.UserId then
        actionLog("AutoMailFruits", "SKIP", "recipient is self")
        return
    end

    local p = packet({ "Mailbox", "SendBatch" })
    local note = tostring(c.Note or "")
    local sent = 0
    local maxPerCycle = math.max(math.floor(tonumber(c.MaxPerCycle) or 20), 1)
    for _, e in ipairs(toSend) do
        if sent >= maxPerCycle then break end
        local items = { { Category = "HarvestedFruits", ItemKey = e.ItemKey, Count = 1 } }
        local ok, success, msg = pcall(function() return p:Fire(userId, items, note) end)
        if not ok then
            actionLog("AutoMailFruits", "ERROR", compactText(success, 60))
            break
        end
        if not success then
            actionLog("AutoMailFruits", "WARN", tostring(msg ~= "" and msg or "could not send fruit"))
            break
        end
        sent = sent + 1
        actionLog("AutoMailFruits", "DONE", tostring(e.DisplayName) .. " -> " .. tostring(recipientName or userId))
        if not waitAlive(0.6) then return end
    end
end

-- GỬI GEAR qua Mailbox. Kho gear STACK theo TÊN: Inventory[Category] = { [tên]=số } (xác nhận MailboxController:788-801).
-- Category gear giftable (MailboxItemCatalog.Categories): Sprinklers/WateringCans/Mushrooms/Gnomes/Trowels/EmptyPots.
-- Gửi item = { Category=loại, ItemKey=tên, Count=n }. Lock list -> KHÔNG gửi (giữ lại). OnlyThese -> chỉ gửi tên trong list.
function Runtime.DoAutoMailGear()
    local c = CFG.AutoMailGear
    if not (c and c.Enabled) then return end
    if Runtime.MailboxBlocked("AutoMailGear") then return end
    if not packet({ "Mailbox", "SendBatch" }) then
        logw("AutoMailGear: thieu Networking.Mailbox.SendBatch -> tat.")
        c.Enabled = false
        return
    end
    local replica = getPlayerReplica()
    local inv = replica and replica.Data and replica.Data.Inventory
    if type(inv) ~= "table" then
        actionLog("AutoMailGear", "SKIP", "no inventory")
        return
    end
    local cats = type(c.Categories) == "table" and c.Categories
        or { "Sprinklers", "WateringCans", "Mushrooms", "Gnomes", "Trowels", "EmptyPots" }
    local lock = {}
    for _, n in ipairs(type(c.Lock) == "table" and c.Lock or {}) do
        if type(n) == "string" and n ~= "" then lock[string.lower(n)] = true end
    end
    local only, onlyActive = {}, false
    for _, n in ipairs(type(c.OnlyThese) == "table" and c.OnlyThese or {}) do
        if type(n) == "string" and n ~= "" then only[string.lower(n)] = true; onlyActive = true end
    end

    local toSend = {}
    for _, cat in ipairs(cats) do
        local bucket = inv[cat]
        if type(bucket) == "table" then
            for name, cnt in pairs(bucket) do
                local n = math.floor(tonumber(cnt) or 0)
                local low = type(name) == "string" and string.lower(name) or ""
                if type(name) == "string" and name ~= "" and n > 0
                    and not lock[low]
                    and ((not onlyActive) or only[low]) then
                    table.insert(toSend, { Category = cat, ItemKey = name, Count = n })
                end
            end
        end
    end
    if #toSend == 0 then
        actionLog("AutoMailGear", "SKIP", "no gear to send")
        return
    end

    local userId, recipientName = resolveMailboxRecipient(c, "AutoMailGear")
    if not userId then return end
    if userId == LocalPlayer.UserId then
        actionLog("AutoMailGear", "SKIP", "recipient is self")
        return
    end

    local p = packet({ "Mailbox", "SendBatch" })
    local note = tostring(c.Note or "")
    local batchMax = math.max(math.floor(tonumber(c.MaxPerBatch) or 20), 1)
    local maxPerCycle = math.max(math.floor(tonumber(c.MaxPerCycle) or 40), 1)
    local sentTotal = 0
    for _, g in ipairs(toSend) do
        if sentTotal >= maxPerCycle then break end
        local remaining = g.Count
        while remaining > 0 and sentTotal < maxPerCycle do
            local chunk = math.min(remaining, batchMax, maxPerCycle - sentTotal)
            local items = { { Category = g.Category, ItemKey = g.ItemKey, Count = chunk } }
            local ok, success, msg = pcall(function() return p:Fire(userId, items, note) end)
            if not ok then
                actionLog("AutoMailGear", "ERROR", compactText(success, 60))
                return
            end
            if not success then
                actionLog("AutoMailGear", "WARN", tostring(msg ~= "" and msg or "could not send gear"))
                break
            end
            sentTotal = sentTotal + chunk
            remaining = remaining - chunk
            State.LastMailGear = os.date("%H:%M:%S") .. (" %s x%d -> %s"):format(tostring(g.ItemKey), chunk, tostring(recipientName or userId))
            actionLog("AutoMailGear", "DONE", ("%s x%d (%s)"):format(tostring(g.ItemKey), chunk, tostring(g.Category)))
            if not waitAlive(0.6) then return end
        end
    end
end

-- LOCK FRUIT = FAVORITE của game: quả tên khớp LockFruits.List -> fire Backpack.SetFruitFavorite(id, true)
-- để game KHÓA (không bán/không gửi) đúng như "favorite" chồng nói. Remote thật: Networking.Backpack.SetFruitFavorite.
-- LƯU Ý: việc favorite có chặn được SellAll hay không là logic SERVER (không có trong source) -> best-effort theo game.
function Runtime.DoLockFavoriteFruits()
    local c = CFG.LockFruits
    if not (c and c.Enabled) then return end
    if not packet({ "Backpack", "SetFruitFavorite" }) then
        logw("LockFruits: thieu Networking.Backpack.SetFruitFavorite -> tat.")
        c.Enabled = false
        return
    end
    local names = {}
    for _, n in ipairs(type(c.List) == "table" and c.List or {}) do
        if type(n) == "string" and n ~= "" then names[string.lower(n)] = true end
    end
    if next(names) == nil then return end
    Runtime.FruitFavorited = Runtime.FruitFavorited or {}
    local done = Runtime.FruitFavorited
    local locked = 0
    local maxPerCycle = math.max(math.floor(tonumber(c.MaxPerCycle) or 30), 1)
    for _, e in ipairs(getFruitInventoryEntries()) do
        if locked >= maxPerCycle then break end
        local id = e.ItemKey
        local nm = string.lower(tostring(e.DisplayName))
        if type(id) == "string" and id ~= "" and not done[id] then
            local match = false
            for k in pairs(names) do if nm:find(k, 1, true) then match = true break end end
            if match then
                local ok, res = firePacket({ "Backpack", "SetFruitFavorite" }, id, true)
                if ok then
                    done[id] = true
                    locked = locked + 1
                    State.LastLockFruit = os.date("%H:%M:%S") .. " " .. tostring(e.DisplayName)
                    actionLog("LockFruits", "FAVORITE", tostring(e.DisplayName))
                end
                if not waitAlive(0.15) then return end
            end
        end
    end
    if locked > 0 then
        actionLog("LockFruits", "DONE", "locked=" .. tostring(locked))
    end
end

-- UNFAVORITE FRUIT (BO KHOA) truoc khi GUI MAIL: qua bi favorite (khoa) khong gui/ban duoc -> bo favorite de gui duoc.
-- Remote thật: Networking.Backpack.SetFruitFavorite(id, false). List rong = BO favorite MOI qua; co List = chi ten khop.
-- LUU Y: NGUOC voi LockFruits. KHONG bat ca 2 cung luc (LockFruits favorite lai -> danh nhau).
function Runtime.DoUnfavoriteFruits()
    local c = CFG.UnfavoriteFruits
    if not (c and c.Enabled) then return end
    if not packet({ "Backpack", "SetFruitFavorite" }) then
        logw("UnfavoriteFruits: thieu Networking.Backpack.SetFruitFavorite -> tat.")
        c.Enabled = false
        return
    end
    local names = {}
    for _, n in ipairs(type(c.List) == "table" and c.List or {}) do
        if type(n) == "string" and n ~= "" then names[string.lower(n)] = true end
    end
    local matchAll = next(names) == nil   -- List rong = bo favorite MOI qua
    Runtime.FruitUnfavorited = Runtime.FruitUnfavorited or {}
    local done = Runtime.FruitUnfavorited
    Runtime.FruitFavorited = Runtime.FruitFavorited or {}
    local unlocked = 0
    local maxPerCycle = math.max(math.floor(tonumber(c.MaxPerCycle) or 30), 1)
    for _, e in ipairs(getFruitInventoryEntries()) do
        if unlocked >= maxPerCycle then break end
        local id = e.ItemKey
        local nm = string.lower(tostring(e.DisplayName))
        if type(id) == "string" and id ~= "" and not done[id] then
            local match = matchAll
            if not match then
                for k in pairs(names) do if nm:find(k, 1, true) then match = true break end end
            end
            if match then
                local ok = firePacket({ "Backpack", "SetFruitFavorite" }, id, false)
                if ok then
                    done[id] = true
                    Runtime.FruitFavorited[id] = nil   -- cho phep LockFruits favorite lai sau neu can
                    unlocked = unlocked + 1
                    State.LastUnfavFruit = os.date("%H:%M:%S") .. " " .. tostring(e.DisplayName)
                    actionLog("UnfavoriteFruits", "UNFAVORITE", tostring(e.DisplayName))
                end
                if not waitAlive(0.12) then return end
            end
        end
    end
    if unlocked > 0 then
        actionLog("UnfavoriteFruits", "DONE", "unlocked=" .. tostring(unlocked))
    end
end
end

-- =====================================================================
-- AutoMailRainbow: phát hiện rainbow seed trong người -> đợi DELAY -> gửi qua Mailbox cho 1 acc.
--   Remote thật: Networking.Mailbox.SendBatch / LookupPlayer (Networking.lua:379-380).
--   item = { Category = "Seeds", ItemKey = <seedKey>, Count = n } (MailboxController.lua:991-996).
--   Mailbox trừ từ Inventory.Seeds (data), KHÔNG trừ Tool trong Backpack.
--   Gói trong do/end + export qua Runtime để không chiếm thêm slot local ở main scope.
-- =====================================================================
do
    local MailRainbowSentKeys = {} -- chống gửi trùng trong phiên (theo itemKey)
    local MailRainbowSeq = 0       -- đếm số lần gửi để tạo webhook key duy nhất

    -- Lấy đúng ItemKey rainbow trong Inventory.Seeds để gửi không lỗi.
    local function resolveMailRainbowItemKey(tool)
        -- 1) Ưu tiên đọc kho thật (PlayerStateClient.Data.Inventory.Seeds)
        local replica = getPlayerReplica()
        if replica and replica.Data and type(replica.Data.Inventory) == "table" then
            local seeds = replica.Data.Inventory.Seeds
            if type(seeds) == "table" then
                for key, count in pairs(seeds) do
                    if type(key) == "string" and (tonumber(count) or 0) > 0 and hasRainbowText(key) then
                        return key, tonumber(count) or 0
                    end
                end
            end
        end
        -- 2) Fallback: attribute SeedTool của tool
        if tool then
            local st = tool:GetAttribute("SeedTool")
            if type(st) == "string" and st ~= "" then
                return st, nil
            end
        end
        -- 3) Fallback cuối: theo buffer mẫu (ItemKey = "Rainbow")
        return "Rainbow", nil
    end

    local function resolveMailRainbowRecipient(c)
        -- Nhiều người nhận: RecipientUsernames là list -> random 1 tên mỗi lần (có list thì bỏ qua UserId).
        local username = c.RecipientUsername
        local hasList = false
        if type(c.RecipientUsernames) == "table" then
            local pool = {}
            for _, nm in ipairs(c.RecipientUsernames) do
                if type(nm) == "string" and nm ~= "" then table.insert(pool, nm) end
            end
            if #pool > 0 then
                hasList = true
                username = pool[math.random(1, #pool)]
                if #pool > 1 then actionLog("AutoMailRainbow", "TO", "random -> " .. tostring(username)) end
            end
        end
        if (not hasList) and type(c.RecipientUserId) == "number" and c.RecipientUserId > 0 then
            return c.RecipientUserId
        end
        if type(username) ~= "string" or username == "" then
            actionLog("AutoMailRainbow", "SKIP", "chua cau hinh recipient")
            return nil
        end
        local p = packet({ "Mailbox", "LookupPlayer" })
        if not p then
            actionLog("AutoMailRainbow", "SKIP", "thieu Mailbox.LookupPlayer")
            return nil
        end
        local ok, userId, name = pcall(function()
            return p:Fire(username)
        end)
        if not ok then
            actionLog("AutoMailRainbow", "ERROR", "LookupPlayer " .. compactText(userId, 60))
            return nil
        end
        if type(userId) ~= "number" or userId <= 0 then
            actionLog("AutoMailRainbow", "SKIP", "khong thay user '" .. tostring(username) .. "'")
            return nil
        end
        return userId, name
    end

    -- Webhook embed chuyên nghiệp báo cho chồng khi gửi mail thành công.
    -- KHÔNG persist key này: seed gửi đi là rời inventory rồi, và itemKey chung ("Rainbow")
    -- nên lưu file sẽ chặn luôn những lần gửi seed mới sau này. Seq chỉ để webhook luôn bắn.
    local function notifyMailRainbowSent(itemKey, sendCount, invCount, recipientName, recipientId, note, resultMsg)
        MailRainbowSeq = MailRainbowSeq + 1
        local key = "mailrb:" .. tostring(MailRainbowSeq) .. ":" .. tostring(itemKey)
        local remain = invCount and tostring(math.max((tonumber(invCount) or 0) - sendCount, 0)) or "?"
        return sendWebhookOnce(
            key,
            "🌈 Rainbow Seed → Đã Gửi Mailbox",
            ("Đã tự gửi **%s** x%d cho **%s** qua Mailbox."):format(
                tostring(itemKey), sendCount, tostring(recipientName or recipientId)),
            {
                webhookField("👤 Acc gửi", getAccountName(), true),
                webhookField("🆔 UserId gửi", tostring(LocalPlayer.UserId), true),
                webhookField("🌱 Seed", tostring(itemKey), true),
                webhookField("📨 Người nhận", tostring(recipientName or "-"), true),
                webhookField("🔖 UserId nhận", tostring(recipientId or "-"), true),
                webhookField("📦 Đã gửi", "x" .. tostring(sendCount), true),
                webhookField("🎒 Kho còn lại", remain, true),
                webhookField("📝 Ghi chú", tostring(note ~= "" and note or "-"), true),
                webhookField("✅ Kết quả", tostring(resultMsg ~= "" and resultMsg or "Gift sent!"), false),
            },
            0x9B59B6, -- tím rainbow
            {
                author = "Kaitun • AutoMailRainbow",
                footer = "Kaitun AutoMailRainbow • " .. getAccountName(),
            }
        )
    end

    function Runtime.DoAutoMailRainbow()
        local c = CFG.AutoMailRainbow
        if not (c and c.Enabled) then return end
        if Runtime.MailboxBlocked("AutoMailRainbow") then return end
        if not packet({ "Mailbox", "SendBatch" }) then
            logw("AutoMailRainbow: thieu Networking.Mailbox.SendBatch -> tat.")
            c.Enabled = false
            return
        end

        -- Tìm rainbow seed trong Backpack/Character (cùng logic ValuableWatcher).
        local tool
        for _, t in ipairs(getAllTools()) do
            if isRainbowSeedTool(t) then
                tool = t
                break
            end
        end
        if not tool then
            return
        end

        local itemKey = resolveMailRainbowItemKey(tool)
        if c.SkipResentKey ~= false and MailRainbowSentKeys[itemKey] then
            return
        end

        actionLog("AutoMailRainbow", "DETECTED", "key=" .. tostring(itemKey))

        local delayBeforeSend = math.max(tonumber(c.DelayBeforeSend) or 0, 0)
        if delayBeforeSend > 0 then
            if not waitAlive(delayBeforeSend) then return end
        end

        -- Còn rainbow seed sau khi đợi mới gửi (tránh đã trồng/dùng hết trong lúc chờ).
        local stillHas = false
        for _, t in ipairs(getAllTools()) do
            if isRainbowSeedTool(t) then
                stillHas = true
                break
            end
        end
        if not stillHas then
            actionLog("AutoMailRainbow", "SKIP", "het rainbow seed sau khi doi")
            return
        end

        -- Đọc lại key + số lượng kho ngay trước khi gửi (cho webhook chính xác).
        local finalKey, invCount = resolveMailRainbowItemKey(tool)
        itemKey = finalKey or itemKey

        local userId, recipientName = resolveMailRainbowRecipient(c)
        if not userId then return end

        local sendCount = math.max(tonumber(c.SendCount) or 1, 1)
        local note = tostring(c.Note or "")
        local items = {
            { Category = "Seeds", ItemKey = itemKey, Count = sendCount },
        }
        local p = packet({ "Mailbox", "SendBatch" })
        local ok, success, msg = pcall(function()
            return p:Fire(userId, items, note)
        end)
        if not ok then
            actionLog("AutoMailRainbow", "ERROR", "SendBatch " .. compactText(success, 60))
            return
        end

        if success then
            if c.SkipResentKey ~= false then
                MailRainbowSentKeys[itemKey] = true
            end
            State.LastMailRainbow = os.date("%H:%M:%S")
                .. (" sent %s x%d -> %s"):format(tostring(itemKey), sendCount, tostring(recipientName or userId))
            actionLog("AutoMailRainbow", "DONE", tostring(msg ~= "" and msg or "Gift sent!"))
            -- Gửi thành công -> báo webhook embed cho chồng.
            notifyMailRainbowSent(itemKey, sendCount, invCount, recipientName, userId, note, msg)
        else
            State.LastMailRainbow = os.date("%H:%M:%S") .. " fail"
            actionLog("AutoMailRainbow", "WARN", tostring(msg ~= "" and msg or "Could not send gift"))
        end
    end
end

-- =====================================================================
-- AutoMailPets: gửi pet theo TÊN (PetNames) đang TRONG TÚI (chưa equip) qua Mailbox.
--   Remote thật: Networking.Mailbox.SendBatch (Networking.lua:379).
--   item = { Category = "Pets", ItemKey = <petId>, Count = 1 } (MailboxController.lua:991-995).
--   Pet phải Equipped ~= true mới gift được (MailboxController.lua:650-659).
--   Gói trong do/end + export qua Runtime để không chiếm thêm slot local ở main scope.
-- =====================================================================
do
    local MailPetSentIds = {} -- chống gửi trùng trong phiên (theo petId)
    local MailPetSentVariant = {} -- [nameKey][variant] = số đã gửi trong phiên (để cap "gửi N con mỗi size")
    local MailPetSeq = 0      -- tạo webhook key duy nhất mỗi lần gửi

    local function resolveMailPetRecipient(c)
        -- Nhiều người nhận: RecipientUsernames là list -> random 1 tên mỗi lần (có list thì bỏ qua UserId).
        local username = c.RecipientUsername
        local hasList = false
        if type(c.RecipientUsernames) == "table" then
            local pool = {}
            for _, nm in ipairs(c.RecipientUsernames) do
                if type(nm) == "string" and nm ~= "" then table.insert(pool, nm) end
            end
            if #pool > 0 then
                hasList = true
                username = pool[math.random(1, #pool)]
                if #pool > 1 then actionLog("AutoMailPets", "TO", "random -> " .. tostring(username)) end
            end
        end
        if (not hasList) and type(c.RecipientUserId) == "number" and c.RecipientUserId > 0 then
            return c.RecipientUserId
        end
        if type(username) ~= "string" or username == "" then
            actionLog("AutoMailPets", "SKIP", "chua cau hinh recipient")
            return nil
        end
        local p = packet({ "Mailbox", "LookupPlayer" })
        if not p then
            actionLog("AutoMailPets", "SKIP", "thieu Mailbox.LookupPlayer")
            return nil
        end
        local ok, userId, name = pcall(function()
            return p:Fire(username)
        end)
        if not ok then
            actionLog("AutoMailPets", "ERROR", "LookupPlayer " .. compactText(userId, 60))
            return nil
        end
        if type(userId) ~= "number" or userId <= 0 then
            actionLog("AutoMailPets", "SKIP", "khong thay user '" .. tostring(username) .. "'")
            return nil
        end
        return userId, name
    end

    -- Pet chưa equip, TÊN nằm trong PetNames, chưa gửi trong phiên này.
    local function buildMailPetCandidates(c)
        -- PetNames nhận: "Tên" (gửi MỌI size) | "Tên, Huge=0, rainbow=1" (gửi theo size, 0=ko gửi) |
        --   ["Tên"]={Rainbow=1,Huge=0} (map theo size) | ["Tên"]=N (gửi tối đa N con bất kể size).
        -- Số = SỐ CON GỬI (không phải ngưỡng). Đếm theo Size/Type pet trong kho.
        local wantByName = {}   -- [nameKey] = { all=true } | { variants={Rainbow=1,...} } | { total=N }
        if type(c.PetNames) == "table" then
            for key, value in pairs(c.PetNames) do
                local name, vmap, total
                if type(value) == "string" then
                    name, vmap, total = Runtime.ParsePetSizeSpec(value)        -- dạng mảng {"Tên"} hoặc {"Tên, Huge=0, rainbow=1"}
                elseif type(key) == "string" and value ~= false then
                    name = key                                                 -- dạng map {Tên=N} hoặc {Tên={...}}
                    local _, vm, tt = Runtime.ParsePetSizeSpec(value)
                    vmap, total = vm, tt
                end
                if name and name ~= "" then
                    local k = normPetKey(name)
                    if vmap then wantByName[k] = { variants = vmap }
                    elseif total then wantByName[k] = { total = total }
                    else wantByName[k] = { all = true } end
                end
            end
        end
        if next(wantByName) == nil then return {} end
        -- gom pet CHƯA equip theo tên + variant
        local byNameVar = {}   -- [k][variant] = { entries }
        for _, e in ipairs(Runtime.GetPetInventoryEntries()) do
            if not e.Equipped and type(e.Id) == "string" and e.Id ~= "" and not MailPetSentIds[e.Id]
                and type(e.Name) == "string" then
                local k = normPetKey(e.Name)
                if wantByName[k] then
                    local v = Runtime.ClassifyPetVariant(e.Size, e.Type)
                    byNameVar[k] = byNameVar[k] or {}
                    byNameVar[k][v] = byNameVar[k][v] or {}
                    table.insert(byNameVar[k][v], e)
                end
            end
        end
        local out = {}
        for k, w in pairs(wantByName) do
            local vmap = byNameVar[k]
            if vmap then
                if w.all then
                    for _, group in pairs(vmap) do for _, e in ipairs(group) do out[#out + 1] = e end end
                elseif w.variants then
                    for variant, cap in pairs(w.variants) do
                        local already = (MailPetSentVariant[k] and MailPetSentVariant[k][variant]) or 0
                        local remain = (tonumber(cap) or 0) - already   -- còn được gửi mấy con size này
                        if remain > 0 and vmap[variant] then
                            local n = 0
                            for _, e in ipairs(vmap[variant]) do
                                if n >= remain then break end
                                out[#out + 1] = e; n = n + 1
                            end
                        end
                    end
                elseif w.total then
                    local n = 0
                    for _, group in pairs(vmap) do
                        for _, e in ipairs(group) do
                            if n >= w.total then break end
                            out[#out + 1] = e; n = n + 1
                        end
                        if n >= w.total then break end
                    end
                end
            end
        end
        -- Xịn nhất gửi trước.
        table.sort(out, function(a, b)
            return getPetScore(a.Name) > getPetScore(b.Name)
        end)
        return out
    end

    local function notifyMailPetSent(petName, rarity, petType, recipientName, recipientId, note, resultMsg)
        MailPetSeq = MailPetSeq + 1
        local key = "mailpet:" .. tostring(MailPetSeq) .. ":" .. tostring(petName)
        return sendWebhookOnce(
            key,
            "🐾 Pet → Đã Gửi Mailbox",
            ("Đã tự gửi **%s** • **%s** cho **%s** qua Mailbox."):format(
                tostring(petName), tostring(rarity), tostring(recipientName or recipientId)),
            {
                webhookField("👤 Acc gửi", getAccountName(), true),
                webhookField("🆔 UserId gửi", tostring(LocalPlayer.UserId), true),
                webhookField("🐾 Pet", tostring(petName), true),
                webhookField("⭐ Độ hiếm", tostring(rarity), true),
                webhookField("🧬 Loại", tostring(petType ~= nil and petType ~= "" and petType or "-"), true),
                webhookField("📨 Người nhận", tostring(recipientName or "-"), true),
                webhookField("🔖 UserId nhận", tostring(recipientId or "-"), true),
                webhookField("📝 Ghi chú", tostring(note ~= "" and note or "-"), true),
                webhookField("✅ Kết quả", tostring(resultMsg ~= "" and resultMsg or "Gift sent!"), false),
            },
            Runtime.RarityColor(rarity, 0xE67E22),
            {
                author = "Kaitun • AutoMailPets",
                footer = "Kaitun AutoMailPets • " .. getAccountName(),
                thumbnail = Runtime.GetPetImage(petName),
            }
        )
    end

    notifyMailPetSent = function(petName, rarity, petType, recipientName, recipientId, note, resultMsg)
        MailPetSeq = MailPetSeq + 1
        local key = "mailpet:" .. tostring(MailPetSeq) .. ":" .. tostring(petName)
        return sendWebhookOnce(
            key,
            "Pet -> Da Gui Mailbox",
            ("%s %s -> %s"):format(tostring(petName), tostring(rarity), tostring(recipientName or recipientId)),
            {
                webhookField("Acc gui", getAccountName(), true),
                webhookField("Acc nhan", tostring(recipientName or "-"), true),
                webhookField("Pet", tostring(petName), true),
                webhookField("Do hiem", tostring(rarity), true),
                webhookField("Ket qua", tostring(resultMsg ~= "" and resultMsg or "Gift sent!"), false),
            },
            Runtime.RarityColor(rarity, 0xE67E22),
            {
                footer = "Kaitun AutoMailPets - " .. getAccountName(),
            }
        )
    end

    function Runtime.DoAutoMailPets()
        local c = CFG.AutoMailPets
        if not (c and c.Enabled) then return end
        if Runtime.MailboxBlocked("AutoMailPets") then return end
        if not packet({ "Mailbox", "SendBatch" }) then
            logw("AutoMailPets: thieu Networking.Mailbox.SendBatch -> tat.")
            c.Enabled = false
            return
        end

        local candidates = buildMailPetCandidates(c)
        if #candidates == 0 then
            return
        end

        actionLog("AutoMailPets", "DETECTED", "pets=" .. tostring(#candidates))

        local delayBeforeSend = math.max(tonumber(c.DelayBeforeSend) or 0, 0)
        if delayBeforeSend > 0 then
            if not waitAlive(delayBeforeSend) then return end
            -- đọc lại sau khi đợi (pet có thể đã bị equip/đổi trạng thái trong lúc chờ)
            candidates = buildMailPetCandidates(c)
            if #candidates == 0 then
                actionLog("AutoMailPets", "SKIP", "het pet du dieu kien sau khi doi")
                return
            end
        end

        local userId, recipientName = resolveMailPetRecipient(c)
        if not userId then return end
        if userId == LocalPlayer.UserId then
            actionLog("AutoMailPets", "SKIP", "recipient la chinh acc nay")
            return
        end

        local note = tostring(c.Note or "")
        local p = packet({ "Mailbox", "SendBatch" })
        local sent = 0
        local maxPerCycle = math.max(tonumber(c.MaxPerCycle) or 2, 1)
        for _, e in ipairs(candidates) do
            if sent >= maxPerCycle then break end
            local items = {
                { Category = "Pets", ItemKey = e.Id, Count = 1 },
            }
            local ok, success, msg = pcall(function()
                return p:Fire(userId, items, note)
            end)
            if not ok then
                actionLog("AutoMailPets", "ERROR", "SendBatch " .. compactText(success, 60))
            elseif success then
                if c.SkipResentKey ~= false then
                    MailPetSentIds[e.Id] = true
                end
                -- đếm đã gửi theo tên+variant (để cap "gửi N con mỗi size" đúng tổng, không gửi dư qua nhiều vòng)
                local k = normPetKey(e.Name)
                local v = Runtime.ClassifyPetVariant(e.Size, e.Type)
                MailPetSentVariant[k] = MailPetSentVariant[k] or {}
                MailPetSentVariant[k][v] = (MailPetSentVariant[k][v] or 0) + 1
                sent = sent + 1
                State.LastMailPets = os.date("%H:%M:%S")
                    .. (" sent %s(%s) -> %s"):format(tostring(e.Name), tostring(e.Rarity), tostring(recipientName or userId))
                actionLog("AutoMailPets", "DONE", ("%s %s"):format(tostring(e.Name), tostring(msg ~= "" and msg or "Gift sent!")))
                notifyMailPetSent(e.Name, e.Rarity, e.Type, recipientName, userId, note, msg)
                -- giãn nhịp > cooldown webhook (CFG.Webhook.Cooldown, mặc định 2s) để embed mỗi
                -- con pet đều gửi được, không bị rớt do cooldown.
                if not waitAlive(math.max((tonumber(CFG.Webhook and CFG.Webhook.Cooldown) or 2) + 0.5, 1)) then return end
            else
                State.LastMailPets = os.date("%H:%M:%S") .. " fail " .. tostring(e.Name)
                actionLog("AutoMailPets", "WARN", tostring(e.Name) .. " " .. tostring(msg ~= "" and msg or "Could not send gift"))
                if not waitAlive(0.6) then return end
            end
        end
    end
end

local function doAutoSnapPets()
    local c = CFG.AutoSnapPets
    if not (c and c.Enabled) then return end
    if not packet({ "Pets", "SnapPets" }) then
        logw("AutoSnapPets: thieu Networking.Pets.SnapPets -> tat.")
        c.Enabled = false
        return
    end
    local root = getRootPart()
    if not root then
        actionLog("AutoSnapPets", "SKIP", "missing root")
        return
    end
    if firePacket({ "Pets", "SnapPets" }, root.Position) then
        State.LastSnap = os.date("%H:%M:%S") .. " ok"
        actionLog("AutoSnapPets", "DONE")
    end
end

local function doAutoSpendSkill()
    local c = CFG.AutoSpendSkill
    if not (c and c.Enabled) then return end
    if not packet({ "SkillPoints", "SpendSkillPoint" }) then
        logw("AutoSpendSkill: thiếu Networking.SkillPoints.SpendSkillPoint -> tắt.")
        c.Enabled = false
        return
    end
    local skillData = LocalPlayer:FindFirstChild("SkillData")
    local pointsObj = skillData and skillData:FindFirstChild("SkillPoints")
    if not pointsObj then
        actionLog("AutoSpendSkill", "SKIP", "missing SkillData/SkillPoints")
        return
    end
    local priority = c.Priority or { "MaxBackpack", "ShovelPower", "BaseSpeed", "BaseJump" }
    local spent = 0
    for _ = 1, 40 do
        local points = tonumber(pointsObj.Value) or 0
        if points <= 0 then break end
        local target
        for _, skillName in ipairs(priority) do
            local sk = skillData:FindFirstChild(skillName)
            local lvl = sk and tonumber(sk.Value)
            if lvl and lvl <= points then
                target = skillName
                break
            end
        end
        if not target then break end
        actionLog("AutoSpendSkill", "SPEND", target .. " points=" .. tostring(points))
        firePacket({ "SkillPoints", "SpendSkillPoint" }, target)
        spent = spent + 1
        if not waitAlive(tonumber(c.Delay) or 0.3) then return end
    end
    if spent > 0 then
        actionLog("AutoSpendSkill", "DONE", "spent=" .. tostring(spent))
    end
end

-- Mở rộng vườn (xác nhận PlotsController.lua:337: Networking.Actions.ExpandGarden:Fire())

-- Mua thêm ô pet (xác nhận PetListController.lua:448: RequestPurchasePetSlot:Fire())

local function getNextPetSlotPrice()
    if not (PetSlotPrices and type(PetSlotPrices.GetNextPrice) == "function") then
        return nil
    end
    return tonumber(PetSlotPrices.GetNextPrice(getMaxEquippedPets()))
end

local function doAutoPurchasePetSlot()
    local c = CFG.AutoPurchasePetSlot
    if not (c and c.Enabled) then return end
    if Runtime.ShouldYieldForSeedPriority("AutoPurchasePetSlot") or Runtime.ShouldYieldForPetPriority("AutoPurchasePetSlot") then
        return
    end
    if not packet({ "Pets", "RequestPurchasePetSlot" }) then
        logw("AutoPurchasePetSlot: thieu Networking.Pets.RequestPurchasePetSlot -> tat.")
        c.Enabled = false
        return
    end
    -- Max Pet Slots: đã đạt số ô tối đa cho phép thì ngừng mua (0 = không giới hạn, mua tới max game).
    local maxSlots = tonumber(c.MaxSlots) or 0
    if maxSlots > 0 and getMaxEquippedPets() >= maxSlots then
        actionLog("AutoPurchasePetSlot", "SKIP", "reached MaxSlots " .. tostring(maxSlots))
        return
    end
    -- FIX (chong: "khong mua slot equip pet du du tien"): truoc day LUON nhuong mua seed truoc -> Fresh Acc
    -- mua seed math.huge nen buildSeedCandidates luon co hang -> pet slot khong bao gio toi luot. Mac dinh
    -- IgnoreSeedFirst=true -> mua slot NGAY khi du tien (slot re + 1 lan/nang cap). false = nhuong seed nhu cu.
    if c.IgnoreSeedFirst ~= true and CFG.AutoBuySeed and CFG.AutoBuySeed.Enabled then
        local seedCandidates = buildSeedCandidates(CFG.AutoBuySeed)
        if type(seedCandidates) == "table" and #seedCandidates > 0 then
            actionLog("AutoPurchasePetSlot", "SKIP", "seed first " .. tostring(seedCandidates[1].Name))
            return
        end
    end
    local price = getNextPetSlotPrice()
    if not price then
        actionLog("AutoPurchasePetSlot", "SKIP", "max")
        return
    end
    local keep = tonumber(c.KeepSheckles) or 0
    local money = tonumber(getSheckles()) or 0
    if money - keep < price then
        actionLog("AutoPurchasePetSlot", "SKIP", "need=" .. tostring(price))
        return
    end
    actionLog("AutoPurchasePetSlot", "BUY", "$" .. tostring(price))
    firePacket({ "Pets", "RequestPurchasePetSlot" })
end

local function getWildPetRefFolder()
    local map = workspace:FindFirstChild("Map")
    return map and map:FindFirstChild("WildPetRef")
end

-- Bắn ĐÚNG ProximityPrompt "BuyPrompt" của CHÍNH con wild pet (ref truyền vào) để mua ĐÚNG con đó.
-- Source SpawnPetController:550 -> model tên "WildPet_{petName}_{ref.Name}" => link ref<->model bằng TÊN (ref.Name là UUID duy nhất).
-- (1) KHỚP ĐÚNG con: model có tên kết thúc "_{ref.Name}" -> bắn BuyPrompt của nó -> KHÔNG mua nhầm Frog/con đi ngang.
-- (2) Fallback: prompt gần ref nhất (nếu vì lý do gì không khớp tên). Đều FORCE bật prompt trước khi bắn.
local function fireWildPetBuyPrompt(refPart)
    if type(fireproximityprompt) ~= "function" or not (refPart and refPart.Parent) then
        return false
    end
    local map = workspace:FindFirstChild("Map")
    local spawns = map and map:FindFirstChild("WildPetSpawns")
    if not spawns then return false end
    -- (1) MATCH ĐÚNG TÊN con pet: model kết thúc bằng "_{ref.Name}".
    local refName = refPart.Name
    if type(refName) == "string" and refName ~= "" then
        local suffix = "_" .. refName
        local slen = #suffix
        for _, m in ipairs(spawns:GetChildren()) do
            local n = m.Name
            if #n >= slen and string.sub(n, #n - slen + 1) == suffix then
                local prompt = m:FindFirstChild("BuyPrompt", true)
                if prompt and prompt:IsA("ProximityPrompt") then
                    Runtime.ensurePromptFireable(prompt)
                    return (pcall(fireproximityprompt, prompt))
                end
                break
            end
        end
    end
    -- (2) FALLBACK: prompt gần vị trí ref nhất (force bật).
    local refPos = refPart.Position
    local best, bestDist
    for _, m in ipairs(spawns:GetChildren()) do
        local prompt = m:FindFirstChild("BuyPrompt", true)
        if prompt and prompt:IsA("ProximityPrompt") then
            local part = prompt.Parent
            local pos
            if part and part:IsA("BasePart") then
                pos = part.Position
            elseif m:IsA("Model") then
                local ok, piv = pcall(function() return m:GetPivot().Position end)
                if ok then pos = piv end
            end
            if pos then
                local d = (refPos - pos).Magnitude
                if not best or d < bestDist then
                    best, bestDist = prompt, d
                end
            end
        end
    end
    if best and bestDist and bestDist <= 30 then
        Runtime.ensurePromptFireable(best)   -- FORCE Enabled=true + HoldDuration=0 + MaxDist>=15 -> mua duoc DU game disable prompt
        return (pcall(fireproximityprompt, best))
    end
    return false
end

local function getWildPetRarity(ref, petName)
    local rarity = ref and ref:GetAttribute("Rarity")
    if type(rarity) == "string" and rarity ~= "" then
        return normalizeRarity(rarity)
    end
    local data = PetData and PetData[petName]
    return normalizeRarity(data and data.Rarity or "Common")
end

local function buildWildPetCandidates(c)
    local folder = getWildPetRefFolder()
    local out = {}
    if not folder then
        return out, "no WildPetRef"
    end
    local keep = tonumber(c.KeepSheckles) or 0
    local money = tonumber(getSheckles()) or 0
    local budget = math.max(money - keep, 0)
    local minRarity = c.MinRarity or "Common"

    -- MUA THEO SIZE: OwnLimit = { [tên] = SỐ (cap tổng mọi size) HOẶC { Normal=,Big=,Huge=,Rainbow= } (cap theo size) }.
    --   0 / không ghi size = KHÔNG mua size đó. Mua tới khi SỞ HỮU đủ số mỗi size (đếm theo Size/Type pet).
    -- Không có OwnLimit nhưng có PetNames -> tame tên trong list (mọi size). Không có gì -> theo MinRarity.
    local capByName   -- [nameKey] = { variants = {Huge=9,...} } HOẶC { total = number }
    if type(c.OwnLimit) == "table" and next(c.OwnLimit) ~= nil then
        capByName = {}
        for kName, spec in pairs(c.OwnLimit) do
            if type(kName) == "string" then
                local _, vmap, total = Runtime.ParsePetSizeSpec(spec)
                if vmap then capByName[normPetKey(kName)] = { variants = vmap }
                elseif total then capByName[normPetKey(kName)] = { total = total } end
            end
        end
    end
    local nameFilter
    if not capByName and type(c.PetNames) == "table" and #c.PetNames > 0 then
        nameFilter = {}
        for _, n in ipairs(c.PetNames) do
            if type(n) == "string" and n ~= "" then nameFilter[normPetKey(n)] = true end
        end
    end
    -- BUY THEO SIZE/LOAI (auto-detect, KHONG can khai ten): BuyVariants = { Big=true, Huge=true, Rainbow=true }.
    -- Detect bang attribute that PetSize/PetType tren WildPetRef (xac nhan SpawnPetController:552-553 +
    -- PetSizes.Normalize "Big"/"Huge" + PetTypes.Rainbow="Rainbow"). Map tu Pets.BuyBig/BuyHuge/BuyRainbow.
    local buyVariants
    if type(c.BuyVariants) == "table" then
        for k, v in pairs(c.BuyVariants) do
            if v == true then
                local kl = tostring(k):lower():gsub("%s+", "")
                local canon = (kl == "huge" and "Huge") or (kl == "big" and "Big")
                    or (kl == "rainbow" and "Rainbow") or (kl == "normal" and "Normal") or nil
                if canon then buyVariants = buyVariants or {}; buyVariants[canon] = true end
            end
        end
    end
    local hasExplicitFilter = (capByName ~= nil) or (nameFilter ~= nil) or (buyVariants ~= nil)
    -- Sở hữu: theo TÊN (cap tổng) + theo TÊN+VARIANT (cap size). Đếm 1 lần từ Inventory.Pets (có Size/Type).
    local ownedTotal = capByName and Runtime.GetOwnedPetCounts() or {}
    local ownedVar   = capByName and Runtime.GetOwnedPetVariantCounts() or {}
    local plannedTotal, plannedVar = {}, {}   -- đã thêm vào candidate vòng này (theo tên / tên+variant)

    for _, ref in ipairs(folder:GetChildren()) do
        if ref:IsA("BasePart") then
            local petName = ref:GetAttribute("PetName")
            local ownerUserId = ref:GetAttribute("OwnerUserId")
            local price = tonumber(ref:GetAttribute("Price")) or 0
            if type(petName) == "string" and petName ~= "" and ownerUserId ~= LocalPlayer.UserId and price <= budget then
                local rarity = getWildPetRarity(ref, petName)
                local lname = normPetKey(petName)
                local petSize = ref:GetAttribute("PetSize")              -- "Big"/"Huge"/nil
                local petType = ref:GetAttribute("PetType")              -- "Rainbow"/nil
                local variant = Runtime.ClassifyPetVariant(petSize, petType)  -- Normal/Big/Huge/Rainbow
                local allow = false
                if c.BuyAllWildPets then
                    allow = true   -- MUA-TAT: moi wild pet mua noi (gia<=budget, khong phai cua minh), bo loc ten/do hiem (giong hic.lua)
                elseif buyVariants and buyVariants[variant] then
                    allow = true   -- BUY THEO SIZE: mua MOI con Big/Huge/Rainbow (auto-detect attribute), khong can khai ten
                elseif capByName then
                    local capE = capByName[lname]
                    if capE then
                        if capE.variants then
                            local cap = tonumber(capE.variants[variant]) or 0   -- 0/nil -> KHÔNG mua size này
                            local have = ((ownedVar[lname] or {})[variant] or 0) + ((plannedVar[lname] or {})[variant] or 0)
                            allow = cap > 0 and have < cap
                        elseif capE.total then
                            local have = (ownedTotal[lname] or 0) + (plannedTotal[lname] or 0)
                            allow = capE.total > 0 and have < capE.total
                        end
                    end
                elseif nameFilter then
                    allow = nameFilter[lname] == true
                elseif not hasExplicitFilter then
                    allow = rarityAllowed(rarity, minRarity)   -- chi fallback do-hiem khi KHONG khai filter nao (tranh BuyHuge keo theo mua bua theo rarity)
                end
                if allow then
                    plannedTotal[lname] = (plannedTotal[lname] or 0) + 1
                    plannedVar[lname] = plannedVar[lname] or {}
                    plannedVar[lname][variant] = (plannedVar[lname][variant] or 0) + 1
                    -- ưu tiên mua trước: Rainbow > Huge > Big > Normal (cộng TRÊN điểm rarity*1e8).
                    local sizeBonus = (variant == "Rainbow" and 3e9) or (variant == "Huge" and 2e9) or (variant == "Big" and 1e9) or 0
                    table.insert(out, {
                        Ref = ref,
                        Name = petName,
                        Price = price,
                        Rarity = rarity,
                        Size = type(petSize) == "string" and petSize or nil,
                        Rainbow = variant == "Rainbow",
                        Variant = variant,
                        Score = ((RarityScore[rarity] or 0) * 100000000) + price + sizeBonus,
                    })
                end
            end
        end
    end

    table.sort(out, function(a, b)
        if a.Score ~= b.Score then
            return a.Score > b.Score
        end
        return a.Price > b.Price
    end)
    return out
end

do
    local PetBuySeq = 0
    Runtime.PendingWildPetTames = Runtime.PendingWildPetTames or {}

    local function notifyWildPetBought(info)
        if type(info) ~= "table" then return end
        PetBuySeq = PetBuySeq + 1
        local sizeLabel = info.Rainbow and "Rainbow" or (info.Size and tostring(info.Size) or "-")
        sendWebhookOnce(
            "petbuy:" .. tostring(PetBuySeq) .. ":" .. tostring(info.Name),
            "Pet -> Da Mua Thanh Cong",
            ("%s %s -> %s"):format(tostring(info.Name), tostring(info.Rarity or "-"), getAccountName()),
            {
                webhookField("Acc", getAccountName(), true),
                webhookField("Pet", tostring(info.Name), true),
                webhookField("Do hiem", tostring(info.Rarity or "-"), true),
                webhookField("Size/Loai", sizeLabel, true),
                webhookField("Gia", tostring(info.Price or "-"), true),
            },
            Runtime.RarityColor(info.Rarity, 0xE67E22),
            {
                footer = "Kaitun AutoTameWildPet - " .. getAccountName(),
            }
        )
    end

    function Runtime.SetupWildPetTameWatcher()
        if Runtime.WildPetTameWatcherReady then
            return
        end
        local resultEvent = packet({ "Pets", "WildPetTameResult" })
        if not (resultEvent and resultEvent.OnClientEvent) then
            actionLog("AutoTameWildPet", "SKIP", "missing WildPetTameResult")
            return
        end
        Runtime.WildPetTameWatcherReady = true
        local conn = resultEvent.OnClientEvent:Connect(function(ref, buyerUserId)
            if buyerUserId ~= LocalPlayer.UserId then
                return
            end
            local pending = Runtime.PendingWildPetTames[ref]
            local info = pending
            if not info and typeof(ref) == "Instance" then
                local petName = ref:GetAttribute("PetName")
                if type(petName) == "string" and petName ~= "" then
                    info = {
                        Name = petName,
                        Rarity = getWildPetRarity(ref, petName),
                        Price = tonumber(ref:GetAttribute("Price")) or 0,
                    }
                end
            end
            Runtime.PendingWildPetTames[ref] = nil
            -- MUA PET XONG -> so huu doi -> xoa cache dem pet + cache uu tien de vong sau doc tuoi
            Runtime.EqPetCache = nil
            Runtime.PetPriorityCache = nil
            if info then
                State.LastPet = os.date("%H:%M:%S") .. " bought " .. tostring(info.Name)
                actionLog("AutoTameWildPet", "BOUGHT", tostring(info.Name))   -- BAT LAI: cho chong THAY mua pet thanh cong
                Runtime.HideBlockingPopups()
                notifyWildPetBought(info)
            end
        end)
        table.insert(Runtime.Cleanups, function()
            pcall(function()
                conn:Disconnect()
            end)
        end)
    end
end

local function doAutoTameWildPet()
    local c = CFG.AutoTameWildPet
    if not (c and c.Enabled) then return end
    c.__MovementOwner = "AutoTameWildPet"   -- task nay GIU khoa di chuyen -> khong tu nhuong, task khac nhuong
    Runtime.SetupWildPetTameWatcher()
    -- CHONG MEMORY LEAK: don pending mua pet con sot (ref da destroy/het parent ma watcher chua xoa) -> tranh giu ref chet.
    for ref in pairs(Runtime.PendingWildPetTames) do
        if not (typeof(ref) == "Instance" and ref.Parent) then
            Runtime.PendingWildPetTames[ref] = nil
        end
    end
    if State.SellInProgress or State.AntiStealEngaging then return end
    if not packet({ "Pets", "WildPetTame" }) then
        logw("AutoTameWildPet: thieu Networking.Pets.WildPetTame -> tat.")
        c.Enabled = false
        return
    end
    if Runtime.ShouldYieldForSeedPriority("AutoTameWildPet") then
        return
    end

    local candidates, reason = buildWildPetCandidates(c)
    if #candidates == 0 then
        State.LastPet = os.date("%H:%M:%S") .. " tame skip"
        -- (LOG SKIP da tat theo yeu cau: mua pet khong in log rac)
        return
    end

    local tamed = 0
    local maxPerCycle = math.max(tonumber(c.MaxPerCycle) or 3, 1)
    State.PetTameInProgress = true
    State.PetTameUntil = os.clock() + math.max((maxPerCycle * 0.6) + 1, tonumber(c.PriorityYieldSeconds) or 1.5)

    -- NHAY VE TAM MAP (cho Sell) bang BAM NUT truoc khi mua (giong hi.lua) -> server doi HOP LE, roi tinh
    -- khoang cach pet TU TAM -> tween NGAN toi tung pet -> KHONG di xuyen map -> het giat.
    -- CHONG YEU CAU: UseRespawnTeleport=true -> BO HET buoc nay (khong nhay ra tam map ngoai vuon nua), dung
    -- respawn-teleport thang toi pet giong claim seed -> het "teleport ra ngoai vuon roi tween ve" ban ngay.
    if c.TeleportToPet ~= false
        and c.UseRespawnTeleport ~= true
        and c.UseTweenTeleport ~= false
        and c.UseSellFirst ~= false
        and c.UseSellCenterFirst ~= false then
        Runtime.GoSellCenter(c, "pet start")
        local r = getRootPart()
        local origin = (r and r.Position) or Runtime.GetSellCenterPos(c)
        if origin then
            for _, pet in ipairs(candidates) do
                if pet.Ref and pet.Ref.Parent then
                    pet.Distance = (origin - pet.Ref.Position).Magnitude
                else
                    pet.Distance = math.huge
                end
            end
            if c.SortPetsByCenter ~= false then
                table.sort(candidates, function(a, b)
                    if a.Distance ~= b.Distance then
                        return a.Distance < b.Distance
                    end
                    if a.Score ~= b.Score then
                        return (a.Score or 0) > (b.Score or 0)
                    end
                    return (a.Price or 0) > (b.Price or 0)
                end)
            end
        end
    end

    -- GIỮ VỊ TRÍ NGAY PET (chồng đã xóa Baseplate/Map -> không neo sẽ RỚT khỏi tầm BuyPrompt
    -- trong lúc chờ -> mua hụt). Neo Anchored suốt loop mua, set CFrame vẫn chạy khi anchored.
    -- Thả neo về trạng thái cũ ở MỌI đường thoát (kể cả return giữa chừng).
    -- Đi bộ (UseWalkToPet) thì KHÔNG anchor (anchor sẽ chặn Humanoid:MoveTo). Map còn TopLayer nên đi bộ ko rớt.
    local holdPos = (c.HoldPositionWhileBuying ~= false) and not c.UseWalkToPet
    local holdRoot = holdPos and getRootPart() or nil
    local prevAnchored = holdRoot and holdRoot.Anchored
    local movedAway = false   -- đã teleport rời nhà (tới pet) -> phải về nhà lúc CÒN anchor trước khi thả neo (chống rớt void)
    local function releaseHold()
        if holdRoot and holdRoot.Parent then
            pcall(function() holdRoot.Anchored = prevAnchored == true end)
        end
        State.PetTameInProgress = false
        State.PetTameUntil = os.clock() + 0.5
    end

    for _, pet in ipairs(candidates) do
        if tamed >= maxPerCycle then break end
        if pet.Ref and pet.Ref.Parent then
            if c.TeleportToPet ~= false then
                if c.UseRespawnTeleport == true then
                    -- LOGIC GIONG CLAIM SEED (chong yeu cau): CHET -> respawn -> spam set CFrame thang toi pet.
                    -- Server RESET vi tri luc respawn nen KHONG keo ve -> het "teleport ra ngoai vuon roi tween ve".
                    -- Pet di chuyen -> vong follow ben duoi van set CFrame bam theo. KHONG anchor truoc (char moi).
                    local yOff = tonumber(c.TeleportYOffset) or 1
                    Runtime.RespawnTeleport(pet.Ref.Position + Vector3.new(0, yOff, 0), c.RespawnSpamFrames, c.RespawnSettleWait)
                    movedAway = true
                    -- neo NEW char SAU respawn (giu vi tri canh pet khi cho mua; set CFrame van chay tren anchored).
                    if holdPos then
                        holdRoot = getRootPart()
                        if holdRoot then pcall(function() holdRoot.Anchored = true; holdRoot.AssemblyLinearVelocity = Vector3.zero end) end
                    end
                else
                    -- ANCHOR TRƯỚC KHI teleport (chồng đã xóa nền -> KHÔNG có đất; nếu teleport xong mới neo thì
                    -- trong lúc chờ nhân vật RỚT XUỐNG VOID). Neo trước -> set CFrame vẫn chạy trên part anchored.
                    if holdPos then
                        holdRoot = getRootPart()
                        if holdRoot then pcall(function() holdRoot.Anchored = true; holdRoot.AssemblyLinearVelocity = Vector3.zero end) end
                    end
                    teleportNearPosition(pet.Ref.Position, c)
                    movedAway = true
                    -- neo lại NGAY sau khi dời tới pet (re-fetch root phòng đổi character)
                    if holdPos then
                        holdRoot = getRootPart()
                        if holdRoot then pcall(function() holdRoot.Anchored = true; holdRoot.AssemblyLinearVelocity = Vector3.zero end) end
                    end
                end
                -- CHỜ server (~30 khung/giây) ghi nhận vị trí mới rồi mới mua. Teleport tới rồi dựt về quá nhanh
                -- -> server chưa thấy mình đứng cạnh pet -> mua hụt. (chồng yêu cầu: đứng đó call mua tới khi được)
                if not waitAlive(math.max(tonumber(c.BuySettleWait) or 0.4, 0)) then releaseHold() return end
            end
            -- (LOG BUY da tat theo yeu cau: mua pet khong in log rac. Mo lai dong duoi neu chong muon thay pet mua:)
            -- local sizeTag = pet.Rainbow and "Rainbow " or (pet.Size and (tostring(pet.Size) .. " ") or "")
            -- actionLog("AutoTameWildPet", "BUY", sizeTag .. pet.Name .. " " .. tostring(pet.Rarity) .. " $" .. tostring(pet.Price))
            Runtime.PendingWildPetTames[pet.Ref] = {
                Name = pet.Name,
                Rarity = pet.Rarity,
                Price = pet.Price,
                Size = pet.Size,
                Rainbow = pet.Rainbow,
            }
            -- ĐỨNG TẠI PET BẮN MUA LIÊN TỤC tới ~BuyHoldSeconds giây HOẶC tới khi pet biến mất (mua xong).
            -- BuyPrompt.Triggered tự fire Pets.WildPetTame -> mua (SpawnPetController:693-696). Giữ remote làm fallback.
            -- BAM PET + SPAM TOI KHI MUA DUOC MOI THOI (chong yeu cau): moi nhip (1) follow pet dang di chuyen,
            -- (2) FORCE bat + ban BuyPrompt + remote. Dung khi: OwnerUserId==minh (DA MUA) / pet bien mat / het BuyMaxWait.
            local buyDeadline = os.clock() + math.max(tonumber(c.BuyMaxWait) or 15, tonumber(c.BuyHoldSeconds) or 4, 1)
            local buyInterval = math.max(tonumber(c.BuyFireInterval) or 0.1, 0.05)
            local followYOffset = tonumber(c.TeleportYOffset) or 1
            local blastRadius = math.max(tonumber(c.BuyBlastRadius) or 15, 1)   -- GIONG hic.lua: fire moi prompt <=15 studs
            local blastEvery = math.max(tonumber(c.BuyBlastInterval) or 0.25, 0.1)
            local lastBlast = 0
            local firedAny = false
            local boughtThis = false
            while pet.Ref and pet.Ref.Parent and os.clock() < buyDeadline do
                -- DA MUA DUOC chua? OwnerUserId == minh (xac nhan source SpawnPetController: prompt tat khi minh so huu) -> dung NGAY.
                if pet.Ref:GetAttribute("OwnerUserId") == LocalPlayer.UserId then boughtThis = true; break end
                -- FOLLOW pet dang di chuyen:
                if c.UseWalkToPet then
                    -- DI BO KIEU NGUOI THAT: Humanoid:MoveTo toi vi tri HIEN TAI cua pet (chong yeu cau). Khong anchor.
                    local ch = LocalPlayer.Character
                    local hum = ch and ch:FindFirstChildOfClass("Humanoid")
                    if hum then pcall(function() hum:MoveTo(pet.Ref.Position) end) end
                elseif c.FollowWhileBuying ~= false then
                    -- bam bang set CFrame (anchored van set duoc -> ko rot void).
                    local fr = getRootPart()
                    if fr then
                        pcall(function()
                            fr.CFrame = CFrame.new(pet.Ref.Position + Vector3.new(0, followYOffset, 0))
                            fr.AssemblyLinearVelocity = Vector3.zero
                        end)
                    end
                end
                -- BAN: nham dung con (fireWildPetBuyPrompt) + remote, VA quan trong nhat: BLAST moi prompt <=15 studs
                -- quanh nguoi (DUNG logic hic.lua chong test mua 100%). Throttle ~0.25s cho do nang (hic chay 0.5s).
                local firedPrompt = fireWildPetBuyPrompt(pet.Ref)
                local firedRemote = firePacket({ "Pets", "WildPetTame" }, pet.Ref)
                if firedPrompt or firedRemote then firedAny = true end
                -- BLAST (fire mọi prompt ≤15) CHỈ khi MUA-TẤT (BuyAll). Mua theo DANH SÁCH thì KHÔNG blast
                -- -> chỉ con đúng tên mới bị bắn -> KHÔNG mua nhầm Frog/con đi ngang qua. (chồng yêu cầu)
                if c.BuyAllWildPets and os.clock() - lastBlast >= blastEvery then
                    local br = getRootPart()
                    if br and blastNearbyPrompts(br.Position, blastRadius) > 0 then firedAny = true end
                    lastBlast = os.clock()
                end
                if not waitAlive(buyInterval) then releaseHold() return end
            end
            if not boughtThis and pet.Ref and pet.Ref.Parent then
                boughtThis = pet.Ref:GetAttribute("OwnerUserId") == LocalPlayer.UserId
            end
            if boughtThis then
                tamed = tamed + 1
            else
                Runtime.PendingWildPetTames[pet.Ref] = nil
            end
            -- Pet VAN CON do sau vong mua = chua mua duoc -> bo pending (tranh giu ref chet gay leak).
            if pet.Ref and pet.Ref.Parent then
                Runtime.PendingWildPetTames[pet.Ref] = nil
            end
            -- MUA HUT con nay (pet bien mat het gio / het BuyMaxWait ma chua so huu) -> DUNG vong, VE NHA trong cay,
            -- vong sau thu lai. Tranh camp tren pet khong mua duoc (BuyAll nhieu pet) lam ket trong cay mai. (chong yeu cau)
            if not boughtThis then break end
        end
    end
    -- VỀ NHÀ TRƯỚC KHI THẢ NEO: chồng đã xóa nền -> nếu thả neo lúc đang đứng chỗ pet (void) sẽ RỚT NGAY.
    -- Teleport về plot (part đặc, KHÔNG bị xóa) lúc CÒN anchor -> đáp xuống đất chắc -> rồi mới thả neo.
    -- Về nhà kể cả khi mua hụt (tamed=0) miễn là đã rời nhà, để không kẹt lơ lửng/rớt ngoài void.
    if movedAway and c.ReturnHomeAfterTame ~= false then
        teleportToGardenHome("AutoTameWildPet", 0.05)
    end
    releaseHold()
    if tamed > 0 then
        State.LastPet = os.date("%H:%M:%S") .. " tame=" .. tostring(tamed)
        -- (LOG DONE da tat theo yeu cau: mua pet khong in log rac)
    end
end

-- Số expansion đang sở hữu (replica.Data.OwnedExpansions). Mặc định 1 khi chưa có data.
local function getOwnedExpansions()
    local replica = getPlayerReplica()
    local data = replica and replica.Data
    return tonumber(data and data.OwnedExpansions) or 1
end

local function getNextExpansionPrice()
    if type(ExpansionPrices) ~= "table" then
        return nil
    end
    local owned = getOwnedExpansions()
    local nextEntry = ExpansionPrices[owned + 1]
    return nextEntry and tonumber(nextEntry.Price) or nil
end

function Runtime.doAutoExpandGarden()
    local c = CFG.AutoExpandGarden
    if not (c and c.Enabled) then return end
    if Runtime.ShouldYieldForSeedPriority("AutoExpandGarden") or Runtime.ShouldYieldForPetPriority("AutoExpandGarden") then
        return
    end
    if not packet({ "Actions", "ExpandGarden" }) then
        logw("AutoExpandGarden: thieu Networking.Actions.ExpandGarden -> tat.")
        c.Enabled = false
        return
    end
    -- Nhường mua seed trước CHỈ khi IgnoreSeedFirst=false (mặc định true -> expand mua ngay).
    if c.IgnoreSeedFirst ~= true and CFG.AutoBuySeed and CFG.AutoBuySeed.Enabled then
        local seedCandidates = buildSeedCandidates(CFG.AutoBuySeed)
        if type(seedCandidates) == "table" and #seedCandidates > 0 then
            actionLog("AutoExpandGarden", "SKIP", "seed first " .. tostring(seedCandidates[1].Name))
            return
        end
    end
    -- Giới hạn mốc: chỉ mua tới MaxExpansions là dừng (0 = không giới hạn -> mua hết).
    local maxExp = tonumber(c.MaxExpansions) or 0
    if maxExp > 0 and getOwnedExpansions() >= maxExp then
        actionLog("AutoExpandGarden", "SKIP", "limit " .. tostring(getOwnedExpansions()) .. "/" .. tostring(maxExp))
        return
    end
    local price = getNextExpansionPrice()
    if not price then
        actionLog("AutoExpandGarden", "SKIP", "max")
        return
    end
    local keep = tonumber(c.KeepSheckles) or 0
    local money = tonumber(getSheckles()) or 0
    if money - keep < price then
        actionLog("AutoExpandGarden", "SKIP", "need=" .. tostring(price))
        return
    end
    actionLog("AutoExpandGarden", "BUY", "$" .. tostring(price))
    local ok, res = firePacket({ "Actions", "ExpandGarden" })
    if ok and res == true then
        actionLog("AutoExpandGarden", "DONE")
    end
end

-- ============================================================
-- AUTO TIER (Zero -> Pro): tự chọn cây + quota theo TIỀN. Cây từ SeedData (multi = thu nhiều lần).
-- ============================================================
Runtime.CurrentTier = nil

-- Build PlanQuota + buyCaps cho 1 tier, scale theo TỔNG plots (chủ lực chiếm phần còn lại).
function Runtime.BuildTierPreset(tier, total)
    local quota, buy = {}, {}
    local function add(name, plantQ, buyCap)
        quota[name] = plantQ
        buy[name] = buyCap or plantQ
    end
    -- CUSTOM TIER tu CONFIG: CFG.AutoTier.Tiers[tier] = { Primary="Ten", Fixed = { [ten]=so,... } }.
    --   Fixed = cac cay trong CO DINH so luong; Primary = cay CHU LUC lap day phan plot con lai (total - fixed).
    --   Co khai thi DUNG config; khong thi fallback preset mac dinh ben duoi.
    local fixed, primary
    local cAT = CFG.AutoTier
    local tcfg = (cAT and type(cAT.Tiers) == "table") and cAT.Tiers[tier] or nil
    if type(tcfg) == "table" and (type(tcfg.Fixed) == "table" or type(tcfg.Primary) == "string") then
        fixed   = type(tcfg.Fixed) == "table" and tcfg.Fixed or {}
        primary = type(tcfg.Primary) == "string" and tcfg.Primary ~= "" and tcfg.Primary or nil
    elseif tier == 1 then
        -- ZERO: cây RẺ thu nhanh lấy vốn (Tomato multi restock 90 chủ lực).
        fixed = { Carrot = 5, Strawberry = 10, Blueberry = 10, Corn = 20 }
        primary = "Tomato"
    elseif tier == 2 then
        -- MID: Corn (multi) chủ lực + vài cây phụ.
        fixed = { Carrot = 5, Tulip = 5, Bamboo = 10, Apple = 2, Tomato = 42 }
        primary = "Corn"
    else
        -- PRO: cây XỊN multi đắt (Banana restock 9 chủ lực + nhóm cao cấp).
        fixed = { Mushroom = 10, Grape = 10, Coconut = 10, Mango = 5, ["Dragon Fruit"] = 5 }
        primary = "Banana"
    end
    local used = 0
    for n, v in pairs(fixed) do
        local q = tonumber(v) or 0
        add(n, q, q + 5)
        used = used + q
    end
    -- Primary lap day phan con lai cua TotalPlots (khong khai Primary -> chi trong dung Fixed).
    if primary then
        local mainQ = math.max((tonumber(total) or 100) - used, 1)
        add(primary, mainQ, mainQ)
    end
    return quota, buy
end

function Runtime.doAutoTier()
    local c = CFG.AutoTier
    if not (c and c.Enabled) then return end
    local money = tonumber(getSheckles()) or 0
    local mid = tonumber(c.MoneyMid) or 50000
    local pro = tonumber(c.MoneyPro) or 1000000
    local downMid = tonumber(c.DownMid) or math.floor(mid * 0.6)
    local downPro = tonumber(c.DownPro) or math.floor(pro * 0.7)

    -- Hysteresis: chỉ LÊN khi vượt mốc-trên, chỉ XUỐNG khi tụt dưới mốc-dưới (chống "rung" tier).
    local tier = Runtime.CurrentTier or 1
    local newTier
    if tier <= 1 then
        newTier = (money >= pro and 3) or (money >= mid and 2) or 1
    elseif tier == 2 then
        newTier = (money >= pro and 3) or (money < downMid and 1) or 2
    else
        newTier = (money < downPro and (money < downMid and 1 or 2)) or 3
    end
    -- CHONG "CHET" (chong yeu cau): mac dinh CHI LEN, KHONG TUT tier. Vi cay tier cao deu multi-harvest
    -- (Banana/Coconut/Mango... trong 1 lan thu mai) -> giu lai van kiem tien; tut tier -> TrimToQuota dao
    -- SACH cay xin chi vi tien tut tam thoi (mua expansion/pet) = mat het von. NoDowngrade=false moi cho tut.
    if c.NoDowngrade ~= false and Runtime.CurrentTier and newTier < Runtime.CurrentTier then
        newTier = Runtime.CurrentTier
    end
    if newTier == Runtime.CurrentTier then return end
    Runtime.CurrentTier = newTier

    local total = tonumber(CFG.TotalPlots)
    if not total or total <= 0 then total = countVisiblePlantAreas() end
    if not total or total <= 0 then total = 100 end

    local quota, buyCaps = Runtime.BuildTierPreset(newTier, total)
    -- Áp dụng giống applyConfig PlanQuota (AutoPlant + TrimToQuota + AutoBuySeed).
    CFG.PlanQuota = quota
    local ap = CFG.AutoPlant
    if ap then ap.PlantQuota = quota; ap.OnlyQuota = true; ap.UsePlantQuota = true end
    local tq = CFG.TrimToQuota
    if tq then tq.Quota = quota; tq.DigUnlisted = true end
    local bs = CFG.AutoBuySeed
    if bs then
        bs.Enabled = true; bs.Mode = "List"
        local names = {}
        for n in pairs(buyCaps) do names[#names + 1] = n end
        bs.List = names
        bs.OwnLimitPerSeed = buyCaps
    end
    actionLog("AutoTier", "TIER" .. tostring(newTier),
        ("money=%s total=%s primary=%s"):format(tostring(money), tostring(total),
            newTier == 1 and "Tomato" or newTier == 2 and "Corn" or "Banana"))
end

-- ============================================================
-- ESP + FPS BOOST  (chỉ client, không gọi remote)
-- ============================================================
Runtime.ESPHighlights = {}

Runtime.clearEspHighlights = function()
    for inst, hl in pairs(Runtime.ESPHighlights) do
        pcall(function() hl:Destroy() end)
        Runtime.ESPHighlights[inst] = nil
    end
end

Runtime.ensureHighlight = function(adornee, fillColor)
    local hl = Runtime.ESPHighlights[adornee]
    if hl and hl.Parent then
        return hl
    end
    hl = Instance.new("Highlight")
    hl.Name = "KaitunESP"
    hl.FillColor = fillColor
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.55
    hl.OutlineTransparency = 0.1
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = adornee
    hl.Parent = adornee
    Runtime.ESPHighlights[adornee] = hl
    return hl
end

Runtime.doEsp = function()
    local c = CFG.ESP
    if not (c and (c.ReadyPlants or c.Players)) then
        Runtime.clearEspHighlights()
        return
    end
    local seen = {}
    if c.ReadyPlants then
        for _, prompt in ipairs(CollectionService:GetTagged("HarvestPrompt")) do
            if prompt:IsA("ProximityPrompt") then
                local model = getHarvestPromptModel(prompt)
                if model then
                    seen[model] = true
                    Runtime.ensureHighlight(model, Color3.fromRGB(80, 222, 160))
                end
            end
        end
    end
    if c.Players then
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer and plr.Character then
                seen[plr.Character] = true
                Runtime.ensureHighlight(plr.Character, Color3.fromRGB(248, 113, 113))
            end
        end
    end
    for inst, hl in pairs(Runtime.ESPHighlights) do
        if not seen[inst] or not inst.Parent then
            pcall(function() hl:Destroy() end)
            Runtime.ESPHighlights[inst] = nil
        end
    end
end

Runtime.ApplyFpsCap = function()
    local c = CFG.FpsBoost
    -- DANG TURBO (task nang mo cap 9999) -> KHONG ghi de nguoc ve 7; xong turbo EndTurboFps tu goi lai.
    if (Runtime.TurboDepth or 0) > 0 then
        if os.clock() < (tonumber(Runtime.TurboDeadline) or math.huge) then
            return
        end
        Runtime.TurboDepth = 0
        Runtime.TurboDeadline = nil
        actionLog("FpsBoost", "WARN", "turbo watchdog restored cap")
        if not (c and c.Enabled) then
            local oldCapFn = Runtime.GetFpsCapFn()
            if oldCapFn and tonumber(Runtime.PreTurboCap) then
                pcall(oldCapFn, tonumber(Runtime.PreTurboCap))
                State.FpsCapStatus = "cap=" .. tostring(Runtime.PreTurboCap)
            end
            return
        end
    end
    if not (c and c.Enabled) then
        return
    end
    -- Tim ham cap FPS cua executor (ten khac nhau tuy executor). Khong co -> BAO RO len GUI
    -- (truoc day skip IM LANG khi Debug=false -> chong tuong cap=7 chay ma thuc ra khong cap duoc).
    local capFn = (type(setfpscap) == "function" and setfpscap)
        or (type(set_fps_cap) == "function" and set_fps_cap)
        or nil
    if not capFn then
        State.FpsCapStatus = "cap FAIL: executor khong co setfpscap"
        if Runtime.FpsCapLogged ~= true then
            Runtime.FpsCapLogged = true
            actionLog("FpsBoost", "SKIP", "no setfpscap")
        end
        return
    end
    -- KHÔNG ép tối thiểu 10 nữa: cho phép cap thấp (3-10) đúng ý chồng. Tối thiểu 1 để tránh freeze.
    local target = math.max(math.floor(tonumber(c.TargetFPS) or 30), 1)
    -- LUÔN set lại mỗi vòng (đứng yên ở đúng mức, không để FPS nhảy lung tung).
    local ok = pcall(capFn, target)
    if ok then
        State.FpsCapStatus = "cap=" .. tostring(target)
        if Runtime.LastFpsCap ~= target then
            Runtime.LastFpsCap = target
            actionLog("FpsBoost", "APPLIED", "cap=" .. tostring(target))
        end
    else
        State.FpsCapStatus = "cap=" .. tostring(target) .. " LOI"
        actionLog("FpsBoost", "ERROR", "setfpscap failed")
    end
end

-- ON DINH CAMERA (fix "tween toi seed -> goc nhin bay xa"): khoa CameraMaxZoomDistance ve khoang gan
-- co dinh nen o khong gian mo (giua map) camera khong phong xa nua -> luon bam sat nhan vat. Property
-- CLIENT chuan Roblox (KHONG phai logic/remote game) -> boc pcall, luu gia tri cu de hoan tac, re-apply
-- sau respawn (Roblox reset zoom khi sinh lai char).
Runtime.SavedCamZoom = nil
Runtime.CameraStableHooked = false
Runtime.ApplyCameraStable = function()
    local c = CFG.CameraStable
    if not (c and c.Enabled) then return end
    local maxZoom = math.max(tonumber(c.MaxZoom) or 18, 0.5)
    pcall(function()
        if Runtime.SavedCamZoom == nil then
            Runtime.SavedCamZoom = LocalPlayer.CameraMaxZoomDistance
        end
        if LocalPlayer.CameraMaxZoomDistance ~= maxZoom then
            LocalPlayer.CameraMaxZoomDistance = maxZoom
        end
    end)
    if not Runtime.CameraStableHooked then
        Runtime.CameraStableHooked = true
        pcall(function()
            local conn = LocalPlayer.CharacterAdded:Connect(function()
                task.wait(0.5)   -- cho char + camera moi san sang roi khoa lai
                Runtime.ApplyCameraStable()
            end)
            table.insert(Runtime.Cleanups, function() pcall(function() conn:Disconnect() end) end)
        end)
        table.insert(Runtime.Cleanups, function()
            pcall(function()
                if Runtime.SavedCamZoom ~= nil then
                    LocalPlayer.CameraMaxZoomDistance = Runtime.SavedCamZoom
                end
            end)
        end)
    end
    if Runtime.LastCamZoom ~= maxZoom then
        Runtime.LastCamZoom = maxZoom
        actionLog("CameraStable", "APPLIED", "maxZoom=" .. tostring(maxZoom))
    end
end

Runtime.IsClaimCriticalInstance = function(inst)
    if not inst then return false end
    local dropped = workspace:FindFirstChild("DroppedItems")
    if dropped and inst:IsDescendantOf(dropped) then
        return true
    end
    local map = workspace:FindFirstChild("Map")
    local seedServer = map and map:FindFirstChild("SeedPackSpawnServerLocations")
    if seedServer and inst:IsDescendantOf(seedServer) then
        return true
    end
    return false
end

Runtime.IsPlayerCharacterInstance = function(inst)
    if not inst then return false end
    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        if char and inst:IsDescendantOf(char) then
            return true
        end
    end
    return false
end

Runtime.SetPerfFlagValue = function(flag, value)
    if type(flag) ~= "table" then return false end
    local old = flag.Value
    if old == value then return true end
    flag.Value = value
    if flag.Changed and type(flag.Changed.Fire) == "function" then
        pcall(function() flag.Changed:Fire(value, old) end)
    end
    return true
end

Runtime.ApplyPerfFlags = function(c)
    if not (c and c.ApplyPerfFlags ~= false) or Runtime.PerfFlagsApplied then return end
    Runtime.PerfFlagsApplied = true
    local shared = ReplicatedStorage:FindFirstChild("SharedModules")
    local flagsFolder = shared and shared:FindFirstChild("Flags")
    local mod = flagsFolder and flagsFolder:FindFirstChild("PerfFlags")
    if not mod then return end
    local ok, flags = pcall(require, mod)
    if not ok or type(flags) ~= "table" then return end
    local changed = 0
    if pcall(Runtime.SetPerfFlagValue, flags.MutationVFXDisabled, true) then changed = changed + 1 end
    if pcall(Runtime.SetPerfFlagValue, flags.DroppedItemAnimationsDisabled, true) then changed = changed + 1 end
    if pcall(Runtime.SetPerfFlagValue, flags.AnimatedGradientsDisabled, true) then changed = changed + 1 end
    if pcall(Runtime.SetPerfFlagValue, flags.AgeUpdateMaxHz, math.max(tonumber(c.AgeUpdateMaxHz) or 10, 1)) then changed = changed + 1 end
    if pcall(Runtime.SetPerfFlagValue, flags.PlantVisualizerBudget, math.max(tonumber(c.PlantVisualizerBudget) or 10, 1)) then changed = changed + 1 end
    actionLog("FpsBoost", "PERF_FLAGS", tostring(changed))
end

-- GEAR FX KILL phần 1: FX tưới nước. Part FX xác nhận source WateringcanController.lua:
--   vũng nước: u36.Name="WateringCanFx" (dòng 125), parent workspace.Temporary (dòng 149)
--   giọt nước: clone Assets.Stud_Part (giữ tên "Stud_Part"), parent workspace.Temporary (dòng 260-277)
-- Destroy ngay khi spawn: connection RenderStepped/tween của game đều có guard Parent (u36 and u36.Parent)
-- hoặc chỉ ghi property lên part đã destroy (vô hại) -> không lỗi, không còn chồng FX ở FPS thấp.
-- Trả true nếu ĐÃ destroy (caller bỏ qua xử lý tiếp). Sound "WateringCanSFX" nằm TRONG part -> chết theo.
Runtime.IsGearFxJunk = function(inst)
    local c = CFG.GearFxKill
    if not (c and c.Enabled ~= false and c.KillWateringFx ~= false) then return false end
    if not (inst and inst:IsA("BasePart")) then return false end
    local nm = inst.Name
    if nm ~= "WateringCanFx" and nm ~= "Stud_Part" and nm ~= "SprinklerRadius" then return false end
    local par = inst.Parent
    if not (par and par.Name == "Temporary" and par.Parent == workspace) then return false end
    pcall(function() inst:Destroy() end)
    return true
end

-- GEAR FX KILL phần 2: sweep model sprinkler client-clone (SprinklerVisualizerController tự clone từ
-- Assets.Sprinklers vào Gardens.Plot<N>.Sprinklers - KHÔNG phải object server nên xóa vô hại với buff).
-- Controller check "v and v.Parent" mỗi vòng timer/spin (dòng 116-160) -> model destroy = bị skip, không lỗi.
Runtime.DoGearSprinklerSweep = function()
    local c = CFG.GearFxKill
    if not (c and c.Enabled ~= false) then return end
    -- quet FX tuoi nuoc con sot trong workspace.Temporary (phong khi FpsBoost tat -> guard
    -- DescendantAdded khong duoc noi, hoac Debris don cham o FPS cap thap)
    if c.KillWateringFx ~= false then
        local tmp = workspace:FindFirstChild("Temporary")
        if tmp then
            for _, child in ipairs(tmp:GetChildren()) do
                Runtime.IsGearFxJunk(child)
            end
        end
    end
    if c.HideSprinklers == false then return end
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then return end
    local removed = 0
    for _, plot in ipairs(gardens:GetChildren()) do
        local spr = plot:FindFirstChild("Sprinklers")
        if spr then
            for _, m in ipairs(spr:GetChildren()) do
                pcall(function() m:Destroy() end)
                removed = removed + 1
            end
        end
    end
    if removed > 0 then
        actionLog("GearFxKill", "SPRINKLER", "removed=" .. tostring(removed))
    end
end

Runtime.HandleVisualJunk = function(inst, c)
    if not (inst and inst.Parent and c) then return 0 end
    -- DescendantAdded nhan moi loai object; loc class re truoc khi quet folders/Players.
    local className = inst.ClassName
    if className ~= "Sound" and className ~= "ParticleEmitter" and className ~= "Trail"
        and className ~= "Beam" and className ~= "Fire" and className ~= "Smoke"
        and className ~= "Sparkles" and className ~= "Decal" and className ~= "Texture"
        and className ~= "SurfaceAppearance" and className ~= "MeshPart"
        and className ~= "SpecialMesh" and className ~= "Animator"
        and className ~= "PointLight" and className ~= "SpotLight"
        and className ~= "SurfaceLight" then
        return 0
    end
    if Runtime.IsClaimCriticalInstance(inst) or Runtime.IsPlayerCharacterInstance(inst) then
        return 0
    end

    -- TAT TIENG: moi Sound moi spawn trong workspace -> Volume 0 + stop (ket hop SoundService.Volume=0 o
    -- applyFpsBoost -> im tieng triet de, ke ca am thanh phat sau khi vao game).
    if c.MuteAudio ~= false and inst:IsA("Sound") then
        if c.DestroySounds == true then
            pcall(function() inst:Destroy() end)   -- ULTRA: destroy han -> nha RAM audio (bat qua FpsBoost.DestroySounds)
        else
            pcall(function() inst.Volume = 0; inst.Playing = false end)
        end
        return 1
    end

    if inst:IsA("ParticleEmitter")
        or inst:IsA("Trail")
        or inst:IsA("Beam")
        or inst:IsA("Fire")
        or inst:IsA("Smoke")
        or inst:IsA("Sparkles") then
        if c.DestroyVisualEffects ~= false then
            pcall(function() inst:Destroy() end)
        else
            pcall(function()
                inst.Enabled = false
                if inst:IsA("ParticleEmitter") then inst:Clear() end
            end)
        end
        return 1
    end

    if c.DisableTextures ~= false and (inst:IsA("Decal") or inst:IsA("Texture")) then
        if c.DestroyTextures ~= false then
            pcall(function() inst:Destroy() end)
        else
            pcall(function()
                inst.Transparency = 1
                if c.StripTextureContent ~= false then inst.Texture = "" end
            end)
        end
        return 1
    end

    -- ULTRA STRIP TEXTURE (dot 2 - ha RAM engine that su): texture chinh la thu ngon RAM nhat cua
    -- process Roblox (2-3GB chu yeu la asset texture/mesh). SurfaceAppearance (PBR) destroy han;
    -- MeshPart/SpecialMesh xoa TextureID -> engine EVICT texture khoi bo nho. CHI VISUAL (vat xam di),
    -- KHONG dung logic/prompt/attribute nao; char minh + drop/seed spawn da duoc chan o dau ham.
    if c.StripSurfaceAppearance ~= false and inst:IsA("SurfaceAppearance") then
        -- Thu strip content truoc (giu object cho controller nao lo giu ref); NHUNG cac property
        -- *Map co the KHONG cho script ghi (tuy executor/identity) -> pcall fail im lang = texture
        -- PBR van nam trong RAM. Fail thi fallback Destroy nhu ban cu (da chay on, chi visual).
        local stripped = pcall(function()
            inst.ColorMap = ""
            inst.MetalnessMap = ""
            inst.NormalMap = ""
            inst.RoughnessMap = ""
        end)
        if not stripped then
            pcall(function() inst:Destroy() end)
        end
        return 1
    end
    if c.StripMeshTextures ~= false then
        if inst:IsA("MeshPart") then
            if inst.TextureID ~= "" then
                pcall(function() inst.TextureID = "" end)
            end
            -- khong return: MeshPart la BasePart, de tiep tuc cac check khac (khong co check nao ap nua -> roi xuong return 0)
        elseif inst:IsA("SpecialMesh") then
            if inst.TextureId ~= "" then
                pcall(function() inst.TextureId = "" end)
            end
            return 1
        end
    end

    if c.DisableAnimations ~= false and inst:IsA("Animator") then
        pcall(function()
            for _, tr in ipairs(inst:GetPlayingAnimationTracks()) do
                tr:Stop(0)
            end
        end)
        return 1
    end

    if inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
        pcall(function() inst.Enabled = false end)
        return 1
    end

    return 0
end

Runtime.CleanupVisualJunk = function(c)
    if not (c and c.DisableEffects ~= false) then return end
    Runtime.ApplyPerfFlags(c)
    if c.DisableWeatherEffects ~= false then
        pcall(function()
            local Lighting = game:GetService("Lighting")
            for _, inst in ipairs(Lighting:GetDescendants()) do
                if inst:IsA("BloomEffect")
                    or inst:IsA("BlurEffect")
                    or inst:IsA("ColorCorrectionEffect")
                    or inst:IsA("DepthOfFieldEffect")
                    or inst:IsA("SunRaysEffect")
                    or inst:IsA("Atmosphere")
                    or inst:IsA("Clouds")
                    or inst:IsA("Sky") then
                    -- Sky (dot 4): skybox = 6 tam texture to -> destroy nha RAM texture (chi visual)
                    pcall(function()
                        if inst:IsA("Atmosphere") then
                            inst.Density = 0
                            inst.Haze = 0
                            inst.Glare = 0
                        elseif inst:IsA("Clouds") then
                            inst.Enabled = false
                            inst.Density = 0
                            inst.Cover = 0
                        elseif inst:IsA("Sky") then
                            inst.CelestialBodiesShown = false
                            inst.StarCount = 0
                            inst.SkyboxBk, inst.SkyboxDn, inst.SkyboxFt = "", "", ""
                            inst.SkyboxLf, inst.SkyboxRt, inst.SkyboxUp = "", "", ""
                            inst.SunTextureId, inst.MoonTextureId = "", ""
                        else
                            inst.Enabled = false
                        end
                    end)
                end
            end
            -- Clouds la con cua Terrain; giu object vi TimeCycle truy cap Terrain.Clouds truc tiep.
            local terrain = workspace:FindFirstChildOfClass("Terrain")
            local clouds = terrain and terrain:FindFirstChildOfClass("Clouds")
            if clouds then
                pcall(function()
                    clouds.Enabled = false
                    clouds.Density = 0
                    clouds.Cover = 0
                end)
            end
        end)
    end

    if Runtime.VisualJunkCleaned ~= true then
        Runtime.VisualJunkCleaned = true
        Runtime.BeginTurboFps("visual clean")   -- TRICK: quet + xoa rac toan workspace 1 lan -> mo cap chay vu
        local removed = 0
        local n = 0
        for _, inst in ipairs(workspace:GetDescendants()) do
            removed = removed + Runtime.HandleVisualJunk(inst, c)
            n = n + 1
            if n % 300 == 0 and task and task.wait then task.wait() end
        end
        Runtime.EndTurboFps()
        actionLog("FpsBoost", "VISUAL_CLEAN", tostring(removed))
    end

    if not Runtime.VisualJunkGuardConnected then
        Runtime.VisualJunkGuardConnected = true
        local conn = workspace.DescendantAdded:Connect(function(inst)
            -- LUON xu ly vat MOI stream/add lai (KHONG skip khi 3D off nua): HandleVisualJunk DESTROY rac
            -- (Sound/Particle/Trail/Beam/Texture/Decal/Light) -> GIAM RAM ke ca khi 3D tat. Day la diem chinh
            -- chong "RAM no" (chong yeu cau): truoc day 3D off thi bo qua -> rac don ve dang nao cung khong xoa.
            -- Handler RAT nhe (chi :IsA type-check + destroy 1 instance), an toan cho cay/qua/claim (HandleVisualJunk
            -- da chua IsClaimCriticalInstance + IsPlayerCharacterInstance + KHONG dung BasePart cua cay).
            -- GEAR FX KILL chay TRUOC (khong phu thuoc FpsBoost.DisableEffects): part FX tuoi nuoc
            -- spawn rat nhieu khi AutoWater chay -> destroy ngay tai day la re nhat (1 check ten + parent).
            if Runtime.IsGearFxJunk(inst) then return end
            if CFG.FpsBoost and CFG.FpsBoost.Enabled and CFG.FpsBoost.DisableEffects ~= false then
                Runtime.HandleVisualJunk(inst, CFG.FpsBoost)
            end
        end)
        table.insert(Runtime.Cleanups, function() pcall(function() conn:Disconnect() end) end)
    end
end

-- MUTE 1 SOUND + GUARD RIENG TUNG CAI: game TU keo Volume len lai! MusicController.lua luu Volume GOC
-- cua tung track luc boot (line 43: u6[v22]=v22.Volume) roi RESTORE lai moi lan doi bai/crossfade
-- (line 143/203/234) -> mute 1 lan luc boot thi doi bai la co tieng lai. Guard per-sound ep Volume
-- ve 0 ngay khi bi doi. Bang weak-key -> sound bi destroy la entry tu nha (khong leak).
Runtime.MutedSoundGuards = Runtime.MutedSoundGuards or setmetatable({}, { __mode = "k" })
Runtime.MuteOneSound = function(s)
    pcall(function()
        s.Volume = 0
        if s:IsA("Sound") then s.Playing = false end
    end)
    if Runtime.MutedSoundGuards[s] == nil then
        local ok, conn = pcall(function()
            return s:GetPropertyChangedSignal("Volume"):Connect(function()
                if s.Volume ~= 0 then pcall(function() s.Volume = 0 end) end
            end)
        end)
        Runtime.MutedSoundGuards[s] = (ok and conn) or false
        if ok and conn and not Runtime.MuteGuardCleanupAdded then
            Runtime.MuteGuardCleanupAdded = true
            table.insert(Runtime.Cleanups, function()
                for _, c2 in pairs(Runtime.MutedSoundGuards) do
                    if c2 then pcall(function() c2:Disconnect() end) end
                end
            end)
        end
    end
end

local function applyFpsBoost()
    local c = CFG.FpsBoost
    if not (c and c.Enabled) then return end
    Runtime.ApplyFpsCap()
    pcall(function()
        local UserGameSettings = UserSettings():GetService("UserGameSettings")
        UserGameSettings.SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
    end)
    pcall(function()
        settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
    end)
    if c.MuteAudio ~= false then
        local soundService = game:GetService("SoundService")
        -- (a) master volume = 0 - pcall RIENG: neu executor chan property nay thi cac buoc (b)(c) VAN chay
        -- (truoc day ca khoi chung 1 pcall -> chet o dong nay la MAT LUON mute tung sound + guard =
        -- ly do "volume game van chua bi tat").
        pcall(function() soundService.Volume = 0 end)
        -- (b) mute + guard TUNG Sound/SoundGroup dang co: nhac game nam o SoundService.MusicTracks
        -- (MusicController.lua:9), SFX o SoundService.SFX (SfxController.lua:10). Phai guard per-sound
        -- vi MusicController restore Volume goc moi lan doi bai (xem comment Runtime.MuteOneSound).
        pcall(function()
            for _, inst in ipairs(soundService:GetDescendants()) do
                if inst:IsA("Sound") or inst:IsA("SoundGroup") then
                    Runtime.MuteOneSound(inst)
                end
            end
        end)
        -- (c) guard master + mute moi Sound MOI parent vao SoundService (SFX clone vao day roi moi Play).
        -- Ket hop guard workspace.DescendantAdded (HandleVisualJunk) -> im tieng triet de.
        if not Runtime.MuteGuardConnected then
            Runtime.MuteGuardConnected = true
            pcall(function()
                local vconn = soundService:GetPropertyChangedSignal("Volume"):Connect(function()
                    if soundService.Volume ~= 0 then pcall(function() soundService.Volume = 0 end) end
                end)
                table.insert(Runtime.Cleanups, function() pcall(function() vconn:Disconnect() end) end)
            end)
            pcall(function()
                local sconn = soundService.DescendantAdded:Connect(function(inst)
                    if inst:IsA("Sound") or inst:IsA("SoundGroup") then Runtime.MuteOneSound(inst) end
                end)
                table.insert(Runtime.Cleanups, function() pcall(function() sconn:Disconnect() end) end)
            end)
        end
    end
    pcall(function()
        local Lighting = game:GetService("Lighting")
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 1e6
        if c.DisablePostEffects ~= false then
            for _, inst in ipairs(Lighting:GetDescendants()) do
                if inst:IsA("BloomEffect")
                    or inst:IsA("BlurEffect")
                    or inst:IsA("ColorCorrectionEffect")
                    or inst:IsA("DepthOfFieldEffect")
                    or inst:IsA("SunRaysEffect") then
                    inst.Enabled = false
                end
            end
        end
    end)
    pcall(function()
        local terrain = workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            terrain.Decoration = false
            terrain.WaterWaveSize = 0
            terrain.WaterWaveSpeed = 0
            terrain.WaterReflectance = 0
            terrain.WaterTransparency = 1
        end
    end)
    -- ===== BOOST MANH THEM (ky thuat render thuan ROBLOX ENGINE, KHONG phai logic game) =====
    -- Lay tu boostfps.lua: ep Lighting Voxel (re nhat), giam chi tiet mesh xuong thap nhat, tat shadow mem,
    -- tat moi truong anh sang gian tiep, bo Material 2022. Deu la property/setting CLIENT -> an toan tuyet doi,
    -- KHONG dung remote/path/logic game. Chay 1 LAN luc boot (applyFpsBoost goi 1 lan) -> khong ton CPU lap.
    pcall(function()
        local Lighting = game:GetService("Lighting")
        Lighting.ShadowSoftness = 0
        Lighting.EnvironmentDiffuseScale = 0
        Lighting.EnvironmentSpecularScale = 0
        -- Technology = Voxel(2): lighting re nhat. Property bi khoa -> set qua sethiddenproperty neu co.
        if c.ForceVoxelLighting ~= false and type(sethiddenproperty) == "function" then
            pcall(function() sethiddenproperty(Lighting, "Technology", 2) end)
        end
    end)
    pcall(function()
        local r = settings().Rendering
        r.QualityLevel = Enum.QualityLevel.Level01
        if c.LowMeshDetail ~= false then
            r.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level04  -- mesh LOD THAP NHAT -> nhe CPU/GPU/RAM mesh
        end
    end)
    if c.ClearMaterialService ~= false then
        pcall(function()
            local ms = game:GetService("MaterialService")
            ms.Use2022Materials = false
            for _, v in ipairs(ms:GetChildren()) do pcall(function() v:Destroy() end) end
        end)
    end
    Runtime.CleanupVisualJunk(c)
    if false and c.DisableEffects ~= false then
        pcall(function()
            -- Quét TOÀN workspace rất nặng -> nhả frame mỗi 250 instance (stagger) cho khỏi đơ lúc boot.
            local _yc = 0
            for _, inst in ipairs(workspace:GetDescendants()) do
                if inst:IsA("ParticleEmitter")
                    or inst:IsA("Trail")
                    or inst:IsA("Beam")
                    or inst:IsA("Fire")
                    or inst:IsA("Smoke")
                    or inst:IsA("Sparkles") then
                    inst.Enabled = false
                end
                _yc = _yc + 1
                if _yc % 250 == 0 and task and task.wait then task.wait() end
            end
        end)
    end
    actionLog("FpsBoost", "APPLIED")
end

-- ============================================================
-- VÒNG LẶP CHẠY  (mỗi tác vụ 1 luồng riêng, có nhịp delay riêng)
-- ============================================================
-- TOI UU RAM (fix leak LON nhat): bang luu trang thai goc cua part/effect PLOT NGUOI KHAC de restore.
-- Truoc day key = Instance GIU CUNG -> plot nguoi khac bi destroy (MapCleanup/roi server) van nam day
-- vinh vien -> cang choi lau RAM cang no. Doi sang WEAK KEY (__mode="k") -> instance chet la GC tu xoa
-- entry. restoreClientLight van chay dung (chi restore duoc part con song = dung y nghia).
local ClientLightOriginal = {
    Parts = setmetatable({}, { __mode = "k" }),
    Effects = setmetatable({}, { __mode = "k" }),
}
local ClientLightLastSummary = nil

local function isEffectInstance(inst)
    return inst:IsA("ParticleEmitter")
        or inst:IsA("Trail")
        or inst:IsA("Beam")
        or inst:IsA("Fire")
        or inst:IsA("Smoke")
        or inst:IsA("Sparkles")
        or inst:IsA("PointLight")
        or inst:IsA("SpotLight")
        or inst:IsA("SurfaceLight")
end

local function isMyGardenPlot(plot)
    local myPlot = getPlot()
    if myPlot and plot == myPlot then
        return true
    end
    local ok, owner = pcall(function()
        return plot:GetAttribute("OwnerUserId")
    end)
    return ok and owner == LocalPlayer.UserId
end

local function restoreClientLight()
    for part, value in pairs(ClientLightOriginal.Parts) do
        if part and part.Parent then
            pcall(function()
                part.LocalTransparencyModifier = value
            end)
        end
    end
    for inst, value in pairs(ClientLightOriginal.Effects) do
        if inst and inst.Parent then
            pcall(function()
                inst.Enabled = value
            end)
        end
    end
    ClientLightOriginal.Parts = setmetatable({}, { __mode = "k" })   -- reset van giu WEAK KEY (chong leak)
    ClientLightOriginal.Effects = setmetatable({}, { __mode = "k" })
end

local function applyClientLight()
    local c = CFG.ClientLight
    if not (c and c.Enabled) then
        return
    end
    local gardens = workspace:FindFirstChild("Gardens")
    if not gardens then
        actionLog("ClientLight", "SKIP", "missing Gardens")
        return
    end

    local hiddenPlots = 0
    local hiddenParts = 0
    local disabledEffects = 0

    -- NHỚ plot ĐÃ xử lý -> lần sau BỎ QUA (không quét lại GetDescendants toàn bộ mỗi 10s = hết sụt FPS
    -- định kỳ). Plot MỚI (người mới vào) chưa có trong cache -> xử lý 1 lần rồi đánh dấu.
    Runtime.ClientLightDone = Runtime.ClientLightDone or setmetatable({}, { __mode = "k" })
    local done = Runtime.ClientLightDone

    local _yc = 0
    local turboed = false   -- TRICK TURBO: chi mo cap khi gap plot MOI can quet lon
    for _, plot in ipairs(gardens:GetChildren()) do
        if not isMyGardenPlot(plot) and not done[plot] then
            done[plot] = true
            hiddenPlots = hiddenPlots + 1
            if not turboed then
                turboed = true
                Runtime.BeginTurboFps("client light plot")
            end
            for _, inst in ipairs(plot:GetDescendants()) do
                _yc = _yc + 1
                -- nhả frame mỗi 250 instance: quét vườn người khác KHÔNG dồn 1 lần gây giật.
                if _yc % 250 == 0 and task and task.wait then task.wait() end
                if c.HideOtherGardens ~= false and inst:IsA("BasePart") then
                    if ClientLightOriginal.Parts[inst] == nil then
                        ClientLightOriginal.Parts[inst] = inst.LocalTransparencyModifier
                    end
                    if inst.LocalTransparencyModifier < 1 then
                        pcall(function()
                            inst.LocalTransparencyModifier = 1
                        end)
                    end
                    hiddenParts = hiddenParts + 1
                elseif c.DisableOtherGardenEffects ~= false and isEffectInstance(inst) then
                    if ClientLightOriginal.Effects[inst] == nil then
                        ClientLightOriginal.Effects[inst] = inst.Enabled
                    end
                    if inst.Enabled then
                        pcall(function()
                            inst.Enabled = false
                        end)
                    end
                    disabledEffects = disabledEffects + 1
                end
            end
        end
    end

    if turboed then Runtime.EndTurboFps() end   -- quet plot moi xong -> khoa lai cap cu
    local summary = ("plots=%s parts=%s fx=%s"):format(tostring(hiddenPlots), tostring(hiddenParts), tostring(disabledEffects))
    State.LastClientLight = os.date("%H:%M:%S") .. " " .. summary
    if summary ~= ClientLightLastSummary then
        ClientLightLastSummary = summary
        actionLog("ClientLight", "DONE", summary)
    end
end

-- (TOI UU LUONG: DA XOA ban loopTask CU o day - ban global chet, KHONG duoc goi o dau, lai THIEU
--  movement-yield/AdaptiveDelay/TaskStatus -> de nham lan "2 he thong luong". Ban THAT la
--  `local function loopTask` phia duoi, moi task deu chay qua no.)

Runtime.LoopTaskIndex = 0

-- Auto Redeem Codes: nhập code qua remote thật Settings.SubmitCode (Networking.lua:85).
-- Mỗi code chỉ thử 1 lần/phiên (tránh spam khi đã đổi hoặc code sai).
Runtime.RedeemedCodes = Runtime.RedeemedCodes or {}
function Runtime.doAutoRedeemCode()
    local c = CFG.AutoRedeemCode
    if not (c and c.Enabled) then return end
    if not packet({ "Settings", "SubmitCode" }) then
        logw("AutoRedeemCode: thieu Networking.Settings.SubmitCode -> tat.")
        c.Enabled = false
        return
    end
    for _, code in ipairs(type(c.List) == "table" and c.List or {}) do
        code = tostring(code)
        if code ~= "" and not Runtime.RedeemedCodes[code] then
            Runtime.RedeemedCodes[code] = true
            actionLog("AutoRedeemCode", "SUBMIT", code)
            local ok, res = firePacket({ "Settings", "SubmitCode" }, code)
            actionLog("AutoRedeemCode", ok and "DONE" or "ERROR", code .. " " .. tostring(res))
            if not waitAlive(tonumber(c.Delay) or 1.5) then return end
        end
    end
end

-- HIDE TREE KEEP FRUIT: ẩn/destroy thân cây ở vườn MÌNH, chừa lại QUẢ -> nhìn chỉ thấy "trái lơ lửng".
-- Nguồn xác nhận: cây = plot.Plants (Model), trong cây có folder "Fruits" (Model quả) +
-- "FruitSpawnLocations" (FruitVisualizerController.SpawnFruitFromData:580-624). Quả CHÍN = quả có
-- ProximityPrompt "HarvestPrompt". GIỮ Fruits + FruitSpawnLocations (để quả mới mọc); chỉ đụng
-- part NHÌN THẤY (Transparency<1) -> không phá part logic vô hình (HarvestPart/collision).
function Runtime.doHideTreeKeepFruit()
    local c = CFG.HideTreeKeepFruit
    if not (c and c.Enabled) then return end
    -- KHONG skip khi 3D off: ham nay DESTROY than cay -> GIAM RAM (co loi du 3D off), va da incremental
    -- (chi quet cay MOI) nen RE CPU. Phan an-visual-qua (render-only) duoi se tu bo qua neu 3D off.
    local plot = getPlot()
    if not plot then return end
    local plants = plot:FindFirstChild("Plants")
    if not plants then return end

    local useDestroy = c.UseDestroy ~= false
    local onlyRipe   = c.OnlyRipe == true
    local hideLabels = c.HideLabels ~= false
    local hideFruitVisual = c.HideFruitVisual ~= false   -- an mesh quả + VFX -> ko render quả -> nhe CPU
    local affected = 0
    -- weak-set quả đã ẩn -> KHONG quét lại (chỉ xử lý quả MỚI) -> nhẹ CPU.
    Runtime.HideFruitDone = Runtime.HideFruitDone or setmetatable({}, { __mode = "k" })
    local fruitDone = Runtime.HideFruitDone

    -- (DA GO guard DescendantAdded dot truoc - PHAN TAC DUNG: PlantVisualizerController.SpawnPlantFromData
    -- (dong 1365-1372) co vong `repeat task.wait() until HasTag("InitializationComplete")` va InitPlant
    -- chay TRUOC khi set attribute PlantGrowthReady. Xoa part NGAY KHI VUA VAO lam InitPlant gay/tag
    -- khong bao gio duoc gan -> MOI CAY MOI 1 thread game KET VINH VIEN -> cang trong (single-fill trong
    -- lien tuc) RAM/CPU cang PHINH. Cay lon len bang ScaleTo (dong 1374-1379), KHONG moc part stage moi
    -- -> sweep-1-lan la DU, khong can guard.)
    -- GATE INIT: chi don cay DA init xong (attribute PlantGrowthReady=true - PlantVisualizer dong 1372).
    -- Cay chua ready -> tiep tuc doi, khong co timeout force-destroy.
    Runtime.HideTreeReadyAt = Runtime.HideTreeReadyAt or setmetatable({}, { __mode = "k" })
    local readyAt = Runtime.HideTreeReadyAt
    local readyGrace = math.max(tonumber(c.PlantReadyGrace) or 0.75, 0)

    local function killPart(p)
        if useDestroy then
            pcall(function() p:Destroy() end)
        elseif p.LocalTransparencyModifier < 1 then
            pcall(function() p.LocalTransparencyModifier = 1 end)
        end
        affected = affected + 1
    end
    local function killGui(g)
        if useDestroy then
            pcall(function() g:Destroy() end)
        elseif g.Enabled then
            pcall(function() g.Enabled = false end)
        end
    end

    -- TOI UU LAG: cay da xu ly than -> BO QUA GetDescendants cay cu (rat nang khi vai tram cay),
    -- chi quet cay MOI. Bang weak-key (khong dong vao instance); cay bi nho/destroy -> GC tu xoa.
    -- Than cay tao 1 lan luc trong, qua moc trong folder Fruits (giu lai) -> danh dau xong la khoi quet lai.
    Runtime.HideTreeDone = Runtime.HideTreeDone or setmetatable({}, { __mode = "k" })
    local done = Runtime.HideTreeDone
    local freshScanned = 0   -- STAGGER chong freeze: vao game co san 400 cay -> luot dau nha frame moi 8 cay moi
    local turboed = false    -- TRICK TURBO: gap dot xoa LON moi mo cap (khong toggle cap moi vong 1s)
    for _, plant in ipairs(plants:GetChildren()) do
        if plant:IsA("Model") or plant:IsA("Folder") then
            local fruits = plant:FindFirstChild("Fruits")
            -- notReady = cay CHUA init xong -> vong nay BO QUA (khong danh dau done, vong sau don)
            local notReady = false
            if not done[plant] then
                local now = os.clock()
                if plant:GetAttribute("PlantGrowthReady") ~= true then
                    readyAt[plant] = nil
                    notReady = true
                else
                    local firstReady = readyAt[plant]
                    if not firstReady then
                        readyAt[plant] = now
                        notReady = true
                    elseif (now - firstReady) < readyGrace then
                        notReady = true
                    end
                end
            end
            if not done[plant] and not notReady then
                local spawns = plant:FindFirstChild("FruitSpawnLocations")
                for _, d in ipairs(plant:GetDescendants()) do
                    if d:IsA("BasePart") then
                        local inFruits = fruits and d:IsDescendantOf(fruits)
                        local inSpawn  = spawns and d:IsDescendantOf(spawns)
                        if not inFruits and not inSpawn and d.Transparency < 1 then
                            killPart(d)
                        end
                    elseif hideLabels and (d:IsA("BillboardGui") or d:IsA("SurfaceGui")) then
                        if not (fruits and d:IsDescendantOf(fruits)) then
                            killGui(d)
                        end
                    end
                end
                done[plant] = true   -- danh dau: lan sau khoi quet sau cay nay (het lag quet lai moi giay)
                freshScanned = freshScanned + 1
                -- Dot xoa LON (>=16 cay moi trong 1 luot, thuong la luot dau sau khi vao game) -> TURBO
                if not turboed and freshScanned >= 16 then
                    turboed = true
                    Runtime.BeginTurboFps("hide tree bulk")
                end
                if freshScanned % 8 == 0 then task.wait() end
            end
            -- ONLY_RIPE: bỏ quả CHƯA chín. Chay ca cay da done (qua moc lien tuc) nhung CHI duyet
            -- fruits:GetChildren() (RE) -> khong GetDescendants ca cay.
            if fruits and onlyRipe then
                for _, fruit in ipairs(fruits:GetChildren()) do
                    local ok, hasTag = pcall(function() return fruit:HasTag("InitializationComplete") end)
                    if ok and hasTag == true and not fruit:FindFirstChild("HarvestPrompt", true) then
                        if fruit:IsA("BasePart") then killPart(fruit) end
                        for _, d in ipairs(fruit:GetDescendants()) do
                            if d:IsA("BasePart") then killPart(d) end
                        end
                    end
                end
            end
            -- ULTRA DestroyFruitToo (dot 4): destroy HAN model qua -> plot gan nhu khong con instance
            -- -> RAM/CPU thap nhat. AutoCollect het prompt candidate -> TU fallback DATA-HARVEST
            -- (Garden.CollectFruit tu TrackedPlants, nhu Nuke All - da chay on dinh). Mac dinh TAT.
            -- GATE INIT QUA: FruitVisualizerController.lua:926 co `repeat task.wait() until
            -- HasTag("InitializationComplete")` KHONG timeout -> destroy qua non chua init xong =
            -- 1 thread game KET vinh vien MOI QUA (400 cay ra qua lien tuc = RAM phinh dan - day la
            -- ly do "bat DestroyFruitToo ma RAM giam it/tang"). Chi destroy qua DA co tag; qua chua
            -- tag tiep tuc doi de khong lam ket thread init cua game.
            if fruits and c.DestroyFruitToo == true then
                for _, fruit in ipairs(fruits:GetChildren()) do
                    local ok, hasTag = pcall(function() return fruit:HasTag("InitializationComplete") end)
                    local ripeToKill = ok and hasTag == true
                    if ripeToKill then
                        pcall(function() fruit:Destroy() end)
                        affected = affected + 1
                    end
                end
            -- AN VISUAL QUA: an mesh quả (LocalTransparencyModifier=1, KHONG destroy -> giu HarvestPrompt ->
            -- HAI VAN CHAY) + tắt VFX "trái chín dần". Quả MỚI mới quét -> nhẹ CPU. Bỏ render quả = hết lag render.
            -- 3D off thi an-visual la render-only vo ich -> bo qua (chi can than cay da destroy o tren cho RAM).
            elseif fruits and hideFruitVisual and Runtime.Render3DState ~= false then
                for _, fruit in ipairs(fruits:GetChildren()) do
                    if not fruitDone[fruit] then
                        local ok, hasTag = pcall(function() return fruit:HasTag("InitializationComplete") end)
                        if ok and hasTag == true then
                            if fruit:IsA("BasePart") and fruit.LocalTransparencyModifier < 1 then
                                pcall(function() fruit.LocalTransparencyModifier = 1 end)
                            end
                            for _, d in ipairs(fruit:GetDescendants()) do
                                if d:IsA("BasePart") then
                                    if d.LocalTransparencyModifier < 1 then pcall(function() d.LocalTransparencyModifier = 1 end) end
                                elseif d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") or d:IsA("Sparkles") or d:IsA("Smoke") or d:IsA("Fire") then
                                    pcall(function() d.Enabled = false end)
                                end
                            end
                            fruitDone[fruit] = true
                            affected = affected + 1
                        end
                    end
                end
            end
        end
    end

    if turboed then Runtime.EndTurboFps() end   -- xong dot xoa lon -> khoa lai cap cu
    if affected > 0 then
        actionLog("HideTreeKeepFruit", useDestroy and "DESTROY" or "HIDE", tostring(affected) .. " parts")
        -- Vua destroy 1 dot LON -> goi GC ngay de nha RAM lien (khoi cho MemJanitor 60s)
        if affected >= 200 and CFG.ForceFullGc == true then
            pcall(function() collectgarbage("collect") end)
        end
    end
end

-- MAP CLEANUP (EVENT, KHÔNG scan 20s): xóa plot người khác + Baseplate/Map/NPCS/ActiveNight cho NHẸ game.
-- Plot MÌNH luôn giữ. Cơ chế:
--   * Bật lên: xóa NGAY tất cả plot người khác đang có + vật thể tĩnh (1 lần).
--   * Players.PlayerAdded: AI MỚI VÀO server -> chờ plot họ stream xong -> xóa plot đó (không quét vô ích).
--   * Baseplate: chỉ xóa khi đang ĐỨNG TRÊN plot mình -> không rớt khỏi thế giới (có 1 luồng chờ-về-vườn).
Runtime.MapCleanupReady = false
Runtime.MapCleanupStaticDone = false
Runtime.MapCleanupInitialDone = false
function Runtime.SetupMapCleanup()
    local c = CFG.MapCleanup
    if not (c and c.Enabled) then
        Runtime.MapCleanupInitialDone = true
        return
    end
    if Runtime.MapCleanupReady then return end
    Runtime.MapCleanupReady = true
    Runtime.MapCleanupNeedsInitialWait = CFG["Nuke All"] == true or c.OtherPlots ~= false
        or c.ActiveNight ~= false or c.MapDecor ~= false or c.NPCS ~= false
        or c.Baseplate ~= false or c.ClearTerrain ~= false
    local ws = workspace
    local myId = LocalPlayer.UserId

    local function forceDestroy(obj)
        if obj and obj.Parent then
            pcall(function()
                if obj:IsA("BasePart") then obj.Locked = false end
                obj:Destroy()
            end)
            return true
        end
        return false
    end
    local function destroyPath(path)
        local obj = ws
        for seg in string.gmatch(path, "[^%.]+") do
            obj = obj and obj:FindFirstChild(seg)
        end
        forceDestroy(obj)
    end

    -- Xóa plot NGƯỜI KHÁC / plot trống (giữ plot mình). Gọi lúc bật + mỗi khi có người mới vào.
    local function cleanOtherPlots()
        if c.OtherPlots == false then return end
        local gardens = ws:FindFirstChild("Gardens")
        if not gardens then return end
        local n = 0
        for _, plot in ipairs(gardens:GetChildren()) do
            if plot:GetAttribute("OwnerUserId") ~= myId then
                if forceDestroy(plot) then n = n + 1 end
            end
        end
        if n > 0 then actionLog("MapCleanup", "PLOTS", "xoa " .. tostring(n) .. " plot nguoi khac") end
    end

    -- Vật thể TĨNH (không respawn): xóa 1 lần. Baseplate để 1 luồng riêng chờ về vườn mới xóa.
    local function cleanStaticOnce()
        if Runtime.MapCleanupStaticDone then return end
        Runtime.MapCleanupStaticDone = true
        if c.ActiveNight ~= false then forceDestroy(ws:FindFirstChild("ActiveNight")) end
        if c.MapDecor ~= false then
            -- Xóa từng phần Map trang trí. MapDecorParts = list các phần muốn xóa (mặc định cả 4).
            -- Chồng GIỮ Stands (Seeds/Sell/Shop) + SafeZones để test teleport: bỏ tên đó khỏi list.
            local parts = type(c.MapDecorParts) == "table" and c.MapDecorParts
                or { "Middle", "PetSpawn", "SafeZones", "Stands" }
            for _, seg in ipairs(parts) do
                if type(seg) == "string" and seg ~= "" then destroyPath("Map." .. seg) end
            end
        end
        if c.NPCS ~= false then forceDestroy(ws:FindFirstChild("NPCS")) end
        -- CLEAR TERRAIN VOXEL (dot 4 - ha RAM): nuoc/dat voxel chi trang tri; san dung la PART (plot/TopLayer).
        -- Cho DUNG TREN PLOT roi moi clear -> neu dang dung tren terrain cung khong rot. :Clear() nha RAM voxel.
        if c.ClearTerrain ~= false then
            task.spawn(function()
                for _ = 1, 120 do
                    if not isAlive() then return end
                    if LocalPlayer:GetAttribute("IsInOwnGarden") == true then
                        pcall(function() ws.Terrain:Clear() end)
                        actionLog("MapCleanup", "TERRAIN", "da clear voxel terrain (dang o vuon)")
                        return
                    end
                    task.wait(1)
                end
            end)
        end
        if c.Baseplate ~= false then
            -- KeepBaseplateChildren: danh sách CON của Baseplate cần CHỪA LẠI (vd "TopLayer" = mặt nền để đứng).
            local keepSet, hasKeep = {}, false
            for _, n in ipairs(type(c.KeepBaseplateChildren) == "table" and c.KeepBaseplateChildren or {}) do
                if type(n) == "string" and n ~= "" then keepSet[n] = true; hasKeep = true end
            end
            if hasKeep then
                -- Giữ TopLayer -> vẫn còn nền đứng (KHÔNG rớt) -> xóa NGAY các CON KHÁC của Baseplate cho nhẹ.
                local bp = ws:FindFirstChild("Baseplate")
                if bp then
                    local removed, kept = 0, 0
                    for _, child in ipairs(bp:GetChildren()) do
                        if keepSet[child.Name] then
                            kept = kept + 1
                        elseif forceDestroy(child) then
                            removed = removed + 1
                        end
                    end
                    actionLog("MapCleanup", "BASEPLATE", ("giu %d con (TopLayer...), xoa %d con khac"):format(kept, removed))
                end
            else
                -- Xóa SẠCH Baseplate: chờ ĐỨNG TRÊN plot mình rồi mới xóa (tránh rớt void); thử tối đa ~120s.
                task.spawn(function()
                    for _ = 1, 120 do
                        if not isAlive() then return end
                        if LocalPlayer:GetAttribute("IsInOwnGarden") == true then
                            if forceDestroy(ws:FindFirstChild("Baseplate")) then
                                actionLog("MapCleanup", "BASEPLATE", "da xoa (dang o vuon)")
                            end
                            return
                        end
                        task.wait(1)
                    end
                end)
            end
        end
        actionLog("MapCleanup", "STATIC", "ActiveNight/Map/NPCS xong")
    end

    -- ============================================================
    -- ===== NUKE ALL (CFG["Nuke All"]==true): xoa SACH workspace kieu honglamgx -> NHE RAM toi da =====
    -- CHUA LAI (toi thieu de bot van chay):
    --   * Terrain + Camera (engine can)
    --   * Character MINH (+ con) -> tao SAN AO theo chan, KHONG rot void (vi xoa ca Baseplate)
    --   * Gardens nhung PRUNE: chi giu PLOT MINH (chua PlantArea -> AutoPlant biet cho trong). Plot nguoi khac xoa.
    --   * Map nhung PRUNE: chi giu SeedPackSpawnServerLocations/Client (claim seed) + WildPetRef/WildPetSpawns (tame pet)
    --   * DroppedItems neu NukeKeepDrops (AutoCollectDrops con nhat do)
    -- XOA: Baseplate/NPCS/ActiveNight/moi decor, PLAYER KHAC (Players service + char), Lighting/ReplicatedFirst children.
    -- Harvest/claim cua hic = REMOTE + data (TrackedPlants) nen KHONG can vat the cay/prompt trong workspace.
    local MAP_KEEP = { SeedPackSpawnServerLocations = true, SeedPackSpawnClient = true, WildPetRef = true, WildPetSpawns = true }
    local NUKE_FLOOR_NAME = "KaitunNukeFloor"
    local nukeFloorDrop = math.max(tonumber(c.NukeFloorDrop) or 3.5, 0)
    -- CHIA BATCH: xoa NukeBatch vat moi lan roi NHA frame NukeBatchDelay -> trai deu tai, KHONG freeze 1 frame.
    local nukeBatch = math.max(tonumber(c.NukeBatch) or 12, 1)
    local nukeBatchDelay = math.max(tonumber(c.NukeBatchDelay) or 0.03, 0)
    local nukeFloorPart

    -- Plot CUA MINH (xac nhan: getPlot() = Gardens.Plot<PlotId>).
    local function nukeMyPlot()
        local id = LocalPlayer:GetAttribute("PlotId")
        local gardens = ws:FindFirstChild("Gardens")
        if not (id and gardens) then return nil end
        return gardens:FindFirstChild("Plot" .. tostring(id))
    end

    -- SAN AO: 1 Part vo hinh ngay duoi chan -> xoa Baseplate van KHONG rot khoi the gioi (giong honglamgx).
    local function nukeEnsureFloor()
        if c.NukeFakeFloor == false then return nil end
        if nukeFloorPart and nukeFloorPart.Parent == ws then return nukeFloorPart end
        local ok, part = pcall(function()
            local p = Instance.new("Part")
            p.Name = NUKE_FLOOR_NAME
            p.Size = Vector3.new(80, 1, 80)
            p.Anchored = true
            p.CanCollide = true
            p.CanQuery = false
            p.CanTouch = false
            p.CastShadow = false
            p.Transparency = 1
            p.Parent = ws
            return p
        end)
        nukeFloorPart = ok and part or nil
        return nukeFloorPart
    end
    local function nukeUpdateFloor()
        if c.NukeFakeFloor == false then return end
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local f = nukeEnsureFloor()
        if f then f.Position = Vector3.new(hrp.Position.X, hrp.Position.Y - nukeFloorDrop, hrp.Position.Z) end
    end

    -- Vat the BAT BUOC giu o cap workspace (Gardens/Map giu de PRUNE rieng).
    local function nukeIsKeep(child)
        if child:IsA("Terrain") or child:IsA("Camera") then return true end
        if child == nukeFloorPart or child.Name == NUKE_FLOOR_NAME then return true end
        local myChar = LocalPlayer.Character
        if myChar and (child == myChar or child:IsDescendantOf(myChar)) then return true end
        if child.Name == "Gardens" or child.Name == "Map" then return true end
        if child.Name == "DroppedItems" and c.NukeKeepDrops ~= false then return true end
        return false
    end

    -- PRUNE Gardens: chi giu plot MINH, xoa plot nguoi khac (da chia batch).
    local function nukePruneGardens()
        local gardens = ws:FindFirstChild("Gardens")
        if not gardens then return end
        local myPlot = nukeMyPlot()
        -- CHONG SPAM LOI: neu CHUA biet plot minh (PlotId chua set) -> KHONG prune. Vi myPlot=nil thi vong duoi
        -- coi MOI plot la "khong phai cua minh" -> xoa CA plot minh -> PlotsController index nil (Signs.Garden.CorePart
        -- chi truy cap cho PLOT MINH) -> spam loi + lag. Xoa plot NGUOI KHAC thi controller khong dung -> vo hai.
        -- Bo qua 1 vong, lan sau PlotId co roi prune tiep. (Source: PlotsController.lua:318-379.)
        if not myPlot then return end
        local since = 0
        for _, plot in ipairs(gardens:GetChildren()) do
            if plot ~= myPlot then
                if forceDestroy(plot) then
                    since = since + 1
                    if since >= nukeBatch then since = 0; if not waitAlive(nukeBatchDelay) then return end end
                end
            end
        end
    end
    -- PRUNE Map: chi giu folder seed-claim + wild-pet (da chia batch).
    local function nukePruneMap()
        local map = ws:FindFirstChild("Map")
        if not map then return end
        local since = 0
        for _, m in ipairs(map:GetChildren()) do
            if not MAP_KEEP[m.Name] then
                if forceDestroy(m) then
                    since = since + 1
                    if since >= nukeBatch then since = 0; if not waitAlive(nukeBatchDelay) then return end end
                end
            end
        end
    end

    -- XOA player KHAC (Players service). Giu LocalPlayer. (yeu cau cua chong: xoa player khac luon)
    local function nukeOtherPlayers()
        if c.NukeKeepOtherPlayers == true then return end
        for _, p in ipairs(Players:GetChildren()) do
            if p ~= LocalPlayer and p:IsA("Player") then forceDestroy(p) end
        end
    end

    -- AN cac ScreenGui khac, GIU GUI hub KaitunCommercial -> van len GUI binh thuong.
    local function nukeHideOtherGui()
        if c.NukeHideOtherGui == false then return end
        local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not pg then return end
        -- CHUA LAI: GUI hub cua bot + HOTBAR GOC cua game ("BackpackGui" do InventoryController/Main.lua tao
        -- runtime, dong 83-87) -> chong van thay thanh do duoi de chon/dung. Them ten khac qua NukeKeepGuiNames.
        local keep = {}
        keep[(Runtime.DashboardGuiName and Runtime.DashboardGuiName()) or "KaitunCommercial"] = true
        keep["BackpackGui"] = true
        if type(c.NukeKeepGuiNames) == "table" then
            for _, n in ipairs(c.NukeKeepGuiNames) do
                if type(n) == "string" and n ~= "" then keep[n] = true end
            end
        end
        for _, gui in ipairs(pg:GetChildren()) do
            if gui:IsA("ScreenGui") then
                if not keep[gui.Name] then
                    pcall(function() gui.Enabled = false end)
                elseif gui.Name == "BackpackGui" then
                    -- inventory/hotbar GOC cua game (phim ` mo no): dam bao BAT lai, phong da bi tat truoc do.
                    pcall(function() gui.Enabled = true end)
                end
            end
        end
    end

    local function nukeAll()
        if CFG["Nuke All"] ~= true then return end
        nukeEnsureFloor(); nukeUpdateFloor()
        -- Nuke co SAN AO theo chan -> clear terrain voxel NGAY duoc (khong so rot) -> nha RAM
        if c.ClearTerrain ~= false then pcall(function() ws.Terrain:Clear() end) end
        nukePruneMap()       -- prune Map (giu seed/pet) truoc
        nukePruneGardens()   -- prune Gardens (giu plot minh)
        local n, since = 0, 0
        for _, child in ipairs(ws:GetChildren()) do
            if not nukeIsKeep(child) then
                if forceDestroy(child) then
                    n = n + 1; since = since + 1
                    if since >= nukeBatch then since = 0; if not waitAlive(nukeBatchDelay) then return end end
                end
            end
        end
        nukeOtherPlayers()
        nukeHideOtherGui()
        if c.NukeClearLighting ~= false then pcall(function() game:GetService("Lighting"):ClearAllChildren() end) end
        if c.NukeClearReplicatedFirst ~= false then pcall(function() game:GetService("ReplicatedFirst"):ClearAllChildren() end) end
        if c.NukeClearPlayerScripts == true then
            pcall(function()
                local ps = LocalPlayer:FindFirstChild("PlayerScripts")
                if ps then ps:ClearAllChildren() end
            end)
        end
        if n > 0 then actionLog("MapCleanup", "NUKE", "xoa " .. tostring(n) .. " vat workspace (giu plot minh/seed/pet/char, san ao)") end
    end

    -- ===== XOA HIEU UNG THOI TIET/EVENT (chong yeu cau muc 6) - chay CA 2 che do (ke ca Nuke All) =====
    -- Quet ngay + NOI ChildAdded (workspace + Lighting) -> VFX thoi tiet xuat hien la xoa, add lai xoa tiep.
    -- Ten lay tu source WeatherController. TUYET DOI KHONG dung Gardens (cay minh). Chi VISUAL -> an toan.
    local function setupWeatherGuard()
        if Runtime.WeatherGuardConnected then return end
        if c.RemoveWeatherEffects == false then return end
        Runtime.WeatherGuardConnected = true
        local wsW = {}
        for _, n in ipairs(type(c.WeatherEffectNames) == "table" and c.WeatherEffectNames or {}) do
            if type(n) == "string" and n ~= "" then wsW[n] = true end
        end
        local lightW = {}
        for _, n in ipairs(type(c.WeatherLightingNames) == "table" and c.WeatherLightingNames or {}) do
            if type(n) == "string" and n ~= "" then lightW[n] = true end
        end
        local okL, lighting = pcall(function() return game:GetService("Lighting") end)
        if not okL then lighting = nil end
        -- Weather modules giu reference folder/model qua nhieu Start/End. Giu container, chi tat render.
        local function suppressOne(inst)
            if not (inst and inst.Parent) then return end
            pcall(function()
                if inst:IsA("ParticleEmitter") then
                    inst.Enabled = false
                    inst:Clear()
                elseif inst:IsA("Trail") or inst:IsA("Beam") or inst:IsA("Fire")
                    or inst:IsA("Smoke") or inst:IsA("Sparkles") then
                    inst.Enabled = false
                elseif inst:IsA("PointLight") or inst:IsA("SpotLight") or inst:IsA("SurfaceLight") then
                    inst.Enabled = false
                elseif inst:IsA("BasePart") then
                    inst.LocalTransparencyModifier = 1
                    inst.CastShadow = false
                elseif inst:IsA("Decal") or inst:IsA("Texture") then
                    inst.Transparency = 1
                    inst.Texture = ""
                elseif inst:IsA("Sound") then
                    inst.Volume = 0
                    inst.Playing = false
                elseif inst:IsA("Atmosphere") then
                    inst.Density = 0
                    inst.Haze = 0
                    inst.Glare = 0
                elseif inst:IsA("Clouds") then
                    inst.Enabled = false
                    inst.Density = 0
                    inst.Cover = 0
                elseif inst:IsA("BloomEffect") or inst:IsA("BlurEffect")
                    or inst:IsA("ColorCorrectionEffect") or inst:IsA("DepthOfFieldEffect")
                    or inst:IsA("SunRaysEffect") then
                    inst.Enabled = false
                end
            end)
        end
        local function suppressWeatherObject(root)
            if not root then return end
            suppressOne(root)
            local ok, descendants = pcall(root.GetDescendants, root)
            if ok and type(descendants) == "table" then
                for _, inst in ipairs(descendants) do suppressOne(inst) end
            end
        end
        -- sweep ngay (bat script giua con mua/event)
        for _, child in ipairs(ws:GetChildren()) do
            if wsW[child.Name] then suppressWeatherObject(child) end
        end
        if lighting then
            for _, child in ipairs(lighting:GetChildren()) do
                if lightW[child.Name] then suppressWeatherObject(child) end
            end
        end
        local wconn = ws.ChildAdded:Connect(function(child)
            if not (CFG.MapCleanup and CFG.MapCleanup.Enabled) then return end
            if wsW[child.Name] then
                task.defer(function()
                    if child and child.Parent == ws then suppressWeatherObject(child) end
                end)
            end
        end)
        table.insert(Runtime.Cleanups, function() pcall(function() wconn:Disconnect() end) end)
        if lighting then
            local lconn = lighting.ChildAdded:Connect(function(child)
                if not (CFG.MapCleanup and CFG.MapCleanup.Enabled) then return end
                if lightW[child.Name] then
                    task.defer(function()
                        if child and child.Parent == lighting then suppressWeatherObject(child) end
                    end)
                end
            end)
            table.insert(Runtime.Cleanups, function() pcall(function() lconn:Disconnect() end) end)
        end
        actionLog("MapCleanup", "WEATHER_GUARD", "tat VFX, giu container controller")
    end

    -- ===== RE-STREAM GUARD (CHI non-Nuke) (chong yeu cau muc 3) =====
    -- Sau khi xoa decor/NPCS/ActiveNight lan 1, NOI ChildAdded -> game stream LAI thi xoa TIEP (ngan RAM no).
    -- Nuke All co guard rieng (ws.ChildAdded ben duoi) nen KHONG chay cai nay. KHONG dung Gardens/Map seed-pet.
    local function setupNonNukeGuard()
        if Runtime.NonNukeGuardConnected then return end
        Runtime.NonNukeGuardConnected = true
        local wsJunk = {}
        if c.NPCS ~= false then wsJunk["NPCS"] = true end
        if c.ActiveNight ~= false then wsJunk["ActiveNight"] = true end
        local mapDecor = {}
        if c.MapDecor ~= false then
            for _, n in ipairs(type(c.MapDecorParts) == "table" and c.MapDecorParts or { "Middle", "PetSpawn", "SafeZones", "Stands" }) do
                if type(n) == "string" and n ~= "" then mapDecor[n] = true end
            end
        end
        local wconn = ws.ChildAdded:Connect(function(child)
            if not (CFG.MapCleanup and CFG.MapCleanup.Enabled) or CFG["Nuke All"] == true then return end
            if wsJunk[child.Name] then
                task.defer(function() if child and child.Parent == ws then forceDestroy(child) end end)
            end
        end)
        table.insert(Runtime.Cleanups, function() pcall(function() wconn:Disconnect() end) end)
        local map = ws:FindFirstChild("Map")
        if map and next(mapDecor) ~= nil then
            local mconn = map.ChildAdded:Connect(function(child)
                if not (CFG.MapCleanup and CFG.MapCleanup.Enabled) or CFG["Nuke All"] == true then return end
                if mapDecor[child.Name] then
                    task.defer(function() if child and child.Parent == map then forceDestroy(child) end end)
                end
            end)
            table.insert(Runtime.Cleanups, function() pcall(function() mconn:Disconnect() end) end)
        end
        actionLog("MapCleanup", "GUARD", "re-stream guard ON")
    end

    -- WEATHER GUARD chay UNCONDITIONAL (ca Nuke All lan non-Nuke) sau khi game load -> VFX thoi tiet luon bi xoa.
    if c.RemoveWeatherEffects ~= false then
        table.insert(Runtime.Tasks, task.spawn(function()
            if not game:IsLoaded() then pcall(function() game.Loaded:Wait() end) end
            if not waitAlive(tonumber(c.StartDelay) or 3) then return end
            setupWeatherGuard()
        end))
    end

    -- DON DEP: PHAI cho game LOAD XONG roi moi xoa (KHONG xoa luc dang load -> tranh treo controller game
    -- PetVisualController/loading screen -> GUI/game len BINH THUONG roi moi don). Chay NEN, ko block boot.
    table.insert(Runtime.Tasks, task.spawn(function()
        if CFG["Nuke All"] == true then return end   -- Nuke All lo HET (gom Baseplate->san ao) -> KHONG chay static cleanup tranh xung dot
        if not game:IsLoaded() then pcall(function() game.Loaded:Wait() end) end
        if not waitAlive(tonumber(c.StartDelay) or 3) then return end  -- buffer cho controller Start xong
        cleanStaticOnce()
        cleanOtherPlots()
        if c.ReStreamGuard ~= false
            and (c.NPCS ~= false or c.ActiveNight ~= false or c.MapDecor ~= false) then
            setupNonNukeGuard()   -- non-Nuke: xoa decor/NPCS lan 1 xong -> guard add lai xoa tiep
        end
        Runtime.MapCleanupInitialDone = true
    end))

    -- NUKE: PHAI cho game LOAD XONG (game.Loaded + buffer) roi MOI noi guard + nuke bulk.
    -- NEU nuke SOM (dang load) -> xoa thu cac CONTROLLER game (PetVisualController/PlotsController...) dang
    -- doi -> controller TREO Start -> KHONG len GUI/loading screen (loi chong gap). Doi loaded thi controller
    -- da Start xong (da tao HarvestPrompt...), gio xoa decor con lai khong treo nua.
    if CFG["Nuke All"] == true and not Runtime.NukeGuardConnected then
        Runtime.NukeGuardConnected = true
        table.insert(Runtime.Tasks, task.spawn(function()
            if not game:IsLoaded() then pcall(function() game.Loaded:Wait() end) end
            if not waitAlive(tonumber(c.NukeStartDelay) or 6) then return end  -- buffer cho controller game Start xong han
            -- GUARD workspace: vat MOI stream ve -> Map/Gardens prune theo luat, con lai xoa ngay.
            local gconn = ws.ChildAdded:Connect(function(child)
                if CFG["Nuke All"] ~= true then return end
                task.defer(function()
                    if not (child and child.Parent == ws) then return end
                    if child.Name == "Map" then nukePruneMap()
                    elseif child.Name == "Gardens" then nukePruneGardens()
                    elseif not nukeIsKeep(child) then forceDestroy(child) end
                end)
            end)
            table.insert(Runtime.Cleanups, function() pcall(function() gconn:Disconnect() end) end)
            -- GUARD Players: ai MOI vao server -> xoa luon (tru minh).
            local pconn = Players.PlayerAdded:Connect(function(p)
                if CFG["Nuke All"] ~= true or c.NukeKeepOtherPlayers == true then return end
                task.defer(function() if p ~= LocalPlayer and p:IsA("Player") then forceDestroy(p) end end)
            end)
            table.insert(Runtime.Cleanups, function() pcall(function() pconn:Disconnect() end) end)
            -- SAN AO theo chan moi frame -> teleport/di chuyen van co nen, KHONG rot void.
            if c.NukeFakeFloor ~= false then
                local nextFloorAt = 0
                local hb = RunService.Heartbeat:Connect(function()
                    if CFG["Nuke All"] ~= true then return end
                    local now = os.clock()
                    if now < nextFloorAt then return end
                    nextFloorAt = now + math.max(tonumber(c.NukeFloorUpdateInterval) or 0.1, 0.05)
                    nukeUpdateFloor()
                end)
                table.insert(Runtime.Cleanups, function() pcall(function() hb:Disconnect() end) end)
            end
            -- TRICK TURBO (chong yeu cau - FIX "Nuke All = true la may farm DO"): xoa do la task NANG
            -- NHAT luc boot. O cap 7, moi batch 12 vat phai doi 1 frame ~143ms -> xoa ca ngan vat keo
            -- dai ca phut = do. Mo cap 9999 -> nuke xong trong vai giay -> khoa lai cap cu -> GC nha RAM.
            Runtime.BeginTurboFps("nuke all")
            nukeAll()   -- bulk chia batch (da co waitAlive ben trong)
            Runtime.EndTurboFps()
            Runtime.NukeDone = true   -- bao Boot sequencer: nuke XONG roi moi tha wave farm
            Runtime.MapCleanupInitialDone = true
            if CFG.ForceFullGc == true then
                pcall(function() collectgarbage("collect") end)
            end
        end))
    end

    -- Chỉ nối event join khi tính năng xóa plot khác được người dùng chủ động bật.
    if c.OtherPlots ~= false then
        local conn = Players.PlayerAdded:Connect(function(plr)
            if not isAlive() or not (CFG.MapCleanup and CFG.MapCleanup.Enabled) then return end
            actionLog("MapCleanup", "JOIN", tostring(plr and plr.Name))
            if not waitAlive(tonumber(c.JoinWait) or 3) then return end
            cleanOtherPlots()
        end)
        table.insert(Runtime.Cleanups, function() pcall(conn.Disconnect, conn) end)
    end
end

-- Anti-AFK: chống bị đá vì treo máy. Hook LocalPlayer.Idled rồi giả lập input qua VirtualUser
-- (client-side, KHÔNG cần remote). Chỉ nối 1 lần.
function Runtime.SetupAntiAfk()
    if Runtime.AntiAfkConnected then return end
    local c = CFG.AntiAfk
    if not (c and c.Enabled ~= false) then return end
    if not VirtualUser then return end
    Runtime.AntiAfkConnected = true
    -- (1) Hook Idled: chống AFK-kick NATIVE của Roblox (~20 phút treo máy) -> nguyên nhân chính bị "văng game".
    local idleConn
    pcall(function()
        idleConn = LocalPlayer.Idled:Connect(function()
            if not isAlive() then return end
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(0, 0))
            end)
        end)
    end)
    if idleConn then
        table.insert(Runtime.Cleanups, function()
            pcall(idleConn.Disconnect, idleConn)
        end)
    end
    -- (2) JIGGLE ĐỊNH KỲ (gia cố): phòng khi Idled không bắn -> chủ động giả lập input mỗi JiggleInterval giây.
    -- Input giả lập reset CẢ timer AFK của Roblox LẪN timer idle của game (AntiAfkController dựa UserInputService).
    local interval = math.max(tonumber(c.JiggleInterval) or 60, 10)
    local jiggleThread = task.spawn(function()
        while isAlive() do
            if not waitAlive(interval) then break end
            if CFG.AntiAfk and CFG.AntiAfk.Enabled ~= false then
                pcall(function()
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.new(0, 0))
                end)
            end
        end
    end)
    table.insert(Runtime.Tasks, jiggleThread)
    actionLog("AntiAfk", "ON", "hook Idled + jiggle " .. tostring(interval) .. "s")
end

-- ============================================================
-- KILL GAME CONTROLLERS (đợt 9): destroy controller client visual/tick của GAME -> giảm CPU scheduler
-- Lua VM mỗi frame + RAM churn khi treo nhiều tab. CHỈ chạy SAU khi game load xong (LoadingScreenDone).
-- Destroy LocalScript = dừng thread + ngắt connection của NÓ. Rủi ro còn lại: module dùng chung
-- (PlayerStateClient/Networking) có thể được init bởi 1 controller bị giết — KHÔNG xác nhận được trong
-- dump -> vì thế có 2 HEALTH-CHECK + mặc định TẮT (pattern PUMP_ALIVE/PUMP_DEAD đợt 8):
--   (1) PUMP GardenSync: SyncAllGardens phải còn về định kỳ; im lặng quá PumpCheckEvery -> tự xin lại
--       (RequestGardens), vẫn im -> báo PUMP_DEAD (harvest data sẽ chết dần -> tắt flag / rejoin).
--   (2) REPLICA: tiền replica phải bám leaderstats; đứng im + lệch to qua 2 lần check -> REPLICA_DEAD
--       (cap mua theo kho sai -> thêm PlayerStateController vào Keep nếu lỡ xóa).
-- ============================================================
function Runtime.SetupKillGameControllers()
    local c = CFG.KillGameControllers
    if not (c and c.Enabled) then return end
    task.spawn(function()
        if not game:IsLoaded() then pcall(function() game.Loaded:Wait() end) end
        -- đợi qua màn loading/tap-to-play (controller loading còn việc phải làm), tối đa 60s
        local t0 = os.clock()
        while isAlive() and LocalPlayer:GetAttribute("LoadingScreenDone") ~= true and (os.clock() - t0) < 60 do
            task.wait(0.5)
        end
        if not waitAlive(math.max(tonumber(c.Delay) or 10, 0)) then return end
        local ps = LocalPlayer:FindFirstChild("PlayerScripts")
        local folder = ps and ps:FindFirstChild("Controllers")
        if not folder then
            logw("KillGameControllers: khong thay PlayerScripts.Controllers -> bo qua.")
            return
        end
        local keep = {}
        for _, list in ipairs({ c.Keep, c.AlsoKeep }) do
            if type(list) == "table" then
                for _, n in ipairs(list) do
                    if type(n) == "string" and n ~= "" then keep[string.lower(n)] = true end
                end
            end
        end
        Runtime.BeginTurboFps("kill controllers")
        local killed, kept = 0, 0
        for _, child in ipairs(folder:GetChildren()) do
            if keep[string.lower(child.Name)] then
                kept = kept + 1
            elseif pcall(function() child:Destroy() end) then
                killed = killed + 1
                if killed % 25 == 0 then task.wait() end   -- nhả frame: không dồn ~180 destroy vào 1 nhịp
            end
        end
        Runtime.EndTurboFps()
        if CFG.ForceFullGc == true then pcall(function() collectgarbage("collect") end) end
        actionLog("KillCtrl", "DONE", ("killed=%d kept=%d"):format(killed, kept))
        Runtime.KillCtrlBase = ("kill %d | keep %d"):format(killed, kept)
        State.KillCtrlStatus = Runtime.KillCtrlBase

        -- GIẾT SCRIPT LẺ ngoài folder Controllers (đợt 16 - đối chiếu dump PlayerScripts từng tên):
        --   ChatMessages (hiển thị chat), RbxCharacterSounds (tiếng bước chân - respawn-spam re-bind mỗi
        --   lần chết = churn), DisableGamepadPlayerList/DisableResetButton (chỉnh UI), InfiniteGradient
        --   (animate gradient GUI - GUI đã purge), LimitedShop (logic GUI shop - mua bằng remote +
        --   StockValues), Msuhroom (đệm nhún nấm - map đã nuke), TEMPLATE_CONTROLLER/TestFlyScript (rác).
        --   HideCollectProximityPrompts: giữ bảng STRONG-REF mọi HarvestPrompt/StealPrompt + 2 connection
        --   CollectionService bắn MỖI prompt mới (400 cây ra prompt liên tục = churn) - chỉ bật/tắt
        --   HIỂN THỊ prompt, fire prompt của script không phụ thuộc -> giết an toàn.
        if c.KillExtraScripts ~= false then
            local extraNames = type(c.ExtraScriptNames) == "table" and c.ExtraScriptNames or {
                "ChatMessages", "RbxCharacterSounds", "DisableGamepadPlayerList", "DisableResetButton",
                "HideCollectProximityPrompts", "InfiniteGradient", "LimitedShop", "Msuhroom",
                "TEMPLATE_CONTROLLER", "TestFlyScript",
            }
            local e1 = 0
            for _, n in ipairs(extraNames) do
                local obj = ps:FindFirstChild(n)
                if obj and pcall(function() obj:Destroy() end) then e1 = e1 + 1 end
            end
            actionLog("KillCtrl", "EXTRA_SCRIPTS", "giet " .. tostring(e1) .. " script le PlayerScripts")
        end

        -- PURGE GUI CHẾT (RAM đợt 9b): GUI game trước chỉ bị ẨN (NukeHideOtherGui) = instance vẫn nằm
        -- trong RAM. Controller quản lý chết rồi -> XÓA HẲN. Xóa cả TEMPLATE StarterGui để respawn
        -- (respawn-teleport dùng liên tục) không re-clone về lại. GIỮ: GUI của mình + BackpackGui/HUD/
        -- SecretDropLog (InventoryController - con GIỮ - có WaitForChild "SecretDropLog"; HUD giữ cho chắc).
        -- Nhạc: CHỈ xóa SoundService.MusicTracks (MusicController.lua:9 - đã chết); GIỮ folder SFX vì
        -- PlantVisualizerController (con GIỮ) tham chiếu SoundService.SFX.GrowSFX (dòng 868).
        if c.PurgeDeadGui ~= false then
            -- Đợt 16: BỎ HUD khỏi keep — đã rà 5 controller GIỮ: KHÔNG có WaitForChild("HUD")/.HUD nào
            -- (chỉ là tham số string trong handler CLICK chuột mở RobuxShop/Settings — bot không click).
            -- SecretDropLog PHẢI giữ: InventoryController/Main.lua:4527 WaitForChild cứng. BackpackGui giữ
            -- (hotbar - InventoryController con GIỮ quản tool). Cần HUD lại -> thêm vào KeepGui config.
            local keepGui = {
                KaitunCommercial = true, KaitunWinToast = true, NightNotifier = true,
                BackpackGui = true, SecretDropLog = true,
                -- GIU shop + list GUI vi CODE CON SONG van update chung -> xoa = spam console:
                --   * SeedShop/GearShop/CrateShop: RestockStoreController (ClientModule KHONG bi kill) goi
                --     RefreshStock -> Main_Frame.Cost_Text moi lan restock. Xoa -> "Cost_Text is not a valid member".
                --   * GrowingList: GardenSyncController (con GIU) van fire callback cua GrowingListController
                --     (da kill nhung callback song trong subscriber list) -> update Frame GUID. Xoa -> spam sync.
                SeedShop = true, GearShop = true, CrateShop = true, GrowingList = true,
            }
            if type(c.KeepGui) == "table" then
                for _, n in ipairs(c.KeepGui) do
                    if type(n) == "string" and n ~= "" then keepGui[n] = true end
                end
            end
            -- ẨN thay vì DESTROY (fix console spam): NHIỀU code CÒN SỐNG (GardenSyncController con GIU fire
            -- callback cua controller da kill; RestockStoreController/NotificationController la ClientModule
            -- KHONG bi kill) van update GUI game (Cost_Text/UIListLayout/Main_Frame/Notification_UI...). Destroy
            -- GUI -> chung goi vao instance da mat -> spam "X is not a valid member". ẨN (Enabled=false + tat
            -- ScreenGui.Enabled) giu instance cho callback chay IM, nhung KHONG render -> RAM/GPU van nhe, het
            -- spam. Muon destroy han (chap nhan spam) -> PurgeDeadGuiDestroy=true.
            -- ẨN (Enabled=false) GIU NGUYEN PARENT: KHONG reparent/destroy -> moi code con song (ke ca
            -- re-fetch qua FindFirstChild) van thay GUI -> callback chay IM, het spam. ScreenGui.Enabled=false
            -- = engine KHONG render (nha texture GUI) nen RAM/GPU van nhe. Muon destroy han -> PurgeDeadGuiDestroy=true.
            local destroyGui = c.PurgeDeadGuiDestroy == true
            local function killOrHideGui(gui)
                if destroyGui then
                    return pcall(function() gui:Destroy() end)
                end
                return pcall(function()
                    if gui:IsA("ScreenGui") then gui.Enabled = false
                    elseif gui:IsA("LocalScript") then gui.Disabled = true end
                end)
            end
            local g1, g2, g3 = 0, 0, 0
            local pg = LocalPlayer:FindFirstChildOfClass("PlayerGui")
            if pg then
                for _, gui in ipairs(pg:GetChildren()) do
                    -- LocalScript lẻ nằm thẳng trong PlayerGui (dump: ConsoleIconMapper) cũng là đồ GUI chết
                    if (gui:IsA("ScreenGui") or gui:IsA("LocalScript")) and not keepGui[gui.Name] then
                        if killOrHideGui(gui) then g1 = g1 + 1 end
                    end
                end
            end
            -- StarterGui template: CHI destroy khi PurgeDeadGuiDestroy (tranh respawn re-clone RAM churn).
            -- Che do an: BO QUA (template khong render san; giu de respawn co GUI -> callback khong loi).
            if destroyGui then
                pcall(function()
                    for _, tpl in ipairs(game:GetService("StarterGui"):GetChildren()) do
                        if not keepGui[tpl.Name] then
                            pcall(function() tpl:Destroy() end)
                            g2 = g2 + 1
                        end
                    end
                end)
            end
            -- SOUND SWEEP TOÀN CỤC (đợt 9c - ĐO BRIDGE 2026-07-12: tag Sounds 74MB -> 9MB, private RAM
            -- -41MB): destroy MỌI Sound trong SoundService + workspace + ReplicatedStorage. Controller
            -- nhạc/SFX chết hết rồi nên không ai phát lại. CHỪA đúng "GrowSFX" vì
            -- PlantVisualizerController (con GIỮ) tham chiếu SoundService.SFX.GrowSFX (dòng 868).
            pcall(function()
                for _, root in ipairs({ game:GetService("SoundService"), workspace, ReplicatedStorage }) do
                    for _, s in ipairs(root:GetDescendants()) do
                        if s:IsA("Sound") and s.Name ~= "GrowSFX" then
                            pcall(function() s:Destroy() end)
                            g3 = g3 + 1
                        end
                    end
                end
            end)
            -- CUTSCENES (đợt 9c - ĐO BRIDGE: Assets.Cutscenes = 36k instance = 73% kho Assets; ~11MB
            -- BaseParts + bớt overhead instance/GC). CutsceneController đã chết -> không ai dùng.
            -- KHÔNG đụng ChainedMoon/RainbowMoon/PizzaMoon (TimeCycleController - con GIỮ - dùng khi đêm event).
            local g4 = 0
            pcall(function()
                local cut = ReplicatedStorage:FindFirstChild("Assets")
                cut = cut and cut:FindFirstChild("Cutscenes")
                if cut then
                    g4 = #cut:GetDescendants()
                    cut:Destroy()
                end
            end)
            if CFG.ForceFullGc == true then pcall(function() collectgarbage("collect") end) end
            actionLog("KillCtrl", "PURGE_GUI", ("gui=%d tpl=%d snd=%d cut=%d"):format(g1, g2, g3, g4))
            Runtime.KillCtrlBase = Runtime.KillCtrlBase .. (" | gui %d snd %d cut %dk"):format(g1, g3, math.floor(g4 / 1000))
            State.KillCtrlStatus = Runtime.KillCtrlBase
        end

        -- PURGE ASSET MỒ CÔI (đợt 15 - xóa SÂU hơn theo yêu cầu chồng): các folder con của
        -- ReplicatedStorage.Assets mà TOÀN BỘ controller tham chiếu đã bị giết ở trên -> không ai còn
        -- Clone/WaitForChild -> destroy nhả RAM model+texture (pet/trứng/crate/VFX/gear/vườn decor...).
        -- ĐÃ ĐỐI CHIẾU DUMP từng tên (map Assets.<X> -> file Controllers/*):
        --   * KHÔNG đụng Seeds/Plants: PlantVisualizerController (con GIỮ) clone cây qua
        --     GetSeedData(name).PlantModel (dòng 1308) - module SeedData KHÔNG có trong dump nên vị trí
        --     vật lý của PlantModel CHƯA xác nhận -> không được liều (destroy xong Clone ra model rỗng).
        --   * KHÔNG đụng POT (PlantVisualizer:1398), Skybox/Vignette/Night/NightAtmosphere/Bloodmoon/
        --     Goldmoon/ChainedMoon/MegaMoon/PizzaMoon/RainbowMoon/Rainbow*Effect/meteor/Chain*/Enchained*/
        --     GoldDisperse... và Animations (TimeCycleController - con GIỮ - dùng khi đổi phase/đêm event).
        if c.PurgeKilledAssets ~= false then
            local keepAssets = {}
            if type(c.KeepAssets) == "table" then
                for _, n in ipairs(c.KeepAssets) do
                    if type(n) == "string" and n ~= "" then keepAssets[n] = true end
                end
            end
            local orphanNames = {
                -- weather/FX (WeatherController + FX controller: Aurora/Starfall/Sunburst/Snowfall/
                -- DragonBreath/GhostPepper/PoisonIvy/Steal/BlockSmash/Mutation/Wateringcan... da chet)
                "AuroraEffects", "Snowfall", "StarfallModel", "SunburstModel", "SunfireFireTrail",
                "ShootingStarMeteor", "Rainbow", "VFX",
                -- GIU LAI (khong xoa): PopVFXModel/PopVFX/Poof/DigParticle/ShakeParticle - StealController +
                -- SpawnPetController da bi kill NHUNG callback VFX cua chung SONG SOT qua SharedModules.Packet
                -- (remote callback ko bi go khi destroy script) -> khi co trom/spawn pet chung goi Assets.PopVFXModel...
                -- ma da xoa -> spam console "X is not a valid member of Assets". Giu lai = VFX vo hai, het spam.
                "Stud_Part", "Ice_Part", "DragonBreathEnd",
                -- pet/trung/crate (PetVisual/SpawnPet/EggOpen/Crate*/Bird*/Raccoon*/Gnome da chet;
                -- mua pet van song bang remote WildPetTame - da chung minh dot 8)
                "Pets", "PetAssets", "PetTorso", "PetCostTimer", "PetLeaveTimer", "PetTeleporters",
                "Raccoon", "Robin", "Gnome", "Eggs", "EggEffects", "Crates", "GuildCrates",
                -- animation mo seed pack (SeedPackOpen da chet; FastSeedPackConfirm bo animation)
                "SeedPackEffects", "SeedNameAttachment",
                -- gear + vuon decor (Sprinkler*/Rake*/GardenVisual/VineWrapper/StrawberrySniper/
                -- WeatherStaff/PlantController da chet; buff sprinkler = server, trong/tuoi = remote)
                "GearAssets", "Rakes", "Sprinklers", "SprinklerRadius", "Dirt",
                "BedSection", "FRONT_BedSection", "FenceThemes", "Flower",
                "Vine", "VineTemplate", "VineArmTemplate", "VineWrapperAssets",
                -- misc (NotificationController/GreenbeanAvatar da chet)
                -- GIU NotificationUI: NotificationController (con song) clone tu day -> xoa = "Content is
                -- not a valid member of Frame Notification_UI" spam. Nho -> giu vo hai.
                "GreenbeanHumanoidDescription",
                -- template QUA (FruitVisualizer/DisplayPlantGrowth/Pot* da chet; data-harvest chi can
                -- DATA qua tu GardenSync, khong can model)
                "Fruits",
                -- dot 17 (soi live bang bridge, ~3.8k instance): Props (PropController/PropVisualizer/
                -- Crowbar/Boombox/GearInspect - chet het; GardenSync doc v.Props la DATA sync, khong phai
                -- asset), Weather (SeedToolTipController - chet), PlotAssets (GardenVisualController - chet
                -- + GUI CustomiseFenceTheme da xoa), BeanstalkSkins/OverheadLevelUIS/ExtraPreview (KHONG
                -- co tham chieu client nao trong dump).
                "Props", "Weather", "BeanstalkSkins", "PlotAssets", "OverheadLevelUIS", "ExtraPreview",
            }
            -- SeedPacks/BillboardUIs: 2 consumer con lai (RobuxShopClient nam TRONG ScreenGui RobuxShop,
            -- Controller2 nam TRONG PropsFrame - dump PlayerGui) da bi PURGE_GUI xoa o tren -> mo coi.
            -- Claim seed KHONG can model pack: server tu detect proximity, script fire remote/prompt/touch.
            if c.PurgeDeadGui ~= false then
                orphanNames[#orphanNames + 1] = "SeedPacks"
                orphanNames[#orphanNames + 1] = "BillboardUIs"
            end
            local assets = ReplicatedStorage:FindFirstChild("Assets")
            local a1, a2 = 0, 0
            if assets then
                for _, n in ipairs(orphanNames) do
                    if not keepAssets[n] then
                        local obj = assets:FindFirstChild(n)
                        if obj then
                            a2 = a2 + #obj:GetDescendants() + 1
                            if pcall(function() obj:Destroy() end) then
                                a1 = a1 + 1
                                if a1 % 8 == 0 then task.wait() end   -- nhả frame, không dồn destroy to
                            end
                        end
                    end
                end
            end
            -- quét nốt XÁC VFX thời tiết đang nằm sẵn trong workspace: WeatherController chết rồi thì
            -- không ai spawn lại -> destroy hẳn thay vì chỉ suppress (tên lấy từ MapCleanup.WeatherEffectNames,
            -- toàn bộ do WeatherController quản - TimeCycle KHÔNG dùng tên nào trong list này).
            local a3 = 0
            local wnames = CFG.MapCleanup and CFG.MapCleanup.WeatherEffectNames
            if type(wnames) == "table" then
                local wset = {}
                for _, n in ipairs(wnames) do
                    if type(n) == "string" then wset[n] = true end
                end
                for _, child in ipairs(workspace:GetChildren()) do
                    if wset[child.Name] then
                        if pcall(function() child:Destroy() end) then a3 = a3 + 1 end
                    end
                end
            end
            actionLog("KillCtrl", "PURGE_ASSETS", ("folder=%d inst=%d weather=%d"):format(a1, a2, a3))
            Runtime.KillCtrlBase = Runtime.KillCtrlBase .. (" | asset %dk"):format(math.floor(a2 / 1000))
            State.KillCtrlStatus = Runtime.KillCtrlBase
        end

        -- HEALTH-CHECK định kỳ: cập nhật dòng status GUI (State.KillCtrlStatus) mỗi vòng; chỉ LOG khi CHẾT
        local checkEvery = math.max(tonumber(c.PumpCheckEvery) or 240, 60)
        local lastReplicaMoney = nil
        while isAlive() do
            if not waitAlive(checkEvery) then return end
            local pumpDead, replicaDead = false, false
            -- (1) PUMP GardenSync: SyncAllGardens gần nhất bao lâu rồi? (doDataHarvest tự xin mỗi DataResyncEvery)
            local lastSync = tonumber(Runtime.GardenDataReadyAt) or 0
            if (os.clock() - lastSync) > checkEvery then
                firePacket({ "Garden", "RequestGardens" })   -- tự xin lại 1 phát trước khi kết luận
                if not waitAlive(10) then return end
                lastSync = tonumber(Runtime.GardenDataReadyAt) or 0
                if (os.clock() - lastSync) > checkEvery then
                    pumpDead = true
                    State.LastWatchdog = os.date("%H:%M:%S") .. " PUMP_DEAD"
                    actionLog("KillCtrl", "PUMP_DEAD", "SyncAllGardens khong ve -> tat KillGameControllers / rejoin")
                end
            end
            -- (2) REPLICA: tiền replica đứng im + lệch to so với leaderstats = pump replica chết
            local leader = tonumber(getSheckles())
            local rep = getPlayerReplica()
            local repMoney = rep and rep.Data and tonumber(rep.Data.Sheckles)
            if leader and repMoney then
                local frozen = lastReplicaMoney ~= nil and repMoney == lastReplicaMoney
                local off = math.abs(leader - repMoney) > math.max(leader * 0.05, 50000)
                if frozen and off then
                    replicaDead = true
                    State.LastWatchdog = os.date("%H:%M:%S") .. " REPLICA_DEAD"
                    actionLog("KillCtrl", "REPLICA_DEAD", "replica dung im lech leaderstats -> giu PlayerStateController trong Keep")
                end
                lastReplicaMoney = repMoney
            end
            -- STATUS GUI: khỏe = "pump OK hh:mm" (giờ check gần nhất); bệnh = tên bệnh IN HOA nhìn thấy liền
            local health = pumpDead and "PUMP_DEAD!" or "pump OK"
            if replicaDead then health = health .. " REPLICA_DEAD!" end
            State.KillCtrlStatus = (Runtime.KillCtrlBase or "on") .. " | " .. health .. " " .. os.date("%H:%M")
        end
    end)
end

-- ============================================================
-- BOOT TUAN TU (dot 5 - chong yeu cau "CHAY TUNG FLOW"): thay vi 40+ task cung xong vao luc data
-- chua load du ("chay nhu dien"), gio boot theo TRINH TU, chap nhan mat ~30-60s cho MOI THU ON DINH:
--   [0s, tha ngay]  AutoStartGame + FpsCap + MemJanitor + AutoCollectDrops (claim event khong can data vuon)
--   [buoc 1] doi FPS BOOST + MAP CLEANUP som xong (FpsBootDone)
--   [buoc 2] Nuke All bat -> doi NUKE BULK xong han (xoa do = task nang nhat; co TURBO fps ho tro)
--   [buoc 3] doi DATA VUON ve du (SyncAllGardens), toi da BootDataWait giay
--   [WAVE 1] hai / ban / guard / watch / mua pet   -> nghi BootWaveGap
--   [WAVE 2] trong / trim / tuoi / sprinkler / hide tree -> nghi BootWaveGap
--   [WAVE 3] tha het phan con lai (shop/mail/pet phu/ESP...)
-- Task doi qua BootMaxWait chua duoc tha (sequencer loi bat ngo) -> TU tha, khong ket vinh vien.
-- Tat che do nay: CFG.BootSequential = false (ve kieu cu).
-- ============================================================
Runtime.BootReleased = { AutoStartGame = true, FpsCap = true, MemJanitor = true, MemWatch = true, AutoCollectDrops = true }
Runtime.BootWave1 = {
    AutoCollect = true, AutoSell = true, AutoSellFull = true, AntiSteal = true,
    ValuableWatcher = true, AutoTameWildPet = true,
}
Runtime.BootWave2 = {
    AutoPlant = true, TrimToQuota = true, AutoWater = true, AutoSprinkler = true, HideTreeKeepFruit = true,
}
Runtime.ReleaseWave = function(set)
    for k in pairs(set) do Runtime.BootReleased[k] = true end
end
Runtime.BootSequencer = function()
    if CFG.BootSequential == false then
        Runtime.BootReleasedAll = true
        return
    end
    local t0 = os.clock()
    -- buoc 1: doi fps boost + don dep som (BootEarlyCleanup dat FpsBootDone)
    while isAlive() and Runtime.FpsBootDone ~= true and (os.clock() - t0) < 30 do task.wait(0.25) end
    -- buoc 2: Nuke All -> doi nuke bulk XONG (dot xoa nang nhat, co turbo fps rieng)
    if CFG["Nuke All"] == true then
        while isAlive() and Runtime.NukeDone ~= true and (os.clock() - t0) < 45 do task.wait(0.5) end
    end
    -- buoc 3: doi DATA vuon ve du -> khong trong/hai bay khi data chua load
    local dataWait = math.max(tonumber(CFG.BootDataWait) or 45, 5)
    while isAlive() and not Runtime.IsGardenDataReady() and (os.clock() - t0) < dataWait do task.wait(0.5) end
    local gap = math.max(tonumber(CFG.BootWaveGap) or 5, 0)
    actionLog("Boot", "WAVE1", ("t=%ds hai/ban/guard/pet"):format(math.floor(os.clock() - t0)))
    Runtime.ReleaseWave(Runtime.BootWave1)
    if not waitAlive(gap) then return end
    actionLog("Boot", "WAVE2", "trong/trim/tuoi")
    Runtime.ReleaseWave(Runtime.BootWave2)
    if not waitAlive(gap) then return end
    actionLog("Boot", "WAVE3", "shop/mail/phu -> boot XONG, vao guong on dinh")
    Runtime.BootReleasedAll = true
end

local function loopTask(name, fn, getDelay)
    Runtime.LoopTaskIndex = (Runtime.LoopTaskIndex or 0) + 1
    local taskIndex = Runtime.LoopTaskIndex
    local thread = task.spawn(function()
        local stagger = CFG.LowFpsMode and tonumber(CFG.LowFpsMode.StartupStagger) or 0
        if stagger and stagger > 0 and taskIndex > 1 then
            if not waitAlive(math.min(stagger * (taskIndex - 1), 4)) then
                return
            end
        end

        -- BOOT TUAN TU (dot 5 - "chay tung flow"): moi task DOI toi wave cua minh moi bat dau
        -- (trinh tu xem Runtime.BootSequencer o tren). Qua BootMaxWait chua duoc tha -> tu tha.
        if CFG.BootSequential ~= false then
            local maxW = tonumber(CFG.BootMaxWait) or 90
            local waited = 0
            while isAlive() and not (Runtime.BootReleasedAll or Runtime.BootReleased[name]) and waited < maxW do
                if not waitAlive(0.25) then return end
                waited = waited + 0.25
            end
        elseif not Runtime.ImportantLoopTasks[name] then
            -- fallback kieu cu (BootSequential=false): task phu chi doi fps boost xong (toi da 12s)
            local waited = 0
            while isAlive() and Runtime.FpsBootDone ~= true and waited < 12 do
                if not waitAlive(0.2) then return end
                waited = waited + 0.2
            end
        end

        while isAlive() do
            local status = Runtime.TaskStatus[name] or {}
            status.LastRun = os.clock()
            status.Runs = (status.Runs or 0) + 1
            Runtime.TaskStatus[name] = status

            if Runtime.ShouldYieldForMovement(name) then
                -- Dang claim seed / mua pet teleport -> nhuong de khong giat (tru chinh task dang giu khoa).
                status.Deferred = (status.Deferred or 0) + 1
                status.LastErr = nil
            elseif Runtime.ShouldDeferForSeedClaim(name) then
                -- DOC CHIEM CLAIM SEED: dang co seed spawn/claim -> moi task DUNG cho nhat het seed spam.
                status.Deferred = (status.Deferred or 0) + 1
                status.LastErr = nil
            elseif Runtime.ShouldDeferForCriticalFps(name) then
                status.Deferred = (status.Deferred or 0) + 1
            else
                -- DONG HO CPU (dot 17): do wall-time moi vong de bat task giat CPU (task co yield ben
                -- trong se hien so to gia tao - doc kem ten task de phan biet). Xem qua bridge:
                -- Runtime.TaskStatus[name].LastMs/MaxMs/SumMs.
                local t0 = os.clock()
                local ok, err = pcall(fn)
                local dtMs = (os.clock() - t0) * 1000
                status.LastMs = dtMs
                status.SumMs = (status.SumMs or 0) + dtMs
                if dtMs > (status.MaxMs or 0) then status.MaxMs = dtMs end
                if ok then
                    status.LastOk = os.clock()
                    status.LastErr = nil
                else
                    status.LastErr = tostring(err)
                    status.Errors = (status.Errors or 0) + 1
                    logw(name, "loi:", err)
                    actionLog(name, "ERROR", compactText(err, 80))
                end
            end

            local delayOk, delay = pcall(getDelay)
            if not delayOk then
                logw(name, "delay loi:", delay)
                delay = 1
            end
            delay = Runtime.AdaptiveDelay(name, delay or 1)
            delay = Runtime.ApplySideTaskMinDelay(name, delay)   -- ép tác vụ phụ >= SideTaskMinDelay (FPS)
            if not waitAlive(delay or 1) then
                break
            end
        end
        actionLog(name, "STOPPED")
    end)
    table.insert(Runtime.Tasks, thread)
end

Runtime.SafeBoot = function(name, fn)
    if not isAlive() then return false end
    local ok, err = pcall(fn)
    if not ok then
        State.LastWatchdog = os.date("%H:%M:%S") .. " boot " .. tostring(name)
        actionLog("Watchdog", "ERROR", tostring(name) .. " " .. compactText(err, 80))
    end
    return ok
end

-- ============================================================
-- GUI THUONG MAI "Thieu Nang Hub" (DA XOA GUI cu KaitunDashboard) -> chi con GUI nay, full man hinh.
-- Config tuy chon: ConfigsKaitun.Commercial = { Discord="...", HubName="..." }
-- Gan vao Runtime.* de KHONG them local o main chunk (Lua gioi han 200 local).
-- ============================================================
Runtime.DashboardGuiName = function()
    return "KaitunCommercial"   -- DA XOA GUI cu: chi con GUI kinh doanh "Thieu Nang Hub"
end

-- TẮT/BẬT render 3D. ĐÂY LÀ TÍNH NĂNG EXECUTOR — CHƯA xác nhận trong source game, bọc pcall an toàn.
-- GUI thương mại phủ kín full màn nên tắt render 3D -> nhẹ FPS/CPU mà KHÔNG ảnh hưởng bot (bot dùng
-- remote/CFrame/đọc workspace, không cần camera vẽ). Thử RunService:Set3dRenderingEnabled rồi setrenderbool.
Runtime.Render3DState = (Runtime.Render3DState == nil) and true or Runtime.Render3DState
Runtime.Set3DRendering = Runtime.Set3DRendering or function(enabled)
    enabled = enabled and true or false
    if Runtime.Render3DState == enabled then return end
    local ok = false
    pcall(function()
        local rs = game:GetService("RunService")
        if rs and rs.Set3dRenderingEnabled then
            rs:Set3dRenderingEnabled(enabled); ok = true
        end
    end)
    if not ok and type(setrenderbool) == "function" then
        pcall(function() setrenderbool("Render3D", enabled); ok = true end)
    end
    if ok then
        Runtime.Render3DState = enabled
        actionLog("Render3D", enabled and "ON" or "OFF")
    end
end

-- PARENT GUI AN TOAN (chong cutscene cay moc offline AN GUI): OfflineGrowthAnimationController (source that,
-- dong 757-762 + 1143-1147) duyet MOI ScreenGui trong PlayerGui (tru OfflineAnimation) va ep Enabled=false
-- suot cutscene -> GUI minh BIEN MAT. Fix: parent GUI ra ngoai PlayerGui (gethui/CoreGui). Cutscene chi dung
-- PlayerGui:GetChildren(), va SetCoreGuiEnabled KHONG anh huong ScreenGui custom o CoreGui -> GUI luon hien.
Runtime.GetGuiParent = function()
    if type(gethui) == "function" then
        local ok, hui = pcall(gethui)
        if ok and hui then return hui end
    end
    local okCore, core = pcall(function() return game:GetService("CoreGui") end)
    if okCore and core then return core end
    return LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
end

-- Bao ve GUI khoi bi game/anti-cheat duyet-destroy (neu executor ho tro). An toan: pcall, khong ho tro thi thoi.
Runtime.ProtectGui = function(gui)
    if not gui then return end
    if type(syn) == "table" and type(syn.protect_gui) == "function" then
        pcall(syn.protect_gui, gui)
    elseif type(protectgui) == "function" then
        pcall(protectgui, gui)
    end
end

Runtime.SetupCommercialGui = function()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 10)
    if not playerGui then return end
    local guiHost = Runtime.GetGuiParent() or playerGui
    local cc = getgenv().ConfigsKaitun
    local com = (type(cc) == "table" and type(cc.Commercial) == "table") and cc.Commercial or {}
    local DISCORD = tostring(com.Discord or com.DiscordLink or "discord.gg/thieunnaghub")
    local HUBNAME = tostring(com.HubName or "Thieu Nang Hub")

    -- Dedupe: xoa GUI cu o CA PlayerGui (legacy) lan host moi + ref da luu -> khong tao trung khi recover.
    if Runtime.CommercialGui then pcall(function() Runtime.CommercialGui:Destroy() end); Runtime.CommercialGui = nil end
    local oldPg = playerGui:FindFirstChild("KaitunCommercial")
    if oldPg then oldPg:Destroy() end
    local oldHost = guiHost ~= playerGui and guiHost:FindFirstChild("KaitunCommercial") or nil
    if oldHost then oldHost:Destroy() end

    -- Palette KHAC duckhub (ho dung vang) -> minh dung xanh ngoc + tim
    local BG      = Color3.fromRGB(13, 15, 22)
    local PANEL   = Color3.fromRGB(22, 26, 36)
    local ACCENT  = Color3.fromRGB(94, 234, 212)
    local ACCENT2 = Color3.fromRGB(167, 139, 250)
    local TEXT    = Color3.fromRGB(236, 241, 248)
    local LINE    = Color3.fromRGB(46, 54, 72)
    local GOLD    = Color3.fromRGB(250, 204, 21)

    local gui = Instance.new("ScreenGui")
    gui.Name = "KaitunCommercial"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = tonumber(com.DisplayOrder) or 999
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = guiHost                 -- gethui/CoreGui -> cutscene offline KHONG an duoc GUI nay
    Runtime.ProtectGui(gui)
    Runtime.CommercialGui = gui
    table.insert(Runtime.Cleanups, function() if gui then pcall(function() gui:Destroy() end) end end)

    -- 3D RENDERING: MAC DINH TAT -> CPU/GPU NHE NHAT (~0.5% giong cac script khac). Khong render game =
    -- het ton CPU render (day la khac biet 2% vs 0.5%). Panel status van hien tren NEN DEN (du de monitor).
    -- MUON THAY GAME (CPU cao hon): set Commercial.Disable3D = false.
    local toggle3D = com.Disable3D ~= false
    if toggle3D then
        Runtime.Set3DRendering(false)
        if not Runtime._render3DCleanupAdded then
            Runtime._render3DCleanupAdded = true
            table.insert(Runtime.Cleanups, function() Runtime.Set3DRendering(true) end)
        end
    else
        Runtime.Set3DRendering(true)   -- chong muon THAY game -> bat 3D (CPU cao hon)
        pcall(function() game:GetService("RunService"):Set3dRenderingEnabled(true) end)
    end

    -- AN UI GAME (kieu Nova): tat CoreGui (topbar Roblox / playerlist / chat / hotbar-backpack) -> chi con
    -- nen den + panel status. setGameUiHidden(true)=an het, (false)=hien lai (de bam nut Hide GUI xem game).
    -- com.KeepHotbar=false neu muon an LUON ca hotbar. Mac dinh GIU hotbar (Backpack) = thanh o chon do duoi.
    -- CHI dong/mo CoreGui (playerlist/chat/topbar) - day la API AN TOAN.
    -- TUYET DOI KHONG set Enabled cho ScreenGui GAME trong PlayerGui: lam vay = FORCE-MO MOI dialog game
    -- (Gift A Friend / Buy item / shop...) cung luc -> "ui game load 1 dong" (bug cu). Nen DEN duc da CHE
    -- het ScreenGui game roi (DisplayOrder 999), khong can dong chung.
    -- KHONG bao gio BAT lai CoreGuiType.Backpack (bo logic keepHotbar cu): GAME co INVENTORY RIENG
    -- "BackpackGui" o PlayerGui (xac nhan InventoryController/Main.lua:83-87, DisplayOrder 120) va game TU
    -- TAT hotbar Roblox mac dinh (Main.lua:3236 SetCoreGuiEnabled(Backpack,false)). Neu minh bat lai ->
    -- hotbar Roblox mac dinh DE LEN inventory game = "2 hotbar chong nhau" (dung bug chong bao). Inventory
    -- game nam o PlayerGui nen SetCoreGuiEnabled(All) KHONG dung toi -> peek (Hide GUI) van thay do binh thuong.
    local function setGameUiHidden(hidden)
        pcall(function()
            local sg = game:GetService("StarterGui")
            sg:SetCoreGuiEnabled(Enum.CoreGuiType.All, not hidden)   -- an playerlist/chat/emotes... (CoreGui)
            sg:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)   -- LUON tat hotbar Roblox mac dinh (GIONG game)
        end)
    end
    setGameUiHidden(true)
    if not Runtime._coreGuiCleanupAdded then
        Runtime._coreGuiCleanupAdded = true
        table.insert(Runtime.Cleanups, function() pcall(function()
            game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, true)
        end) end)
    end

    local bg = Instance.new("Frame")
    bg.Name = "BG"
    bg.Size = UDim2.fromScale(1, 1)
    bg.AnchorPoint = Vector2.new(0.5, 0.5)   -- NEO GIUA: thu nho cua so thi panel co ve GIUA (khong dat goc)
    bg.Position = UDim2.fromScale(0.5, 0.5)
    bg.BackgroundColor3 = Color3.fromRGB(8, 9, 13)
    bg.BackgroundTransparency = 0            -- NEN DEN DUC che het (game UI + 3D) -> kieu full man Nova
    bg.BorderSizePixel = 0
    bg.Parent = gui
    local grad = Instance.new("UIGradient")
    grad.Color = ColorSequence.new(Color3.fromRGB(15, 17, 26), Color3.fromRGB(20, 16, 30))
    grad.Rotation = 90
    grad.Parent = bg

    -- PANEL = 1 CARD theo % cua so (scale) -> tu FILL moi co cua so (man nho/to/multi-acc deu vua). KHONG
    -- dung pixel co dinh nua. Chinh do rong/cao = com.GuiWidth / com.GuiHeight (0-1). Chu dung TextScaled.
    local hideBtn = Instance.new("TextButton")
    hideBtn.AnchorPoint = Vector2.new(1, 0)
    hideBtn.Position = UDim2.new(1, -6, 0.01, 0)
    hideBtn.Size = UDim2.new(0.17, 0, 0.05, 0)
    hideBtn.BackgroundColor3 = ACCENT
    hideBtn.TextColor3 = Color3.fromRGB(10, 14, 20)
    hideBtn.Font = Enum.Font.GothamBold
    hideBtn.TextScaled = true
    hideBtn.Text = "Hide GUI"
    hideBtn.ZIndex = 5
    hideBtn.Parent = bg
    Instance.new("UICorner", hideBtn).CornerRadius = UDim.new(0, 8)
    do local hp = Instance.new("UIPadding", hideBtn)
        hp.PaddingTop = UDim.new(0, 4); hp.PaddingBottom = UDim.new(0, 4)
        hp.PaddingLeft = UDim.new(0, 8); hp.PaddingRight = UDim.new(0, 8) end

    local panel = Instance.new("Frame")
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.Size = UDim2.new(
        math.clamp(tonumber(com.GuiWidth) or 0.72, 0.2, 1), 0,
        math.clamp(tonumber(com.GuiHeight) or 0.86, 0.2, 1), 0)   -- chua dat 0.86: de chua hotbar o day khong che hang cuoi
    panel.BackgroundColor3 = PANEL
    panel.BackgroundTransparency = 0.1
    panel.BorderSizePixel = 0
    panel.Parent = bg
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 16)
    local ps = Instance.new("UIStroke", panel); ps.Color = ACCENT; ps.Transparency = 0.45; ps.Thickness = 1.5
    local pp = Instance.new("UIPadding", panel)
    pp.PaddingTop = UDim.new(0.02, 0); pp.PaddingBottom = UDim.new(0.02, 0)
    pp.PaddingLeft = UDim.new(0.03, 0); pp.PaddingRight = UDim.new(0.03, 0)
    local pl = Instance.new("UIListLayout", panel)
    pl.SortOrder = Enum.SortOrder.LayoutOrder
    pl.Padding = UDim.new(0.005, 0)
    pl.HorizontalAlignment = Enum.HorizontalAlignment.Center

    local ord = 0
    -- moi row cao theo % PANEL + TextScaled -> chu tu to/nho theo cua so, FILL dep o moi co.
    local function row(h, color)
        ord = ord + 1
        local l = Instance.new("TextLabel")
        l.LayoutOrder = ord
        l.BackgroundTransparency = 1
        l.Size = UDim2.new(1, 0, h or 0.058, 0)
        l.Font = Enum.Font.GothamSemibold
        l.TextScaled = true
        l.TextColor3 = color or TEXT
        l.TextXAlignment = Enum.TextXAlignment.Center
        l.Text = ""
        l.Parent = panel
        local c = Instance.new("UITextSizeConstraint", l); c.MaxTextSize = 40; c.MinTextSize = 6
        return l
    end
    local function divider()
        ord = ord + 1
        local d = Instance.new("Frame")
        d.LayoutOrder = ord
        d.Size = UDim2.new(0.96, 0, 0.004, 0)
        d.BackgroundColor3 = LINE
        d.BorderSizePixel = 0
        d.Parent = panel
    end

    -- Banner discord + hub = 2 row dau (to hon)
    local discord = row(0.075, ACCENT); discord.Font = Enum.Font.GothamBold;   discord.Text = "\u{1F517} " .. DISCORD
    local hub     = row(0.05, ACCENT2); hub.Font     = Enum.Font.GothamMedium; hub.Text     = "\u{2B50} " .. HUBNAME
    divider()
    local vUser  = row(0.07)
    local vTask  = row(0.058, ACCENT)
    divider()
    local vMoney = row()
    local vEarn  = row()
    local vPlant = row()
    local vFruit = row()
    local vHarv  = row()
    local vPets  = row()
    local vExp   = row()
    -- HELD FRUIT PANEL (chong dot 20): THAY dong "Events / du doan thoi tiet" bang LIST fruit dang GIU
    -- (KeepCropsForSell / SellAllForMultipliers cho x4) + mutation moi loai; SCROLL len/xuong khong tran GUI.
    local vHeldTitle = row(0.045, GOLD); vHeldTitle.Font = Enum.Font.GothamBold
    vHeldTitle.Text = "\u{1F9EC} Fruit dang giu (cho x4):"
    ord = ord + 1
    local heldScroll = Instance.new("ScrollingFrame")
    heldScroll.LayoutOrder = ord
    -- Cao co dinh -> LIST tran thi SCROLL trong khung nay (khong day cac dong duoi ra ngoai panel).
    -- Chinh cao/thap = doi 0.13 (0-1 theo panel). ScrollBar keo len/xuong xem het loai dang giu.
    heldScroll.Size = UDim2.new(0.98, 0, 0.13, 0)
    heldScroll.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
    heldScroll.BackgroundTransparency = 0.25
    heldScroll.BorderSizePixel = 0
    heldScroll.ScrollBarThickness = 5
    heldScroll.ScrollBarImageColor3 = ACCENT
    heldScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    heldScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    heldScroll.ScrollingDirection = Enum.ScrollingDirection.Y
    heldScroll.Active = true
    heldScroll.Parent = panel
    Instance.new("UICorner", heldScroll).CornerRadius = UDim.new(0, 8)
    do
        local hsl = Instance.new("UIListLayout", heldScroll)
        hsl.SortOrder = Enum.SortOrder.LayoutOrder
        hsl.Padding = UDim.new(0, 2)
        local hsp = Instance.new("UIPadding", heldScroll)
        hsp.PaddingLeft = UDim.new(0, 8); hsp.PaddingRight = UDim.new(0, 8)
        hsp.PaddingTop = UDim.new(0, 3); hsp.PaddingBottom = UDim.new(0, 3)
    end
    Runtime.HeldPanel = { Scroll = heldScroll, Title = vHeldTitle, Pool = {} }
    divider()
    local vEquip = row()
    local vFps   = row(0.058, GOLD)
    -- Dòng status KillGameControllers (đợt 9): CHỈ tạo khi bật flag -> tab không bật GUI y như cũ.
    local vKill  = (CFG.KillGameControllers and CFG.KillGameControllers.Enabled) and row(0.055, ACCENT) or nil
    local vTime  = row(0.058, ACCENT2)

    local showBtn = Instance.new("TextButton")
    showBtn.AnchorPoint = Vector2.new(1, 0)
    showBtn.Position = UDim2.new(1, -6, 0.01, 0)
    showBtn.Size = UDim2.new(0.17, 0, 0.05, 0)
    showBtn.BackgroundColor3 = ACCENT2
    showBtn.TextColor3 = Color3.fromRGB(10, 14, 20)
    showBtn.Font = Enum.Font.GothamBold
    showBtn.TextScaled = true
    showBtn.Text = "Show GUI"
    showBtn.Visible = false
    showBtn.ZIndex = 5
    showBtn.Parent = gui
    Instance.new("UICorner", showBtn).CornerRadius = UDim.new(0, 8)
    do local sp = Instance.new("UIPadding", showBtn)
        sp.PaddingTop = UDim.new(0, 4); sp.PaddingBottom = UDim.new(0, 4)
        sp.PaddingLeft = UDim.new(0, 8); sp.PaddingRight = UDim.new(0, 8) end
    -- (KHONG con UIScale: moi thanh phan da dung % + TextScaled -> tu FILL theo cua so o moi co.)

    -- show=true  -> hien PANEL inventory (kieu Nova): AN het UI game + tat 3D (nhe CPU).
    -- show=false -> AN panel: HIEN lai UI game + bat 3D -> de chong xem/choi game binh thuong.
    local function setPanel(show)
        bg.Visible = show
        showBtn.Visible = not show
        setGameUiHidden(show)
        if toggle3D then Runtime.Set3DRendering(not show) end
        -- AP LAI CAP FPS NGAY khi bat/tat 3D: mot so executor reset frame limiter luc toggle render
        -- -> FPS vot len 60 toi ~5s (cho vong FpsCap ke tiep). Ap lai tuc thi -> het nhay.
        pcall(Runtime.ApplyFpsCap)
        -- PEEK game (show=false -> bat lai 3D): chay HideTree NGAY de an than cay tuc thi, khoi cho loop 1s
        -- -> bot canh "bam hide gui thay nguyen vuon roi moi an". (Khung khua 1 nhip do 3D bat lai la khong tranh khoi.)
        if (not show) and CFG.HideTreeKeepFruit and CFG.HideTreeKeepFruit.Enabled
            and type(Runtime.doHideTreeKeepFruit) == "function" then
            task.spawn(function() pcall(Runtime.doHideTreeKeepFruit) end)
        end
    end
    hideBtn.MouseButton1Click:Connect(function() setPanel(false) end)
    showBtn.MouseButton1Click:Connect(function() setPanel(true) end)

    local function fmtMoney(v)
        v = tonumber(v); if not v then return "-" end
        if v >= 1e9 then return string.format("%.2fb", v / 1e9)
        elseif v >= 1e6 then return string.format("%.2fm", v / 1e6)
        elseif v >= 1e3 then return string.format("%.2fk", v / 1e3) end
        return tostring(math.floor(v))
    end

    -- TOI UU GUI (chong bao GUI lag + nang): CHI ghi .Text khi GIA TRI DOI -> khong re-layout
    -- moi giay. Tach doc NANG (quet workspace: dem cay/plot + pet + equip + event + username) ra
    -- moi 5 nhip cho nhe; gia tri NHE (tien/qua/fps/gio) van cap nhat moi giay. FPS thap -> nhip 2s.
    -- DAY CHI LA PHAN HIEN THI, KHONG dung toi logic mua pet / collect rainbow & gold seed.
    local function setText(label, value)
        if label and label.Text ~= value then label.Text = value end
    end
    task.spawn(function()
        local tick = 0
        local petTxt, equipTxt, expTxt, eventTxt, plantStr, userStr = "0/0", "None", "-", "None", "0 / ?", "-"
        while gui.Parent do
            -- PANEL DANG AN (chong bam Hide GUI de xem game) -> NGU cho toi khi panel hien lai:
            -- khong cap nhat label + KHONG goi getEquippedPetCounts (fire remote) -> bot churn RAM/CPU
            -- luc peek. (Earned van dung: delta tien cong don khi panel hien lai, chi gop thanh 1 nhip.)
            while gui.Parent and not bg.Visible do
                task.wait(2)
            end
            if not gui.Parent then break end
            tick = tick + 1

            -- ===== GIA TRI NANG: cap nhat moi 5 nhip (~5s) cho nhe CPU =====
            if tick == 1 or tick % 5 == 0 then
                local okp, counts, total = pcall(function()
                    local c, t = getEquippedPetCounts(); return c, t
                end)
                local maxEq = getMaxEquippedPets()
                if okp and type(counts) == "table" then
                    local parts = {}
                    for name, n in pairs(counts) do parts[#parts + 1] = tostring(name) .. " x" .. tostring(n) end
                    equipTxt = (#parts > 0) and table.concat(parts, ", ") or "None"
                    petTxt = tostring(total or 0) .. "/" .. tostring(maxEq or 0)
                else
                    equipTxt = "None"; petTxt = "0/" .. tostring(maxEq or 0)
                end
                local owned = getOwnedExpansions()
                local maxExp
                pcall(function() if type(ExpansionPrices) == "table" and #ExpansionPrices > 0 then maxExp = #ExpansionPrices end end)
                expTxt = maxExp and (tostring(owned) .. "/" .. tostring(maxExp)) or tostring(owned)

                local plantTotal = 0
                local plot = getPlot()
                local pf = plot and plot:FindFirstChild("Plants")
                if pf then for _, m in ipairs(pf:GetChildren()) do if m:IsA("Model") then plantTotal = plantTotal + 1 end end end
                local totalPlots = tonumber(CFG.TotalPlots) or 0
                if totalPlots <= 0 then totalPlots = countVisiblePlantAreas() end
                plantStr = plantTotal .. " / " .. (totalPlots > 0 and tostring(totalPlots) or "?")

                eventTxt = (Runtime.GetMoonTimersText and Runtime.GetMoonTimersText()) or "None"
                userStr = getAccountName()

                -- So qua CHIN ngoai vuon tu DATA (TrackedPlants) - de biet "collect cham" la do HET qua
                -- chin hay do khong lay duoc data. Stat cu >3s (vong data dang ban/che do prompt)
                -- -> tu quet lai (chi doc bang data, khong instance/remote -> nhe).
                if Runtime.GardenTrackerReady and Runtime.ScanHarvestTargets
                    and (not State.HarvestStat or (os.clock() - (State.HarvestStat.At or 0)) > 3) then
                    pcall(Runtime.ScanHarvestTargets, true, true)   -- statsOnly: GUI chi DEM, khong build mang -> 0 cap phat (dot 3)
                end
            end

            -- ===== GIA TRI NHE: cap nhat moi giay =====
            local ratio, fruitCount, fruitMax = getFruitFill()
            local rt = math.max(math.floor(os.clock() - (Runtime.StartedAt or os.clock())), 0)
            local rtStr = ("%02d:%02d:%02d"):format(math.floor(rt / 3600), math.floor((rt % 3600) / 60), rt % 60)
            -- FPS thật của Roblox (FpsMonitor đo qua RenderStepped/Heartbeat -> State.Fps). Chưa đo được -> "-".
            local fpsTxt = State.Fps and (tostring(math.floor(State.Fps + 0.5)) .. " fps") or tostring(State.LastFps or "-")
            -- Hien TRANG THAI CAP ngay canh FPS: "cap=7" = dang ep dung muc; "cap FAIL..." = executor
            -- khong co setfpscap (ly do FPS Cap=7 ma van thay 60 - khong phai loi config).
            if State.FpsCapStatus then
                fpsTxt = fpsTxt .. "  [" .. tostring(State.FpsCapStatus) .. "]"
            end
            -- RAM LUA (dot 3 - MemWatch do): heap Lua cua SCRIPT. So nay THAP ma RAM process van cao
            -- -> RAM no phia ENGINE (instance/texture) -> bat "Nuke All" / HideTreeKeepFruit.DestroyFruitToo.
            if State.LuaHeapMB then
                fpsTxt = fpsTxt .. ("  Lua %dMB"):format(math.floor(State.LuaHeapMB + 0.5))
            end

            -- THONG KE TIEN KIEM/GIO (yeu cau cua chong): cong don cac lan tien TANG (ban qua...)
            -- vao Earned - bo qua luc TIEU tien (mua pet/seed) de khong bi am. Trung binh = Earned/gio chay.
            -- Chi bat dau sau khi data vuon ve (GardenDataReady, fallback 60s) de khoi dinh cu nhay
            -- tien tu 0 -> so that luc load data. Luu tren Runtime -> GUI recover khong mat so lieu.
            local money = tonumber(getSheckles())
            local ms = Runtime.MoneyStat
            if not ms then
                if money and (Runtime.GardenDataReady or rt > 60) then
                    ms = { StartAt = os.clock(), Last = money, Earned = 0 }
                    Runtime.MoneyStat = ms
                end
            elseif money then
                local d = money - (ms.Last or money)
                if d > 0 then ms.Earned = ms.Earned + d end
                ms.Last = money
            end
            local earnTxt = "-"
            if ms then
                local el = os.clock() - ms.StartAt
                earnTxt = fmtMoney(ms.Earned)
                -- chay du 2 phut moi hien X/h (som qua thi so trung binh nhay loan chua co nghia)
                if el >= 120 then earnTxt = earnTxt .. "  (" .. fmtMoney(ms.Earned / (el / 3600)) .. "/h)" end
            end

            setText(vUser,  "\u{1F464} Username: " .. tostring(userStr or "-"))
            setText(vTask,  "\u{1F4CB} " .. tostring(State.LastAction or "-"))
            setText(vMoney, "\u{1F4B0} Sheckles: " .. fmtMoney(money))
            setText(vEarn,  "\u{1F4B5} Earned: " .. earnTxt)
            setText(vPlant, "\u{1F331} Planted: " .. plantStr)
            setText(vFruit, "\u{1F34E} Fruits: " .. (fruitCount and (tostring(fruitCount) .. " / " .. tostring(fruitMax)) or "-"))
            -- Ripe = qua CHIN cho hai / TONG qua ngoai vuon (data); +N cay = cay 1-lan da lon cho hai;
            -- (N ket) = muc tieu ban >=2 lan van con (favorite/server tu choi) -> ly do Ripe khong ve 0.
            local hs = State.HarvestStat
            local harvTxt = "-"
            if hs then
                harvTxt = tostring(hs.Ripe or 0) .. " chin / " .. tostring(hs.Total or 0) .. " qua"
                if (hs.Single or 0) > 0 then harvTxt = harvTxt .. " +" .. tostring(hs.Single) .. " cay" end
                if (hs.Held or 0) > 0 then harvTxt = harvTxt .. " [giu " .. tostring(hs.Held) .. "]" end
                if (hs.Stuck or 0) > 0 then harvTxt = harvTxt .. " (" .. tostring(hs.Stuck) .. " ket)" end
            end
            setText(vHarv,  "\u{1F34F} Ripe: " .. harvTxt)
            setText(vPets,  "\u{1F43E} Active Pets: " .. petTxt)
            setText(vExp,   "\u{1F3E1} Plot Expansions: " .. expTxt)
            -- (thay dong "Events / du doan thoi tiet" bang LIST fruit dang giu - scroll duoc)
            if type(Runtime.UpdateHeldFruitPanel) == "function" then pcall(Runtime.UpdateHeldFruitPanel) end
            setText(vEquip, "\u{1F415} Equipped: " .. equipTxt)
            setText(vFps,   "\u{1F4C8} FPS: " .. fpsTxt)
            if vKill then
                setText(vKill, "\u{2694} KillCtrl: " .. tostring(State.KillCtrlStatus or "dang cho load..."))
            end
            setText(vTime,  "\u{23F0} Time: " .. rtStr)

            -- Nhịp GUI theo Dashboard.RefreshRate (trước hardcode 1s, key bị chết): sàn 1s giữ
            -- hành vi cũ (default 0.5 không làm GUI chạy DÀY hơn); LowFps -> nhân đôi như cũ.
            local rd = math.max(
                tonumber(CFG.Dashboard and CFG.Dashboard.RefreshRate) or 1,
                tonumber(CFG.Dashboard and CFG.Dashboard.MinRefreshRate) or 2,
                0.25
            )
            task.wait(State.LowFps and rd * 2 or rd)
        end
    end)
end

Runtime.BootDashboard = function()
    if CFG.Dashboard and CFG.Dashboard.Enabled == false then
        local cc = getgenv().ConfigsKaitun
        local com = type(cc) == "table" and type(cc.Commercial) == "table" and cc.Commercial or {}
        if com.Disable3D ~= false then
            Runtime.Set3DRendering(false)
            if not Runtime._render3DCleanupAdded then
                Runtime._render3DCleanupAdded = true
                table.insert(Runtime.Cleanups, function() Runtime.Set3DRendering(true) end)
            end
        end
        State.DashboardVisible = false
        return
    end
    Runtime.SetupCommercialGui()  -- chi con GUI kinh doanh "Thieu Nang Hub" (DA XOA GUI cu)
end

Runtime.SetupRuntimeWatchdog = function()
    local thread = task.spawn(function()
        while isAlive() do
            pcall(doAutoStartGame)

            -- GUI parent o CoreGui/gethui (khong con o PlayerGui) -> check theo REF da luu, khong tim trong
            -- PlayerGui nua (neu khong se tuong GUI mat -> tao trung lien tuc moi 8s). Mat ref/parent -> recover.
            local enabled = CFG.Dashboard and CFG.Dashboard.Enabled ~= false
            local guiAlive = Runtime.CommercialGui ~= nil and Runtime.CommercialGui.Parent ~= nil
            if enabled and not guiAlive then
                Runtime.SafeBoot("DashboardRecover", Runtime.BootDashboard)
            end

            local aliveTasks = 0
            local errorTasks = 0
            for _, status in pairs(Runtime.TaskStatus) do
                if status.LastRun then
                    aliveTasks = aliveTasks + 1
                end
                if status.LastErr then
                    errorTasks = errorTasks + 1
                end
            end
            State.LastWatchdog = os.date("%H:%M:%S") .. (" tasks=%s err=%s"):format(tostring(aliveTasks), tostring(errorTasks))

            local delay = CFG.LowFpsMode and tonumber(CFG.LowFpsMode.WatchdogDelay) or 8
            if not waitAlive(delay or 8) then
                break
            end
        end
    end)
    table.insert(Runtime.Tasks, thread)
end

-- BOOT CLEANUP SỚM + TUẦN TỰ (chồng yêu cầu): xóa map -> fps boost -> client light chạy LẦN LƯỢT cách nhau
-- ~0.5s, NGAY đầu (trước khi map/data stream nạp đầy RAM + trước các loop farm nặng). KHÔNG để cách 60s.
-- Đúng ý "xoa1() wait(0.5) xoa2() wait(0.5) chạy trước tiên". Đổi CFG.BootCleanupGap để chỉnh khoảng cách.
Runtime.BootEarlyCleanup = function()
    local gap = math.max(tonumber(CFG.BootCleanupGap) or 0.5, 0)
    Runtime.SafeBoot("MapCleanup", Runtime.SetupMapCleanup)   -- xóa map TRƯỚC TIÊN (data chưa nạp đầy)
    if Runtime.MapCleanupNeedsInitialWait then
        local maxWait = CFG["Nuke All"] == true
            and math.max(tonumber(CFG.MapCleanup and CFG.MapCleanup.NukeStartDelay) or 6, 1) + 30
            or math.max(tonumber(CFG.MapCleanup and CFG.MapCleanup.StartDelay) or 3, 1) + 15
        local deadline = os.clock() + maxWait
        while isAlive() and not Runtime.MapCleanupInitialDone and os.clock() < deadline do
            if not waitAlive(0.25) then return end
        end
    end
    if not waitAlive(gap) then return end
    Runtime.SafeBoot("FpsBoost", applyFpsBoost)               -- mute audio + tắt hiệu ứng nặng
    -- FPS BOOST XONG -> mo cong cho farm task nang (AutoPlant/Trim) bat dau (chong yeu cau: fps boot truoc).
    Runtime.FpsBootDone = true
    Runtime.FpsBootDoneAt = os.clock()
    if not waitAlive(gap) then return end
    Runtime.SafeBoot("ClientLight", applyClientLight)         -- tắt sáng/bóng cho nhẹ FPS
end
Runtime.BootStartup = function()
    Runtime.BootEarlyCleanup()
    Runtime.SafeBoot("CameraStable", Runtime.ApplyCameraStable)   -- khoa zoom camera -> het "bay goc nhin xa" khi tween seed
    Runtime.SafeBoot("FpsMonitor", Runtime.SetupFpsMonitor)
    Runtime.SafeBoot("AutoStartGame", doAutoStartGame)
    Runtime.SafeBoot("NightNotifier", setupNightNotifier)
    -- GardenTracker boot SOM (khong phu thuoc AutoCollect bat/tat) -> nhan SyncAllGardens som ->
    -- Runtime.GardenDataReady bat dung luc -> AutoPlant/Trim duoc mo cong dung thoi diem.
    Runtime.SafeBoot("GardenTracker", Runtime.SetupGardenTracker)
    -- PromptRegistry boot SOM (sau khi map cleanup xong -> workspace da gon): seed set prompt 1 lan
    -- de luc event claim seed KHONG phai quet GetDescendants -> het dung hinh luc event.
    Runtime.SafeBoot("PromptRegistry", Runtime.SetupPromptRegistry)
    Runtime.SafeBoot("InventoryWatcher", setupInventoryWatcher)
    Runtime.SafeBoot("AntiPush", Runtime.SetupAntiPush)
    Runtime.SafeBoot("CharacterStrip", Runtime.SetupCharacterStrip)   -- dot 4: lot phu kien nguoi khac -> ha RAM
    Runtime.SafeBoot("PlantFullWatcher", Runtime.SetupPlantFullWatcher)
    Runtime.SafeBoot("ValuableWatcher", doValuableWatcher)
    Runtime.SafeBoot("WildPetTameWatcher", Runtime.SetupWildPetTameWatcher)
    Runtime.SafeBoot("RuntimeWatchdog", Runtime.SetupRuntimeWatchdog)
    table.insert(Runtime.Cleanups, Runtime.clearEspHighlights)
    table.insert(Runtime.Cleanups, restoreClientLight)
end
-- HA RENDER NGAY LUC VAO (dot 18 - chong: "vua vao 1100-1200MB, muon 700-800 nhu emulator dien thoai"):
-- applyFpsBoost that su chi chay SAU MapCleanup + gap (~vai giay) -> luc do texture/mesh da load het =
-- peak RAM. Day len TRUOC boot sequence: chi la SETTINGS render (QualityLevel1/MeshLOD thap nhat/tat
-- shadow/voxel lighting) + fps cap -> engine cap phat texture/mesh o muc THAP NHAT ngay tu dau, cat peak.
-- KHONG dung logic game (chi giong che do do hoa thap cua Roblox mobile). Chay dong bo, boc pcall.
Runtime.ApplyEarlyRenderLow = function()
    local c = CFG.FpsBoost
    if not (c and c.Enabled) then return end
    if type(Runtime.ApplyFpsCap) == "function" then pcall(Runtime.ApplyFpsCap) end
    pcall(function()
        UserSettings():GetService("UserGameSettings").SavedQualityLevel = Enum.SavedQualitySetting.QualityLevel1
    end)
    pcall(function()
        local r = settings().Rendering
        r.QualityLevel = Enum.QualityLevel.Level01
        if c.LowMeshDetail ~= false then r.MeshPartDetailLevel = Enum.MeshPartDetailLevel.Level04 end
    end)
    pcall(function()
        local Lighting = game:GetService("Lighting")
        Lighting.GlobalShadows = false
        Lighting.FogEnd = 1e6
        if c.ForceVoxelLighting ~= false and type(sethiddenproperty) == "function" then
            pcall(function() sethiddenproperty(Lighting, "Technology", 2) end)
        end
    end)
end

-- Boot GUI dong bo truoc tat ca cleanup/loopTask de execute xong la thay GUI ngay.
Runtime.SafeBoot("EarlyRenderLow", Runtime.ApplyEarlyRenderLow)   -- ha do hoa NGAY -> cat peak RAM luc vao
Runtime.SafeBoot("Dashboard", Runtime.BootDashboard)
table.insert(Runtime.Tasks, task.spawn(Runtime.BootStartup))
table.insert(Runtime.Tasks, task.spawn(Runtime.BootSequencer))   -- dot 5: dieu phoi "chay tung flow" (tha task theo wave)

log("Khởi động. Sheckles hiện tại:", tostring(getSheckles()))

loopTask("AutoStartGame", doAutoStartGame, function() return (CFG.AutoStartGame and CFG.AutoStartGame.Delay) or 2 end)
loopTask("AutoBuySeed",  Runtime.doAutoBuySeed,  function() return ((CFG.AutoBuySeed and CFG.AutoBuySeed.Delay) or 0.35) + (tonumber(CFG.AutoBuySeed and CFG.AutoBuySeed.LoopGap) or 3) end)
loopTask("AutoPlant",    Runtime.doAutoPlant,    function() return 2 end)
loopTask("AutoShovelReplace", Runtime.doAutoShovelReplace, function() return (CFG.AutoShovelReplace and CFG.AutoShovelReplace.Delay) or 5 end)
loopTask("AutoWater",    doAutoWater,    function() return (CFG.AutoWater and CFG.AutoWater.Delay) or 2 end)
loopTask("AutoSprinkler",doAutoSprinkler,function() return ((CFG.AutoSprinkler and CFG.AutoSprinkler.Delay) or 0.5) + 2 end)
-- GEAR FX KILL: sweep sprinkler visual + FX tuoi con sot (rat nhe: chi duyet children 2 folder)
loopTask("GearFxKill", Runtime.DoGearSprinklerSweep, function() return tonumber(CFG.GearFxKill and CFG.GearFxKill.Delay) or 5 end)
loopTask("AutoBuyGear",  Runtime.doAutoBuyGear,  function() return ((CFG.AutoBuyGear and CFG.AutoBuyGear.Delay) or 0.5) + 3 end)
loopTask("AutoBuyCrate", Runtime.doAutoBuyCrate, function() return ((CFG.AutoBuyCrate and CFG.AutoBuyCrate.Delay) or 0.5) + 5 end)
loopTask("ClientLight", applyClientLight, function() return (CFG.ClientLight and CFG.ClientLight.Delay) or 10 end)
loopTask("FpsCap", Runtime.ApplyFpsCap, function() return (CFG.FpsBoost and CFG.FpsBoost.CapRefreshDelay) or 5 end)
loopTask("AutoEquipGear",Runtime.doAutoEquipGear,function() return 10 end)
loopTask("AutoCollect",  Runtime.doAutoCollect,  function()
    -- NHỊP THÍCH ỨNG: vòng vừa rồi còn hái được quả -> lặp NGAY (ContinuousDelay ~0.1s) cho LIÊN TỤC,
    -- không "roẹt rồi ngắt". Hết quả -> nghỉ Delay đầy đủ cho nhẹ. Quả mới chín có cache bắt ngay.
    local c = CFG.AutoCollect or {}
    if (tonumber(State.LastCollectCount) or 0) > 0 then
        local d = tonumber(c.ContinuousDelay) or 0.1
        -- FPS THAP/nhieu tab: gian nhip hai-lien-tuc ra chut (van hai HET, cham hon vai %) -> khong
        -- build+sort danh sach qua 20 lan/giay luc may dang duoi -> het nghen CPU (dot 2).
        if State.CriticalFps then return math.max(d, 0.35) end
        if State.LowFps then return math.max(d, 0.2) end
        return d
    end
    return math.max(tonumber(c.Delay) or 1, tonumber(c.IdleDelay) or 0.5)
end)
-- ============================================================
-- MOON TIMER (port từ moon_event_timer.lua chồng đã test) -> dùng để DYNAMIC SCAN:
-- chỉ quét AutoCollectDrops nhanh khi sắp/đang đêm đặc biệt; xa event thì quét chậm cho nhẹ FPS.
-- Nguồn: ReplicatedStorage.SharedModules.TimeCycleData (đã xác nhận trong source).
-- ============================================================
Runtime.MoonReady = nil  -- nil=chưa thử, false=fail, true=ok
Runtime.MoonData = nil
Runtime.MoonCache = { Start = nil, End = nil, At = 0 }

local function moonPickWeather(nightPhase, seed)
    -- Y HỆT moon_event_timer.pickMoon: Random.new(seed) + duyệt Weathers theo pairs.
    local rng = Random.new(seed)
    local total = 0
    for _, w in pairs(nightPhase.Weathers) do total = total + (w.Chance or 0) end
    if total <= 0 then return "Moon" end
    local roll = rng:NextNumber() * total
    local acc = 0
    for name, w in pairs(nightPhase.Weathers) do
        acc = acc + (w.Chance or 0)
        if roll <= acc then return name end
    end
    for name in pairs(nightPhase.Weathers) do return name end
    return "Moon"
end

Runtime.MoonInit = function()
    if Runtime.MoonReady ~= nil then return Runtime.MoonReady end
    Runtime.MoonReady = false
    local shared = ReplicatedStorage:FindFirstChild("SharedModules")
    local mod = shared and shared:FindFirstChild("TimeCycleData")
    if not mod then return false end
    local ok, data = pcall(require, mod)
    if not ok or type(data) ~= "table" or type(data.Data) ~= "table" then
        logw("MoonTimer: require TimeCycleData that bai")
        return false
    end
    local phases = {}
    for name, d in pairs(data.Data) do
        phases[#phases + 1] = { Name = name, Weathers = d.Weathers, Duration = d.Lasts, Order = d.StartOrder }
    end
    table.sort(phases, function(a, b) return (a.Order or 0) < (b.Order or 0) end)
    local cycleLen = 0
    for _, p in ipairs(phases) do cycleLen = cycleLen + (tonumber(p.Duration) or 0) end
    if cycleLen <= 0 then cycleLen = 600 end
    local nightIndex, nightPhase
    for i, p in ipairs(phases) do
        if p.Name == "Night" then nightIndex = i; nightPhase = p end
    end
    if not nightPhase then return false end
    -- Calibrate offset: unix = serverTime + offset (giống moon_event_timer).
    local samples = {}
    for _ = 1, 5 do
        local t1 = os.time()
        local s  = workspace:GetServerTimeNow()
        local t2 = os.time()
        if t1 == t2 then samples[#samples + 1] = t1 - s end
        task.wait(0.05)
    end
    local offset
    if #samples > 0 then
        local sum = 0
        for _, v in ipairs(samples) do sum = sum + v end
        offset = math.round(sum / #samples)
    else
        offset = math.round(os.time() - workspace:GetServerTimeNow())
    end
    Runtime.MoonData = {
        phases = phases, cycleLen = cycleLen,
        nightIndex = nightIndex, nightPhase = nightPhase, offset = offset,
    }
    Runtime.MoonReady = true
    actionLog("MoonTimer", "READY", "cycle=" .. tostring(cycleLen) .. "s offset=" .. tostring(offset))
    return true
end

-- Trả về (serverStart, serverEnd, moon) của đêm ĐẶC BIỆT (moon ~= "Moon") SẮP TỚI gần nhất.
Runtime.ComputeNextSpecialMoon = function()
    if not Runtime.MoonInit() then return nil end
    local md = Runtime.MoonData
    local now = workspace:GetServerTimeNow()
    local activePhase = workspace:GetAttribute("ActivePhase")
    local phaseEnd    = workspace:GetAttribute("PhaseDuration")
    if not (activePhase and phaseEnd) then return nil end
    local ci
    for i, p in ipairs(md.phases) do
        if p.Name == activePhase then ci = i end
    end
    if not ci then return nil end
    local function cycleNumAt(T) return math.floor((T + md.offset) / md.cycleLen) end

    local t = phaseEnd
    local idx = ci
    local guard = 0
    while guard < 500 do
        guard = guard + 1
        idx = idx + 1
        if idx > #md.phases then idx = 1 end
        local p = md.phases[idx]
        local startT = t
        if p.Name == "Night" then
            local moon = moonPickWeather(md.nightPhase, cycleNumAt(startT) * 1000 + md.nightIndex)
            if moon ~= "Moon" and startT > now then
                return startT, startT + (tonumber(p.Duration) or 120), moon
            end
        end
        t = t + (tonumber(p.Duration) or 0)
    end
    return nil
end

-- Giây còn lại tới đêm đặc biệt gần nhất (cache 30s để khỏi tính lại mỗi vòng). nil = không tính được.
Runtime.SecondsUntilSpecialMoon = function()
    if Runtime.MoonReady == false then return nil end
    local okNow, now = pcall(function() return workspace:GetServerTimeNow() end)
    if not okNow or type(now) ~= "number" then return nil end
    local cache = Runtime.MoonCache
    if (not cache.Start) or (os.clock() - cache.At > 30) or (cache.End and now > cache.End) then
        local s, e = Runtime.ComputeNextSpecialMoon()
        cache.Start, cache.End, cache.At = s, e, os.clock()
    end
    if not cache.Start then return nil end
    return cache.Start - now
end

-- Tìm serverTime BẮT ĐẦU đêm gần nhất cho TỪNG loại moon đặc biệt (Goldmoon / Rainbow Moon / Bloodmoon).
Runtime.ComputeMoonStarts = function()
    if not Runtime.MoonInit() then return nil end
    local md = Runtime.MoonData
    local now = workspace:GetServerTimeNow()
    local activePhase = workspace:GetAttribute("ActivePhase")
    local phaseEnd    = workspace:GetAttribute("PhaseDuration")
    if not (activePhase and phaseEnd) then return nil end
    local ci
    for i, p in ipairs(md.phases) do
        if p.Name == activePhase then ci = i end
    end
    if not ci then return nil end
    local function cycleNumAt(T) return math.floor((T + md.offset) / md.cycleLen) end
    -- Mega Moon = đêm spawn Mega Seed (TimeCycleData: Night.Weathers["Mega Moon"], Chance 2%). Thêm để dự đoán.
    local want = { Goldmoon = true, ["Rainbow Moon"] = true, Bloodmoon = true, ["Mega Moon"] = true }
    local found, foundCount = {}, 0
    local t = phaseEnd
    local idx = ci
    local guard = 0
    while guard < 2000 and foundCount < 4 do
        guard = guard + 1
        idx = idx + 1
        if idx > #md.phases then idx = 1 end
        local p = md.phases[idx]
        local startT = t
        if p.Name == "Night" then
            local moon = moonPickWeather(md.nightPhase, cycleNumAt(startT) * 1000 + md.nightIndex)
            if want[moon] and not found[moon] and startT > now then
                found[moon] = startT
                foundCount = foundCount + 1
            end
        end
        t = t + (tonumber(p.Duration) or 0)
    end
    return found
end

-- Bảng giây còn lại tới TỪNG loại moon đặc biệt (cache 15s). nil = không tính được.
Runtime.MoonTimersCache = { starts = nil, At = 0 }
Runtime.GetMoonTimers = function()
    if Runtime.MoonReady == false then return nil end
    if not Runtime.MoonInit() then return nil end
    local okNow, now = pcall(function() return workspace:GetServerTimeNow() end)
    if not okNow or type(now) ~= "number" then return nil end
    local cache = Runtime.MoonTimersCache
    local need = (not cache.starts) or (os.clock() - cache.At > 15)
    if not need then
        for _, s in pairs(cache.starts) do
            if now > s then need = true break end
        end
    end
    if need then
        cache.starts = Runtime.ComputeMoonStarts()
        cache.At = os.clock()
    end
    if not cache.starts then return nil end
    local out = {}
    for k, s in pairs(cache.starts) do out[k] = s - now end
    return out
end

-- Chuỗi gọn cho GUI: "M 8m  R 12m05s  G 4m  B 1h02m" (M=Mega, R=Rainbow, G=Gold, B=Blood). nil = chưa tính được.
Runtime.GetMoonTimersText = function()
    local mt = Runtime.GetMoonTimers()
    if not mt then return nil end
    local function f(s)
        s = math.max(0, math.floor(s + 0.5))
        if s >= 3600 then return string.format("%dh%02dm", math.floor(s / 3600), math.floor((s % 3600) / 60)) end
        if s >= 60 then return string.format("%dm%02ds", math.floor(s / 60), s % 60) end
        return s .. "s"
    end
    local parts = {}
    local m = mt["Mega Moon"];    if m and m > 0 then parts[#parts + 1] = "M " .. f(m) end
    local r = mt["Rainbow Moon"]; if r and r > 0 then parts[#parts + 1] = "R " .. f(r) end
    local g = mt.Goldmoon;        if g and g > 0 then parts[#parts + 1] = "G " .. f(g) end
    local b = mt.Bloodmoon;       if b and b > 0 then parts[#parts + 1] = "B " .. f(b) end
    if #parts == 0 then return nil end
    return table.concat(parts, "  ")
end

-- getDelay động cho AutoCollectDrops: nhanh khi sắp/đang event, chậm khi xa event.
local function autoCollectDropsDelay()
    local c = CFG.AutoCollectDrops or {}
    local fast = tonumber(c.Delay) or 0.1
    if c.EventDynamicScan == false then return fast end
    local idle = tonumber(c.IdleScanDelay) or 0.35   -- giam 1.0 -> 0.35: detect seed nhanh hon (chong yeu cau)
    -- 1) Có seed pack spawn THẬT ngay bây giờ (source chắc chắn) -> TURBO (nhanh nhất) để claim/teleport dồn dập.
    if Runtime.GetPrioritySeedSpawnLabel() then
        return math.max(tonumber(c.EventActiveDelay) or fast, 0)
    end
    -- 2) Đang đêm -> quét nhanh (event seed xảy ra ban đêm).
    if isNight() then return fast end
    -- 3) Sắp tới đêm đặc biệt trong PreEventWindow -> quét nhanh đón đầu.
    local remain = Runtime.SecondsUntilSpecialMoon()
    if remain and remain <= (tonumber(c.PreEventWindow) or 240) then return fast end
    -- 4) Xa event -> quét chậm cho nhẹ FPS.
    return idle
end

loopTask("AutoCollectDrops", Runtime.doAutoCollectDrops, autoCollectDropsDelay)
loopTask("ValuableWatcher", doValuableWatcher, function() return (CFG.ValuableWatcher and CFG.ValuableWatcher.Delay) or 2 end)
loopTask("AutoSell",     function()
    -- COOLDOWN dùng CHUNG: chỉ bán định kỳ khi đã đủ Delay tính TỪ LẦN BÁN GẦN NHẤT (State.LastSellAt),
    -- kể cả lần bán do ĐẦY TÚI (sau thu hoạch). -> bán đầy túi xong là RESET bộ đếm, timer không bán
    -- chồng 1 túi gần rỗng nữa. Acc mới chưa bán bao giờ (LastSellAt=nil) -> bán luôn.
    local s = CFG.AutoSell or {}
    local minD = tonumber(s.Delay) or 30
    local last = tonumber(State.LastSellAt)
    if last and (os.clock() - last) < minD then
        actionLog("AutoSell", "COOLDOWN", string.format("%.0fs/%.0fs", os.clock() - last, minD))
        return
    end
    runSellSafe("timer")
end, function()
    -- Random nhịp KIỂM TRA trong [Delay, DelayMax]. Acc mới chậm/không bao giờ đầy 100 quả
    -- vẫn được bán định kỳ; còn đầy túi thì doSellWhenFull/InventoryWatcher bán NGAY (không đợi).
    local s = CFG.AutoSell or {}
    local minD = tonumber(s.Delay) or 30
    local maxD = tonumber(s.DelayMax) or minD
    if maxD > minD then
        return minD + math.random() * (maxD - minD)
    end
    return minD
end)
loopTask("AutoSellFull", doSellWhenFull, function() return (CFG.AutoSell and CFG.AutoSell.FullCheckDelay) or 1 end)
loopTask("AntiSteal",    Runtime.doAntiSteal,    function() return (CFG.AntiSteal and CFG.AntiSteal.Delay) or 0.35 end)
loopTask("AutoHatchEgg", Runtime.doAutoHatchEgg, function() return (CFG.AutoHatchEgg and CFG.AutoHatchEgg.Delay) or 0.5 end)
loopTask("AutoOpenCrate",Runtime.doAutoOpenCrate,function() return ((CFG.AutoOpenCrate and CFG.AutoOpenCrate.Delay) or 0.5) + 2 end)
loopTask("AutoOpenSeedPack", Runtime.doAutoOpenSeedPack, function() return ((CFG.AutoOpenSeedPack and CFG.AutoOpenSeedPack.Delay) or 0.5) + 2 end)
loopTask("AutoClaimMailbox", Runtime.doAutoClaimMailbox, function() return (CFG.AutoClaimMailbox and CFG.AutoClaimMailbox.Delay) or 60 end)
loopTask("AutoMailSeeds", Runtime.DoAutoMailSeeds, function()
    local s = CFG.AutoMailSeeds or CFG.AutoMailRainbow or {}
    return tonumber(s.Delay) or 30
end)
loopTask("AutoMailPets", Runtime.DoAutoMailPets, function() return (CFG.AutoMailPets and CFG.AutoMailPets.Delay) or 30 end)
loopTask("AutoMailFruits", Runtime.DoAutoMailFruits, function() return (CFG.AutoMailFruits and CFG.AutoMailFruits.Delay) or 30 end)
loopTask("AutoMailGear", Runtime.DoAutoMailGear, function() return (CFG.AutoMailGear and CFG.AutoMailGear.Delay) or 30 end)
loopTask("LockFruits", Runtime.DoLockFavoriteFruits, function() return (CFG.LockFruits and CFG.LockFruits.Delay) or 5 end)
loopTask("UnfavoriteFruits", Runtime.DoUnfavoriteFruits, function() return (CFG.UnfavoriteFruits and CFG.UnfavoriteFruits.Delay) or 3 end)
loopTask("RainbowReport", Runtime.DoRainbowAccountReport, function() return (CFG.RainbowAccountReport and CFG.RainbowAccountReport.Interval) or 60 end)
loopTask("AutoEquipPet", Runtime.doAutoEquipPet, function() return (CFG.AutoEquipPet and CFG.AutoEquipPet.Delay) or 5 end)
loopTask("AutoSnapPets", doAutoSnapPets, function() return (CFG.AutoSnapPets and CFG.AutoSnapPets.Delay) or 15 end)
loopTask("AutoSpendSkill", doAutoSpendSkill, function() return ((CFG.AutoSpendSkill and CFG.AutoSpendSkill.Delay) or 0.3) + 4 end)
loopTask("AutoExpandGarden", Runtime.doAutoExpandGarden, function() return (CFG.AutoExpandGarden and CFG.AutoExpandGarden.Delay) or 10 end)
loopTask("AutoTier", Runtime.doAutoTier, function() return (CFG.AutoTier and CFG.AutoTier.Delay) or 45 end)
loopTask("AutoPurchasePetSlot", doAutoPurchasePetSlot, function() return (CFG.AutoPurchasePetSlot and CFG.AutoPurchasePetSlot.Delay) or 15 end)
loopTask("AutoTameWildPet", doAutoTameWildPet, function() return (CFG.AutoTameWildPet and CFG.AutoTameWildPet.Delay) or 2 end)
loopTask("ESP",          Runtime.doEsp,          function()
    local c = CFG.ESP
    if not (c and (c.ReadyPlants or c.Players)) then return 30 end
    return tonumber(c.RefreshRate) or 1
end)
loopTask("AutoRedeemCode", Runtime.doAutoRedeemCode, function() return 30 end)
loopTask("TrimToQuota", Runtime.doTrimToQuota, function() return (CFG.TrimToQuota and CFG.TrimToQuota.Delay) or 8 end)
loopTask("HideTreeKeepFruit", Runtime.doHideTreeKeepFruit, function() return (CFG.HideTreeKeepFruit and CFG.HideTreeKeepFruit.Delay) or 1 end)

-- ============================================================
-- MEM JANITOR (chong RAM NO khi farm lau): moi 2 phut don cac bang dedup/cache NOI BO cua script
-- (thu pham RAM tang dan). CHI dung DATA cua script, KHONG destroy/dung vat the game -> an toan
-- tuyet doi, khong anh huong farm. Khong co yield ben trong -> khong bi race voi task khac.
-- ============================================================
Runtime.DoMemJanitor = function()
    local nowc = os.clock()
    -- 1) dedup data-harvest: key cu > 300s (dedup chi can vai giay) -> xoa het, khoi cho toi nguong 20000
    local fired = Runtime.DataHarvestFiredAt
    if type(fired) == "table" then
        local removed = 0
        for k, t in pairs(fired) do
            if (nowc - (tonumber(t) or 0)) > 300 then
                fired[k] = nil
                removed = removed + 1
            end
        end
        if removed > 0 then
            Runtime.DataHarvestFiredCount = math.max((Runtime.DataHarvestFiredCount or 0) - removed, 0)
        end
    end
    -- 1b) backoff miss theo key da bi don o (1) -> don theo; moc tuoi qua khong duoc dung >10 phut
    -- (qua da hai/xoa khoi TrackedPlants) -> xoa (chong 2 bang moi cua data-harvest phinh dan)
    if type(Runtime.DataHarvestMiss) == "table" and type(fired) == "table" then
        for k in pairs(Runtime.DataHarvestMiss) do
            if fired[k] == nil then Runtime.DataHarvestMiss[k] = nil end
        end
    end
    if type(Runtime.FruitAgeBase) == "table" then
        for k, b in pairs(Runtime.FruitAgeBase) do
            local seen = (type(b) == "table" and tonumber(b.s)) or 0
            if (nowc - seen) > 600 then Runtime.FruitAgeBase[k] = nil end
        end
    end
    -- 2) cooldown danh trom: moc cu > 10 phut (nguoi choi thuong da roi server) -> xoa
    for uid, t in pairs(AntiStealCooldown) do
        if (nowc - (tonumber(t) or 0)) > 600 then AntiStealCooldown[uid] = nil end
    end
    -- 2b) blocklist pet equip loi da het han -> xoa
    if type(Runtime.PetEquipBlocked) == "table" then
        for k, t in pairs(Runtime.PetEquipBlocked) do
            if (tonumber(t) or 0) < nowc then Runtime.PetEquipBlocked[k] = nil end
        end
    end
    -- 3) quet vet harvest cache: prompt da roi workspace ma signal removed lo khong ban -> xoa han
    for p in pairs(Runtime.HarvestPrompts) do
        local ok, alive = pcall(function() return p:IsDescendantOf(workspace) end)
        if not ok or not alive then
            Runtime.HarvestPrompts[p] = nil
            Runtime.HarvestRipeAt[p] = nil
            Runtime.HarvestScore[p] = nil
        end
    end
    -- 4) prompt registry (blast): prompt chet con sot -> xoa
    if type(Runtime.PromptSet) == "table" then
        for p in pairs(Runtime.PromptSet) do
            local ok, alive = pcall(function() return p:IsDescendantOf(workspace) end)
            if not ok or not alive then Runtime.PromptSet[p] = nil end
        end
    end
    -- 5) auto-start da xong -> bo bang GUI da an (giu ref ScreenGui vo ich)
    if Runtime.AutoStartCompleted and type(Runtime.AutoStartHiddenGuis) == "table"
        and next(Runtime.AutoStartHiddenGuis) ~= nil then
        table.clear(Runtime.AutoStartHiddenGuis)
    end
    -- 6) bang favorite fruit qua to (id qua cu da ban/gui tu lau) -> reset (chi ton 1 luot re-favorite)
    for _, key in ipairs({ "FruitFavorited", "FruitUnfavorited" }) do
        local t = Runtime[key]
        if type(t) == "table" then
            local n = 0
            for _ in pairs(t) do
                n = n + 1
                if n > 4000 then table.clear(t) break end
            end
        end
    end
    -- 7) Instance userdata khong nen chi dua vao weak-key: don ro key da mat Parent moi phut.
    local function pruneDeadInstanceKeys(t)
        if type(t) ~= "table" then return end
        for inst in pairs(t) do
            if typeof(inst) ~= "Instance" or inst.Parent == nil then t[inst] = nil end
        end
    end
    for _, t in ipairs({
        Runtime.HideTreeDone, Runtime.HideFruitDone, Runtime.HideTreeReadyAt,
        Runtime.ClientLightDone, Runtime.TouchPartCache,
        Runtime.ItemPromptCache, Runtime.ItemPromptMissAt,
        ClientLightOriginal.Parts, ClientLightOriginal.Effects,
    }) do
        pruneDeadInstanceKeys(t)
    end
    -- 8) CAY CULL CUA NGUOI KHAC trong ReplicatedStorage.CulledPlants (PlantCullingController:127
    -- chuyen cay xa camera vao day) -> destroy = nha RAM. AN TOAN theo source: controller tu don
    -- state khi model mat Parent (dong 167-168), reparent boc pcall. Nhan dien chu cay bang attribute
    -- UserId (PlantVisualizerController:1311; game tu so sanh kieu nay o dong 840). Attr thieu -> GIU
    -- (khong doan). Cay MINH giu nguyen de restore khi lai gan.
    if not (CFG.MapCleanup and CFG.MapCleanup.PurgeCulledPlants == false) then
        local culled = ReplicatedStorage:FindFirstChild("CulledPlants")
        if culled then
            local myUid = LocalPlayer.UserId
            local purged = 0
            for _, model in ipairs(culled:GetChildren()) do
                local uid = tonumber(model:GetAttribute("UserId"))
                if uid and uid ~= myUid then
                    if pcall(function() model:Destroy() end) then purged = purged + 1 end
                end
            end
            if purged > 0 then
                actionLog("MemJanitor", "CULLED", "xoa " .. tostring(purged) .. " cay cull nguoi khac")
            end
        end
    end
    -- 9) full GC la opt-in; mac dinh de incremental GC cua Luau tu dieu tiet.
    if CFG.ForceFullGc == true then pcall(function() collectgarbage("collect") end) end
end
-- Nhip don RAM: mac dinh 60s (dot 4: tang tiep 90->60, GC deu tay -> RAM khong kip no). Chinh bang CFG.MemJanitorDelay.
loopTask("MemJanitor", Runtime.DoMemJanitor, function() return tonumber(CFG.MemJanitorDelay) or 60 end)

-- ============================================================
-- MEM WATCH (dot 3 - "sieu toi uu RAM"): dong ho heap Lua + van xa ap suat.
-- GOC RE "RAM no nhanh": GC Luau chay theo FRAME -> cap 7-10fps = GC bi bo doi, trong khi cac vong
-- nong (AutoCollect 0.1s, Scan, blast luc event) cap phat lien tuc -> heap phinh nhanh hon toc do don.
-- Dot 3 da giam manh cap phat (pool buffer); MemWatch la lop bao ve cuoi: moi 20s
--   (1) doc heap Lua bang gcinfo()/collectgarbage("count") (CHUAN Luau - doc duoc ke ca khi executor
--       khong cho "collect") -> State.LuaHeapMB; GUI hien "Lua xxMB" canh FPS.
--       => So nay THAP ma RAM process van cao = no phia ENGINE (instance/texture) -> chinh Nuke All/
--          DestroyFruitToo, khong phai loi script.
--   (2) heap >= CFG.LuaHeapSoftMB (mac dinh 150MB) -> PurgeCaches (xoa cache DUNG LAI DUOC) + GC full.
-- ============================================================
Runtime.GetLuaHeapKB = function()
    local kb
    if type(gcinfo) == "function" then
        local ok, v = pcall(gcinfo)
        if ok then kb = v end
    end
    if type(kb) ~= "number" and type(collectgarbage) == "function" then
        pcall(function() kb = collectgarbage("count") end)
    end
    return tonumber(kb)
end
-- Xoa cache DUNG LAI DUOC (khong mat logic; chi ton 1 luot tinh lai / ban lai toi da 1 luot remote dedup).
Runtime.PurgeCaches = function()
    pcall(function()
        table.clear(Runtime.HarvestScore)         -- diem gia qua: FruitCollectScore tu tinh lai
        table.clear(Runtime.DataHarvestFiredAt)   -- dedup ban qua: xoa = ban lai 1 luot, vo hai
        table.clear(Runtime.DataHarvestMiss)
        table.clear(Runtime.FruitAgeBase)
        Runtime.DataHarvestFiredCount = 0
        Runtime.PlantAreaCache = nil
        Runtime.EqPetCache = nil
        Runtime.PetPriorityCache = nil
        Runtime.SeedLabelCache = nil
    end)
end
Runtime.DoMemWatch = function()
    local kb = Runtime.GetLuaHeapKB()
    if not kb then return end
    local mb = kb / 1024
    State.LuaHeapMB = mb
    local soft = tonumber(CFG.LuaHeapSoftMB) or 150
    if mb >= soft then
        Runtime.PurgeCaches()
        if CFG.ForceFullGc == true then pcall(function() collectgarbage("collect") end) end
        local kb2 = Runtime.GetLuaHeapKB()
        if kb2 then State.LuaHeapMB = kb2 / 1024 end
        actionLog("MemWatch", "PURGE", ("%dMB -> %dMB (soft %d)"):format(
            math.floor(mb + 0.5), math.floor((State.LuaHeapMB or mb) + 0.5), soft))
    end
end
loopTask("MemWatch", Runtime.DoMemWatch, function() return tonumber(CFG.MemWatchDelay) or 20 end)

Runtime.SetupAntiAfk()
Runtime.SetupInstantRestockBuy()
Runtime.SetupKillGameControllers()

log("Đã chạy tất cả tác vụ theo config. Chỉnh getgenv().ConfigsKaitun để bật/tắt.")
