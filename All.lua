-- Language: Lua (Luau) | ZYROX SHOP | ProScript v1 (Universal 3D ESP for Mobile & PC)
-- Home = เปิด/ปิด UI

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Camera           = workspace.CurrentCamera
local LocalPlayer      = Players.LocalPlayer

-- Track event connections so the entire script can be shut down safely.
local running = true
-- Pause is session-only: keep the user's chosen feature settings intact.
local Pause = {active=false, callbacks={}}
local connections = {}
local function bind(signal, callback)
    if not running then return nil end
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local T = {
    BG=Color3.fromRGB(10,18,12), CARD=Color3.fromRGB(16,28,18),
    CARD2=Color3.fromRGB(22,38,24), ACCENT=Color3.fromRGB(0,215,90),
    ACCENTLIT=Color3.fromRGB(0,255,120), TAB_OFF=Color3.fromRGB(18,30,20),
    TEXT=Color3.fromRGB(235,255,240), SUBTEXT=Color3.fromRGB(130,170,140),
    TRACK=Color3.fromRGB(32,60,38), GREEN=Color3.fromRGB(0,210,85),
    RED=Color3.fromRGB(255,60,60),
}

local CFG = {
    AimbotEnabled=true, AimbotActivation="Hold Key", AimbotKey=Enum.KeyCode.E,
    AimbotMode="Camera", AimbotPart="Head", AimbotSmooth=30,
    AimbotMaxDist=700, AimbotTeamCheck=true, AimbotWallCheck=false, AimbotPrediction=true,
    AimbotFOV=140, TargetWallCheck=false,
    ShowFOVCircle=true,
    ESPEnabled=true, ESPName=true,
    ESPDistance=true, ESPHealth=true, ESPHealthMode="ตัวเลข", ESPTracers=false,
    ESPMaxDist=1500, ESPWallCheck=false,
    ColorEnemy=Color3.fromRGB(255,65,65), ColorTeammate=Color3.fromRGB(60,190,255),
    ColorText=Color3.fromRGB(255,255,255),
    ColorZombie=Color3.fromRGB(145,240,150), ColorBoss=Color3.fromRGB(255,120,95),
    ColorLoot=Color3.fromRGB(255,215,90),
    ColorFOV=Color3.fromRGB(0,255,120),
}

-- Performance mode changes refresh cadence, not feature availability.
local Perf={economy=false,max=false}

-- Settings are stored locally only when the executor provides file access.
local Settings={values={},available=type(readfile)=="function" and type(writefile)=="function",status=nil,serial=0,resetters={}}
Settings.path="ProScript_WARZ66Z_settings.json"
if Settings.available then
    local ok,data=pcall(function()
        local raw=readfile(Settings.path)
        if type(raw)~="string" or #raw>100000 then return nil end
        return game:GetService("HttpService"):JSONDecode(raw)
    end)
    if ok and type(data)=="table" then Settings.values=data end
end
-- Keep settings saved under earlier UI labels when names are improved.
local settingsNameMigration={
    {"toggle:เปิดระบบ ESP", "toggle:มองผู้เล่น (ESP)"},
    {"toggle:เส้นโครงร่างผู้เล่น", "toggle:โครงกระดูกผู้เล่น"},
    {"toggle:ชื่อผู้เล่น", "toggle:แสดงชื่อผู้เล่น"},
    {"toggle:ระยะทาง", "toggle:แสดงระยะทาง"},
    {"toggle:พลังชีวิต", "toggle:แสดงพลังชีวิต"},
    {"choice:สีผู้เล่น", "choice:สี ESP ผู้เล่น"},
    {"slider:ระยะเหวี่ยงทดลอง", "slider:ระยะเหวี่ยงเบ็ด"},
    {"toggle:เพิ่มระยะตกปลา", "toggle:ปรับระยะเหวี่ยงเบ็ด"},
    {"slider:เริ่มใช้เมื่อ HP (%)", "slider:ใช้ยาเมื่อ HP ถึง (%)"},
    {"toggle:เดินไว", "toggle:เพิ่มความเร็วเดิน"},
}
for _,names in ipairs(settingsNameMigration) do
    if Settings.values[names[2]]==nil and Settings.values[names[1]]~=nil then
        Settings.values[names[2]]=Settings.values[names[1]]
    end
end
function Settings.save()
    if not Settings.available then return false end
    local ok=pcall(function()
        writefile(Settings.path,game:GetService("HttpService"):JSONEncode(Settings.values))
    end)
    if Settings.status then
        pcall(function() Settings.status.Text=ok and "บันทึกอัตโนมัติแล้ว" or "บันทึกไม่สำเร็จ" end)
    end
    return ok
end
function Settings.set(key,value)
    Settings.values[key]=value
    if not Settings.available then return end
    Settings.serial=Settings.serial+1
    local ticket=Settings.serial
    task.delay(0.7,function()
        if ticket==Settings.serial then Settings.save() end
    end)
end
if type(Settings.values.aimKey)=="string" then
    local ok,key=pcall(function() return Enum.KeyCode[Settings.values.aimKey] end)
    if ok and key and key~=Enum.KeyCode.Unknown and key~=Enum.KeyCode.Home and key~=Enum.KeyCode.Escape then
        CFG.AimbotKey=key
    end
end

----------------------------------------------------------------
-- SAFE FOV CIRCLE DRAWING
----------------------------------------------------------------
local fovCircle = nil
pcall(function()
    fovCircle = Drawing.new("Circle")
    fovCircle.Visible = false
    fovCircle.Thickness = 1
    fovCircle.Transparency = 1
    fovCircle.Filled = false
    fovCircle.Color = CFG.ColorFOV
end)

----------------------------------------------------------------
-- UTILS
----------------------------------------------------------------
local function getParts(p)
    local c = p.Character
    if not c then return nil, nil, nil end
    local hum = c:FindFirstChildWhichIsA("Humanoid", true)
    local root = c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("UpperTorso") or c:FindFirstChild("Torso")
    local head = c:FindFirstChild("Head")
    if not head then head = root end
    return root, head, hum
end

local function screenCenter() 
    return Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2) 
end

local _rp = RaycastParams.new()
_rp.FilterType = Enum.RaycastFilterType.Exclude
local function hasLOS(from, to, extra, extraVisual)
    local char = LocalPlayer.Character
    local ig = char and {char} or {}
    if extra then table.insert(ig, extra) end
    if extraVisual then table.insert(ig, extraVisual) end
    _rp.FilterDescendantsInstances = ig
    return workspace:Raycast(from, to - from, _rp) == nil
end

local function isAliveRaw(p, knownHum)
    local char = p.Character
    if not char or not char.Parent then return false end
    local hum = knownHum or char:FindFirstChildWhichIsA("Humanoid", true)
    if not hum or not hum.Parent then return false end
    if hum.Health <= 0 then return false end
    local ok, state = pcall(function() return hum:GetState() end)
    if ok and state == Enum.HumanoidStateType.Dead then return false end
    if char:FindFirstChild("Dead") or char:FindFirstChild("IsDead") then return false end
    local root = char:FindFirstChild("HumanoidRootPart")
    if root and root.Anchored then return false end
    return true
end


----------------------------------------------------------------
-- 2K-STYLE PLAYER HEAD LOCK
----------------------------------------------------------------
local aimHeld=false
local aimArmed=false
local aimWaitingForKey=false
local aimKeyButton=nil
local aimMobileButton=nil
local lockedPlayer=nil
local aimPartFallback={Head={"Head","HumanoidRootPart"},HumanoidRootPart={"HumanoidRootPart","UpperTorso","Torso","Head"}}

local function getPlayerAimPart(character)
    if not character then return nil end
    local order=aimPartFallback[CFG.AimbotPart] or aimPartFallback.Head
    for _,name in ipairs(order) do
        local part=character:FindFirstChild(name)
        if part and part:IsA("BasePart") then return part end
    end
    return nil
end

local function isPlayerTeammate(player)
    if not CFG.AimbotTeamCheck then return false end
    local myTeam,theirTeam=LocalPlayer.Team,player.Team
    if myTeam and theirTeam and not LocalPlayer.Neutral and not player.Neutral and myTeam==theirTeam then
        return true
    end
    local myParty=LocalPlayer:GetAttribute("WarZPartyId")
    local theirParty=player:GetAttribute("WarZPartyId")
    if myParty~=nil and myParty~="" and myParty~=0 and theirParty==myParty then
        local myRoom=LocalPlayer:GetAttribute("ClanRoom")
        local theirRoom=player:GetAttribute("ClanRoom")
        if not myRoom or myRoom=="" or not theirRoom or theirRoom=="" or myRoom==theirRoom then
            return true
        end
    end
    return false
end

local function predictPlayerAim(part)
    local position=part.Position
    if not CFG.AimbotPrediction then return position end
    local mover=part
    local character=part.Parent
    local root=character and character:FindFirstChild("HumanoidRootPart")
    if root and root:IsA("BasePart") then mover=root end
    local ok,velocity=pcall(function() return mover.AssemblyLinearVelocity end)
    if not ok or typeof(velocity)~="Vector3" then return position end
    local lead=0.1
    pcall(function()
        local ping=LocalPlayer:GetNetworkPing()
        if type(ping)=="number" and ping>0 then lead=ping*0.5+0.05 end
    end)
    return position+velocity*lead
end

local function scanPlayerTargets(center)
    local bestPlayer,bestPart,bestScore=nil,nil,math.huge
    local character=LocalPlayer.Character
    local root=character and character:FindFirstChild("HumanoidRootPart")
    for _,player in ipairs(Players:GetPlayers()) do
        if player~=LocalPlayer and not isPlayerTeammate(player) and isAliveRaw(player) then
            local targetCharacter=player.Character
            local part=getPlayerAimPart(targetCharacter)
            if part then
                local targetPosition=predictPlayerAim(part)
                local inRange=not root or (part.Position-root.Position).Magnitude<=CFG.AimbotMaxDist
                if inRange then
                    local screen,onScreen=Camera:WorldToViewportPoint(targetPosition)
                    if onScreen and screen.Z>0 then
                        local score=(Vector2.new(screen.X,screen.Y)-center).Magnitude
                        if score<=CFG.AimbotFOV and score<bestScore then
                            local visible=not CFG.AimbotWallCheck or hasLOS(Camera.CFrame.Position,targetPosition,targetCharacter)
                            if visible then bestPlayer,bestPart,bestScore=player,part,score end
                        end
                    end
                end
            end
        end
    end
    return bestPlayer,bestPart
end

local function isPlayerAimActive()
    if Pause.active or not CFG.AimbotEnabled or aimWaitingForKey then return false end
    if CFG.AimbotActivation=="Always" then return true end
    if CFG.AimbotActivation=="Toggle" then return aimArmed end
    return aimHeld
end

