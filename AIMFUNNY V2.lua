-- AIMFUNNY.lua | GUI propia (sin LinoriaLib), redimensionable y ligera
-- Requiere: Drawing API, mousemoverel, getgenv

--// ============================================================
--// LIMPIEZA DE EJECUCION ANTERIOR
--// ============================================================
if getgenv().AIMFUNY and getgenv().AIMFUNY.Unload then
    pcall(getgenv().AIMFUNY.Unload)
end

--// ============================================================
--// SERVICIOS
--// ============================================================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local Camera           = workspace.CurrentCamera
local LocalPlayer      = Players.LocalPlayer

--// ============================================================
--// TEMA (cambia ACCENT para otro color: azul 80,160,255 / rojo 255,80,80)
--// ============================================================
local THEME = {
    Accent = Color3.fromRGB(70, 220, 120),
    Bg     = Color3.fromRGB(16, 16, 19),
    Side   = Color3.fromRGB(21, 21, 25),
    Panel  = Color3.fromRGB(26, 26, 31),
    Stroke = Color3.fromRGB(44, 44, 52),
    Text   = Color3.fromRGB(235, 235, 240),
    Sub    = Color3.fromRGB(140, 140, 150),
    Off    = Color3.fromRGB(52, 52, 60),
}

local MIN_W, MIN_H = 460, 300

--// ============================================================
--// TRACKING DE CONEXIONES
--// ============================================================
local connections = {}
local function track(conn)
    table.insert(connections, conn)
    return conn
end

--// ============================================================
--// DRAWING INIT
--// ============================================================
local Drawing_new = Drawing and Drawing.new or function()
    error("Drawing API required: usa un executor con Drawing")
end

--// ============================================================
--// STATE
--// ============================================================
getgenv().AIMFUNY = {}
local State = getgenv().AIMFUNY

State.Aimbot = {
    Enabled = false, FOV = 120, Distance = 500, ShowFOV = false,
    Smoothness = 0.15, MouseFollow = false, TargetPart = "Head",
    IgnoreTeammates = true, IgnoreList = {},
}

State.ESP = {
    Enabled = false, Tracers = true, Boxes = true, Names = true,
    Health = true, Distance = true, MaxDist = 1000,
}

State.Player = {
    Walkspeed = 16,
    JumpPower = 50,
}

--// ============================================================
--// DRAWING OBJECTS
--// ============================================================
local fov_circle = Drawing_new("Circle")
fov_circle.Visible = false
fov_circle.Thickness = 2
fov_circle.Color = Color3.fromRGB(255, 255, 255)
fov_circle.Filled = false
fov_circle.Transparency = 0.7

local esp_cache = {}

--// ============================================================
--// UTILIDADES
--// ============================================================
local function world_to_screen(pos)
    local sp, on_screen = Camera:WorldToViewportPoint(pos)
    return Vector2.new(sp.X, sp.Y), on_screen
end

local function get_character(player)
    local char = player.Character
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if hum and root and hum.Health > 0 then
        return char, hum, root
    end
    return nil
end

local function get_target_part(player, part_name)
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChild(part_name)
        or char:FindFirstChild("Head")
        or char:FindFirstChild("HumanoidRootPart")
end

--// ============================================================
--// ALLY FILTER (equipos + lista manual)
--// ============================================================
local ignore_lower = {}
local function rebuild_ignore_lower()
    ignore_lower = {}
    for name in pairs(State.Aimbot.IgnoreList) do
        ignore_lower[string.lower(name)] = true
    end
end
rebuild_ignore_lower()

local function is_ally(player)
    -- lista manual siempre gana (case-insensitive)
    if ignore_lower[string.lower(player.Name)] then return true end

    if not State.Aimbot.IgnoreTeammates then return false end

    -- 1) servicio Team estandar
    local lp_team = LocalPlayer.Team
    local p_team  = player.Team
    if lp_team and p_team and lp_team == p_team then
        return true
    end

    -- 2) fallback por TeamColor SOLO si ambos estan en un equipo real (no Neutral)
    --    en FFA todos son Neutral y TeamColor es blanco -> sin esto se bloquearia todo
    if LocalPlayer.Neutral == false and player.Neutral == false
       and LocalPlayer.TeamColor == player.TeamColor then
        return true
    end

    return false
