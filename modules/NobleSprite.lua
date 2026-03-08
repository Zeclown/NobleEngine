---
-- An extension of Playdate's sprite object, incorporating `Noble.Animation` and other Noble Engine features.
-- Use this in place of `playdate.graphics.sprite` in most cases.
--
-- `NobleSprite` is a child class of `playdate.graphics.sprite`, so see the Playdate SDK documentation for additional methods and properties.
--
-- @classmod NobleSprite
--

NobleSprite = {}
class("NobleSprite").extends(Graphics.sprite)

--- Do not call an "init" method directly. Use `NobleSprite()` (see usage examples).
-- @string[opt] __view This can be: the path to an image or spritesheet image file, an image object (`Graphics.image`) or an animation object (`Noble.Animation`)
-- @bool[opt=false] __viewIsSpritesheet Set this to `true` to indicate that `__view` is a spritesheet. Will only be considered if `__view` is a string path to an image.
-- @bool[opt=false] __singleState If this sprite has just one animation, set this to true. It saves you from having to use Noble.Animation.addState()
-- @bool[opt=true] __singleStateLoop If using a single state animation, should it loop?
--
-- @usage
--	-- Provide a spritesheet image file to create a new `Noble.Animation` for a NobleSprite's view.
--	myNobleSprite = NobleSprite("path/to/spritesheet", true)
--
-- @usage
--	-- Provide an image file to create a new `Graphics.image` for a NobleSprite's view.
--	myNobleSprite = NobleSprite("path/to/image")
--
-- @usage
--	-- Use an existing `Noble.Animation` for a NobleSprite's view.
-- 	local myAnimation = Noble.Animation.new("path/to/spritesheet")
--  myAnimation:addState("default", 1, animation.imageTable:getLength(), nil, true)
--	myNobleSprite = NobleSprite(myAnimation)
--
-- @usage
--	-- Use an existing `Graphics.image` object for a NobleSprite's view.
--  local myImage = Graphics.image.new("path/to/image")
--	myNobleSprite = NobleSprite(myImage)
--
-- @usage
--	-- Extending NobleSprite.
--
--	-- MyCustomSprite.lua
--	MyCustomSprite = {}
--	class("MyCustomSprite").extends(NobleSprite)
--
--	function MyCustomSprite:init(__x, __y, __anotherFunArgument)
--		MyCustomSprite.super.init(self, "path/to/spritesheet", true)
--		-- Etc. etc.
--	end
--
--	-- MyNobleScene.lua
--	myNobleSprite = MyCustomSprite(100, 100, "Fun!")
--
-- @see Noble.Animation:addState
-- @see Noble.Animation.new
--
function NobleSprite:init(__view, __viewIsSpritesheet, __singleState, __singleStateLoop)
	-- Initialize parenting fields before super.init because Playdate's sprite init calls
	-- moveTo internally, which triggers our override and reads these fields.
	self._parent = nil
	self._children = {}
	self._localX = 0
	self._localY = 0
	self._localRotation = 0
	self._localScaleX = 1
	self._localScaleY = 1
	self._localZIndex = 0

	NobleSprite.super.init(self)
	self.isNobleSprite = true -- This is important so other methods don't confuse this for a playdate.graphics.sprite. DO NOT modify this value at runtime.

	if (__view ~= nil) then

		-- __view is the path to an image or spritesheet file.
		if (type(__view) == "string") then
			self.animated = __viewIsSpritesheet -- NO NOT modify self.animated at runtime.

			if (__viewIsSpritesheet == true) then
				-- Create a new Noble.Animation object.

				--- The animation for this NobleSprite.
				-- @see Noble.Animation.new
				self.animation = Noble.Animation.new(__view)

				local singleStateLoop = true
				if (__singleStateLoop ~= nil) then singleStateLoop = __singleStateLoop end

				if (__singleState == true) then
					self.animation:addState("default", 1, self.animation.imageTable:getLength(), nil, singleStateLoop)
				end

			else
				-- Create a new Graphics.image object.
				self:setImage(Graphics.image.new(__view))
			end

		-- __view is an existing Graphics.image object.
		elseif (type(__view) == "userdata") then
			self.animated = false
			self:setImage(__view)

		-- __view is an existing Noble.Animation object.
		elseif (type(__view) == "table") then
			self.animated = true
			self.animation = __view
		end

	end

end

