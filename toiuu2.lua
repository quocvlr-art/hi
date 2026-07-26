--[[
	MM2 KAITUN - AUTO COIN + SEGMENTED STEP + LOW RAM

	NGUON GAME DA DOI CHIEU:
	- Players.../PlayerScripts/CoinVisualizer.lua
	  Tag "CoinVisual"; attributes CoinID, Collected, Delete, RoundEnd.
	  CoinCollected / CoinsStarted la OnClientEvent.
	- Players.../PlayerGui/MainGUI/Game/CoinBags/CoinBagContainerScript.lua
	  CoinCollected(bagId, current, maximum, ...);
	  onCoinsStarted(p11) dong 51-59: p11[bagName] ~= nil = bag dang active.
	  => CoinsStarted(activeBags) LA THAT, key theo bagName (trung bagId CoinCollected).
	- ReplicatedStorage.../Modules/CurrentRoundClient.lua
	  PlayerData[name].Role / Dead / Perk.
	- Workspace.../<player>/CharacterClient.lua
	  Callback TeleportToPart dung Character:PivotTo() va khong tu so sanh distance.
	- Players.../PlayerGui/MainGUI/Inventory/Leaderboard.lua
	  GUI con truc tiep cua PlayerGui ten chinh xac "ESP" se bi Kick.

	CHUA XAC NHAN:
	- Khong co server source movement/anti-cheat, nen KHONG co con so "tele an toan X studs".
	- Khong co path/model current map. Aggressive Map Purge chi xoa candidate co
	  Collide/Touch/Query deu false; khong tu bia ten map hay claim an toan physics.
	- Khong co remote client->server de nhat coin. Chong da test file main.lua va
	  xac nhan cach NHAT OK: coin nhat duoc la BasePart trong object "CoinContainer",
	  co TouchInterest + child "CoinVisual"; teleport = anchor rootPart roi set CFrame
	  tung buoc toi coin.CFrame. Kaitun da tich hop dung logic nay (CFG.AnchorWhile
	  Collecting + CoinStepStuds + Noclip). Day la xac nhan runtime cua chong.
	  (CoinVisualizer.lua:104 co handler function() bo qua tham so, nhung
	  CoinBagContainerScript.lua:51 dung p11 nen activeBags van la payload that.)

	SUON_TOIUU_RAM_CPU.md DA TICH HOP:
	- Scheduler trung tam, stagger, adaptive delay, profile tung task.
	- FPS cap neu executor co setfpscap/set_fps_cap.
	- Weak cache, prune dead instance, cap bang, mem watch.
	- Strip visual theo DescendantAdded; optional controller list duoc doc tu source.
]]

--====================================================================
-- 0) RE-EXECUTE GUARD
--====================================================================
local GLOBAL_KEY = "__MM2_KAITUN_SOURCE_V2"
local previous = rawget(_G, GLOBAL_KEY)
if type(previous) == "table" and type(previous.Shutdown) == "function" then
	pcall(previous.Shutdown, "re-execute")
end

--====================================================================
-- 1) SERVICES + CONFIG
--====================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
-- VirtualUser: API engine Roblox chuan de chong AFK (KHONG phai logic game trong source).
local VirtualUser = nil
pcall(function()
	VirtualUser = game:GetService("VirtualUser")
end)

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	warn("[Thieu Nang Hub] Khong tim thay Players.LocalPlayer")
	return
end

local CFG = {
	-- CHI DIEU KHIEN BANG CACH GAN CFG TAI DAY.
	-- GUI ben duoi chi hien thong ke + logs, khong co control tuong tac.
	Enabled = true,
	AutoCollect = true,
	AutoHide = true,
	AvoidMurderer = false,
	-- Khi da nhat xong (CollectionFinished) VA chi con MINH minh song (het innocent
	-- khac) -> tu teleport tung buoc ra TRUOC MAT murderer cho bi giet, ket thuc van
	-- de vao van moi nhanh. Tat = false neu chong muon o lai nup.
	SuicideWhenLastAlive = true,
	SuicideFrontStuds = 3, -- dung cach murderer bao nhieu stud phia truoc mat

	-- Heuristic runtime, KHONG phai path/current-map da xac nhan trong source:
	-- 1) luc CoinsStarted: tim mat BasePart cao nhat quanh bien X/Z CoinVisual,
	--    teleport len do, doi mot chut roi moi nhat coin;
	-- 2) khi dat dieu kien coin: quay lai diem cao do va o yen.
	-- TAT: khong nup dau round, nhat coin ngay; xong moi len safe.
	OpeningHideEnabled = false,
	OpeningHideWaitSeconds = 2.5,
	OpeningHideSearchDelay = 0.35,
	OpeningHideSearchTimeout = 8,
	OpeningHideArrivalTimeout = 8,
	HighestArrivalCushion = 3,
	HighestSearchRetrySeconds = 1,
	HighestFinalSearchMaxAttempts = 2,
	HighestFinalSearchRetrySeconds = 4,
	HighestScanBatchSize = 300,
	HighestStreamUpgradeDebounce = 0.75,
	HighestMaxUpgradeScans = 1,
	HighestCoinBoundsMargin = 90,
	HighestMinFootprint = 6,
	HighestMaxFootprint = 500,
	HighestMinUpVectorY = 0.75,
	HighestClearance = 2,
	HighestRequireAnchored = true,
	HighestInstantTeleport = true,
	HighestInstantMaxAttempts = 2,
	HighestInstantRetrySeconds = 2,
	HideAtHighestAfterCollect = true,

	-- Kaitun cong field current cua cac bag da emit de so voi CoinTarget.
	-- Source chi xac nhan current/cap tung bag, khong dat ten tong nay la pickup total.
	-- 0 = thu den khi tat ca bag da biet full, hoac heuristic het CoinVisual kha dung.
	CoinTarget = 0,
	-- Heuristic noi bo; source khong khang dinh 0 CoinVisual la da het coin.
	NoCoinGraceSeconds = 5,

	-- NHAT COIN theo dung logic main.lua chong da test hoan chinh (nhat OK):
	--  * Coin nhat duoc = BasePart trong object ten "CoinContainer", co TouchInterest
	--    (co .Touched de server nhan) + child ten "CoinVisual".
	--  * Teleport = ANCHOR rootPart roi set CFrame tien tung buoc CoinStepStuds toi
	--    thang coin.CFrame (khong cong HipHeight). Anchor de khong bi physics keo/rot.
	CoinStepStuds = 20, -- CHI dung khi DirectTeleport=false (fallback nhay tung stud)
	AnchorWhileCollecting = true, -- anchor rootPart khi collect (main.lua da test)
	CoinScanRange = 0, -- chi nhat coin trong ban kinh nay (0 = khong gioi han), main.lua MAX_DISTANCE
	-- CHONG CHON: quay ve teleport TUNG STUD (segmented CoinStepStuds) NHUNG van bat
	-- TouchNearbyCoins de vua di vua ban firetouchinterest claim ca cum.
	--   false = nhay tung buoc CoinStepStuds (mac dinh hien tai).
	--   true  = TP thang 1 phat toi coin gan nhat (khong nhay tung stud).
	DirectTeleport = false,
	-- Chot an toan cho cu nhay dau tien / khi coin gan nhat lo qua xa: > gia tri nay
	-- thi chi nhay 1 buoc DirectMaxStuds (van la 1 buoc, khong lien tuc tung stud nho).
	-- 0 = luon TP thang 1 phat bat ke xa (dung y "tp 1 phat an luon").
	DirectMaxStuds = 0,
	-- THU METHOD TWEEN: di chuyen toi coin bang TweenService (muot, di lien tuc thay
	-- vi nhay/teleport). Bat = uu tien tween; tat = ve teleport/anchor-step o tren.
	-- CHONG CHON: TAT tween -> ve teleport TUNG STUD (anchorStepToward + DirectTeleport=false).
	UseTween = true,
	TweenStudsPerSecond = 40, -- toc do tween (studs/giay); tang = nhanh hon
	TweenMaxTime = 3,         -- cap thoi gian 1 tween (giay), tranh tween qua dai khi coin xa
	-- CLAIM CA CUM (firetouchinterest): BAT SAN trong code. An toan vi da co auto-detect
	-- FastClaimBroken: executor co firetouchinterest lom (server khong nhan .Touched)
	-- -> fail 8 coin lien tiep la TU chuyen ve 100% cham that (touchCoinAndWait,
	-- logic main.lua da test OK) cho het phien. Executor xin thi claim ca cum, nhanh.
	TouchNearbyCoins = true,
	TouchNearbyRadius = 0, -- studs; 0 = khong gioi han (fire het coin, coi chung server distance-check)
	-- FAST CLAIM: BAT SAN trong code (di cung TouchNearbyCoins). Executor lom da co
	-- auto-detect FastClaimBroken keo ve cham that sau 8 coin fail -> khong can config.
	-- Muon ep 1 acc luon cham that ngay tu dau: FastClaim = false trong getgenv config.
	FastClaim = true,
	FastClaimWait = 0.05, -- nhip cho server nhan .Touched khi FastClaim (giay); 0 = khong cho
	-- UU TIEN CUM COIN: vi fire touch claim ca cum trong tam ban, nen uu tien teleport
	-- toi coin ma QUANH NO co NHIEU coin (density cao) -> tới 1 phat claim nhieu coin.
	PreferCoinClusters = true,
	ClusterRadius = 0,   -- ban kinh tinh cum; 0 = dung TouchNearbyRadius (dung tam ban)
	ClusterBonus = 8,    -- moi coin them trong cum "dang gia" bao nhieu stud (uu tien cum vs gan)
	-- Noclip: khi phase collect, ep CanCollide=false cho part nhan vat de khong bi
	-- vat can; anchor van giu khong roi. Roi collect thi tra lai CanCollide. Tat = false.
	Noclip = true,

	MoveDelay = 0.35, -- nhip tick FarmMove (giay) - GIONG main.lua DEFAULT_DELAY
	-- CHECK COIN NHANH: nhip chon/quet coin khi dang round. Nho = check nhanh hon.
	CoinScanDelay = 0.05,
	-- Bao lau rescan lai CoinContainer (giay). Nho = bat coin map moi nhanh hon.
	ContainerRescanSeconds = 1,
	ArrivalRadius = 5,
	StuckSeconds = 3,
	RetryDelay = 1.5,
	-- Cac so duoi CHI con dung cho di chuyen NUP (hide) bang Segmented Step.
	MaxStepStuds = 2,
	MaxMoveStudsPerSecond = 14,

	-- Heuristic kaitun; source khong xac nhan khoang cach an toan voi Murderer.
	SafeDistance = 75,
	PanicDistance = 50,
	-- Khi COLLECT: chi LOAI coin cach murderer duoi nguong nay (nhay sat murderer moi bo).
	-- Coin xa hon van chon binh thuong, chi bi tru diem trong SafeDistance -> uu tien coin xa.
	-- Nho hon PanicDistance nhieu de KHONG bo collect chi vi murderer quanh quan gan char.
	MurdererHardAvoid = 18,
	MaxHidePoints = 160,

	CpuSaver = true,
	LowFpsThreshold = 20,
	CriticalFpsThreshold = 10,
	Jitter = 0.08,
	TargetFPS = 10,
	-- Policy local khi dung script; SUON chi xac nhan setter, khong co getter cap.
	RestoreFPSOnShutdown = 60,

	LowRender = true,
	MuteAudio = true,
	-- OFF mac dinh: Destroy visual generic khong duoc source dam bao co the khoi phuc.
	DestroyVisualInstances = true,
	HideWorldButKeepCollision = true,
	-- Hai tier nay OFF mac dinh vi source khong co Shutdown cua controller da init.
	AutoHideGameGui = false,
	AutoKillVisualControllers = false,

	-- OFF mac dinh: local destroy visual BasePart khong hoan tac cho toi khi rejoin.
	-- Luon giu part co CanCollide/CanTouch/CanQuery; khong claim moi part con lai
	-- la vo nghia voi assembly/script vi source khong du du lieu.
	HardMapless = false,

	-- === AUTO BOX + GODLY WEBHOOK (dump: box "Summer2026Box", godly "Icecream") ===
	AutoBuyBox = false,          -- MAC DINH TAT (tieu so that). Bat khi da dien WebhookUrl.
	BoxName = "Summer2026Box",   -- id box trong Sync.MysteryBox (tu dump cua chong)
	BoxCurrency = "Shells",      -- mua bang so
	BoxPrice = 120,              -- gia box (so so) - tu anh shop
	GodlyItemName = "Icecream",  -- ten godly can bao (khop RewardedItemId, ca "IcecreamChroma")
	WebhookUrl = "",             -- URL webhook Discord (de trong = KHONG gui)
	GodlyGreenUI = true,         -- godly -> doi nen UI den thanh xanh la cay
	-- Anh thumbnail webhook embed (link chong cung cap - nguon ngoai game).
	GodlyImageUrl = "https://static.wikia.nocookie.net/murder-mystery-2/images/b/b6/Icecream_knife.png/revision/latest?cb=20260724060716",
	GodlyChromaImageUrl = "https://static.wikia.nocookie.net/murder-mystery-2/images/9/9b/C_Icecream.png/revision/latest?cb=20260724020208",

	-- === SERVER HOP khi farm cham (config chong yeu cau) ===
	AutoServerHop = false,               -- MAC DINH TAT (hop se reload game). Bat neu muon.
	HOP_WHEN_COIN_EARNED_LOWER = 200,    -- earned trong 1 chu ky < muc nay -> hop server
	TIME_TO_CHECK_COIN_EARNED = 1800,    -- chu ky kiem tra earned (giay)

	-- === AUTO CHANGE ACC (accountops.org autoswap) ===
	-- Xong TOAN BO moc quest DAILY (chi daily, khong tinh weekly) + het so mua box
	-- -> POST autoswap-complete de doi acc (tool move acc qua folder khac + tu keo
	-- acc moi vao). MAC DINH TAT (doi acc that, khong hoan tac). Bat = true khi da
	-- tao rule On-Demand tren web + dien ApiKey. Can AutoBuyBox=true de tieu het so.
	AutoChangeAcc = false,
	AutoSwapApiKey = "",        -- X-Api-Key (dat trong getgenv config, DUNG lo ra ban public)
	AutoSwapUrl = "https://accountops.org/api/accounts/autoswap-complete",
	AutoSwapUsername = "",      -- de trong = dung ten acc hien tai (LocalPlayer.Name)
	AutoSwapOptionNoGodly = 1,  -- rule On-Demand cho acc KHONG godly -> folder "no godly"
	AutoSwapOptionHaveGodly = 2,-- rule On-Demand cho acc TRUNG godly -> folder "havegodly"

	LuaHeapSoftMB = 150,
	ForceFullGC = true,
	-- _G.Cache trong source da doi chieu la cache image. Xoa mot lan luc boot.
	ClearImageCacheOnBoot = true,
	-- === TOI UU ENGINE (API engine/executor, khong phai logic game) ===
	-- Tat ve 3D hoan toan (GUI van hien). Tiet kiem CPU/GPU manh nhat. Restore khi stop.
	Disable3DRender = true,
	-- settings().Rendering.QualityLevel = Level01 (chi khi executor cho phep).
	LowQualityRendering = true,
	-- Lighting.GlobalShadows = false (restore khi stop).
	DisableGlobalShadows = true,
	ToggleKey = Enum.KeyCode.RightControl,

	-- === CONFIG NGOAI (getgenv, dung cho luarmor) ===
	-- DevDebug: hien khung LOGS/console tren GUI. Mac dinh AN cho gon/chuyen nghiep.
	DevDebug = false,
	-- HideShow: cho phep RightControl BAT/TAT GUI. Mac dinh KHONG cho tat.
	-- Muon bat/tat GUI thi getgenv().ThieuNangHub.HideShow = true.
	HideShow = true,
}

-- Config ngoai: dat TRUOC khi loadstring (chay cung luarmor). Vi du:
--   getgenv().ThieuNangHub = { AutoCollect = true, DevDebug = true, HideShow = true }
--   loadstring(game:HttpGet("..."))()
-- Chi key DA CO san trong CFG moi duoc nhan; khong nhan ten config la.
local function readExternalConfig()
	local env = (type(getgenv) == "function") and getgenv() or nil
	if type(env) == "table" then
		local c = env.ThieuNangHub or env.THIEUNANG_HUB or env.MM2_KAITUN_CONFIG
		if type(c) == "table" then
			return c
		end
	end
	if type(_G) == "table" then
		return rawget(_G, "ThieuNangHub") or rawget(_G, "MM2_KAITUN_CONFIG")
	end
	return nil
end

local assignedConfig = readExternalConfig()
if type(assignedConfig) == "table" then
	for key, value in pairs(assignedConfig) do
		if CFG[key] ~= nil then
			CFG[key] = value
		end
	end
end

--====================================================================
-- 2) RUNTIME + STATE
--====================================================================
local Runtime = {
	Alive = true,
	Connections = {},
	Tasks = {},
	TaskStatus = {},
	TaskIndex = 0,
	CoinCache = setmetatable({}, { __mode = "k" }),
	CoinBlacklist = setmetatable({}, { __mode = "k" }),
	CharacterSet = setmetatable({}, { __mode = "k" }),
	CharacterConnections = setmetatable({}, { __mode = "k" }),
	-- part -> true: cac part nhan vat da bi noclip ep CanCollide=false, de restore.
	NoclipDisabled = setmetatable({}, { __mode = "k" }),
	-- Cache cac object ten "CoinContainer" (main.lua): coin nhat duoc nam trong day.
	CoinContainers = nil,
	LastContainerScan = 0,
	-- Hook DescendantAdded bat CoinContainer moi (khoi quet full workspace lien tuc).
	ContainerHooked = false,
	-- Cooldown chon coin khi khong co coin nao (chong spam scan lam do GUI).
	NextChooseAt = 0,
	-- true khi dang anchor rootPart de collect (anchor-step teleport nhu main.lua).
	CoinAnchorActive = false,
	-- true khi dang tam unanchor + restore collision cho .Touched fire (0.35s).
	WaitingForTouch = false,
	-- Auto-detect firetouchinterest lom (ton tai nhung server khong nhan .Touched):
	-- fail lien tiep N coin khong an -> FastClaimBroken=true, chuyen physics touch.
	FastClaimFails = 0,
	FastClaimBroken = false,
	Gui = nil,
	GuiRefs = {},
	Logs = {},
	VisualHooked = false,
	AudioHooked = false,
	GameGuiHooked = false,
	CleanupBusy = false,
	LowRenderComplete = false,
	LowRenderNeedsRescan = false,
	HighestSearchBusy = false,
	HighestSearchToken = 0,
	LastHighestSearchAt = 0,
	CoinGeneration = 0,
	HighestSearchCoinGeneration = -1,
	LastCoinAddedAt = 0,
	FpsFrames = 0,
	FpsSampleAt = os.clock(),
	-- Uptime + tong coin earned (cho GUI timer va server-hop check).
	StartTime = os.clock(),
	TotalCoinsEarned = 0,
	-- Auto-box + godly.
	BoxBusy = false,
	BoxesOpened = 0,
	GodlyReported = false,
	-- Auto change acc (autoswap): da call chua (1 lan/phien) + cache event/quest.
	SwapCalled = false,
	MainEvent = nil,
	DailyQuestProgressText = nil,
	-- Engine saver: trang thai da chinh de restore khi shutdown.
	Render3DDisabled = false,
	OldGlobalShadows = nil,
	-- Server-hop check.
	HopCheckAt = nil,
	HopBaseline = 0,
}