end

--// ============================================================
--// FOV CIRCLE
--// ============================================================
local function update_fov()
    if State.Aimbot.ShowFOV then
        fov_circle.Visible = true
        fov_circle.Radius = State.Aimbot.FOV
        fov_circle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    else
        fov_circle.Visible = false
    end
end

--// ============================================================
--// AIMBOT
--// ============================================================
local function get_closest_target()
    local closest = nil
    local shortest = State.Aimbot.FOV
    local center = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if is_ally(player) then continue end

        local char, hum, root = get_character(player)
        if not char then continue end

        local part = get_target_part(player, State.Aimbot.TargetPart)
        if not part then continue end

        local dist = (root.Position - Camera.CFrame.Position).Magnitude
        if dist > State.Aimbot.Distance then continue end

        local screen_pos, on_screen = world_to_screen(part.Position)
        if not on_screen then continue end

        local mag = (screen_pos - center).Magnitude
        if mag < shortest then
            shortest = mag
            closest = player
        end
    end
    return closest
end

track(RunService.RenderStepped:Connect(function()
    update_fov()

    if not State.Aimbot.Enabled then return end

    local target = get_closest_target()
    if not target then return end

    local part = get_target_part(target, State.Aimbot.TargetPart)
    if not part then return end

    local target_pos = part.Position

    if State.Aimbot.MouseFollow then
        local mouse_pos = UserInputService:GetMouseLocation()
        local screen_pos, on_screen = world_to_screen(target_pos)
        if on_screen then
            local delta = (screen_pos - mouse_pos) * State.Aimbot.Smoothness
            mousemoverel(delta.X, delta.Y)
        end
    else
        local cam_pos = Camera.CFrame.Position
        local direction = (target_pos - cam_pos).Unit
        Camera.CFrame = CFrame.new(cam_pos, cam_pos + direction)
    end
end))

--// ============================================================
--// ESP
--// ============================================================
local function create_esp(player)
    if esp_cache[player] then return end
    local drawings = {
        box    = Drawing_new("Square"),
        tracer = Drawing_new("Line"),
        name   = Drawing_new("Text"),
        health = Drawing_new("Text"),
        dist   = Drawing_new("Text"),
    }

    drawings.box.Thickness = 1
    drawings.box.Filled = false
    drawings.box.Color = Color3.fromRGB(255, 255, 255)
    drawings.box.Transparency = 0.8

    drawings.tracer.Thickness = 1
    drawings.tracer.Color = Color3.fromRGB(255, 255, 255)
    drawings.tracer.Transparency = 0.7
    drawings.tracer.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)

    drawings.name.Size = 14
    drawings.name.Center = true
    drawings.name.Outline = true
    drawings.name.Color = Color3.fromRGB(255, 255, 255)

    drawings.health.Size = 12
    drawings.health.Center = true
    drawings.health.Outline = true
    drawings.health.Color = Color3.fromRGB(0, 255, 0)

    drawings.dist.Size = 12
    drawings.dist.Center = true
    drawings.dist.Outline = true
    drawings.dist.Color = Color3.fromRGB(200, 200, 200)

    esp_cache[player] = drawings
end

local function remove_esp(player)
    local d = esp_cache[player]
    if not d then return end
    for _, obj in pairs(d) do
        pcall(function() obj:Remove() end)
    end
    esp_cache[player] = nil
end

track(Players.PlayerAdded:Connect(create_esp))
track(Players.PlayerRemoving:Connect(remove_esp))
for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer then create_esp(p) end
end

