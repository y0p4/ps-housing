---@diagnostic disable: duplicate-set-field
Property = {
	property_id = nil,
	propertyData = nil,

	shellData = nil,
	inShell = false,
	shellObj = nil,

	has_access = false,
	owner = false,

	storageTarget = nil,
	clothingTarget = nil,
	furnitureObjs = {},

	garageZone = nil,
	doorbellPool = {},

	GetDoorCoords = function(self)
		local coords = nil

		if self.propertyData.apartment then
			local apartment = self.propertyData.apartment
			coords = Config.Apartments[apartment].door
		else
			coords = self.propertyData.door_data
		end

		return coords
	end,

	CreateShell = function(self)
		local ped = cache.ped

		local coords = self:GetDoorCoords()

		local modelHash = self.shellData.hash
		RequestModel(modelHash)
		while not HasModelLoaded(modelHash) do
			Wait(0)
		end

		self.shellObj = CreateObject(modelHash, coords.x, coords.y, coords.z - 50.0, false, false, false)

		SetModelAsNoLongerNeeded(modelHash)
		FreezeEntityPosition(self.shellObj, true)

		local doorOffset = self.shellData.doorOffset
		local offset = GetOffsetFromEntityInWorldCoords(self.shellObj, doorOffset.x, doorOffset.y, doorOffset.z)
		self:RegisterDoorZone(offset)

		SetEntityCoordsNoOffset(ped, offset.x, offset.y, offset.z, false, false, true)
		SetEntityHeading(ped, self.shellData.doorOffset.heading)

		DoScreenFadeIn(250)
	end,

	RegisterDoorZone = function(self, offset)

		local function leave()
			self:LeaveShell()
		end

		local function checkDoor()
			self:OpenDoorbellMenu()
		end

		if Config.Target == "qb" then
			exports["qb-target"]:AddBoxZone(
				"shellExit",
				vector3(offset.x, offset.y, offset.z),
				1.0,
				self.shellData.doorOffset.width,
				{
					name = "shellExit",
					heading = self.shellData.doorOffset.heading,
					debugPoly = Config.DebugPoly,
					minZ = offset.z - 2.0,
					maxZ = offset.z + 1.0,
				},
				{
					options = {
						{
							label = "Leave Property",
							action = leave,
						},
						{
							label = "Check Door",
							action = checkDoor,
						},
					},
				}
			)
		elseif Config.Target == "ox" then
			exports.ox_target:addBoxZone({
				id = "shellExit",
				coords = vector3(offset.x, offset.y, offset.z),
				size = vector3(1.0, self.shellData.doorOffset.width, 3.0),
				rotation = self.shellData.doorOffset.heading,
				debug = Config.DebugZones,
				options = {
					{
						name = "leave",
						label = "Leave Property",
						onSelect = leave,
					},
					{
						name = "doorbell",
						label = "Check Door",
						onSelect = checkDoor,
					},
				},
			})
		end
	end,

	RegisterPropertyEntrance = function(self)
		local door_data = self.propertyData.door_data
		local targetName = string.format("%s_%s", self.propertyData.label, self.property_id)
		local label = nil

		local function enter()
			TriggerServerEvent("ps-housing:server:enterProperty", self.property_id)
		end

		if Config.Target == "qb" then
			exports["qb-target"]:AddBoxZone(
				targetName,
				vector3(door_data.x, door_data.y, door_data.z),
				door_data.length,
				door_data.width,
				{
					name = targetName,
					heading = door_data.h,
					debugPoly = Config.DebugZones,
					minZ = door_data.z - 1.0,
					maxZ = door_data.z + 2.0,
				},
				{
					options = {
						{
							label = (self.has_access or self.owner) and "Enter Property" or "Ring Doorbell",
							action = enter,
						},
					},
				}
			)
		elseif Config.Target == "ox" then
			exports.ox_target:addBoxZone({
				id = targetName,
				coords = vector3(door_data.x, door_data.y, door_data.z),
				size = vector3(door_data.length, door_data.width, 3.0),
				rotation = door_data.h,
				debug = Config.DebugZones,
				options = {
					{
						name = "enter",
						label = label,
						onSelect = enter,
					},
				},
			})
		end
	end,

	-- QBCORE Did house garages the shittiest way possible so I did my own version of it. Might not be a very framework friendly decision but fuck qb
	RegisterGarageZone = function(self)
		if not self.propertyData.garage_data.x then
			return
		end

		local garageData = self.propertyData.garage_data
		local garageName = string.format("property-%s-garage")

		self.garageZone = BoxZone:Create(vector3(garageData.x, garageData.y, garageData.z), garageData.length, garageData.width, {
				name = garageName,
				debugPoly = Config.DebugPoly,
			})

		local function handleGarage()
			TriggerEvent("ps-housing:client:handleGarage", garageName)
		end

		self.garageZone:onPlayerInOut(function(isPointInside, point)
			if isPointInside then
				exports["qb-core"]:DrawText(self.propertyData.label .. " Garage", "left")
				lib.showTextUI(self.propertyData.label .. " Garage")
				lib.addRadialItem({
					id = garageName,
					icon = "warehouse",
					label = cache.vehicle and "Store Vehicle" or "Open Property Garage",
					onSelect = handleGarage,
				})
			else
				lib.hideTextUI()
				lib.removeRadialItem(garageName)
			end
		end)
	end,

	EnterShell = function(self)
		DoScreenFadeOut(250)
		self.inShell = true
		self.shellData = Config.Shells[self.propertyData.shell]

		self:CreateShell()
		self:LoadFurnitures()

		if not self.owner and not Config.AccessCanEditFurniture then
			return
		end

		SendNUIMessage({
			action = "setOwnedItems",
			data = self.propertyData.furnitures,
		})

		lib.addRadialItem({
			id = "furniture_menu",
			icon = "house",
			label = "Furniture Menu",
			onSelect = function()
				Modeler:OpenMenu()
			end,
		})
	end,

	LeaveShell = function(self)
		if not self.inShell then
			return
		end

		DoScreenFadeOut(250)

		local coords = self:GetDoorCoords()
		SetEntityCoordsNoOffset(cache.ped, coords.x, coords.y, coords.z, false, false, true)

		if Config.Target == "qb" then
			exports["qb-target"]:RemoveZone("shellExit")
		elseif Config.Target == "ox" then
			exports.ox_target:removeZone("shellExit")
		end

		lib.removeRadialItem("furniture_menu")

		SendNUIMessage({
			action = "setOwnedItems",
			data = {},
		})

		if self.garageZone then
			self.garageZone:destroy()
			self.garageZone = nil
		end

		TriggerServerEvent("ps-housing:server:leaveProperty", self.property_id)

		self:UnloadFurnitures()
		DeleteObject(self.shellObj)

		self.inShell = false
		self.shellObj = nil
		self.shellData = nil
		self.doorbellPool = {}

		DoScreenFadeIn(250)
	end,

	ManageAccesMenu = function(self)
		if not self.owner then
			return
		end

		local id = "property-" .. self.property_id .. "-access"
		local menu = {
			id = id,
			title = "Manage Access",
			options = {},
		}

		-- only stores names and citizenids in a table so if their offline you can still remove them
		local playersWithAccess = lib.callback.await("ps-housing:cb:getPlayersWithAccess", self.property_id)
		for k, v in pairs(playersWithAccess) do
			table.insert(menu.options, {
				title = v.name,
				description = "Remove Access",
				onSelect = function()
					TriggerServerEvent("ps-housing:server:removeAccess", self.property_id, v.citizenid)
				end,
			})
		end
	end,

	OpenDoorbellMenu = function(self)
		if not self.doorbellPool then
			lib.notify({ title = "No one is at the door", type = "error" })
			return
		end

		local id = string.format("property-%s-doorbell", self.property_id)
		local menu = {
			id = id,
			title = "People at the door",
			options = {},
		}

		for k, v in pairs(self.doorbellPool) do
			table.insert(menu.options, {
				title = GetPlayerName(k),
				onSelect = function()
					TriggerServerEvent(
						"ps-housing:server:doorbellAnswer",
						{ targetSrc = k, property_id = self.property_id }
					)
				end,
			})
		end

		lib.registerContext(menu)
		lib.showContext(id)
	end,

	LoadFurnitures = function(self)
		for i = 1, #self.propertyData.furnitures do
			local v = self.propertyData.furnitures[i]
			local coords = GetOffsetFromEntityInWorldCoords(self.shellObj, v.position.x, v.position.y, v.position.z)
			local hash = v.object

			while not HasModelLoaded(hash) do
				Wait(0)
			end

			local object = CreateObject(hash, coords.x, coords.y, coords.z, false, true, false)
			SetModelAsNoLongerNeeded(hash)
			SetEntityRotation(object, v.rotation.x, v.rotation.y, v.rotation.z, 2, true)
			FreezeEntityPosition(object, true)


			-- For the prerequisites
			if v.type == "storage" then
				self.storageTarget = object
				local stash = string.format("%s-property", self.property_id) -- if you ever change this you will fuck shit up from previous stash db

				local function openStash()
					TriggerServerEvent("inventory:server:OpenInventory", "stash", stash)
					TriggerEvent("inventory:client:SetCurrentStash", stash)
				end

				if Config.Target == "qb" then
					exports["qb-target"]:AddTargetEntity(object, {
						options = {
							label = "Storage",
							type = "client",
							action = openStash,
						},
					})
				elseif Config.Target == "ox" then
					exports.ox_target:addLocalEntity(object, {
						{
							name = "storage",
							label = "Storage",
							onSelect = openStash,
						},
					})
				end
			elseif v.type == "clothing" then
				self.clothingTarget = object

				if Config.Target == "qb" then
					exports["qb-target"]:AddTargetEntity(object, {
						options = {
							label = "Clothing",
							type = "client",
							event = "qb-clothing:client:openOutfitMenu",
						},
					})
				elseif Config.Target == "ox" then
					exports.ox_target:addLocalEntity(object, {
						{
							name = "clothing",
							label = "Clothing",
							event = "qb-clothing:client:openOutfitMenu",
						},
					})
				end
			end

			self.furnitureObjs[#self.furnitureObjs + 1] = object
		end
	end,

	UnloadFurnitures = function(self)
		for i = 1, #self.furnitureObjs do
			local object = self.furnitureObjs[i]

			if clothingTarget == object or storageTarget == object then
				if Config.Target == "qb" then
					exports["qb-target"]:RemoveTargetEntity(object)
				elseif Config.Target == "ox" then
					exports.ox_target:removeLocalEntity(object)
				end

				if clothingTarget == object then
					clothingTarget = nil
				elseif storageTarget == object then
					storageTarget = nil
				end
			end

			DeleteObject(object)
		end

		self.furnitureObjs = {}
	end,

	DeleteProperty = function(self)
		local targetName = string.format("%s_%s", self.propertyData.label, self.property_id)
		if Config.Target == "qb" then
			exports["qb-target"]:RemoveZone(targetName)
		elseif Config.Target == "ox" then
			exports.ox_target:removeZone(targetName)
		end

		if self.inShell then
			self:LeaveShell()
		end

		if self.propertyData.apartment then
			ApartmentsTable[self.propertyData.apartment]:RemoveProperty()
		end
	end,
}

function Property:new(propertyData)
	local obj = {}

	obj.property_id = propertyData.property_id
	obj.propertyData = propertyData

	local Player = QBCore.Functions.GetPlayerData()
	local citizenid = Player.citizenid

	local owner = false
	if propertyData.owner == citizenid then
		owner = true
	end
	obj.owner = owner

	local has_access = false
	for i = 1, #propertyData.has_access do
		if propertyData.has_access[i] == citizenid then
			has_access = true
			break
		end
	end
	obj.has_access = has_access

	setmetatable(obj, self)
	self.__index = self

	if propertyData.apartment ~= nil then
		local apartmentName = propertyData.apartment
		local apartment = ApartmentsTable[apartmentName]

		if not apartment and Config.Apartments[apartmentName] then
			ApartmentsTable[apartmentName] = Apartment:new(Config.Apartments[apartmentName])
			return
		elseif not apartment then
			print(apartmentName .. " not found in Config")
			return
		end

		apartment:AddProperty(propertyData.property_id)
	else
		obj:RegisterPropertyEntrance()
		obj:RegisterGarageZone()
	end

	return obj
end

RegisterNetEvent("ps-housing:client:enterProperty", function(property_id)
	local property = PropertiesTable[property_id]
	property:EnterShell()
end)

RegisterNetEvent("ps-housing:client:updateDoorbellPool", function(property_id, data)
	local property = PropertiesTable[property_id]
	property.doorbellPool = data
end)

-- seperate event so the player doesnt have to leave the shell to update the furniture
RegisterNetEvent("ps-housing:client:updateFurniture", function(propertyData)
	local property_id = propertyData.property_id
	local property = PropertiesTable[property_id]
	property.propertyData.furnitures = propertyData.furnitures
	property:UnloadFurnitures()
	property:LoadFurnitures()
end)

RegisterNetEvent("ps-housing:client:updateProperty", function(propertyData)
	local property_id = propertyData.property_id
	local property = PropertiesTable[property_id]
	property.propertyData = propertyData

	if property.inShell then
		property:LeaveShell()
	end

	if propertyData.apartment ~= nil then
		local apartment = ApartmentsTable[propertyData.apartment]
		apartment:RemoveProperty(property_id)
	end

	property:DeleteProperty()
	property = nil
	PropertiesTable[property_id] = Property:new(propertyData)
end)
