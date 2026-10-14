--!strict
--!nolint LocalShadow

-- Other dependencies
local Signal = require("./././Signal/Signal")

local TierShift = {}
TierShift.__index = TierShift

function TierShift.new()
    local self = {}
    setmetatable(self, TierShift)

    self.initialized = false

    -- Events
    self.OnReset = Signal.new()
    self.OnUpgrade = Signal.new()
    self.OnDownGrade = Signal.new()
    self.OnUpdate = Signal.new()
    self.OnAdded = Signal.new()
    self.OnRemoved = Signal.new()
    
    -- Config
    self._CanUpgrade = false
    self._CanDownGrade = false
    self._CanReset = false

    self._MaxPointsForUpgrade = 99
    self._MaxPointsForDownGrade = 99

    -- DATA
    self.UsedPoints = 0
    self.AvailablePoints = 0
    self._table = {} :: ExpectedTable
    self._raw = {___s = {av = 0, us = 0}} :: ExpectedTableRaw
    return self
end

type TierShift = typeof(TierShift.new())
type ExpectedTable = {[string]: {min:number, max:number, curr:number}}
type ExpectedTableRaw = {
    [string]: number,
    ___s: packet
}
type packet = {av:number, us:number}

function TierShift:init(CanUpgrade:boolean?, CanDowngrade:boolean?, CanReset:boolean?, MaxPointsForUpgrade:number?, MaxPointsForDownGrade:number?)
    local self = self :: TierShift

    self._CanUpgrade = CanUpgrade or false
    self._CanDownGrade = CanDowngrade or false
    self._CanReset = CanReset or false
    self._MaxPointsForDownGrade = MaxPointsForDownGrade or self._MaxPointsForDownGrade
    self._MaxPointsForUpgrade = MaxPointsForUpgrade or self._MaxPointsForUpgrade

    self.initialized = true
end

function TierShift:UpdateMSinfo(AVAILABLEPOINTS:number, USEDPOINTS:number)
    local self = self :: TierShift
    assert(self.initialized == true, "TierShift is not initialized.")
    assert(typeof(USEDPOINTS) == "number", "UsedPoints must be a nr")
    assert(typeof(AVAILABLEPOINTS) == "number", "Available points must be a number")
    assert(USEDPOINTS >= 0 and USEDPOINTS <= AVAILABLEPOINTS, "Used points cannot exceed available points")
    assert(USEDPOINTS % 1 == 0, "must be an integer")
    assert(AVAILABLEPOINTS % 1 == 0, "must be an integer")

    self.AvailablePoints = AVAILABLEPOINTS
    self.UsedPoints = USEDPOINTS
    self:_syncPoints()
    self.OnUpdate:Fire()
    return true
end

-- Must be initialized first.
function TierShift:LoadRaw(data: ExpectedTableRaw): boolean
    local self = self :: TierShift
    assert(self.initialized == true, "TierShift is not initialized.")
    assert(typeof(data) == "table", "Loaded data must be a table!")

    -- 1. Validate everything before touching any state
    local points = data.___s 

    if typeof(points) ~= "table"
        or typeof(points.av) ~= "number"
        or typeof(points.us) ~= "number"
        or points.av % 1 ~= 0
        or points.us % 1 ~= 0
        or points.us < 0
        or points.us > points.av
    then
        return false
    end

    local values = {}
    local parsed = 0
    for id, value in pairs(data) do
        if id == "___s" then
            continue
        end

        local handle = self._table[id]
        if handle == nil then
            continue -- stat no longer exists, ignore it
        end

        if typeof(value) ~= "number" or value % 1 ~= 0
            or value < handle.min or value > handle.max then
            return false
        end

        values[id] = value
        parsed += 1    
    end
    
    if parsed == 0 then
        task.spawn(function()
            error(`0 Items were parsed from LoadRaw. Traceback:{debug.traceback()}`)
        end)
    end

    self.AvailablePoints = points.av
    self.UsedPoints = points.us

    for id, value in pairs(values) do
        self._table[id].curr = value
        self._raw[id] = value
    end

    self:_syncPoints()
    self.OnUpdate:Fire()
    return true
end

function TierShift:GivePoint(Value:number)
    local self = self :: TierShift
    assert(self.initialized == true, "TierShift is not initialized.")
    assert(typeof(Value) == "number", "Not a number was specified.")
    assert(Value >= 0 and Value == Value, "Invalid point value")
    assert(Value % 1 == 0, "must be an integer")

    self.AvailablePoints += Value
    self:_syncPoints()
    self.OnUpdate:Fire()
end 