track(RunService.RenderStepped:Connect(function()
    if not State.ESP.Enabled then
        for _, d in pairs(esp_cache) do
            for _, obj in pairs(d) do obj.Visible = false end
        end
        return
    end

    for player, d in pairs(esp_cache) do
        local char, hum, root = get_character(player)
        if not char then
            for _, obj in pairs(d) do obj.Visible = false end
            continue
        end

        local dist = (root.Position - Camera.CFrame.Position).Magnitude
        if dist > State.ESP.MaxDist then
            for _, obj in pairs(d) do obj.Visible = false end
            continue
        end

        local head = char:FindFirstChild("Head")
        if not head then continue end
        local head_pos, on_screen = world_to_screen(head.Position)
        local root_pos = world_to_screen(root.Position)

        if not on_screen then
            for _, obj in pairs(d) do obj.Visible = false end
            continue
        end

        local box_size = Vector2.new(2000 / dist, 3000 / dist)
        d.box.Size = box_size
        d.box.Position = root_pos - box_size / 2
        d.box.Visible = State.ESP.Boxes

        d.tracer.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
        d.tracer.To = head_pos
        d.tracer.Visible = State.ESP.Tracers

        d.name.Text = player.Name
        d.name.Position = head_pos - Vector2.new(0, 20)
        d.name.Visible = State.ESP.Names

        local hp = math.floor(hum.Health)
        local max_hp = math.floor(hum.MaxHealth)
        d.health.Text = "HP: " .. hp .. "/" .. max_hp
        d.health.Position = head_pos + Vector2.new(0, 5)
        d.health.Color = Color3.fromRGB(255 - (hp / max_hp * 255), hp / max_hp * 255, 0)
        d.health.Visible = State.ESP.Health

        d.dist.Text = math.floor(dist) .. " studs"
        d.dist.Position = head_pos + Vector2.new(0, 20)
        d.dist.Visible = State.ESP.Distance
    end
end))

--// ============================================================
--// HELPERS DE GUI
--// ============================================================
local order = 0
local function nxt()
    order += 1
    return order
end

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end

local function corner(o, r)
    return new("UICorner", { CornerRadius = UDim.new(0, r) }, o)
end

local function stroke(o, color, thickness)
    return new("UIStroke", {
        Color = color or THEME.Stroke,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, o)
end

local function tw(o, props, t)
    TweenService:Create(o, TweenInfo.new(t or 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function text_label(parent, str, size, color, font)
    return new("TextLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = str,
        TextSize = size or 13,
        TextColor3 = color or THEME.Text,
        Font = font or Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, parent)
end

local function is_press(i)
    return i.UserInputType == Enum.UserInputType.MouseButton1
        or i.UserInputType == Enum.UserInputType.Touch
end

local function is_move(i)
    return i.UserInputType == Enum.UserInputType.MouseMovement
        or i.UserInputType == Enum.UserInputType.Touch
end

-- arrastrar "target" agarrando "handle". Devuelve funcion que dice si hubo movimiento
local function make_draggable(handle, target)
    local dragging, drag_start, start_pos, moved = false, nil, nil, false
    handle.InputBegan:Connect(function(i)
        if is_press(i) then
            dragging = true
            moved = false
            drag_start = i.Position
            start_pos = target.Position
        end
    end)
    track(UserInputService.InputChanged:Connect(function(i)
        if dragging and is_move(i) then
            local d = i.Position - drag_start
            if d.Magnitude > 4 then moved = true end
            target.Position = UDim2.new(
                start_pos.X.Scale, start_pos.X.Offset + d.X,
                start_pos.Y.Scale, start_pos.Y.Offset + d.Y
            )
        end
    end))
    track(UserInputService.InputEnded:Connect(function(i)
        if is_press(i) then dragging = false end
    end))
    return function() return moved end
end

--// ============================================================
--// VENTANA
--// ============================================================
local gui_parent = (gethui and gethui()) or game:GetService("CoreGui")
local function make_screengui(name, order_value)
    local g = new("ScreenGui", {
        Name = name,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        IgnoreGuiInset = true,
        DisplayOrder = order_value,
    })
    local ok = pcall(function() g.Parent = gui_parent end)
    if not ok then g.Parent = LocalPlayer:WaitForChild("PlayerGui") end
    return g
end

local gui = make_screengui("AIMFUNNY_GUI", 1000)
local float_gui = make_screengui("AIMFUNNY_Float", 1001)
float_gui.Enabled = false

local main = new("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(580, 380),
    Position = UDim2.new(0.5, -290, 0.5, -190),
    BackgroundColor3 = THEME.Bg,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Active = true,
}, gui)
corner(main, 10)
stroke(main)

-- barra de titulo
local titlebar = new("Frame", {
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = THEME.Side,
    BorderSizePixel = 0,
}, main)

new("Frame", {
    Size = UDim2.fromOffset(8, 8),
    Position = UDim2.new(0, 14, 0.5, -4),
    BackgroundColor3 = THEME.Accent,
    BorderSizePixel = 0,
}, titlebar)
corner(titlebar:FindFirstChildOfClass("Frame"), 4)

local title = text_label(titlebar, "AIMFUNNY", 14, THEME.Text, Enum.Font.GothamBold)
title.Position = UDim2.new(0, 30, 0, 0)
title.Size = UDim2.new(0, 120, 1, 0)

local version = text_label(titlebar, "v1.0", 11, THEME.Sub)
version.Position = UDim2.new(0, 104, 0, 1)
version.Size = UDim2.new(0, 40, 1, 0)

new("Frame", {
    Size = UDim2.new(1, 0, 0, 1),
    Position = UDim2.new(0, 0, 1, -1),
    BackgroundColor3 = THEME.Stroke,
    BorderSizePixel = 0,
}, titlebar)

local function title_button(str, x_offset, hover_color)
    local b = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, x_offset, 0.5, 0),
        Size = UDim2.fromOffset(28, 24),
        BackgroundColor3 = THEME.Side,
        BorderSizePixel = 0,
        Text = str,
        TextColor3 = THEME.Sub,
        TextSize = 14,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = false,
    }, titlebar)
    corner(b, 6)
    b.MouseEnter:Connect(function()
        tw(b, { BackgroundColor3 = hover_color, TextColor3 = THEME.Text })
    end)
    b.MouseLeave:Connect(function()
        tw(b, { BackgroundColor3 = THEME.Side, TextColor3 = THEME.Sub })
    end)
    return b
