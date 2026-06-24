-- minigame.lua -- "Treat Catch" mini-game for Pocket Artemis.
-- Treats fall from the top, player moves Artemis left/right to catch them.
-- Score determines happiness bonus. Missed treats cost points.

local Input = require("love2d4me.src.input")
local Fonts = require("love2d4me.src.fonts")

local lg = love.graphics

local MiniGame = {}

local STATE_READY = "ready"
local STATE_PLAYING = "playing"
local STATE_DONE = "done"

local game_state = STATE_READY
local game_w, game_h = 0, 0
local player_x = 0
local player_w = 30
local player_h = 24
local player_speed = 150

local treats = {}
local treat_w = 12
local treat_h = 12
local spawn_timer = 0
local spawn_interval = 0.6
local treat_speed = 80

local score = 0
local misses = 0
local max_misses = 5
local game_timer = 0
local game_duration = 12
local countdown = 3
local countdown_timer = 0
local on_finish_cb = nil

local sfx = nil

local COL = {
    bg        = { 0.15, 0.18, 0.25 },
    player    = { 0.95, 0.75, 0.45 },
    player_ear = { 0.80, 0.55, 0.30 },
    treat     = { 0.90, 0.40, 0.40 },
    treat_star = { 1.0, 0.85, 0.20 },
    text      = { 1, 1, 1 },
    score_bg  = { 0, 0, 0, 0.4 },
    floor     = { 0.25, 0.30, 0.20 },
}

local function spawn_treat()
    local tx = math.random(treat_w, game_w - treat_w * 2)
    local kind = math.random() < 0.2 and "star" or "treat"
    table.insert(treats, {
        x = tx, y = -treat_h,
        kind = kind,
        speed = treat_speed + math.random(-20, 30),
    })
end

function MiniGame.start(w, h, sound_module, on_finish)
    game_w, game_h = w, h
    player_x = w / 2 - player_w / 2
    treats = {}
    score = 0
    misses = 0
    spawn_timer = 0
    game_timer = 0
    game_state = STATE_READY
    countdown = 3
    countdown_timer = 0
    on_finish_cb = on_finish
    sfx = sound_module
    if sfx then sfx.play("game_start") end
end

function MiniGame.is_active()
    return game_state ~= nil and game_state ~= STATE_DONE
end

function MiniGame.update(dt)
    if game_state == STATE_READY then
        countdown_timer = countdown_timer + dt
        if countdown_timer >= 1 then
            countdown_timer = countdown_timer - 1
            countdown = countdown - 1
            if countdown <= 0 then
                game_state = STATE_PLAYING
            end
        end
        return
    end

    if game_state == STATE_DONE then return end

    game_timer = game_timer + dt

    if Input.held("move_left") then
        player_x = math.max(0, player_x - player_speed * dt)
    end
    if Input.held("move_right") then
        player_x = math.min(game_w - player_w, player_x + player_speed * dt)
    end

    spawn_timer = spawn_timer + dt
    local progress = game_timer / game_duration
    local cur_interval = spawn_interval * (1 - progress * 0.4)
    if spawn_timer >= cur_interval then
        spawn_timer = 0
        spawn_treat()
    end

    local floor_y = game_h - 20
    local py = floor_y - player_h
    local i = 1
    while i <= #treats do
        local tr = treats[i]
        tr.y = tr.y + tr.speed * dt

        if tr.y + treat_h >= py and tr.y <= py + player_h
            and tr.x + treat_w >= player_x and tr.x <= player_x + player_w then
            local pts = tr.kind == "star" and 3 or 1
            score = score + pts
            table.remove(treats, i)
            if sfx then sfx.play("catch") end
        elseif tr.y > game_h then
            misses = misses + 1
            table.remove(treats, i)
            if sfx then sfx.play("miss") end
        else
            i = i + 1
        end
    end

    if game_timer >= game_duration or misses >= max_misses then
        game_state = STATE_DONE
        if sfx then sfx.play("game_end") end
        if on_finish_cb then
            on_finish_cb(score)
        end
    end
