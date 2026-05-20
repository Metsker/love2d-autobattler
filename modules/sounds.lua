local M = { muted = false }

local SR = 22050
local sources = {}

local function envAt(t, dur, attack, release)
  local env = 1
  if attack and t < attack then env = t / attack end
  if release and t > dur - release then
    env = math.max(0, (dur - t) / release)
  end
  return env
end

local function buildTone(opts)
  -- opts: { freq=f or fn(t), dur, vol, attack, release, wave="sine"|"square"|"noise" }
  local dur = opts.dur
  local samples = math.floor(SR * dur)
  local sd = love.sound.newSoundData(samples, SR, 16, 1)
  local phase = 0
  local prev_t = 0
  for i = 0, samples - 1 do
    local t = i / SR
    local f
    if type(opts.freq) == "function" then f = opts.freq(t / dur)
    else f = opts.freq end
    local dt = t - prev_t
    phase = phase + 2 * math.pi * f * dt
    prev_t = t
    local s
    if opts.wave == "square" then
      s = (math.sin(phase) >= 0) and 1 or -1
    elseif opts.wave == "noise" then
      s = (math.random() * 2 - 1)
    else
      s = math.sin(phase)
    end
    local env = envAt(t, dur, opts.attack, opts.release)
    sd:setSample(i, opts.vol * env * s)
  end
  return sd
end

local function mix(layers)
  -- layers: array of {freq=..., dur, vol, attack, release, wave}
  local maxDur = 0
  for _, l in ipairs(layers) do if l.dur > maxDur then maxDur = l.dur end end
  local samples = math.floor(SR * maxDur)
  local sd = love.sound.newSoundData(samples, SR, 16, 1)
  for i = 0, samples - 1 do
    local t = i / SR
    local acc = 0
    for _, l in ipairs(layers) do
      if t < l.dur then
        local f = (type(l.freq) == "function") and l.freq(t / l.dur) or l.freq
        local s
        if l.wave == "square" then
          s = (math.sin(2 * math.pi * f * t) >= 0) and 1 or -1
        elseif l.wave == "noise" then
          s = (math.random() * 2 - 1)
        else
          s = math.sin(2 * math.pi * f * t)
        end
        acc = acc + l.vol * envAt(t, l.dur, l.attack, l.release) * s
      end
    end
    if acc >  1 then acc =  1 end
    if acc < -1 then acc = -1 end
    sd:setSample(i, acc)
  end
  return sd
end

local function src(sd)
  local s = love.audio.newSource(sd, "static")
  s:setVolume(0.6)
  return s
end

function M.init()
  sources.hit    = src(buildTone{ freq = 180, dur = 0.08, vol = 0.5, attack = 0.002, release = 0.05, wave = "square" })
  sources.crit   = src(mix{
    { freq = function(p) return 600 - 200 * p end, dur = 0.18, vol = 0.45, attack = 0.005, release = 0.12, wave = "square" },
    { freq = 1200,                                  dur = 0.05, vol = 0.30, attack = 0.001, release = 0.04, wave = "sine"   },
  })
  sources.dodge  = src(buildTone{ freq = 90, dur = 0.06, vol = 0.4, attack = 0.005, release = 0.04, wave = "noise" })
  sources.death  = src(buildTone{ freq = function(p) return 320 - 240 * p end, dur = 0.30, vol = 0.5, attack = 0.005, release = 0.18, wave = "square" })
  sources.loot   = src(buildTone{ freq = function(p) return 540 + 360 * p end, dur = 0.16, vol = 0.4, attack = 0.005, release = 0.10, wave = "sine" })
  sources.equip  = src(mix{
    { freq = 440, dur = 0.10, vol = 0.4, attack = 0.005, release = 0.08, wave = "sine" },
    { freq = 660, dur = 0.10, vol = 0.4, attack = 0.005, release = 0.08, wave = "sine" },
  })
  sources.lock   = src(buildTone{ freq = 1500, dur = 0.04, vol = 0.35, attack = 0.001, release = 0.03, wave = "square" })
  sources.advance = src(buildTone{ freq = function(p) return 200 + 300 * p end, dur = 0.22, vol = 0.5, attack = 0.01, release = 0.12, wave = "sine" })
  sources.gameover = src(buildTone{ freq = function(p) return 220 - 160 * p end, dur = 0.60, vol = 0.5, attack = 0.02, release = 0.30, wave = "square" })
  sources.victory  = src(mix{
    { freq = 523, dur = 0.20, vol = 0.4, attack = 0.005, release = 0.10, wave = "sine" },
    { freq = 659, dur = 0.30, vol = 0.4, attack = 0.005, release = 0.20, wave = "sine" },
    { freq = 784, dur = 0.40, vol = 0.4, attack = 0.005, release = 0.25, wave = "sine" },
  })
  sources.click   = src(buildTone{ freq = 600, dur = 0.03, vol = 0.3, attack = 0.001, release = 0.02, wave = "square" })
  sources.heal    = src(mix{
    { freq = 523, dur = 0.10, vol = 0.35, attack = 0.005, release = 0.08, wave = "sine" },
    { freq = 784, dur = 0.18, vol = 0.30, attack = 0.06,  release = 0.10, wave = "sine" },
  })
  sources.dust    = src(buildTone{ freq = function(p) return 880 + 300 * p end, dur = 0.10, vol = 0.30, attack = 0.003, release = 0.07, wave = "sine" })
  sources.reject  = src(buildTone{ freq = 140, dur = 0.10, vol = 0.4, attack = 0.005, release = 0.08, wave = "square" })
end

function M.play(name)
  if M.muted then return end
  local s = sources[name]
  if not s then return end
  if s:isPlaying() then
    local clone = s:clone()
    clone:play()
  else
    s:play()
  end
end

function M.toggleMute()
  M.muted = not M.muted
  if M.muted then love.audio.stop() end
end

function M.isMuted() return M.muted end

return M