function TierShift:Add(string:string, CurrentValueOr0:number?, min:number, max:number)
    local self = self :: TierShift
    
    assert(self.initialized == true, "TierShift is not initialized.")
    if CurrentValueOr0 then
        assert(typeof(CurrentValueOr0) == "number", "CurrentValueor0 must be a number!")  
        assert(CurrentValueOr0 >= 0, "Current Value must be higher or equal to 0")
        assert(CurrentValueOr0 >= min and CurrentValueOr0 <= max, "Initial value must be within the allowed range!")
        assert(CurrentValueOr0 % 1 == 0, "must be an integer")
    end
    assert(typeof(string) == "string", "Passed in argument has to be a string!")
    assert(self._table[string] == nil, "Already known identifier has been attempted to add.")
    assert(min <= max, "Minimum cannot exceed maximum!")
    assert(min % 1 == 0, "must be an integer")
    assert(max % 1 == 0, "must be an integer")
    assert(string ~= "___s", "___s is a blacklisted value!")

    self._table[string] = {min = min, max = max, curr = CurrentValueOr0 or min}
    self._raw[string] = self._table[string].curr

    self.OnAdded:Fire(string, (CurrentValueOr0 or min))
    self.OnUpdate:Fire()
    return true
end

-- Points are re awarded by: (current points invested - minimum points declaring offset as 0)
function TierShift:Remove(string:string, reAwardLostPoints:boolean?)
    local self = self :: TierShift

    assert(self.initialized == true, "TierShift is not initialized.")
    assert(typeof(string) == "string", "Passed in argument has to be a string!")
    assert(string ~= "___s", "___s is a blacklisted value!")

    if not self._table[string] then
        return false
    end

    if reAwardLostPoints then
        local handle = self._table[string]
        self.UsedPoints = math.max(0, self.UsedPoints - (handle.curr - handle.min))
        self:_syncPoints()
    end

    
    self._table[string] = nil
    self._raw[string] = nil

    self.OnRemoved:Fire(string)
    self.OnUpdate:Fire()
    return true
end

-- Generally recommended to put in short strings starting from AAA and ends to ZZZ and have processors handle them on initialization
function TierShift:Upgrade(id:string, value: number): boolean
        local self = self :: TierShift
        assert(self.initialized == true, "TierShift is not initialized.")
        assert(typeof(value) == "number", "Upgrade value must be a number!")
        assert(value > 0, "Upgrade value must be bigger than 0!")
        assert(typeof(id) == "string", "Passed in argument has to be a string!")
        assert(self._table[id] ~= nil, "Could not find identifier to upgrade")
        assert(self._raw[id] ~= nil, "raw table does not exist!")
        assert(value % 1 == 0, "must be an integer")
        
        if self._CanUpgrade == false then
            return false
        end
        
        local handle = self._table[id]
        if self._MaxPointsForUpgrade then
            if value > self._MaxPointsForUpgrade then
                return false
            end
        end

        if (value + handle.curr) > handle.max then
            return false
        end

        if value > self.AvailablePoints - self.UsedPoints then
            return false
        end

        handle.curr += value
        self._raw[id] = handle.curr

        self.UsedPoints += value
        self:_syncPoints()

        self.OnUpgrade:Fire(id, handle.curr)
        self.OnUpdate:Fire()
        return true
end

function TierShift:DownGrade(id:string, value:number): boolean
        local self = self :: TierShift
        assert(self.initialized == true, "TierShift is not initialized.")
        assert(typeof(value) == "number", "Upgrade value must be a number!")
        assert(value > 0, "Upgrade value must be bigger than 0!")
        assert(typeof(id) == "string", "Passed in argument has to be a string!")
        assert(self._raw[id] ~= nil, "raw table does not exist!")
        assert(self._table[id] ~= nil, "Could not find identifier to upgrade")
        assert(value % 1 == 0, "must be an integer")

        if self._CanDownGrade == false then
            return false
        end

        local handle = self._table[id]

        if self._MaxPointsForDownGrade then
            if value > self._MaxPointsForDownGrade then
                return false
            end
        end

        if (handle.curr - value) < handle.min then
            return false
        end

        if value > self.UsedPoints then
            return false
        end
        
        handle.curr -= value
        self._raw[id] = handle.curr

        self.UsedPoints -= value
        self:_syncPoints()

        self.OnDownGrade:Fire(id, handle.curr)
        self.OnUpdate:Fire()
        return true
end

function TierShift:Reset()
    local self = self :: TierShift
    assert(self.initialized == true, "TierShift is not initialized.")
    assert(self._CanReset == true, "TierShift Cannot reset this version!")

    for i, v in pairs(self._table) do
        v.curr = v.min or 0
        self._raw[i] = v.curr
    end

    self.UsedPoints = 0
    self:_syncPoints()

    for id, v in pairs(self._table) do
        self.OnReset:Fire(id, v.curr)
    end

    self.OnUpdate:Fire()

    return true
end

-- Only call once, store into datastore table and everytime an event fires call safe flag or auto save when changes detected
function TierShift:GetDataStoreDataReference()
    local self = self :: TierShift
    return self._raw
end

function TierShift:_syncPoints()
    self._raw.___s.av = self.AvailablePoints
    self._raw.___s.us = self.UsedPoints
end

return TierShift