bind(UserInputService.InputBegan,function(input,gameProcessed)
    if aimWaitingForKey then
        if input.UserInputType~=Enum.UserInputType.Keyboard then return end
        aimWaitingForKey=false
        if input.KeyCode~=Enum.KeyCode.Unknown and input.KeyCode~=Enum.KeyCode.Home and input.KeyCode~=Enum.KeyCode.Escape then
            CFG.AimbotKey=input.KeyCode
            Settings.set("aimKey",input.KeyCode.Name)
        end
        if aimKeyButton then aimKeyButton.Text=CFG.AimbotKey.Name end
        return
    end
    if gameProcessed or Pause.active or input.KeyCode~=CFG.AimbotKey then return end
    if CFG.AimbotActivation=="Hold Key" then aimHeld=true
    elseif CFG.AimbotActivation=="Toggle" then aimArmed=not aimArmed end
end)
bind(UserInputService.InputEnded,function(input)
    if input.KeyCode==CFG.AimbotKey and CFG.AimbotActivation=="Hold Key" then aimHeld=false end
end)

local AIM_STEP_NAME="ZYROX_2K_HeadLock"
RunService:UnbindFromRenderStep(AIM_STEP_NAME)
RunService:BindToRenderStep(AIM_STEP_NAME,Enum.RenderPriority.Last.Value-1,function(dt)
    Camera=workspace.CurrentCamera
    if not Camera then return end
    if not isPlayerAimActive() then lockedPlayer=nil;return end
    local center=screenCenter()
    local player,part=scanPlayerTargets(center)
    if not player or not part then lockedPlayer=nil;return end
    lockedPlayer=player
    local aimPosition=predictPlayerAim(part)
    if UserInputService:GetFocusedTextBox() then return end
    local frameTime=math.clamp(dt or 0,0,0.1)
    local smoothFactor=1-math.clamp(CFG.AimbotSmooth,0,100)/100
    local rate=2+200*smoothFactor*smoothFactor
    local alpha=math.clamp(1-math.exp(-rate*frameTime),0.01,1)
    if CFG.AimbotMode=="Mouse" then
        local screen=Camera:WorldToViewportPoint(aimPosition)
        if screen.Z>0 then
            pcall(function() mousemoverel((screen.X-center.X)*alpha*0.85,(screen.Y-center.Y)*alpha*0.85) end)
        end
    else
        local wanted=CFrame.lookAt(Camera.CFrame.Position,aimPosition)
        Camera.CFrame=Camera.CFrame:Lerp(wanted,alpha)
    end
end)

----------------------------------------------------------------
-- UNIVERSAL 3D ESP (WORK ON MOBILE & PC)
----------------------------------------------------------------
local espFolder = Instance.new("Folder")
espFolder.Name = "ProScript_ESP"
pcall(function() espFolder.Parent = game:GetService("CoreGui") end)
if not espFolder.Parent then espFolder.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local espCache = {}

local function createESP(p)
    if espCache[p] then return end
    
    local billboard = Instance.new("BillboardGui")
    billboard.Name = p.Name
    billboard.AlwaysOnTop = true
    billboard.Size = UDim2.new(0, 100, 0, 50)
    billboard.StudsOffset = Vector3.new(0, 2.5, 0)
    billboard.Enabled = false
    billboard.Parent = espFolder

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "InfoText"
    nameLabel.Size = UDim2.new(1, 0, 1, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.new(1, 1, 1)
    nameLabel.TextStrokeTransparency = 0
    nameLabel.TextSize = 12
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.Text = p.Name
    nameLabel.Parent = billboard

    local hpBackground = Instance.new("Frame")
    hpBackground.Name = "HealthBarBackground"
    hpBackground.Size = UDim2.new(0.8, 0, 0, 6)
    hpBackground.Position = UDim2.new(0.1, 0, 1, -8)
    hpBackground.BackgroundColor3 = Color3.fromRGB(24, 27, 34)
    hpBackground.BorderSizePixel = 0
    hpBackground.Visible = false
    hpBackground.Parent = billboard
    local hpFill = Instance.new("Frame")
    hpFill.Name = "HealthBarFill"
    hpFill.Size = UDim2.new(1, 0, 1, 0)
    hpFill.BackgroundColor3 = Color3.fromRGB(60, 220, 120)
    hpFill.BorderSizePixel = 0
    hpFill.Parent = hpBackground

    espCache[p] = {billboard = billboard, text = nameLabel, hpBackground = hpBackground, hpFill = hpFill}
end

local function removeESP(p)
    if espCache[p] then
        if espCache[p].billboard then espCache[p].billboard:Destroy() end
        espCache[p] = nil
    end
end

for unusedIndex, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then createESP(p) end
end
bind(Players.PlayerAdded, function(p) if p ~= LocalPlayer then createESP(p) end end)
bind(Players.PlayerRemoving, removeESP)

----------------------------------------------------------------
-- ESP UPDATE LOOP

-- 66Z zombies and bosses are tagged models, not a fixed workspace folder.
local npcScanCache={}
local nextNpcScan=0
local function get66ZNpcs()
    local now=os.clock()
    if now<nextNpcScan then return npcScanCache end
    nextNpcScan=now+2
    local found={}
    for _,node in ipairs(workspace:GetDescendants()) do
        if node:IsA("Model") and (node:GetAttribute("WarZZombie")==true or node:GetAttribute("WarZSuperZombie")==true) then
            table.insert(found,node)
        end
    end
    npcScanCache=found
    return found
end
local function npcRoot(model)
    return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart",true)
end
----------------------------------------------------------------
-- Experimental WarZ shot-direction assist (opt-in).
-- FireRequest signature observed in supplied CombatInput:
-- direction, seed, stance, camera position, muzzle, ...
----------------------------------------------------------------
local silentState
local silentStatus="ตัวรันไม่รองรับ hookmetamethod / getnamecallmethod"
local supported=type(hookmetamethod)=="function" and type(getnamecallmethod)=="function" and type(newcclosure)=="function" and type(getgenv)=="function"
if supported then
    local env=getgenv()
    if type(env.__ProHub66ZShotAssist)~="table" then env.__ProHub66ZShotAssist={} end
    silentState=env.__ProHub66ZShotAssist
    silentState.enabled=false
    silentState.npcEnabled=false
    local remotes=game:GetService("ReplicatedStorage"):FindFirstChild("WarZSession")
    local fireRequest=remotes and remotes:FindFirstChild("Request")
    if fireRequest and fireRequest:IsA("RemoteEvent") then
        silentState.remote=fireRequest
        silentState.fireFunction=fireRequest.FireServer
    end
    if not silentState.installed and silentState.remote then
        local oldNamecall
        local ok,err=pcall(function()
            oldNamecall=hookmetamethod(game,"__namecall",newcclosure(function(self,...)
                -- All calls to other objects pass through untouched, without extra Roblox calls.
                if Pause.active or self~=silentState.remote or not silentState.enabled or getnamecallmethod()~="FireServer" then
                    return oldNamecall(self,...)
                end
                local args=table.pack(...)
                pcall(function()
                    local data=args[1]
                    if type(data)~="table" or (data.action~="Fire" and data.action~="Intent") then return end
                    if typeof(data.origin)~="Vector3" or typeof(data.direction)~="Vector3" then return end
                    local target=silentState.pickHead and silentState.pickHead(data.origin)
                    if target then
                        local delta=target-data.origin
                        if delta.Magnitude>0.001 then
                            local copy=table.clone(data);copy.direction=delta.Unit;args[1]=copy
                        end
                    end
                end)
                -- Use the saved method directly after selection, which itself calls Roblox APIs.
                return silentState.fireFunction(self,table.unpack(args,1,args.n))
            end))
        end)
        if ok and type(oldNamecall)=="function" then
            silentState.installed=true
        else
            silentStatus="ติดตั้งไม่สำเร็จ: "..tostring(err)
        end
    end
    if silentState.installed then
        silentStatus="พร้อมใช้งาน • เป้าซอมบี้/บอส"
    elseif not silentState.remote then
        silentStatus="ไม่พบ WarZSession.Request"
    end
end

local espRefreshElapsed=0
bind(RunService.RenderStepped, function(dt)
    Camera = workspace.CurrentCamera
    if not Camera then return end
    if fovCircle then
        fovCircle.Visible = CFG.ShowFOVCircle and not Pause.active
        fovCircle.Position = screenCenter()
        fovCircle.Radius = CFG.AimbotFOV
    end

    -- Billboard positions track automatically; reduce text refresh in economy mode.
    espRefreshElapsed=espRefreshElapsed+math.max(dt or 0,0)
    if espRefreshElapsed<(Perf.economy and 0.75 or (Perf.max and 0.1 or 0.2)) then return end
    espRefreshElapsed=0
    if not CFG.ESPEnabled then
        for _,cache in pairs(espCache) do if cache.billboard.Enabled then cache.billboard.Enabled=false end end
        return
    end
    for p, cache in pairs(espCache) do
        local char = p.Character
        local root, head, hum = getParts(p)
        if CFG.ESPEnabled and root and head and hum and isAliveRaw(p,hum) then
            local dist3D = (root.Position - Camera.CFrame.Position).Magnitude
            if dist3D <= CFG.ESPMaxDist then
                cache.billboard.Adornee = head
                cache.billboard.Enabled = true
                local txt = ""
                if CFG.ESPName then txt = p.Name end
                if CFG.ESPDistance then txt = txt .. string.format(" [%dm]", math.floor(dist3D / 4)) end
                if CFG.ESPHealth and CFG.ESPHealthMode == "ตัวเลข" then
                    local hp = math.floor(hum.Health)
                    local maxHp = math.floor(hum.MaxHealth)
                    txt = txt .. string.format(" - HP: %d/%d", hp, maxHp)
                end
                local showBar = CFG.ESPHealth and CFG.ESPHealthMode == "หลอดเลือด"
                cache.hpBackground.Visible = showBar
                if showBar then
                    local ratio = hum.MaxHealth > 0 and math.clamp(hum.Health / hum.MaxHealth, 0, 1) or 0
                    cache.hpFill.Size = UDim2.new(ratio, 0, 1, 0)
                    cache.hpFill.BackgroundColor3 = Color3.fromRGB(240, 75, 75):Lerp(Color3.fromRGB(60, 220, 120), ratio)
                end
                cache.text.Text = txt
                cache.text.TextColor3 = CFG.ColorText
            else
                cache.billboard.Enabled = false
            end
        else
            cache.billboard.Enabled = false
        end
    end

end)

----------------------------------------------------------------
-- PC UI: ZYROX midnight violet
----------------------------------------------------------------
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ProScriptUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end)
if not ScreenGui.Parent then ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local C = {
    bg=Color3.fromRGB(10,8,16), panel=Color3.fromRGB(20,14,31),
    card=Color3.fromRGB(26,20,39), border=Color3.fromRGB(60,42,83),
    accent=Color3.fromRGB(186,120,255), accentDark=Color3.fromRGB(100,55,164),
    text=Color3.fromRGB(248,242,255), muted=Color3.fromRGB(175,159,192),
    success=Color3.fromRGB(169,116,234), off=Color3.fromRGB(65,51,81),
}
local function corner(obj, radius)
    local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,radius); c.Parent=obj
end
local function stroke(obj, color)
    local st=Instance.new("UIStroke"); st.Color=color; st.Thickness=1; st.Parent=obj
end
local function text(parent, content, size, color, font)
    local t=Instance.new("TextLabel"); t.BackgroundTransparency=1; t.Text=content
    t.TextColor3=color; t.TextSize=size; t.Font=font or Enum.Font.Gotham
    t.TextXAlignment=Enum.TextXAlignment.Left; t.Parent=parent; return t
