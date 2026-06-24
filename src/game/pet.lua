-- pet.lua -- Pocket Artemis: the whole tamagotchi in one module.
--
-- Meters decay in real time (including while the app is closed).
-- Save file stores meter values + timestamp; on load, elapsed offline decay is applied.
-- UI is d-pad driven: left/right navigates toolbar, confirm activates, cancel goes back.

local Input = require("love2d4me.src.input")
local Storage = require("love2d4me.src.storage")
local JSON = require("love2d4me.src.json")
local Fonts = require("love2d4me.src.fonts")
local GameState = require("love2d4me.src.gamestate")
local SFX = require("love2d4me.src.sfx")
local Stats = require("love2d4me.src.stats")
local Toolbar = require("love2d4me.src.toolbar")
local MiniGame = require("game.minigame")

local Pet = {}

local lg = love.graphics
local min, floor = math.min, math.floor

-- ── String enums ──

local NEED = {
    HUNGER    = "hunger",
    THIRST    = "thirst",
    ENERGY    = "energy",
    HAPPINESS = "happiness",
}

local MOOD = {
    HAPPY   = "happy",
    NEUTRAL = "neutral",
    SAD     = "sad",
}

local ANIM = {
    EAT       = "eat",
    DRINK     = "drink",
    PLAY      = "play",
    SLEEP     = "sleep",
    SIT       = "sit",
    SHAKE     = "shake",
    SPIN      = "spin",

    LIE_DOWN  = "lie_down",
    ROLL_OVER = "roll_over",
    BEAR      = "bear",
}


-- ── Balance constants ──

local SAVE_FILE = "save.json"
local SAVE_INTERVAL = 30

local MOOD_THRESHOLD_HAPPY = 0.66
local MOOD_THRESHOLD_SAD   = 0.33
local METER_LOW_THRESHOLD  = 0.25

local TRICK_ANIM_DURATION = 1.5

-- ── Content tables ──

local ACTIONS = {
    { name = "Feed",  action_id = "feed",  meter = NEED.HUNGER,  delta = -30, cooldown = 5,  anim = ANIM.EAT,   dur = 1.5, sfx = "eat",   full_msg = "Not hungry" },
    { name = "Water", action_id = "water", meter = NEED.THIRST,  delta = -30, cooldown = 5,  anim = ANIM.DRINK,  dur = 1.5, sfx = "drink", full_msg = "Not thirsty" },
    { name = "Play",  action_id = "play",  minigame = true, cooldown = 2 },
    { name = "Rest",  action_id = "rest",  meter = NEED.ENERGY,  delta = 30,  cooldown = 10, anim = ANIM.SLEEP,  dur = 10, sfx = "sleep", effects = { [NEED.HUNGER] = 10, [NEED.THIRST] = 10 }, full_msg = "Not tired" },
}

local TRICKS = {
    { name = "Sit",       action_id = "trick_sit",       anim = ANIM.SIT,       happiness = 5,  cooldown = 3, effects = { [NEED.ENERGY] = -2 }, sfx = "trick" },
    { name = "Shake",     action_id = "trick_shake",      anim = ANIM.SHAKE,      happiness = 6,  cooldown = 3, effects = { [NEED.ENERGY] = -3 }, sfx = "trick" },
    { name = "Spin",      action_id = "trick_spin",       anim = ANIM.SPIN,       happiness = 8,  cooldown = 4, effects = { [NEED.ENERGY] = -5, [NEED.HUNGER] = 2 }, sfx = "trick" },
    { name = "Lie Down",  action_id = "trick_lie_down",   anim = ANIM.LIE_DOWN,   happiness = 5,  cooldown = 3, effects = { [NEED.ENERGY] = -1 }, sfx = "trick" },
    { name = "Roll Over", action_id = "trick_roll_over",  anim = ANIM.ROLL_OVER,  happiness = 10, cooldown = 5, effects = { [NEED.ENERGY] = -6, [NEED.HUNGER] = 3 }, sfx = "trick_big" },
    { name = "Bear",      action_id = "trick_bear",       anim = ANIM.BEAR,       happiness = 12, cooldown = 5, dur = 3.5, effects = { [NEED.ENERGY] = -8, [NEED.HUNGER] = 4 }, sfx = "bark" },
}

