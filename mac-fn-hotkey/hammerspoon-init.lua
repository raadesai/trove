-- ╭──────────────────────────────────────────────────────────────╮
-- │  Trove — paper-plane save animation                            │
-- │  Fired after the double-tap-fn save (save.sh opens the URL     │
-- │  event below). A little origami plane pops out of the address  │
-- │  bar, does two calm loops, darts up into the notch — and the   │
-- │  notch "reacts": a black bulge swells out, flashes +1, and     │
-- │  springs back. (Boring Notch has no external API, so the       │
-- │  reaction is our own seamless black overlay.)                  │
-- ╰──────────────────────────────────────────────────────────────╯

local canvas   = require("hs.canvas")
local screen   = require("hs.screen")
local timer    = require("hs.timer")
local urlevent = require("hs.urlevent")
local matrix   = require("hs.canvas").matrix
local http     = require("hs.http")
require("hs.ipc")   -- enables the `hs -c "trovePlane()"` terminal command

math.randomseed(os.time())

-- read-only anon creds (same as the map page) for the unread count, read from
-- ~/.config/trove/config (copy mac-fn-hotkey/config.example and fill it in).
local function troveConfig()
  local cfg, f = {}, io.open(os.getenv("HOME") .. "/.config/trove/config", "r")
  if f then
    for line in f:lines() do
      local k, v = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if k then cfg[k] = v end
    end
    f:close()
  end
  return cfg
end
local CFG           = troveConfig()
local SUPABASE_URL  = CFG.SUPABASE_URL  or ""
local SUPABASE_ANON = CFG.SUPABASE_ANON or ""
local TROVE_NAME    = CFG.NAME          or "Trove"
local function fetchUnreadCount(cb)
  http.asyncGet(
    SUPABASE_URL .. "/rest/v1/links?select=id&board=eq.backlog&consumed=eq.false",
    { apikey = SUPABASE_ANON, Authorization = "Bearer " .. SUPABASE_ANON },
    function(status, body)
      local n = 0
      if status == 200 and body then n = select(2, body:gsub('"id"', '')) end
      cb(n)
    end)
end

-- keep handles so a rapid re-trigger replaces the previous flight
local activeCanvas, activeTimer
local notchCanvas, notchTimer

-- fly on the screen you're actually looking at (where the mouse is);
-- fall back to the built-in notched display, then the primary one
local function activeScreen()
  local m = hs.mouse.getCurrentScreen()
  if m then return m end
  for _, s in ipairs(screen.allScreens()) do
    if tostring(s:name()):find("Built%-in") then return s end
  end
  return screen.primaryScreen()
end

