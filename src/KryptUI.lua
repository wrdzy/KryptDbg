--[[
    KryptUI

    A compact retained-mode UI library built specifically for KryptDbg.
    It owns the single application shell and exposes consistent primitives to
    every lazy-loaded feature module.
]]

local KryptUI = {}

KryptUI.Theme = {
    canvas = Color3.fromRGB(16, 18, 23),
    chrome = Color3.fromRGB(21, 24, 30),
    surface = Color3.fromRGB(27, 30, 38),
    surfaceRaised = Color3.fromRGB(33, 37, 46),
    surfaceHover = Color3.fromRGB(40, 45, 56),
    input = Color3.fromRGB(20, 23, 29),
    border = Color3.fromRGB(50, 56, 69),
    borderSoft = Color3.fromRGB(39, 44, 54),
    text = Color3.fromRGB(235, 238, 245),
    textMuted = Color3.fromRGB(150, 158, 176),
    textFaint = Color3.fromRGB(103, 112, 132),
    accent = Color3.fromRGB(73, 137, 255),
    accentSoft = Color3.fromRGB(32, 58, 102),
    cyan = Color3.fromRGB(58, 200, 230),
    green = Color3.fromRGB(72, 194, 125),
    yellow = Color3.fromRGB(235, 183, 75),
    red = Color3.fromRGB(236, 92, 104),
    transparent = Color3.fromRGB(255, 255, 255),
}

KryptUI.Metrics = {
    radius = 8,
    header = 48,
    rail = 74,
    status = 28,
    toolbar = 42,
    row = 32,
}

local Theme = KryptUI.Theme
local Metrics = KryptUI.Metrics

function KryptUI.create(className, properties, children)
    local instance = Instance.new(className)

    for property, value in pairs(properties or {}) do
        if property ~= "Parent" then
            instance[property] = value
        end
    end

    for _, child in ipairs(children or {}) do
        child.Parent = instance
    end

    if properties and properties.Parent then
        instance.Parent = properties.Parent
    end

    return instance
end

function KryptUI.corner(parent, radius)
    return KryptUI.create("UICorner", {
        CornerRadius = UDim.new(0, radius or Metrics.radius),
        Parent = parent,
    })
end

function KryptUI.stroke(parent, color, transparency, thickness)
    return KryptUI.create("UIStroke", {
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Color = color or Theme.border,
        Transparency = transparency or 0,
        Thickness = thickness or 1,
        Parent = parent,
    })
end

function KryptUI.padding(parent, left, right, top, bottom)
    return KryptUI.create("UIPadding", {
        PaddingLeft = UDim.new(0, left or 0),
        PaddingRight = UDim.new(0, right or left or 0),
        PaddingTop = UDim.new(0, top or left or 0),
        PaddingBottom = UDim.new(0, bottom or top or left or 0),
        Parent = parent,
    })
end

function KryptUI.list(parent, direction, spacing, horizontalAlignment)
    return KryptUI.create("UIListLayout", {
        FillDirection = direction or Enum.FillDirection.Vertical,
        HorizontalAlignment = horizontalAlignment or Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, spacing or 0),
        Parent = parent,
    })
end

function KryptUI.Signal()
    local signal = {
        listeners = {},
        destroyed = false,
    }

    function signal:connect(callback)
        if self.destroyed then
            return { Disconnect = function() end }
        end

        local listener = { callback = callback, connected = true }
        table.insert(self.listeners, listener)

        return {
            Disconnect = function()
                listener.connected = false
            end,
        }
    end

    function signal:fire(...)
        if self.destroyed then
            return
        end

        for _, listener in ipairs(self.listeners) do
            if listener.connected then
                task.spawn(listener.callback, ...)
            end
        end
    end

    function signal:destroy()
        self.destroyed = true
        self.listeners = {}
    end

    return signal
end

local function textObject(className, properties)
    local defaults = {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Font = Enum.Font.Gotham,
        TextColor3 = Theme.text,
        TextSize = 12,
    }

    for key, value in pairs(properties or {}) do
        defaults[key] = value
    end

    return KryptUI.create(className, defaults)
end

function KryptUI.label(properties)
    return textObject("TextLabel", properties)
end