end

local close_btn = title_button("X", -8, Color3.fromRGB(150, 40, 40))
local min_btn   = title_button("-", -40, THEME.Off)

make_draggable(titlebar, main)

-- barra lateral
local sidebar = new("Frame", {
    Position = UDim2.new(0, 0, 0, 38),
    Size = UDim2.new(0, 128, 1, -38),
    BackgroundColor3 = THEME.Side,
    BorderSizePixel = 0,
}, main)
new("UIPadding", {
    PaddingTop = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
}, sidebar)
new("UIListLayout", {
    Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
}, sidebar)

new("Frame", {
    Position = UDim2.new(0, 128, 0, 38),
    Size = UDim2.new(0, 1, 1, -38),
    BackgroundColor3 = THEME.Stroke,
    BorderSizePixel = 0,
}, main)

local content = new("Frame", {
    Position = UDim2.new(0, 129, 0, 38),
    Size = UDim2.new(1, -129, 1, -38),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
}, main)

-- grip para cambiar tamano
local grip = new("Frame", {
    AnchorPoint = Vector2.new(1, 1),
    Position = UDim2.new(1, 0, 1, 0),
    Size = UDim2.fromOffset(20, 20),
    BackgroundTransparency = 1,
    Active = true,
    ZIndex = 10,
}, main)
for i = 1, 2 do
    new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 3 + (i - 1) * 4, 0.5, 3 + (i - 1) * 4),
        Size = UDim2.fromOffset(i == 1 and 10 or 5, 1),
        Rotation = -45,
        BackgroundColor3 = THEME.Sub,
        BorderSizePixel = 0,
        ZIndex = 10,
    }, grip)
end

