--[[
	WickerSprite
	by Omniwicker
	@ 2026
	
	API:
	
	sprite.new() -> Sprite
		Creates and returns a new Sprite object with default properties.
	
	sprite.Properties:
		Frame         [number]   -- Current frame index (read-only, managed internally)
		TotalFrames   [number]   -- Total number of frames in the animation
		Frames        [Vector2]  -- Grid layout of the spritesheet (columns, rows)
		FPS           [number]   -- Playback speed in frames per second (default: 10)
		Dimensions    [Vector2]  -- Full pixel dimensions of the spritesheet image
		TimePosition  [number]   -- Current playback time in seconds
		IsPlaying     [boolean]  -- Whether the animation is currently playing (read-only)
	
	Sprite:AttachToInstance(instance: Instance)
		Binds the sprite's lifetime to an Instance. The sprite will be
		automatically destroyed when the Instance is destroyed.
	
	Sprite:Add(instance: ImageLabel | ImageButton | (size: Vector2, offset: Vector2) -> ()) -> instance
		Registers an ImageLabel, ImageButton, or callback function to be updated
		each frame. Returns the passed instance. Callbacks receive (rectSize, rectOffset).
	
	Sprite:Remove(instance: ImageLabel | ImageButton | (size: Vector2, offset: Vector2) -> ()) -> instance
		Unregisters a previously added instance or callback from frame updates.
		Returns the passed instance.
	
	Sprite:Play()
		Starts playback. If already playing, resets TimePosition to 0.
		Automatically calls Clean() when the animation reaches its last frame.
	
	Sprite:Pause()
		Pauses playback, preserving TimePosition. Call Play() to resume.
	
	Sprite:Stop()
		Stops playback and resets TimePosition to 0. Does not clean Memory.
	
	Sprite:Clean()
		Stops playback and disconnects all connections in Memory.
		Does not remove scheduled updatables.
	
	Sprite:Destroy()
		Alias for Clean(). Stops playback and cleans up all resources.
--]]

--!strict

local runService = game:GetService("RunService")

local SPRITE_PROPERTIES = {
	Frame = 0,
	TotalFrames = 0,
	Frames = Vector2.zero,
	FPS = 10,
	Dimensions = Vector2.zero,

	ImageRectSize = Vector2.zero,
	ImageRectOffset = Vector2.zero,

	Memory = {},
	Scheduled = {},

	TimePosition = 0,
	IsPlaying = false
}

local WickerSprite = {}

local function deep_copy<T>(original: T): T
	if (type(original) ~= "table") then
		return original
	end
	local copy = {}
	for k, v in pairs(original) do
		copy[k] = deep_copy(v)
	end
	return setmetatable(copy, getmetatable(original :: any)) :: any
end

local function individual_clean(v: any)
	local mem_type = typeof(v)
	if (mem_type == "RBXScriptConnection") then
		v:Disconnect()
	elseif (mem_type == "Instance") then
		v:Destroy()
	elseif (mem_type == "table") then
		if (typeof(v.Destroy) == "function") then
			(v.Destroy :: (any) -> ())(v)
		elseif (typeof(v.destroy) == "function") then
			(v.destroy :: (any) -> ())(v)
		else
			for _, v2 in pairs(v) do
				individual_clean(v2)
			end
		end
	elseif (mem_type == "thread") and (coroutine.status(v) == "suspended") then
		task.cancel(v)
	elseif (mem_type == "function") then
		v()
	end
end

export type Sprite = typeof(setmetatable(SPRITE_PROPERTIES, {__index = WickerSprite}))
export type Updatable = ImageLabel|ImageButton|(size: Vector2, offset: Vector2) -> ()

function WickerSprite.new(): Sprite
	local new_sprite = deep_copy(SPRITE_PROPERTIES)
	setmetatable(new_sprite, {__index = WickerSprite})
	return new_sprite
end

function WickerSprite.AttachToInstance(self: Sprite, instance: Instance)
	table.insert(self.Memory, instance.Destroying:Connect(function()
		self:Destroy()
	end))
end

function WickerSprite.Add<T>(self: Sprite, instance: T & Updatable): T
	table.insert(self.Scheduled, instance)
	return instance
end

function WickerSprite.Remove<T>(self: Sprite, instance: T & Updatable): T
	for i = #self.Scheduled, 1, -1 do
		if (self.Scheduled[i] == instance) then
			table.remove(self.Scheduled, i)
			break
		end
	end
	return instance
end

function WickerSprite.Play(self: Sprite)
	if (self.IsPlaying) then
		self.TimePosition = 0
		return
	end

	self.IsPlaying = true

	table.insert(self.Memory, runService.Heartbeat:Connect(function(dt)
		self.TimePosition = math.clamp(self.TimePosition + dt, 0, self.TotalFrames * (1 / self.FPS))

		local frame = math.floor(self.TimePosition * self.FPS)
		self.Frame = frame

		local rectSize = self.Dimensions * Vector2.new(1 / self.Frames.X, 1 / self.Frames.Y)
		local rectOffset = Vector2.new(
			(frame % self.Frames.X) * rectSize.X,
			math.floor(frame / self.Frames.X) * rectSize.Y
		)

		self.ImageRectSize = rectSize
		self.ImageRectOffset = rectOffset

		for i = 1, #self.Scheduled do
			local v = self.Scheduled[i] :: any
			local schedule_type = typeof(v)
			if (schedule_type == "Instance") then
				if (v:IsA("ImageLabel")) or (v:IsA("ImageButton")) then
					v.ImageRectSize = rectSize
					v.ImageRectOffset = rectOffset
				end
			elseif (schedule_type == "function") then
				v(rectSize, rectOffset)
			end
		end

		if (frame >= self.TotalFrames) then
			self:Clean()
		end
	end))
end

function WickerSprite.Pause(self: Sprite)
	if (not self.IsPlaying) then
		return
	end
	self.IsPlaying = false
	for i = #self.Memory, 1, -1 do
		individual_clean(table.remove(self.Memory, i))
	end
end

function WickerSprite.Stop(self: Sprite)
	self:Pause()
	self.TimePosition = 0
end

function WickerSprite.Clean(self: Sprite)
	self.IsPlaying = false
	for i = #self.Memory, 1, -1 do
		individual_clean(table.remove(self.Memory, i))
	end
end

function WickerSprite.Destroy(self: Sprite)
	self:Clean()
end

return {
	new = WickerSprite.new
}