function KryptUI.button(properties)
    local options = properties or {}
    local button = textObject("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = options.BackgroundColor3 or Theme.surfaceRaised,
        BackgroundTransparency = options.BackgroundTransparency or 0,
        BorderSizePixel = 0,
        Font = options.Font or Enum.Font.GothamMedium,
        Position = options.Position or UDim2.fromOffset(0, 0),
        Size = options.Size or UDim2.fromOffset(options.Width or 92, options.Height or 30),
        Text = options.Text or "Button",
        TextColor3 = options.TextColor3 or Theme.text,
        TextSize = options.TextSize or 11,
        LayoutOrder = options.LayoutOrder or 0,
        Parent = options.Parent,
    })
    KryptUI.corner(button, options.Radius or 6)
    KryptUI.stroke(button, options.StrokeColor or Theme.border, options.StrokeTransparency or 0.25)

    local base = button.BackgroundColor3
    button.MouseEnter:Connect(function()
        if button.Parent then
            button.BackgroundColor3 = options.HoverColor or Theme.surfaceHover
        end
    end)
    button.MouseLeave:Connect(function()
        if button.Parent then
            button.BackgroundColor3 = base
        end
    end)

    return button
end

function KryptUI.input(properties)
    local options = properties or {}
    local input = textObject("TextBox", {
        BackgroundColor3 = options.BackgroundColor3 or Theme.input,
        BorderSizePixel = 0,
        ClearTextOnFocus = options.ClearTextOnFocus == true,
        Font = options.Font or Enum.Font.Code,
        MultiLine = options.MultiLine == true,
        PlaceholderColor3 = Theme.textFaint,
        PlaceholderText = options.PlaceholderText or "",
        Position = options.Position or UDim2.fromOffset(0, 0),
        Size = options.Size or UDim2.fromOffset(options.Width or 220, options.Height or 30),
        LayoutOrder = options.LayoutOrder or 0,
        Text = options.Text or "",
        TextColor3 = options.TextColor3 or Theme.text,
        TextSize = options.TextSize or 12,
        TextWrapped = options.TextWrapped == true,
        TextXAlignment = options.TextXAlignment or Enum.TextXAlignment.Left,
        TextYAlignment = options.TextYAlignment or Enum.TextYAlignment.Center,
        Parent = options.Parent,
    })
    KryptUI.corner(input, options.Radius or 6)
    KryptUI.stroke(input, Theme.border, 0.2)
    KryptUI.padding(input, options.Padding or 10, options.Padding or 10, 0, 0)
    return input
end

function KryptUI.panel(properties)
    local options = properties or {}
    local panel = KryptUI.create("Frame", {
        BackgroundColor3 = options.BackgroundColor3 or Theme.surface,
        BackgroundTransparency = options.BackgroundTransparency or 0,
        BorderSizePixel = 0,
        ClipsDescendants = options.ClipsDescendants == true,
        Position = options.Position or UDim2.fromOffset(0, 0),
        Size = options.Size or UDim2.fromScale(1, 1),
        LayoutOrder = options.LayoutOrder or 0,
        Parent = options.Parent,
    })

    if options.Corner ~= false then
        KryptUI.corner(panel, options.Radius or Metrics.radius)
    end
    if options.Stroke ~= false then
        KryptUI.stroke(panel, options.StrokeColor or Theme.borderSoft, options.StrokeTransparency or 0)
    end

    return panel
end

function KryptUI.toolbar(parent)
    local frame = KryptUI.create("Frame", {
        BackgroundColor3 = Theme.chrome,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, Metrics.toolbar),
        Parent = parent,
    })
    KryptUI.padding(frame, 10, 10, 6, 6)
    KryptUI.list(frame, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Left)
    return frame
end

function KryptUI.scroller(properties)
    local options = properties or {}
    local scroller = KryptUI.create("ScrollingFrame", {
        Active = true,
        AutomaticCanvasSize = options.AutomaticCanvasSize or Enum.AutomaticSize.Y,
        BackgroundColor3 = options.BackgroundColor3 or Theme.canvas,
        BackgroundTransparency = options.BackgroundTransparency or 0,
        BorderSizePixel = 0,
        CanvasSize = UDim2.fromOffset(0, 0),
        Position = options.Position or UDim2.fromOffset(0, 0),
        ScrollBarImageColor3 = Theme.border,
        ScrollBarThickness = options.ScrollBarThickness or 5,
        Size = options.Size or UDim2.fromScale(1, 1),
        Parent = options.Parent,
    })

    if options.Padding ~= false then
        KryptUI.padding(scroller, options.Padding or 8, options.Padding or 8, options.Padding or 8, options.Padding or 8)
    end

    local layout = KryptUI.list(scroller, Enum.FillDirection.Vertical, options.Spacing or 4)
    return scroller, layout