local resizing, rs_start, rs_size = false, nil, nil
grip.InputBegan:Connect(function(i)
    if is_press(i) then
        resizing = true
        rs_start = i.Position
        rs_size = main.AbsoluteSize
    end
end)
track(UserInputService.InputChanged:Connect(function(i)
    if resizing and is_move(i) then
        local d = i.Position - rs_start
        local vp = Camera.ViewportSize
        main.Size = UDim2.fromOffset(
            math.clamp(rs_size.X + d.X, MIN_W, vp.X - 40),
            math.clamp(rs_size.Y + d.Y, MIN_H, vp.Y - 40)
        )
    end
end))
track(UserInputService.InputEnded:Connect(function(i)
    if is_press(i) then resizing = false end
end))

--// ============================================================
--// COMPONENTES
--// ============================================================
local pages, tab_buttons = {}, {}

local function select_tab(name)
    for n, page in pairs(pages) do page.Visible = (n == name) end
    for n, b in pairs(tab_buttons) do
        local active = (n == name)
        tw(b, {
            BackgroundColor3 = active and THEME.Panel or THEME.Side,
            TextColor3 = active and THEME.Text or THEME.Sub,
        })
        tw(b.UIStroke, { Transparency = active and 0 or 1 })
    end
end

local function add_tab(name)
    local b = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = THEME.Side,
        BorderSizePixel = 0,
        Text = name,
        TextColor3 = THEME.Sub,
        TextSize = 13,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
        AutoButtonColor = false,
        LayoutOrder = nxt(),
    }, sidebar)
    corner(b, 6)
    new("UIPadding", { PaddingLeft = UDim.new(0, 12) }, b)
    local s = stroke(b, THEME.Accent, 1)
    s.Transparency = 1
    b.MouseButton1Click:Connect(function() select_tab(name) end)
    tab_buttons[name] = b

    local page = new("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = THEME.Off,
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
    }, content)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 16),
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14),
    }, page)
    new("UIListLayout", {
        Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder,
    }, page)
    pages[name] = page
    return page
end

local function add_section(page, title_str)
    local f = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = THEME.Panel,
        BorderSizePixel = 0,
        LayoutOrder = nxt(),
    }, page)
    corner(f, 8)
    stroke(f)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12),
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
    }, f)
    new("UIListLayout", {
        Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder,
    }, f)
    local t = text_label(f, string.upper(title_str), 11, THEME.Sub, Enum.Font.GothamBold)
    t.Size = UDim2.new(1, 0, 0, 16)
    t.LayoutOrder = nxt()
    return f
end

local function add_toggle(sec, text, default, callback)
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 26),
        BackgroundTransparency = 1,
        LayoutOrder = nxt(),
    }, sec)
    local lbl = text_label(row, text, 13, THEME.Text)
    lbl.Size = UDim2.new(1, -50, 1, 0)

    local track_f = new("Frame", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, 0, 0.5, 0),
        Size = UDim2.fromOffset(38, 20),
        BackgroundColor3 = default and THEME.Accent or THEME.Off,
        BorderSizePixel = 0,
    }, row)
    corner(track_f, 10)
    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0, 0.5),
        Position = default and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(14, 14),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
    }, track_f)
    corner(knob, 7)

    local state = default
    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 1, 0),
        BackgroundTransparency = 1,
        Text = "",
    }, row)
    btn.MouseButton1Click:Connect(function()
        state = not state
        tw(track_f, { BackgroundColor3 = state and THEME.Accent or THEME.Off })
        tw(knob, { Position = state and UDim2.new(1, -17, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) })
        callback(state)
    end)
end

