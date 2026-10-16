--[[
    ═══════════════════════════════════════════════════════════
    AXK HUB — Final Edition
    ═══════════════════════════════════════════════════════════

    Architecture:
    ├── Core
    │   ├── Services (Players, RunService, etc.)
    │   ├── State (كل الحالات في جدول واحد)
    │   └── Config (الإعدادات الافتراضية)
    │
    ├── Systems
    │   ├── RemoteScanner (ReplicatedStorage فقط)
    │   ├── RemoteCaller (task.spawn + pcall)
    │   ├── HatchLoop (Toggle-based)
    │   ├── EquipLoop
    │   ├── SellLoop
    │   ├── ClaimLoop (جديد)
    │   └── LightingLock (task.wait(1))
    │
    ├── Safety
    │   ├── isCharReady() (فحص الجاهزية)
    │   ├── safeWait() (Jitter)
    │   ├── BLACKLIST (Robux/Scam)
    │   └── pcall في كل remote
    │
    └── UI
        ├── Rayfield
        └── 5 تابات (Home, Hatch, Equip, Claim, Misc)

    Removed:
    - FakeSlowWalk (kick guarantee with Server Authority)
    - Drawing ESP (memory leak)
    - Teleport (kick)
    - Speed/Fly (kick)

    Safe:
    - Auto Hatch (official remote)
    - Auto Equip
    - Auto Sell
    - Auto Claim
    - Lighting (locked loop)
    - Anti-AFK

    Discord: https://discord.gg/9wTaNyJ2z
    ═══════════════════════════════════════════════════════════
--]]

-- ═══════════════════════════════════════════════
-- SERVICES
-- ═══════════════════════════════════════════════
local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting       = game:GetService("Lighting")
local StarterGui     = game:GetService("StarterGui")
local VirtualUser    = game:GetService("VirtualUser")
local HttpService    = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")

local LP = Players.LocalPlayer

-- ═══════════════════════════════════════════════
-- CONFIGURATION
-- ═══════════════════════════════════════════════
local CONFIG = {
    DISCORD_URL = "https://discord.gg/9wTaNyJ2z",
    SCAN_DELAY  = 5,
    JITTER_MIN  = 0.1,
    JITTER_MAX  = 0.5,
    BLACKLIST   = {
        "robux", "premium", "buy", "purchase", "scam",
        "gift", "trade", "cancel", "payment", "gamepass",
        "vip", "money", "cash",
    },
}

-- ═══════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════
local S = {
    -- Auto Actions
    AutoHatch    = false,
    HatchDelay   = 3,
    AutoEquip    = false,
    EquipDelay   = 5,
    AutoSell     = false,
    SellRarity   = "Common",
    AutoClaim    = false,
    ClaimDelay   = 2,
    -- Protection
    AntiAFK      = true,
    -- Visuals
    FullBright   = false,
    NoFog        = false,
}

-- ═══════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════
local function notify(txt, dur)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "AXK HUB",
            Text = txt,
            Duration = dur or 3,
        })
    end)
end

local function isCharReady()
    if not LP.Character then return false end
    local humanoid = LP.Character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end
    return humanoid.Health > 0
end

local function safeWait(base)
    local jitter = math.random() * (CONFIG.JITTER_MAX - CONFIG.JITTER_MIN) + CONFIG.JITTER_MIN
    return task.wait(base + jitter)
end

-- ═══════════════════════════════════════════════
-- REMOTE SCANNER
-- ═══════════════════════════════════════════════
local R = {
    Hatch = {},
    Equip = {},
    Sell  = {},
    Claim = {},
}

local function isBlacklisted(name)
    for _, kw in ipairs(CONFIG.BLACKLIST) do
        if name:find(kw) then return true end
    end
    return false
end