end

function KryptUI.section(parent, title, detail)
    local section = KryptUI.panel({
        Parent = parent,
        Size = UDim2.new(1, 0, 0, 48),
        StrokeTransparency = 0.2,
    })

    KryptUI.label({
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromOffset(12, 7),
        Size = UDim2.new(1, -24, 0, 18),
        Text = title or "Section",
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = section,
    })
    KryptUI.label({
        Position = UDim2.fromOffset(12, 24),
        Size = UDim2.new(1, -24, 0, 16),
        Text = detail or "",
        TextColor3 = Theme.textMuted,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = section,
    })

    return section
end

function KryptUI.empty(parent, title, detail)
    local frame = KryptUI.create("Frame", {
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Parent = parent,
    })
    KryptUI.label({
        AnchorPoint = Vector2.new(0.5, 0.5),
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromScale(0.5, 0.46),
        Size = UDim2.new(1, -40, 0, 24),
        Text = title or "Nothing here",
        TextColor3 = Theme.textMuted,
        TextSize = 14,
        Parent = frame,
    })
    KryptUI.label({
        AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, -64, 0, 34),
        Text = detail or "",
        TextColor3 = Theme.textFaint,
        TextSize = 11,
        TextWrapped = true,
        Parent = frame,
    })
    return frame
end

function KryptUI.clear(parent, preserve)
    local keep = preserve or {}
    for _, child in ipairs(parent:GetChildren()) do
        if not keep[child] and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
            child:Destroy()
        end
    end
end

local Window = {}
Window.__index = Window

local function viewportSize()
    local camera = workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(1280, 720)
end

local function clampWindow(frame, position, size, minimum, maximum)
    local viewport = viewportSize()
    local width = math.clamp(size.X, minimum.X, math.min(maximum.X, viewport.X - 24))
    local height = math.clamp(size.Y, minimum.Y, math.min(maximum.Y, viewport.Y - 24))
    local x = math.clamp(position.X, 12, math.max(12, viewport.X - width - 12))
    local y = math.clamp(position.Y, 12, math.max(12, viewport.Y - height - 12))

    frame.Position = UDim2.fromOffset(x, y)
    frame.Size = UDim2.fromOffset(width, height)
end