local State = {
	Running = true,
	Phase = "waiting", -- waiting | loading | opening_hide | collect | hide | suicide | stopped
	RoundActive = false,
	RoundEpoch = 0,
	CoinsStartedActive = false,
	Role = "?",
	Gamemode = "?",
	MurdererName = nil,
	MurdererDistance = -1,

	BagCounts = {},
	BagCaps = {},
	ActiveBags = {},
	FullBags = {},
	Collected = 0,
	CoinsLeft = 0,
	HadCoinThisRound = false,
	HadConfirmedCollection = false,
	NoCoinSince = nil,

	TargetCoin = nil,
	TargetArrivedAt = nil,
	LastTargetDistance = nil,
	LastTargetProgressAt = 0,
	HidePoints = {},
	HidePointKeys = {},
	HideMoving = false,
	CoinBounds = nil,
	HighestHidePart = nil,
	HighestHidePosition = nil,
	HighestHideTopY = nil,
	OpeningHideSearchAt = nil,
	OpeningHideDeadline = nil,
	OpeningHideUntil = nil,
	OpeningHideTeleported = false,
	OpeningHideTeleportAttemptAt = nil,
	OpeningHideTeleportAttempts = 0,
	HideTeleported = false,
	HideTeleportAttemptAt = nil,
	HideTeleportAttempts = 0,
	FinalHideSearchAttempts = 0,
	HighestUpgradeScans = 0,
	CollectionFinished = false,

	Status = "Khoi dong...",
	FPS = 0,
	LuaHeapMB = 0,
	RemovedVisuals = 0,
	RemovedParts = 0,
	HiddenGui = 0,
	KilledControllers = 0,
	LastError = nil,
	FallbackPlayerData = {},
	HasEventPlayerData = false,
	ModulePlayerDataFresh = false,
	PlayerDataGeneration = 0,
	EventPlayerDataGeneration = -1,
	ModulePlayerDataGeneration = -1,
	MaplessRequestedAt = nil,
}

local shutdown
local ownsRuntime
local releaseCoinAnchor

local function pushLog(message)
	local text = tostring(message)
	State.Status = text
	Runtime.Logs[#Runtime.Logs + 1] = os.date("%H:%M:%S") .. "  " .. text
	if #Runtime.Logs > 40 then
		table.remove(Runtime.Logs, 1)
	end
	-- Chi in console khi DevDebug (config ngoai) de khong spam khi chay that.
	if CFG.DevDebug then
		print("[Thieu Nang Hub] " .. text)
	end
end

local function connect(signal, callback)
	if not signal or (ownsRuntime and not ownsRuntime()) then
		return nil
	end
	local ok, connection = pcall(function()
		return signal:Connect(callback)
	end)
	if ok and connection then
		Runtime.Connections[#Runtime.Connections + 1] = connection
		return connection
	end
	return nil
end

local function clearTable(t)
	if type(t) ~= "table" then
		return
	end
	if type(table.clear) == "function" then
		table.clear(t)
	else
		for key in pairs(t) do
			t[key] = nil
		end
	end
end

local function tryDestroy(instance)
	if not instance then
		return false
	end
	return pcall(function()
		instance:Destroy()
	end)
end

local function getLuaHeapMB()
	local kb = nil
	if type(gcinfo) == "function" then
		local ok, value = pcall(gcinfo)
		if ok then
			kb = value
		end
	end
	if type(kb) ~= "number" and type(collectgarbage) == "function" then
		local ok, value = pcall(collectgarbage, "count")
		if ok then
			kb = value
		end
	end
	return type(kb) == "number" and kb / 1024 or 0
end

ownsRuntime = function()
	return Runtime.Alive and rawget(_G, GLOBAL_KEY) == Runtime
end

shutdown = function(reason)
	if not Runtime.Alive then
		return
	end
	Runtime.Alive = false
	State.Running = false
	State.RoundActive = false
	State.Phase = "stopped"
	State.Status = "Da dung: " .. tostring(reason or "unknown")

	for _, connection in ipairs(Runtime.Connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end
	clearTable(Runtime.Connections)
	clearTable(Runtime.Tasks)
	clearTable(Runtime.CoinCache)
	clearTable(Runtime.CoinBlacklist)
	clearTable(Runtime.CharacterSet)
	clearTable(Runtime.CharacterConnections)
	clearTable(State.HidePoints)
	clearTable(State.HidePointKeys)
	Runtime.HighestSearchBusy = false

	-- Tra lai CanCollide cho cac part noclip da tat, tranh nhan vat xuyen san sau khi dung.
	for part in pairs(Runtime.NoclipDisabled) do
		if part and part.Parent then
			pcall(function()
				part.CanCollide = true
			end)
		end
	end
	clearTable(Runtime.NoclipDisabled)

	-- Huy tween coin dang chay (neu co) de char khong bi tween keo di sau khi dung.
	if Runtime.CoinTween then
		pcall(function()
			Runtime.CoinTween:Cancel()
		end)
		Runtime.CoinTween = nil
	end

	-- Bo anchor collect neu con (getRoot chua khai bao o day nen doc thang Character).
	if Runtime.CoinAnchorActive then
		Runtime.CoinAnchorActive = false
		local character = LocalPlayer.Character
		local anchorRoot = character and character:FindFirstChild("HumanoidRootPart")
		if anchorRoot then
			pcall(function()
				anchorRoot.Anchored = false
			end)
		end
	end

	local capFunction = nil
	if type(setfpscap) == "function" then
		capFunction = setfpscap
	elseif type(set_fps_cap) == "function" then
		capFunction = set_fps_cap
	end
	if capFunction and Runtime.FpsCapApplied then
		pcall(
			capFunction,
			math.max(1, math.floor(tonumber(CFG.RestoreFPSOnShutdown) or 60))
		)
	end

	-- Tra lai trang thai engine da chinh (ve 3D + shadow).
	if Runtime.Render3DDisabled then
		pcall(function()
			RunService:Set3dRenderingEnabled(true)
		end)
		Runtime.Render3DDisabled = false
	end
	if Runtime.OldGlobalShadows ~= nil then
		pcall(function()
			Lighting.GlobalShadows = Runtime.OldGlobalShadows
		end)
	end

	if Runtime.Gui and Runtime.Gui.Parent then
		pcall(function()
			Runtime.Gui:Destroy()
		end)
	end
	if rawget(_G, GLOBAL_KEY) == Runtime then
		rawset(_G, GLOBAL_KEY, nil)
	end
	if CFG.DevDebug then
		print("[Thieu Nang Hub] Shutdown: " .. tostring(reason or "unknown"))
	end
end

Runtime.Shutdown = function(reason)
	return shutdown(reason)
end
rawset(_G, GLOBAL_KEY, Runtime)

local function installEspNameGuard(playerGui)
	if not playerGui or Runtime.EspGuardedPlayerGui == playerGui then
		return
	end
	Runtime.EspGuardedPlayerGui = playerGui
	local function removeForbiddenEspGui(child)
		if ownsRuntime() and child and child.Parent == playerGui
			and child.Name == "ESP" and tryDestroy(child) then
			pushLog('Da xoa PlayerGui child ten "ESP" theo kick check trong source')
		end
	end
	removeForbiddenEspGui(playerGui:FindFirstChild("ESP"))
	connect(playerGui.ChildAdded, removeForbiddenEspGui)
end

-- Chay truoc cac WaitForChild remote de khong bo lo kick check moi frame.
installEspNameGuard(LocalPlayer:FindFirstChild("PlayerGui"))
connect(LocalPlayer.ChildAdded, function(child)
	if child.Name == "PlayerGui" then
		installEspNameGuard(child)
	end
end)

-- ANTI-AFK: Roblox kick sau ~20 phut khong co INPUT (chuot/phim). Di chuyen character
-- bang CFrame KHONG reset idle timer nen van bi kick. LocalPlayer.Idled fire truoc khi
-- kick (~20 phut) -> gia lap input bang VirtualUser de reset. Day la API engine chuan,
-- KHONG phai remote/logic game trong source.
if VirtualUser then
	connect(LocalPlayer.Idled, function()
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end)
		pushLog("Anti-AFK: reset idle timer (tranh kick 20p)")
	end)
else
	pushLog("Anti-AFK: executor khong co VirtualUser -> co the bi kick AFK")
end

--====================================================================
-- 3) SOURCE-CONFIRMED PATHS
--====================================================================
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 15)
if not Remotes or not ownsRuntime() then
	if ownsRuntime() then
		shutdown("thieu ReplicatedStorage.Remotes")
	end
	return
end
local Gameplay = Remotes and Remotes:WaitForChild("Gameplay", 10)
if not Gameplay or not ownsRuntime() then
	if ownsRuntime() then
		shutdown("thieu ReplicatedStorage.Remotes.Gameplay")
	end
	return
end

local function gameplayRemote(name)
	if not Gameplay or not ownsRuntime() then
		return nil
	end
	local remote = Gameplay:WaitForChild(name, 5)
	return ownsRuntime() and remote or nil
end

local R_CoinCollected = gameplayRemote("CoinCollected")
local R_CoinsStarted = gameplayRemote("CoinsStarted")
local R_RoleSelect = gameplayRemote("RoleSelect")
local R_RoundStart = gameplayRemote("RoundStart")
local R_LoadingMap = gameplayRemote("LoadingMap")
local R_VictoryScreen = gameplayRemote("VictoryScreen")
local R_RoundEndFade = gameplayRemote("RoundEndFade")
local R_PlayerDataChanged = gameplayRemote("PlayerDataChanged")

if not ownsRuntime() then
	return
end

local CurrentRoundClient = nil
local refreshRole
do
	local modules = ReplicatedStorage:FindFirstChild("Modules")
	local moduleScript = modules and modules:FindFirstChild("CurrentRoundClient")
	if moduleScript then
		local requireDataGeneration = State.PlayerDataGeneration
		task.spawn(function()
			-- Module source tu InvokeServer; tach coroutine de boot/GUI khong bi treo.
			local ok, result = pcall(require, moduleScript)
			if not ownsRuntime() then
				return
			end
			if ok and type(result) == "table" then
				CurrentRoundClient = result
				State.ModulePlayerDataFresh =
					State.PlayerDataGeneration == requireDataGeneration
				State.ModulePlayerDataGeneration =
					State.ModulePlayerDataFresh
						and State.PlayerDataGeneration
						or -1
				if result.PlayerDataChanged then
					pcall(function()
						connect(result.PlayerDataChanged.Event, function()
							if ownsRuntime() and refreshRole then
								State.ModulePlayerDataFresh = true
								State.ModulePlayerDataGeneration =
									State.PlayerDataGeneration
								refreshRole()
							end
						end)
					end)
				end
				if refreshRole then
					refreshRole()
				end
			else
				pushLog("Khong require duoc CurrentRoundClient")
			end
		end)
	else
		pushLog("Thieu ReplicatedStorage.Modules.CurrentRoundClient")
	end
end

-- Level nguoi choi (nguon THAT): LevelModule.GetLevel(ProfileData.NewXP).
-- Sync: Database.Sync (Weapons rarity, MysteryBox) - de detect godly khi mo box.
local LevelModule = nil
local ProfileData = nil
local Sync = nil
do
	local modules = ReplicatedStorage:FindFirstChild("Modules")
	if modules then
		task.spawn(function()
			local levelScript = modules:FindFirstChild("LevelModule")
			if levelScript then
				local ok, result = pcall(require, levelScript)
				if ownsRuntime() and ok and type(result) == "table" then
					LevelModule = result
				end
			end
			local profileScript = modules:FindFirstChild("ProfileData")
			if profileScript then
				local ok, result = pcall(require, profileScript)
				if ownsRuntime() and ok and type(result) == "table" then
					ProfileData = result
				end
			end
		end)
	end
	task.spawn(function()
		local database = ReplicatedStorage:FindFirstChild("Database")
		local syncScript = database and database:FindFirstChild("Sync")
		if syncScript then
			local ok, result = pcall(require, syncScript)
			if ownsRuntime() and ok and type(result) == "table" then
				Sync = result
			end
		end
	end)
	-- EventInfoService: cache MainEvent 1 LAN luc boot (task.spawn de khong chan
	-- scheduler nhu bipbeo.lua require + WaitForInitializedAsync moi 30s).
	-- Dung cho check quest daily cua AutoChangeAcc (schema: QuestService.lua:5-8).
	task.spawn(function()
		local shared = ReplicatedStorage:FindFirstChild("SharedServices")
		local eisScript = shared and shared:FindFirstChild("EventInfoService")
		if not eisScript then
			return
		end
		local ok, eis = pcall(require, eisScript)
		if ownsRuntime() and ok and type(eis) == "table" then
			pcall(function()
				if type(eis.WaitForInitializedAsync) == "function" then
					eis:WaitForInitializedAsync()
				end
				Runtime.MainEvent = eis:GetMainEvent()
			end)
		end
	end)
end

local function getPlayerLevel()
	if LevelModule
		and ProfileData
		and type(LevelModule.GetLevel) == "function" then
		local ok, lv = pcall(LevelModule.GetLevel, ProfileData.NewXP)
		if ok and tonumber(lv) then
			return math.floor(tonumber(lv))
		end
	end
	return nil
end

local function getAccountName()
	local display = LocalPlayer.DisplayName
	if type(display) == "string"
		and display ~= ""
		and display ~= LocalPlayer.Name then
		return display .. " (@" .. LocalPlayer.Name .. ")"
	end
	return LocalPlayer.Name
end

--====================================================================
-- 3b) SHELLS + AUTO BOX + GODLY WEBHOOK + SERVER HOP
--====================================================================
-- BoxCurrency co the la KEY that ("SummerKey2026") hoac TEN hien thi ("Shells").
-- Materials.lua:1072 SummerKey2026 = { Name="Shells", Currency=true }. So du + OpenCrate
-- deu dung KEY that. Ham nay map "Shells" -> "SummerKey2026" qua Sync.Materials.
local function resolveCurrencyKey()
	local cur = tostring(CFG.BoxCurrency or "")
	if Sync and type(Sync.Materials) == "table" then
		if Sync.Materials[cur] then
			return cur -- da la key that
		end
		for key, mat in pairs(Sync.Materials) do
			if type(mat) == "table"
				and (tostring(mat.Name) == cur or tostring(mat.ItemName) == cur) then
				return key -- vd "Shells" -> "SummerKey2026"
			end
		end
	end
	return cur
end

local function getShells()
	if not (ProfileData
		and type(ProfileData.Materials) == "table"
		and type(ProfileData.Materials.Owned) == "table") then
		return 0
	end
	local key = resolveCurrencyKey()
	return tonumber(ProfileData.Materials.Owned[key])
		or tonumber(ProfileData[key])
		or 0
end

-- Coin trong SHOP: ShopModule.lua:317/562 so gia bang ProfileData.Coins.
-- Fallback Materials.Owned.Coins (Sync.Materials co key "Coins", Materials.lua:9).
local function getShopCoins()
	if type(ProfileData) ~= "table" then
		return nil
	end
	local coins = tonumber(ProfileData.Coins)
	if coins == nil
		and type(ProfileData.Materials) == "table"
		and type(ProfileData.Materials.Owned) == "table" then
		coins = tonumber(ProfileData.Materials.Owned.Coins)
	end
	return coins
end

-- Battle pass tier: template ProfileData cua event co CurrentTier (Summer2025.lua:59).
-- Title event Summer2026 khong co trong dump nen quet bang ProfileData tim CurrentTier.
local function getBattlePassTier()
	if type(ProfileData) ~= "table" then
		return nil
	end
	for _, value in pairs(ProfileData) do
		if type(value) == "table" and tonumber(value.CurrentTier) then
			return tonumber(value.CurrentTier)
		end
	end
	return nil
end

-- Quest DAILY (logic bipbeo.lua): tim quest id "DailyCoins" hoac id/Title chua
-- "daily" trong EventStartInfo.Quests; so Progress (ProfileData[title].Quests[id])
-- voi ChallengeAmount cuoi (schema: QuestService.lua). CHI daily — weekly
-- ("Complete daily quest tiers") reset ca tuan, khong the xong trong 1 ngay nen
-- khong duoc dua vao dieu kien doi acc. Tra nil khi chua load/khong thay quest.
local function getDailyQuestInfo()
	local ev = Runtime.MainEvent
	if type(ev) ~= "table"
		or type(ev.EventStartInfo) ~= "table"
		or type(ev.EventStartInfo.Quests) ~= "table"
		or type(ProfileData) ~= "table"
		or type(ProfileData[ev.Title]) ~= "table" then
		return nil
	end
	local questConfigs = ev.EventStartInfo.Quests
	local playerQuests = ProfileData[ev.Title].Quests
	if type(playerQuests) ~= "table" then
		return nil
	end
	local questName = "DailyCoins"
	if not questConfigs[questName] then
		questName = nil
		for id, def in pairs(questConfigs) do
			if tostring(id):lower():find("daily", 1, true)
				or (type(def) == "table" and def.Title
					and tostring(def.Title):lower():find("daily", 1, true)) then
				questName = id
				break
			end
		end
	end
	local config = questName and questConfigs[questName]
	local playerQuest = questName and playerQuests[questName]
	if type(config) ~= "table"
		or type(config.Quests) ~= "table"
		or #config.Quests == 0
		or type(playerQuest) ~= "table" then
		return nil
	end
	local progress = tonumber(playerQuest.Progress) or 0
	local finalTarget = 0
	local completedTiers = 0
	for _, tier in ipairs(config.Quests) do
		local target = tonumber(tier.ChallengeAmount) or 0
		finalTarget = target
		if progress >= target then
			completedTiers = completedTiers + 1
		end
	end
	return {
		Name = questName,
		Progress = progress,
		FinalTarget = finalTarget,
		TiersDone = completedTiers,
		TierCount = #config.Quests,
	}
end

-- payload = table Discord webhook (content / embeds...) -> JSON encode roi POST.
local function sendWebhook(payload)
	local url = tostring(CFG.WebhookUrl or "")
	if url == "" then
		return false
	end
	local httpFn = (type(request) == "function" and request)
		or (type(http_request) == "function" and http_request)
		or (syn and type(syn.request) == "function" and syn.request)
		or (http and type(http.request) == "function" and http.request)
	if not httpFn then
		return false
	end
	local okBody, body = pcall(function()
		return HttpService:JSONEncode(payload)
	end)
	if not okBody then
		return false
	end
	return pcall(httpFn, {
		Url = url,
		Method = "POST",
		Headers = { ["Content-Type"] = "application/json" },
		Body = body,
	})
end

-- Godly Icecream: khop ten (ke ca "IcecreamChroma") va/hoac Rarity Godly trong Sync.
local function isTargetGodly(itemId)
	local id = tostring(itemId)
	local want = tostring(CFG.GodlyItemName or ""):lower()
	local nameMatch = want ~= "" and id:lower():find(want, 1, true) ~= nil
	local godly = false
	if Sync
		and type(Sync.Weapons) == "table"
		and type(Sync.Weapons[id]) == "table" then
		godly = Sync.Weapons[id].Rarity == "Godly"
	end
	return nameMatch, godly