local function scanRemotes()
    -- Clear old data (zero GC pressure)
    table.clear(R.Hatch)
    table.clear(R.Equip)
    table.clear(R.Sell)
    table.clear(R.Claim)
    
    for _, obj in ipairs(ReplicatedStorage:GetDescendants()) do
        if obj:IsA("RemoteFunction") or obj:IsA("RemoteEvent") then
            local n = obj.Name:lower()
            if not isBlacklisted(n) then
                if n:find("hatch") or n:find("open") or n:find("egg") then
                    table.insert(R.Hatch, obj)
                end
                if n:find("equip") then
                    table.insert(R.Equip, obj)
                end
                if n:find("sell") then
                    table.insert(R.Sell, obj)
                end
                if n:find("claim") or n:find("index") or n:find("reward") then
                    table.insert(R.Claim, obj)
                end
            end
        end
    end
    
    print(string.format("[AXK] Remotes — Hatch: %d, Equip: %d, Sell: %d, Claim: %d",
        #R.Hatch, #R.Equip, #R.Sell, #R.Claim))
end

-- Initial scan + delayed scan
scanRemotes()
task.delay(CONFIG.SCAN_DELAY, scanRemotes)

-- ═══════════════════════════════════════════════
-- REMOTE CALLER
-- ═══════════════════════════════════════════════
local function fireRemote(remote, ...)
    if not remote or not remote.Parent then return end
    if not isCharReady() then return end
    
    task.spawn(function()
        local ok, err = pcall(function()
            if remote:IsA("RemoteFunction") then
                remote:InvokeServer(...)
            else
                remote:FireServer(...)
            end
        end)
        if not ok then
            warn("[AXK] Remote error:", err)
        end
    end)
end

-- ═══════════════════════════════════════════════
-- AUTO LOOPS
-- ═══════════════════════════════════════════════

-- Auto Hatch
task.spawn(function()
    while true do
        safeWait(S.HatchDelay)
        if S.AutoHatch and #R.Hatch > 0 then
            fireRemote(R.Hatch[1])
        end
    end
end)

-- Auto Equip
task.spawn(function()
    while true do
        safeWait(S.EquipDelay)
        if S.AutoEquip and #R.Equip > 0 then
            fireRemote(R.Equip[1], "Best")
        end
    end
end)

-- Auto Sell
task.spawn(function()
    while true do
        safeWait(5)
        if S.AutoSell and #R.Sell > 0 then
            fireRemote(R.Sell[1], S.SellRarity)
        end
    end
end)

-- Auto Claim
task.spawn(function()
    while true do
        safeWait(S.ClaimDelay)
        if S.AutoClaim and #R.Claim > 0 then
            for _, remote in ipairs(R.Claim) do
                fireRemote(remote)
            end
        end
    end
end)

-- Lighting Lock (task.wait(1) - no flicker)
task.spawn(function()
    while true do
        task.wait(1)
        
        if S.FullBright then
            local bright = Color3.fromRGB(255, 255, 255)
            if Lighting.Ambient ~= bright then
                Lighting.Ambient = bright
                Lighting.OutdoorAmbient = bright
                Lighting.Brightness = 3
            end
        end
        
        if S.NoFog and Lighting.FogEnd < 9e9 then
            Lighting.FogEnd = 9e9
        end
    end
end)

-- Anti-AFK
LP.Idled:Connect(function()
    if S.AntiAFK then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.new())
        end)
    end
end)

-- ═══════════════════════════════════════════════
-- UI — RAYFIELD
-- ═══════════════════════════════════════════════
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local W = Rayfield:CreateWindow({
    Name = "⚡ AXK HUB",
    LoadingTitle = "🚀 AXK HUB Loading",
    LoadingSubtitle = "Final Edition",
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "AXK_Hub",
        FileName = "config",
    },
    KeySystem = false,
})

-- ═══════════════════════════════════════════════
-- TABS
-- ═══════════════════════════════════════════════
local HomeTab  = W:CreateTab("🏠 الرئيسية", "home")
local HatchTab = W:CreateTab("🥚 الفقس", "egg")
local EquipTab = W:CreateTab("🎽 التجهيز", "shirt")
local ClaimTab = W:CreateTab("📋 الاستلام", "clipboard")
local MiscTab  = W:CreateTab("⚙️ الإعدادات", "settings")

-- ═══════════════════════════════════════════════
-- HOME TAB
-- ═══════════════════════════════════════════════
HomeTab:CreateSection("📊 معلومات")
HomeTab:CreateParagraph({
    Title = "AXK HUB — Final",
    Content = string.format(
        "👤 %s\n🥚 Hatch: %d\n🎽 Equip: %d\n💰 Sell: %d\n📋 Claim: %d",
        LP.Name, #R.Hatch, #R.Equip, #R.Sell, #R.Claim
    ),
})

HomeTab:CreateSection("⚡ Quick Actions")
HomeTab:CreateButton({
    Name = "🔄 Refresh Remotes",
    Callback = function()
        scanRemotes()
        notify("✓ Remotes updated", 3)
    end,
})

HomeTab:CreateButton({
    Name = "💬 Discord",
    Callback = function()
        if setclipboard then
            pcall(setclipboard, CONFIG.DISCORD_URL)
            notify("✓ Copied Discord URL", 3)
        else
            notify(CONFIG.DISCORD_URL, 5)
        end
    end,
})