function KryptUI.new(options)
    local self = setmetatable({}, Window)
    local config = options or {}
    local Players = game:GetService("Players")
    local UserInputService = game:GetService("UserInputService")
    local TweenService = game:GetService("TweenService")

    self.connections = {}
    self.tabs = {}
    self.destroyed = false
    self.activeTab = nil
    self.minimum = config.MinimumSize or Vector2.new(860, 520)
    self.maximum = config.MaximumSize or Vector2.new(1380, 860)
    self.onTabSelected = KryptUI.Signal()
    self.onDestroyed = KryptUI.Signal()

    local parent = config.Parent
    if not parent then
        local getHui = rawget((getgenv and getgenv()) or _G, "gethui")
        if type(getHui) == "function" then
            local ok, result = pcall(getHui)
            if ok then
                parent = result
            end
        end
    end
    parent = parent or game:GetService("CoreGui")

    local screen = KryptUI.create("ScreenGui", {
        DisplayOrder = 1000000,
        IgnoreGuiInset = true,
        Name = config.Name or "KryptDbg",
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    local parented = pcall(function()
        screen.Parent = parent
    end)
    if not parented then
        local player = Players.LocalPlayer
        local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
        if not playerGui then
            screen:Destroy()
            error("KryptUI could not find a permitted GUI parent")
        end
        screen.Parent = playerGui
    end
    self.screen = screen

    local initial = config.Size or Vector2.new(1080, 680)
    local position = Vector2.new(
        math.max(12, math.floor((viewportSize().X - initial.X) / 2)),
        math.max(12, math.floor((viewportSize().Y - initial.Y) / 2))
    )

    local root = KryptUI.create("Frame", {
        BackgroundColor3 = Theme.canvas,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Position = UDim2.fromOffset(position.X, position.Y),
        Size = UDim2.fromOffset(initial.X, initial.Y),
        Parent = screen,
    })
    KryptUI.corner(root, 10)
    KryptUI.stroke(root, Theme.border, 0, 1)
    self.root = root

    local shadow = KryptUI.create("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        Image = "rbxassetid://1316045217",
        ImageColor3 = Color3.new(0, 0, 0),
        ImageTransparency = 0.45,
        Position = UDim2.fromScale(0.5, 0.5),
        ScaleType = Enum.ScaleType.Slice,
        Size = UDim2.new(1, 28, 1, 28),
        SliceCenter = Rect.new(10, 10, 118, 118),
        ZIndex = 0,
        Parent = root,
    })
    shadow.Visible = false

    local header = KryptUI.create("Frame", {
        BackgroundColor3 = Theme.chrome,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, Metrics.header),
        Parent = root,
    })
    self.header = header

    local mark = KryptUI.create("Frame", {
        BackgroundColor3 = Theme.accent,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(14, 13),
        Size = UDim2.fromOffset(22, 22),
        Parent = header,
    })
    KryptUI.corner(mark, 6)
    KryptUI.label({
        Font = Enum.Font.GothamBlack,
        Size = UDim2.fromScale(1, 1),
        Text = "K",
        TextSize = 12,
        Parent = mark,
    })

    KryptUI.label({
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromOffset(46, 8),
        Size = UDim2.fromOffset(160, 20),
        Text = config.Title or "KryptDbg",
        TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = header,
    })
    self.subtitle = KryptUI.label({
        Position = UDim2.fromOffset(46, 26),
        Size = UDim2.fromOffset(250, 14),
        Text = config.Subtitle or "Runtime debugging workspace",
        TextColor3 = Theme.textFaint,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = header,
    })

    local loadedBadge = KryptUI.label({
        AnchorPoint = Vector2.new(1, 0.5),
        BackgroundColor3 = Theme.surface,
        BackgroundTransparency = 0,
        Font = Enum.Font.GothamMedium,
        Position = UDim2.new(1, -92, 0.5, 0),
        Size = UDim2.fromOffset(112, 24),
        Text = "0 modules loaded",
        TextColor3 = Theme.textMuted,
        TextSize = 9,
        Parent = header,
    })
    KryptUI.corner(loadedBadge, 6)
    KryptUI.stroke(loadedBadge, Theme.borderSoft, 0.1)
    self.loadedBadge = loadedBadge

    local minimize = KryptUI.button({
        Parent = header,
        Position = UDim2.new(1, -72, 0.5, -12),
        Size = UDim2.fromOffset(26, 24),
        Text = "—",
        TextColor3 = Theme.textMuted,
    })
    minimize.Position = UDim2.new(1, -72, 0.5, -12)

    local close = KryptUI.button({
        Parent = header,
        Position = UDim2.new(1, -38, 0.5, -12),
        Size = UDim2.fromOffset(26, 24),
        Text = "×",
        TextColor3 = Theme.red,
    })
    close.Position = UDim2.new(1, -38, 0.5, -12)

    local rail = KryptUI.create("Frame", {
        BackgroundColor3 = Theme.chrome,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, Metrics.header),
        Size = UDim2.new(0, Metrics.rail, 1, -Metrics.header - Metrics.status),
        Parent = root,
    })
    self.rail = rail

    local railList = KryptUI.create("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(7, 8),
        Size = UDim2.new(1, -14, 1, -16),
        Parent = rail,
    })
    KryptUI.list(railList, Enum.FillDirection.Vertical, 7, Enum.HorizontalAlignment.Center)
    self.railList = railList

    local content = KryptUI.create("Frame", {
        BackgroundColor3 = Theme.canvas,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Position = UDim2.fromOffset(Metrics.rail, Metrics.header),
        Size = UDim2.new(1, -Metrics.rail, 1, -Metrics.header - Metrics.status),
        Parent = root,
    })
    self.content = content

    local statusBar = KryptUI.create("Frame", {
        BackgroundColor3 = Theme.chrome,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 1, -Metrics.status),
        Size = UDim2.new(1, 0, 0, Metrics.status),
        Parent = root,
    })
    KryptUI.create("Frame", {
        BackgroundColor3 = Theme.borderSoft,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 1),
        Parent = statusBar,
    })
    local statusDot = KryptUI.create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = Theme.green,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(12, 14),
        Size = UDim2.fromOffset(7, 7),
        Parent = statusBar,
    })
    KryptUI.corner(statusDot, 7)
    local statusText = KryptUI.label({
        Position = UDim2.fromOffset(26, 0),
        Size = UDim2.new(1, -150, 1, 0),
        Text = "Ready",
        TextColor3 = Theme.textMuted,
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = statusBar,
    })
    self.statusDot = statusDot
    self.statusText = statusText

    local hint = KryptUI.label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 0),
        Size = UDim2.fromOffset(220, Metrics.status),
        Text = "RightShift · show / hide",
        TextColor3 = Theme.textFaint,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = statusBar,
    })
    self.hint = hint

    local toastHost = KryptUI.create("Frame", {
        AnchorPoint = Vector2.new(1, 1),
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -14, 1, -Metrics.status - 14),
        Size = UDim2.fromOffset(320, 160),
        ZIndex = 50,
        Parent = root,
    })
    KryptUI.list(toastHost, Enum.FillDirection.Vertical, 8, Enum.HorizontalAlignment.Right)
    self.toastHost = toastHost

    local minimized = false
    local savedSize = root.Size
    local savedPosition = root.Position

    local function setMinimized(value)
        minimized = value
        if minimized then
            savedSize = root.Size
            savedPosition = root.Position
            rail.Visible = false
            content.Visible = false
            statusBar.Visible = false
            root.Size = UDim2.fromOffset(330, Metrics.header)
        else
            rail.Visible = true
            content.Visible = true
            statusBar.Visible = true
            root.Size = savedSize
            root.Position = savedPosition
            clampWindow(
                root,
                Vector2.new(root.Position.X.Offset, root.Position.Y.Offset),
                Vector2.new(root.Size.X.Offset, root.Size.Y.Offset),
                self.minimum,
                self.maximum
            )
        end
    end
    self.setMinimized = setMinimized

    table.insert(self.connections, minimize.MouseButton1Click:Connect(function()
        setMinimized(not minimized)
    end))
    table.insert(self.connections, close.MouseButton1Click:Connect(function()
        self:destroy()
    end))

    local dragInput
    local dragStart
    local startPosition
    table.insert(self.connections, header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch
        then
            local controlBoundary = root.AbsolutePosition.X + root.AbsoluteSize.X - 112
            if input.Position.X > controlBoundary then
                return
            end
            dragInput = input
            dragStart = input.Position
            startPosition = root.Position
        end
    end))
    table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
        if dragInput and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch)
        then
            dragInput = nil
        end
    end))
    table.insert(self.connections, UserInputService.InputChanged:Connect(function(input)
        if dragInput and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch)
        then
            local delta = input.Position - dragStart
            clampWindow(
                root,
                Vector2.new(startPosition.X.Offset + delta.X, startPosition.Y.Offset + delta.Y),
                Vector2.new(root.Size.X.Offset, root.Size.Y.Offset),
                self.minimum,
                self.maximum
            )
        end
    end))

    local directions = {
        N = { UDim2.new(0, 8, 0, 0), UDim2.new(1, -16, 0, 7), "N" },
        S = { UDim2.new(0, 8, 1, -7), UDim2.new(1, -16, 0, 7), "S" },
        W = { UDim2.new(0, 0, 0, 8), UDim2.new(0, 7, 1, -16), "W" },
        E = { UDim2.new(1, -7, 0, 8), UDim2.new(0, 7, 1, -16), "E" },
        NW = { UDim2.fromOffset(0, 0), UDim2.fromOffset(12, 12), "NW" },
        NE = { UDim2.new(1, -12, 0, 0), UDim2.fromOffset(12, 12), "NE" },
        SW = { UDim2.new(0, 0, 1, -12), UDim2.fromOffset(12, 12), "SW" },
        SE = { UDim2.new(1, -12, 1, -12), UDim2.fromOffset(12, 12), "SE" },
    }

    for _, definition in pairs(directions) do
        local handle = KryptUI.create("Frame", {
            Active = true,
            BackgroundTransparency = 1,
            Position = definition[1],
            Size = definition[2],
            ZIndex = 30,
            Parent = root,
        })

        local resizing = false
        local resizeStart
        local resizePosition
        local resizeSize
        local direction = definition[3]

        table.insert(self.connections, handle.InputBegan:Connect(function(input)
            if minimized then
                return
            end
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch
            then
                resizing = true
                resizeStart = input.Position
                resizePosition = Vector2.new(root.Position.X.Offset, root.Position.Y.Offset)
                resizeSize = Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
            end
        end))

        table.insert(self.connections, UserInputService.InputChanged:Connect(function(input)
            if not resizing or (input.UserInputType ~= Enum.UserInputType.MouseMovement
                and input.UserInputType ~= Enum.UserInputType.Touch)
            then
                return
            end

            local delta = input.Position - resizeStart
            local positionNow = resizePosition
            local sizeNow = resizeSize

            if direction:find("E", 1, true) then
                sizeNow = Vector2.new(resizeSize.X + delta.X, sizeNow.Y)
            end
            if direction:find("S", 1, true) then
                sizeNow = Vector2.new(sizeNow.X, resizeSize.Y + delta.Y)
            end
            if direction:find("W", 1, true) then
                positionNow = Vector2.new(resizePosition.X + delta.X, positionNow.Y)
                sizeNow = Vector2.new(resizeSize.X - delta.X, sizeNow.Y)
            end
            if direction:find("N", 1, true) then
                positionNow = Vector2.new(positionNow.X, resizePosition.Y + delta.Y)
                sizeNow = Vector2.new(sizeNow.X, resizeSize.Y - delta.Y)
            end

            clampWindow(root, positionNow, sizeNow, self.minimum, self.maximum)
        end))

        table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
            if resizing and (input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch)
            then
                resizing = false
            end
        end))
    end

    table.insert(self.connections, UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and input.KeyCode == Enum.KeyCode.RightShift then
            screen.Enabled = not screen.Enabled
        end
    end))

    self.tween = function(instance, duration, properties)
        local tween = TweenService:Create(
            instance,
            TweenInfo.new(duration or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            properties
        )
        tween:Play()
        return tween
    end

    return self
end

function Window:addTab(definition)
    local id = definition.id
    local page = KryptUI.create("Frame", {
        BackgroundColor3 = Theme.canvas,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        Visible = false,
        Parent = self.content,
    })

    local button = KryptUI.create("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Theme.transparent,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        LayoutOrder = definition.order or 0,
        Size = UDim2.fromOffset(60, 54),
        Text = "",
        Parent = self.railList,
    })
    KryptUI.corner(button, 8)

    local indicator = KryptUI.create("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        BackgroundColor3 = Theme.accent,
        BorderSizePixel = 0,
        Position = UDim2.new(0, -7, 0.5, 0),
        Size = UDim2.fromOffset(3, 28),
        Visible = false,
        Parent = button,
    })
    KryptUI.corner(indicator, 3)

    local icon = KryptUI.label({
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromOffset(4, 5),
        Size = UDim2.new(1, -8, 0, 22),
        Text = definition.icon or id:sub(1, 2):upper(),
        TextColor3 = Theme.textMuted,
        TextSize = 10,
        Parent = button,
    })
    local label = KryptUI.label({
        Position = UDim2.fromOffset(2, 29),
        Size = UDim2.new(1, -4, 0, 16),
        Text = definition.title or id,
        TextColor3 = Theme.textFaint,
        TextSize = 8,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = button,
    })
    local loadDot = KryptUI.create("Frame", {
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor3 = Theme.textFaint,
        BorderSizePixel = 0,
        Position = UDim2.new(1, -5, 0, 5),
        Size = UDim2.fromOffset(5, 5),
        Parent = button,
    })
    KryptUI.corner(loadDot, 5)

    local loading = KryptUI.empty(
        page,
        definition.title .. " is not loaded",
        "Open this tab to download and mount its module."
    )

    local tab = {
        id = id,
        button = button,
        page = page,
        icon = icon,
        label = label,
        indicator = indicator,
        loadDot = loadDot,
        loading = loading,
        loaded = false,
    }
    self.tabs[id] = tab

    table.insert(self.connections, button.MouseButton1Click:Connect(function()
        self:selectTab(id)
    end))
    table.insert(self.connections, button.MouseEnter:Connect(function()
        if self.activeTab ~= id then
            button.BackgroundTransparency = 0
            button.BackgroundColor3 = Theme.surface
        end
    end))
    table.insert(self.connections, button.MouseLeave:Connect(function()
        if self.activeTab ~= id then
            button.BackgroundTransparency = 1
        end
    end))

    return page