end

-- OpenCrate tra ve list {MysteryBoxId, RewardedItemId} (MysteryBoxService).
local function extractRewardIds(result)
	local ids = {}
	if type(result) == "table" then
		if result.RewardedItemId ~= nil then
			ids[#ids + 1] = result.RewardedItemId
		end
		for _, v in pairs(result) do
			if type(v) == "table" and v.RewardedItemId ~= nil then
				ids[#ids + 1] = v.RewardedItemId
			end
		end
	elseif type(result) == "string" then
		ids[#ids + 1] = result
	end
	return ids
end

local function onGodlyIcecream(itemId)
	if Runtime.GodlyReported then
		return
	end
	Runtime.GodlyReported = true
	State.GodlyItem = tostring(itemId)
	-- Doi nen UI den -> XANH LA CAY khi trung godly.
	if CFG.GodlyGreenUI and Runtime.GuiRefs and Runtime.GuiRefs.Root then
		pcall(function()
			Runtime.GuiRefs.Root.BackgroundColor3 = Color3.fromRGB(18, 120, 45)
		end)
	end
	pushLog("GODLY " .. tostring(itemId) .. " -> gui webhook 1 lan")
	task.spawn(function()
		local id = tostring(itemId)
		local isChroma = id:lower():find("chroma", 1, true) ~= nil
		local image = isChroma
			and tostring(CFG.GodlyChromaImageUrl or "")
			or tostring(CFG.GodlyImageUrl or "")
		local up = math.max(0, os.clock() - (Runtime.StartTime or os.clock()))
		local embed = {
			title = (isChroma and "🌈 TRUNG CHROMA GODLY: " or "🍦 TRUNG GODLY: ") .. id,
			description = ("**Acc:** %s (@%s)\n**Box:** %s   •   **Box da mo:** %d\n**Thoi gian chay:** %02d:%02d:%02d")
				:format(
					tostring(LocalPlayer.DisplayName),
					tostring(LocalPlayer.Name),
					tostring(CFG.BoxName),
					tonumber(Runtime.BoxesOpened) or 0,
					math.floor(up / 3600),
					math.floor((up % 3600) / 60),
					math.floor(up % 60)
				),
			-- Mau embed: chroma = hong neon 0xFF4DE8, thuong = xanh ngoc 0x4DE8D0.
			color = isChroma and 16731624 or 5106896,
			footer = { text = "Thieu Nang Hub • discord.gg/thieunanghub" },
		}
		if image ~= "" then
			embed.thumbnail = { url = image }
		end
		sendWebhook({ content = "@everyone", embeds = { embed } })
	end)
end

-- Mua + mo box. OpenCrate la RemoteFunction (YIELD) -> chay trong coroutine rieng,
-- KHONG goi truc tiep trong scheduler callback (se chan Worker).
local function doAutoBuyBox()
	local price = tonumber(CFG.BoxPrice) or math.huge
	if getShells() < price then
		return
	end
	local shopFolder = Remotes and Remotes:FindFirstChild("Shop")
	local openCrate = shopFolder and shopFolder:FindFirstChild("OpenCrate")
	if not openCrate then
		State.LastError = "Khong thay Remotes.Shop.OpenCrate"
		return
	end
	local boxCtrl = shopFolder:FindFirstChild("BoxController")
	local currencyKey = resolveCurrencyKey()
	-- Mua HET so: mua toi da floor(so/gia) box, mo tung cai. Dung ngay khi loi/nil
	-- (server het so tu choi). Dem = so box mua duoc tai thoi diem nay; so tang them
	-- sau (weekly reward) se duoc mua o lan AutoBox tiep theo.
	local count = math.floor(getShells() / price)
	for _ = 1, count do
		if getShells() < price then
			break
		end
		local ok, result = pcall(function()
			return openCrate:InvokeServer(CFG.BoxName, "MysteryBox", currencyKey)
		end)
		if not ok then
			State.LastError = "OpenCrate: " .. tostring(result)
			break
		end
		if not result then
			break
		end
		Runtime.BoxesOpened = (Runtime.BoxesOpened or 0) + 1
		-- Cho game choi animation mo box (khong bat buoc).
		if boxCtrl then
			pcall(function()
				boxCtrl:Fire(CFG.BoxName, result)
			end)
		end
		for _, id in ipairs(extractRewardIds(result)) do
			local nameMatch, godly = isTargetGodly(id)
			if nameMatch then
				onGodlyIcecream(id)
			elseif godly then
				pushLog("Trung godly khac: " .. tostring(id))
			end
		end
	end
end

local function doServerHop()
	return pcall(function()
		TeleportService:Teleport(game.PlaceId, LocalPlayer)
	end)
end

-- POST accountops.org/api/accounts/autoswap-complete { username, option }.
-- option = so rule On-Demand tren web (1 = folder no godly, 2 = folder havegodly).
local function callAutoSwap(option)
	local key = tostring(CFG.AutoSwapApiKey or "")
	if key == "" then
		State.LastError = "AutoSwap: chua co ApiKey"
		return false
	end
	local httpFn = (type(request) == "function" and request)
		or (type(http_request) == "function" and http_request)
		or (syn and type(syn.request) == "function" and syn.request)
		or (http and type(http.request) == "function" and http.request)
	if not httpFn then
		return false
	end
	local username = tostring(CFG.AutoSwapUsername or "")
	if username == "" then
		username = LocalPlayer.Name
	end
	local okBody, body = pcall(function()
		return HttpService:JSONEncode({
			username = username,
			option = tonumber(option) or 1,
		})
	end)
	if not okBody then
		return false
	end
	return pcall(httpFn, {
		Url = tostring(CFG.AutoSwapUrl or ""),
		Method = "POST",
		Headers = {
			["X-Api-Key"] = key,
			["Content-Type"] = "application/json",
		},
		Body = body,
	})
end

if not ownsRuntime() then
	return
end

--====================================================================
-- 4) CHARACTER / ROUND HELPERS
--====================================================================
local function getCharacter()
	local character = LocalPlayer.Character
	if character and character.Parent then
		return character
	end
	return nil
end

local function getHumanoid()
	local character = getCharacter()
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

local function getRoot()
	local character = getCharacter()
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

local EMPTY_PLAYER_DATA = {}

local function getPlayerData()
	if State.HasEventPlayerData
		and State.EventPlayerDataGeneration == State.PlayerDataGeneration
		and type(State.FallbackPlayerData) == "table" then
		return State.FallbackPlayerData
	end
	if State.ModulePlayerDataFresh
		and State.ModulePlayerDataGeneration == State.PlayerDataGeneration
		and CurrentRoundClient
		and type(CurrentRoundClient.PlayerData) == "table" then
		return CurrentRoundClient.PlayerData
	end
	return EMPTY_PLAYER_DATA
end

local function isAliveByData()
	local data = getPlayerData()
	local mine = type(data) == "table" and data[LocalPlayer.Name] or nil
	if type(mine) == "table" then
		return mine.Dead ~= true
	end
	local humanoid = getHumanoid()
	return not humanoid or humanoid.Health > 0
end

local function hasLocalRoundData()
	local data = getPlayerData()
	local mine = type(data) == "table" and data[LocalPlayer.Name] or nil
	return type(mine) == "table" and mine.Role ~= nil and mine.Dead ~= true
end

refreshRole = function()
	local data = getPlayerData()
	if type(data) ~= "table" then
		return
	end

	local mine = data[LocalPlayer.Name]
	if type(mine) == "table" and mine.Role ~= nil then
		State.Role = tostring(mine.Role)
	end

	local murdererName = nil
	for name, info in pairs(data) do
		if type(info) == "table" and info.Role == "Murderer" and info.Dead ~= true then
			murdererName = tostring(name)
			break
		end
	end
	State.MurdererName = murdererName
end

local function getMurdererRoot()
	if not State.MurdererName then
		return nil
	end
	local player = Players:FindFirstChild(State.MurdererName)
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart") or nil
end

-- Dem so nguoi con song KHONG phai Murderer (innocent/sheriff/...) tu PlayerData.
-- Dung de biet co con moi minh minh song hay khong (suicide de ket thuc van nhanh).
-- Tra ve -1 neu chua co du lieu de khong ket luan voi vang.
local function countAliveNonMurderer()
	local data = getPlayerData()
	if type(data) ~= "table" or data == EMPTY_PLAYER_DATA then
		return -1
	end
	local count = 0
	local sawAny = false
	for _, info in pairs(data) do
		if type(info) == "table" then
			sawAny = true
			if info.Role ~= "Murderer" and info.Dead ~= true then
				count = count + 1
			end
		end
	end
	if not sawAny then
		return -1
	end
	return count
end

local function resetRoundState(newPhase)
	-- RoundEpoch chi huy async task/state movement. PlayerData co generation rieng:
	-- khong invalidate tai CoinsStarted vi source khong xac nhan no den truoc/sau
	-- RoundStart; LoadingMap/round-end moi la boundary invalidation.
	State.RoundEpoch = State.RoundEpoch + 1
	clearTable(State.BagCounts)
	clearTable(State.BagCaps)
	clearTable(State.ActiveBags)
	clearTable(State.FullBags)
	clearTable(State.HidePoints)
	clearTable(State.HidePointKeys)
	clearTable(Runtime.CoinBlacklist)
	State.Collected = 0
	State.CoinsLeft = 0
	State.HadCoinThisRound = false
	State.HadConfirmedCollection = false
	State.NoCoinSince = nil
	State.TargetCoin = nil
	State.TargetArrivedAt = nil
	State.LastTargetDistance = nil
	State.LastTargetProgressAt = 0
	State.HideMoving = false
	State.CoinBounds = nil
	State.HighestHidePart = nil
	State.HighestHidePosition = nil
	State.HighestHideTopY = nil
	State.OpeningHideSearchAt = nil
	State.OpeningHideDeadline = nil
	State.OpeningHideUntil = nil
	State.OpeningHideTeleported = false
	State.OpeningHideTeleportAttemptAt = nil
	State.OpeningHideTeleportAttempts = 0
	State.HideTeleported = false
	State.HideTeleportAttemptAt = nil
	State.HideTeleportAttempts = 0
	State.FinalHideSearchAttempts = 0
	State.HighestUpgradeScans = 0
	State.CollectionFinished = false
	State.MurdererDistance = -1
	State.MaplessRequestedAt = nil
	State.CoinsStartedActive = false
	Runtime.HighestSearchBusy = false
	Runtime.HighestSearchToken = Runtime.HighestSearchToken + 1
	Runtime.LastHighestSearchAt = 0
	Runtime.HighestSearchCoinGeneration = -1
	-- Round doi/ket thuc: bo anchor collect (farmMoveStep se return som khi het round).
	if releaseCoinAnchor then
		releaseCoinAnchor()
	end
	State.Phase = newPhase or "waiting"
end

local function invalidateRoundPlayerData()
	State.PlayerDataGeneration = State.PlayerDataGeneration + 1
	State.FallbackPlayerData = {}
	State.HasEventPlayerData = false
	State.EventPlayerDataGeneration = -1
	State.ModulePlayerDataFresh = false
	State.ModulePlayerDataGeneration = -1
	State.Role = "?"
	State.Gamemode = "?"
	State.MurdererName = nil
	State.MurdererDistance = -1
end

local function recalculateCollected()
	local total = 0
	for _, amount in pairs(State.BagCounts) do
		total = total + (tonumber(amount) or 0)
	end
	State.Collected = total
end

--====================================================================
-- 5) COIN CACHE - TAG/ATTRIBUTES CONFIRMED IN CoinVisualizer.lua
--====================================================================
local function cacheCoin(instance)
	if instance and instance:IsA("BasePart") then
		if not Runtime.CoinCache[instance] then
			Runtime.CoinGeneration = Runtime.CoinGeneration + 1
			Runtime.LastCoinAddedAt = os.clock()
		end
		Runtime.CoinCache[instance] = true
	end
end

local function refreshCoinCache()
	local ok, tagged = pcall(function()
		return CollectionService:GetTagged("CoinVisual")
	end)
	if ok and type(tagged) == "table" then
		Runtime.LastFullCoinRefresh = os.clock()
		for _, coin in ipairs(tagged) do
			cacheCoin(coin)
		end
	end
end

local function coinBagId(coin)
	if not coin then
		return nil
	end
	local ok, value = pcall(function()
		return coin:GetAttribute("CoinID")
	end)
	return ok and value ~= nil and tostring(value) or nil
end

local function coinBaseAvailable(coin)
	if not coin then
		return false
	end
	if not coin.Parent or not coin:IsA("BasePart") then
		Runtime.CoinCache[coin] = nil
		Runtime.CoinBlacklist[coin] = nil
		return false
	end
	if not coin:IsDescendantOf(workspace) then
		return false
	end
	if coin:GetAttribute("Collected") or coin:GetAttribute("Delete") then
		return false
	end
	local bagId = coinBagId(coin)
	if bagId and State.FullBags[bagId] then
		return false
	end
	return true
end

local function coinAvailable(coin, now)
	if not coinBaseAvailable(coin) then
		return false
	end
	local retryAt = Runtime.CoinBlacklist[coin]
	if retryAt and retryAt > now then
		return false
	elseif retryAt then
		Runtime.CoinBlacklist[coin] = nil
	end
	return true
end

--====================================================================
-- 5b) CLAIMABLE COIN theo main.lua (chong da test): CoinContainer + TouchInterest
-- Coin nhat duoc = BasePart trong object ten "CoinContainer", co TouchInterest
-- (TouchTransmitter) + child ten "CoinVisual". Nguon: main.lua isClaimableCoin.
--====================================================================
local function refreshCoinContainers()
	local list = {}
	local ok = pcall(function()
		for _, object in ipairs(workspace:GetDescendants()) do
			if object.Name == "CoinContainer" then
				list[#list + 1] = object
			end
		end
	end)
	if ok then
		Runtime.CoinContainers = list
		Runtime.LastContainerScan = os.clock()
	end
	-- Hook 1 lan: container MOI duoc bat ngay qua event -> khong can quet full
	-- workspace moi ContainerRescanSeconds nua (nguyen nhan chinh lam do GUI).
	if not Runtime.ContainerHooked then
		Runtime.ContainerHooked = true
		connect(workspace.DescendantAdded, function(object)
			if object.Name == "CoinContainer"
				and type(Runtime.CoinContainers) == "table"
				and not table.find(Runtime.CoinContainers, object) then
				Runtime.CoinContainers[#Runtime.CoinContainers + 1] = object
			end
		end)
	end
end

local function isClaimableCoin(object)
	if not object or not object.Parent or not object:IsA("BasePart") then
		return false
	end
	local hasTouch = object:FindFirstChild("TouchInterest")
		or object:FindFirstChildOfClass("TouchTransmitter")
	if not hasTouch then
		return false
	end
	return object:FindFirstChild("CoinVisual") ~= nil
end

-- Quet cac CoinContainer (co cache 5s / khi chua co) va goi callback cho moi coin.
local function forEachClaimableCoin(callback)
	-- Container moi da co hook DescendantAdded bat ngay; quet full chi con la
	-- fallback an toan (>=10s) thay vi moi ContainerRescanSeconds (1s lam do GUI).
	if type(Runtime.CoinContainers) ~= "table"
		or #Runtime.CoinContainers == 0
		or os.clock() - (Runtime.LastContainerScan or 0)
			>= math.max(tonumber(CFG.ContainerRescanSeconds) or 2, 10) then
		refreshCoinContainers()
	end
	local containers = Runtime.CoinContainers
	if type(containers) ~= "table" then
		return
	end
	for _, container in ipairs(containers) do
		if container and container.Parent then
			local ok, children = pcall(function()
				return container:GetChildren()
			end)
			if ok and type(children) == "table" then
				for _, coin in ipairs(children) do
					if isClaimableCoin(coin) then
						callback(coin)
					end
				end
			end
		end
	end
end

local function claimableInRange(distance)
	local range = tonumber(CFG.CoinScanRange) or 0
	return range <= 0 or distance <= range
end

-- Coin muc tieu con nhat duoc khong (con TouchInterest + khong bi blacklist).
local function claimableCoinStillValid(coin, now)
	if not isClaimableCoin(coin) then
		return false
	end
	local retryAt = Runtime.CoinBlacklist[coin]
	if retryAt and retryAt > now then
		return false
	elseif retryAt then
		Runtime.CoinBlacklist[coin] = nil
	end
	return true
end

-- Chon coin claim duoc gan nhat (giu logic tranh Murderer nhu chooseCoin cu).
local function chooseClaimableCoin()
	local root = getRoot()
	if not root then
		return nil, 0
	end
	local now = os.clock()
	local origin = root.Position
	local murdererRoot = CFG.AvoidMurderer and getMurdererRoot() or nil
	local murdererPosition = murdererRoot and murdererRoot.Position or nil
	-- Fallback khi MOI coin con lai deu sat murderer: chon coin XA murderer nhat
	-- de van nhat + thoat, thay vi dung yen nup (dung y chong: chon coin khac).
	local bestSafe = nil
	local bestSafeDanger = -1
	local availableCount = 0

	-- PASS 1: gom moi coin claim duoc (trong range, khong blacklist) vao list de tinh cum.
	local cands = {}
	forEachClaimableCoin(function(coin)
		local pos = coin.Position
		local distance = (pos - origin).Magnitude
		if not claimableInRange(distance) then
			return
		end
		availableCount = availableCount + 1
		local retryAt = Runtime.CoinBlacklist[coin]
		if retryAt and retryAt > now then
			return
		elseif retryAt then
			Runtime.CoinBlacklist[coin] = nil
		end

		local dangerDistance = math.huge
		if murdererPosition then
			dangerDistance = (pos - murdererPosition).Magnitude
		end
		-- Ung vien du phong: coin xa murderer nhat trong so con lai.
		if dangerDistance > bestSafeDanger then
			bestSafeDanger = dangerDistance
			bestSafe = coin
		end
		cands[#cands + 1] = {
			coin = coin,
			pos = pos,
			distance = distance,
			danger = dangerDistance,
		}
	end)

	-- Ban kinh tinh cum = tam ban firetouchinterest (nhung coin claim CUNG 1 luc).
	local clusterRadius = tonumber(CFG.ClusterRadius) or 0
	if clusterRadius <= 0 then
		clusterRadius = tonumber(CFG.TouchNearbyRadius) or 0
	end
	local clusterBonus = tonumber(CFG.ClusterBonus) or 0
	-- Guard chong lag: cum chi tinh khi bat, co ban kinh/bonus, va so coin khong qua lon.
	-- 250 (thay vi 600): tinh cum la O(n^2), 600 coin = 360k phep tinh moi lan chon
	-- -> giat GUI; 250 van du cho map dong coin.
	local usePrefer = CFG.PreferCoinClusters
		and clusterRadius > 0
		and clusterBonus > 0
		and #cands <= 250

	-- PASS 2: cham diem = gan char (distance) - thuong density (cum) + phat gan murderer.
	local best = nil
	local bestScore = math.huge
	for i = 1, #cands do
		local c = cands[i]
		-- CHI loai coin nam sat murderer duoi MurdererHardAvoid (khong loai ca cum).
		if c.danger >= CFG.MurdererHardAvoid then
			local density = 1
			if usePrefer then
				for j = 1, #cands do
					if j ~= i and (cands[j].pos - c.pos).Magnitude <= clusterRadius then
						density = density + 1
					end
				end
			end
			local score = c.distance - clusterBonus * (density - 1)
			if murdererPosition and c.danger < CFG.SafeDistance then
				score = score + (CFG.SafeDistance - c.danger) * 2
			end
			if score < bestScore then
				best = c.coin
				bestScore = score
			end
		end
	end

	-- Neu khong coin nao dat nguong an toan -> lay coin xa murderer nhat (van nhat).
	local chosen = best or bestSafe

	State.CoinsLeft = availableCount
	if availableCount > 0 then
		State.HadCoinThisRound = true
		State.NoCoinSince = nil
	elseif State.HadCoinThisRound and not State.NoCoinSince then
		State.NoCoinSince = now
	end
	return chosen, availableCount
end

local function countClaimableCoins()
	local count = 0
	forEachClaimableCoin(function()
		count = count + 1
	end)
	return count
end

local function destroyFullBagCoins(bagId)
	for coin in pairs(Runtime.CoinCache) do
		if coin and coin.Parent and coinBagId(coin) == bagId then
			Runtime.CoinCache[coin] = nil
			if tryDestroy(coin) then
				State.RemovedVisuals = State.RemovedVisuals + 1
			end
		end
	end
end

local function allKnownBagsFull()
	local sawActiveBag = false
	for bagId in pairs(State.ActiveBags) do
		sawActiveBag = true
		if not State.BagCaps[bagId] or not State.FullBags[bagId] then
			return false
		end
	end
	if sawActiveBag then
		return true
	end
	-- Neu miss CoinsStarted (inject giua round), source khong cho biet tong bag
	-- active. Khong duoc suy ra "tat ca full" chi tu nhung bag da tung emit.
	return false
end

local function enoughCoins()
	if CFG.CoinTarget > 0 and State.Collected >= CFG.CoinTarget then
		return true
	end
	if allKnownBagsFull() then
		return true
	end
	if CFG.CoinTarget <= 0
		and State.HadConfirmedCollection
		and State.HadCoinThisRound
		and State.CoinsLeft == 0
		and State.NoCoinSince
		and os.clock() - State.NoCoinSince >= CFG.NoCoinGraceSeconds then
		return true
	end
	return false
end

local function setTargetCoin(coin)
	State.TargetCoin = coin
	State.TargetArrivedAt = nil
	State.LastTargetDistance = nil
	State.LastTargetProgressAt = coin and os.clock() or 0
end

local function beginRoundMovement()
	setTargetCoin(nil)
	local openingHide = CFG.OpeningHideEnabled
		and CFG.AutoHide
		and State.Role ~= "Murderer"
	if openingHide then
		local now = os.clock()
		State.Phase = "opening_hide"
		State.OpeningHideSearchAt = now + CFG.OpeningHideSearchDelay
		State.OpeningHideDeadline = now + CFG.OpeningHideSearchTimeout
		State.OpeningHideUntil = nil
		State.OpeningHideTeleported = false
		State.OpeningHideTeleportAttemptAt = nil
		State.OpeningHideTeleportAttempts = 0
		State.Status = "Cho CoinVisual de tim mat cao nhat (heuristic)"
	else
		State.Phase = "collect"
	end
	return openingHide
end

local function rememberHidePoint(position)
	local cell = 8
	local key = tostring(math.floor(position.X / cell)) .. ":"
		.. tostring(math.floor(position.Y / cell)) .. ":"
		.. tostring(math.floor(position.Z / cell))
	if State.HidePointKeys[key] then
		return
	end
	State.HidePointKeys[key] = true
	State.HidePoints[#State.HidePoints + 1] = position
	if #State.HidePoints > CFG.MaxHidePoints then
		local removed = table.remove(State.HidePoints, 1)
		if removed then
			local oldKey = tostring(math.floor(removed.X / cell)) .. ":"
				.. tostring(math.floor(removed.Y / cell)) .. ":"
				.. tostring(math.floor(removed.Z / cell))
			State.HidePointKeys[oldKey] = nil
		end
	end
end

--====================================================================
-- 6) MOVEMENT: SEGMENTED COIN + OPTIONAL DIRECT TP DIEM CAO
-- CharacterClient.lua xac nhan Character:PivotTo + Humanoid.HipHeight.
-- Khong co con so anti-cheat server trong dump.
--====================================================================
local function normalizeMovementConfig()
	CFG.MoveDelay = math.clamp(tonumber(CFG.MoveDelay) or 0.15, 0.12, 1)
	local budget = math.clamp(
		tonumber(CFG.MaxMoveStudsPerSecond) or 14,
		1,
		14
	)
	CFG.MaxMoveStudsPerSecond = budget
	local maxStep = math.max(0.5, math.min(3, budget * CFG.MoveDelay))
	CFG.MaxStepStuds = math.clamp(
		tonumber(CFG.MaxStepStuds) or 2,
		0.5,
		maxStep
	)
	return CFG.MaxStepStuds
end

local function normalizeConfig()
	CFG.CoinTarget = math.max(0, math.floor(tonumber(CFG.CoinTarget) or 0))
	CFG.NoCoinGraceSeconds = math.clamp(
		tonumber(CFG.NoCoinGraceSeconds) or 5,
		1,
		30
	)
	CFG.ArrivalRadius = math.clamp(tonumber(CFG.ArrivalRadius) or 5, 1, 12)
	CFG.CoinScanDelay = math.clamp(tonumber(CFG.CoinScanDelay) or 0.25, 0.05, 2)
	CFG.ContainerRescanSeconds = math.clamp(
		tonumber(CFG.ContainerRescanSeconds) or 2,
		0.5,
		30
	)
	CFG.StuckSeconds = math.clamp(tonumber(CFG.StuckSeconds) or 3, 1, 15)
	CFG.RetryDelay = math.clamp(tonumber(CFG.RetryDelay) or 1.5, 0.25, 10)
	CFG.PanicDistance = math.max(5, tonumber(CFG.PanicDistance) or 35)
	CFG.SafeDistance = math.max(
		CFG.PanicDistance + 1,
		tonumber(CFG.SafeDistance) or 65
	)
	-- Nguong loai coin sat murderer khi collect: >=3 va khong lon hon PanicDistance.
	CFG.MurdererHardAvoid = math.clamp(
		tonumber(CFG.MurdererHardAvoid) or 18,
		3,
		CFG.PanicDistance
	)
	CFG.TargetFPS = math.clamp(
		math.floor(tonumber(CFG.TargetFPS) or 10),
		1,
		60
	)
	CFG.LuaHeapSoftMB = math.max(32, tonumber(CFG.LuaHeapSoftMB) or 150)
	CFG.OpeningHideWaitSeconds = math.clamp(
		tonumber(CFG.OpeningHideWaitSeconds) or 2.5,
		0,
		30
	)
	CFG.OpeningHideSearchDelay = math.clamp(
		tonumber(CFG.OpeningHideSearchDelay) or 0.35,
		0,
		5
	)
	CFG.OpeningHideSearchTimeout = math.clamp(
		tonumber(CFG.OpeningHideSearchTimeout) or 8,
		1,
		30
	)
	CFG.OpeningHideArrivalTimeout = math.clamp(
		tonumber(CFG.OpeningHideArrivalTimeout) or 8,
		2,
		30
	)
	CFG.HighestArrivalCushion = math.clamp(
		tonumber(CFG.HighestArrivalCushion) or 3,
		1,
		15
	)
	CFG.HighestSearchRetrySeconds = math.clamp(
		tonumber(CFG.HighestSearchRetrySeconds) or 1,
		0.25,
		10
	)
	CFG.HighestFinalSearchMaxAttempts = math.clamp(
		math.floor(tonumber(CFG.HighestFinalSearchMaxAttempts) or 2),
		0,
		5
	)
	CFG.HighestFinalSearchRetrySeconds = math.clamp(
		tonumber(CFG.HighestFinalSearchRetrySeconds) or 4,
		1,
		30
	)
	CFG.HighestScanBatchSize = math.clamp(
		math.floor(tonumber(CFG.HighestScanBatchSize) or 300),
		50,
		1000
	)
	CFG.HighestStreamUpgradeDebounce = math.clamp(
		tonumber(CFG.HighestStreamUpgradeDebounce) or 0.75,
		0.25,
		5
	)
	CFG.HighestMaxUpgradeScans = math.clamp(
		math.floor(tonumber(CFG.HighestMaxUpgradeScans) or 1),
		0,
		3
	)
	CFG.HighestCoinBoundsMargin = math.clamp(
		tonumber(CFG.HighestCoinBoundsMargin) or 90,
		0,
		500
	)
	CFG.HighestMinFootprint = math.clamp(
		tonumber(CFG.HighestMinFootprint) or 6,
		3,
		40
	)
	CFG.HighestMaxFootprint = math.max(
		CFG.HighestMinFootprint,
		tonumber(CFG.HighestMaxFootprint) or 500
	)
	CFG.HighestMinUpVectorY = math.clamp(
		tonumber(CFG.HighestMinUpVectorY) or 0.75,
		0.5,
		1
	)
	CFG.HighestClearance = math.clamp(
		tonumber(CFG.HighestClearance) or 2,
		0.5,
		10
	)
	CFG.HighestInstantMaxAttempts = math.clamp(
		math.floor(tonumber(CFG.HighestInstantMaxAttempts) or 2),
		1,
		5
	)
	CFG.HighestInstantRetrySeconds = math.clamp(
		tonumber(CFG.HighestInstantRetrySeconds) or 2,
		0.5,
		10
	)
	normalizeMovementConfig()
end

normalizeConfig()

local function moveRootToPosition(targetRootPosition, instant)
	local character = getCharacter()
	local root = getRoot()
	if not character or not root or typeof(targetRootPosition) ~= "Vector3" then
		return math.huge, false
	end

	local current = root.Position
	local delta = targetRootPosition - current
	local distance = delta.Magnitude
	if distance < 0.001 then
		return 0, true
	end

	local nextPosition = targetRootPosition
	if not instant then
		local step = normalizeMovementConfig()
		nextPosition = distance > step and current + delta.Unit * step
			or targetRootPosition
	end
	local look = Vector3.new(delta.X, 0, delta.Z)
	if look.Magnitude < 0.001 then
		look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	if look.Magnitude < 0.001 then
		look = Vector3.new(0, 0, -1)
	end

	local ok, err = pcall(function()
		character:PivotTo(CFrame.lookAt(nextPosition, nextPosition + look.Unit))
	end)
	if not ok then
		State.LastError = tostring(err)
	end
	return distance, ok
end

local function stepPivotTo(targetPosition, instant)
	local humanoid = getHumanoid()
	if not humanoid or typeof(targetPosition) ~= "Vector3" then
		return math.huge
	end
	local goal = Vector3.new(
		targetPosition.X,
		targetPosition.Y + (tonumber(humanoid.HipHeight) or 0),
		targetPosition.Z
	)
	return moveRootToPosition(goal, instant == true)
end

-- ANCHOR-STEP teleport toi coin.CFrame (bam dung main.lua da test).
-- Anchor rootPart roi set CFrame tien toi da CoinStepStuds moi tick; buoc cuoi dat
-- chinh xac coin.CFrame de HumanoidRootPart trung coin -> .Touched cong coin.
-- Tra ve khoang cach CON LAI sau khi buoc (0 = da dat dung coin tick nay).
local function anchorStepToward(targetCFrame)
	local root = getRoot()
	if not root or typeof(targetCFrame) ~= "CFrame" then
		return math.huge
	end
	if CFG.AnchorWhileCollecting then
		Runtime.CoinAnchorActive = true
		pcall(function()
			root.Anchored = true
		end)
	end
	local startPos = root.Position
	local targetPos = targetCFrame.Position
	local distance = (targetPos - startPos).Magnitude

	-- DIRECT TELEPORT (yeu cau chong): TP THANG 1 phat toi coin, khong nhay tung stud.
	-- Vi target luon la coin GAN NHAT nen doan nay ngan -> an toan. DirectMaxStuds > 0
	-- chi la chot an toan cho cu nhay dau/coin gan nhat lo qua xa.
	if CFG.DirectTeleport then
		local cap = tonumber(CFG.DirectMaxStuds) or 0
		if cap > 0 and distance > cap then
			local direction = (targetPos - startPos).Unit
			pcall(function()
				root.CFrame = CFrame.new(startPos + direction * cap)
			end)
			return distance - cap
		end
		pcall(function()
			root.CFrame = targetCFrame
		end)
		return 0
	end

	-- FALLBACK cu: nhay tung buoc CoinStepStuds moi tick.
	local step = math.max(0.5, tonumber(CFG.CoinStepStuds) or 15)
	if distance <= step then
		pcall(function()
			root.CFrame = targetCFrame
		end)
		return 0
	end
	local direction = (targetPos - startPos).Unit
	pcall(function()
		root.CFrame = CFrame.new(startPos + direction * step)
	end)
	return distance - step
end

-- === TWEEN METHOD (chong thu) ===
-- Huy tween coin dang chay (khi doi target / touch / roi collect / round doi).
local function cancelCoinTween()
	if Runtime.CoinTween then
		pcall(function()
			Runtime.CoinTween:Cancel()
		end)
		Runtime.CoinTween = nil
	end
	Runtime.CoinTweenTargetPos = nil
end

-- Di chuyen toi coin bang TweenService thay vi teleport tung stud.
-- Anchor rootPart (nhu anchor-step) de tween muot, physics khong danh nhau voi tween.
-- Tra ve khoang cach CON LAI (0 = da toi trong ArrivalRadius, san sang touch).
local function tweenStepToward(targetCFrame)
	local root = getRoot()
	if not root or typeof(targetCFrame) ~= "CFrame" then
		return math.huge
	end
	if CFG.AnchorWhileCollecting then
		Runtime.CoinAnchorActive = true
		pcall(function()
			root.Anchored = true
		end)
	end
	local targetPos = targetCFrame.Position
	local distance = (targetPos - root.Position).Magnitude
	if distance <= math.max(0.5, CFG.ArrivalRadius) then
		cancelCoinTween()
		pcall(function()
			root.CFrame = targetCFrame
		end)
		return 0
	end

	-- Chi tao tween moi khi: chua co tween / doi target / tween da dung (khong Playing).
	local needNew = true
	if Runtime.CoinTween and Runtime.CoinTweenTargetPos then
		local sameTarget = (Runtime.CoinTweenTargetPos - targetPos).Magnitude <= 2
		local playing = Runtime.CoinTween.PlaybackState == Enum.PlaybackState.Playing
		if sameTarget and playing then
			needNew = false
		end
	end
	if needNew then
		cancelCoinTween()
		local speed = math.max(1, tonumber(CFG.TweenStudsPerSecond) or 60)
		local duration = math.clamp(
			distance / speed,
			0.05,
			math.max(0.1, tonumber(CFG.TweenMaxTime) or 3)
		)
		local ok, tween = pcall(function()
			return TweenService:Create(
				root,
				TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
				{ CFrame = targetCFrame }
			)
		end)
		if ok and tween then
			Runtime.CoinTween = tween
			Runtime.CoinTweenTargetPos = targetPos
			pcall(function()
				tween:Play()
			end)
		end
	end
	return distance
end

-- Bo anchor da bat khi collect (goi khi roi collect / round end / shutdown).
releaseCoinAnchor = function()
	cancelCoinTween()
	if not Runtime.CoinAnchorActive then
		return
	end
	Runtime.CoinAnchorActive = false
	local root = getRoot()
	if root then
		pcall(function()
			root.Anchored = false
		end)
	end
end

-- Touch coin: dat root trung coin, tha Anchored, cho physics .Touched fire.
-- GIONG CHINH XAC main.lua: set CFrame -> unanchor -> wait 0.35s.
-- Bug cu: restoreNoclipParts() dinh nghia o dong ~2832 nhung goi o day -> nil crash.
-- Gio inline toan bo, khong phu thuoc ham dinh nghia sau.
local function touchCoinAndWait(coin)
	if not coin or not coin.Parent then
		return
	end
	local root = getRoot()
	if not root then
		return
	end
	local character = getCharacter()
	if not character then
		return
	end

	Runtime.WaitingForTouch = true

	-- 0) Huy tween coin (neu dang tween toi) de khong danh nhau voi set CFrame + unanchor.
	cancelCoinTween()

	-- 1) Dat root CHINH XAC trung coin (dam bao overlap).
	pcall(function()
		root.CFrame = coin.CFrame
	end)

	-- 2) Restore CanCollide INLINE (khong goi restoreNoclipParts vi no chua dinh nghia).
	pcall(function()
		for part in pairs(Runtime.NoclipDisabled) do
			if part and part.Parent then
				part.CanCollide = true
			end
		end
		-- Xoa table sau khi restore xong.
		for part in pairs(Runtime.NoclipDisabled) do
			Runtime.NoclipDisabled[part] = nil
		end
	end)

	-- 3) Tha Anchored de physics tao va cham that (GIONG main.lua dong 143).
	pcall(function()
		root.Anchored = false
	end)

	-- 4) (DA BO buoc bonus firetouchinterest - chong chot 100% cham that nhu main.lua;
	-- executor stub fire vo ich con ton 0.1s/coin.)

	-- 5) Cho 0.35s de server nhan .Touched (GIONG main.lua dong 636).
	task.wait(0.35)

	-- 6) Re-anchor cho coin tiep theo.
	root = getRoot()
	if root and CFG.AnchorWhileCollecting then
		pcall(function()
			root.Anchored = true
		end)
		Runtime.CoinAnchorActive = true
	end
	Runtime.WaitingForTouch = false
