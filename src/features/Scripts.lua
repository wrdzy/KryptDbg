local Scripts = {}

local function isScript(instance)
    return instance:IsA("LocalScript")
        or instance:IsA("ModuleScript")
        or instance:IsA("Script")
end

local function sanitizeFilename(value)
    local cleaned = tostring(value):gsub("[^%w%._%-]", "_")
    if cleaned == "" then
        cleaned = "script"
    end
    return cleaned
end

function Scripts.mount(ctx)
    local UI = ctx.ui
    local Theme = ctx.theme
    local page = ctx.page
    local state = {
        index = {},
        selected = nil,
        indexing = false,
        indexToken = 0,
        sourceCache = setmetatable({}, { __mode = "k" }),
    }
    local rowConnections = {}

    local function clearRowConnections()
        for _, connection in ipairs(rowConnections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        table.clear(rowConnections)
    end

    ctx:cleanup(clearRowConnections)

    local toolbar = UI.toolbar(page)
    local search = UI.input({
        Parent = toolbar,
        PlaceholderText = "Search scripts and paths…",
        Size = UDim2.fromOffset(250, 30),
    })
    local refreshButton = UI.button({ Parent = toolbar, Text = "Re-index", Width = 76 })
    local useSelectionButton = UI.button({ Parent = toolbar, Text = "Use selection", Width = 96 })
    local copyButton = UI.button({ Parent = toolbar, Text = "Copy source", Width = 88 })
    local saveButton = UI.button({
        Parent = toolbar,
        Text = "Save source",
        TextColor3 = Theme.cyan,
        Width = 86,
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
        Size = UDim2.new(0.38, -5, 1, 0),
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
        Text = "SCRIPT INDEX · 0",
        TextSize = 10,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = listHeader,
    })
    local indexStatus = UI.label({
        Position = UDim2.fromOffset(12, 20),
        Size = UDim2.new(1, -24, 0, 16),
        Text = "Index starts when this module loads",
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

    local sourcePanel = UI.panel({
        Parent = body,
        ClipsDescendants = true,
        Position = UDim2.new(0.38, 5, 0, 0),
        Size = UDim2.new(0.62, -5, 1, 0),
    })
    local sourceHeader = UI.create("Frame", {
        BackgroundColor3 = Theme.surfaceRaised,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 66),
        Parent = sourcePanel,
    })
    local selectedName = UI.label({
        Font = Enum.Font.GothamBold,
        Position = UDim2.fromOffset(12, 7),
        Size = UDim2.new(1, -24, 0, 20),
        Text = "No script selected",
        TextSize = 13,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = sourceHeader,
    })
    local selectedPath = UI.label({
        Font = Enum.Font.Code,
        Position = UDim2.fromOffset(12, 28),
        Size = UDim2.new(1, -24, 0, 16),
        Text = "",
        TextColor3 = Theme.textFaint,
        TextSize = 9,
        TextTruncate = Enum.TextTruncate.AtEnd,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = sourceHeader,
    })
    local sourceStatus = UI.label({
        Position = UDim2.fromOffset(12, 45),
        Size = UDim2.new(1, -24, 0, 14),
        Text = "Select a script from the index or Explorer",
        TextColor3 = Theme.textMuted,
        TextSize = 9,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = sourceHeader,
    })

    local source = UI.input({
        Parent = sourcePanel,
        Font = Enum.Font.Code,
        MultiLine = true,
        Position = UDim2.fromOffset(8, 74),
        Size = UDim2.new(1, -16, 1, -82),
        Text = "-- Source will appear here",
        TextSize = 11,
        TextWrapped = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
    })
    source.TextEditable = false
    UI.padding(source, 10, 10, 8, 8)

    local environment = (getgenv and getgenv()) or _G
    local decompileFunction = rawget(environment, "decompile") or decompile
    local writeFile = rawget(environment, "writefile") or writefile

    local function sourceFor(instance)
        if state.sourceCache[instance] then
            return true, state.sourceCache[instance], "cached"
        end

        if type(decompileFunction) == "function" then
            local ok, result = pcall(decompileFunction, instance)
            if ok and type(result) == "string" and result ~= "" then
                state.sourceCache[instance] = result
                return true, result, "decompiled"
            end
        end

        local ok, result = pcall(function()
            return instance.Source
        end)
        if ok and type(result) == "string" then
            state.sourceCache[instance] = result
            return true, result, "Source property"
        end

        return false,
            "-- Source is unavailable in this environment.\n"
                .. "-- A decompile capability or readable Source property is required.",
            "unavailable"
    end

    local renderIndex
    local function selectScript(instance)
        if typeof(instance) ~= "Instance" or not isScript(instance) then
            ctx:toast("The current selection is not a script", Theme.yellow)
            return
        end

        state.selected = instance
        selectedName.Text = instance.Name
        selectedPath.Text = ctx:path(instance)
        sourceStatus.Text = "Reading source…"
        sourceStatus.TextColor3 = Theme.yellow
        ctx:setSelection(instance)

        task.spawn(function()
            local ok, result, mode = sourceFor(instance)
            if state.selected ~= instance or not ctx.app.alive then
                return
            end
            source.Text = result
            sourceStatus.Text = ok and ("Source ready · " .. mode) or "Source unavailable"
            sourceStatus.TextColor3 = ok and Theme.green or Theme.yellow
            renderIndex()
        end)
    end

    renderIndex = function()
        if not ctx:isActive() then
            return
        end
        clearRowConnections()
        UI.clear(list)
        local query = search.Text:lower()
        local filtered = {}
        for _, instance in ipairs(state.index) do
            if query == ""
                or instance.Name:lower():find(query, 1, true)
                or instance:GetFullName():lower():find(query, 1, true)
                or instance.ClassName:lower():find(query, 1, true)
            then
                table.insert(filtered, instance)
            end
        end

        for index, instance in ipairs(filtered) do
            local active = instance == state.selected
            local row = UI.create("TextButton", {
                AutoButtonColor = false,
                BackgroundColor3 = active and Theme.accentSoft or Theme.surface,
                BorderSizePixel = 0,
                LayoutOrder = index,
                Size = UDim2.new(1, 0, 0, 44),
                Text = "",
                Parent = list,
            })
            UI.corner(row, 6)
            UI.stroke(row, active and Theme.accent or Theme.borderSoft, active and 0.35 or 0.5)
            local badgeColor = instance:IsA("ModuleScript") and Theme.yellow
                or instance:IsA("LocalScript") and Theme.cyan
                or Theme.green
            UI.label({
                BackgroundColor3 = Theme.surfaceRaised,
                BackgroundTransparency = 0,
                Font = Enum.Font.GothamBold,
                Position = UDim2.fromOffset(7, 7),
                Size = UDim2.fromOffset(28, 16),
                Text = instance:IsA("ModuleScript") and "MO"
                    or instance:IsA("LocalScript") and "LO"
                    or "SV",
                TextColor3 = badgeColor,
                TextSize = 7,
                Parent = row,
            })
            UI.label({
                Font = Enum.Font.GothamMedium,
                Position = UDim2.fromOffset(42, 3),
                Size = UDim2.new(1, -48, 0, 20),
                Text = instance.Name,
                TextSize = 10,
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = row,
            })
            UI.label({
                Font = Enum.Font.Code,
                Position = UDim2.fromOffset(42, 22),
                Size = UDim2.new(1, -48, 0, 15),
                Text = instance:GetFullName(),
                TextColor3 = Theme.textFaint,
                TextSize = 8,
                TextTruncate = Enum.TextTruncate.AtEnd,
                TextXAlignment = Enum.TextXAlignment.Left,
                Parent = row,
            })
            table.insert(rowConnections, row.MouseButton1Click:Connect(function()
                selectScript(instance)
            end))
        end

        countLabel.Text = ("SCRIPT INDEX · %d / %d"):format(#filtered, #state.index)
    end

    local function rebuildIndex()
        if state.indexing then
            state.indexToken = state.indexToken + 1
        end

        state.indexing = true
        state.indexToken = state.indexToken + 1
        local token = state.indexToken
        state.index = {}
        indexStatus.Text = "Scanning DataModel asynchronously…"
        indexStatus.TextColor3 = Theme.yellow
        renderIndex()

        task.spawn(function()
            local queue = { game }
            local head = 1
            local visited = 0
            while head <= #queue and visited < 30000 and #state.index < 700 do
                if token ~= state.indexToken or not ctx.app.alive then
                    return
                end

                local instance = queue[head]
                head = head + 1
                visited = visited + 1
                if instance ~= game and isScript(instance) then
                    table.insert(state.index, instance)
                end

                local ok, children = pcall(instance.GetChildren, instance)
                if ok then
                    for _, child in ipairs(children) do
                        if #queue < 35000 then
                            table.insert(queue, child)
                        end
                    end
                end

                if visited % 350 == 0 then
                    indexStatus.Text = ("Scanning… %d visited · %d scripts"):format(
                        visited,
                        #state.index
                    )
                    task.wait()
                end
            end

            table.sort(state.index, function(left, right)
                return left:GetFullName():lower() < right:GetFullName():lower()
            end)
            state.indexing = false
            indexStatus.Text = ("%d instances visited · index capped at 700 scripts"):format(visited)
            indexStatus.TextColor3 = Theme.green
            renderIndex()
        end)
    end

    ctx:connect(search:GetPropertyChangedSignal("Text"), renderIndex)
    ctx:connect(refreshButton.MouseButton1Click, rebuildIndex)
    ctx:connect(useSelectionButton.MouseButton1Click, function()
        selectScript(ctx:getSelection())
    end)
    ctx:connect(copyButton.MouseButton1Click, function()
        if state.selected then
            ctx:copy(source.Text, "Script source copied")
        else
            ctx:toast("Select a script first", Theme.yellow)
        end
    end)
    ctx:connect(saveButton.MouseButton1Click, function()
        if not state.selected then
            ctx:toast("Select a script first", Theme.yellow)
            return
        end
        if type(writeFile) ~= "function" then
            ctx:toast("Filesystem API is unavailable", Theme.red)
            return
        end

        local filename = "KryptDbg_" .. sanitizeFilename(state.selected.Name) .. ".lua"
        local ok, message = pcall(writeFile, filename, source.Text)
        if ok then
            ctx:toast("Saved " .. filename, Theme.green)
        else
            ctx:toast("Save failed: " .. tostring(message), Theme.red)
        end
    end)
    ctx:on("selectionChanged", function(instance, origin)
        if origin ~= ctx.id and instance and isScript(instance) and ctx:isActive() then
            selectScript(instance)
        end
    end)
    ctx:on("activeFeatureChanged", function(id)
        if id == ctx.id then
            renderIndex()
            local selected = ctx:getSelection()
            if selected and isScript(selected) and selected ~= state.selected then
                selectScript(selected)
            end
        end
    end)

    rebuildIndex()
    return {
        refresh = rebuildIndex,
        destroy = function()
            state.indexToken = state.indexToken + 1
        end,
    }
end

return Scripts
