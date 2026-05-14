love.filesystem.setRequirePath(
  "libs/?.lua;libs/?/init.lua;"
  .. "modules/?.lua;modules/?/init.lua;"
  .. love.filesystem.getRequirePath()
)

local isWeb = love.system.getOS() == "Web"
local mcp = not isWeb and require("love_mcp") or nil
local Farm = require("farm")

function love.load()
  if not isWeb then
    local socket = require("socket")
    _G._appLock = socket.bind("127.0.0.1", 21199)
    if not _G._appLock then
      print("[main] Another instance already running. Exiting.")
      love.event.quit()
      return
    end
    mcp.init({ port = 21110 })
  end

  love.math.setRandomSeed(os.time())
  Farm.start()
end

function love.update(dt)              Farm.update(dt) end
function love.draw()                  Farm.draw() end
function love.mousemoved(x,y,dx,dy,t) Farm.mousemoved(x,y,dx,dy,t) end
function love.mousepressed(x,y,b,t)   Farm.mousepressed(x,y,b,t) end
function love.mousereleased(x,y,b,t)  Farm.mousereleased(x,y,b,t) end
function love.wheelmoved(dx,dy)       Farm.wheelmoved(dx,dy) end
function love.keypressed(k,s,r)        Farm.keypressed(k,s,r) end
function love.keyreleased(k)          Farm.keyreleased(k) end
function love.quit()                  Farm.shutdown() end