end

-- FAST CLAIM: fireTouchNearbyCoins moi tick da claim ca cum quanh char, nen luc "toi
-- coin" chi can fire dung coin do 1 phat (khong lam man unanchor + wait 0.35s cua
-- touchCoinAndWait) roi qua coin ke -> nhanh hon nhieu. Giu Anchored (neu dang collect)
-- vi firetouchinterest fire .Touched truc tiep, khong can physics va cham. CHI dung khi
-- co firetouchinterest; khong co thi farmMoveStep tu fallback ve touchCoinAndWait.
local function fastTouchCoin(coin)
	local root = getRoot()
	if not coin or not coin.Parent or not root then
		return
	end
	local touchFn = type(firetouchinterest) == "function" and firetouchinterest or nil
	if not touchFn then
		return
	end
	-- Dat root trung coin de chac chan overlap (van giu Anchored neu dang collect).
	pcall(function()
		root.CFrame = coin.CFrame
	end)
	pcall(touchFn, root, coin, 0) -- bat dau cham
	pcall(touchFn, root, coin, 1) -- ket thuc cham
	local wait = math.clamp(tonumber(CFG.FastClaimWait) or 0.05, 0, 0.3)
	if wait > 0 then
		task.wait(wait)
	end
end

-- Fire touch (firetouchinterest) MOI coin claim duoc trong ban kinh quanh nhan vat.
-- Chong xac nhan runtime: dung BEN CANH coin la server nhan .Touched (khong can dung
-- chinh xac len coin) -> lai gan 1 cum coin thi claim CA CUM 1 luc, nhanh hon nhat
-- tung coin. KHONG tu tang State.Collected o day: count that di qua remote CoinCollected.
-- Chi duoc goi trong phase collect cua farmMoveStep (da qua gate RoundActive + con
-- song + AutoCollect) -> khong fire o lobby / khi chet / coin da nhat.
local function fireTouchNearbyCoins(root)
	if not CFG.TouchNearbyCoins or Runtime.FastClaimBroken then
		-- FastClaimBroken: firetouchinterest da xac dinh khong an -> fire cum vo ich, bo.
		return 0
	end
	local touchFn = type(firetouchinterest) == "function" and firetouchinterest or nil
	if not touchFn or not root then
		return 0
	end
	local origin = root.Position
	local radius = tonumber(CFG.TouchNearbyRadius) or 0
	local fired = 0
	forEachClaimableCoin(function(coin)
		-- isClaimableCoin da doi hoi con TouchInterest; them lop chan coin da danh dau.
		if coin:GetAttribute("Collected") or coin:GetAttribute("Delete") then
			return
		end
		if radius > 0 then
			local distance = (coin.Position - origin).Magnitude
			if distance > radius then
				return
			end
		end
		pcall(touchFn, root, coin, 0) -- bat dau cham
		pcall(touchFn, root, coin, 1) -- ket thuc cham
		fired = fired + 1
	end)
	return fired
