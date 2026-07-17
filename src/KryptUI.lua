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
    border = Color3.fromRGB(76, 85, 104),
    borderSoft = Color3.fromRGB(54, 61, 75),
    text = Color3.fromRGB(248, 250, 252),
    textMuted = Color3.fromRGB(205, 213, 225),
    textFaint = Color3.fromRGB(164, 174, 194),
    icon = Color3.fromRGB(226, 232, 240),
    accent = Color3.fromRGB(96, 165, 250),
    accentSoft = Color3.fromRGB(35, 76, 135),
    cyan = Color3.fromRGB(103, 232, 249),
    green = Color3.fromRGB(74, 222, 128),
    yellow = Color3.fromRGB(250, 204, 21),
    red = Color3.fromRGB(251, 113, 133),
    transparent = Color3.fromRGB(255, 255, 255),
}

KryptUI.Metrics = {
    radius = 8,
    header = 54,
    rail = 90,
    status = 32,
    toolbar = 46,
    row = 36,
}

local Theme = KryptUI.Theme
local Metrics = KryptUI.Metrics

-- Lucide v0.363.0 atlas metadata from latte-soft/lucide-roblox.
-- Only icons used by KryptDbg are included so the UI stays lightweight.
local LucideAssets = {
    -- fallback asset id/offset, followed by bundled atlas offset
    ["activity"] = { 16898612629, 514, 771, 0, 0 },
    ["ban"] = { 16898612629, 196, 967, 48, 0 },
    ["box"] = { 16898612819, 771, 196, 96, 0 },
    ["bug"] = { 16898612819, 257, 967, 144, 0 },
    ["circle-check"] = { 16898612819, 869, 955, 192, 0 },
    ["circle-alert"] = { 16898612819, 918, 808 },
    ["circle-x"] = { 16898613044, 820, 306 },
    ["triangle-alert"] = { 16898613869, 967, 0 },
    ["info"] = { 16898613509, 612, 869 },
    ["chevron-down"] = { 16898612819, 196, 918 },
    ["chevron-right"] = { 16898612819, 869, 759 },
    ["cog"] = { 16898613044, 918, 563 },
    ["copy"] = { 16898613044, 918, 612, 240, 0 },
    ["database-backup"] = { 16898613044, 820, 759 },
    ["file-code-2"] = { 16898613353, 918, 0, 288, 0 },
    ["file-output"] = { 16898613353, 661, 771, 336, 0 },
    ["folder-tree"] = { 16898613353, 967, 404, 0, 48 },
    ["locate-fixed"] = { 16898613509, 967, 759, 48, 48 },
    ["minus"] = { 16898613613, 771, 196, 96, 48 },
    ["mouse-pointer-2"] = { 16898613613, 820, 661, 144, 48 },
    ["pause"] = { 16898613699, 0, 771, 192, 48 },
    ["play"] = { 16898613699, 918, 257, 240, 48 },
    ["radio"] = { 16898613699, 306, 918, 288, 48 },
    ["refresh-cw"] = { 16898613699, 404, 869, 336, 48 },
    ["save"] = { 16898613699, 918, 453, 0, 96 },
    ["square-terminal"] = { 16898613777, 404, 918, 48, 96 },
    ["trash-2"] = { 16898613869, 257, 918, 96, 96 },
    ["unplug"] = { 16898613869, 710, 771, 144, 96 },
    ["x"] = { 16898613869, 869, 906, 192, 96 },
}
local LucideContentId
local ActiveLoaders = setmetatable({}, { __mode = "k" })
local loaderAnimationRunning = false

local function startLoaderAnimation()
    if loaderAnimationRunning then
        return
    end

    loaderAnimationRunning = true
    task.spawn(function()
        while next(ActiveLoaders) do
            local phase = math.floor(os.clock() * 8) % 8
            for frame, state in pairs(ActiveLoaders) do
                if not frame.Parent then
                    ActiveLoaders[frame] = nil
                else
                    for index, dot in ipairs(state.dots) do
                        local distance = (index - 1 - phase) % 8
                        dot.BackgroundTransparency = math.min(0.82, distance * 0.12)
                    end
                end
            end
            task.wait(0.08)
        end
        loaderAnimationRunning = false
    end)