local function add_slider(sec, text, min, max, default, decimals, callback)
    local mult = 10 ^ decimals
    local function fmt(v)
        if decimals == 0 then return tostring(v) end
        return string.format("%." .. decimals .. "f", v)
    end

    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 44),
        BackgroundTransparency = 1,
        LayoutOrder = nxt(),
    }, sec)
    local lbl = text_label(row, text, 13, THEME.Text)
    lbl.Size = UDim2.new(1, -70, 0, 18)

    local box = new("TextLabel", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(56, 20),
        BackgroundColor3 = THEME.Bg,
        BorderSizePixel = 0,
        Text = fmt(default),
        TextColor3 = THEME.Text,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
    }, row)
    corner(box, 5)
    stroke(box)

    local bar = new("Frame", {
        Position = UDim2.new(0, 0, 0, 31),
        Size = UDim2.new(1, 0, 0, 6),
        BackgroundColor3 = THEME.Off,
        BorderSizePixel = 0,
    }, row)
    corner(bar, 3)
    local rel0 = (default - min) / (max - min)
    local fill = new("Frame", {
        Size = UDim2.new(rel0, 0, 1, 0),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
    }, bar)
    corner(fill, 3)
    local knob = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(rel0, 0, 0.5, 0),
        Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = Color3.fromRGB(255, 255, 255),
        BorderSizePixel = 0,
    }, bar)
    corner(knob, 6)

    local hit = new("TextButton", {
        Position = UDim2.new(0, 0, 0, 22),
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundTransparency = 1,
        Text = "",
    }, row)

    local dragging = false
    local function set_from_x(x)
        local rel = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local v = math.floor((min + (max - min) * rel) * mult + 0.5) / mult
        local r = (v - min) / (max - min)
        fill.Size = UDim2.new(r, 0, 1, 0)
        knob.Position = UDim2.new(r, 0, 0.5, 0)
        box.Text = fmt(v)
        callback(v)
    end

    hit.InputBegan:Connect(function(i)
        if is_press(i) then
            dragging = true
            set_from_x(i.Position.X)
        end
    end)
    track(UserInputService.InputChanged:Connect(function(i)
        if dragging and is_move(i) then set_from_x(i.Position.X) end
    end))
    track(UserInputService.InputEnded:Connect(function(i)
        if is_press(i) then dragging = false end
    end))
end

local function add_dropdown(sec, text, values, default_index, callback)
    local holder = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder = nxt(),
    }, sec)
    new("UIListLayout", {
        Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
    }, holder)

    local lbl = text_label(holder, text, 13, THEME.Text)
    lbl.Size = UDim2.new(1, 0, 0, 18)
    lbl.LayoutOrder = 1

    local head = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 28),
        BackgroundColor3 = THEME.Bg,
        BorderSizePixel = 0,
        Text = values[default_index],
        TextColor3 = THEME.Text,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
        AutoButtonColor = false,
        LayoutOrder = 2,
    }, holder)
    corner(head, 6)
    stroke(head)
    new("UIPadding", { PaddingLeft = UDim.new(0, 10) }, head)
    local arrow = text_label(head, "v", 11, THEME.Sub, Enum.Font.GothamBold)
    arrow.AnchorPoint = Vector2.new(1, 0)
    arrow.Position = UDim2.new(1, -4, 0, 0)
    arrow.Size = UDim2.new(0, 16, 1, 0)

    local opts = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = THEME.Bg,
        BorderSizePixel = 0,
        Visible = false,
        LayoutOrder = 3,
    }, holder)
    corner(opts, 6)
    stroke(opts)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, opts)

    head.MouseButton1Click:Connect(function()
        opts.Visible = not opts.Visible
    end)

    for idx, v in ipairs(values) do
        local o = new("TextButton", {
            Size = UDim2.new(1, 0, 0, 26),
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Text = v,
            TextColor3 = THEME.Sub,
            TextSize = 12,
            Font = Enum.Font.GothamMedium,
            TextXAlignment = Enum.TextXAlignment.Left,
            AutoButtonColor = false,
            LayoutOrder = idx,
        }, opts)
        new("UIPadding", { PaddingLeft = UDim.new(0, 10) }, o)
        o.MouseEnter:Connect(function() tw(o, { TextColor3 = THEME.Text }) end)
        o.MouseLeave:Connect(function() tw(o, { TextColor3 = THEME.Sub }) end)
        o.MouseButton1Click:Connect(function()
            head.Text = v
            opts.Visible = false
            callback(v)
        end)
    end
end

local function add_button(sec, text, callback)
    local b = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 30),
        BackgroundColor3 = THEME.Off,
        BorderSizePixel = 0,
        Text = text,
        TextColor3 = THEME.Text,
        TextSize = 13,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = false,
        LayoutOrder = nxt(),
    }, sec)
    corner(b, 6)
    b.MouseEnter:Connect(function() tw(b, { BackgroundColor3 = THEME.Stroke }) end)
    b.MouseLeave:Connect(function() tw(b, { BackgroundColor3 = THEME.Off }) end)
    b.MouseButton1Click:Connect(callback)