end

local function chooseHideTarget(murdererPosition)
	local best = nil
	local bestDistance = -1
	for _, point in ipairs(State.HidePoints) do
		local distance = (point - murdererPosition).Magnitude
		if distance > bestDistance then
			bestDistance = distance
			best = point
		end
	end
	return best
end

-- Cai dat sau isEssentialWorldPart(), truoc khi scheduler bat dau chay.
-- Tach forward declaration de farmMoveStep khong can doi thu tu cac khoi source.
local highestHideSpotValid
local requestHighestHideSearch

local function requestHighestUpgradeIfDue(now)
	if not State.HighestHidePart
		or Runtime.CoinGeneration <= Runtime.HighestSearchCoinGeneration
		or State.HighestUpgradeScans >= CFG.HighestMaxUpgradeScans
		or now - Runtime.LastCoinAddedAt
			< CFG.HighestStreamUpgradeDebounce
		or Runtime.HighestSearchBusy then
		return false
	end
	local started = requestHighestHideSearch(true)
	if started then
		State.HighestUpgradeScans = State.HighestUpgradeScans + 1
		State.Status =
			"Phat hien CoinVisual moi -> scan nang cap diem cao 1 lan"
		return true
	end
	return false
end

local function moveToHighestHideSpot(openingPhase)
	local valid, targetPosition = highestHideSpotValid()
	if not valid or not targetPosition then
		requestHighestHideSearch()
		return false, "search"
	end
	local root = getRoot()
	if not root then
		return false, "character"
	end
	local now = os.clock()
	local distance = (root.Position - targetPosition).Magnitude
	if distance <= CFG.ArrivalRadius then
		if openingPhase then
			State.OpeningHideTeleported = true
		else
			State.HideTeleported = true
		end
		return true, "arrived"
	end

	if openingPhase then
		State.OpeningHideTeleported = false
		State.OpeningHideUntil = nil
	else
		State.HideTeleported = false
	end

	if CFG.HighestInstantTeleport then
		local attemptKey = openingPhase
			and "OpeningHideTeleportAttemptAt"
			or "HideTeleportAttemptAt"
		local attemptsKey = openingPhase
			and "OpeningHideTeleportAttempts"
			or "HideTeleportAttempts"
		local lastAttempt = State[attemptKey]
		local attempts = State[attemptsKey] or 0
		-- Gioi han lan direct PivotTo, sau do fallback segmented de khong spam.
		-- Day van chi la policy noi bo; server anti-cheat khong co trong source.
		if attempts < CFG.HighestInstantMaxAttempts
			and (
				not lastAttempt
				or now - lastAttempt >= CFG.HighestInstantRetrySeconds
			) then
			State[attemptKey] = now
			State[attemptsKey] = attempts + 1
			local _, moved = moveRootToPosition(targetPosition, true)
			if not moved then
				return false, "error"
			end
			State.Status = openingPhase
				and "Da teleport 1 lan len diem cao; dang xac nhan vi tri"
				or "Dang quay lai diem cao sau khi nhat coin"
		elseif attempts < CFG.HighestInstantMaxAttempts then
			moveRootToPosition(targetPosition, false)
			State.Status =
				"Cho retry direct PivotTo; van di Segmented Step toi diem cao"
		else
			moveRootToPosition(targetPosition, false)
			State.Status =
				"Direct PivotTo khong giu duoc vi tri -> fallback Segmented Step"
		end
	else
		moveRootToPosition(targetPosition, false)
		State.Status = "Dang Segmented Step toi diem cao heuristic"
	end
	return false, "moving"
end

local function farmMoveStep()
	if not CFG.Enabled or not State.RoundActive then
		return
	end
	if not isAliveByData() then
		State.Status = "PlayerData bao da chet; dung movement round nay"
		return
	end
	local humanoid = getHumanoid()
	if not humanoid or humanoid.Health <= 0 then
		State.Status = "Cho Humanoid san sang"
		return
	end
	local root = getRoot()
	if not root then
		State.Status = "Cho nhan vat spawn"
		return
	end

	-- Collect va suicide deu dung anchor-step (tu quan ly anchor); phase khac unanchor.
	if State.Phase ~= "collect" and State.Phase ~= "suicide" then
		releaseCoinAnchor()
	end

	if State.Phase == "opening_hide" then
		if not CFG.OpeningHideEnabled
			or not CFG.AutoHide
			or State.Role == "Murderer" then
			State.Phase = "collect"
			pushLog("Bo pha nup dau round theo CFG/Role -> collect")
			return
		end

		local now = os.clock()
		if State.OpeningHideSearchAt and now < State.OpeningHideSearchAt then
			State.Status = "Doi CoinVisual on dinh truoc khi tim diem cao"
			return
		end

		local valid = highestHideSpotValid()
		if not valid then
			if Runtime.CleanupBusy then
				State.OpeningHideDeadline = math.max(
					State.OpeningHideDeadline or 0,
					now + CFG.OpeningHideSearchTimeout
				)
				State.Status =
					"Cho LowRender/cleanup xong roi moi scan diem cao"
				return
			end
			if Runtime.HighestSearchBusy then
				State.Status =
					"Dang quet workspace de chon diem cao heuristic"
				return
			end
			if State.OpeningHideDeadline and now >= State.OpeningHideDeadline then
				State.Phase = "collect"
				pushLog(
					"Timeout tim diem cao heuristic -> van tiep tuc collect, "
						.. "khong bia toa do"
				)
			else
				requestHighestHideSearch()
				State.Status =
					"Dang tim BasePart cao nhat trong bien X/Z CoinVisual"
			end
			return
		end

		requestHighestUpgradeIfDue(now)

		local arrived = moveToHighestHideSpot(true)
		if not arrived then
			if State.OpeningHideDeadline and now >= State.OpeningHideDeadline then
				State.Phase = "collect"
				pushLog(
					"Khong giu duoc vi tri diem cao trong timeout -> collect"
				)
			end
			return
		end
		if not State.OpeningHideUntil then
			State.OpeningHideUntil = now + CFG.OpeningHideWaitSeconds
			pushLog("Da len diem cao heuristic -> nup dau round")
		end
		if now < State.OpeningHideUntil then
			State.Status = string.format(
				"Nup dau round tren cao, con %.1fs",
				State.OpeningHideUntil - now
			)
			return
		end
		State.Phase = "collect"
		setTargetCoin(nil)
		pushLog("Het thoi gian nup dau round -> bat dau collect")
		return
	end

	if State.Phase == "collect" then
		requestHighestUpgradeIfDue(os.clock())
		if enoughCoins() then
			releaseCoinAnchor()
			setTargetCoin(nil)
			State.CollectionFinished = true
			State.HideTeleported = false
			State.HideTeleportAttemptAt = nil
			State.HideTeleportAttempts = 0
			State.FinalHideSearchAttempts = 0
			if CFG.AutoHide and State.Role ~= "Murderer" then
				State.Phase = "hide"
				pushLog(
					"Dat dieu kien bag/CFG/no-Coin heuristic -> nup luon"
				)
			else
				State.Status = "Dat dieu kien dung coin"
			end
			return
		end
		if not CFG.AutoCollect then
			releaseCoinAnchor()
			State.Status = "Auto Collect dang tat"
			return
		end

		-- CLAIM CA CUM: fire touch moi coin claim duoc quanh nhan vat (chong xac nhan
		-- dung ben canh la an). Da qua gate: RoundActive + con song + AutoCollect + phase
		-- collect (round dang co coin) -> "call dung luc coin spawn, khong call o lobby/khi chet".
		fireTouchNearbyCoins(root)

		-- Murderer gan KHONG con bo collect nup nua. Thay vao do chooseClaimableCoin
		-- se tu chon coin XA murderer (nhat + thoat cung luc). Chi cap nhat khoang
		-- cach cho GUI o day; viec ne murderer nam trong logic chon coin ben duoi.
		local mRoot = CFG.AvoidMurderer and State.Role ~= "Murderer" and getMurdererRoot() or nil
		if mRoot then
			State.MurdererDistance = (root.Position - mRoot.Position).Magnitude
		else
			State.MurdererDistance = -1
		end

		local now = os.clock()
		local target = State.TargetCoin
		if not claimableCoinStillValid(target, now) then
			target = chooseClaimableCoin()
			setTargetCoin(target)
		end
		if not target then
			releaseCoinAnchor()
			State.Status = "Cho CoinContainer co coin claim duoc"
			return
		end

		-- Di chuyen toi coin.CFrame: tween (UseTween) hoac anchor-step/teleport.
		local remaining
		if CFG.UseTween then
			remaining = tweenStepToward(target.CFrame)
		else
			remaining = anchorStepToward(target.CFrame)
		end
		if remaining <= 0 then
			rememberHidePoint(target.Position)
			-- FastClaim: co firetouchinterest + da bat TouchNearbyCoins -> fire nhanh, khong
			-- cho 0.45s (cum da claim moi tick). Khong co firetouchinterest -> fallback
			-- touchCoinAndWait (man unanchor + physics + wait, an toan cho executor yeu).
			local hasTouchFn = type(firetouchinterest) == "function"
			-- FastClaimBroken: firetouchinterest co ton tai nhung server khong nhan
			-- (executor stub) -> bo fast claim, ve physics touch (main.lua da test OK).
			local useFast = CFG.FastClaim and CFG.TouchNearbyCoins and hasTouchFn
				and not Runtime.FastClaimBroken
			if useFast then
				State.Status = "Toi coin; fast claim"
				fastTouchCoin(target)
			else
				State.Status = "Da toi coin; dang fire touch"
				touchCoinAndWait(target)
			end
			-- Sau 0.35s: check coin da duoc nhat chua.
			if not claimableCoinStillValid(target, os.clock()) then
				-- Coin da mat TouchInterest = da nhat thanh cong.
				Runtime.FastClaimFails = 0
				setTargetCoin(nil)
			else
				-- Van con TouchInterest = chua nhat duoc, blacklist roi thu coin khac.
				-- Chi tinh fail khi 5s gan day KHONG co CoinCollected nao (bang chung
				-- server) -> tranh dem nham do replicate tre tren executor xin.
				if useFast
					and os.clock() - (Runtime.LastCoinCollectedAt or 0) > 5 then
					Runtime.FastClaimFails = (Runtime.FastClaimFails or 0) + 1
					if Runtime.FastClaimFails >= 8 then
						Runtime.FastClaimBroken = true
						pushLog("firetouchinterest KHONG an coin (8 lan lien tiep)"
							.. " -> chuyen physics touch (unanchor + cham that)")
					end
				end
				Runtime.CoinBlacklist[target] = os.clock() + CFG.RetryDelay
				setTargetCoin(nil)
			end
		else
			State.TargetArrivedAt = nil
			if not State.LastTargetDistance
				or remaining < State.LastTargetDistance - 0.2 then
				State.LastTargetDistance = remaining
				State.LastTargetProgressAt = now
			elseif now - State.LastTargetProgressAt >= CFG.StuckSeconds then
				Runtime.CoinBlacklist[target] = now + CFG.RetryDelay
				setTargetCoin(nil)
			end
			State.Status = CFG.UseTween and "Dang tween toi coin" or "Dang anchor-step toi coin"
		end
		return
	end

	if State.Phase == "suicide" then
		local mRoot = getMurdererRoot()
		if not mRoot then
			releaseCoinAnchor()
			State.Phase = "hide"
			State.Status = "Chua co murderer de tu sat -> tam nup"
			return
		end
		-- Diem ngay TRUOC MAT murderer (theo huong nhin cua murderer).
		local mCFrame = mRoot.CFrame
		local front = mCFrame.Position + mCFrame.LookVector * CFG.SuicideFrontStuds
		-- Teleport tung buoc GIONG logic nhat coin (anchor-step) ra truoc mat murderer.
		local remaining = anchorStepToward(CFrame.new(front))
		if remaining <= 0 then
			-- Da toi noi: tha anchor + collision de murderer chem trung, ket thuc van.
			releaseCoinAnchor()
			State.Status = "Da ra truoc mat murderer -> cho bi giet ket thuc van"
		else
			State.Status = "Dang teleport ra truoc mat murderer de tu sat"
		end
		return
	end

	if State.Phase == "hide" then
		requestHighestUpgradeIfDue(os.clock())
		-- Da nhat xong + chi con MINH minh song -> tu sat cho murderer, lam van moi.
		if CFG.SuicideWhenLastAlive
			and State.CollectionFinished
			and State.Role ~= "Murderer"
			and getMurdererRoot() then
			local aliveOthers = countAliveNonMurderer()
			if aliveOthers >= 0 and aliveOthers <= 1 then
				State.Phase = "suicide"
				pushLog("Nhat xong + con moi minh -> tu sat truoc mat murderer, lam van moi")
				return
			end
		end
		if not State.CollectionFinished
			and CFG.AutoCollect
			and not enoughCoins()
			and State.CoinsLeft > 0 then
			State.Phase = "collect"
			return
		end
		if not CFG.AutoHide then
			State.Status = "Auto Hide dang tat"
			return
		end
		if State.Role == "Murderer" then
			State.Status = "Role Murderer -> khong auto hide"
			return
		end

		if CFG.HideAtHighestAfterCollect then
			local valid = highestHideSpotValid()
			if not valid then
				requestHighestHideSearch()
			else
				local arrived = moveToHighestHideSpot(false)
				if arrived then
					State.Status =
						"Da nhat xong -> dang nup yen tren diem cao heuristic"
				end
				return
			end
		end

		local murdererRoot = getMurdererRoot()
		if not murdererRoot then
			State.MurdererDistance = -1
			State.HideMoving = false
			State.Status = "Chua xac dinh Murderer -> dung yen"
			return
		end

		local murdererPosition = murdererRoot.Position
		local distance = (root.Position - murdererPosition).Magnitude
		State.MurdererDistance = distance
		if distance <= CFG.PanicDistance then
			State.HideMoving = true
		elseif distance >= CFG.SafeDistance then
			State.HideMoving = false
		end

		if not State.HideMoving then
			State.Status = "Dung tai hide point tu CoinVisual (heuristic)"
			return
		end

		local target = chooseHideTarget(murdererPosition)
		if target then
			stepPivotTo(target)
			State.Status = "Murderer gan -> di hide point xa nhat (heuristic)"
		else
			-- Khong tu bia toa do fallback khi chua co diem CoinVisual da di qua.
			State.Status = "Khong co hide point da ghi nhan -> dung yen"
		end
	end
end

--====================================================================
-- 7) LOW RAM / LOW RENDER
--====================================================================
local function registerCharacter(character)
	if character then
		Runtime.CharacterSet[character] = true
	end
end

local function hookPlayerCharacter(player)
	if not player then
		return
	end
	registerCharacter(player.Character)
	if not Runtime.CharacterConnections[player] then
		Runtime.CharacterConnections[player] = connect(
			player.CharacterAdded,
			registerCharacter
		)
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	hookPlayerCharacter(player)
end
connect(Players.PlayerAdded, hookPlayerCharacter)
connect(Players.PlayerRemoving, function(player)
	local connection = Runtime.CharacterConnections[player]
	if connection then
		pcall(function()
			connection:Disconnect()
		end)
		Runtime.CharacterConnections[player] = nil
	end
	if player.Character then
		Runtime.CharacterSet[player.Character] = nil
	end
end)

local function isPlayerCharacterInstance(instance)
	local cursor = instance
	while cursor and cursor ~= workspace do
		if Runtime.CharacterSet[cursor] then
			return true
		end
		cursor = cursor.Parent
	end
	return false
end

local function isCoinPart(instance)
	if not instance then
		return false
	end
	if Runtime.CoinCache[instance] then
		return true
	end
	if instance:GetAttribute("CoinID") ~= nil then
		return true
	end
	-- Bao ve luon coin nhat duoc theo main.lua: part trong CoinContainer / co child CoinVisual.
	local parent = instance.Parent
	if parent and parent.Name == "CoinContainer" then
		return true
	end
	if instance:IsA("BasePart") and instance:FindFirstChild("CoinVisual") then
		return true
	end
	return false
end

local function isEssentialWorldPart(instance)
	if isPlayerCharacterInstance(instance) then
		return true
	end
	if isCoinPart(instance) then
		return true
	end
	local camera = workspace.CurrentCamera
	if camera and (instance == camera or instance:IsDescendantOf(camera)) then
		return true
	end
	return false
end

-- Khong co path current map trong source hop le. Khoi nay chi dung object runtime:
-- CoinVisual tao bien X/Z, sau do chon mat BasePart va cham cao nhat trong bien.
-- "Cao nhat" khong dong nghia "an toan"; hazard/collision group/server khong co source.
local function getHideCandidateGeometry(instance)
	local ok, geometry = pcall(function()
		if not instance
			or not instance.Parent
			or not instance:IsA("BasePart")
			or not instance:IsDescendantOf(workspace)
			or not instance.CanCollide
			or (CFG.HighestRequireAnchored and not instance.Anchored)
			or isEssentialWorldPart(instance) then
			return nil
		end

		local cframe = instance.CFrame
		if math.abs(cframe.UpVector.Y) < CFG.HighestMinUpVectorY then
			return nil
		end
		local half = instance.Size * 0.5
		local extentX = math.abs(cframe.RightVector.X) * half.X
			+ math.abs(cframe.UpVector.X) * half.Y
			+ math.abs(cframe.LookVector.X) * half.Z
		local extentY = math.abs(cframe.RightVector.Y) * half.X
			+ math.abs(cframe.UpVector.Y) * half.Y
			+ math.abs(cframe.LookVector.Y) * half.Z
		local extentZ = math.abs(cframe.RightVector.Z) * half.X
			+ math.abs(cframe.UpVector.Z) * half.Y
			+ math.abs(cframe.LookVector.Z) * half.Z
		if extentX * 2 < CFG.HighestMinFootprint
			or extentZ * 2 < CFG.HighestMinFootprint
			or extentX * 2 > CFG.HighestMaxFootprint
			or extentZ * 2 > CFG.HighestMaxFootprint then
			return nil
		end

		local humanoid = getHumanoid()
		local root = getRoot()
		if not humanoid or not root then
			return nil
		end
		local topY = instance.Position.Y + extentY
		local goal = Vector3.new(
			instance.Position.X,
			topY
				+ (tonumber(humanoid.HipHeight) or 0)
				+ root.Size.Y * 0.5
				+ CFG.HighestClearance,
			instance.Position.Z
		)
		return {
			Goal = goal,
			TopY = topY,
			Width = extentX * 2,
			Depth = extentZ * 2,
		}
	end)
	return ok and geometry or nil