end
local function button(parent, caption)
    local b=Instance.new("TextButton"); b.AutoButtonColor=true; b.BorderSizePixel=0
    b.Font=Enum.Font.GothamBold; b.TextSize=12; b.TextColor3=C.text
    b.Text=caption; b.Parent=parent; return b
end

local Window=Instance.new("Frame")
Window.Size=UDim2.fromOffset(440,570); Window.AnchorPoint=Vector2.new(.5,.5); Window.Position=UDim2.fromScale(.5,.5)
Window.BackgroundColor3=C.bg; Window.BorderSizePixel=0; Window.ClipsDescendants=true
Window.Parent=ScreenGui; corner(Window,16); stroke(Window,C.border)
local uiScale=Instance.new("UIScale");uiScale.Parent=Window
local function resizeForViewport()
    local cam=workspace.CurrentCamera
    if cam then uiScale.Scale=math.min(1,math.max(0.5,math.min((cam.ViewportSize.X-24)/440,(cam.ViewportSize.Y-24)/570))) end
end
resizeForViewport()
if workspace.CurrentCamera then bind(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"),resizeForViewport) end

local bar=Instance.new("Frame"); bar.Size=UDim2.new(1,0,0,70)
bar.BackgroundColor3=C.panel; bar.BorderSizePixel=0; bar.Parent=Window
-- A slim violet light bar and a compact Z badge anchor the new header.
local glow=Instance.new("Frame");glow.Name="VioletAccent";glow.Size=UDim2.new(1,0,0,3)
glow.BackgroundColor3=Color3.new(1,1,1);glow.BorderSizePixel=0;glow.Parent=bar
local glowGradient=Instance.new("UIGradient")
glowGradient.Color=ColorSequence.new(Color3.fromRGB(108,57,183),Color3.fromRGB(219,165,255))
glowGradient.Parent=glow
local badge=Instance.new("Frame");badge.Size=UDim2.fromOffset(35,35);badge.Position=UDim2.fromOffset(16,18)
badge.BackgroundColor3=C.accentDark;badge.BorderSizePixel=0;badge.Parent=bar;corner(badge,10)
local badgeText=text(badge,"Z",20,C.text,Enum.Font.GothamBold)
badgeText.Size=UDim2.fromScale(1,1);badgeText.TextXAlignment=Enum.TextXAlignment.Center
-- Use the supplied image as a local asset when the executor supports it.
-- Keep the original Z visible if file/custom-asset support is unavailable.
do
    local getAsset=type(getcustomasset)=="function" and getcustomasset
        or (type(getsynasset)=="function" and getsynasset or nil)
    if getAsset and type(writefile)=="function" then
        local ok,asset=pcall(function()
            local encoded="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"
            local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
            local lookup={}
            for i=1,#alphabet do lookup[alphabet:sub(i,i)]=i-1 end
            local decoded={}
            for block in encoded:gmatch("....") do
                local a=lookup[block:sub(1,1)]
                local b=lookup[block:sub(2,2)]
                local c=lookup[block:sub(3,3)] or 0
                local d=lookup[block:sub(4,4)] or 0
                if a==nil or b==nil then error("Invalid logo data") end
                local n=a*262144+b*4096+c*64+d
                decoded[#decoded+1]=string.char(math.floor(n/65536)%256)
                if block:sub(3,3)~="=" then decoded[#decoded+1]=string.char(math.floor(n/256)%256) end
                if block:sub(4,4)~="=" then decoded[#decoded+1]=string.char(n%256) end
            end
            local path="ZYROX_SHOP_logo_v1.png"
            writefile(path,table.concat(decoded))
            return getAsset(path)
        end)
        if ok and type(asset)=="string" and asset~="" then
            local logo=Instance.new("ImageLabel")
            logo.Name="ZYROXLogo";logo.BackgroundTransparency=1;logo.Size=UDim2.fromScale(1,1)
            logo.ScaleType=Enum.ScaleType.Fit;logo.Image=asset;logo.Parent=badge
            badge.ClipsDescendants=true
            badgeText.Visible=false
            task.delay(5,function()
                if running and logo.Parent and not logo.IsLoaded then
                    logo.Visible=false;badgeText.Visible=true
                end
            end)
        else
            warn("ZYROX SHOP: ไม่สามารถโหลดโลโก้จากไฟล์ได้")
        end
    else
        warn("ZYROX SHOP: ตัวรันไม่รองรับการใช้ภาพในเครื่อง")
    end
end
local title=text(bar,"ZYROX SHOP",19,C.text,Enum.Font.GothamBold)
title.Position=UDim2.fromOffset(62,12); title.Size=UDim2.new(1,-195,0,24)
local subtitle=text(bar,"เซิฟ : WARZ 66Z PVP",10,C.muted,Enum.Font.GothamMedium)
subtitle.Position=UDim2.fromOffset(62,39); subtitle.Size=UDim2.new(1,-195,0,16)
local cleanupNpcEsp=function() end
local cleanupLootEsp=function() end
local cleanupCrosshair=function() end
local cleanupPlayerShapes=function() end
local cleanupFishingRange=function() end
local restoreWeaponFunctions=function() end
local restoreQuickPickup=function() end
local stopWalkSpeed=function() end
local hide=button(bar,"×"); hide.Size=UDim2.fromOffset(34,34); hide.Position=UDim2.new(1,-50,0,18)
hide.BackgroundColor3=C.card; hide.TextSize=20; corner(hide,9)
-- X fully shuts down the script; Home only hides/shows its window.
bind(hide.MouseButton1Click, function()
    if not running then return end
    running=false
    if Settings.available then Settings.serial=Settings.serial+1; Settings.save() end
    RunService:UnbindFromRenderStep(AIM_STEP_NAME)
    aimHeld=false; aimArmed=false; lockedPlayer=nil
    cleanupNpcEsp()
    cleanupLootEsp()
    cleanupCrosshair()
    cleanupPlayerShapes()
    cleanupFishingRange()
    restoreWeaponFunctions()
    restoreQuickPickup()
    stopWalkSpeed()
    CFG.ESPEnabled=false
    CFG.ShowFOVCircle=false
    if silentState then
        silentState.enabled=false
        silentState.npcEnabled=false
        silentState.pickHead=nil
    end
    for unusedIndex,connection in ipairs(connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(connections)
    if fovCircle then
        pcall(function() fovCircle:Remove() end)
        fovCircle=nil
    end
    pcall(function() espFolder:Destroy() end)
    pcall(function() ScreenGui:Destroy() end)
end)

if UserInputService.TouchEnabled then
    local menu=button(ScreenGui,"ZYROX");menu.Size=UDim2.fromOffset(70,36);menu.Position=UDim2.new(0,12,.5,-18)
    menu.BackgroundColor3=C.accentDark;corner(menu,9)
    bind(menu.MouseButton1Click,function() Window.Visible=not Window.Visible end)
    local aimButton=button(ScreenGui,"ล็อกหัว")
    aimButton.Size=UDim2.fromOffset(74,54); aimButton.AnchorPoint=Vector2.new(1,1)
    aimButton.Position=UDim2.new(1,-20,1,-110); aimButton.BackgroundColor3=C.accentDark; corner(aimButton,18)
    bind(aimButton.InputBegan,function(input)
        if input.UserInputType~=Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
        if CFG.AimbotActivation=="Toggle" then aimArmed=not aimArmed else aimHeld=true end
    end)
    bind(aimButton.InputEnded,function(input)
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then aimHeld=false end
    end)
end
local dragging=false
local dragStart, initialPosition
bind(bar.InputBegan, function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
        dragging=true; dragStart=input.Position; initialPosition=Window.Position
    end
end)
bind(UserInputService.InputChanged, function(input)
    if dragging and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then
        local d=input.Position-dragStart
        Window.Position=UDim2.new(initialPosition.X.Scale,initialPosition.X.Offset+d.X,initialPosition.Y.Scale,initialPosition.Y.Offset+d.Y)
    end
end)
bind(UserInputService.InputEnded, function(input)
    if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then dragging=false end
end)
bind(UserInputService.InputBegan, function(input, processed)
    if input.KeyCode==Enum.KeyCode.Home then
        if not processed then Window.Visible=not Window.Visible end
    end
end)

local tabs=Instance.new("Frame"); tabs.Position=UDim2.fromOffset(16,82)
tabs.Size=UDim2.new(1,-32,0,40); tabs.BackgroundColor3=C.panel; tabs.BorderSizePixel=0
tabs.Parent=Window; corner(tabs,10); stroke(tabs,C.border)
local aimTab=button(tabs,"ล็อกหัว / FOV"); aimTab.Size=UDim2.new(0.25,-4,1,-8)
aimTab.Position=UDim2.fromOffset(4,4); corner(aimTab,7)
local espTab=button(tabs,"มองทะลุ"); espTab.Size=UDim2.new(0.25,-4,1,-8)
espTab.Position=UDim2.new(0.25,3,0,4); corner(espTab,7)
local farmTab=button(tabs,"ฟาร์ม"); farmTab.Size=UDim2.new(0.25,-4,1,-8)
farmTab.Position=UDim2.new(0.5,2,0,4); corner(farmTab,7)
local otherTab=button(tabs,"อื่นๆ"); otherTab.Size=UDim2.new(0.25,-4,1,-8)
otherTab.Position=UDim2.new(0.75,1,0,4); corner(otherTab,7)
local function scrollPage()
    local page=Instance.new("ScrollingFrame"); page.Position=UDim2.fromOffset(16,136)
    page.Size=UDim2.new(1,-32,1,-176); page.BackgroundTransparency=1; page.BorderSizePixel=0
    page.ScrollBarThickness=4; page.ScrollBarImageColor3=C.accentDark
    page.CanvasSize=UDim2.new(0,0,0,0); page.AutomaticCanvasSize=Enum.AutomaticSize.Y
    page.Parent=Window
    local layout=Instance.new("UIListLayout"); layout.SortOrder=Enum.SortOrder.LayoutOrder
    layout.Padding=UDim.new(0,7); layout.Parent=page
    local pad=Instance.new("UIPadding"); pad.PaddingRight=UDim.new(0,6)
    pad.PaddingBottom=UDim.new(0,14); pad.Parent=page
    return page
end
local aimPage=scrollPage(); local espPage=scrollPage(); local farmPage=scrollPage(); local otherPage=scrollPage()
local function selectTab(which)
    local items={{aimTab,aimPage,"aim"},{espTab,espPage,"esp"},{farmTab,farmPage,"farm"},{otherTab,otherPage,"other"}}
    for unusedIndex,item in ipairs(items) do
        local selected=item[3]==which
        item[2].Visible=selected
        item[1].BackgroundColor3=selected and C.accentDark or C.panel
        item[1].TextColor3=selected and C.text or C.muted
        item[1].TextTransparency=selected and 0 or 0.08
    end
end
bind(aimTab.MouseButton1Click, function() selectTab("aim") end)
bind(espTab.MouseButton1Click, function() selectTab("esp") end)
bind(farmTab.MouseButton1Click, function() selectTab("farm") end)
bind(otherTab.MouseButton1Click, function() selectTab("other") end)
selectTab("aim")
local footer=text(Window,"HOME  ซ่อน / เปิดเมนู     •     X  ปิดสคริปต์",10,C.muted)
footer.Position=UDim2.new(0,20,1,-29); footer.Size=UDim2.new(1,-40,0,16)

local orders={}
local function nextOrder(page) orders[page]=(orders[page] or 0)+1; return orders[page] end
local function section(page, heading, detail)
    local f=Instance.new("Frame"); f.Size=UDim2.new(1,0,0,50); f.BackgroundTransparency=1
    f.LayoutOrder=nextOrder(page); f.Parent=page
    local mark=Instance.new("Frame");mark.Size=UDim2.fromOffset(3,19);mark.Position=UDim2.fromOffset(2,6)
    mark.BackgroundColor3=C.accent;mark.BorderSizePixel=0;mark.Parent=f;corner(mark,2)
    local h=text(f,heading,14,C.text,Enum.Font.GothamBold); h.Position=UDim2.fromOffset(13,5); h.Size=UDim2.new(1,-17,0,20)
    local d=text(f,detail,11,C.muted); d.Position=UDim2.fromOffset(13,27); d.Size=UDim2.new(1,-17,0,17)
end
local function card(page,height)
    local f=Instance.new("Frame"); f.Size=UDim2.new(1,0,0,height); f.BackgroundColor3=C.card
    f.BorderSizePixel=0; f.LayoutOrder=nextOrder(page); f.Parent=page; corner(f,10); stroke(f,C.border)
    return f
end
local function rowLabel(f, title, detail)
    local a=text(f,title,13,C.text,Enum.Font.GothamMedium); a.Position=UDim2.fromOffset(14,8); a.Size=UDim2.new(1,-155,0,20)
    local b=text(f,detail,10,C.muted); b.Position=UDim2.fromOffset(14,29); b.Size=UDim2.new(1,-155,0,15)
end
local function toggle(page,title,detail,initial,callback)
    local f=card(page,52); rowLabel(f,title,detail)
    local b=button(f,""); b.Size=UDim2.fromOffset(44,24); b.Position=UDim2.new(1,-58,.5,-12); corner(b,12)
    local knob=Instance.new("Frame"); knob.Size=UDim2.fromOffset(16,16); knob.BackgroundColor3=C.text
    knob.BorderSizePixel=0; knob.Parent=b; corner(knob,8)
    local key="toggle:"..title
    local stored=Settings.values[key]
    local value=initial
    if type(stored)=="boolean" then value=stored end
    local function draw()
        b.BackgroundColor3=value and C.accent or C.off
        knob.Position=value and UDim2.new(1,-20,.5,-8) or UDim2.new(0,4,.5,-8)
    end
    draw()
    if type(stored)=="boolean" then pcall(callback,value) end
    table.insert(Pause.callbacks,function(paused)
        callback(not paused and value or false)
    end)
    table.insert(Settings.resetters,function()
        value=initial;draw()
        if not Pause.active then callback(value) end
    end)
    bind(b.MouseButton1Click, function()
        value=not value; draw()
        if not Pause.active then callback(value) end
        Settings.set(key,value)
    end)
end
local function choice(page,title,detail,options,labels,initial,callback)
    local f=card(page,52); rowLabel(f,title,detail)
    local b=button(f,""); b.Size=UDim2.fromOffset(120,30); b.Position=UDim2.new(1,-134,.5,-15)
    b.BackgroundColor3=C.accentDark; corner(b,8)
    local key="choice:"..title
    local stored=Settings.values[key]
    local index=1
    for i,v in ipairs(options) do if v==initial then index=i; break end end
    local defaultIndex=index
    local restored=false
    for i,v in ipairs(options) do if v==stored then index=i; restored=true; break end end
    b.Text=labels[options[index]] or options[index]
    if restored then pcall(callback,options[index]) end
    table.insert(Settings.resetters,function()
        index=defaultIndex
        local value=options[index]
        b.Text=labels[value] or value
        callback(value)
    end)
    bind(b.MouseButton1Click, function()
        index=index%#options+1; local v=options[index]; b.Text=labels[v] or v; callback(v); Settings.set(key,v)
    end)
end
local function slider(page,title,detail,min,max,current,step,callback)
    local f=card(page,73); rowLabel(f,title,detail)
    local value=text(f,"",12,C.accent,Enum.Font.GothamBold)
    value.Position=UDim2.new(1,-95,0,10); value.Size=UDim2.fromOffset(80,20); value.TextXAlignment=Enum.TextXAlignment.Right
    local track=Instance.new("Frame"); track.Position=UDim2.new(0,15,1,-17); track.Size=UDim2.new(1,-30,0,5)
    track.BackgroundColor3=C.off; track.BorderSizePixel=0; track.Parent=f; corner(track,3)
    local fill=Instance.new("Frame"); fill.Size=UDim2.new(0,0,1,0); fill.BackgroundColor3=C.accent
    fill.BorderSizePixel=0; fill.Parent=track; corner(fill,3)
    local thumb=Instance.new("Frame"); thumb.AnchorPoint=Vector2.new(.5,.5); thumb.Size=UDim2.fromOffset(12,12)
    thumb.BackgroundColor3=C.text; thumb.BorderSizePixel=0; thumb.Parent=track; corner(thumb,6); stroke(thumb,C.accent)
    local function display(v)
        local fraction=(v-min)/(max-min); fill.Size=UDim2.new(fraction,0,1,0)
        thumb.Position=UDim2.new(fraction,0,.5,0)
        value.Text=step<1 and string.format("%.2f",v) or string.format("%d",v)
    end
    local key="slider:"..title
    local defaultValue=current
    local stored=Settings.values[key]
    if type(stored)=="number" and stored==stored then
        current=math.clamp(math.floor(stored/step+0.5)*step,min,max)
        pcall(callback,current)
    end
    display(current)
    table.insert(Settings.resetters,function()
        current=defaultValue
        display(current)
        callback(current)
    end)
    local hit=button(track,""); hit.BackgroundTransparency=1; hit.Position=UDim2.new(0,0,0,-10)
    hit.Size=UDim2.new(1,0,0,25)
    local draggingSlider=false
    local function update(x)
        if track.AbsoluteSize.X<=0 then return end
        local relative=math.clamp((x-track.AbsolutePosition.X)/track.AbsoluteSize.X,0,1)
        local v=math.clamp(math.floor((min+relative*(max-min))/step+.5)*step,min,max)
        display(v); callback(v); Settings.set(key,v)
    end
    bind(hit.InputBegan, function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then draggingSlider=true; update(input.Position.X) end
    end)
    bind(UserInputService.InputChanged, function(input)
        if draggingSlider and (input.UserInputType==Enum.UserInputType.MouseMovement or input.UserInputType==Enum.UserInputType.Touch) then update(input.Position.X) end
    end)
    bind(UserInputService.InputEnded, function(input)
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then draggingSlider=false end
    end)
end
section(aimPage,"ล็อกหัวผู้เล่น","ระบบเล็งแบบ 2K • กดค้าง E เป็นค่าเริ่มต้น")
toggle(aimPage,"เปิดระบบล็อกหัว (2K)","เปิดหรือปิดการเล็งผู้เล่น",CFG.AimbotEnabled,function(v) CFG.AimbotEnabled=v; if not v then lockedPlayer=nil end end)
choice(aimPage,"วิธีเปิดล็อกหัว","กดค้าง สลับเปิด/ปิด หรือทำงานตลอด",{"Hold Key","Toggle","Always"},{},CFG.AimbotActivation,function(v) CFG.AimbotActivation=v; aimHeld=false; aimArmed=false end)
do
    local f=card(aimPage,52); rowLabel(f,"ปุ่มล็อกหัว","คลิกปุ่มขวาแล้วกดคีย์ใหม่")
    aimKeyButton=button(f,CFG.AimbotKey.Name); aimKeyButton.Size=UDim2.fromOffset(100,30)
    aimKeyButton.Position=UDim2.new(1,-114,.5,-15); aimKeyButton.BackgroundColor3=C.accentDark; corner(aimKeyButton,8)
    table.insert(Settings.resetters,function() CFG.AimbotKey=Enum.KeyCode.E; aimKeyButton.Text="E" end)
    bind(aimKeyButton.MouseButton1Click,function() aimWaitingForKey=true; aimKeyButton.Text="กดคีย์..." end)
end
choice(aimPage,"จุดเล็ง","เลือกศีรษะหรือแกนกลาง",{"Head","HumanoidRootPart"},{Head="หัว",HumanoidRootPart="แกนกลาง"},CFG.AimbotPart,function(v) CFG.AimbotPart=v end)
slider(aimPage,"ระยะเล็งสูงสุด","ระยะจากตัวเรา",50,2000,CFG.AimbotMaxDist,10,function(v) CFG.AimbotMaxDist=v end)
slider(aimPage,"ความไวล็อกหัว","ค่าสูงเล็งตามเร็วขึ้น",0,100,CFG.AimbotSmooth,1,function(v) CFG.AimbotSmooth=v end)
choice(aimPage,"โหมดเล็ง","กล้อง หรือเมาส์สำหรับ FPS",{"Camera","Mouse"},{Camera="กล้อง",Mouse="เมาส์"},CFG.AimbotMode,function(v) CFG.AimbotMode=v end)
toggle(aimPage,"เช็กทีม","ข้ามทีมเดียวกันและปาร์ตี้เดียวกัน",CFG.AimbotTeamCheck,function(v) CFG.AimbotTeamCheck=v end)
toggle(aimPage,"เช็กกำแพง","เลือกเฉพาะเป้าที่มองเห็น",CFG.AimbotWallCheck,function(v) CFG.AimbotWallCheck=v end)
toggle(aimPage,"คาดการณ์ตำแหน่ง","ชดเชยความเร็วเป้าและ ping",CFG.AimbotPrediction,function(v) CFG.AimbotPrediction=v end)

section(aimPage,"วง FOV","กำหนดขอบเขต FOV สำหรับล็อกหัวและเป้าหมาย NPC")
slider(aimPage,"FOV ล็อกหัว","ขอบเขตล็อกหัวและวง FOV ที่แสดง",20,500,CFG.AimbotFOV,1,function(v) CFG.AimbotFOV=v end)
toggle(aimPage,"แสดงวง FOV","แสดงขอบเขตบนหน้าจอ",CFG.ShowFOVCircle,function(v) CFG.ShowFOVCircle=v end)
local ESP_COLOR_NAMES={
    "ขาว","แดง","ฟ้า","น้ำเงิน","ม่วง","ชมพู","เหลือง","เขียว","เขียวอ่อน","ส้ม",
    "ทอง","ฟ้าอ่อน","ฟ้าเข้ม","น้ำเงินเข้ม","ม่วงอ่อน","ม่วงเข้ม","ชมพูอ่อน","ชมพูเข้ม",
    "แดงเข้ม","ส้มอ่อน","เขียวมะนาว","เขียวเข้ม","เทา","ดำ","ครีม","น้ำตาล",
}
local ESP_COLORS={
    ["ขาว"]=Color3.fromRGB(255,255,255), ["แดง"]=Color3.fromRGB(255,65,65),
    ["ฟ้า"]=Color3.fromRGB(70,210,255), ["น้ำเงิน"]=Color3.fromRGB(95,130,255),
    ["ม่วง"]=Color3.fromRGB(180,110,255), ["ชมพู"]=Color3.fromRGB(255,115,190),
    ["เหลือง"]=Color3.fromRGB(255,215,70), ["เขียว"]=Color3.fromRGB(0,255,120),
    ["เขียวอ่อน"]=Color3.fromRGB(145,240,150), ["ส้ม"]=Color3.fromRGB(255,120,95),
    ["ทอง"]=Color3.fromRGB(255,215,90), ["ฟ้าอ่อน"]=Color3.fromRGB(168,235,255),
    ["ฟ้าเข้ม"]=Color3.fromRGB(0,150,210), ["น้ำเงินเข้ม"]=Color3.fromRGB(45,70,180),
    ["ม่วงอ่อน"]=Color3.fromRGB(215,185,255), ["ม่วงเข้ม"]=Color3.fromRGB(110,55,175),
    ["ชมพูอ่อน"]=Color3.fromRGB(255,190,215), ["ชมพูเข้ม"]=Color3.fromRGB(220,55,135),
    ["แดงเข้ม"]=Color3.fromRGB(180,35,45), ["ส้มอ่อน"]=Color3.fromRGB(255,185,130),
    ["เขียวมะนาว"]=Color3.fromRGB(175,255,40), ["เขียวเข้ม"]=Color3.fromRGB(30,145,75),
    ["เทา"]=Color3.fromRGB(170,175,185), ["ดำ"]=Color3.fromRGB(20,20,20),
    ["ครีม"]=Color3.fromRGB(255,241,195), ["น้ำตาล"]=Color3.fromRGB(170,110,70),
}
choice(aimPage,"สีวง FOV","คลิกปุ่มเพื่อเปลี่ยนสี",ESP_COLOR_NAMES,{},"เขียว",function(name)
    CFG.ColorFOV=ESP_COLORS[name]
    if fovCircle then pcall(function() fovCircle.Color=CFG.ColorFOV end) end
end)

section(aimPage,"เป้ากลางจอ","เลือกแบบ สี และขนาดแยกจากวง FOV")
do
    local visible=false
    local size=20
    local style="บวก"
    local color=Color3.fromRGB(255,255,255)
    local gui=Instance.new("ScreenGui")
    gui.Name="ProScriptCrosshair"
    gui.IgnoreGuiInset=true
    gui.ResetOnSpawn=false
    gui.DisplayOrder=100
    gui.Enabled=false
    pcall(function() gui.Parent=game:GetService("CoreGui") end)
    if not gui.Parent then gui.Parent=LocalPlayer:WaitForChild("PlayerGui") end
    local root=Instance.new("Frame")
    root.AnchorPoint=Vector2.new(.5,.5)
    root.Position=UDim2.fromScale(.5,.5)
    root.Size=UDim2.fromOffset(size,size)
    root.BackgroundTransparency=1
    root.Parent=gui
    local function makeLine()
        local part=Instance.new("Frame")
        part.AnchorPoint=Vector2.new(.5,.5)
        part.BorderSizePixel=0
        part.BackgroundColor3=color
        part.Visible=false
        part.Parent=root
        return part
    end
    local horizontal=makeLine()
    horizontal.Position=UDim2.fromScale(.5,.5)
    horizontal.Size=UDim2.new(1,0,0,2)
    local vertical=makeLine()
    vertical.Position=UDim2.fromScale(.5,.5)
    vertical.Size=UDim2.new(0,2,1,0)
    local left=makeLine();left.Position=UDim2.fromScale(.17,.5);left.Size=UDim2.new(.34,0,0,2)
    local right=makeLine();right.Position=UDim2.fromScale(.83,.5);right.Size=UDim2.new(.34,0,0,2)
    local top=makeLine();top.Position=UDim2.fromScale(.5,.17);top.Size=UDim2.new(0,2,.34,0)
    local bottom=makeLine();bottom.Position=UDim2.fromScale(.5,.83);bottom.Size=UDim2.new(0,2,.34,0)
    local dot=makeLine();dot.Position=UDim2.fromScale(.5,.5)
    local dotCorner=Instance.new("UICorner");dotCorner.CornerRadius=UDim.new(1,0);dotCorner.Parent=dot
    local ring=Instance.new("Frame")
    ring.AnchorPoint=Vector2.new(.5,.5);ring.Position=UDim2.fromScale(.5,.5)
    ring.Size=UDim2.fromScale(1,1);ring.BackgroundTransparency=1;ring.Visible=false;ring.Parent=root
    local ringCorner=Instance.new("UICorner");ringCorner.CornerRadius=UDim.new(1,0);ringCorner.Parent=ring
    local ringStroke=Instance.new("UIStroke");ringStroke.Thickness=2;ringStroke.Color=color;ringStroke.Parent=ring
    local parts={horizontal,vertical,left,right,top,bottom,dot}
    local function update()
        root.Size=UDim2.fromOffset(size,size)
        local dotSize=math.clamp(math.floor(size/6+0.5),3,7)
        dot.Size=UDim2.fromOffset(dotSize,dotSize)
        for index,part in ipairs(parts) do part.BackgroundColor3=color;part.Visible=false end
        ringStroke.Color=color;ring.Visible=false
        horizontal.Rotation=0;vertical.Rotation=0
        if style=="บวก" then
            horizontal.Visible=true;vertical.Visible=true
        elseif style=="บวก + จุด" then
            left.Visible=true;right.Visible=true;top.Visible=true;bottom.Visible=true;dot.Visible=true
        elseif style=="จุด" then
            dot.Visible=true
        elseif style=="วงกลม" then
            ring.Visible=true
        elseif style=="วงกลม + จุด" then
            ring.Visible=true;dot.Visible=true
        elseif style=="กากบาท" then
            horizontal.Visible=true;vertical.Visible=true
            horizontal.Rotation=45;vertical.Rotation=45
        end
        gui.Enabled=visible
    end
    cleanupCrosshair=function()
        visible=false
        pcall(function() gui:Destroy() end)
    end
    toggle(aimPage,"แสดงเป้ากลางจอ","แยกจากวง FOV • เปิดปิดได้",false,function(value)
        visible=value;update()
    end)
    choice(aimPage,"รูปแบบเป้า","กดเพื่อเปลี่ยนรูปแบบ",{"บวก","บวก + จุด","จุด","วงกลม","วงกลม + จุด","กากบาท"},{},style,function(value)
        style=value;update()
    end)
    slider(aimPage,"ขนาดเป้ากลางจอ","ปรับขนาดเป้า • หน่วยพิกเซล",6,60,size,1,function(value)
        size=value;update()
    end)
    choice(aimPage,"สีเป้ากลางจอ","เลือกจากสีที่มี",ESP_COLOR_NAMES,{},"ขาว",function(name)
        color=ESP_COLORS[name];update()
    end)
    update()
end

section(espPage,"มองผู้เล่น","เปิดการแสดงข้อมูลและรูปแบบผู้เล่น")
toggle(espPage,"มองผู้เล่น (ESP)","ควบคุมข้อมูล กรอบ และโครงกระดูกผู้เล่น",CFG.ESPEnabled,function(v) CFG.ESPEnabled=v end)
section(espPage,"กรอบและโครงกระดูก","เปิดแต่ละแบบแยกกันได้")
do
    local showBox=false
    local showSkeleton=false
    local gui=Instance.new("ScreenGui")
    gui.Name="ProScriptPlayerShapes"
    gui.IgnoreGuiInset=true
    gui.ResetOnSpawn=false
    gui.DisplayOrder=90
    pcall(function() gui.Parent=game:GetService("CoreGui") end)
    if not gui.Parent then gui.Parent=LocalPlayer:WaitForChild("PlayerGui") end
    local cache={}
    local jointNames={
        head={"Bip01_Head","Head"}, neck={"Bip01_Neck","UpperTorso","Torso"},
        pelvis={"Bip01_Pelvis","LowerTorso","Torso","HumanoidRootPart"},
        leftShoulder={"Bip01_L_UpperArm","LeftUpperArm","Left Arm"},
        leftElbow={"Bip01_L_Forearm","LeftLowerArm","Left Arm"},
        leftHand={"Bip01_L_Hand","LeftHand","Left Arm"},
        rightShoulder={"Bip01_R_UpperArm","RightUpperArm","Right Arm"},
        rightElbow={"Bip01_R_Forearm","RightLowerArm","Right Arm"},
        rightHand={"Bip01_R_Hand","RightHand","Right Arm"},
        leftHip={"Bip01_L_Thigh","LeftUpperLeg","Left Leg"},
        leftKnee={"Bip01_L_Calf","LeftLowerLeg","Left Leg"},
        leftFoot={"Bip01_L_Foot","LeftFoot","Left Leg"},
        rightHip={"Bip01_R_Thigh","RightUpperLeg","Right Leg"},
        rightKnee={"Bip01_R_Calf","RightLowerLeg","Right Leg"},
        rightFoot={"Bip01_R_Foot","RightFoot","Right Leg"},
    }
    local edges={
        {"head","neck"},{"neck","pelvis"},
        {"neck","leftShoulder"},{"leftShoulder","leftElbow"},{"leftElbow","leftHand"},
        {"neck","rightShoulder"},{"rightShoulder","rightElbow"},{"rightElbow","rightHand"},
        {"pelvis","leftHip"},{"leftHip","leftKnee"},{"leftKnee","leftFoot"},
        {"pelvis","rightHip"},{"rightHip","rightKnee"},{"rightKnee","rightFoot"},
    }
    local function remove(player)
        local entry=cache[player]
        if entry then
            pcall(function() entry.box:Destroy() end)
            for index,line in ipairs(entry.lines) do pcall(function() line:Destroy() end) end
            cache[player]=nil
        end
    end
    cleanupPlayerShapes=function()
        for player in pairs(cache) do remove(player) end
        pcall(function() gui:Destroy() end)
    end
    local function hide(entry)
        entry.box.Visible=false
        for index,line in ipairs(entry.lines) do line.Visible=false end
    end
    local function create(player)
        local box=Instance.new("Frame")
        box.Name="PlayerBox";box.BackgroundTransparency=1;box.BorderSizePixel=0
        box.Visible=false;box.Parent=gui
        local outline=Instance.new("UIStroke");outline.Thickness=2;outline.Color=CFG.ColorText;outline.Parent=box
        -- Allocate skeleton lines only when that feature is actually used.
        local entry={box=box,outline=outline,lines={},visual=nil,nextScan=0};cache[player]=entry
        return entry
    end
    local function ensureSkeletonLines(entry)
        if #entry.lines>0 then return end
        for index=1,#edges do
            local line=Instance.new("Frame")
            line.Name="SkeletonLine";line.AnchorPoint=Vector2.new(.5,.5)
            line.BorderSizePixel=0;line.Visible=false;line.Parent=gui
            entry.lines[index]=line
        end
    end
    local function project(camera,position)
        local point=camera:WorldToViewportPoint(position)
        if point.Z<=0 then return nil end
        return Vector2.new(point.X,point.Y)
    end
    local function findJointNode(character,visual,key)
        for _,name in ipairs(jointNames[key]) do
            local node=(visual and visual:FindFirstChild(name,true)) or character:FindFirstChild(name,true)
            if node and (node:IsA("Bone") or node:IsA("Attachment") or node:IsA("BasePart")) then return node,name end
        end
        return nil,nil
    end
    local function jointPosition(node,name,key)
        if not node or not node.Parent then return nil end
        if node:IsA("Bone") then
            local ok,position=pcall(function() return node.TransformedWorldCFrame.Position end)
            if ok then return position end
            return node.WorldCFrame.Position
        elseif node:IsA("Attachment") then return node.WorldPosition
        elseif node:IsA("BasePart") then
            if name=="Left Arm" or name=="Right Arm" or name=="Left Leg" or name=="Right Leg" then
                local offset=0
                if key=="leftShoulder" or key=="rightShoulder" or key=="leftHip" or key=="rightHip" then offset=node.Size.Y/2
                elseif key=="leftHand" or key=="rightHand" or key=="leftFoot" or key=="rightFoot" then offset=-node.Size.Y/2 end
                return node.CFrame:PointToWorldSpace(Vector3.new(0,offset,0))
            end
            return node.Position
        end
        return nil
    end
    -- WarZ creates visible characters under HeroVisualsLocal; holder names
    -- include the hero id and character name, or carry WarzOwnerUserId.
    local function resolveVisual(entry,player,character)
        if os.clock()<entry.nextScan then
            if not entry.visual then return nil end
            if entry.visual.Parent then return entry.visual end
        end
        entry.nextScan=os.clock()+(Perf.economy and 1.5 or (Perf.max and 0.25 or 0.5))
        entry.visual=nil
        for _,folderName in ipairs({"HeroVisualsLocal","HeroVisuals"}) do
            local folder=workspace:FindFirstChild(folderName)
            if folder then
                for _,holder in ipairs(folder:GetChildren()) do
                    local owner=holder:GetAttribute("WarzOwnerUserId")
                    local suffix="_"..character.Name
                    if owner==player.UserId or (owner==nil and (holder.Name==character.Name or holder.Name:sub(-#suffix)==suffix)) then
                        entry.visual=holder:FindFirstChild("LiveAim") or holder
                        return entry.visual
                    end
                end
            end
        end
        return nil
    end
    -- Fixed world-space rectangle, projected to 2D: proportions stay stable
    -- while perspective still makes the box smaller as a player moves away.
    local function drawBox(entry,player,character,camera)
        local root=character:FindFirstChild("HumanoidRootPart")
        if not root or not root:IsA("BasePart") then entry.box.Visible=false;return end
        local center=root.Position
        local right=camera.CFrame.RightVector
        local horizontal=Vector3.new(right.X,0,right.Z)
        if horizontal.Magnitude<0.001 then horizontal=Vector3.new(1,0,0) else horizontal=horizontal.Unit end
        local halfWidth=1.65
        local bottom=3.55
        local top=2.4
        local points={
            center-horizontal*halfWidth+Vector3.new(0,top,0),
            center+horizontal*halfWidth+Vector3.new(0,top,0),
            center-horizontal*halfWidth-Vector3.new(0,bottom,0),
            center+horizontal*halfWidth-Vector3.new(0,bottom,0),
        }
        local minX,minY=math.huge,math.huge
        local maxX,maxY=-math.huge,-math.huge
        for _,position in ipairs(points) do
            local point=project(camera,position)
            if not point then entry.box.Visible=false;return end
            minX=math.min(minX,point.X);maxX=math.max(maxX,point.X)
            minY=math.min(minY,point.Y);maxY=math.max(maxY,point.Y)
        end
        -- Keep a fixed 2-pixel screen-space margin at every distance.
        local padding=2
        minX=minX-padding;maxX=maxX+padding
        minY=minY-padding;maxY=maxY+padding
        local viewport=camera.ViewportSize
        if maxX<0 or maxY<0 or minX>viewport.X or minY>viewport.Y then entry.box.Visible=false;return end
        entry.box.Position=UDim2.fromOffset(minX,minY)
        entry.box.Size=UDim2.fromOffset(math.max(2,maxX-minX),math.max(2,maxY-minY))
        entry.outline.Color=CFG.ColorText;entry.box.Visible=true
    end
    local function drawSkeleton(entry,player,character,camera)
        ensureSkeletonLines(entry)
        local visual=resolveVisual(entry,player,character)
        local now=os.clock()
        if entry.jointCharacter~=character or entry.jointVisual~=visual or now>=(entry.nextJointScan or 0) then
            entry.jointCharacter=character;entry.jointVisual=visual;entry.nextJointScan=now+(Perf.economy and 2 or (Perf.max and 0.25 or 0.5))
            entry.joints={}
            for key in pairs(jointNames) do
                local node,name=findJointNode(character,visual,key)
                if node then entry.joints[key]={node=node,name=name} end
            end
        end
        local points={}
        for key,joint in pairs(entry.joints or {}) do
            local position=jointPosition(joint.node,joint.name,key)
            if position then points[key]=project(camera,position) end
        end
        for index,edge in ipairs(edges) do
            local line=entry.lines[index]
            local first,last=points[edge[1]],points[edge[2]]
            if first and last and (last-first).Magnitude>0.1 then
                local delta=last-first
                line.Position=UDim2.fromOffset((first.X+last.X)/2,(first.Y+last.Y)/2)
                line.Size=UDim2.fromOffset(delta.Magnitude,2)
                line.Rotation=math.deg(math.atan2(delta.Y,delta.X))
                line.BackgroundColor3=CFG.ColorText;line.Visible=true
            else
                line.Visible=false
            end
        end
    end
    toggle(espPage,"กรอบรอบตัวผู้เล่น","กรอบ 2D • ปรับขนาดตามระยะ",false,function(value) showBox=value end)
    toggle(espPage,"โครงกระดูกผู้เล่น","แสดงเส้นโครงกระดูกตามตัวผู้เล่น",false,function(value) showSkeleton=value end)
    bind(Players.PlayerRemoving,remove)
    local shapeElapsed=0
    local shapesVisible=false
    bind(RunService.RenderStepped,function(dt)
        if not CFG.ESPEnabled or not (showBox or showSkeleton) then
            if shapesVisible then
                for _,entry in pairs(cache) do hide(entry) end
                shapesVisible=false
            end
            return
        end
        shapeElapsed=shapeElapsed+math.max(dt or 0,0)
        if shapeElapsed<(Perf.economy and 1/15 or (Perf.max and 1/60 or 1/30)) then return end
        shapeElapsed=0;shapesVisible=true
        local camera=workspace.CurrentCamera
        for index,player in ipairs(Players:GetPlayers()) do
            if player~=LocalPlayer then
                local character=player.Character
                local root=character and character:FindFirstChild("HumanoidRootPart")
                local valid=CFG.ESPEnabled and (showBox or showSkeleton) and camera and root and root:IsA("BasePart")
                if valid then
                    local worldDistance=(root.Position-camera.CFrame.Position).Magnitude
                    valid=worldDistance<=CFG.ESPMaxDist and isAliveRaw(player)
                    -- Far-offscreen shapes cannot be seen; skip their projections.
                    -- Keep a generous margin to avoid clipping near screen edges.
                    if valid and Perf.economy and worldDistance>80 then
                        local point=camera:WorldToViewportPoint(root.Position)
                        local view=camera.ViewportSize
                        valid=point.Z>0 and point.X>=-400 and point.X<=view.X+400
                            and point.Y>=-400 and point.Y<=view.Y+400
                    end
                end
                local entry=cache[player]
                if valid then
                    entry=entry or create(player)
                    if showBox then
                        local ok,err=pcall(drawBox,entry,player,character,camera)
                        if not ok then
                            entry.box.Visible=false
                            if not entry.boxError then entry.boxError=true;warn("ProScript player box: "..tostring(err)) end
                        end
                    else entry.box.Visible=false end
                    if showSkeleton then
                        local ok,err=pcall(drawSkeleton,entry,player,character,camera)
                        if not ok then
                            for _,line in ipairs(entry.lines) do line.Visible=false end
                            if not entry.skeletonError then entry.skeletonError=true;warn("ProScript player skeleton: "..tostring(err)) end
                        end
                    else for _,line in ipairs(entry.lines) do line.Visible=false end end
                elseif entry then hide(entry) end
            end
        end
    end)
end
toggle(espPage,"แสดงชื่อผู้เล่น","แสดงชื่อเหนือผู้เล่น",CFG.ESPName,function(v) CFG.ESPName=v end)
toggle(espPage,"แสดงระยะทาง","ใช้กับผู้เล่น ซอมบี้ และบอส",CFG.ESPDistance,function(v) CFG.ESPDistance=v end)
toggle(espPage,"แสดงพลังชีวิต","ใช้กับผู้เล่น ซอมบี้ และบอส",CFG.ESPHealth,function(v) CFG.ESPHealth=v end)
choice(espPage,"รูปแบบพลังชีวิต","เลือกตัวเลขหรือหลอดเลือด",{"ตัวเลข","หลอดเลือด"},{},CFG.ESPHealthMode,function(v) CFG.ESPHealthMode=v end)
section(espPage,"สีผู้เล่น","สีข้อความ กรอบ และโครงกระดูก")
choice(espPage,"สี ESP ผู้เล่น","กดเพื่อเลือกสี",ESP_COLOR_NAMES,{},"ขาว",function(name) CFG.ColorText=ESP_COLORS[name] end)
section(farmPage,"กระสุนดูดหัวซอมบี้","เลือกซอมบี้หรือบอสในวง FOV")
do
    if silentState and silentState.installed then
        local function pickZombieHead(origin)
            local camera=workspace.CurrentCamera
            if not camera then return nil end
            local center=Vector2.new(camera.ViewportSize.X/2,camera.ViewportSize.Y/2)
            local closest=CFG.AimbotFOV
            local best=nil
            for unusedIndex,zombie in ipairs(get66ZNpcs()) do
                if zombie:IsA("Model") and zombie.Parent
                    and zombie:GetAttribute("WarZZombieState")~="Dead" then
                    local root=npcRoot(zombie)
                    local health=zombie:FindFirstChildOfClass("Humanoid")
                    if root and root:IsA("BasePart") and (not health or health.Health>0)
                        and (root.Position-origin).Magnitude<=CFG.ESPMaxDist then
                        -- Some versions render the animated model separately from the NPC.
                        local visual=zombie:FindFirstChild("WarZZombieVisual")
                        local head=zombie:FindFirstChild("Head",true) or zombie:FindFirstChild("Bip01_Head",true)
                        if not head and visual then
                            head=visual:FindFirstChild("Head",true) or visual:FindFirstChild("Bip01_Head",true)
                        end
                        local position=nil
                        if head and head:IsA("BasePart") then
                            position=head.Position
                        elseif head and head:IsA("Bone") then
                            local ok,cf=pcall(function() return head.TransformedWorldCFrame end)
                            if ok then position=cf.Position end
                        elseif head and head:IsA("Attachment") then
                            position=head.WorldPosition
                        end
                        if position then
                            local screen,onScreen=camera:WorldToViewportPoint(position)
                            if onScreen and screen.Z>0 then
                                local distance=(Vector2.new(screen.X,screen.Y)-center).Magnitude
                                if distance<=closest and (not CFG.TargetWallCheck or hasLOS(origin,position,zombie)) then
                                    closest=distance
                                    best=position
                                end
                            end
                        end
                    end
                end
            end
            return best
        end
        -- Reuse the existing narrowly scoped FireRequest hook instead of installing a second hook.
        silentState.pickHead=pickZombieHead
        toggle(farmPage,"กระสุนดูดหัวซอมบี้","ในวง FOV • รวมบอส • ใช้ระยะ ESP",false,function(v)
            silentState.npcEnabled=v
            silentState.enabled=v
        end)
    else
        local unavailable=card(farmPage,52)
        rowLabel(unavailable,"กระสุนดูดหัวไม่พร้อม",silentStatus)
    end
end
section(farmPage,"มองซอมบี้และบอส","แยกเปิด–ปิดได้ • ใช้ระยะ ESP เดียวกัน")
do
    local showZombies=false
    local showBosses=false
    local npcFolder=Instance.new("Folder")
    npcFolder.Name="ProScript_NPC_ESP"
    pcall(function() npcFolder.Parent=game:GetService("CoreGui") end)
    if not npcFolder.Parent then npcFolder.Parent=LocalPlayer:WaitForChild("PlayerGui") end
    local cache={}
    local function remove(model)
        local entry=cache[model]
        if entry then pcall(function() entry.gui:Destroy() end);cache[model]=nil end
    end
    local function create(model)
        local gui=Instance.new("BillboardGui")
        gui.Name="NPC_ESP";gui.Size=UDim2.fromOffset(170,50);gui.AlwaysOnTop=true
        gui.StudsOffset=Vector3.new(0,3,0);gui.Enabled=false;gui.Parent=npcFolder
        local label=Instance.new("TextLabel")
        label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1
        label.TextStrokeTransparency=0;label.TextSize=12;label.Font=Enum.Font.GothamBold
        label.Parent=gui
        local bar=Instance.new("Frame")
        bar.Size=UDim2.new(.7,0,0,6);bar.Position=UDim2.new(.15,0,1,-8)
        bar.BackgroundColor3=Color3.fromRGB(24,27,34);bar.BorderSizePixel=0
        bar.Visible=false;bar.Parent=gui
        local fill=Instance.new("Frame");fill.Size=UDim2.fromScale(1,1)
        fill.BorderSizePixel=0;fill.Parent=bar
        local item={gui=gui,label=label,bar=bar,fill=fill}
        cache[model]=item
        return item
    end
    cleanupNpcEsp=function()
        for model in pairs(cache) do remove(model) end
        pcall(function() npcFolder:Destroy() end)
    end
    table.insert(Pause.callbacks,function(paused)
        if paused then for _,entry in pairs(cache) do entry.gui.Enabled=false end end
    end)
    toggle(farmPage,"มองทะลุซอมบี้","แสดงตำแหน่งและข้อมูลซอมบี้",false,function(v) showZombies=v end)
    toggle(farmPage,"มองทะลุบอส","แสดงตำแหน่งและข้อมูลบอส",false,function(v) showBosses=v end)
    choice(farmPage,"สีซอมบี้","สีข้อความ ESP ซอมบี้",ESP_COLOR_NAMES,{},"เขียวอ่อน",function(name) CFG.ColorZombie=ESP_COLORS[name] end)
    choice(farmPage,"สีบอส","สีข้อความ ESP บอส",ESP_COLOR_NAMES,{},"ส้ม",function(name) CFG.ColorBoss=ESP_COLORS[name] end)
    task.spawn(function()
        while running do
            local seen={}
            local camera=workspace.CurrentCamera
            if camera and (showZombies or showBosses) then
                for scanIndex,model in ipairs(get66ZNpcs()) do
                    if not running or not (showZombies or showBosses) then break end
                    if scanIndex%(Perf.economy and 15 or 60)==0 then task.wait() end
                    if not running or not (showZombies or showBosses) then break end
                    if model:IsA("Model") and model.Parent then
                        local isBoss=model:GetAttribute("WarZSuperZombie")==true
                        if (isBoss and showBosses) or (not isBoss and showZombies) then
                            local root=npcRoot(model)
                            local hum=model:FindFirstChildOfClass("Humanoid")
                            local alive=model:GetAttribute("WarZZombieState")~="Dead" and (not hum or hum.Health>0)
                            if root and root:IsA("BasePart") and alive then
                                local distance=(root.Position-camera.CFrame.Position).Magnitude
                                if distance<=CFG.ESPMaxDist then
                                    seen[model]=true
                                    local item=cache[model] or create(model)
                                    item.gui.Adornee=root;item.gui.Enabled=true
                                    item.gui.StudsOffset=Vector3.new(0,isBoss and 5 or 3,0)
                                    item.label.TextColor3=isBoss and CFG.ColorBoss or CFG.ColorZombie
                                    local label=isBoss and "บอส" or "ซอมบี้"
                                    if CFG.ESPDistance then label=label..string.format(" [%dm]",math.floor(distance/4)) end
                                    if CFG.ESPHealth and CFG.ESPHealthMode=="ตัวเลข" and hum then
                                        label=label..string.format(" - HP: %d/%d",math.floor(hum.Health),math.floor(hum.MaxHealth))
                                    end
                                    item.label.Text=label
                                    local showBar=CFG.ESPHealth and CFG.ESPHealthMode=="หลอดเลือด" and hum~=nil
                                    item.bar.Visible=showBar
                                    if showBar then
                                        local ratio=hum.MaxHealth>0 and math.clamp(hum.Health/hum.MaxHealth,0,1) or 0
                                        item.fill.Size=UDim2.new(ratio,0,1,0)
                                        item.fill.BackgroundColor3=Color3.fromRGB(240,75,75):Lerp(Color3.fromRGB(60,220,120),ratio)
                                    end
                                end
                            end
                        end
                    end
                end
            end
            for model in pairs(cache) do if not seen[model] then remove(model) end end
            task.wait(Perf.economy and 1.75 or (Perf.max and 0.25 or .5))
        end
    end)
end

section(farmPage,"มองไอเทม","แสดงชื่อและระยะไอเทม")
do
    local enabled=false
    local maxDistance=350
    local folder=Instance.new("Folder")
    folder.Name="ProScriptLootESP"
    pcall(function() folder.Parent=game:GetService("CoreGui") end)
    if not folder.Parent then folder.Parent=LocalPlayer:WaitForChild("PlayerGui") end
    local cache={}
    local config=nil
    local shared=game:GetService("ReplicatedStorage"):FindFirstChild("WarZSession")
    local configScript=shared and shared:FindFirstChild("ItemCatalog")
    if configScript and configScript:IsA("ModuleScript") then
        local ok,result=pcall(require,configScript)
        if ok and type(result)=="table" then config=result end
    end
    local function clear()
        for item,entry in pairs(cache) do
            pcall(function() entry.gui:Destroy() end)
            cache[item]=nil
        end
    end
    cleanupLootEsp=function()
        enabled=false
        clear()
        pcall(function() folder:Destroy() end)
    end
    local function lootName(item)
        local id=item:GetAttribute("ItemId")
        if config and type(config.get)=="function" and id~=nil then
            local ok,data=pcall(config.get,id)
            if ok and type(data)=="table" then
                local label=data.name or data.displayName or data.Name
                if type(label)=="string" and label~="" then return label end
            end
        end
        return id~=nil and ("ไอเทม "..tostring(id)) or item.Name
    end
    local function makeEntry(item)
        local gui=Instance.new("BillboardGui")
        gui.Name="LootESP";gui.Size=UDim2.fromOffset(200,38)
        gui.StudsOffset=Vector3.new(0,1.5,0);gui.AlwaysOnTop=true;gui.Parent=folder
        local label=Instance.new("TextLabel")
        label.Size=UDim2.fromScale(1,1);label.BackgroundTransparency=1
        label.TextColor3=CFG.ColorLoot;label.TextStrokeTransparency=0
        label.TextSize=12;label.Font=Enum.Font.GothamBold;label.Parent=gui
        local entry={gui=gui,label=label}
        cache[item]=entry
        return entry
    end
    toggle(farmPage,"มองไอเทม","แสดงชื่อทะลุสิ่งกีดขวาง • เปิดปิดได้",false,function(value)
        enabled=value
        if not value then clear() end
    end)
    slider(farmPage,"ระยะมองไอเทม","ระยะสูงสุด • หน่วย studs",50,1500,maxDistance,25,function(value)
        maxDistance=value
    end)
    choice(farmPage,"สีไอเทม","สีข้อความ ESP ไอเทม",ESP_COLOR_NAMES,{},"ทอง",function(name)
        CFG.ColorLoot=ESP_COLORS[name]
    end)
    task.spawn(function()
        while running do
            if enabled then
                local loot=workspace:FindFirstChild("WarZWorldDrops")
                local camera=workspace.CurrentCamera
                local seen={}
                if loot and camera then
                    for scanIndex,item in ipairs(loot:GetChildren()) do
                        if not running or not enabled then break end
                        if scanIndex%(Perf.economy and 15 or 60)==0 then task.wait() end
                        if not running or not enabled then break end
                        local part=nil
                        if item:IsA("BasePart") then part=item
                        elseif item:IsA("Model") then part=item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart",true) end
                        if part and item:GetAttribute("DropId")~=nil then
                            local distance=(part.Position-camera.CFrame.Position).Magnitude
                            if distance<=maxDistance then
                                seen[item]=true
                                local entry=cache[item] or makeEntry(item)
                                entry.gui.Adornee=part
                                entry.label.TextColor3=CFG.ColorLoot
                                entry.label.Text=lootName(item).." ["..math.floor(distance).." studs]"
                            end
                        end
                    end
                end
                for item,entry in pairs(cache) do
                    if not seen[item] then
                        pcall(function() entry.gui:Destroy() end)
                        cache[item]=nil
                    end
                end
            end
            task.wait(Perf.economy and 2 or (Perf.max and 0.3 or 0.6))
        end
    end)
end

section(farmPage,"ตกปลา","ยังไม่ได้เชื่อมระบบของแมพนี้")
do local row=card(farmPage,52);rowLabel(row,"ตกปลาอัตโนมัติ / ระยะเหวี่ยง","ยังไม่พร้อม • ต้องตรวจระบบเกมเพิ่มเติม") end

section(espPage,"ระยะการแสดงผล","ค่านี้ใช้กับ ESP เท่านั้น ไม่ใช่ระยะล็อกเป้า")
slider(espPage,"ระยะ ESP สูงสุด","ผู้เล่น ซอมบี้ และบอส • หน่วย studs",100,5000,CFG.ESPMaxDist,50,function(v) CFG.ESPMaxDist=v end)

section(otherPage,"ประสิทธิภาพ","เลือกความถี่อัปเดต ESP โดยไม่ปิดฟังก์ชัน")
choice(otherPage,"โหมดประสิทธิภาพ","ประหยัด • สมดุล • MAX อัปเดตไวสุด",{"ประหยัด","สมดุล","แสดงเต็ม MAX"},{},"สมดุล",function(value)
    Perf.economy=value=="ประหยัด"
    Perf.max=value=="แสดงเต็ม MAX"
end)
section(otherPage,"ฟังชั่นเสริม","ตั้งค่าฟังก์ชันสำหรับการเล่น")
do
    local row=card(otherPage,52)
    rowLabel(row,"เก็บของไว","ยังไม่พร้อม • เกมระบุเวลารอ 1 วินาที")
end
do
    local row=card(otherPage,52);rowLabel(row,"ลดแรงดีด / ลดกระจาย","ยังไม่พร้อม • ระบบยิงต่างจากเกมเดิม")
end
do
    local row=card(otherPage,52);rowLabel(row,"ใช้ยาอัตโนมัติ","ยังไม่พร้อม • ต้องตรวจระบบ QuickHeal เพิ่มเติม")
end
do
    local enabled=false
    local percent=120
    local stepName="ProScript_WalkSpeed_"..tostring(math.random(100000,999999))
    local lastHumanoid=nil
    local baseSpeed=nil
    local appliedSpeed=nil
    local function restore()
        if lastHumanoid and baseSpeed~=nil and appliedSpeed~=nil then
            pcall(function()
                if math.abs(lastHumanoid.WalkSpeed-appliedSpeed)<0.001 then
                    lastHumanoid.WalkSpeed=baseSpeed
                end
            end)
        end
        lastHumanoid=nil
        baseSpeed=nil
        appliedSpeed=nil
    end
    stopWalkSpeed=function()
        enabled=false
        pcall(function() RunService:UnbindFromRenderStep(stepName) end)
        restore()
    end
    local function updateSpeed()
        if not enabled or not running then return end
        local character=LocalPlayer.Character
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        if humanoid~=lastHumanoid then
            restore()
            lastHumanoid=humanoid
        end
        if not humanoid or humanoid.Health<=0 then return end
        local current=humanoid.WalkSpeed
        -- When the game changes stance, take its new speed as the baseline.
        if appliedSpeed==nil or math.abs(current-appliedSpeed)>0.001 then
            baseSpeed=current
        end
        if baseSpeed and baseSpeed>0 then
            appliedSpeed=baseSpeed*percent/100
            if math.abs(current-appliedSpeed)>0.001 then humanoid.WalkSpeed=appliedSpeed end
        else
            appliedSpeed=nil
        end
    end
    toggle(otherPage,"เพิ่มความเร็วเดิน","เปิดหรือปิด • เริ่มต้นปิด",false,function(value)
        if not value then
            stopWalkSpeed()
            return
        end
        enabled=true
        -- Apply after the game's CSGO_PlayerStance render step.
        RunService:BindToRenderStep(stepName,Enum.RenderPriority.Character.Value+2,updateSpeed)
    end)
    slider(otherPage,"ความเร็วเดิน (%)","ทดลองฝั่งเครื่อง • สูงสุด 135%",100,135,percent,5,function(value)
        percent=value
    end)
end

section(otherPage,"พักและรีเซ็ต","พักชั่วคราวหรือคืนค่าเริ่มต้น")
do
do
    local row=card(otherPage,52)
    rowLabel(row,"พักทุกฟังก์ชัน","กลับมาทำงานได้โดยไม่ต้องรันใหม่")
    local control=button(row,"พักทั้งหมด")
    control.Size=UDim2.fromOffset(112,30)
    control.Position=UDim2.new(1,-126,.5,-15)
    control.BackgroundColor3=C.accentDark;corner(control,8)
    bind(control.MouseButton1Click,function()
        Pause.active=not Pause.active
        aimHeld=false; aimArmed=false; lockedPlayer=nil
        if Pause.active then
            if fovCircle then fovCircle.Visible=false end
            for _,entry in pairs(espCache) do entry.billboard.Enabled=false end
        end
        control.Text=Pause.active and "กลับมาทำงาน" or "พักทั้งหมด"
        control.BackgroundColor3=Pause.active and Color3.fromRGB(164,58,72) or C.accentDark
        local failures=0
        for _,callback in ipairs(Pause.callbacks) do
            local ok,err=pcall(callback,Pause.active)
            if not ok then failures=failures+1;warn("พัก/กลับมาทำงาน: "..tostring(err)) end
        end
        if failures>0 then warn("บางฟังก์ชันเปลี่ยนสถานะไม่สำเร็จ: "..tostring(failures)) end
    end)
end
    local resetRow=card(otherPage,52)
    rowLabel(resetRow,"รีเซ็ตการตั้งค่าทั้งหมด","กดเพื่อยืนยันหรือยกเลิก")
    local resetButton=button(resetRow,"รีเซ็ต")
    resetButton.Size=UDim2.fromOffset(120,30)
    resetButton.Position=UDim2.new(1,-134,.5,-15)
    resetButton.BackgroundColor3=C.accentDark
    corner(resetButton,8)
    local version=0
    local modal=nil
    local function applyReset()
        version=version+1
        Settings.serial=Settings.serial+1
        local failures=0
        for index,reset in ipairs(Settings.resetters) do
            local ok,reason=pcall(reset)
            if not ok then failures=failures+1;warn("รีเซ็ตไม่สำเร็จ: "..tostring(reason)) end
        end
        Settings.values={}
        local saved=not Settings.available or Settings.save()
        resetButton.Text=failures==0 and saved and "รีเซ็ตแล้ว" or "ตรวจสอบสถานะ"
        resetButton.BackgroundColor3=failures==0 and saved and C.accentDark or Color3.fromRGB(164,58,72)
        if failures>0 then Settings.status.Text="บางค่ารีเซ็ตไม่สำเร็จ"
        elseif not saved then Settings.status.Text="บันทึกไม่สำเร็จ"
        elseif not Settings.available then Settings.status.Text="ตัวรันไม่รองรับไฟล์" end
        local ticket=version
        task.delay(3,function()
            if running and ticket==version and resetButton.Parent then
                resetButton.Text="รีเซ็ต";resetButton.BackgroundColor3=C.accentDark
            end
        end)
    end
    bind(resetButton.MouseButton1Click,function()
        if modal and modal.Parent then return end
        modal=Instance.new("Frame")
        modal.Name="ResetConfirmation"
        modal.Size=UDim2.fromScale(1,1)
        modal.BackgroundColor3=Color3.fromRGB(0,0,0)
        modal.BackgroundTransparency=.35
        modal.BorderSizePixel=0
        modal.Active=true
        modal.ZIndex=100
        modal.Parent=Window
        local panel=Instance.new("Frame")
        panel.AnchorPoint=Vector2.new(.5,.5)
        panel.Position=UDim2.fromScale(.5,.5)
        panel.Size=UDim2.fromOffset(330,180)
        panel.BackgroundColor3=C.panel
        panel.BorderSizePixel=0
        panel.ZIndex=101
        panel.Parent=modal
        corner(panel,14);stroke(panel,C.border)
        local heading=text(panel,"รีเซ็ตการตั้งค่าทั้งหมด?",16,C.text,Enum.Font.GothamBold)
        heading.Position=UDim2.fromOffset(20,18);heading.Size=UDim2.new(1,-40,0,24);heading.ZIndex=102
        local detail=text(panel,"ค่าปัจจุบันและค่าที่บันทึกไว้จะกลับเป็นค่าเริ่มต้น",11,C.muted)
        detail.Position=UDim2.fromOffset(20,52);detail.Size=UDim2.new(1,-40,0,42)
        detail.TextWrapped=true;detail.TextYAlignment=Enum.TextYAlignment.Top;detail.ZIndex=102
        local cancel=button(panel,"ยกเลิก")
        cancel.Size=UDim2.fromOffset(130,36);cancel.Position=UDim2.new(1,-150,1,-56)
        cancel.BackgroundColor3=C.card;cancel.ZIndex=102;corner(cancel,8)
        local confirm=button(panel,"ยืนยัน")
        confirm.Size=UDim2.fromOffset(130,36);confirm.Position=UDim2.new(0,20,1,-56)
        confirm.BackgroundColor3=Color3.fromRGB(164,58,72);confirm.ZIndex=102;corner(confirm,8)
        local function closeModal()
            if modal then modal:Destroy();modal=nil end
        end
        cancel.MouseButton1Click:Connect(closeModal)
        confirm.MouseButton1Click:Connect(function()
            closeModal()
            applyReset()
        end)
    end)
end

section(otherPage,"บันทึกและออกจากเกม","สถานะการบันทึกและปุ่มออกเซิร์ฟเวอร์")
do
    local row=card(otherPage,52)
    rowLabel(row,"สถานะการบันทึก","ใช้ไฟล์ในตัวรัน • รวมสถานะเปิดปิด")
    local status=text(row,Settings.available and "พร้อมบันทึก" or "ตัวรันไม่รองรับ",10,C.muted,Enum.Font.GothamBold)
    status.Position=UDim2.new(1,-144,0,15);status.Size=UDim2.fromOffset(132,22)
    status.TextXAlignment=Enum.TextXAlignment.Right
    Settings.status=status
    local row=card(otherPage,52)
    rowLabel(row,"ออกจากเซิร์ฟเวอร์","กดเพื่อยืนยันหรือยกเลิก")
    local disconnect=button(row,"ออกทันที")
    disconnect.Size=UDim2.fromOffset(120,30)
    disconnect.Position=UDim2.new(1,-134,.5,-15)
    disconnect.BackgroundColor3=Color3.fromRGB(164,58,72)
    corner(disconnect,8)
    local modal=nil
    bind(disconnect.MouseButton1Click, function()
        if modal and modal.Parent then return end
        modal=Instance.new("Frame")
        modal.Name="ExitConfirmation"
        modal.Size=UDim2.fromScale(1,1)
        modal.BackgroundColor3=Color3.fromRGB(0,0,0)
        modal.BackgroundTransparency=.35
        modal.BorderSizePixel=0
        modal.Active=true
        modal.ZIndex=100
        modal.Parent=Window
        local panel=Instance.new("Frame")
        panel.AnchorPoint=Vector2.new(.5,.5)
        panel.Position=UDim2.fromScale(.5,.5)
        panel.Size=UDim2.fromOffset(330,180)
        panel.BackgroundColor3=C.panel
        panel.BorderSizePixel=0
        panel.ZIndex=101
        panel.Parent=modal
        corner(panel,14);stroke(panel,C.border)
        local heading=text(panel,"ออกจากเซิร์ฟเวอร์?",16,C.text,Enum.Font.GothamBold)
        heading.Position=UDim2.fromOffset(20,18);heading.Size=UDim2.new(1,-40,0,24);heading.ZIndex=102
        local detail=text(panel,"หากยืนยัน จะออกจากเซิร์ฟเวอร์ทันที และต้องเข้าใหม่ด้วยตัวเอง",11,C.muted)
        detail.Position=UDim2.fromOffset(20,52);detail.Size=UDim2.new(1,-40,0,42)
        detail.TextWrapped=true;detail.TextYAlignment=Enum.TextYAlignment.Top;detail.ZIndex=102
        local cancel=button(panel,"ยกเลิก")
        cancel.Size=UDim2.fromOffset(130,36);cancel.Position=UDim2.new(1,-150,1,-56)
        cancel.BackgroundColor3=C.card;cancel.ZIndex=102;corner(cancel,8)
        local confirm=button(panel,"ยืนยัน")
        confirm.Size=UDim2.fromOffset(130,36);confirm.Position=UDim2.new(0,20,1,-56)
        confirm.BackgroundColor3=Color3.fromRGB(164,58,72);confirm.ZIndex=102;corner(confirm,8)
        local function closeModal()
            if modal then modal:Destroy();modal=nil end
        end
        cancel.MouseButton1Click:Connect(closeModal)
        confirm.MouseButton1Click:Connect(function()
            closeModal()
            LocalPlayer:Kick("ออกจากเซิร์ฟเวอร์ตามคำขอ")
        end)
    end)
end