end

function Window:selectTab(id)
    local target = self.tabs[id]
    if not target or self.destroyed then
        return
    end

    self.activeTab = id
    for tabId, tab in pairs(self.tabs) do
        local active = tabId == id
        tab.page.Visible = active
        tab.indicator.Visible = active
        tab.button.BackgroundTransparency = active and 0 or 1
        tab.button.BackgroundColor3 = active and Theme.surfaceRaised or Theme.transparent
        tab.icon.TextColor3 = active and Theme.accent or Theme.textMuted
        tab.label.TextColor3 = active and Theme.text or Theme.textFaint
    end

    self.onTabSelected:fire(id)
end

function Window:setTabLoading(id, loading)
    local tab = self.tabs[id]
    if not tab then
        return
    end

    tab.loadDot.BackgroundColor3 = loading and Theme.yellow or Theme.textFaint
    if loading and not tab.loaded then
        for _, child in ipairs(tab.page:GetChildren()) do
            child:Destroy()
        end
        tab.loading = KryptUI.empty(
            tab.page,
            "Loading " .. id .. "…",
            "Downloading and mounting the feature module."
        )
    elseif tab.loading then
        local title = tab.loading:FindFirstChildWhichIsA("TextLabel")
        if title then
            title.Text = id .. " is not loaded"
        end
    end
