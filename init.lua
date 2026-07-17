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

local manifest = execute("src/Manifest.lua")
local KryptUI = execute(manifest.ui)
local Runtime = execute(manifest.core)

local app = Runtime.start({
    baseUrl = BASE_URL,
    execute = execute,
    manifest = manifest,
    ui = KryptUI,
})

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