end

function KryptUI.configureAssets(options)
    local config = options or {}
    local environment = (getgenv and getgenv()) or _G
    local writeFile = rawget(environment, "writefile") or writefile
    local getCustomAsset = rawget(environment, "getcustomasset")
        or rawget(environment, "getsynasset")
        or getcustomasset
        or getsynasset

    if type(config.fetch) ~= "function"
        or type(writeFile) ~= "function"
        or type(getCustomAsset) ~= "function"
    then
        return false
    end

    local filename = "KryptDbg_lucide_1_3_0.png"
    local fetched, contents = pcall(config.fetch, "assets/lucide-kryptdbg.png")
    if not fetched or type(contents) ~= "string" or contents == "" then
        return false
    end

    local written = pcall(writeFile, filename, contents)
    if not written then
        return false
    end

    local loaded, contentId = pcall(getCustomAsset, filename)
    if loaded and type(contentId) == "string" and contentId ~= "" then
        LucideContentId = contentId
        return true
    end
    return false
end

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
                task.defer(listener.callback, ...)
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
        Font = Enum.Font.GothamMedium,
        TextColor3 = Theme.text,
        TextSize = 12,
    }

    for key, value in pairs(properties or {}) do
        defaults[key] = value
    end
    if type(defaults.TextSize) == "number" then
        defaults.TextSize = math.max(defaults.TextSize, 11)
    end

    return KryptUI.create(className, defaults)
end

function KryptUI.label(properties)
    return textObject("TextLabel", properties)
end