end

highestHideSpotValid = function()
	local part = State.HighestHidePart
	local geometry = getHideCandidateGeometry(part)
	if not geometry then
		State.HighestHidePart = nil
		State.HighestHidePosition = nil
		State.HighestHideTopY = nil
		State.OpeningHideTeleported = false
		State.HideTeleported = false
		return false, nil
	end
	State.HighestHidePosition = geometry.Goal
	State.HighestHideTopY = geometry.TopY
	return true, geometry.Goal
end

local function getCoinBoundsForHideSearch()
	local minX, maxX, minZ, maxZ
	local sumX, sumZ, count = 0, 0, 0
	for coin in pairs(Runtime.CoinCache) do
		if coinBaseAvailable(coin) then
			local ok, position = pcall(function()
				return coin.Position
			end)
			if ok and typeof(position) == "Vector3" then
				minX = minX and math.min(minX, position.X) or position.X
				maxX = maxX and math.max(maxX, position.X) or position.X
				minZ = minZ and math.min(minZ, position.Z) or position.Z
				maxZ = maxZ and math.max(maxZ, position.Z) or position.Z
				sumX = sumX + position.X
				sumZ = sumZ + position.Z
				count = count + 1
			end
		end
	end
	if count > 0 then
		return {
			MinX = minX,
			MaxX = maxX,
			MinZ = minZ,
			MaxZ = maxZ,
			CenterX = sumX / count,
			CenterZ = sumZ / count,
			Count = count,
		}
	end
	return State.CoinBounds
end

requestHighestHideSearch = function(upgradeOnly)
	if not ownsRuntime()
		or not State.RoundActive
		or Runtime.HighestSearchBusy
		or Runtime.CleanupBusy then
		return false
	end
	local now = os.clock()
	local finalHide = State.Phase == "hide"
	if finalHide
		and State.FinalHideSearchAttempts
			>= CFG.HighestFinalSearchMaxAttempts then
		return false, "exhausted"
	end
	local retrySeconds = finalHide
		and CFG.HighestFinalSearchRetrySeconds
		or CFG.HighestSearchRetrySeconds
	if Runtime.LastHighestSearchAt > 0
		and now - Runtime.LastHighestSearchAt < retrySeconds then
		return false
	end
	if finalHide then
		State.FinalHideSearchAttempts =
			State.FinalHideSearchAttempts + 1
	end
	Runtime.HighestSearchBusy = true
	Runtime.HighestSearchToken = Runtime.HighestSearchToken + 1
	local token = Runtime.HighestSearchToken
	local roundEpoch = State.RoundEpoch
	local searchPhase = State.Phase
	local openingScanDeadline = searchPhase == "opening_hide"
		and State.OpeningHideDeadline
		or nil
	local searchCoinGeneration = Runtime.CoinGeneration

	task.spawn(function()
		local scanTimedOut = false
		local function ownsSearch()
			return ownsRuntime()
				and State.RoundActive
				and State.RoundEpoch == roundEpoch
				and Runtime.HighestSearchToken == token
		end
		local function searchCanContinue()
			if not ownsSearch() then
				return false
			end
			if searchPhase == "opening_hide" then
				if State.Phase ~= "opening_hide" then
					return false
				end
				if openingScanDeadline
					and os.clock() >= openingScanDeadline then
					scanTimedOut = true
					return false
				end
			end
			return true
		end

		local searchOk, searchErr = pcall(function()
			refreshCoinCache()
			searchCoinGeneration = Runtime.CoinGeneration
			local bounds = getCoinBoundsForHideSearch()
			if not bounds or not searchCanContinue() then
				if searchCanContinue() and State.Phase == "opening_hide" then
					State.Status =
						"Chua co CoinVisual de khoanh vung diem cao (heuristic)"
				end
				return
			end

			local descendants = workspace:GetDescendants()
			local margin = CFG.HighestCoinBoundsMargin
			local bestPart = nil
			local bestGeometry = nil
			local bestCenterDistance = math.huge
			for index, instance in ipairs(descendants) do
				if not searchCanContinue() then
					return
				end
				if instance and instance:IsA("BasePart") then
					local positionOk, position = pcall(function()
						return instance.Position
					end)
					local insideBounds = positionOk
						and position.X >= bounds.MinX - margin
							and position.X <= bounds.MaxX + margin
							and position.Z >= bounds.MinZ - margin
							and position.Z <= bounds.MaxZ + margin
					if insideBounds then
						local geometry = getHideCandidateGeometry(instance)
						if geometry then
							local dx = position.X - bounds.CenterX
							local dz = position.Z - bounds.CenterZ
							local centerDistance = dx * dx + dz * dz
							if not bestGeometry
								or geometry.TopY > bestGeometry.TopY + 0.01
								or (
									math.abs(geometry.TopY - bestGeometry.TopY) <= 0.01
									and centerDistance < bestCenterDistance
								) then
								bestPart = instance
								bestGeometry = geometry
								bestCenterDistance = centerDistance
							end
						end
					end
				end
				if index % CFG.HighestScanBatchSize == 0 then
					task.wait()
				end
			end
			descendants = nil
			if not searchCanContinue() then
				return
			end
			State.CoinBounds = bounds
			Runtime.HighestSearchCoinGeneration = searchCoinGeneration
			if bestPart and bestGeometry then
				local currentGeometry = upgradeOnly
					and getHideCandidateGeometry(State.HighestHidePart)
					or nil
				if currentGeometry
					and currentGeometry.TopY >= bestGeometry.TopY - 0.01 then
					return
				end
				State.HighestHidePart = bestPart
				State.HighestHidePosition = bestGeometry.Goal
				State.HighestHideTopY = bestGeometry.TopY
				State.OpeningHideTeleported = false
				State.OpeningHideTeleportAttemptAt = nil
				State.OpeningHideTeleportAttempts = 0
				State.HideTeleported = false
				State.HideTeleportAttemptAt = nil
				State.HideTeleportAttempts = 0
				if State.Phase == "opening_hide" then
					local arrivalWindow = CFG.OpeningHideArrivalTimeout
					local root = getRoot()
					if root then
						local distance =
							(root.Position - bestGeometry.Goal).Magnitude
						-- Uoc luong noi bo de segmented fallback co du thoi gian;
						-- adaptive scheduler/server correction van co the cham hon.
						local adaptiveFactor = CFG.CpuSaver
							and (
								1.25
								* (
									1
									+ math.max(
										0,
										tonumber(CFG.Jitter) or 0
									)
								)
							)
							or 1
						local conservativeSpeed = math.max(
							0.25,
							CFG.MaxStepStuds
								/ (CFG.MoveDelay * adaptiveFactor)
						)
						arrivalWindow = math.max(
							arrivalWindow,
							distance
								/ conservativeSpeed
								+ CFG.HighestArrivalCushion
						)
					end
					State.OpeningHideDeadline =
						os.clock() + arrivalWindow
				end
				pushLog(
					string.format(
						"Da chon mat cao heuristic Y=%.1f quanh %d CoinVisual; "
							.. "source khong xac nhan day la cho an toan",
						bestGeometry.TopY,
						bounds.Count or 0
					)
				)
			elseif State.Phase == "opening_hide" then
				State.Status =
					"Khong thay mat cao hop le trong bien CoinVisual; dang thu lai"
			end
		end)

		if ownsSearch() then
			Runtime.HighestSearchBusy = false
			Runtime.LastHighestSearchAt = os.clock()
			if not searchOk then
				State.LastError = "HighestSearch: " .. tostring(searchErr)
			elseif scanTimedOut and State.Phase == "opening_hide" then
				State.Status =
					"Scan diem cao cham deadline; chuyen collect o tick ke"
			end
		end
	end)
	return true, "started"
end

local EFFECT_CLASSES = {
	ParticleEmitter = true,
	Trail = true,
	Beam = true,
	Fire = true,
	Smoke = true,
	Sparkles = true,
}

local function stripVisualInstance(instance)
	if not CFG.LowRender or not instance or not instance.Parent then
		return
	end

	local className = instance.ClassName
	if className == "Sound" and CFG.MuteAudio then
		local insideCharacter = isPlayerCharacterInstance(instance)
		pcall(function()
			instance.Volume = 0
		end)
		if CFG.DestroyVisualInstances and not insideCharacter then
			if tryDestroy(instance) then
				State.RemovedVisuals = State.RemovedVisuals + 1
			end
		end
		return
	end

	if EFFECT_CLASSES[className] then
		local insideCharacter = isPlayerCharacterInstance(instance)
		pcall(function()
			instance.Enabled = false
		end)
		if CFG.DestroyVisualInstances and not insideCharacter then
			if tryDestroy(instance) then
				State.RemovedVisuals = State.RemovedVisuals + 1
			end
		end
		return
	end

	if className == "Decal" or className == "Texture" then
		local insideCharacter = isPlayerCharacterInstance(instance)
		pcall(function()
			instance.Texture = ""
			instance.Transparency = 1
		end)
		if CFG.DestroyVisualInstances and not insideCharacter then
			if tryDestroy(instance) then
				State.RemovedVisuals = State.RemovedVisuals + 1
			end
		end
		return
	end

	if className == "SurfaceAppearance" then
		local insideCharacter = isPlayerCharacterInstance(instance)
		pcall(function()
			instance.ColorMap = ""
			instance.MetalnessMap = ""
			instance.NormalMap = ""
			instance.RoughnessMap = ""
		end)
		if CFG.DestroyVisualInstances and not insideCharacter then
			if tryDestroy(instance) then
				State.RemovedVisuals = State.RemovedVisuals + 1
			end
		end
		return
	end

	if className == "SpecialMesh" then
		pcall(function()
			instance.TextureId = ""
		end)
		return
	end

	if instance:IsA("BasePart") then
		pcall(function()
			instance.CastShadow = false
		end)
		if className == "MeshPart" then
			pcall(function()
				instance.TextureID = ""
			end)
		end
		if CFG.HideWorldButKeepCollision and not isEssentialWorldPart(instance) then
			pcall(function()
				instance.LocalTransparencyModifier = 1
			end)
		end
	end
end

local function muteSoundInstance(instance)
	if CFG.MuteAudio and instance and instance:IsA("Sound") then
		pcall(function()
			instance.Volume = 0
		end)
	end
end

local function disableLightingInstance(instance)
	if CFG.LowRender and instance and instance:IsA("PostEffect") then
		pcall(function()
			instance.Enabled = false
		end)
	end
end

local function openingHideHasPriority()
	return State.RoundActive and State.Phase == "opening_hide"
end

local function applyLowRender()
	if not ownsRuntime() then
		return
	end
	if Runtime.CleanupBusy
		or Runtime.HighestSearchBusy
		or openingHideHasPriority() then
		Runtime.LowRenderNeedsRescan = true
		return
	end
	Runtime.LowRenderNeedsRescan = false
	Runtime.CleanupBusy = true
	task.spawn(function()
		local interrupted = false
		local cleanupOk, cleanupErr = pcall(function()
			local descendants = workspace:GetDescendants()
			for index, instance in ipairs(descendants) do
				if not ownsRuntime() then
					break
				end
				if Runtime.HighestSearchBusy or openingHideHasPriority() then
					interrupted = true
					break
				end
				pcall(stripVisualInstance, instance)
				if index % 60 == 0 then
					task.wait()
				end
			end
			descendants = nil

			if not ownsRuntime() or interrupted then
				return
			end
			for _, instance in ipairs(Lighting:GetDescendants()) do
				disableLightingInstance(instance)
			end
			local newItemBlur = Lighting:FindFirstChild("NewItemBlur")
			if newItemBlur then
				pcall(function()
					newItemBlur.Enabled = false
				end)
			end
			for _, instance in ipairs(SoundService:GetDescendants()) do
				muteSoundInstance(instance)
			end
			local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
			if playerGui then
				for _, instance in ipairs(playerGui:GetDescendants()) do
					muteSoundInstance(instance)
				end
			end

		end)
		Runtime.CleanupBusy = false
		if not cleanupOk then
			Runtime.LowRenderComplete = false
			Runtime.LowRenderNeedsRescan = false
			State.LastError = "LowRender: " .. tostring(cleanupErr)
		elseif interrupted then
			Runtime.LowRenderComplete = false
			Runtime.LowRenderNeedsRescan = true
			if ownsRuntime() then
				State.Status =
					"Tam dung LowRender de uu tien nup dau round"
			end
		elseif ownsRuntime() then
			Runtime.LowRenderComplete = true
			Runtime.LowRenderNeedsRescan = false
			pushLog("Da strip visual; giu collision va CoinVisual")
		end
	end)

	if not Runtime.VisualHooked then
		Runtime.VisualHooked = true
		connect(workspace.DescendantAdded, function(instance)
			if ownsRuntime() and CFG.LowRender then
				pcall(stripVisualInstance, instance)
			end
		end)
		connect(Lighting.DescendantAdded, disableLightingInstance)
	end
	if not Runtime.AudioHooked then
		Runtime.AudioHooked = true
		connect(SoundService.DescendantAdded, muteSoundInstance)
		local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
		if playerGui then
			connect(playerGui.DescendantAdded, muteSoundInstance)
		end
	end
end

-- Cac GUI name duoc thay truc tiep trong dump PlayerGui hop le.
local CONFIRMED_GAME_GUI = {
	BackpackUI = true,
	CrossPlatform = true,
	Fade = true,
	GameplayControlsUI = true,
	GameTopbar = true,
	InteractGUI = true,
	MainGUI = true,
	Scoreboard = true,
	Scoreboard_Phone = true,
	SpawnFade = true,
	TouchInteractButtons = true,
}

local function purgeConfirmedGameGui()
	if not ownsRuntime() then
		return
	end
	local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end
	for name in pairs(CONFIRMED_GAME_GUI) do
		local child = playerGui:FindFirstChild(name)
		if child then
			local enabledOk = pcall(function()
				child.Enabled = false
			end)
			local visibleOk = pcall(function()
				child.Visible = false
			end)
			if enabledOk or visibleOk then
				State.HiddenGui = State.HiddenGui + 1
			end
		end
	end
	if not Runtime.GameGuiHooked then
		Runtime.GameGuiHooked = true
		connect(playerGui.ChildAdded, function(child)
			if CFG.AutoHideGameGui and CONFIRMED_GAME_GUI[child.Name] then
				task.spawn(function()
					task.wait()
					if ownsRuntime() and child.Parent then
						local enabledOk = pcall(function()
							child.Enabled = false
						end)
						local visibleOk = pcall(function()
							child.Visible = false
						end)
						if enabledOk or visibleOk then
							State.HiddenGui = State.HiddenGui + 1
						end
					end
				end)
			end
		end)
	end
	if ownsRuntime() then
		pushLog("Da an game HUD; khong Destroy de tranh callback nil")
	end
end

-- Best-effort, OFF mac dinh: source xac nhan cac controller nay xu ly
-- pet/audio/weapon/coin visual ma kaitun khong can hien thi. Destroy LocalScript
-- da init KHONG duoc source dam bao se disconnect callback da tao.
local SOURCE_OBSERVED_OPTIONAL_CONTROLLERS = {
	Pets = true,
	PetsNew = true,
	RbxCharacterSounds = true,
	ControllerIcons = true,
	ToolHandleVisuals = true,
	WeaponVisuals = true,
	CoinVisualizer = true, -- kaitun thay scan/spin va delete coin full-bag
}

local function killOptionalControllers()
	if not ownsRuntime() then
		return
	end
	local playerScripts = LocalPlayer:FindFirstChild("PlayerScripts")
	if not playerScripts then
		return
	end
	local targets = {}
	for name in pairs(SOURCE_OBSERVED_OPTIONAL_CONTROLLERS) do
		local object = playerScripts:FindFirstChild(name)
		if object then
			targets[#targets + 1] = object
			for _, descendant in ipairs(object:GetDescendants()) do
				if descendant:IsA("LocalScript") then
					pcall(function()
						descendant.Disabled = true
					end)
				end
			end
			pcall(function()
				if object:IsA("LocalScript") then
					object.Disabled = true
				end
			end)
		end
	end
	task.wait()
	if not ownsRuntime() then
		return
	end
	for _, object in ipairs(targets) do
		if object.Parent then
			if tryDestroy(object) then
				State.KilledControllers = State.KilledControllers + 1
			end
		end
	end

	-- PetsNew.lua xac nhan clone tu ReplicatedStorage.Pets duoc parent vao PetContainer.
	-- Chi xoa child co ten trung template pet; giu container/child khong xac dinh.
	local petContainer = workspace:FindFirstChild("PetContainer")
	local petTemplates = ReplicatedStorage:FindFirstChild("Pets")
	if petContainer and petTemplates then
		for _, petClone in ipairs(petContainer:GetChildren()) do
			if petTemplates:FindFirstChild(petClone.Name) then
				if tryDestroy(petClone) then
					State.RemovedVisuals = State.RemovedVisuals + 1
				end
			end
		end
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local petValue = character and character:FindFirstChild("Pet")
		local petBody = petValue and petValue:FindFirstChild("Body")
		if petBody then
			tryDestroy(petBody)
		end
	end

	pushLog(
		"Da kill optional controller best-effort; callback da init co the van con"
	)
end

local function purgeCaches(forceGC, includeConfirmedGameCache)
	for coin in pairs(Runtime.CoinCache) do
		if not coin or not coin.Parent then
			Runtime.CoinCache[coin] = nil
			Runtime.CoinBlacklist[coin] = nil
		end
	end
	local gameCacheCleared = false
	if includeConfirmedGameCache and type(_G.Cache) == "table" then
		clearTable(_G.Cache)
		gameCacheCleared = true
	end
	local gcRan = false
	if (forceGC or CFG.ForceFullGC) and type(collectgarbage) == "function" then
		gcRan = pcall(function()
			collectgarbage("collect")
		end)
	end
	State.LuaHeapMB = getLuaHeapMB()
	local message = "Da prune weak cache kaitun"
	if gameCacheCleared then
		message = message .. " + _G.Cache image"
	elseif includeConfirmedGameCache then
		message = message .. "; runtime khong co _G.Cache table"
	end
	if forceGC or CFG.ForceFullGC then
		message = message .. (gcRan and " + full GC" or " + GC khong kha dung")
	end
	pushLog(message)
end

local function runHardMapless()
	if not ownsRuntime() or not State.RoundActive or not State.CoinsStartedActive then
		State.MaplessRequestedAt = nil
		return
	end
	if State.Phase == "opening_hide" then
		State.MaplessRequestedAt = os.clock() + 1
		return
	end
	if Runtime.CleanupBusy or Runtime.HighestSearchBusy then
		State.MaplessRequestedAt = os.clock() + 1
		return
	end
	Runtime.CleanupBusy = true
	State.MaplessRequestedAt = nil
	local roundEpoch = State.RoundEpoch
	refreshCoinCache()
	task.spawn(function()
		local function sameRound()
			return ownsRuntime()
				and State.RoundActive
				and State.CoinsStartedActive
				and State.RoundEpoch == roundEpoch
		end
		local cleanupOk, cleanupErr = pcall(function()
			local protectedInstances = setmetatable({}, { __mode = "k" })
			local function protectTree(root)
				if not root or not sameRound() then
					return
				end
				protectedInstances[root] = true
				for _, descendant in ipairs(root:GetDescendants()) do
					protectedInstances[descendant] = true
				end
				local cursor = root.Parent
				while cursor and cursor ~= workspace do
					protectedInstances[cursor] = true
					cursor = cursor.Parent
				end
			end
			for _, tagName in ipairs({ "CoinVisual", "InteractiveBox", "Water" }) do
				if not sameRound() then
					return
				end
				local ok, tagged = pcall(function()
					return CollectionService:GetTagged(tagName)
				end)
				if ok then
					for _, taggedInstance in ipairs(tagged) do
						protectTree(taggedInstance)
					end
				end
			end
			-- Bao ve CoinContainer (main.lua nhat coin = BasePart trong CoinContainer).
			if sameRound() then
				for _, desc in ipairs(workspace:GetDescendants()) do
					if not sameRound() then
						return
					end
					if desc.Name == "CoinContainer" then
						protectTree(desc)
					end
				end
			end
			if not sameRound() then
				return
			end
			local descendants = workspace:GetDescendants()
			for _, instance in ipairs(descendants) do
				if not sameRound() then
					return
				end
				if instance.Name == "TrapVisual" then
					protectTree(instance)
				end
			end
			for index, instance in ipairs(descendants) do
				if not sameRound() then
					return
				end
				local pureVisualPart = instance
					and instance.Parent
					and instance:IsA("BasePart")
					and not instance.CanCollide
					and not instance.CanTouch
					and not instance.CanQuery
				if pureVisualPart
					and not protectedInstances[instance]
					and not isEssentialWorldPart(instance) then
					if tryDestroy(instance) then
						State.RemovedParts = State.RemovedParts + 1
					end
				else
					pcall(stripVisualInstance, instance)
				end
				if index % 40 == 0 then
					task.wait()
				end
			end
			descendants = nil
			if CFG.ForceFullGC then
				pcall(function()
					collectgarbage("collect")
				end)
			end
		end)
		Runtime.CleanupBusy = false
		if not cleanupOk then
			State.LastError = "HardMapless: " .. tostring(cleanupErr)
		elseif sameRound() then
			pushLog(
				"Map Purge xong: giu part Collide/Touch/Query va object bao ve"
			)
		end
	end)
end

--====================================================================
-- 8) GAME EVENTS
--====================================================================
refreshCoinCache()
connect(CollectionService:GetInstanceAddedSignal("CoinVisual"), function(coin)
	cacheCoin(coin)
end)
connect(CollectionService:GetInstanceRemovedSignal("CoinVisual"), function(coin)
	Runtime.CoinCache[coin] = nil
	Runtime.CoinBlacklist[coin] = nil
	if State.TargetCoin == coin then
		setTargetCoin(nil)
	end
end)