-- ── the notch reaction: a black pill swells from behind the notch showing
--    a green ✓, "Saved to your Trove", and a green badge with the live
--    unread count, then springs back with a little overshoot ──
local function notchReact(scr)
  if notchTimer then notchTimer:stop(); notchTimer = nil end
  if notchCanvas then notchCanvas:delete(); notchCanvas = nil end

  local full = scr:fullFrame()
  local mb   = math.max(24, scr:frame().y - full.y)   -- menubar / notch strip height
  local W, MAXE = 372, 40                             -- pill width / max swell below the notch
  local c = canvas.new({ x = full.x + full.w / 2 - W / 2, y = full.y, w = W, h = mb + MAXE + 34 })
  c:level(canvas.windowLevels.screenSaver)
  c:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
  c:canvasMouseEvents(false, false, false, false)

  local GREEN = { red = 0.20, green = 0.80, blue = 0.36, alpha = 1 }
  local cd = 22                                       -- circle diameter
  -- content row (centred-ish), all BELOW the notch line so it's never hidden
  local checkX, textX, textW, countX = 78, 108, 168, 280

  c:appendElements({ type = "rectangle", id = "bulge",
    roundedRectRadii = { xRadius = 21, yRadius = 21 },
    fillColor = { red = 0, green = 0, blue = 0, alpha = 1 },
    frame = { x = 8, y = -24, w = W - 16, h = 24 + mb } })
  c:appendElements({ type = "circle", id = "checkbg", fillColor = GREEN, radius = cd / 2, center = { x = checkX + cd / 2, y = 0 } })
  c:appendElements({ type = "segments", id = "check", closed = false, action = "stroke",
    strokeColor = { white = 1, alpha = 0 }, strokeWidth = 2.4,
    strokeCapStyle = "round", strokeJoinStyle = "round", coordinates = { { x = 0, y = 0 } } })
  c:appendElements({ type = "text", id = "label", text = "Saved to " .. TROVE_NAME,
    textSize = 13.5, textAlignment = "left", textColor = { white = 1, alpha = 0 },
    frame = { x = textX, y = 0, w = textW, h = 20 } })
  c:appendElements({ type = "circle", id = "countbg", fillColor = GREEN, radius = cd / 2, center = { x = countX + cd / 2, y = 0 } })
  c:appendElements({ type = "text", id = "count", text = "", textSize = 12.5, textAlignment = "center",
    textColor = { white = 1, alpha = 0 }, frame = { x = countX, y = 0, w = cd, h = 18 } })

  c:show()
  notchCanvas = c
  fetchUnreadCount(function(n) if notchCanvas == c then c["count"].text = tostring(n) end end)

  -- swell 0.4s → hold 1.9s → spring back 0.6s  (hold held ½s longer)
  local T, t = 2.9, 0
  local SWELL, HOLD = 0.4, 2.3
  notchTimer = timer.doEvery(1 / 60, function()
    t = t + 1 / 60
    if t >= T then
      if notchTimer then notchTimer:stop(); notchTimer = nil end
      if notchCanvas then notchCanvas:delete(); notchCanvas = nil end
      return
    end
    local e, a
    if t < SWELL then local k = t / SWELL; e, a = MAXE * (1 - (1 - k) ^ 3), k
    elseif t < HOLD then e, a = MAXE, 1
    else local k = (t - HOLD) / (T - HOLD); e = MAXE * (1 - k) * math.cos(k * math.pi * 1.35); a = math.max(0, 1 - k * 1.4) end

    local yc  = mb + e - 27          -- content-row top, bottom-aligned to the pill
    local cyc = yc + cd / 2          -- circle centres
    local g   = { red = GREEN.red, green = GREEN.green, blue = GREEN.blue, alpha = a }
    c["bulge"].frame   = { x = 8, y = -24, w = W - 16, h = 24 + mb + e }
    c["checkbg"].center = { x = checkX + cd / 2, y = cyc }; c["checkbg"].fillColor = g
    -- checkmark centred in the circle (centre x = checkX + cd/2): short arm down
    -- to a vertex, long arm up to the right — balanced, not bottom-heavy
    c["check"].coordinates = {
      { x = checkX + 6.5, y = cyc - 0.5 }, { x = checkX + 9.5, y = cyc + 3.0 }, { x = checkX + 15.5, y = cyc - 3.5 } }
    c["check"].strokeColor = { white = 1, alpha = a }
    c["label"].frame   = { x = textX, y = yc + 2, w = textW, h = 20 }; c["label"].textColor = { white = 1, alpha = a }
    c["countbg"].center = { x = countX + cd / 2, y = cyc }; c["countbg"].fillColor = g
    c["count"].frame   = { x = countX, y = yc + 3, w = cd, h = 16 }; c["count"].textColor = { white = 1, alpha = a }
  end)
end