end

function MiniGame.draw()
    lg.setColor(COL.bg)
    lg.rectangle("fill", 0, 0, game_w, game_h)

    local floor_y = game_h - 20
    lg.setColor(COL.floor)
    lg.rectangle("fill", 0, floor_y, game_w, 20)

    if game_state == STATE_READY then
        lg.setColor(COL.text)
        local font = Fonts.get(nil, 24)
        lg.setFont(font)
        local text = countdown > 0 and tostring(countdown) or "GO!"
        lg.printf(text, 0, game_h * 0.4, game_w, "center")
        return
    end

    -- Draw treats
    for _, t in ipairs(treats) do
        if t.kind == "star" then
            lg.setColor(COL.treat_star)
            local cx, cy = t.x + treat_w / 2, t.y + treat_h / 2
            local rad = treat_w * 0.6
            for a = 0, 4 do
                local angle = a * math.pi * 2 / 5 - math.pi / 2
                local x1 = cx + math.cos(angle) * rad
                local y1 = cy + math.sin(angle) * rad
                local angle2 = angle + math.pi * 2 / 5
                local x2 = cx + math.cos(angle2) * rad
                local y2 = cy + math.sin(angle2) * r
                lg.polygon("fill", cx, cy, x1, y1, x2, y2)
            end
        else
            lg.setColor(COL.treat)
            lg.rectangle("fill", t.x, t.y, treat_w, treat_h, 3, 3)
            lg.setColor(1, 1, 1, 0.3)
            lg.rectangle("fill", t.x + 2, t.y + 2, treat_w - 4, 3, 1, 1)
        end
    end

    -- Draw player (simple Artemis silhouette)
    local py = floor_y - player_h
    lg.setColor(COL.player)
    lg.rectangle("fill", player_x, py, player_w, player_h, 6, 6)
    lg.setColor(COL.player_ear)
    lg.polygon("fill", player_x + 4, py, player_x + 8, py - 8, player_x + 12, py)
    lg.polygon("fill", player_x + player_w - 12, py, player_x + player_w - 8, py - 8, player_x + player_w - 4, py)
    lg.setColor(0.1, 0.1, 0.1)
    lg.circle("fill", player_x + 10, py + 8, 2)
    lg.circle("fill", player_x + player_w - 10, py + 8, 2)
    lg.circle("fill", player_x + player_w / 2, py + 13, 2.5)

    -- HUD
    lg.setColor(COL.score_bg)
    lg.rectangle("fill", 0, 0, game_w, 18)
    lg.setColor(COL.text)
    local hud_font = Fonts.get(nil, 10)
    lg.setFont(hud_font)
    lg.print("Score: " .. score, 4, 2)
    local time_left = math.max(0, math.ceil(game_duration - game_timer))
    lg.printf(time_left .. "s", 0, 2, game_w - 4, "right")
    local hearts = ""
    for h = 1, max_misses do
        hearts = hearts .. (h <= max_misses - misses and "<3 " or "x ")
    end
    lg.printf(hearts, 0, 2, game_w, "center")

    if game_state == STATE_DONE then
        lg.setColor(0, 0, 0, 0.6)
        lg.rectangle("fill", 0, game_h * 0.3, game_w, game_h * 0.35)
        lg.setColor(COL.text)
        local big = Fonts.get(nil, 16)
        lg.setFont(big)
        lg.printf("Treats caught: " .. score, 0, game_h * 0.35, game_w, "center")
        local small = Fonts.get(nil, 10)
        lg.setFont(small)
        local bonus = score * 3
        lg.printf("+" .. bonus .. " happiness!", 0, game_h * 0.48, game_w, "center")
        lg.printf("Press any button", 0, game_h * 0.56, game_w, "center")
    end
end

return MiniGame