function NobleSprite:draw()
	if (self.animation ~= nil) then
		self.animation:draw()
		self:markDirty()
	end
end

-- =====================================================================
-- Parenting
-- =====================================================================

--- Internal: compute and apply this sprite's world transform from its parent's world transform and its own local transform.
-- Propagates recursively to all descendants.
function NobleSprite:_syncWorldTransform()
	local p = self._parent
	if p == nil then return end

	local pw, ph   = p:getPosition()
	local pr       = p:getRotation()
	local psx, psy = p:getScale()

	-- Rotate and scale the local offset by the parent's world transform.
	local rad   = math.rad(pr)
	local cos_r = math.cos(rad)
	local sin_r = math.sin(rad)
	local scaledX = self._localX * psx
	local scaledY = self._localY * psy

	local worldX   = pw + scaledX * cos_r - scaledY * sin_r
	local worldY   = ph + scaledX * sin_r + scaledY * cos_r
	local worldRot = pr + self._localRotation
	local worldSX  = psx * self._localScaleX
	local worldSY  = psy * self._localScaleY

	-- Apply directly to Playdate (bypassing our overrides so children are not triggered
	-- three times — we cascade once below instead).
	NobleSprite.super.moveTo(self, worldX, worldY)
	NobleSprite.super.setRotation(self, worldRot)
	NobleSprite.super.setScale(self, worldSX, worldSY)
	NobleSprite.super.setZIndex(self, p:getZIndex() + self._localZIndex)

	-- Propagate once to direct children; they recurse to their own children.
	for i = 1, #self._children do
		self._children[i]:_syncWorldTransform()
	end
end

--- Internal: recursively register all unregistered children with the current scene.
function NobleSprite:_addChildrenToScene()
	local scene = Noble.currentScene()
	for i = 1, #self._children do
		local child = self._children[i]
		if table.indexOfElement(scene.sprites, child) == nil then
			scene:addSprite(child)
		end
		child:_addChildrenToScene()
	end
end

--- Override `moveTo` to keep local transform in sync and propagate to children.
-- Behaviour for sprites without a parent is identical to the original Playdate API.
-- For parented sprites, call `setLocalPosition` instead when you want to move relative to the parent.
function NobleSprite:moveTo(__x, __y)
	NobleSprite.super.moveTo(self, __x, __y)

	if self._parent == nil then
		-- No parent: local == world.
		self._localX = __x
		self._localY = __y
	end
	-- When called directly on a parented sprite the Playdate position is updated but local
	-- transform stays unchanged; it snaps back to its local-derived world pos next time the
	-- parent moves. Use setLocalPosition() to persistently reposition a parented sprite.

	for i = 1, #self._children do
		self._children[i]:_syncWorldTransform()
	end
end

--- Override `setRotation` to keep local transform in sync and propagate to children.
-- Behaviour for sprites without a parent is identical to the original Playdate API.
function NobleSprite:setRotation(__angle)
	NobleSprite.super.setRotation(self, __angle)

	if self._parent == nil then
		self._localRotation = __angle
	end

	for i = 1, #self._children do
		self._children[i]:_syncWorldTransform()
	end
end

--- Override `setScale` to keep local transform in sync and propagate to children.
-- Behaviour for sprites without a parent is identical to the original Playdate API.
function NobleSprite:setScale(__scaleX, __scaleY)
	local sy = __scaleY or __scaleX
	NobleSprite.super.setScale(self, __scaleX, sy)

	if self._parent == nil then
		self._localScaleX = __scaleX
		self._localScaleY = sy
	end

	for i = 1, #self._children do
		self._children[i]:_syncWorldTransform()
	end
end

--- Internal: returns the min and max world Z-index across this sprite and all its descendants.
function NobleSprite:_getSubtreeZRange()
	local z = self:getZIndex()
	local minZ, maxZ = z, z
	for i = 1, #self._children do
		local childMin, childMax = self._children[i]:_getSubtreeZRange()
		if childMin < minZ then minZ = childMin end
		if childMax > maxZ then maxZ = childMax end
	end
	return minZ, maxZ
end