-- Meter HUD: invert=true means 0 is good (full bar), 100 is bad (empty bar)
local METER_DISPLAY = {
    { key = NEED.HUNGER,    icon_path = "game/icons/hunger.png",    color = { 0.90, 0.55, 0.20 }, invert = true },
    { key = NEED.THIRST,    icon_path = "game/icons/thirst.png",    color = { 0.30, 0.60, 0.90 }, invert = true },
    { key = NEED.ENERGY,    icon_path = "game/icons/energy.png",    color = { 0.85, 0.75, 0.20 }, invert = false },
    { key = NEED.HAPPINESS, icon_path = "game/icons/happiness.png", color = { 0.85, 0.40, 0.60 }, invert = false },
}

-- Animation pose parameters keyed by ANIM.*
local ANIM_POSE = {
    [ANIM.EAT]       = { head_y = 15, head_tilt = 0.15 },
    [ANIM.DRINK]     = { head_y = 15, head_tilt = 0.15 },
    [ANIM.PLAY]      = { bounce_speed = 8, bounce_amp = 8 },
    [ANIM.SLEEP]     = { squish_x = 1.3, squish_y = 0.7, body_y = 10 },
    [ANIM.SIT]       = { squish_y = 0.85, body_y = 6 },
    [ANIM.SHAKE]     = { shake_speed = 12, shake_amp = 0.2 },
    [ANIM.SPIN]      = { spin_speed = 6 },

    [ANIM.LIE_DOWN]  = { squish_x = 1.4, squish_y = 0.5, body_y = 20 },
    [ANIM.ROLL_OVER] = { squish_y = 0.6, body_y = 15, roll_speed = 4, roll_amp = 0.5 },
    [ANIM.BEAR]      = { squish_x = 0.75, squish_y = 1.3, body_y = -18, shake_speed = 10, shake_amp = 0.08 },
}

-- ── Colors ──

local COL = {
    bg           = { 0.93, 0.91, 0.87 },
    meter_bg     = { 0.55, 0.53, 0.50 },
    meter_low    = { 0.80, 0.25, 0.25 },
    text         = { 0.20, 0.20, 0.20 },
    text_light   = { 0.50, 0.50, 0.50 },
    body_cream   = { 0.95, 0.88, 0.75 },
    body_brown   = { 0.65, 0.45, 0.30 },
    body_white   = { 1.0,  0.98, 0.95 },
    eye_blue     = { 0.35, 0.55, 0.85 },
    nose_black   = { 0.15, 0.15, 0.15 },
    tongue_pink  = { 0.90, 0.50, 0.55 },
    [MOOD.HAPPY]   = { 0.30, 0.75, 0.35 },
    [MOOD.NEUTRAL] = { 0.85, 0.75, 0.20 },
    [MOOD.SAD]     = { 0.70, 0.35, 0.35 },
    bubble_fill     = { 1, 1, 1, 0.9 },
    bubble_border   = { 0.6, 0.6, 0.6 },
}

local MOOD_LABEL = {
    [MOOD.HAPPY]   = "Happy!",
    [MOOD.NEUTRAL] = "Okay",
    [MOOD.SAD]     = "Sad...",
}

local CRITICAL_INFO = {
    { key = NEED.ENERGY,    label = "Tired...",   refusal = "Too tired...",   color = { 0.55, 0.45, 0.70 } },
    { key = NEED.HUNGER,    label = "Hungry...",  refusal = "Too hungry...",  color = { 0.90, 0.55, 0.20 } },
    { key = NEED.THIRST,    label = "Thirsty...", refusal = "Too thirsty...", color = { 0.30, 0.60, 0.90 } },
}

-- ── Layout (computed from game size in init) ──

local L = {}

local function compute_layout(w, h)
    L.game_w = w
    L.game_h = h

    -- Meter icons
    L.meter_icon_w    = floor(w * 0.133)
    L.meter_icon_h    = floor(h * 0.167)
    L.meter_gap       = floor(w * 0.033)
    L.meter_y         = floor(h * 0.017)
    L.meter_inset     = 2
    L.meter_font      = floor(h * 0.058)

    -- Mood label
    L.mood_y          = L.meter_y + L.meter_icon_h + floor(h * 0.01)
    L.mood_font       = floor(h * 0.042)

    -- Dog
    L.dog_cx          = floor(w / 2)
    L.dog_cy          = floor(h * 0.45)
    L.dog_scale       = h / 240

    -- Thought bubble
    L.thought_font    = floor(h * 0.042)
    L.thought_pad_x   = floor(w * 0.025)
    L.thought_pad_y   = floor(h * 0.017)
    L.thought_offset  = floor(h * 0.21)
    L.thought_corner  = floor(h * 0.033)
    L.thought_dot1_r  = floor(h * 0.017)
    L.thought_dot2_r  = floor(h * 0.013)