end

-- NUEVO: textbox con boton "Add" para agregar nombres a la whitelist
local function add_textbox(sec, placeholder, callback)
    local row = new("Frame", {
        Size = UDim2.new(1, 0, 0, 32),
        BackgroundTransparency = 1,
        LayoutOrder = nxt(),
    }, sec)

    local box = new("TextBox", {
        Size = UDim2.new(1, -66, 1, 0),
        BackgroundColor3 = THEME.Bg,
        BorderSizePixel = 0,
        Text = "",
        PlaceholderText = placeholder or "",
        PlaceholderColor3 = THEME.Sub,
        TextColor3 = THEME.Text,
        TextSize = 12,
        Font = Enum.Font.GothamMedium,
        TextXAlignment = Enum.TextXAlignment.Left,
        ClearTextOnFocus = false,
    }, row)
    corner(box, 5)
    stroke(box)
    new("UIPadding", { PaddingLeft = UDim.new(0, 8) }, box)

    local btn = new("TextButton", {
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, 0, 0, 0),
        Size = UDim2.fromOffset(58, 32),
        BackgroundColor3 = THEME.Accent,
        BorderSizePixel = 0,
        Text = "Add",
        TextColor3 = Color3.fromRGB(20, 20, 20),
        TextSize = 12,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = false,
    }, row)
    corner(btn, 5)

    local function commit()
        local name = box.Text:gsub("^%s*(.-)%s*$", "%1")
        if #name > 0 then
            callback(name)
            box.Text = ""
        end
    end

    btn.MouseButton1Click:Connect(commit)
    box.FocusLost:Connect(function(enterPressed)
        if enterPressed then commit() end
    end)
end

--// ============================================================
--// UNLOAD / MINIMIZAR / RESTAURAR
--// ============================================================
local function unload()
    for _, c in ipairs(connections) do
        pcall(function() c:Disconnect() end)
    end
    connections = {}

    for _, d in pairs(esp_cache) do
        for _, obj in pairs(d) do pcall(function() obj:Remove() end) end
    end
    esp_cache = {}
    pcall(function() fov_circle:Remove() end)

    pcall(function() gui:Destroy() end)
    pcall(function() float_gui:Destroy() end)
    State.Unload = nil
end
State.Unload = unload

local float_btn = new("TextButton", {
    Size = UDim2.fromOffset(96, 32),
    Position = UDim2.new(0, 20, 0.5, -16),
    BackgroundColor3 = THEME.Bg,
    BorderSizePixel = 0,
    Text = "AIMFUNNY",
    TextColor3 = THEME.Text,
    TextSize = 13,
    Font = Enum.Font.GothamBold,
    AutoButtonColor = false,
}, float_gui)
corner(float_btn, 8)
stroke(float_btn, THEME.Accent, 1)
local float_moved = make_draggable(float_btn, float_btn)

local minimized = false
local function minimize()
    minimized = true
    main.Visible = false
    float_gui.Enabled = true
end
local function restore()
    minimized = false
    main.Visible = true
    float_gui.Enabled = false
end

min_btn.MouseButton1Click:Connect(minimize)
close_btn.MouseButton1Click:Connect(unload)
float_btn.MouseButton1Click:Connect(function()
    if not float_moved() then restore() end
end)

track(UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        if minimized then restore() else minimize() end
    end
end))

--// ============================================================
--// PESTANAS
--// ============================================================
local aim_page = add_tab("Aimbot")
local vis_page = add_tab("Visuals")
local move_page = add_tab("Movement")
local set_page = add_tab("Settings")