--- Override `setZIndex` to keep local Z-index in sync and propagate to children.
-- Behaviour for sprites without a parent is identical to the original Playdate API.
-- Note: if two sibling groups overlap in Z-range (because a group's subtree is thicker than
-- the gap between their parent Z-indices), layers will interleave. Space parent Z-indices by
-- at least the maximum depth of their subtrees to avoid this.
function NobleSprite:setZIndex(__z)
	NobleSprite.super.setZIndex(self, __z)

	if self._parent == nil then
		self._localZIndex = __z
	end

	for i = 1, #self._children do
		self._children[i]:_syncWorldTransform()
	end
end

--- Add a child sprite to this sprite. The child's current world position is preserved and
-- converted into a local-space offset relative to this parent. If the child already has a
-- parent it is detached first. If the child is not yet in the scene it will be registered.
-- @tparam NobleSprite __child The sprite to attach.
-- @bool[opt=true] __inFront When true (default) the child is placed just above the parent's
-- entire subtree. When false it is placed just below, e.g. for shadows or glows.
function NobleSprite:addChild(__child, __inFront)
	assert(__child ~= nil, "NobleSprite:addChild() — child cannot be nil.")
	assert(__child ~= self, "NobleSprite:addChild() — a sprite cannot be its own parent.")

	-- Detach from existing parent without triggering _syncWorldTransform.
	if __child._parent ~= nil then
		__child._parent:removeChild(__child)
	end

	__child._parent = self
	table.insert(self._children, __child)

	-- Derive initial local transform from the child's current world transform and this
	-- sprite's world transform so the child keeps its apparent screen position.
	local cw, ch   = __child:getPosition()
	local cr        = __child:getRotation()
	local csx, csy  = __child:getScale()
	local pw, ph    = self:getPosition()
	local pr        = self:getRotation()
	local psx, psy  = self:getScale()

	local dx  = cw - pw
	local dy  = ch - ph
	local rad = math.rad(-pr)
	local cos_r = math.cos(rad)
	local sin_r = math.sin(rad)

	__child._localX        = (psx ~= 0) and ((dx * cos_r - dy * sin_r) / psx) or dx
	__child._localY        = (psy ~= 0) and ((dx * sin_r + dy * cos_r) / psy) or dy
	__child._localRotation = cr - pr
	__child._localScaleX   = (psx ~= 0) and (csx / psx) or csx
	__child._localScaleY   = (psy ~= 0) and (csy / psy) or csy

	-- Place the child just outside the parent's current subtree Z-range. Computed before
	-- insertion so the range reflects only the existing members.
	local inFront = __inFront ~= false  -- default true
	local minZ, maxZ = self:_getSubtreeZRange()
	if inFront then
		__child._localZIndex = (maxZ + 1) - self:getZIndex()
	else
		__child._localZIndex = (minZ - 1) - self:getZIndex()
	end

	-- Register with the scene if not already there.
	local scene = Noble.currentScene()
	if scene ~= nil and table.indexOfElement(scene.sprites, __child) == nil then
		scene:addSprite(__child)
	end

	-- Recursively register any of the child's own children.
	__child:_addChildrenToScene()

	-- Apply the computed world transform immediately.
	__child:_syncWorldTransform()
end

--- Remove a child sprite from this sprite. The child retains its current world position as its
-- new absolute transform and is kept in the scene.
-- @tparam NobleSprite __child The child sprite to detach.
function NobleSprite:removeChild(__child)
	for i = 1, #self._children do
		if self._children[i] == __child then
			table.remove(self._children, i)
			break
		end
	end

	__child._parent = nil

	-- Promote current world transform to local so the sprite stays where it is.
	local wx, wy    = __child:getPosition()
	local wr        = __child:getRotation()
	local wsx, wsy  = __child:getScale()
	__child._localX        = wx
	__child._localY        = wy
	__child._localRotation = wr
	__child._localScaleX   = wsx
	__child._localScaleY   = wsy
	__child._localZIndex   = __child:getZIndex()
end

--- Attach this sprite to a parent, or pass `nil` to detach from the current parent.
-- @tparam[opt] NobleSprite __parent The new parent, or nil to detach.
function NobleSprite:setParent(__parent)
	if __parent ~= nil then
		__parent:addChild(self)
	elseif self._parent ~= nil then
		self._parent:removeChild(self)
	end
end

--- Returns the parent sprite, or nil if this sprite has no parent.
function NobleSprite:getParent()
	return self._parent
end

--- Returns the table of direct children of this sprite.
function NobleSprite:getChildren()
	return self._children
end

-- ── Local-space transform setters / getters ─────────────────────────