end

-- ── Runtime state ──

local mood = MOOD.HAPPY
local current_anim = nil
local anim_timer = 0
local anim_duration = 0
local save_timer = 0
local thought_text = nil
local thought_timer = 0
local wag_phase = 0
local sprite_frame_timer = 0

local sprites = {}      -- anim_key -> { img, quads, frames, fps }
local sprites_loaded = false
local idle_pool = {}    -- { { key, weight }, ... } — built from idle_chance in sprites.json
local idle_total_weight = 0
local idle_timer = 0
local idle_playing = false
local IDLE_MIN_DELAY = 4
local IDLE_MAX_DELAY = 10
local idle_next_delay = 6

-- ── Helpers ──

local function idle_anim(m) return "idle_" .. m end

local function calc_mood()
    local avg = Stats.get_average()
    if avg > MOOD_THRESHOLD_HAPPY then return MOOD.HAPPY
    elseif avg > MOOD_THRESHOLD_SAD then return MOOD.NEUTRAL
    else return MOOD.SAD end
end

local function set_anim(name, duration)
    current_anim = name
    anim_timer = 0
    anim_duration = duration or 0
    sprite_frame_timer = 0
end

local function show_thought(text, duration)
    thought_text = text
    thought_timer = duration or 2
end

local function is_on_cooldown(action_id)
    return Toolbar.is_on_cooldown(action_id)
end

