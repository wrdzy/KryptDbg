--[[
    KryptDbg bootstrap

    This is the only file users execute. It downloads the manifest and the
    small shared runtime first. Feature modules are fetched only when their
    tab is opened for the first time.
]]

local ENV = (getgenv and getgenv()) or _G
local DEFAULT_BASE = "https://raw.githubusercontent.com/wrdzy/KryptDbg/main/"
local BASE_URL = ENV.KryptDbgBaseUrl or DEFAULT_BASE

if BASE_URL:sub(-1) ~= "/" then
    BASE_URL = BASE_URL .. "/"
end

-- Native adaptation of MageCDN's Circle Fade SVG loader. It exists in the
-- bootstrap so the first network requests never leave a frozen-looking screen.
local function createBootstrapLoader()
    local parent
    local getHui = rawget(ENV, "gethui") or gethui
    if type(getHui) == "function" then
        local ok, result = pcall(getHui)
        if ok then
            parent = result
        end
    end
    parent = parent or game:GetService("CoreGui")

    local screen = Instance.new("ScreenGui")
    screen.DisplayOrder = 1000001
    screen.IgnoreGuiInset = true
    screen.Name = "KryptDbgBootstrap"
    screen.ResetOnSpawn = false

    local card = Instance.new("Frame")
    card.AnchorPoint = Vector2.new(0.5, 0)
    card.BackgroundColor3 = Color3.fromRGB(21, 24, 30)
    card.BorderSizePixel = 0
    card.Position = UDim2.new(0.5, 0, 0, 18)
    card.Size = UDim2.fromOffset(320, 62)
    card.Parent = screen

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 9)
    corner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(50, 56, 69)
    stroke.Transparency = 0.1
    stroke.Parent = card

    local spinner = Instance.new("Frame")
    spinner.AnchorPoint = Vector2.new(0.5, 0.5)
    spinner.BackgroundTransparency = 1
    spinner.Position = UDim2.fromOffset(31, 31)
    spinner.Size = UDim2.fromOffset(34, 34)
    spinner.Parent = card

    local dots = {}
    for index = 1, 8 do
        local angle = math.rad((index - 1) * 45 - 90)
        local dot = Instance.new("Frame")
        dot.AnchorPoint = Vector2.new(0.5, 0.5)
        dot.BackgroundColor3 = Color3.fromRGB(73, 137, 255)
        dot.BackgroundTransparency = math.min(0.82, (index - 1) * 0.12)
        dot.BorderSizePixel = 0
        dot.Position = UDim2.new(
            0.5,
            math.floor(math.cos(angle) * 12 + 0.5),
            0.5,
            math.floor(math.sin(angle) * 12 + 0.5)
        )
        dot.Size = UDim2.fromOffset(5, 5)
        dot.Parent = spinner

        local dotCorner = Instance.new("UICorner")
        dotCorner.CornerRadius = UDim.new(1, 0)
        dotCorner.Parent = dot
        dots[index] = dot
    end

    local title = Instance.new("TextLabel")
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.Position = UDim2.fromOffset(58, 10)
    title.Size = UDim2.new(1, -72, 0, 20)
    title.Text = "Starting KryptDbg…"
    title.TextColor3 = Color3.fromRGB(235, 238, 245)
    title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = card

    local detail = Instance.new("TextLabel")
    detail.BackgroundTransparency = 1
    detail.Font = Enum.Font.Gotham
    detail.Position = UDim2.fromOffset(58, 31)
    detail.Size = UDim2.new(1, -72, 0, 18)
    detail.Text = "Preparing loader"
    detail.TextColor3 = Color3.fromRGB(150, 158, 176)
    detail.TextSize = 9
    detail.TextTruncate = Enum.TextTruncate.AtEnd
    detail.TextXAlignment = Enum.TextXAlignment.Left
    detail.Parent = card

    local parented = pcall(function()
        screen.Parent = parent
    end)
    if not parented then
        local player = game:GetService("Players").LocalPlayer
        local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            screen.Parent = playerGui
        else
            screen:Destroy()
        end
    end

    local alive = screen.Parent ~= nil
    task.spawn(function()
        while alive and screen.Parent do
            local phase = math.floor(os.clock() * 8) % 8
            for index, dot in ipairs(dots) do
                local distance = (index - 1 - phase) % 8
                dot.BackgroundTransparency = math.min(0.82, distance * 0.12)
            end
            task.wait(0.08)
        end
    end)

    local controller = {}
    function controller:setDetail(value)
        if detail.Parent then
            detail.Text = tostring(value)
        end
    end
    function controller:fail(message)
        title.Text = "KryptDbg could not start"
        title.TextColor3 = Color3.fromRGB(236, 92, 104)
        detail.Text = tostring(message)
        for _, dot in ipairs(dots) do
            dot.BackgroundColor3 = Color3.fromRGB(236, 92, 104)
        end
    end
    function controller:destroy()
        alive = false
        if screen.Parent then
            screen:Destroy()
        end
    end
    return controller
end

local function fetch(path)
    local url = BASE_URL .. path
    local ok, response = pcall(function()
        return game:HttpGet(url)
    end)

    if not ok then
        error(("KryptDbg could not download %s: %s"):format(path, tostring(response)), 0)
    end

    if type(response) ~= "string" or response == "" then
        error(("KryptDbg received an empty response for %s"):format(path), 0)
    end

    return response
end

local function execute(path)
    if type(loadstring) ~= "function" then
        error("KryptDbg requires loadstring support to load its modules.", 0)
    end

    local source = fetch(path)
    local chunk, compileError = loadstring(source, "@KryptDbg/" .. path)
    if not chunk then
        error(("KryptDbg could not compile %s: %s"):format(path, tostring(compileError)), 0)
    end

    local ok, result = pcall(chunk)
    if not ok then
        error(("KryptDbg could not start %s: %s"):format(path, tostring(result)), 0)
    end

    return result
end

local previousShutdown = ENV.KryptDbgShutdown
if type(previousShutdown) == "function" then
    pcall(previousShutdown)
end

local bootstrapLoader = createBootstrapLoader()
local started, app = pcall(function()
    bootstrapLoader:setDetail("Downloading manifest…")
    local manifest = execute("src/Manifest.lua")
    bootstrapLoader:setDetail("Loading interface…")
    local KryptUI = execute(manifest.ui)
    bootstrapLoader:setDetail("Loading runtime…")
    local Runtime = execute(manifest.core)
    bootstrapLoader:setDetail("Mounting workspace…")

    return Runtime.start({
        baseUrl = BASE_URL,
        execute = execute,
        fetch = fetch,
        manifest = manifest,
        ui = KryptUI,
    })
end)

if not started then
    bootstrapLoader:fail(app)
    task.delay(6, function()
        bootstrapLoader:destroy()
    end)
    error(app, 0)
end
bootstrapLoader:destroy()

ENV.KryptDbg = app
ENV.KryptDbgShutdown = function()
    if app and app.destroy then
        app:destroy()
    end

    if ENV.KryptDbg == app then
        ENV.KryptDbg = nil
        ENV.KryptDbgShutdown = nil
    end
end

return app