end

function Window:setTabLoaded(id)
    local tab = self.tabs[id]
    if not tab or tab.loaded then
        return
    end

    tab.loaded = true
    tab.loadDot.BackgroundColor3 = Theme.green
    if tab.loading then
        tab.loading:Destroy()
        tab.loading = nil
    end

    local loaded = 0
    local total = 0
    for _, item in pairs(self.tabs) do
        total = total + 1
        if item.loaded then
            loaded = loaded + 1
        end
    end
    self.loadedBadge.Text = ("%d / %d modules"):format(loaded, total)
end

function Window:setTabError(id, message)
    local tab = self.tabs[id]
    if not tab then
        return
    end

    tab.loadDot.BackgroundColor3 = Theme.red
    for _, child in ipairs(tab.page:GetChildren()) do
        child:Destroy()
    end
    tab.loading = KryptUI.empty(tab.page, "Module failed to load", tostring(message))
end

function Window:setStatus(message, color)
    self.statusText.Text = tostring(message or "Ready")
    self.statusDot.BackgroundColor3 = color or Theme.green
end

function Window:toast(message, color, duration)
    if self.destroyed then
        return
    end

    local toast = KryptUI.panel({
        BackgroundColor3 = Theme.surfaceRaised,
        Parent = self.toastHost,
        Size = UDim2.fromOffset(300, 42),
        StrokeColor = color or Theme.accent,
    })
    toast.ZIndex = 52
    local bar = KryptUI.create("Frame", {
        BackgroundColor3 = color or Theme.accent,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(3, 42),
        ZIndex = 53,
        Parent = toast,
    })
    KryptUI.corner(bar, 3)
    KryptUI.label({
        Position = UDim2.fromOffset(12, 0),
        Size = UDim2.new(1, -20, 1, 0),
        Text = tostring(message),
        TextColor3 = Theme.text,
        TextSize = 10,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 53,
        Parent = toast,
    })

    task.delay(duration or 2.6, function()
        if toast.Parent then
            toast:Destroy()
        end
    end)
end

function Window:destroy()
    if self.destroyed then
        return
    end
    self.destroyed = true

    self.onDestroyed:fire()
    for _, connection in ipairs(self.connections) do
        pcall(function()
            connection:Disconnect()
        end)
    end
    self.connections = {}
    self.onTabSelected:destroy()
    self.onDestroyed:destroy()

    if self.screen then
        self.screen:Destroy()
    end
end

KryptUI.Window = Window

return KryptUI