function KryptUI.icon(properties)
    local options = properties or {}
    local asset = LucideAssets[options.Icon]
    assert(asset, "Unknown Lucide icon: " .. tostring(options.Icon))
    local useBundled = LucideContentId ~= nil and asset[4] ~= nil and asset[5] ~= nil

    return KryptUI.create("ImageLabel", {
        AnchorPoint = options.AnchorPoint or Vector2.new(0, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Image = useBundled and LucideContentId or "rbxassetid://" .. asset[1],
        ImageColor3 = options.ImageColor3 or options.Color or Theme.icon,
        ImageRectOffset = useBundled and Vector2.new(asset[4], asset[5])
            or Vector2.new(asset[2], asset[3]),
        ImageRectSize = Vector2.new(48, 48),
        ImageTransparency = options.ImageTransparency or 0,
        Name = options.Name or "LucideIcon",
        Position = options.Position or UDim2.fromOffset(0, 0),
        ScaleType = Enum.ScaleType.Fit,
        Size = options.Size or UDim2.fromOffset(options.Width or 20, options.Height or 20),
        ZIndex = options.ZIndex or 1,
        Parent = options.Parent,
    })
end

function KryptUI.setIcon(instance, iconName, color)
    local asset = LucideAssets[iconName]
    assert(asset, "Unknown Lucide icon: " .. tostring(iconName))
    assert(instance and instance:IsA("ImageLabel"), "KryptUI.setIcon requires an ImageLabel")
    local useBundled = LucideContentId ~= nil and asset[4] ~= nil and asset[5] ~= nil

    instance.Image = useBundled and LucideContentId or "rbxassetid://" .. asset[1]
    instance.ImageRectOffset = useBundled and Vector2.new(asset[4], asset[5])
        or Vector2.new(asset[2], asset[3])
    instance.ImageRectSize = Vector2.new(48, 48)
    if color then
        instance.ImageColor3 = color
    end
end

function KryptUI.button(properties)
    local options = properties or {}
    local hasLabeledIcon = options.Icon ~= nil and options.IconOnly ~= true
    local button = textObject("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = options.BackgroundColor3 or Theme.surfaceRaised,
        BackgroundTransparency = options.BackgroundTransparency or 0,
        BorderSizePixel = 0,
        Font = options.Font or Enum.Font.GothamMedium,
        Position = options.Position or UDim2.fromOffset(0, 0),
        Size = options.Size or UDim2.fromOffset(options.Width or 92, options.Height or 30),
        Text = options.IconOnly and "" or options.Text or "Button",
        TextColor3 = options.TextColor3 or Theme.text,
        TextTransparency = hasLabeledIcon and 1 or 0,
        TextSize = options.TextSize or 11,
        LayoutOrder = options.LayoutOrder or 0,
        Parent = options.Parent,
    })
    KryptUI.corner(button, options.Radius or 6)
    KryptUI.stroke(button, options.StrokeColor or Theme.border, options.StrokeTransparency or 0.25)

    if options.Icon then
        local iconSize = options.IconSize or 16
        local centered = options.IconOnly == true
        KryptUI.icon({
            AnchorPoint = centered and Vector2.new(0.5, 0.5) or Vector2.new(0, 0.5),
            Color = options.IconColor or options.TextColor3 or Theme.icon,
            Icon = options.Icon,
            Name = "LucideIcon",
            Position = centered and UDim2.fromScale(0.5, 0.5)
                or UDim2.new(0, options.IconOffset or 8, 0.5, 0),
            Size = UDim2.fromOffset(iconSize, iconSize),
            ZIndex = button.ZIndex + 1,
            Parent = button,
        })
    end

    if hasLabeledIcon then
        local iconSize = options.IconSize or 16
        local iconOffset = options.IconOffset or 8
        local textLabel = textObject("TextLabel", {
            BackgroundTransparency = 1,
            Font = options.Font or Enum.Font.GothamMedium,
            Position = UDim2.fromOffset(iconOffset + iconSize + 6, 0),
            Size = UDim2.new(1, -(iconOffset + iconSize + 12), 1, 0),
            Text = button.Text,
            TextColor3 = button.TextColor3,
            TextSize = options.TextSize or 11,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = button.ZIndex + 1,
            Parent = button,
        })
        button:GetPropertyChangedSignal("Text"):Connect(function()
            if textLabel.Parent then
                textLabel.Text = button.Text
            end
        end)
        button:GetPropertyChangedSignal("TextColor3"):Connect(function()
            if textLabel.Parent then
                textLabel.TextColor3 = button.TextColor3
            end
        end)
    end

    local base = button.BackgroundColor3
    local hovering = false
    local applyingHover = false
    button:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
        if applyingHover then
            return
        end
        base = button.BackgroundColor3
        if hovering then
            applyingHover = true
            button.BackgroundColor3 = options.HoverColor or Theme.surfaceHover
            applyingHover = false
        end
    end)
    button.MouseEnter:Connect(function()
        if button.Parent then
            hovering = true
            applyingHover = true
            button.BackgroundColor3 = options.HoverColor or Theme.surfaceHover
            applyingHover = false
        end
    end)
    button.MouseLeave:Connect(function()
        if button.Parent then
            hovering = false
            applyingHover = true
            button.BackgroundColor3 = base
            applyingHover = false
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
    KryptUI.icon({
        AnchorPoint = Vector2.new(0.5, 0.5),
        Color = Theme.textFaint,
        Icon = "box",
        Position = UDim2.fromScale(0.5, 0.37),
        Size = UDim2.fromOffset(28, 28),
        Parent = frame,
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

-- Native adaptation of MageCDN's Circle Fade SVG loader.
function KryptUI.loader(properties)
    local options = properties or {}
    local zIndex = options.ZIndex or 5
    local frame = KryptUI.create("Frame", {
        BackgroundColor3 = options.BackgroundColor3 or Theme.canvas,
        BackgroundTransparency = options.BackgroundTransparency == nil
            and 1 or options.BackgroundTransparency,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        LayoutOrder = options.LayoutOrder or 0,
        Position = options.Position or UDim2.fromOffset(0, 0),
        Size = options.Size or UDim2.fromScale(1, 1),
        ZIndex = zIndex,
        Parent = options.Parent,
    })

    local spinner = KryptUI.create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        Position = options.SpinnerPosition or UDim2.new(0.5, 0, 0.5, -18),
        Size = UDim2.fromOffset(options.SpinnerSize or 34, options.SpinnerSize or 34),
        ZIndex = zIndex + 1,
        Parent = frame,
    })

    local dots = {}
    local radius = options.Radius or 12
    local dotSize = options.DotSize or 5
    for index = 1, 8 do
        local angle = math.rad((index - 1) * 45 - 90)
        local dot = KryptUI.create("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = options.Color or Theme.accent,
            BackgroundTransparency = math.min(0.82, (index - 1) * 0.12),
            BorderSizePixel = 0,
            Position = UDim2.new(
                0.5,
                math.floor(math.cos(angle) * radius + 0.5),
                0.5,
                math.floor(math.sin(angle) * radius + 0.5)
            ),
            Size = UDim2.fromOffset(dotSize, dotSize),
            ZIndex = zIndex + 2,
            Parent = spinner,
        })
        KryptUI.corner(dot, dotSize)
        dots[index] = dot
    end

    local title = KryptUI.label({
        Font = Enum.Font.GothamBold,
        Position = options.TitlePosition or UDim2.new(0, 16, 0.5, 8),
        Size = UDim2.new(1, -32, 0, 20),
        Text = options.Title or "Loading…",
        TextColor3 = options.TextColor3 or Theme.textMuted,
        TextSize = options.TitleSize or 12,
        TextXAlignment = Enum.TextXAlignment.Center,
        ZIndex = zIndex + 1,
        Parent = frame,
    })
    local detail = KryptUI.label({
        Position = options.DetailPosition or UDim2.new(0, 24, 0.5, 28),
        Size = UDim2.new(1, -48, 0, 28),
        Text = options.Detail or "",
        TextColor3 = options.DetailColor3 or Theme.textFaint,
        TextSize = options.DetailSize or 9,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Center,
        TextYAlignment = Enum.TextYAlignment.Top,
        ZIndex = zIndex + 1,
        Parent = frame,
    })

    ActiveLoaders[frame] = {
        dots = dots,
    }
    frame.AncestryChanged:Connect(function(_, parent)
        if not parent then
            ActiveLoaders[frame] = nil
        end
    end)
    startLoaderAnimation()

    local controller = {
        frame = frame,
    }

    function controller:setTitle(value)
        if title.Parent then
            title.Text = tostring(value or "")
        end
    end

    function controller:setDetail(value)
        if detail.Parent then
            detail.Text = tostring(value or "")
        end
    end

    function controller:destroy()
        ActiveLoaders[frame] = nil
        if frame.Parent then
            frame:Destroy()
        end
    end

    return controller
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
    local availableWidth = math.max(300, viewport.X - 24)
    local availableHeight = math.max(220, viewport.Y - 24)
    local minimumWidth = math.min(minimum.X, availableWidth)
    local minimumHeight = math.min(minimum.Y, availableHeight)
    local width = math.clamp(size.X, minimumWidth, math.min(maximum.X, availableWidth))
    local height = math.clamp(size.Y, minimumHeight, math.min(maximum.Y, availableHeight))
    local x = math.clamp(position.X, 12, math.max(12, viewport.X - width - 12))
    local y = math.clamp(position.Y, 12, math.max(12, viewport.Y - height - 12))

    frame.Position = UDim2.fromOffset(x, y)
    frame.Size = UDim2.fromOffset(width, height)