local function pick_idle_anim()
    if idle_total_weight <= 0 or #idle_pool == 0 then return nil, nil end
    local r = math.random() * idle_total_weight
    for _, entry in ipairs(idle_pool) do
        r = r - entry.weight
        if r <= 0 then return entry.key, entry.duration end
    end
    local last = idle_pool[#idle_pool]
    return last.key, last.duration
end

local function reset_idle_timer()
    idle_timer = 0
    idle_next_delay = IDLE_MIN_DELAY + math.random() * (IDLE_MAX_DELAY - IDLE_MIN_DELAY)
end

-- ── Save / Load ──

local function save()
    local data = Stats.serialize()
    data.last_save = os.time()
    Storage.write(SAVE_FILE, JSON.encode(data))
end

local function load_save()
    local str = Storage.read(SAVE_FILE)
    if not str then return end
    local data = JSON.decode(str)
    if not data then return end

    Stats.deserialize(data)

    if data.last_save then
        local elapsed = os.time() - data.last_save
        if elapsed > 0 then Stats.tick(elapsed) end
    end
end

-- ── Actions / Tricks ──

local function get_critical()
    for _, info in ipairs(CRITICAL_INFO) do
        if Stats.is_critical(info.key) then return info end
    end
    return nil
end

local function get_refusal()
    local c = get_critical()
    return c and c.refusal or nil
end

local minigame_active = false

local function finish_minigame(score)
    local bonus = score * 3
    Stats.add(NEED.HAPPINESS, bonus)
    Stats.add(NEED.ENERGY, -10)
    Stats.add(NEED.HUNGER, 5)
    show_thought("Fun!", 2)
    set_anim(ANIM.PLAY, 1.5)
    save()
end

local function start_minigame()
    minigame_active = true
    MiniGame.start(L.game_w, L.game_h, SFX, function(score)
        finish_minigame(score)
    end)
end

local function do_action(action)
    if anim_duration > 0 and not idle_playing then return end
    if is_on_cooldown(action.action_id) then return end
    if action.minigame then
        local refusal = get_refusal()
        if refusal then
            show_thought(refusal, 1.5)
            SFX.play("sad")
            return
        end
        Toolbar.start_cooldown(action.action_id, action.cooldown)
        start_minigame()
        return
    end
    if action.full_msg and action.meter then
        if Stats.is_full(action.meter) then
            show_thought(action.full_msg, 1.5)
            return
        end
    end
    if action.meter then
        Stats.add(action.meter, action.delta)
    end
    if action.effects then
        for k, v in pairs(action.effects) do
            Stats.add(k, v)
        end
    end
    Toolbar.start_cooldown(action.action_id, action.cooldown)
    set_anim(action.anim, action.dur)
    show_thought(action.name .. "!", action.dur)
    if action.sfx then SFX.play(action.sfx) end
    idle_playing = false
    reset_idle_timer()
    save()
end

local function do_trick(trick)
    if anim_duration > 0 and not idle_playing then return end
    if is_on_cooldown(trick.action_id) then return end
    local refusal = get_refusal()
    if refusal then
        show_thought(refusal, 1.5)
        SFX.play("sad")
        return
    end
    Stats.add(NEED.HAPPINESS, trick.happiness)
    if trick.effects then
        for k, v in pairs(trick.effects) do
            Stats.add(k, v)
        end
    end
    Toolbar.start_cooldown(trick.action_id, trick.cooldown)
    set_anim(trick.anim, trick.dur or TRICK_ANIM_DURATION)
    show_thought(trick.name .. "!", TRICK_ANIM_DURATION)
    if trick.sfx then SFX.play(trick.sfx) end
    idle_playing = false
    reset_idle_timer()
    save()
end

-- ── Drawing: meter icons ──

local function draw_meters()
    local count = #METER_DISPLAY
    local total_w = count * L.meter_icon_w + (count - 1) * L.meter_gap
    local start_x = (L.game_w - total_w) / 2

    for i, m in ipairs(METER_DISPLAY) do
        local x = start_x + (i - 1) * (L.meter_icon_w + L.meter_gap)
        local y = L.meter_y
        local fill = Stats.get_fill(m.key)

        lg.setColor(COL.meter_bg)
        lg.rectangle("fill", x, y, L.meter_icon_w, L.meter_icon_h, 4, 4)

        local inner_h = L.meter_icon_h - L.meter_inset * 2
        local fill_h = inner_h * fill
        lg.setColor(fill < METER_LOW_THRESHOLD and COL.meter_low or m.color)
        if fill_h > 0 then
            lg.rectangle("fill",
                x + L.meter_inset,
                y + L.meter_inset + inner_h - fill_h,
                L.meter_icon_w - L.meter_inset * 2,
                fill_h)
        end

        lg.setColor(1, 1, 1, 0.9)
        if m.icon_img then
            local iw, ih = m.icon_img:getDimensions()
            local pad = L.meter_inset * 2
            local max_sz = math.min(L.meter_icon_w - pad, L.meter_icon_h - pad)
            local s = max_sz / math.max(iw, ih)
            lg.draw(m.icon_img, x + (L.meter_icon_w - iw * s) / 2, y + (L.meter_icon_h - ih * s) / 2, 0, s, s)
        end

        lg.setColor(0, 0, 0, 0.15)
        lg.rectangle("line", x, y, L.meter_icon_w, L.meter_icon_h, 4, 4)
    end
end

-- ── Drawing: mood ──

local function draw_mood()
    lg.setFont(Fonts.get(nil, L.mood_font))
    local crit = get_critical()
    if crit then
        lg.setColor(crit.color)
        lg.printf(crit.label, 0, L.mood_y, L.game_w, "center")
    else
        lg.setColor(COL[mood])
        lg.printf(MOOD_LABEL[mood], 0, L.mood_y, L.game_w, "center")
    end
end


-- ── Drawing: Artemis placeholder ──

local function draw_artemis(cx, cy, s)
    local anim = current_anim
    local pose = ANIM_POSE[anim] or {}

    local body_y_off = pose.body_y and pose.body_y * s or 0
    local head_y_off = pose.head_y and pose.head_y * s or 0
    local head_tilt  = pose.head_tilt or 0
    local squish_x   = pose.squish_x or 1
    local squish_y   = pose.squish_y or 1

    if pose.bounce_speed then
        body_y_off = math.sin(anim_timer * pose.bounce_speed) * pose.bounce_amp * s
    end
    if pose.shake_speed then
        head_tilt = math.sin(anim_timer * pose.shake_speed) * pose.shake_amp
    end
    if pose.spin_speed then
        head_tilt = anim_timer * pose.spin_speed
    end
    if pose.roll_speed then
        head_tilt = math.sin(anim_timer * pose.roll_speed) * pose.roll_amp
    end

    local bw = 55 * s * squish_x
    local bh = 45 * s * squish_y
    local by = cy + body_y_off

    -- Tail
    local tail_wag = mood == MOOD.HAPPY and math.sin(wag_phase * 6) * 0.4
                  or (mood == MOOD.SAD and 0.5 or 0)
    lg.push()
    lg.translate(cx + bw * 0.7, by - bh * 0.2)
    lg.rotate(tail_wag - 0.8)
    lg.setColor(COL.body_cream)
    lg.ellipse("fill", 0, -15 * s, 8 * s, 20 * s)
    lg.setColor(COL.body_white)
    lg.circle("fill", 0, -30 * s, 7 * s)
    lg.pop()

    -- Body
    lg.setColor(COL.body_cream)
    lg.ellipse("fill", cx, by, bw, bh)
    lg.setColor(COL.body_white)
    lg.ellipse("fill", cx, by + bh * 0.2, bw * 0.6, bh * 0.5)

    -- Legs
    if squish_y > 0.6 then
        local leg_w = 10 * s
        local leg_h = 18 * s * squish_y
        lg.setColor(COL.body_cream)
        lg.ellipse("fill", cx - bw * 0.5, by + bh * 0.7, leg_w, leg_h)
        lg.ellipse("fill", cx + bw * 0.5, by + bh * 0.7, leg_w, leg_h)
        lg.setColor(COL.body_white)
        lg.ellipse("fill", cx - bw * 0.5, by + bh * 0.7 + leg_h * 0.6, leg_w * 0.8, 5 * s)
        lg.ellipse("fill", cx + bw * 0.5, by + bh * 0.7 + leg_h * 0.6, leg_w * 0.8, 5 * s)
    end

    -- Head
    local hx = cx - bw * 0.35
    local hy = by - bh * 0.7 + head_y_off
    local hr = 30 * s

    lg.push()
    lg.translate(hx, hy)
    lg.rotate(head_tilt)

    lg.setColor(COL.body_cream)
    lg.circle("fill", 0, 0, hr)
    lg.setColor(COL.body_white)
    lg.ellipse("fill", 0, hr * 0.2, hr * 0.55, hr * 0.4)

    -- Ears
    lg.setColor(COL.body_brown)
    lg.polygon("fill", -hr * 0.6, -hr * 0.3, -hr * 0.3, -hr * 1.1, 0, -hr * 0.3)
    lg.polygon("fill", 0, -hr * 0.3, hr * 0.35, -hr * 0.9, hr * 0.7, -hr * 0.2)
    lg.setColor(COL.tongue_pink[1], COL.tongue_pink[2], COL.tongue_pink[3], 0.4)
    lg.polygon("fill", -hr * 0.5, -hr * 0.3, -hr * 0.3, -hr * 0.85, -hr * 0.1, -hr * 0.3)

    -- Eyes
    local is_sleeping = (anim == ANIM.SLEEP)
    if is_sleeping then
        lg.setColor(COL.nose_black)
        lg.setLineWidth(2)
        lg.arc("line", "open", -hr * 0.25, -hr * 0.05, 4 * s, 0, math.pi)
        lg.arc("line", "open",  hr * 0.25, -hr * 0.05, 4 * s, 0, math.pi)
        lg.setLineWidth(1)
    else
        lg.setColor(1, 1, 1)
        lg.circle("fill", -hr * 0.25, -hr * 0.05, 6 * s)
        lg.circle("fill",  hr * 0.25, -hr * 0.05, 6 * s)
        lg.setColor(COL.eye_blue)
        lg.circle("fill", -hr * 0.25, -hr * 0.05, 3.5 * s)
        lg.circle("fill",  hr * 0.25, -hr * 0.05, 3.5 * s)
        lg.setColor(COL.nose_black)
        lg.circle("fill", -hr * 0.25, -hr * 0.05, 1.5 * s)
        lg.circle("fill",  hr * 0.25, -hr * 0.05, 1.5 * s)
    end

    -- Nose
    lg.setColor(COL.nose_black)
    lg.ellipse("fill", 0, hr * 0.15, 4 * s, 3 * s)

    -- Mouth
    lg.setLineWidth(2)
    if mood == MOOD.HAPPY and not is_sleeping then
        lg.setColor(COL.nose_black)
        lg.arc("line", "open", 0, hr * 0.2, 8 * s, 0.2, math.pi - 0.2)
        lg.setColor(COL.tongue_pink)
        lg.ellipse("fill", 3 * s, hr * 0.35, 4 * s, 6 * s)
    elseif mood == MOOD.SAD then
        lg.setColor(COL.nose_black)
        lg.arc("line", "open", 0, hr * 0.35, 8 * s, math.pi + 0.3, 2 * math.pi - 0.3)
    else
        lg.setColor(COL.nose_black)
        lg.line(-5 * s, hr * 0.25, 5 * s, hr * 0.25)
    end
    lg.setLineWidth(1)
    lg.pop()

    -- Z's when sleeping
    if is_sleeping then
        lg.setColor(COL.text_light)
        lg.setFont(Fonts.get(nil, 16))
        local z_off = math.sin(anim_timer * 2) * 5
        local zx, zy = hx + hr * 0.8, hy - hr * 0.8
        lg.print("z", zx, zy - 10 + z_off)
        lg.print("Z", zx + 10, zy - 25 + z_off * 0.7)
        lg.print("Z", zx + 18, zy - 42 + z_off * 0.5)
    end
end

-- ── Drawing: sprite-based Artemis ──

local function draw_artemis_sprite(cx, cy)
    local spr = sprites[current_anim]
    if not spr then
        spr = sprites["idle_neutral"] or sprites["idle_happy"]
    end
    if not spr then return false end

    local frame_idx = 0
    if spr.frames > 1 then
        local total_frame = floor(sprite_frame_timer * spr.fps)
        if spr.loop_from then
            local lf = spr.loop_from
            local lt = spr.loop_to or (spr.frames - 1)
            local intro_len = lt + 1
            local loop_len = lt - lf + 1
            if total_frame < intro_len then
                frame_idx = total_frame
            else
                frame_idx = lf + (total_frame - intro_len) % loop_len
            end
        else
            frame_idx = total_frame % spr.frames
        end
    end

    local max_h = L.game_h * 0.4
    local scale = min(max_h / spr.frame_h, max_h / spr.frame_w)
    local draw_w = spr.frame_w * scale
    local draw_h = spr.frame_h * scale

    lg.setColor(1, 1, 1, 1)
    lg.draw(spr.img, spr.quads[frame_idx + 1],
        cx - draw_w / 2, cy - draw_h / 2, 0, scale, scale)
    return true
end

-- ── Drawing: thought bubble ──

local function draw_thought_bubble(cx, cy, text)
    if not text or thought_timer <= 0 then return end
    local font = Fonts.get(nil, L.thought_font)
    lg.setFont(font)
    local tw = font:getWidth(text) + L.thought_pad_x * 2
    local th = font:getHeight() + L.thought_pad_y * 2
    local bx = cx - tw / 2
    local by = cy - L.thought_offset
    lg.setColor(COL.bubble_fill)
    lg.rectangle("fill", bx, by, tw, th, L.thought_corner, L.thought_corner)
    lg.setColor(COL.bubble_border)
    lg.rectangle("line", bx, by, tw, th, L.thought_corner, L.thought_corner)
    lg.setColor(COL.bubble_fill)
    lg.circle("fill", cx - 5, by + th + 4, L.thought_dot1_r)
    lg.circle("fill", cx - 10, by + th + 12, L.thought_dot2_r)
    lg.setColor(COL.text)
    lg.printf(text, bx, by + L.thought_pad_y, tw, "center")
end

-- ── Public API ──

function Pet.init()
    local w, h = GameState.get_game_size()
    compute_layout(w, h)

    -- Define stats
    Stats.define(NEED.HUNGER,    { min = 0, max = 100, default = 30, decay =  1.0/60, invert = true,  critical = 95, full = 10 })
    Stats.define(NEED.THIRST,    { min = 0, max = 100, default = 30, decay =  1.5/60, invert = true,  critical = 95, full = 10 })
    Stats.define(NEED.ENERGY,    { min = 0, max = 100, default = 70, decay = -0.8/60, invert = false, critical = 5,  full = 90 })
    Stats.define(NEED.HAPPINESS, { min = 0, max = 100, default = 70, decay = -0.5/60, invert = false })
    Stats.reset()

    -- Init toolbar
    Toolbar.init(w, h)
    Toolbar.set_on_navigate(function() SFX.play("navigate") end)

    local main_menu = {}
    for _, a in ipairs(ACTIONS) do
        table.insert(main_menu, { label = a.name, kind = "action", id = a.action_id, ref = a })
    end
    local tricks_menu = {}
    table.insert(tricks_menu, { label = "Back", kind = "back" })
    for _, t in ipairs(TRICKS) do
        table.insert(tricks_menu, { label = t.name, kind = "action", id = t.action_id, ref = t })
    end
    table.insert(main_menu, { label = "Tricks", kind = "submenu", submenu = tricks_menu })
    Toolbar.set_menu(main_menu)

    for _, m in ipairs(METER_DISPLAY) do
        if m.icon_path and love.filesystem.getInfo(m.icon_path) then
            m.icon_img = lg.newImage(m.icon_path)
            m.icon_img:setFilter("linear", "linear")
        end
    end

    -- Load sprite sheet
    local sprite_cfg_path = "game/sprites/sprites.json"
    if love.filesystem.getInfo(sprite_cfg_path) then
        local raw = love.filesystem.read(sprite_cfg_path)
        local cfg = JSON.decode(raw)
        if cfg and cfg.sheet then
            local img_path = "game/sprites/" .. cfg.sheet
            if love.filesystem.getInfo(img_path) then
                local img = lg.newImage(img_path)
                img:setFilter("nearest", "nearest")
                local iw, ih = img:getDimensions()
                local cw = cfg.cell_w
                local ch = cfg.cell_h
                for key, def in pairs(cfg.animations) do
                    local quads = {}
                    for f = 0, (def.frames or 1) - 1 do
                        local col = (def.col or 0) + f
                        local row = def.row or 0
                        table.insert(quads, lg.newQuad(col * cw, row * ch, cw, ch, iw, ih))
                    end
                    sprites[key] = {
                        img = img,
                        quads = quads,
                        frames = def.frames or 1,
                        fps = def.fps or 1,
                        frame_w = cw,
                        frame_h = ch,
                        loop_from = def.loop_from,
                        loop_to = def.loop_to,
                    }
                end
                sprites_loaded = true

                idle_pool = {}
                idle_total_weight = 0
                for key, def in pairs(cfg.animations) do
                    if def.idle_chance and def.idle_chance > 0 then
                        table.insert(idle_pool, { key = key, weight = def.idle_chance, duration = def.idle_duration })
                        idle_total_weight = idle_total_weight + def.idle_chance
                    end
                end
            end
        end
    end

    load_save()
    mood = calc_mood()
    current_anim = idle_anim(mood)
    reset_idle_timer()

    -- Register sounds
    local S = SFX
    S.generate("eat", 0.25, function(t, d) return S.square(200 + 100 * math.sin(t * 30), t) * S.fade(t, d) * 0.6 end)
    S.generate("drink", 0.3, function(t, d) return S.sine(300 + 150 * math.sin(t * 20), t) * S.fade(t, d) * 0.5 end)
    S.generate("play", 0.3, function(t, d) return S.square(400 + 200 * t / d, t) * S.fade(t, d) * 0.5 end)
    S.generate("sleep", 0.5, function(t, d) return S.sine(150 + 30 * math.sin(t * 4), t) * S.fade(t, d) * 0.3 end)
    S.generate("trick", 0.2, function(t, d) return S.square(500 + 300 * t / d, t) * S.fade(t, d) * 0.5 end)
    S.generate("trick_big", 0.35, function(t, d) return S.square(400 + math.floor(t * 12) * 80, t) * S.fade(t, d) * 0.5 end)
    S.generate("happy", 0.25, function(t, d) return S.square(600 + math.floor(t * 8) * 50, t) * S.fade(t, d) * 0.4 end)
    S.generate("sad", 0.4, function(t, d) return S.sine(300 - 100 * t / d, t) * S.fade(t, d) * 0.3 end)
    S.generate("catch", 0.12, function(t, d) return S.square(800 + 400 * t / d, t) * S.fade(t, d) * 0.5 end)
    S.generate("miss", 0.2, function(t, d) return S.square(200 - 100 * t / d, t) * S.fade(t, d) * 0.4 end)
    S.generate("game_start", 0.3, function(t, d) return S.square(300 + math.floor(t * 6) * 100, t) * S.fade(t, d) * 0.4 end)
    S.generate("game_end", 0.5, function(t, d)
        local notes = {523, 659, 784, 1047}
        return S.square(notes[(math.floor(t * 8) % 4) + 1], t) * S.fade(t, d) * 0.4
    end)
    S.generate("navigate", 0.05, function(t, d) return S.square(800, t) * S.fade(t, d) * 0.2 end)
    S.load("bark", "game/sounds/bark.wav", { volume = 0.5 })
end

function Pet.update(dt)
    if minigame_active then
        if MiniGame.is_active() then
            MiniGame.update(dt)
        else
            if Input.pressed("confirm") or Input.pressed("cancel") then
                minigame_active = false
                idle_playing = false
                reset_idle_timer()
            end
        end
        return
    end

    Stats.tick(dt)
    mood = calc_mood()

    -- Auto-rest when energy is depleted
    if Stats.get(NEED.ENERGY) <= 0 and anim_duration <= 0 and not idle_playing then
        local rest_action = ACTIONS[4]
        if not is_on_cooldown(rest_action.action_id) then
            Stats.add(rest_action.meter, rest_action.delta)
            if rest_action.effects then
                for k, v in pairs(rest_action.effects) do Stats.add(k, v) end
            end
            Toolbar.start_cooldown(rest_action.action_id, rest_action.cooldown)
            set_anim(rest_action.anim, rest_action.dur)
            show_thought("Zzz...", rest_action.dur)
            if rest_action.sfx then SFX.play(rest_action.sfx) end
            idle_playing = false
            reset_idle_timer()
            save()
        end
    end

    -- Toolbar navigation
    local activated = Toolbar.update(dt, Input)
    if activated then
        if activated.ref then
            if activated.ref.happiness then
                do_trick(activated.ref)
            else
                do_action(activated.ref)
            end
        end
    end

    -- Animation
    if anim_duration > 0 then
        anim_timer = anim_timer + dt
        if anim_timer >= anim_duration then
            anim_duration = 0
            anim_timer = 0
            idle_playing = false
            current_anim = idle_anim(mood)
            reset_idle_timer()
        end
    elseif idle_playing then
        local spr = sprites[current_anim]
        if spr and spr.frames > 1 then
            local total_frame = floor(sprite_frame_timer * spr.fps)
            if total_frame >= spr.frames then
                idle_playing = false
                current_anim = idle_anim(mood)
                reset_idle_timer()
            end
        end
    else
        idle_timer = idle_timer + dt
        if idle_timer >= idle_next_delay then
            local anim_key, dur = pick_idle_anim()
            if anim_key and sprites[anim_key] then
                current_anim = anim_key
                sprite_frame_timer = 0
                anim_timer = 0
                anim_duration = dur or 0
                idle_playing = true
            end
            reset_idle_timer()
        end
        if not idle_playing then
            current_anim = idle_anim(mood)
        end
    end

    if thought_timer > 0 then
        thought_timer = thought_timer - dt
        if thought_timer <= 0 then thought_text = nil end
    end

    wag_phase = wag_phase + dt
    sprite_frame_timer = sprite_frame_timer + dt

    save_timer = save_timer + dt
    if save_timer >= SAVE_INTERVAL then
        save_timer = 0
        save()
    end
end

function Pet.draw()
    if minigame_active then
        MiniGame.draw()
        lg.setColor(1, 1, 1)
        return
    end

    lg.setColor(COL.bg)
    lg.rectangle("fill", 0, 0, L.game_w, L.game_h)

    draw_meters()
    draw_mood()
    if not sprites_loaded or not draw_artemis_sprite(L.dog_cx, L.dog_cy) then
        draw_artemis(L.dog_cx, L.dog_cy, L.dog_scale)
    end
    draw_thought_bubble(L.dog_cx, L.dog_cy - L.thought_offset * 0.4, thought_text)
    Toolbar.draw()

    lg.setColor(1, 1, 1)
end

function Pet.save()
    save()
end

return Pet
