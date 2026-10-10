-- ==========================================================
-- KYÔKA HUB • BACKEND & CORE FUNCTIONS
-- Project Slayers 2 BY SHADOW
-- ==========================================================

if getgenv().Kyoka_Loaded then return end
getgenv().Kyoka_Loaded = true

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

local RS = ReplicatedStorage

-- [1] TABELA GLOBAL DE FLAGS E VARIÁVEIS
getgenv().KyokaFlags = {
    AutoFarmLevel = false,
    AutoFarmMob = false,
    SelectedMob = "Bandit",
    FlySpeed = 22,
    AutoAttack = false,
    AutoSkill = false,
    SelectedSkill = "Q",
    AntiSun = false,
    AntiDrown = false,
    Fullbright = false
}

local Flags = getgenv().KyokaFlags
getgenv().KyokaCore = {}
local Core = getgenv().KyokaCore

-- [2] REQUISIÇÃO DOS MÓDULOS NATIVOS DO JOGO
pcall(function()
    Core.Utility = require(RS.CAM.Global.Utility)
    Core.gameSettings = require(RS.CAM.Global.gameSettings)
    Core.MinigameSettings = require(RS.CAM.Global.MinigameSettings)
    Core.SignalEvent = require(RS.Communication.ServerAndClient.Signals.SignalEvent)
    Core.SignalFunction = require(RS.Communication.ServerAndClient.Signals.SignalFunction)
    Core.SkillController = require(RS.CAM.Client.Controllers.Skill_Controller)
end)

-- [3] HOOKS ANTI-SUN & ANTI-DROWN
pcall(function()
    if Core.MinigameSettings and Core.MinigameSettings.Get then
        local origGet = Core.MinigameSettings.Get
        Core.MinigameSettings.Get = function(key, ...)
            if key == "NoSunDamage" and Flags.AntiSun then return true end
            return origGet(key, ...)
        end
    end

    if Core.SignalFunction and Core.SignalFunction.ToServer then
        local origToServer = Core.SignalFunction.ToServer
        Core.SignalFunction.ToServer = function(name, inSun, ...)
            if name == "SunDamage" and inSun == true and Flags.AntiSun then
                return origToServer(name, false, ...)
            end
            return origToServer(name, inSun, ...)
        end
    end

    if Core.SignalEvent and Core.SignalEvent.ToServer then
        local origEventToServer = Core.SignalEvent.ToServer
        Core.SignalEvent.ToServer = function(name, action, ...)
            if name == "Swim" and action == "DrownDamage" and Flags.AntiDrown then
                return nil
            end
            return origEventToServer(name, action, ...)
        end
    end
end)

-- [4] NOCLIP EM TEMPO REAL
RunService.Stepped:Connect(function()
    if Flags.AutoFarmLevel or Flags.AutoFarmMob then
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = false
                end
            end
        end
    end
end)

-- [5] FUNÇÕES AUXILIARES
function Core.GetLevel()
    local playerLevelStr = "N/A"
    pcall(function()
        if Core.Utility and Core.gameSettings then
            local slot = Core.Utility.GetData(LocalPlayer, true)
            if slot and slot.Exp and slot.Exp.Goal then
                playerLevelStr = tostring(math.floor(slot.Exp.Goal.Value / Core.gameSettings.expPerLevel))
            end
        end
    end)
    return playerLevelStr
end

function Core.GetClosestMob(targetName)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local closest, shortestDist = nil, math.huge
    local regionsFolder = workspace:FindFirstChild("Humanoids") and workspace.Humanoids:FindFirstChild("Regions")

    if regionsFolder then
        for _, region in ipairs(regionsFolder:GetChildren()) do
            local active = region:FindFirstChild("ActiveNpcs")
            for _, folder in ipairs(active and active:GetChildren() or {}) do
                local rig = folder:FindFirstChild(folder.Name)
                if rig and rig:GetAttribute("IsMob") == true then
                    local hum = rig:FindFirstChildOfClass("Humanoid")
                    local root = rig:FindFirstChild("HumanoidRootPart")
                    
                    if hum and hum.Health > 0 and root then
                        if not targetName or rig.Name:lower():find(targetName:lower()) or folder.Name:lower():find(targetName:lower()) then
                            local dist = (root.Position - hrp.Position).Magnitude
                            if dist < shortestDist then
                                shortestDist = dist
                                closest = rig
                            end
                        end
                    end
                end
            end
        end
    end
    return closest
end

-- [6] LOOPS DE AUTOMAÇÃO
task.spawn(function()
    while true do
        local deltaTime = task.wait(0.03)
        if Flags.AutoFarmLevel or Flags.AutoFarmMob then
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local hrp = char and char:FindFirstChild("HumanoidRootPart")

            if char and hum and hrp and hum.Health > 0 then
                local targetMob = Core.GetClosestMob(Flags.AutoFarmMob and Flags.SelectedMob or nil)

                if targetMob then
                    local mHrp = targetMob:FindFirstChild("HumanoidRootPart")
                    if mHrp then
                        local targetPos = mHrp.Position + Vector3.new(0, 2, 0)
                        local distance = (targetPos - hrp.Position).Magnitude

                        if distance > 4 then
                            local direction = (targetPos - hrp.Position).Unit
                            local moveAmount = direction * math.min(distance, Flags.FlySpeed * deltaTime)
                            hrp.CFrame = CFrame.new(hrp.Position + moveAmount, targetPos)
                        else
                            hrp.CFrame = CFrame.new(hrp.Position, mHrp.Position)
                            if Core.SignalEvent and Core.SignalEvent.ToServer then
                                pcall(function()
                                    Core.SignalEvent.ToServer("Tool_Mouse", "Down", mHrp.Position)
                                    task.wait(0.05)
                                    Core.SignalEvent.ToServer("Tool_Mouse", "Up", mHrp.Position)
                                end)
                            end
                        end
                    end
                end
            end
        end
    end
end)

task.spawn(function()
    while task.wait(0.15) do
        if Flags.AutoAttack and Core.SignalEvent then
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if hrp then
                pcall(function()
                    Core.SignalEvent.ToServer("Tool_Mouse", "Down", hrp.Position + hrp.CFrame.LookVector * 5)
                    task.wait(0.05)
                    Core.SignalEvent.ToServer("Tool_Mouse", "Up", hrp.Position + hrp.CFrame.LookVector * 5)
                end)
            end
        end
    end
end)

task.spawn(function()
    while task.wait(1) do
        if Flags.AutoSkill and Core.SkillController then
            pcall(function()
                Core.SkillController.Attempt_Hold(Flags.SelectedSkill, nil)
                task.wait(0.3)
                Core.SkillController.UnHoldBoolean = true
            end)
        end
    end
end)

print("[KYÔKA CORE] Módulos e Funções Carregados com Sucesso!")
