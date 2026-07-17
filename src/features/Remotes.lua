local Remotes = {}

local function pack(...)
    return { n = select("#", ...), ... }
end

local function unpackArgs(arguments)
    return table.unpack(arguments, 1, arguments.n or #arguments)
end

local function shallowValue(value)
    local kind = typeof(value)
    if kind == "Instance" then
        return value:GetFullName()
    elseif kind == "table" then
        return "table:" .. tostring(value)
    end
    return tostring(value)
end

function Remotes.mount(ctx)
    local UI = ctx.ui
    local Theme = ctx.theme
    local page = ctx.page
    local state = {
        logs = {},
        selected = nil,
        paused = false,
        query = "",
        filter = "All",
        nextId = 0,
        renderDirty = false,
        renderScheduled = false,
        maxLogs = 500,
        blockedInstances = setmetatable({}, { __mode = "k" }),
        blockedNames = {},
        excludedInstances = setmetatable({}, { __mode = "k" }),
        excludedNames = {},
        replayThreads = setmetatable({}, { __mode = "k" }),
    }
    local rowSlots = {}
    local replayLoader

    ctx:cleanup(function()
        if replayLoader then
            replayLoader:destroy()
            replayLoader = nil
        end
    end)

    local toolbar = UI.toolbar(page)
    local search = UI.input({
        Parent = toolbar,
        PlaceholderText = "Search captured calls…",
        Size = UDim2.fromOffset(210, 30),
    })
    local allButton = UI.button({ Parent = toolbar, Text = "All", Width = 48 })
    local eventButton = UI.button({ Parent = toolbar, Text = "Events", Width = 64 })
    local functionButton = UI.button({ Parent = toolbar, Text = "Functions", Width = 78 })
    local pauseButton = UI.button({
        Icon = "pause",
        Parent = toolbar,
        Text = "Pause",
        Width = 76,
    })
    local clearButton = UI.button({
        Icon = "trash-2",
        Parent = toolbar,
        Text = "Clear",
        TextColor3 = Theme.red,
        Width = 70,
    })

    local body = UI.create("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(10, 52),
        Size = UDim2.new(1, -20, 1, -62),
        Parent = page,
    })
    local listPanel = UI.panel({
        Parent = body,
        ClipsDescendants = true,
        Size = UDim2.new(0.43, -5, 1, 0),
    })
    local listHeader = UI.create("Frame", {
        BackgroundColor3 = Theme.surfaceRaised,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 42),
        Parent = listPanel,
    })
    local countLabel = UI.label({
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromOffset(12, 3),
        Size = UDim2.new(1, -24, 0, 20),
        Text = "REMOTE TRAFFIC · 0",
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = listHeader,
    })
    local hookLabel = UI.label({
        Position = UDim2.fromOffset(12, 20),
        Size = UDim2.new(1, -24, 0, 16),
        Text = "Preparing capture hook…",
        TextColor3 = Theme.textFaint,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = listHeader,
    })
    local list, listLayout = UI.scroller({
        Parent = listPanel,
        Position = UDim2.fromOffset(0, 42),
        Size = UDim2.new(1, 0, 1, -42),
        Padding = 6,
        Spacing = 4,
    })

    local inspector = UI.panel({
        Parent = body,
        ClipsDescendants = true,
        Position = UDim2.new(0.43, 5, 0, 0),
        Size = UDim2.new(0.57, -5, 1, 0),
    })
    local inspectorHeader = UI.create("Frame", {
        BackgroundColor3 = Theme.surfaceRaised,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 76),
        Parent = inspector,
    })
    local selectedName = UI.label({
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromOffset(12, 8),
        Size = UDim2.new(1, -124, 0, 20),
        Text = "No captured call",
        TextSize = 13,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = inspectorHeader,
    })
    local methodBadge = UI.label({
        AnchorPoint = Vector2.new(1, 0),
        BackgroundColor3 = Theme.accentSoft,
        BackgroundTransparency = 0,
        Font = Enum.Font.GothamBold,
        Position = UDim2.new(1, -12, 0, 8),
        Size = UDim2.fromOffset(98, 22),
        Text = "NO CALL",
        TextColor3 = Theme.textMuted,
        TextSize = 8,
        Parent = inspectorHeader,
    })
    UI.corner(methodBadge, 5)
    local selectedPath = UI.label({
        Font = Enum.Font.Code,
        Position = UDim2.fromOffset(12, 33),
        Size = UDim2.new(1, -24, 0, 16),
        Text = "",
        TextColor3 = Theme.textFaint,
        TextSize = 9,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = inspectorHeader,
    })
    local selectedMeta = UI.label({
        Position = UDim2.fromOffset(12, 51),
        Size = UDim2.new(1, -24, 0, 16),
        Text = "Select a captured call to inspect it",
        TextColor3 = Theme.textMuted,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = inspectorHeader,
    })

    local actions = UI.create("Frame", {
        BackgroundColor3 = Theme.chrome,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 76),
        Size = UDim2.new(1, 0, 0, 42),
        Parent = inspector,
    })
    UI.padding(actions, 8, 8, 6, 6)
    UI.list(actions, Enum.FillDirection.Horizontal, 7)
    local copyButton = UI.button({
        Icon = "copy",
        Parent = actions,
        Text = "Copy code",
        Width = 94,
    })
    local replayButton = UI.button({
        Icon = "play",
        Parent = actions,
        Text = "Run captured",
        TextColor3 = Theme.green,
        Width = 106,
    })
    local blockButton = UI.button({
        Icon = "ban",
        Parent = actions,
        Text = "Block exact",
        TextColor3 = Theme.red,
        Width = 98,
    })
    local excludeButton = UI.button({
        Icon = "unplug",
        Parent = actions,
        Text = "Exclude exact",
        TextColor3 = Theme.yellow,
        Width = 106,
    })

    local code = UI.input({
        Parent = inspector,
        Font = Enum.Font.Code,
        MultiLine = true,
        Position = UDim2.fromOffset(8, 126),
        Size = UDim2.new(1, -16, 1, -134),
        Text = "-- Select a remote call",
        TextSize = 11,
        TextWrapped = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    code.TextEditable = false
    UI.padding(code, 10, 10, 8, 8)

    local function fingerprint(remote, method, arguments)
        local parts = { tostring(remote), method, tostring(arguments.n or #arguments) }
        for index = 1, math.min(arguments.n or #arguments, 5) do
            table.insert(parts, shallowValue(arguments[index]))
        end
        return table.concat(parts, "|")
    end

    local function generate(entry)
        local lines = {
            "local remote = " .. ctx:path(entry.remote),
            "local args = {",
        }
        for index = 1, entry.args.n or #entry.args do
            table.insert(lines, ("    [%d] = %s,"):format(index, ctx:serialize(entry.args[index])))
        end
        table.insert(lines, ("    n = %d,"):format(entry.args.n or #entry.args))
        table.insert(lines, "}")
        table.insert(lines, "")
        table.insert(
            lines,
            ("remote:%s(table.unpack(args, 1, args.n))"):format(entry.method)
        )
        return table.concat(lines, "\n")
    end

    local function matches(entry)
        if state.filter == "Events" and entry.method ~= "FireServer" then
            return false
        elseif state.filter == "Functions" and entry.method ~= "InvokeServer" then
            return false
        end

        local query = state.query:lower()
        return query == ""
            or entry.remote.Name:lower():find(query, 1, true) ~= nil
            or entry.remote:GetFullName():lower():find(query, 1, true) ~= nil
            or entry.method:lower():find(query, 1, true) ~= nil
    end

    local render
    local function selectEntry(entry)
        state.selected = entry
        if not entry then
            selectedName.Text = "No captured call"
            selectedPath.Text = ""
            selectedMeta.Text = "Select a captured call to inspect it"
            methodBadge.Text = "NO CALL"
            methodBadge.TextColor3 = Theme.textMuted
            code.Text = "-- Select a remote call"
            blockButton.Text = "Block exact"
            excludeButton.Text = "Exclude exact"
            UI.setIcon(blockButton:FindFirstChild("LucideIcon"), "ban", Theme.red)
            UI.setIcon(excludeButton:FindFirstChild("LucideIcon"), "unplug", Theme.yellow)
            return
        end

        selectedName.Text = entry.remote.Name
        selectedPath.Text = ctx:path(entry.remote)
        selectedMeta.Text = ("%d arguments · captured %s · repeated %d×"):format(
            entry.args.n or #entry.args,
            os.date("%H:%M:%S", entry.time),
            entry.count
        )
        methodBadge.Text = entry.method
        methodBadge.TextColor3 = entry.method == "FireServer" and Theme.cyan or Theme.yellow
        code.Text = entry.code or generate(entry)
        entry.code = code.Text
        local blocked = state.blockedInstances[entry.remote] == true
        local excluded = state.excludedInstances[entry.remote] == true
        blockButton.Text = blocked and "Unblock exact" or "Block exact"
        excludeButton.Text = excluded and "Include exact" or "Exclude exact"
        UI.setIcon(
            blockButton:FindFirstChild("LucideIcon"),
            blocked and "circle-check" or "ban",
            Theme.red
        )
        UI.setIcon(
            excludeButton:FindFirstChild("LucideIcon"),
            excluded and "circle-check" or "unplug",
            Theme.yellow
        )
        ctx:setSelection(entry.remote)
        render()
    end

    local function ensureRow(slotIndex)
        local existing = rowSlots[slotIndex]
        if existing then
            return existing
        end

        local row = UI.create("TextButton", {
            AutoButtonColor = false,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 46),
            Text = "",
            Parent = list,
        })
        UI.corner(row, 6)
        local stroke = UI.stroke(row, Theme.borderSoft, 0.45)
        local badge = UI.label({
            BackgroundTransparency = 0,
            Font = Enum.Font.GothamBold,
            Position = UDim2.fromOffset(7, 7),
            Size = UDim2.fromOffset(28, 16),
            TextSize = 7,
            Parent = row,
        })
        UI.corner(badge, 4)
        local name = UI.label({
            Font = Enum.Font.GothamMedium,
            Position = UDim2.fromOffset(42, 4),
            Size = UDim2.new(1, -84, 0, 20),
            TextSize = 10,
            TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = row,
        })
        local detail = UI.label({
            Font = Enum.Font.Code,
            Position = UDim2.fromOffset(42, 23),
            Size = UDim2.new(1, -84, 0, 16),
            TextColor3 = Theme.textFaint,
            TextSize = 8,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = row,
        })
        local count = UI.label({
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -9, 0.5, 0),
            Size = UDim2.fromOffset(34, 18),
            TextSize = 8,
            TextXAlignment = Enum.TextXAlignment.Right,
            Parent = row,
        })

        local slot = {
            row = row,
            stroke = stroke,
            badge = badge,
            name = name,
            detail = detail,
            count = count,
            entry = nil,
        }
        rowSlots[slotIndex] = slot
        ctx:connect(row.MouseButton1Click, function()
            if slot.entry then
                selectEntry(slot.entry)
            end
        end)
        return slot
    end

    render = function()
        if not ctx:isActive() then
            state.renderDirty = true
            return
        end
        state.renderDirty = false

        local filtered = {}
        for _, entry in ipairs(state.logs) do
            if matches(entry) then
                table.insert(filtered, entry)
            end
        end

        local first = math.max(1, #filtered - 99)
        local visibleCount = 0
        for index = first, #filtered do
            visibleCount = visibleCount + 1
            local entry = filtered[index]
            local active = entry == state.selected
            local slot = ensureRow(visibleCount)
            slot.entry = entry
            slot.row.BackgroundColor3 = active and Theme.accentSoft or Theme.surface
            slot.row.LayoutOrder = visibleCount
            slot.row.Visible = true
            slot.stroke.Color = active and Theme.accent or Theme.borderSoft
            slot.stroke.Transparency = active and 0.3 or 0.45
            slot.badge.BackgroundColor3 = entry.method == "FireServer"
                and Theme.accentSoft or Theme.surfaceRaised
            slot.badge.Text = entry.method == "FireServer" and "EV" or "FN"
            slot.badge.TextColor3 = entry.method == "FireServer" and Theme.cyan or Theme.yellow
            slot.name.Text = entry.remote.Name
            slot.detail.Text = ("%s · %d args"):format(entry.method, entry.args.n or #entry.args)
            slot.count.Text = entry.count > 1 and ("×" .. entry.count) or ("#" .. entry.id)
            slot.count.TextColor3 = entry.count > 1 and Theme.yellow or Theme.textFaint
        end

        for index = visibleCount + 1, #rowSlots do
            rowSlots[index].entry = nil
            rowSlots[index].row.Visible = false
        end

        countLabel.Text = ("REMOTE TRAFFIC · %d / %d"):format(#filtered, #state.logs)
    end

    local function requestRender()
        state.renderDirty = true
        if state.renderScheduled then
            return
        end
        state.renderScheduled = true
        task.delay(0.12, function()
            state.renderScheduled = false
            if state.renderDirty and ctx:isActive() then
                render()
            end
        end)
    end

    local function isExcluded(remote)
        return state.excludedInstances[remote] or state.excludedNames[remote.Name]
    end

    local function isBlocked(remote)
        return state.blockedInstances[remote] or state.blockedNames[remote.Name]
    end

    local function capture(remote, method, arguments)
        if not ctx.app.alive or state.paused or isExcluded(remote) then
            return
        end

        local key = fingerprint(remote, method, arguments)
        local last = state.logs[#state.logs]
        if last and last.fingerprint == key and os.clock() - last.clock < 0.5 then
            last.count = last.count + 1
            last.clock = os.clock()
            requestRender()
            return
        end

        state.nextId = state.nextId + 1
        local entry = {
            id = state.nextId,
            remote = remote,
            method = method,
            args = arguments,
            time = os.time(),
            clock = os.clock(),
            count = 1,
            fingerprint = key,
        }
        table.insert(state.logs, entry)
        if #state.logs > state.maxLogs then
            local removed = table.remove(state.logs, 1)
            if state.selected == removed then
                state.selected = nil
            end
        end
        requestRender()
    end

    local environment = (getgenv and getgenv()) or _G
    local hookMetamethod = rawget(environment, "hookmetamethod") or hookmetamethod
    local getNamecallMethod = rawget(environment, "getnamecallmethod") or getnamecallmethod
    local newClosure = rawget(environment, "newcclosure") or newcclosure or function(callback)
        return callback
    end
    local oldNamecall

    if type(hookMetamethod) == "function" and type(getNamecallMethod) == "function" then
        local ok, result = pcall(function()
            oldNamecall = hookMetamethod(game, "__namecall", newClosure(function(self, ...)
                local method = getNamecallMethod()
                if (method == "FireServer" or method == "InvokeServer")
                    and typeof(self) == "Instance"
                    and not state.replayThreads[coroutine.running()]
                then
                    local arguments = pack(...)
                    local captured, captureError = pcall(capture, self, method, arguments)
                    if not captured then
                        warn("KryptDbg remote capture failed: " .. tostring(captureError))
                    end
                    if isBlocked(self) then
                        return nil
                    end
                end
                return oldNamecall(self, ...)
            end))
            return oldNamecall
        end)

        if ok and type(result) == "function" then
            hookLabel.Text = "Namecall capture active · bounded history"
            hookLabel.TextColor3 = Theme.green
            ctx:status("Remote capture active", Theme.green)
        else
            hookLabel.Text = "Capture hook failed"
            hookLabel.TextColor3 = Theme.red
            ctx:toast("Remote capture hook failed: " .. tostring(result), Theme.red)
        end
    else
        hookLabel.Text = "This environment does not expose remote hook APIs"
        hookLabel.TextColor3 = Theme.yellow
    end

    local function setFilter(value)
        state.filter = value
        allButton.TextColor3 = value == "All" and Theme.accent or Theme.text
        eventButton.TextColor3 = value == "Events" and Theme.cyan or Theme.text
        functionButton.TextColor3 = value == "Functions" and Theme.yellow or Theme.text
        render()
    end

    ctx:connect(search:GetPropertyChangedSignal("Text"), function()
        state.query = search.Text
        requestRender()
    end)
    ctx:connect(allButton.MouseButton1Click, function()
        setFilter("All")
    end)
    ctx:connect(eventButton.MouseButton1Click, function()
        setFilter("Events")
    end)
    ctx:connect(functionButton.MouseButton1Click, function()
        setFilter("Functions")
    end)
    ctx:connect(pauseButton.MouseButton1Click, function()
        state.paused = not state.paused
        pauseButton.Text = state.paused and "Resume" or "Pause"
        pauseButton.TextColor3 = state.paused and Theme.yellow or Theme.text
        UI.setIcon(
            pauseButton:FindFirstChild("LucideIcon"),
            state.paused and "play" or "pause",
            state.paused and Theme.yellow or Theme.textMuted
        )
        ctx:status(state.paused and "Remote capture paused" or "Remote capture active", Theme.yellow)
    end)
    ctx:connect(clearButton.MouseButton1Click, function()
        state.logs = {}
        selectEntry(nil)
        render()
    end)
    ctx:connect(copyButton.MouseButton1Click, function()
        if state.selected then
            ctx:copy(state.selected.code or generate(state.selected), "Captured call copied")
        else
            ctx:toast("Select a captured call first", Theme.yellow)
        end
    end)
    ctx:connect(replayButton.MouseButton1Click, function()
        if replayLoader then
            ctx:toast("A captured call is already running", Theme.yellow)
            return
        end
        local entry = state.selected
        if not entry then
            ctx:toast("Select a captured call first", Theme.yellow)
            return
        end

        local loader = UI.loader({
            BackgroundColor3 = Theme.input,
            BackgroundTransparency = 0.04,
            Detail = entry.remote.Name .. " · " .. entry.method,
            Parent = inspector,
            Position = UDim2.fromOffset(8, 126),
            Size = UDim2.new(1, -16, 1, -134),
            Title = "Running captured call…",
            ZIndex = 20,
        })
        replayLoader = loader
        task.spawn(function()
            local thread = coroutine.running()
            state.replayThreads[thread] = true
            local result = pack(pcall(function()
                return entry.remote[entry.method](entry.remote, unpackArgs(entry.args))
            end))
            state.replayThreads[thread] = nil
            loader:destroy()
            if replayLoader == loader then
                replayLoader = nil
            end

            if not ctx.app.alive then
                return
            end
            if result[1] then
                ctx:toast("Captured call completed", Theme.green)
            else
                ctx:toast("Replay failed: " .. tostring(result[2]), Theme.red, 4)
            end
        end)
    end)
    ctx:connect(blockButton.MouseButton1Click, function()
        local entry = state.selected
        if not entry then
            ctx:toast("Select a captured call first", Theme.yellow)
            return
        end
        state.blockedInstances[entry.remote] = not state.blockedInstances[entry.remote]
        blockButton.Text = state.blockedInstances[entry.remote] and "Unblock exact" or "Block exact"
        UI.setIcon(
            blockButton:FindFirstChild("LucideIcon"),
            state.blockedInstances[entry.remote] and "circle-check" or "ban",
            Theme.red
        )
        ctx:toast(
            state.blockedInstances[entry.remote] and "Remote blocked" or "Remote unblocked",
            Theme.yellow
        )
    end)
    ctx:connect(excludeButton.MouseButton1Click, function()
        local entry = state.selected
        if not entry then
            ctx:toast("Select a captured call first", Theme.yellow)
            return
        end
        state.excludedInstances[entry.remote] = not state.excludedInstances[entry.remote]
        excludeButton.Text = state.excludedInstances[entry.remote] and "Include exact" or "Exclude exact"
        UI.setIcon(
            excludeButton:FindFirstChild("LucideIcon"),
            state.excludedInstances[entry.remote] and "circle-check" or "unplug",
            Theme.yellow
        )
        ctx:toast(
            state.excludedInstances[entry.remote] and "Remote excluded" or "Remote included",
            Theme.yellow
        )
    end)
    ctx:on("activeFeatureChanged", function(id)
        if id == ctx.id and state.renderDirty then
            render()
        end
    end)

    setFilter("All")
    selectEntry(nil)

    return {
        destroy = function()
            if type(hookMetamethod) == "function" and type(oldNamecall) == "function" then
                pcall(hookMetamethod, game, "__namecall", oldNamecall)
            end
        end,
    }
end

return Remotes