if R_CoinCollected then
	connect(R_CoinCollected.OnClientEvent, function(bagId, current, maximum)
		if not ownsRuntime() or not State.RoundActive then
			return
		end
		local id = bagId ~= nil and tostring(bagId) or nil
		local amount = tonumber(current)
		local cap = tonumber(maximum)
		if not id or not amount then
			return
		end
		if amount > 0 then
			State.HadConfirmedCollection = true
		end
		-- Cong don coin earned (session) cho server-hop check.
		local prevAmount = tonumber(State.BagCounts[id]) or 0
		if amount > prevAmount then
			Runtime.TotalCoinsEarned = (Runtime.TotalCoinsEarned or 0)
				+ (amount - prevAmount)
			-- Bang chung claim THAT (server xac nhan) -> fast claim dang hoat dong.
			Runtime.LastCoinCollectedAt = os.clock()
			Runtime.FastClaimFails = 0
		end
		State.BagCounts[id] = amount
		if cap then
			State.BagCaps[id] = cap
			if amount >= cap then
				State.FullBags[id] = true
				local roundEpoch = State.RoundEpoch
				task.spawn(function()
					task.wait(0.05)
					if ownsRuntime() and State.RoundActive
						and State.RoundEpoch == roundEpoch
						and State.FullBags[id] then
						destroyFullBagCoins(id)
					end
				end)
			end
		end
		recalculateCollected()
		if State.TargetCoin and coinBagId(State.TargetCoin) == id
			and State.FullBags[id] then
			setTargetCoin(nil)
		end
	end)
end

if R_CoinsStarted then
	connect(R_CoinsStarted.OnClientEvent, function(activeBags)
		resetRoundState("waiting")
		State.RoundActive = true
		State.CoinsStartedActive = true
		-- Ep rescan CoinContainer NGAY (map moi) de bat coin lien, khong cho cache.
		Runtime.LastContainerScan = 0
		Runtime.CoinContainers = nil
		-- XAC NHAN THAT: CoinBagContainerScript.lua:51-59 doc p11[bagName] ~= nil.
		-- activeBags la table key theo bagName (= bagId cua CoinCollected), gia tri
		-- danh dau bag do dang active. Nap vao ActiveBags de allKnownBagsFull() dung.
		if type(activeBags) == "table" then
			for bagId in pairs(activeBags) do
				State.ActiveBags[tostring(bagId)] = true
			end
		end
		refreshCoinCache()
		if CFG.HardMapless then
			State.MaplessRequestedAt = os.clock() + 1
		end
		refreshRole()
		local openingHide = beginRoundMovement()
		pushLog(
			openingHide
				and "CoinsStarted -> nup diem cao truoc khi collect"
				or "CoinsStarted -> round collect"
		)
	end)
end

if R_LoadingMap then
	connect(R_LoadingMap.OnClientEvent, function()
		Runtime.AllowInitialCoinFallbackUntil = nil
		State.RoundActive = false
		resetRoundState("loading")
		invalidateRoundPlayerData()
		pushLog("LoadingMap")
	end)
end

if R_RoundStart then
	connect(R_RoundStart.OnClientEvent, function(_, playerData)
		if type(playerData) == "table" then
			State.FallbackPlayerData = playerData
			State.HasEventPlayerData = true
			State.EventPlayerDataGeneration = State.PlayerDataGeneration
			if CurrentRoundClient then
				CurrentRoundClient.PlayerData = playerData
			end
		end
		State.RoundActive = true
		refreshRole()
		if State.Phase == "waiting" or State.Phase == "loading" then
			beginRoundMovement()
		end
	end)
end

if R_RoleSelect then
	connect(R_RoleSelect.OnClientEvent, function(role, _, _, _, gamemode)
		-- RoleSelector.lua: p24=tham so 1, p28=tham so 5.
		if role ~= nil then
			State.Role = tostring(role)
		end
		if gamemode ~= nil then
			State.Gamemode = tostring(gamemode)
		end
		-- RoleSelect con co countdown trong source; khong bat movement tai day.
	end)
end

local function closeRound(reason)
	Runtime.AllowInitialCoinFallbackUntil = nil
	State.RoundActive = false
	resetRoundState("waiting")
	invalidateRoundPlayerData()
	pushLog(reason)
end

if R_VictoryScreen then
	connect(R_VictoryScreen.OnClientEvent, function()
		closeRound("VictoryScreen -> dung movement")
	end)
end
if R_RoundEndFade then
	connect(R_RoundEndFade.OnClientEvent, function()
		closeRound("RoundEndFade -> dung movement")
	end)
end

if R_PlayerDataChanged then
	connect(R_PlayerDataChanged.OnClientEvent, function(playerData)
		if type(playerData) == "table" then
			State.FallbackPlayerData = playerData
			State.HasEventPlayerData = true
			State.EventPlayerDataGeneration = State.PlayerDataGeneration
			if CurrentRoundClient then
				CurrentRoundClient.PlayerData = playerData
			end
		end
		refreshRole()
	end)
end
connect(LocalPlayer.CharacterAdded, function()
	setTargetCoin(nil)
	-- Nhan vat moi khong anchor/khong noclip: reset co de khong thao tac nham part cu.
	cancelCoinTween()
	Runtime.CoinAnchorActive = false
	clearTable(Runtime.NoclipDisabled)
	State.OpeningHideTeleported = false
	State.OpeningHideTeleportAttemptAt = nil
	State.OpeningHideTeleportAttempts = 0
	State.OpeningHideUntil = nil
	State.HideTeleported = false
	State.HideTeleportAttemptAt = nil
	State.HideTeleportAttempts = 0
	task.spawn(function()
		task.wait(0.5)
		if ownsRuntime() then
			refreshRole()
		end
	end)
end)

--====================================================================
-- 9) CENTRAL SCHEDULER + PROFILING
--====================================================================
local IMPORTANT_TASKS = {
	FarmMove = true,
	CoinScan = true,
	FpsCap = true, -- khong cho adaptiveDelay keo dai nhip re-apply cap
}

local function adaptiveDelay(name, baseDelay)
	local delay = tonumber(baseDelay) or 1
	-- Task QUAN TRONG (FarmMove/CoinScan/FpsCap): giu DUNG baseDelay, KHONG phat theo
	-- FPS va KHONG jitter -> CHECK COIN NHANH. FPS thap la do cap co y (TargetFPS),
	-- khong phai lag that nen khong duoc lam cham farm.
	if IMPORTANT_TASKS[name] then
		return math.max(delay, 0.02)
	end
	if CFG.CpuSaver then
		if State.FPS > 0 and State.FPS < CFG.CriticalFpsThreshold then
			delay = delay * 2.4
		elseif State.FPS > 0 and State.FPS < CFG.LowFpsThreshold then
			delay = delay * 1.6
		else
			delay = math.max(delay * 1.2, 0.2)
		end
		local jitter = tonumber(CFG.Jitter) or 0
		if jitter > 0 then
			delay = delay * (1 + (math.random() * 2 - 1) * jitter)
		end
	end
	return math.max(delay, 0.02)
end

local function addTask(name, callback, getDelay)
	Runtime.TaskIndex = Runtime.TaskIndex + 1
	Runtime.Tasks[#Runtime.Tasks + 1] = {
		Name = name,
		Callback = callback,
		GetDelay = getDelay,
		NextAt = os.clock() + math.min((Runtime.TaskIndex - 1) * 0.05, 0.5),
	}
	Runtime.TaskStatus[name] = {
		Runs = 0,
		LastMs = 0,
		MaxMs = 0,
		LastError = nil,
	}
end

local function applyFpsCap()
	local capFunction = nil
	if type(setfpscap) == "function" then
		capFunction = setfpscap
	elseif type(set_fps_cap) == "function" then
		capFunction = set_fps_cap
	end
	if capFunction then
		local ok = pcall(
			capFunction,
			math.max(1, math.floor(tonumber(CFG.TargetFPS) or 10))
		)
		if ok then
			Runtime.FpsCapApplied = true
		end
	end
end

-- Tiet kiem CPU/GPU o muc ENGINE (API engine/executor, khong dung logic game):
-- tat shadow, ha quality render, tat han ve 3D neu config bat.
-- Tat ca deu pcall (executor khong ho tro thi bo qua) + restore trong shutdown().
local function applyEngineSaver()
	if CFG.DisableGlobalShadows then
		pcall(function()
			if Runtime.OldGlobalShadows == nil then
				Runtime.OldGlobalShadows = Lighting.GlobalShadows
			end
			Lighting.GlobalShadows = false
		end)
	end
	if CFG.LowQualityRendering then
		pcall(function()
			settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
		end)
	end
	if CFG.Disable3DRender and not Runtime.Render3DDisabled then
		local ok = pcall(function()
			RunService:Set3dRenderingEnabled(false)
		end)
		if ok then
			Runtime.Render3DDisabled = true
			pushLog("Da tat ve 3D (Disable3DRender) - GUI van hien")
		end
	end
end

