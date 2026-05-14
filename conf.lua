function love.conf(t)
  t.identity = "farmbots"
  t.version  = "11.5"
  t.window.title      = "FarmBots"
  if love._os == "Web" then
    t.window.width  = 1280
    t.window.height = 720
  else
    t.window.width  = 1920
    t.window.height = 1080
  end
  t.window.resizable  = true
  t.window.vsync      = 1
  t.window.fullscreen = false
  t.console = true
end