-- Aimbot
local aim = add_section(aim_page, "Aimbot configuration")
add_toggle(aim, "Enable Aimbot", false, function(v) State.Aimbot.Enabled = v end)
add_slider(aim, "FOV", 10, 500, 120, 0, function(v) State.Aimbot.FOV = v end)
add_slider(aim, "Max Distance", 50, 2000, 500, 0, function(v) State.Aimbot.Distance = v end)
add_toggle(aim, "Show FOV Circle", false, function(v) State.Aimbot.ShowFOV = v end)
add_slider(aim, "Smoothness", 0.01, 1, 0.15, 2, function(v) State.Aimbot.Smoothness = v end)
add_toggle(aim, "Mouse Follow", false, function(v) State.Aimbot.MouseFollow = v end)
add_toggle(aim, "Ignore Teammates", true, function(v) State.Aimbot.IgnoreTeammates = v end)
add_dropdown(aim, "Target Part", { "Head", "HumanoidRootPart", "UpperTorso", "LowerTorso" }, 1,
    function(v) State.Aimbot.TargetPart = v end)

-- NUEVO: Ally Whitelist (nombres a ignorar manualmente, por si el juego no usa el Team service)
local wl = add_section(aim_page, "Ally Whitelist")
local wl_hint = text_label(wl, "Nombres a ignorar por el aimbot", 11, THEME.Sub)
wl_hint.Size = UDim2.new(1, 0, 0, 14)
wl_hint.LayoutOrder = nxt()

local wl_display
local function refresh_wl_display()
    if not wl_display then return end
    local names = {}
    for name in pairs(State.Aimbot.IgnoreList) do table.insert(names, name) end
    table.sort(names)
    wl_display.Text = (#names == 0) and "Lista vacia" or table.concat(names, ", ")
end

add_textbox(wl, "Escribe un nombre y Enter", function(name)
    State.Aimbot.IgnoreList[name] = true
    rebuild_ignore_lower()
    refresh_wl_display()
end)

wl_display = text_label(wl, "Lista vacia", 12, THEME.Sub)
wl_display.Size = UDim2.new(1, 0, 0, 0)
wl_display.AutomaticSize = Enum.AutomaticSize.Y
wl_display.TextWrapped = true
wl_display.LayoutOrder = nxt()

add_button(wl, "Limpiar lista", function()
    State.Aimbot.IgnoreList = {}
    rebuild_ignore_lower()
    refresh_wl_display()
end)

-- Visuals
local esp = add_section(vis_page, "ESP functions")
add_toggle(esp, "Enable ESP", false, function(v) State.ESP.Enabled = v end)
add_toggle(esp, "Tracers", true, function(v) State.ESP.Tracers = v end)
add_toggle(esp, "Boxes", true, function(v) State.ESP.Boxes = v end)
add_toggle(esp, "Names", true, function(v) State.ESP.Names = v end)
add_toggle(esp, "Health", true, function(v) State.ESP.Health = v end)
add_toggle(esp, "Distance (studs)", true, function(v) State.ESP.Distance = v end)
add_slider(esp, "Max Render Distance", 100, 5000, 1000, 0, function(v) State.ESP.MaxDist = v end)

-- Movement
local move = add_section(move_page, "Movement")

local function apply_walkspeed(v)
    State.Player.Walkspeed = v
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum.WalkSpeed = v end
end

local function apply_jumppower(v)
    State.Player.JumpPower = v
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum.UseJumpPower = true
        hum.JumpPower = v
    end
end

add_slider(move, "Walkspeed", 0, 500, 16, 0, apply_walkspeed)
add_slider(move, "JumpPower", 0, 500, 50, 0, apply_jumppower)

track(LocalPlayer.CharacterAdded:Connect(function(char)
    local hum = char:WaitForChild("Humanoid")
    hum.WalkSpeed = State.Player.Walkspeed
    hum.UseJumpPower = true
    hum.JumpPower = State.Player.JumpPower
end))

-- Settings
local menu = add_section(set_page, "Menu")
local hint = text_label(menu, "Mostrar / ocultar: RightShift", 12, THEME.Sub)
hint.Size = UDim2.new(1, 0, 0, 18)
hint.LayoutOrder = nxt()
add_button(menu, "Unload", unload)

select_tab("Aimbot")