--- Set this sprite's position relative to its parent. Has no effect on root sprites (use `moveTo` instead).
function NobleSprite:setLocalPosition(__x, __y)
	self._localX = __x
	self._localY = __y
	self:_syncWorldTransform()
end

--- Returns the sprite's local x and y position relative to its parent.
function NobleSprite:getLocalPosition()
	return self._localX, self._localY
end

--- Set local x only.
function NobleSprite:setLocalX(__x)
	self._localX = __x
	self:_syncWorldTransform()
end

--- Returns local x.
function NobleSprite:getLocalX()
	return self._localX
end

--- Set local y only.
function NobleSprite:setLocalY(__y)
	self._localY = __y
	self:_syncWorldTransform()
end

--- Returns local y.
function NobleSprite:getLocalY()
	return self._localY
end

--- Set rotation relative to parent (degrees).
function NobleSprite:setLocalRotation(__angle)
	self._localRotation = __angle
	self:_syncWorldTransform()
end

--- Returns rotation relative to parent (degrees).
function NobleSprite:getLocalRotation()
	return self._localRotation
end

--- Set scale relative to parent.
function NobleSprite:setLocalScale(__scaleX, __scaleY)
	self._localScaleX = __scaleX
	self._localScaleY = __scaleY or __scaleX
	self:_syncWorldTransform()
end

--- Returns local scale as xScale, yScale.
function NobleSprite:getLocalScale()
	return self._localScaleX, self._localScaleY
end

--- Set Z-index relative to parent. Positive values draw above the parent, negative below.
-- For unparented sprites, use `setZIndex` instead.
function NobleSprite:setLocalZIndex(__z)
	self._localZIndex = __z
	self:_syncWorldTransform()
end

--- Returns the Z-index offset relative to the parent.
function NobleSprite:getLocalZIndex()
	return self._localZIndex
end

-- ─────────────────────────────────────────────────────────────────────

--- This will enable the update loop for this NobleSprite, which also causes its Noble.Animation to play.
function NobleSprite:play()
	self:setUpdatesEnabled(true)
end

--- This will disable the update loop for this NobleSprite, which also causes its Noble.Animation to pause.
function NobleSprite:pause()
	self:setUpdatesEnabled(false)
end

--- This will disable the update loop for this NobleSprite, and also reset its Noble.Animation (if it exists) to the first frame of its current state.
function NobleSprite:stop()
	self:setUpdatesEnabled(false)
	if (self.animation ~= nil) then
		self.animation.currentFrame = self.animation.current.startFrame
	end
end

--- Use this to add this NobleSprite to your scene. This replaces `playdate.graphics.sprite:add()` to allow NobleSprites to be tracked by the current NobleScene.
-- Any children attached to this sprite that are not yet in the scene are also registered automatically.
--
-- To add a `playdate.graphics.sprite` to a scene, use `NobleScene:addSprite(__sprite)`.
-- @see NobleScene:addSprite
function NobleSprite:add(__x, __y)
	local x = __x or 0
	local y = __y or 0
	self:moveTo(x, y)
	Noble.currentScene():addSprite(self)
	self:_addChildrenToScene()
end

function NobleSprite:superAdd()
	NobleSprite.super.add(self)
end

--- Use this to remove this NobleSprite from your scene. This replaces `playdate.graphics.sprite:remove()` to allow NobleSprites to be tracked by the current NobleScene.
-- Removing a sprite also removes all of its children recursively, and detaches it from its parent.
--
-- To remove a `playdate.graphics.sprite` from a scene, use `NobleScene:removeSprite(__sprite)`.
-- @see NobleScene:removeSprite
function NobleSprite:remove()
	-- Detach from parent without triggering a local-transform recalculation.
	if self._parent ~= nil then
		local siblings = self._parent._children
		for i = 1, #siblings do
			if siblings[i] == self then
				table.remove(siblings, i)
				break
			end
		end
		self._parent = nil
	end

	-- Snapshot the children table then clear it so recursive calls don't see stale entries.
	local childrenSnapshot = self._children
	self._children = {}
	for i = 1, #childrenSnapshot do
		childrenSnapshot[i]:remove()
	end

	if (self.animation ~= nil) then
		self:stop()
		self:setUpdatesEnabled(true)	-- reset!
	end
	Noble.currentScene():removeSprite(self)
end

function NobleSprite:superRemove()
	NobleSprite.super.remove(self)
end