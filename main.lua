local base = love.filesystem.getSource()
package.path = base .. "/libs/?.lua;"
            .. base .. "/libs/?/init.lua;"
            .. base .. "/modules/?.lua;"
            .. base .. "/modules/?/init.lua;"
            .. package.path

require("se3")

local mcp = require("love_mcp")
local Farm = require("farm")

function love.load()
  local socket = require("socket")
  _G._appLock = socket.bind("127.0.0.1", 21199)
  if not _G._appLock then
    print("[main] Another instance already running. Exiting.")
    love.event.quit()
    return
  end

  love.math.setRandomSeed(os.time())
  mcp.init({ port = 21110 })
  Farm.start()
end

function love.update(dt)              Farm.update(dt) end
function love.draw()                  Farm.draw() end
function love.mousemoved(x,y,dx,dy,t) Farm.mousemoved(x,y,dx,dy,t) end
function love.mousepressed(x,y,b,t)   Farm.mousepressed(x,y,b,t) end
function love.mousereleased(x,y,b,t)  Farm.mousereleased(x,y,b,t) end
function love.wheelmoved(dx,dy)       Farm.wheelmoved(dx,dy) end
function love.keypressed(k,s,r)
  if k == "escape" then love.event.quit() end
  Farm.keypressed(k,s,r)
end
function love.keyreleased(k)          Farm.keyreleased(k) end
function love.quit()                  Farm.shutdown() end