-- ── build the flight path: one choreographed, deterministic route.
--    A single graceful U — out of the notch, sweep down toward the bottom-right
--    corner, round the base, then climb back up and glide into the notch,
--    arriving dead-vertical for a seamless hand-off to the notch reaction.
--    Cubic beziers with reflected controls keep every join tangent-smooth;
--    a final constant-speed resample keeps the plane's pace even throughout. ──
local function buildPath(fw, fh)
  local raw = {}
  local function push(x, y) raw[#raw + 1] = { x = x, y = y } end
  local function cbez(ax, ay, c1x, c1y, c2x, c2y, bx, by, n)   -- cubic bezier
    for i = 0, n do
      local t = i / n; local u = 1 - t
      local w0, w1, w2, w3 = u*u*u, 3*u*u*t, 3*u*t*t, t*t*t
      push(w0*ax + w1*c1x + w2*c2x + w3*bx,
           w0*ay + w1*c1y + w2*c2y + w3*by)
    end
  end

  -- A symmetric U centred on the screen: both legs mirror-imaged about the
  -- middle (x = fw/2), the base dead-centre, departing/arriving vertically
  -- through the notch. mx() mirrors an x about the centre so the two halves
  -- stay perfectly matched. Legs sit at 0.30 / 0.70, base at 0.90.
  local function mx(x) return fw - x end
  local S  = { x = fw * 0.50, y = 0        }   -- the notch (start & end)
  local P1 = { x = fw * 0.70, y = fh * 0.78 }  -- right leg of the U
  local PB = { x = fw * 0.50, y = fh * 0.90 }  -- base of the U (lowest, centred)
  local P2 = { x = mx(P1.x),  y = fh * 0.78 }  -- left leg (mirror of the right)

  -- 1. out of the notch (straight down) sweeping into the right leg
  cbez(S.x, S.y, fw * 0.50, fh * 0.34, fw * 0.70, fh * 0.64, P1.x, P1.y, 70)
  -- 2. round down into the base, levelling to a horizontal tangent at centre
  cbez(P1.x, P1.y, fw * 0.70, fh * 0.90, fw * 0.62, fh * 0.90, PB.x, PB.y, 55)
  -- 3. mirror of 2: out of the base and up into the left leg
  cbez(PB.x, PB.y, mx(fw * 0.62), fh * 0.90, mx(fw * 0.70), fh * 0.90, P2.x, P2.y, 55)
  -- 4. mirror of 1: climb the left leg and glide into the notch, dead-vertical
  cbez(P2.x, P2.y, mx(fw * 0.70), fh * 0.64, fw * 0.50, fh * 0.34, S.x, S.y, 70)

  -- constant-speed resample (one point every ~6px of travel)
  local pts, need, step = { raw[1] }, 6, 6
  for i = 2, #raw do
    local A, B = raw[i - 1], raw[i]
    local dx, dy = B.x - A.x, B.y - A.y
    local seg = math.sqrt(dx * dx + dy * dy)
    local t = 0
    while seg - t >= need do
      t = t + need
      pts[#pts + 1] = { x = A.x + dx * t / seg, y = A.y + dy * t / seg }
      need = step
    end
    need = need - (seg - t)
  end
  pts[#pts + 1] = raw[#raw]
  return pts
end

function trovePlane()
  hs.settings.set("trovePlane.lastFired", os.time())  -- debug marker
  if activeTimer then activeTimer:stop(); activeTimer = nil end
  if activeCanvas then activeCanvas:delete(); activeCanvas = nil end

  local scr   = activeScreen()
  local frame = scr:fullFrame()                   -- includes the notch strip
  local c     = canvas.new(frame)
  c:level(canvas.windowLevels.screenSaver)        -- above the menubar / notch
  c:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
  c:canvasMouseEvents(false, false, false, false) -- fully click-through

  -- origami plane, nose pointing +x, drawn around the origin (two folds)
  c:appendElements({
    type = "segments", closed = true,
    fillColor   = { red = 1, green = 1, blue = 1, alpha = 1 },
    strokeColor = { red = 0.68, green = 0.71, blue = 0.76, alpha = 1 }, strokeWidth = 1,
    coordinates = { { x = 19, y = 0 }, { x = -17, y = -11 }, { x = -5, y = 0 } },
  })
  c:appendElements({
    type = "segments", closed = true,
    fillColor   = { red = 0.80, green = 0.83, blue = 0.88, alpha = 1 }, -- shaded fold
    strokeColor = { red = 0.68, green = 0.71, blue = 0.76, alpha = 1 }, strokeWidth = 1,
    coordinates = { { x = 19, y = 0 }, { x = -5, y = 0 }, { x = -17, y = 11 } },
  })

  local pts    = buildPath(frame.w, frame.h)
  local N      = #pts
  local BASE   = 1.65                             -- bigger, clearly visible
  local SECS   = 1.5                              -- brisk flight (half the old 3.0s)
  local adv    = N / (SECS * 60)                  -- points advanced per frame
  local p      = 1
  local reacted = false

  c:show()
  activeCanvas = c
  activeTimer = timer.doEvery(1 / 60, function()
    -- ease the pace down through the final approach so the plane glides
    -- (rather than snaps) into the notch
    local fr = p / N
    local speed = adv
    if fr > 0.80 then
      local k = (fr - 0.80) / 0.20                 -- 0→1 across the last leg
      speed = adv * (1 - 0.55 * k)                 -- decelerate to ~45% pace
    end
    p = p + speed
    local i = math.floor(p)
    if i >= N then
      if activeTimer then activeTimer:stop(); activeTimer = nil end
      if activeCanvas then activeCanvas:delete(); activeCanvas = nil end
      return
    end
    local a  = pts[i]
    local b  = pts[math.min(i + 2, N)]
    local ang = math.deg(math.atan(b.y - a.y, b.x - a.x))
    local frac = p / N

    -- fire the notch reaction as the plane glides in, so the swell is already
    -- emerging to meet it (rather than popping after it lands)
    if not reacted and frac > 0.86 then reacted = true; notchReact(scr) end

    -- pop in at the start, shrink + fade into the notch at the end
    local sc, alpha = BASE, 1
    if frac < 0.06 then
      local k = frac / 0.06; sc = BASE * (0.35 + 0.65 * k); alpha = k
    elseif frac > 0.85 then
      local k = (frac - 0.85) / 0.15; sc = BASE * (1 - 0.9 * k); alpha = 1 - k
    end

    c:transformation(matrix.translate(a.x, a.y):rotate(ang):scale(sc))
    c:alpha(alpha)
  end)
end

-- save.sh triggers this with:  open -g "hammerspoon://trovePlane"
urlevent.bind("trovePlane", function() trovePlane() end)

hs.alert.show("Trove ✈ ready")
