local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Camera = workspace.CurrentCamera

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local RISC_V = require(ReplicatedStorage:WaitForChild("RISC-V_Emulator"))

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "RISCVGUI"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 500, 0, 350)
frame.Position = UDim2.new(0.5, -250, 0.5, -175)
frame.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
frame.BorderSizePixel = 2
frame.BorderColor3 = Color3.fromRGB(0, 255, 65)
frame.Parent = screenGui

local titleBar = Instance.new("TextButton")
titleBar.Size = UDim2.new(1, 0, 0, 26)
titleBar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
titleBar.BorderSizePixel = 0
titleBar.Text = " this is risc-v emu (no mmu)"
titleBar.TextColor3 = Color3.fromRGB(0, 255, 65)
titleBar.TextSize = 13
titleBar.Font = Enum.Font.Code
titleBar.TextXAlignment = Enum.TextXAlignment.Left
titleBar.Parent = frame

local consoleLog = Instance.new("TextLabel")
consoleLog.Size = UDim2.new(1, -10, 1, -36)
consoleLog.Position = UDim2.new(0, 5, 0, 31)
consoleLog.BackgroundTransparency = 1
consoleLog.TextColor3 = Color3.fromRGB(180, 180, 180)
consoleLog.TextSize = 12
consoleLog.Font = Enum.Font.Code
consoleLog.TextXAlignment = Enum.TextXAlignment.Left
consoleLog.TextYAlignment = Enum.TextYAlignment.Top
consoleLog.TextWrapped = true
consoleLog.Parent = frame

local dragging = false
local dragStart, startPos

titleBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = frame.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
		local delta = input.Position - dragStart
		frame.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + delta.X,
			startPos.Y.Scale,
			startPos.Y.Offset + delta.Y
		)
	end
end)

local code = [[
    li t0, 0x6c6c6548
    li t1, 100
    sw t0, 0(t1)
    li t0, 0x57206f6c
    sw t0, 4(t1)
    li t0, 0x646c726f
    sw t0, 8(t1)
    li t0, 0x00000a21
    sw t0, 12(t1)
    li a7, 64
    li a0, 1
    mv a1, t1
    li a2, 14
    ecall
    li a7, 93
    li a0, 0
    ecall
]]

RISC_V:init()
local bytes = RISC_V:assemble(code)
RISC_V:load_program(bytes)
RISC_V:run(100)

consoleLog.Text = RISC_V:get_log()