HomeTab:CreateButton({
    Name = "🔄 Rejoin Server",
    Callback = function()
        TeleportService:Teleport(game.PlaceId, LP)
    end,
})

-- ═══════════════════════════════════════════════
-- HATCH TAB
-- ═══════════════════════════════════════════════
HatchTab:CreateSection("🥚 Auto Hatch")
HatchTab:CreateToggle({
    Name = "Enable Auto Hatch",
    CurrentValue = false,
    Flag = "auto_hatch",
    Callback = function(v)
        S.AutoHatch = v
        notify(v and "🥚 Auto Hatch ON" or "⏹ Auto Hatch OFF", 2)
    end,
})

HatchTab:CreateSlider({
    Name = "Delay (seconds)",
    Range = {1, 10},
    Increment = 0.5,
    Suffix = "s",
    CurrentValue = 3,
    Flag = "hatch_delay",
    Callback = function(v) S.HatchDelay = v end,
})

-- ═══════════════════════════════════════════════
-- EQUIP TAB
-- ═══════════════════════════════════════════════
EquipTab:CreateSection("🎽 Auto Equip")
EquipTab:CreateToggle({
    Name = "Enable Auto Equip Best",
    CurrentValue = false,
    Flag = "auto_equip",
    Callback = function(v)
        S.AutoEquip = v
        notify(v and "🎽 Auto Equip ON" or "⏹ Auto Equip OFF", 2)
    end,
})

EquipTab:CreateSection("💰 Auto Sell")
EquipTab:CreateToggle({
    Name = "Enable Auto Sell",
    CurrentValue = false,
    Flag = "auto_sell",
    Callback = function(v)
        S.AutoSell = v
        notify(v and "💰 Auto Sell ON" or "⏹ Auto Sell OFF", 2)
    end,
})

EquipTab:CreateDropdown({
    Name = "Sell Rarity",
    Options = {"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic"},
    CurrentOption = {"Common"},
    Flag = "sell_rarity",
    Callback = function(opt) S.SellRarity = opt[1] end,
})

-- ═══════════════════════════════════════════════
-- CLAIM TAB
-- ═══════════════════════════════════════════════
ClaimTab:CreateSection("📋 Auto Claim Index")
ClaimTab:CreateToggle({
    Name = "Enable Auto Claim",
    CurrentValue = false,
    Flag = "auto_claim",
    Callback = function(v)
        S.AutoClaim = v
        notify(v and "📋 Auto Claim ON" or "⏹ Auto Claim OFF", 2)
    end,
})

ClaimTab:CreateSlider({
    Name = "Claim Delay",
    Range = {1, 10},
    Increment = 0.5,
    Suffix = "s",
    CurrentValue = 2,
    Flag = "claim_delay",
    Callback = function(v) S.ClaimDelay = v end,
})

-- ═══════════════════════════════════════════════
-- MISC TAB
-- ═══════════════════════════════════════════════
MiscTab:CreateSection("🛡️ Protection")
MiscTab:CreateToggle({
    Name = "Anti-AFK",
    CurrentValue = true,
    Flag = "anti_afk",
    Callback = function(v) S.AntiAFK = v end,
})

MiscTab:CreateSection("🎨 Visuals")
MiscTab:CreateToggle({
    Name = "Full Bright (Locked)",
    CurrentValue = false,
    Flag = "fullbright",
    Callback = function(v)
        S.FullBright = v
        if not v then
            Lighting.Ambient = Color3.fromRGB(70, 70, 70)
            Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
            Lighting.Brightness = 1
        end
    end,
})

MiscTab:CreateToggle({
    Name = "No Fog (Locked)",
    CurrentValue = false,
    Flag = "nofog",
    Callback = function(v)
        S.NoFog = v
        if not v then
            Lighting.FogEnd = 100000
        end
    end,
})

MiscTab:CreateSection("♻️ Actions")
MiscTab:CreateButton({
    Name = "🔄 Stop All Features",
    Callback = function()
        S.AutoHatch = false
        S.AutoEquip = false
        S.AutoSell = false
        S.AutoClaim = false
        notify("♻️ All features stopped", 2)
    end,
})

-- ═══════════════════════════════════════════════
-- INITIAL NOTIFICATION
-- ═══════════════════════════════════════════════
notify("✨ AXK HUB — Ready!", 5)
print("[AXK] Final loaded ✓")
