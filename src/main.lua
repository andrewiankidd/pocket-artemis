local Love2D4Me = require("love2d4me")
local GameState = Love2D4Me.gamestate
local Pet = require("game.pet")

function love.load()
    GameState.init({
        on_gameplay_init = function() Pet.init() end,
        on_gameplay_update = function(dt) Pet.update(dt) end,
        on_gameplay_draw = function() Pet.draw() end,
    })
end

function love.update(dt) GameState.update(dt) end
function love.draw() GameState.draw() end
function love.keypressed(key) GameState.keypressed(key) end
function love.keyreleased(key) GameState.keyreleased(key) end
function love.mousepressed(x, y, btn) GameState.mousepressed(x, y, btn) end
function love.mousereleased(x, y, btn) GameState.mousereleased(x, y, btn) end
function love.touchpressed(id, x, y) GameState.touchpressed(id, x, y) end
function love.touchreleased(id, x, y) GameState.touchreleased(id, x, y) end
function love.touchmoved(id, x, y) GameState.touchmoved(id, x, y) end
function love.resize(w, h) GameState.resize(w, h) end

function love.quit()
    if GameState.get_state() == "gameplay" then Pet.save() end
end
