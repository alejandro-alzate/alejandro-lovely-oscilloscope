--luacheck: globals love
local moonshine = require("lib.moonshine")
local scope = require("scope")
local man = require("array-manipulation")
local rgb = require("lib.color2RGB")
local srt = require("lib.srt")
local vumeter = love.graphics.newImage("res/vugradient.png")
local captions = srt.new("")
--Un-comment to load automatically a file and play it immediately
local recording = false
local soundData -- = love.sound.newSoundData("music.ogg")
local music -- = love.audio.newSource(soundData)
local lines = {0,0,10,10}
local lastTell = 0
local currentTell = 0
local vuL = 0
local vuR = 0
local dBvuL = 0
local dBvuR = 0
local normalizeddBvuL = 0
local normalizeddBvuR = 0
local gravity = 0.5
local vubarL = 0
local vubarR = 0
local vuColorL = "#ffffff"
local vuColorR = "#ffffff"
local showPerformance = false
local showCaptions = true
local showVUMeter = true
local simulateRealCRTBeam = true
local queueSourcesInstead = true
local useShaders = false
local scopeMode = "XY"
local samples = {}
local video
local showVideo = true
local defaultRecordingDevice = love.audio.getRecordingDevices()[1]
--local rawSamples = {}
local warningMsg = [[
Disclaimer: Remeber that some files are
too spicy and may trigger seizures
on some people with that out of he way
]]
local welcomeMsg = [[
Welcome to Alejandro's Oscilloscope.
]]
local dropfileMsg = [[
To start just drop an audio file.
]]
-- local loadingMsg = [[
-- Loading file %s...
-- ]]
-- local waitingMsg = [[
-- You can play this again by pressing space,
-- Or just drop another file.
-- ]]
local titleMsg = [[Alejandro's Oscilloscope]]
local shader = moonshine(moonshine.effects.crt).chain(moonshine.effects.glow).chain(moonshine.effects.scanlines)
shader.scanlines.phase = 1
shader.scanlines.width = 1
shader.scanlines.thickness = 1
shader.scanlines.opacity = 0.3

function love.load()
	love.graphics.setLineWidth(1)
	love.graphics.setNewFont(24)
	love.graphics.setDefaultFilter("nearest", "nearest")
	love.window.setTitle(titleMsg)
	if music then
		music:play()
		if video then pcall(video.play, video) end
	end
end

local function getAbsoluteAverage(array, combine)
	local averageLeft = 0
	local countLeft = 0
	local averageRight = 0
	local countRight = 0

	for i,v in ipairs(array) do
		local value = math.abs(v)
		if i % 2 == 0 then
			averageRight = averageRight + value
			countRight = countRight + 1
		else
			averageLeft = averageLeft + value
			countLeft = countLeft + 1
		end
	end
	averageLeft = averageLeft / countLeft
	averageRight = averageRight / countRight

	if combine then return (averageLeft + averageRight) / 2	end

	return averageLeft, averageRight
end

-- I did not came up to linearToDecibels and normalizeDecibels
-- I looked them up to be completely honest
local function linearToDecibels(linearValue, referenceValue)
	-- Ensure positive linear and reference values for logarithm calculation
	linearValue = math.max(linearValue, 1e-12)  -- Prevent log10(0) or negative values
	referenceValue = referenceValue or 1  -- Default reference value is 1

	-- Calculate decibels using the formula: dB = 20 * log10(linearValue / referenceValue)
	local dB = 20 * math.log10(linearValue / referenceValue)
	return dB
end

local function normalizeDecibels(dB)
	-- Define the minimum and maximum dB values for mapping
	local minDB = -99
	local maxDB = 0

	-- Ensure dB value is within the range [minDB, maxDB]
	dB = math.max(dB, minDB)
	dB = math.min(dB, maxDB)

	-- Linear interpolation to map dB to the range [0, 1]
	local normalizedValue = (dB - minDB) / (maxDB - minDB)

	return normalizedValue
end

local function categorizeDB(dB)
	-- Define thresholds for each section
	local whisperThreshold = -30  -- dB threshold for whisper-like (quiet) sounds
	local audibleThreshold = -10  -- dB threshold for audible (normal) sounds
	-- Noisy range will be above audibleThreshold

	-- Categorize the dB level based on the thresholds
	if dB <= whisperThreshold then
		return 1
	elseif dB <= audibleThreshold then
		return 2
	else
		return 3
	end
end

local function changeMusicVolume(source, changeAmountPercent)
	local currentVolume = source:getVolume()
	local maxVolume = 1.0
	local minVolume = 0.0

	-- Calculate logarithmic change in volume
	local scaleFactor = 10  -- Adjust this scale factor for logarithmic effect
	local logChange = math.log10(currentVolume + 1) * (changeAmountPercent / 100.0 * scaleFactor)

	-- Calculate new volume based on logarithmic change
	local newVolume = currentVolume + (logChange / 100.0)

	-- Clamp the new volume between 0.0 and 1.0
	newVolume = math.max(minVolume, math.min(maxVolume, newVolume))

	-- Set the new volume for the music source
	source:setVolume(newVolume)
end

local function changevuBarColor()
	local colors = {
		"#4CFF4C",
		"#FFFF4C",
		"#FF4C4C",
	}
	vuColorL = colors[categorizeDB(dBvuL)] or "#FF1C1C"
	vuColorR = colors[categorizeDB(dBvuR)] or "#FF1C1C"
end

local function updatevumeterBar(dt, volL, volR)
	--Falls slowy
	vubarL = vubarL - gravity * dt
	vubarR = vubarR - gravity * dt

	--Forcefully goes up
	vubarL = math.max(volL, vubarL)
	vubarR = math.max(volR, vubarR)

	local max = 1
	local min = 0

	--Clamp it
	vubarL = math.max(min, math.min(max, vubarL))
	vubarR = math.max(min, math.min(max, vubarR))
end

local function updatevumeterEnvironment(dt)
	if not soundData then return end
	captions:setTime(currentTell)
	lines = {0,0,0,0}
	samples = {}
	samples = man.processSamples(false, soundData, lastTell, currentTell)
	scope.update(dt, samples)
	--rawSamples = samples
	if #samples > 0 then
		local volume = 1
		if music then
			volume = music:getVolume()
		end
		local referenceValue = 0.8
		vuL, vuR = getAbsoluteAverage(samples)
		vuL = vuL * volume
		vuR = vuR * volume
		dBvuL, dBvuR = linearToDecibels(vuL, referenceValue), linearToDecibels(vuR, referenceValue)
		normalizeddBvuL = normalizeDecibels(dBvuL)
		normalizeddBvuR = normalizeDecibels(dBvuR)
		updatevumeterBar(dt, normalizeddBvuL, normalizeddBvuR)
		changevuBarColor()
	end
	samples = man.scaleTable(
		samples,
		math.min(love.graphics.getWidth(),
		(love.graphics.getHeight()) / 2) - ( showVUMeter and (vumeter:getHeight() / 2) or 0)
		)
	samples = man.flipTable(samples, 1)
	samples = man.flipTable(samples, 0)
	samples = man.flipTable(samples, 1)
	samples = man.translateTable(samples, 1, love.graphics.getWidth() / 2)
	samples = man.translateTable(
		samples,
		0, (love.graphics.getHeight() / 2) + (showVUMeter and (vumeter:getHeight() / 2) or 0)
		)
	lines = samples
end

function love.update(dt)
	if music then
		if music:isPlaying() then
			if scopeMode == "XY" then
				currentTell = music:tell()
				updatevumeterEnvironment(dt)
				lastTell = music:tell()
			end
		end
		if love.keyboard.isDown("down") then
			changeMusicVolume(music, -50)
		end
		if love.keyboard.isDown("up") then
			changeMusicVolume(music,  50)
		end
	else
		--Let the samples bleed slowy
		table.remove(samples)
	end

	if recording then
		if defaultRecordingDevice then
			if defaultRecordingDevice:isRecording() then
				soundData = defaultRecordingDevice:getData()
				if soundData then
					lastTell = 0
					currentTell = soundData:getDuration() - 0.0001
					--print(lastTell, currentTell)
					--man.processSamples(false, soundData, lastTell, currentTell)
					updatevumeterEnvironment(dt)
				end
			else
				local d = defaultRecordingDevice
				d:start(8192, d:getSampleRate(), d:getBitDepth(), d:getChannelCount())
			end
		end
	else
		if defaultRecordingDevice then
			defaultRecordingDevice:stop()
		end
	end
end

local function getDistance(x1,y1,x2,y2)
	local dx = x2 - x1
	local dy = y2 - y1
	local distance = math.sqrt(dx * dx + dy * dy)

	local canvasWidth = love.graphics.getWidth()
	local canvasHeight = love.graphics.getHeight()

	local minDistance = 0.05 * math.min(canvasWidth, canvasHeight) -- 5% of canvas size
	local maxDistance = 0.3 * math.max(canvasWidth, canvasHeight) -- 90% of canvas size

	local normalizedDistance = (distance - minDistance) / (maxDistance - minDistance)

	normalizedDistance = math.max(0, math.min(1, normalizedDistance))

	local intensity = 1 - normalizedDistance

	intensity = 0.1 + intensity * 0.9

	return intensity
end

local function drawVideoIfAvailable()
	if not video then return end
	if not showVideo then return end
	if video:typeOf("Drawable") then
		love.graphics.push("all")
		love.graphics.origin()
		local size = math.min(
			love.graphics.getWidth() / video:getWidth(),
			love.graphics.getHeight() / video:getHeight()
			)
		love.graphics.translate(
			love.graphics.getWidth() / 2,
			love.graphics.getHeight() / 2 + (showVUMeter and (vumeter:getHeight() / 2) or 0))
		love.graphics.draw(video, 0, 0, 0, size, size, video:getWidth() / 2, video:getHeight() / 2)
		--love.graphics.draw(drawable, x, y, r, sx, sy, ox, oy, kx, ky)
		love.graphics.pop()

	end
end

local function oscilloscopeDrawRoutine()
	if #lines > 4  and #lines % 2 == 0 then
		--Here's a guy that did it properly not like me
		--Fake 'till you make it am i right?
		--https://richardandersson.net/?p=350
		if simulateRealCRTBeam then
			for i = 1, #lines, 2 do
				--Short distances will give time to the "BEAM"
				--to excite a non-existent phosphor layer
				local oscCenx = love.graphics.getWidth() / 2
				local oscCeny = (love.graphics.getHeight() / 2) + (showVUMeter and (vumeter:getHeight() / 2) or 0)
				local x1 = lines[i + 0] or oscCenx
				local y1 = lines[i + 1] or oscCeny
				local x2 = lines[i + 2] or x1 or oscCenx
				local y2 = lines[i + 3] or y1 or oscCeny
				local intensity = getDistance(x1, y1, x2, y2)
				love.graphics.setColor(0, intensity, 0, intensity / 2)
				love.graphics.line(x1, y1, x2, y2)
			end
		else
			love.graphics.setColor(0, 1, 0)
			love.graphics.line(lines)
		end
	end
end

function love.draw()
	if music or recording then
		if useShaders then
			shader(drawVideoIfAvailable)
			shader(oscilloscopeDrawRoutine)
		else
			drawVideoIfAvailable()
			oscilloscopeDrawRoutine()
		end
	else
		love.graphics.setColor(1,1,1)
		love.graphics.printf(
			welcomeMsg.."\n"..warningMsg.."\n"..dropfileMsg,
			0,
			love.graphics.getHeight() / 2, love.graphics.getWidth(), "center"
			)
	end
	--Beta feature: Too much flicker
	--scope.draw(love.graphics.getWidth() / 2, love.graphics.getHeight() / 2)
	--Please use it :crying_face:, took way to much time to do a pleasant vu meter
	if showVUMeter then
		--BG
		love.graphics.setColor(1,1,1)
		love.graphics.draw(vumeter, 0, 0, 0, love.graphics.getWidth() / vumeter:getWidth(), 1)

		--Mask 1
		love.graphics.setColor(0,0,0,0.8)
		love.graphics.rectangle("fill", normalizeddBvuL * love.graphics.getWidth(), 0, love.graphics.getWidth(),
			vumeter:getHeight() / 2
			)
		--Bar 1
		love.graphics.setColor(rgb(vuColorL))
		love.graphics.rectangle("fill", vubarL * love.graphics.getWidth(), 0, 10,  vumeter:getHeight() / 2)
		love.graphics.setColor(0,0,0,0.8)
		love.graphics.rectangle("line", vubarL * love.graphics.getWidth(), 0, 10,  vumeter:getHeight() / 2)
		--Mask 2
		love.graphics.setColor(0,0,0,0.8)
		love.graphics.rectangle("fill", normalizeddBvuR * love.graphics.getWidth(), vumeter:getHeight() / 2,
			love.graphics.getWidth(), vumeter:getHeight() / 2
			)
		--Bar 2
		love.graphics.setColor(rgb(vuColorR))
		love.graphics.rectangle("fill", vubarR * love.graphics.getWidth(), vumeter:getHeight() / 2, 10,
			vumeter:getHeight() / 2
		)
		love.graphics.setColor(0,0,0,0.8)
		love.graphics.rectangle("line", vubarR * love.graphics.getWidth(), vumeter:getHeight() / 2, 10,
			vumeter:getHeight() / 2
		)
		--Vu meter Text
		love.graphics.setColor(rgb("#AA33AA"))
		local formattedvuL = string.format("%.3f", dBvuL)
		local formattedvuR = string.format("%.3f", dBvuR)
		love.graphics.print(
			formattedvuL,
			(love.graphics.getWidth() / 2) - (love.graphics.getFont():getWidth(formattedvuL) / 2),
			vumeter:getHeight() * 0.25 - (love.graphics.getFont():getHeight() / 2)
		)
		love.graphics.print(
			formattedvuR,
			(love.graphics.getWidth() / 2) - (love.graphics.getFont():getWidth(formattedvuR) / 2),
			vumeter:getHeight() * 0.75 - (love.graphics.getFont():getHeight() / 2)
		)
	end
	if showCaptions then
		--Captions
		local text = captions:getText()
		love.graphics.setColor(1,1,1)
		local y = showVUMeter and (vumeter:getHeight() * 1.25 - (love.graphics.getFont():getHeight() / 2)) or 0
		--local x = (love.graphics.getWidth() / 2) - (love.graphics.getFont():getWidth(text) / 2)
		local x = showPerformance and love.graphics.getWidth() / 2 or 0
		x = math.floor(x)
		y = math.floor(y)
		love.graphics.printf(
			text,
			x, y,
			showPerformance and love.graphics.getWidth() / 2 or love.graphics.getWidth(), "center"
		)
	end
	if showPerformance then
		local stats = love.graphics.getStats()
		local text = "FPS: %d\nDrawCalls: %d\nSample troughput: %d\n"
		text = string.format(
			text,
			love.timer.getFPS(),
			stats.drawcalls or 0,
			#samples
			)
		text = (showVUMeter and "\n\n" or "") .. text
		love.graphics.setColor(0,0,0)
		love.graphics.print(text, 1, 1)
		love.graphics.setColor(1,1,1)
		love.graphics.print(text)
	end
end

local function releaseSources()
	if music then
		pcall(music.release, music)
	end
	if soundData then
		pcall(soundData.release, soundData)
	end
	if video then
		pcall(video.release, video)
	end
end

function love.filedropped(file)
	local lastDotIndex = file:getFilename():find("[^%.]+$")
	local extension = ""
	if lastDotIndex then
		extension = file:getFilename():sub(lastDotIndex):lower() or ""
		--print(extension)
	end
	if extension ~= "srt" then
		local res, msg = pcall(love.sound.newSoundData, file)
		if res then
			print(string.format("loading \"%s\" as sound source.", file:getFilename()))
			local filename = file:getFilename():match("[\\/]?([^\\/]+)$") or file:getFilename()
			love.window.setTitle(titleMsg .. ": " .. filename)
			if music then
				music:stop()
				if video then pcall(video.stop, video) end
			end
			releaseSources()
			soundData = love.sound.newSoundData(file)
			music = love.audio.newSource(soundData)
			local attempt, result = pcall(love.graphics.newVideo, file)
			if attempt then
				video = result
				music = video:getSource() or music
				print(string.format("loading \"%s\" as video source.", file:getFilename()))
			else
				video = false
			end
			music:play()
			if video then pcall(video.play, video) end
		else
			print(msg)
		end
	else
		print(string.format("Loading \"%s\" as captions.", file:getFilename()))
		local content = file:read() or ""
		captions = srt.new(content)
	end
end

function love.keypressed(key, _, _)
	--Actions / visuals
	if key == "f1" then showPerformance = not showPerformance end
	if key == "f2" then useShaders = not useShaders end
	if key == "f3" then showVUMeter = not showVUMeter end
	if key == "f4" then
		if love.keyboard.isDown("lshift", "rshift") then
			--Drop current captions
			captions = srt.new("")
		else
			showCaptions = not showCaptions
		end
	end
	if key == "f5" then love.event.quit("restart") end
	if key == "f6" then simulateRealCRTBeam = not simulateRealCRTBeam end
	if key == "f7" then queueSourcesInstead = not queueSourcesInstead end
	if key == "f8" then scopeMode = scopeMode == "XY" and "AB" or "XY" end
	if key == "f9" then
		recording = not recording
		if recording then
			defaultRecordingDevice = love.audio.getRecordingDevices()[1]
			if music then pcall(music.stop, music) end
			print("recording started")
			releaseSources()
			music = nil
		else
			print("recording stopped")
		end
	end
	if key == "f10" then showVideo = not showVideo end
	if key == "f11" then love.window.setFullscreen(not love.window.getFullscreen(), "desktop") end

	--Playback
	if music then
		if key == "space" then
			if music:isPlaying()
			then
				music:pause()
				if video then pcall(video.seek, video, music:tell()) pcall(video.pause, video) end
			else
				music:play()
				if video then pcall(video.seek, video, music:tell()) pcall(video.play, video) end
			end
		end

		if key == "left" then
			music:seek(math.max(0, music:tell() - 5)) lastTell = music:tell() currentTell = music:tell()
			if video then pcall(video.seek, video, music:tell()) end
		end

		if key == "right" then
			music:seek(math.min(music:getDuration(), music:tell() + 5)) lastTell = music:tell() currentTell = music:tell()
			if video then pcall(video.seek, video, music:tell()) end
		end

		if key == "," and love.keyboard.isDown("lshift", "rshift") then
			music:setPitch(math.max(music:getPitch() - 0.1, 0.1))
		end

		if key == "." and love.keyboard.isDown("lshift", "rshift") then
			music:setPitch(math.min(music:getPitch() + 0.1, math.huge))
		end

	end
	--print(key, scancode, isrepeat)
end