end

local function clampPosition(frame, position, size)
    local viewport = viewportSize()
    local width = math.min(size.X, math.max(1, viewport.X - 24))
    local height = math.min(size.Y, math.max(1, viewport.Y - 24))
    local x = math.clamp(position.X, 12, math.max(12, viewport.X - width - 12))
    local y = math.clamp(position.Y, 12, math.max(12, viewport.Y - height - 12))
    frame.Position = UDim2.fromOffset(x, y)
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
    clampWindow(root, position, initial, self.minimum, self.maximum)

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
        Size = UDim2.fromOffset(28, 28),
        Parent = header,
    })
    KryptUI.corner(mark, 6)
    KryptUI.icon({
        AnchorPoint = Vector2.new(0.5, 0.5),
        Color = Theme.text,
        Icon = "bug",
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(18, 18),
        Parent = mark,
    })

    KryptUI.label({
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromOffset(52, 8),
        Size = UDim2.fromOffset(160, 20),
        Text = config.Title or "KryptDbg",
        TextSize = 15,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = header,
    })
    self.subtitle = KryptUI.label({
        Position = UDim2.fromOffset(52, 28),
        Size = UDim2.fromOffset(250, 14),
        Text = config.Subtitle or "Runtime debugging workspace",
        TextColor3 = Theme.textMuted,
        TextSize = 11,
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
        TextSize = 11,
        Parent = header,
    })
    KryptUI.corner(loadedBadge, 6)
    KryptUI.stroke(loadedBadge, Theme.borderSoft, 0.1)
    self.loadedBadge = loadedBadge

    local minimize = KryptUI.button({
        Icon = "minus",
        IconOnly = true,
        Parent = header,
        Position = UDim2.new(1, -72, 0.5, -12),
        Size = UDim2.fromOffset(26, 24),
        IconColor = Theme.textMuted,
    })
    minimize.Position = UDim2.new(1, -72, 0.5, -12)

    local close = KryptUI.button({
        Icon = "x",
        IconOnly = true,
        Parent = header,
        Position = UDim2.new(1, -38, 0.5, -12),
        Size = UDim2.fromOffset(26, 24),
        IconColor = Theme.red,
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
        Position = UDim2.fromOffset(8, 8),
        Size = UDim2.new(1, -16, 1, -16),
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
        Position = UDim2.new(0, 12, 0.5, 0),
        Size = UDim2.fromOffset(7, 7),
        Parent = statusBar,
    })
    KryptUI.corner(statusDot, 7)
    local statusText = KryptUI.label({
        Position = UDim2.fromOffset(26, 0),
        Size = UDim2.new(1, -474, 1, 0),
        Text = "Ready",
        TextColor3 = Theme.textMuted,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = statusBar,
    })
    self.statusDot = statusDot
    self.statusText = statusText

    local hint = KryptUI.label({
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -10, 0, 0),
        Size = UDim2.fromOffset(420, Metrics.status),
        Text = "",
        TextColor3 = Theme.textMuted,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Right,
        Parent = statusBar,
    })
    self.hint = hint
    local watermark = tostring(config.Watermark or config.Title or "KryptDbg")
    local function updateWatermark()
        local ok, currentTime = pcall(os.date, "%H:%M:%S")
        hint.Text = ("%s  |  %s"):format(ok and currentTime or "--:--:--", watermark)
    end
    updateWatermark()
    task.spawn(function()
        while not self.destroyed and hint.Parent do
            task.wait(1)
            if not self.destroyed and hint.Parent then
                updateWatermark()
            end
        end
    end)

    local toastHost = KryptUI.create("Frame", {
        AnchorPoint = Vector2.new(1, 1),
        BackgroundTransparency = 1,
        Position = UDim2.new(1, -14, 1, -Metrics.status - 14),
        Size = UDim2.fromOffset(320, 340),
        ZIndex = 50,
        Parent = root,
    })
    local toastLayout = KryptUI.list(
        toastHost,
        Enum.FillDirection.Vertical,
        8,
        Enum.HorizontalAlignment.Right
    )
    toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
    self.toastHost = toastHost
    self.toasts = {}

    local minimized = false
    local savedSize = root.Size

    local function setMinimized(value)
        if minimized == value then
            return
        end
        minimized = value
        if minimized then
            savedSize = root.Size
            rail.Visible = false
            content.Visible = false
            statusBar.Visible = false
            self.subtitle.Visible = false
            loadedBadge.Visible = false
            root.Size = UDim2.fromOffset(300, Metrics.header)
            clampPosition(
                root,
                Vector2.new(root.Position.X.Offset, root.Position.Y.Offset),
                Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
            )
        else
            local currentPosition = root.Position
            rail.Visible = true
            content.Visible = true
            statusBar.Visible = true
            self.subtitle.Visible = true
            loadedBadge.Visible = true
            root.Size = savedSize
            root.Position = currentPosition
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

    local resizeDirection
    local resizeStart
    local resizePosition
    local resizeSize

    for _, definition in pairs(directions) do
        local handle = KryptUI.create("Frame", {
            Active = true,
            BackgroundTransparency = 1,
            Position = definition[1],
            Size = definition[2],
            ZIndex = 30,
            Parent = root,
        })

        local direction = definition[3]

        table.insert(self.connections, handle.InputBegan:Connect(function(input)
            if minimized then
                return
            end
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch
            then
                resizeDirection = direction
                resizeStart = input.Position
                resizePosition = Vector2.new(root.Position.X.Offset, root.Position.Y.Offset)
                resizeSize = Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
            end
        end))
    end

    table.insert(self.connections, UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch
        then
            return
        end

        if resizeDirection then
            local delta = input.Position - resizeStart
            local positionNow = resizePosition
            local sizeNow = resizeSize
            -- The edges opposite a west/north drag stay fixed. Capture them so
            -- we can re-anchor after clamping; otherwise, once the size clamps
            -- to the minimum the window slides across the screen instead of
            -- stopping.
            local rightEdge = resizePosition.X + resizeSize.X
            local bottomEdge = resizePosition.Y + resizeSize.Y
            local anchorWest = resizeDirection:find("W", 1, true) ~= nil
            local anchorNorth = resizeDirection:find("N", 1, true) ~= nil

            if resizeDirection:find("E", 1, true) then
                sizeNow = Vector2.new(resizeSize.X + delta.X, sizeNow.Y)
            end
            if resizeDirection:find("S", 1, true) then
                sizeNow = Vector2.new(sizeNow.X, resizeSize.Y + delta.Y)
            end
            if anchorWest then
                positionNow = Vector2.new(resizePosition.X + delta.X, positionNow.Y)
                sizeNow = Vector2.new(resizeSize.X - delta.X, sizeNow.Y)
            end
            if anchorNorth then
                positionNow = Vector2.new(positionNow.X, resizePosition.Y + delta.Y)
                sizeNow = Vector2.new(sizeNow.X, resizeSize.Y - delta.Y)
            end

            clampWindow(root, positionNow, sizeNow, self.minimum, self.maximum)

            if anchorWest or anchorNorth then
                local anchoredX = anchorWest
                    and rightEdge - root.Size.X.Offset or root.Position.X.Offset
                local anchoredY = anchorNorth
                    and bottomEdge - root.Size.Y.Offset or root.Position.Y.Offset
                root.Position = UDim2.fromOffset(anchoredX, anchoredY)
            end
        elseif dragInput then
            local delta = input.Position - dragStart
            local nextPosition = Vector2.new(
                startPosition.X.Offset + delta.X,
                startPosition.Y.Offset + delta.Y
            )
            local currentSize = Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
            if minimized then
                clampPosition(root, nextPosition, currentSize)
            else
                clampWindow(root, nextPosition, currentSize, self.minimum, self.maximum)
            end
        end
    end))

    table.insert(self.connections, UserInputService.InputEnded:Connect(function(input)
        if resizeDirection and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch)
        then
            resizeDirection = nil
        end
    end))

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
        Size = UDim2.fromOffset(74, 60),
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

    local icon = KryptUI.icon({
        AnchorPoint = Vector2.new(0.5, 0),
        Color = Theme.icon,
        Icon = definition.icon or "box",
        Position = UDim2.new(0.5, 0, 0, 6),
        Size = UDim2.fromOffset(23, 23),
        Parent = button,
    })
    local label = KryptUI.label({
        Position = UDim2.fromOffset(2, 32),
        Size = UDim2.new(1, -4, 0, 18),
        Text = definition.title or id,
        TextColor3 = Theme.textMuted,
        TextSize = 11,
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
        tab.icon.ImageColor3 = active and Theme.text or Theme.icon
        tab.label.TextColor3 = active and Theme.text or Theme.textMuted
    end

    self.onTabSelected:fire(id)
end

local function destroyLoadingState(tab)
    if not tab.loading then
        return
    end

    if type(tab.loading) == "table" and type(tab.loading.destroy) == "function" then
        tab.loading:destroy()
    elseif typeof(tab.loading) == "Instance" then
        tab.loading:Destroy()
    end
    tab.loading = nil
end

function Window:setTabLoading(id, loading)
    local tab = self.tabs[id]
    if not tab then
        return
    end

    tab.loadDot.BackgroundColor3 = loading and Theme.yellow or Theme.textFaint
    if loading and not tab.loaded then
        destroyLoadingState(tab)
        for _, child in ipairs(tab.page:GetChildren()) do
            child:Destroy()
        end
        tab.loading = KryptUI.loader({
            Parent = tab.page,
            Title = "Loading " .. id .. "…",
            Detail = "Downloading and mounting the feature module.",
        })
    end
end

function Window:setTabLoaded(id)
    local tab = self.tabs[id]
    if not tab or tab.loaded then
        return
    end

    tab.loaded = true
    tab.loadDot.BackgroundColor3 = Theme.green
    destroyLoadingState(tab)

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
    destroyLoadingState(tab)
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
    color = color or Theme.accent

    -- Pick an icon from the semantic color so notifications read at a glance.
    local iconName = "info"
    if color == Theme.green then
        iconName = "circle-check"
    elseif color == Theme.red then
        iconName = "circle-x"
    elseif color == Theme.yellow then
        iconName = "triangle-alert"
    end

    -- Cap the stack so a burst of events cannot fill the screen; drop the oldest.
    self.toasts = self.toasts or {}
    while #self.toasts >= 4 do
        local oldest = table.remove(self.toasts, 1)
        if oldest and oldest.Parent then
            oldest:Destroy()
        end
    end

    local toast = KryptUI.create("TextButton", {
        AutoButtonColor = false,
        BackgroundColor3 = Theme.surfaceRaised,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(306, 48),
        Text = "",
        ZIndex = 52,
        Parent = self.toastHost,
    })
    table.insert(self.toasts, toast)
    KryptUI.corner(toast, 8)
    local stroke = KryptUI.stroke(toast, color, 1)

    local bar = KryptUI.create("Frame", {
        BackgroundColor3 = color,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(6, 7),
        Size = UDim2.new(0, 3, 1, -14),
        ZIndex = 53,
        Parent = toast,
    })
    KryptUI.corner(bar, 3)

    local icon = KryptUI.icon({
        AnchorPoint = Vector2.new(0, 0.5),
        Color = color,
        Icon = iconName,
        ImageTransparency = 1,
        Position = UDim2.new(0, 16, 0.5, 0),
        Size = UDim2.fromOffset(18, 18),
        ZIndex = 53,
        Parent = toast,
    })

    local label = KryptUI.label({
        Position = UDim2.fromOffset(44, 0),
        Size = UDim2.new(1, -56, 1, 0),
        Text = tostring(message),
        TextColor3 = Theme.text,
        TextSize = 11,
        TextTransparency = 1,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        ZIndex = 53,
        Parent = toast,
    })

    self.tween(toast, 0.18, { BackgroundTransparency = 0 })
    self.tween(stroke, 0.18, { Transparency = 0.3 })
    self.tween(bar, 0.18, { BackgroundTransparency = 0 })
    self.tween(icon, 0.18, { ImageTransparency = 0 })
    self.tween(label, 0.18, { TextTransparency = 0 })

    local dismissed = false
    local function dismiss()
        if dismissed then
            return
        end
        dismissed = true
        for index, entry in ipairs(self.toasts) do
            if entry == toast then
                table.remove(self.toasts, index)
                break
            end
        end
        if not toast.Parent then
            return
        end
        self.tween(toast, 0.16, { BackgroundTransparency = 1 })
        self.tween(stroke, 0.16, { Transparency = 1 })
        self.tween(bar, 0.16, { BackgroundTransparency = 1 })
        self.tween(icon, 0.16, { ImageTransparency = 1 })
        self.tween(label, 0.16, { TextTransparency = 1 })
        task.delay(0.18, function()
            if toast.Parent then
                toast:Destroy()
            end
        end)
    end

    toast.MouseButton1Click:Connect(dismiss)
    task.delay(duration or 3, dismiss)
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
