local Sounds = {}

Sounds.muted = false

local rate = 22050

local function makeTone(opts)
  local dur = opts.dur or 0.1
  local samples = math.floor(rate * dur)
  local sd = love.sound.newSoundData(samples, rate, 16, 1)
  local wave = opts.wave or "sine"
  local f1 = opts.freq or 440
  local f2 = opts.freq2 or f1
  local gain = opts.gain or 0.25
  local attackT = opts.attack or 0.005
  for i = 0, samples - 1 do
    local t = i / rate
    local progress = t / dur
    local freq = f1 + (f2 - f1) * progress
    local attack = math.min(1, t / attackT)
    local release = math.max(0, 1 - progress)
    local env = attack * release * gain
    local sample
    if wave == "square" then
      sample = (math.sin(2 * math.pi * freq * t) >= 0) and 1 or -1
    elseif wave == "noise" then
      sample = love.math.random() * 2 - 1
    elseif wave == "tri" then
      local phase = (freq * t) % 1
      sample = math.abs(phase * 4 - 2) - 1
    else
      sample = math.sin(2 * math.pi * freq * t)
    end
    sd:setSample(i, sample * env)
  end
  return love.audio.newSource(sd, "static")
end

function Sounds.init()
  Sounds.click   = makeTone({ freq = 1200, dur = 0.035, gain = 0.16 })
  Sounds.buy     = makeTone({ freq = 600,  freq2 = 1000, dur = 0.12, gain = 0.22 })
  Sounds.sell    = makeTone({ freq = 1000, freq2 = 600,  dur = 0.12, gain = 0.22 })
  Sounds.error   = makeTone({ freq = 180,  dur = 0.13, gain = 0.16, wave = "square" })
  Sounds.plant   = makeTone({ freq = 400,  freq2 = 700, dur = 0.07, gain = 0.20, wave = "tri" })
  Sounds.harvest = makeTone({ freq = 900,  freq2 = 1500, dur = 0.16, gain = 0.24 })
  Sounds.work    = makeTone({ freq = 750,  dur = 0.05, gain = 0.16, wave = "tri" })
  Sounds.queue   = makeTone({ freq = 1500, freq2 = 1100, dur = 0.05, gain = 0.18 })
  Sounds.ripen   = makeTone({ freq = 800,  freq2 = 1600, dur = 0.20, gain = 0.22 })
  Sounds.fert    = makeTone({ freq = 500,  freq2 = 950, dur = 0.10, gain = 0.20 })
  Sounds.unlock  = makeTone({ freq = 500,  freq2 = 1200, dur = 0.20, gain = 0.26 })
end

function Sounds.play(name)
  if Sounds.muted then return end
  local s = Sounds[name]
  if not s then return end
  local c = s:clone()
  c:play()
end

return Sounds