-- HARD-LOCK FPS (yeu cau chong: gan chet vao TargetFPS, khong troi len xuong).
-- Re-apply setfpscap MOI FRAME (throttle nhe) qua RenderStepped, thay vi doi task
-- FpsCap 5s/lan (con bi adaptiveDelay keo dai luc FPS thap). Vay FPS bi khoa cung.
do
	local capFunction = (type(setfpscap) == "function" and setfpscap)
		or (type(set_fps_cap) == "function" and set_fps_cap)
		or nil
	if capFunction then
		local lastApply = 0
		local conn = RunService.RenderStepped:Connect(function()
			if not Runtime.Alive then
				return
			end
			local now = os.clock()
			if now - lastApply < 0.2 then
				return
			end
			lastApply = now
			pcall(capFunction, math.max(1, math.floor(tonumber(CFG.TargetFPS) or 10)))
			Runtime.FpsCapApplied = true
		end)
		Runtime.Connections[#Runtime.Connections + 1] = conn
	end
end

local function coinScanTask()
	local now = os.clock()
	if now - (Runtime.LastFullCoinRefresh or 0) >= 12 then
		refreshCoinCache()
	end
	if not State.RoundActive and State.Phase == "waiting"
		and Runtime.AllowInitialCoinFallbackUntil
		and hasLocalRoundData()
		and now <= Runtime.AllowInitialCoinFallbackUntil then
		for coin in pairs(Runtime.CoinCache) do
			-- RoundEnd khong phai availability flag trong source; chi loai no
			-- o fallback heuristic de giam nguy co nham coin cu cuoi round.
			if coinAvailable(coin, now)
				and coin:GetAttribute("RoundEnd") ~= true then
				State.RoundActive = true
				local openingHide = beginRoundMovement()
				pushLog(
					openingHide
						and "Inject giua round -> nup diem cao truoc khi collect"
						or "Inject giua round -> heuristic bang PlayerData + CoinVisual"
				)
				break
			end
		end
	end
	if State.RoundActive and State.Phase == "collect" and CFG.AvoidMurderer
		and claimableCoinStillValid(State.TargetCoin, now) then
		local murdererRoot = getMurdererRoot()
		-- Chi bo target khi murderer SAT coin dang nham (duoi HardAvoid), roi picker
		-- se chon coin khac. Khong bo chi vi murderer trong ~50st de con nhat duoc.
		if murdererRoot
			and (State.TargetCoin.Position - murdererRoot.Position).Magnitude
				< CFG.MurdererHardAvoid then
			Runtime.CoinBlacklist[State.TargetCoin] = now + CFG.RetryDelay
			setTargetCoin(nil)
		end
	end
	if State.RoundActive and State.Phase == "collect"
		and not claimableCoinStillValid(State.TargetCoin, now)
		and now >= (Runtime.NextChooseAt or 0) then
		local nearest, count = chooseClaimableCoin()
		State.CoinsLeft = count
		setTargetCoin(nearest)
		-- Khong co coin nao -> nghi 0.3s roi moi quet chon lai. CoinScanDelay=0.05
		-- ma quet 20 lan/s luc map trong la nguyen nhan lam do GUI; co coin thi van
		-- chon NGAY tick ke tiep (khong cham farm).
		Runtime.NextChooseAt = (nearest == nil) and (now + 0.3) or 0
	elseif State.RoundActive and State.Phase ~= "collect" then
		local count = countClaimableCoins()
		State.CoinsLeft = count
		if count > 0 then
			State.HadCoinThisRound = true
			State.NoCoinSince = nil
		end
	end
	if State.RoundActive and State.CoinsStartedActive and State.MaplessRequestedAt
		and now >= State.MaplessRequestedAt then
		runHardMapless()
	end
end

local function updateFpsSample()
	local now = os.clock()
	local elapsed = now - Runtime.FpsSampleAt
	if elapsed >= 1 then
		State.FPS = Runtime.FpsFrames / elapsed
		Runtime.FpsFrames = 0
		Runtime.FpsSampleAt = now
	end
end

local function memWatch()
	State.LuaHeapMB = getLuaHeapMB()
	if State.LuaHeapMB >= CFG.LuaHeapSoftMB then
		purgeCaches(false, false)
	end
end

local function memJanitor()
	local now = os.clock()
	for coin, retryAt in pairs(Runtime.CoinBlacklist) do
		if not coin or not coin.Parent or retryAt <= now then
			Runtime.CoinBlacklist[coin] = nil
		end
	end
	for coin in pairs(Runtime.CoinCache) do
		if not coin or not coin.Parent then
			Runtime.CoinCache[coin] = nil
		end
	end
	-- Prune container da bi huy (map cu) khoi cache de vong lap coin khong duyet rac.
	if type(Runtime.CoinContainers) == "table" then
		local live = {}
		for _, container in ipairs(Runtime.CoinContainers) do
			if container and container.Parent then
				live[#live + 1] = container
			end
		end
		Runtime.CoinContainers = live
	end
	if #Runtime.Logs > 40 then
		while #Runtime.Logs > 40 do
			table.remove(Runtime.Logs, 1)
		end
	end
	local liveConnections = {}
	for _, connection in ipairs(Runtime.Connections) do
		local ok, connected = pcall(function()
			return connection.Connected
		end)
		if ok and connected then
			liveConnections[#liveConnections + 1] = connection
		end
	end
	Runtime.Connections = liveConnections
end

connect(RunService.Heartbeat, function()
	Runtime.FpsFrames = Runtime.FpsFrames + 1
end)

-- NOCLIP (chong yeu cau). Chi ep CanCollide=false luc dang di nhat coin (phase
-- collect) de teleport khong bi vat can; luc nup thi restore de con dung tren mat.
local function noclipShouldRun()
	-- Noclip suot phase collect, TRU khi dang tam unanchor cho .Touched fire.
	-- Luc WaitingForTouch can CanCollide=true de physics detect coin pickup.
	return CFG.Noclip
		and State.RoundActive
		and State.Phase == "collect"
		and not Runtime.WaitingForTouch
end

local function restoreNoclipParts()
	for part in pairs(Runtime.NoclipDisabled) do
		if part and part.Parent then
			pcall(function()
				part.CanCollide = true
			end)
		end
		Runtime.NoclipDisabled[part] = nil
	end
end

connect(RunService.Stepped, function()
	if not ownsRuntime() then
		return
	end
	if not noclipShouldRun() then
		-- Ra khoi phase collect: tra lai CanCollide cho dung cac part minh da tat.
		if next(Runtime.NoclipDisabled) ~= nil then
			restoreNoclipParts()
		end
		return
	end
	local character = getCharacter()
	if not character then
		return
	end
	pcall(function()
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") and part.CanCollide then
				part.CanCollide = false
				-- Chi ghi part von CanCollide=true de restore dung trang thai goc.
				Runtime.NoclipDisabled[part] = true
			end
		end
	end)
end)

addTask("FarmMove", farmMoveStep, function()
	return State.RoundActive and CFG.MoveDelay or 1
end)
addTask("CoinScan", coinScanTask, function()
	return State.RoundActive and CFG.CoinScanDelay or 2
end)
addTask("RoleRefresh", function()
	if State.RoundActive then
		refreshRole()
	end
end, function()
	return State.RoundActive and 1 or 5
end)
addTask("FpsSample", updateFpsSample, function()
	return 1
end)
addTask("FpsCap", applyFpsCap, function()
	return 5
end)
addTask("MemWatch", memWatch, function()
	return 20
end)
addTask("MemJanitor", memJanitor, function()
	return 60
end)
addTask("LowRenderRetry", function()
	if CFG.LowRender
		and not Runtime.LowRenderComplete
		and (Runtime.LowRenderNeedsRescan or not Runtime.VisualHooked) then
		applyLowRender()
	end
end, function()
	return Runtime.LowRenderNeedsRescan and 1 or 3
end)

-- Auto mua + mo box khi du so (OpenCrate yield -> spawn coroutine, guard BoxBusy).
addTask("AutoBox", function()
	if not CFG.AutoBuyBox or Runtime.BoxBusy then
		return
	end
	if getShells() < (tonumber(CFG.BoxPrice) or math.huge) then
		return
	end
	Runtime.BoxBusy = true
	task.spawn(function()
		pcall(doAutoBuyBox)
		Runtime.BoxBusy = false
	end)
end, function()
	return 3
end)

-- Server hop khi farm cham: moi TIME_TO_CHECK_COIN_EARNED giay, neu earned trong
-- chu ky < HOP_WHEN_COIN_EARNED_LOWER thi doi server (reload). Mac dinh TAT.
addTask("ServerHop", function()
	if not CFG.AutoServerHop then
		return
	end
	local period = tonumber(CFG.TIME_TO_CHECK_COIN_EARNED) or 0
	if period <= 0 then
		return
	end
	local now = os.clock()
	if not Runtime.HopCheckAt then
		Runtime.HopCheckAt = now + period
		Runtime.HopBaseline = Runtime.TotalCoinsEarned or 0
		return
	end
	if now < Runtime.HopCheckAt then
		return
	end
	local earned = (Runtime.TotalCoinsEarned or 0) - (Runtime.HopBaseline or 0)
	Runtime.HopCheckAt = now + period
	Runtime.HopBaseline = Runtime.TotalCoinsEarned or 0
	if earned < (tonumber(CFG.HOP_WHEN_COIN_EARNED_LOWER) or 0) then
		pushLog(string.format(
			"Farm cham (earned %d < %d trong %ds) -> hop server",
			earned,
			tonumber(CFG.HOP_WHEN_COIN_EARNED_LOWER) or 0,
			period
		))
		doServerHop()
	end
end, function()
	return 15
end)

-- Auto change acc (logic bipbeo.lua, da fix khong chan scheduler): theo doi quest
-- DAILY. Xong TOAN BO moc daily (Progress >= ChallengeAmount cuoi) VA het so mua
-- box (AutoBox da mua het) -> call autoswap 1 LAN:
--   ra Godly (Icecream) -> option havegodly; khong -> option no godly.
-- KHONG doi BoxesOpened phien nay: acc da xong daily + mo box tu hom truoc, vao
-- lai (phien moi 0 box, 0 so) van doi duoc ngay.
local lastDailyProgress = -1
addTask("AutoChangeAcc", function()
	local info = getDailyQuestInfo()
	if not info then
		return
	end
	-- Cap nhat tien do cho GUI + log khi progress doi (khong spam).
	Runtime.DailyQuestProgressText = string.format(
		"Moc %d/%d (%d/%d)",
		info.TiersDone, info.TierCount, info.Progress, info.FinalTarget
	)
	if info.Progress ~= lastDailyProgress then
		lastDailyProgress = info.Progress
		pushLog(string.format(
			"Daily %s: %s%s",
			tostring(info.Name),
			Runtime.DailyQuestProgressText,
			info.Progress >= info.FinalTarget
				and " -> XONG HET (het luot hom nay)"
				or " -> van con lam duoc"
		))
	end
	if not CFG.AutoChangeAcc or Runtime.SwapCalled then
		return
	end
	-- Chua xong het moc daily -> chua doi (acc con luot lam nhiem vu hom nay).
	if info.FinalTarget <= 0 or info.Progress < info.FinalTarget then
		return
	end
	-- Con so >= gia box -> de AutoBox mua + mo HET truoc roi moi doi.
	if getShells() >= (tonumber(CFG.BoxPrice) or math.huge) then
		return
	end
	Runtime.SwapCalled = true
	local option = Runtime.GodlyReported
		and CFG.AutoSwapOptionHaveGodly
		or CFG.AutoSwapOptionNoGodly
	-- SwapCalled=true TRUOC khi cho -> task 10s khong ban trung lan 2 trong luc doi.
	pushLog("DU DIEU KIEN doi acc (xong daily + het so) -> cho 60s roi call autoswap")
	task.spawn(function()
		task.wait(60) -- dem 60s cho server luu/on dinh truoc khi doi acc
		if not ownsRuntime() then
			return
		end
		local ok = callAutoSwap(option)
		pushLog("Het 60s cho -> autoswap option "
			.. tostring(option) .. (ok and " (da gui)" or " (loi/khong gui)"))
	end)
end, function()
	return 10
end)

--====================================================================
-- 10) FULL-SCREEN GUI CHI DOC: THONG KE + LOGS
-- GUI name KHONG DUOC la "ESP" (Leaderboard.lua co check ten nay).
--====================================================================
local function createGui()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui", 15)
	if not playerGui or not ownsRuntime() then
		pushLog("Khong tim thay PlayerGui")
		return nil
	end
	installEspNameGuard(playerGui)

	local old = playerGui:FindFirstChild("ThieuNangHub")
	if old then
		tryDestroy(old)
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "ThieuNangHub"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	Runtime.Gui = gui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Position = UDim2.new(0, 0, 0, 0)
	root.Size = UDim2.new(1, 0, 1, 0)
	root.BackgroundColor3 = Color3.fromRGB(12, 8, 20)
	root.BackgroundTransparency = 0
	root.BorderSizePixel = 0
	root.Parent = gui

	-- Cot thong tin dong GIUA man hinh, xep DOC, moi dong co ICON (emoji).
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.45, 0)
	panel.Size = UDim2.new(0, 640, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundTransparency = 1
	panel.Parent = root

	local panelLayout = Instance.new("UIListLayout")
	panelLayout.Padding = UDim.new(0, 10)
	panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
	panelLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	panelLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	panelLayout.Parent = panel

	local function makeRow(order, height, text, color, size, bold)
		local label = Instance.new("TextLabel")
		label.LayoutOrder = order
		label.Size = UDim2.new(1, 0, 0, height)
		label.BackgroundTransparency = 1
		label.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
		label.TextSize = size or 18
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextYAlignment = Enum.TextYAlignment.Center
		label.TextWrapped = true
		label.RichText = true
		label.TextColor3 = color or Color3.fromRGB(230, 235, 245)
		label.Text = text or ""
		label.Parent = panel
		return label
	end

	-- Title neon TIM tren cung — chat rieng Thieu Nang (khac style DuckHub vang).
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.AnchorPoint = Vector2.new(0.5, 0)
	titleLabel.Position = UDim2.new(0.5, 0, 0, 16)
	titleLabel.Size = UDim2.new(1, -20, 0, 64)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.LuckiestGuy
	titleLabel.TextSize = 48
	titleLabel.TextColor3 = Color3.fromRGB(188, 111, 255)
	titleLabel.TextStrokeColor3 = Color3.fromRGB(60, 20, 110)
	titleLabel.TextStrokeTransparency = 0.35
	titleLabel.Text = "discord.gg/thieunanghub"
	titleLabel.Parent = root

	-- Duong ke TIM phan cach cac khoi info.
	local function makeSeparator(order)
		local line = Instance.new("Frame")
		line.Name = "Sep" .. tostring(order)
		line.LayoutOrder = order
		line.Size = UDim2.new(1, -36, 0, 2)
		line.BackgroundColor3 = Color3.fromRGB(140, 80, 220)
		line.BackgroundTransparency = 0.15
		line.BorderSizePixel = 0
		line.Parent = panel
	end

	makeRow(1, 28, "🧠  Thieu Nang Hub  •  MM2 Kaitun", Color3.fromRGB(255, 130, 200), 20, true)
	local accountLabel = makeRow(2, 30, "", Color3.fromRGB(120, 230, 255), 22, true)
	makeSeparator(3)
	local phaseLabel = makeRow(4, 28, "", Color3.fromRGB(235, 235, 245), 19, true)
	local murdererLabel = makeRow(5, 28, "", Color3.fromRGB(255, 95, 120), 19, true)
	local coinLabel = makeRow(6, 36, "", Color3.fromRGB(255, 200, 60), 26, true)
	local shellLabel = makeRow(7, 28, "", Color3.fromRGB(80, 235, 190), 20, true)
	local passLabel = makeRow(8, 28, "", Color3.fromRGB(200, 170, 255), 19, true)
	local dailyLabel = makeRow(9, 28, "", Color3.fromRGB(255, 180, 90), 19, true)
	local perfLabel = makeRow(10, 22, "", Color3.fromRGB(140, 190, 170), 14, false)
	local statusLabel = makeRow(11, 44, "", Color3.fromRGB(255, 210, 105), 15, false)
	makeSeparator(12)
	local uptimeLabel = makeRow(13, 26, "", Color3.fromRGB(180, 190, 220), 18, true)

	-- Logs NHO dock day man hinh: CHI tao khi DevDebug bat (console debug ngoai).
	local logLabel = nil
	if CFG.DevDebug then
		local logFrame = Instance.new("Frame")
		logFrame.Name = "LogFrame"
		logFrame.AnchorPoint = Vector2.new(0.5, 1)
		logFrame.Position = UDim2.new(0.5, 0, 1, -8)
		logFrame.Size = UDim2.new(0, 660, 0, 128)
		logFrame.BackgroundColor3 = Color3.fromRGB(12, 15, 20)
		logFrame.BackgroundTransparency = 0.1
		logFrame.BorderSizePixel = 0
		logFrame.Parent = root
		Instance.new("UICorner", logFrame).CornerRadius = UDim.new(0, 8)

		local logPad = Instance.new("UIPadding")
		logPad.PaddingTop = UDim.new(0, 6)
		logPad.PaddingLeft = UDim.new(0, 10)
		logPad.PaddingRight = UDim.new(0, 10)
		logPad.PaddingBottom = UDim.new(0, 6)
		logPad.Parent = logFrame

		logLabel = Instance.new("TextLabel")
		logLabel.Name = "Logs"
		logLabel.Size = UDim2.new(1, 0, 1, 0)
		logLabel.BackgroundTransparency = 1
		logLabel.Font = Enum.Font.Code
		logLabel.TextSize = 12
		logLabel.TextXAlignment = Enum.TextXAlignment.Left
		logLabel.TextYAlignment = Enum.TextYAlignment.Bottom
		logLabel.TextWrapped = true
		logLabel.TextColor3 = Color3.fromRGB(150, 200, 160)
		logLabel.Text = ""
		logLabel.Parent = logFrame
	end

	local function applyResponsive()
		local w = root.AbsoluteSize.X
		local narrow = w < 700
		panel.Size = UDim2.new(0, narrow and math.max(300, w - 24) or 640, 0, 0)
		titleLabel.TextSize = narrow and 30 or 48
	end
	applyResponsive()
	connect(root:GetPropertyChangedSignal("AbsoluteSize"), applyResponsive)

	-- Nut HIDE/SHOW goc TRAI TREN: nam truc tiep trong gui (KHONG trong root) de khi
	-- an root (man den) nut van con tren man hinh ma bam lai duoc.
	local toggleBtn = Instance.new("TextButton")
	toggleBtn.Name = "ToggleGui"
	toggleBtn.Position = UDim2.new(0, 8, 0, 8)
	toggleBtn.Size = UDim2.new(0, 96, 0, 32)
	toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 22, 70)
	toggleBtn.BackgroundTransparency = 0.15
	toggleBtn.BorderSizePixel = 0
	toggleBtn.Font = Enum.Font.GothamBold
	toggleBtn.TextSize = 15
	toggleBtn.TextColor3 = Color3.fromRGB(188, 111, 255)
	toggleBtn.Text = "🙈 HIDE"
	toggleBtn.ZIndex = 50
	toggleBtn.AutoButtonColor = true
	toggleBtn.Parent = gui
	do
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = toggleBtn
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(140, 80, 220)
		stroke.Thickness = 1.5
		stroke.Transparency = 0.2
		stroke.Parent = toggleBtn
	end

	local function setGuiVisible(visible)
		root.Visible = visible
		toggleBtn.Text = visible and "🙈 HIDE" or "👁 SHOW"
		if visible then
			-- GUI hien lai -> tat ve 3D lai theo config (tiet kiem nhu cu).
			applyEngineSaver()
		elseif Runtime.Render3DDisabled then
			-- An GUI de xem game: bat lai ve 3D, khong thi chi thay man hinh trang.
			local ok = pcall(function()
				RunService:Set3dRenderingEnabled(true)
			end)
			if ok then
				Runtime.Render3DDisabled = false
				pushLog("An GUI -> bat lai ve 3D de xem game")
			end
		end
	end
	connect(toggleBtn.MouseButton1Click, function()
		setGuiVisible(not root.Visible)
	end)
	-- CHI cho RightControl bat/tat GUI khi getgenv config bat HideShow = true.
	connect(UserInputService.InputBegan, function(input, gameProcessed)
		if not gameProcessed
			and CFG.HideShow
			and input.KeyCode == CFG.ToggleKey then
			setGuiVisible(not root.Visible)
		end
	end)

	Runtime.GuiRefs = {
		Root = root,
		Account = accountLabel,
		Phase = phaseLabel,
		Murderer = murdererLabel,
		Coin = coinLabel,
		Shell = shellLabel,
		Pass = passLabel,
		Daily = dailyLabel,
		Perf = perfLabel,
		Status = statusLabel,
		Uptime = uptimeLabel,
		Log = logLabel,
	}
	return gui
end

local function refreshGui()
	local refs = Runtime.GuiRefs
	if not refs.Root or not refs.Root.Parent or not refs.Root.Visible then
		return
	end

	local level = getPlayerLevel()
	refs.Account.Text = "👑  " .. getAccountName()
		.. "   •   Lv " .. (level and tostring(level) or "?")

	refs.Phase.Text = "😈  Phase: " .. tostring(State.Phase)
		.. "   |   🎭 Role: " .. tostring(State.Role)
		.. " (" .. tostring(State.Gamemode) .. ")"
	refs.Murderer.Text = "🗡  Murderer: " .. tostring(State.MurdererName or "?")
		.. "   •   " .. (State.MurdererDistance >= 0
			and (string.format("%.0f", State.MurdererDistance) .. " st")
			or "? st")
	refs.Coin.Text = "💰  Coin: " .. tostring(State.Collected)
		.. "   •   con: " .. tostring(State.CoinsLeft)
		.. "   •   tong: " .. tostring(Runtime.TotalCoinsEarned or 0)
	refs.Shell.Text = "🌊  Shells: " .. tostring(getShells())
		.. "/" .. tostring(CFG.BoxPrice)
		.. "   |   📦 Box: " .. tostring(Runtime.BoxesOpened or 0)
		.. (State.GodlyItem and ("   •   ✨ GODLY: " .. tostring(State.GodlyItem)) or "")
	local tier = getBattlePassTier()
	local shopCoins = getShopCoins()
	refs.Pass.Text = "🎫  BP Tier: " .. (tier and tostring(tier) or "?")
		.. "   |   🏦 Coin shop: " .. (shopCoins and tostring(shopCoins) or "?")
	refs.Daily.Text = "📅  Daily: "
		.. (Runtime.DailyQuestProgressText or "dang doc...")
	refs.Perf.Text = string.format(
		"⚙  FPS %.0f   •   Heap %.0f MB   •   noclip %s",
		State.FPS,
		State.LuaHeapMB,
		tostring(CFG.Noclip)
	)
	refs.Status.Text = "📢  " .. tostring(State.Status)
		.. (State.LastError and ("\n⚠ " .. State.LastError) or "")

	local up = math.max(0, os.clock() - (Runtime.StartTime or os.clock()))
	refs.Uptime.Text = string.format(
		"⏳  Time: %02d:%02d:%02d",
		math.floor(up / 3600),
		math.floor((up % 3600) / 60),
		math.floor(up % 60)
	)

	-- Logs chi cap nhat khi DevDebug tao ra khung log (refs.Log ~= nil).
	if refs.Log then
		local n = #Runtime.Logs
		local startI = math.max(1, n - 6)
		local lines = {}
		for i = startI, n do
			lines[#lines + 1] = Runtime.Logs[i]
		end
		refs.Log.Text = #lines > 0 and table.concat(lines, "\n") or "Chua co log."
	end
end

addTask("GuiUpdate", refreshGui, function()
	-- 1s la du cho info; do 1 nua CPU refresh GUI so voi 0.5s.
	local root = Runtime.GuiRefs.Root
	return root and root.Visible and 1 or 3
end)

--====================================================================
-- 11) SHUTDOWN + BOOT
--====================================================================
Runtime.Config = CFG
Runtime.State = State

if not ownsRuntime() then
	return
end
local gui = createGui()
if not gui then
	if ownsRuntime() then
		shutdown("khong tao duoc GUI")
	end
	return
end
if not ownsRuntime() then
	return
end
refreshRole()
refreshCoinCache()
State.LuaHeapMB = getLuaHeapMB()
Runtime.AllowInitialCoinFallbackUntil = os.clock() + 10
applyFpsCap()
applyEngineSaver()
purgeCaches(CFG.ForceFullGC, CFG.ClearImageCacheOnBoot)

Runtime.Worker = task.spawn(function()
	while ownsRuntime() do
		local now = os.clock()
		local nearestDue = now + 1
		for _, scheduled in ipairs(Runtime.Tasks) do
			if now >= scheduled.NextAt then
				local status = Runtime.TaskStatus[scheduled.Name]
				local started = os.clock()
				local ok, err = pcall(scheduled.Callback)
				local elapsedMs = (os.clock() - started) * 1000
				status.Runs = status.Runs + 1
				status.LastMs = elapsedMs
				if elapsedMs > status.MaxMs then
					status.MaxMs = elapsedMs
				end
				if not ok then
					status.LastError = tostring(err)
					State.LastError = scheduled.Name .. ": " .. tostring(err)
				end

				local baseDelay = 1
				local delayOk, delayValue = pcall(scheduled.GetDelay)
				if delayOk then
					baseDelay = tonumber(delayValue) or 1
				end
				scheduled.NextAt = os.clock()
					+ adaptiveDelay(scheduled.Name, baseDelay)
			end
			if scheduled.NextAt < nearestDue then
				nearestDue = scheduled.NextAt
			end
		end

		local waitTime = math.clamp(nearestDue - os.clock(), 0.02, 1)
		task.wait(waitTime)
	end
end)

task.spawn(function()
	-- Optional controller luon OFF mac dinh; chi chay neu config duoc sua ro rang.
	if CFG.AutoKillVisualControllers and ownsRuntime() then
		killOptionalControllers()
	end
	if CFG.AutoHideGameGui and ownsRuntime() then
		purgeConfirmedGameGui()
	end
	if CFG.LowRender and ownsRuntime() then
		applyLowRender()
	end
end)

pushLog(
	"Thieu Nang Hub da chay. Config qua getgenv().ThieuNangHub "
		.. "(HideShow de bat/tat GUI, DevDebug de hien logs)."
)
