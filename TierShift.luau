--!strict
--!nolint LocalShadow

local TierShift = {}
TierShift.__index = TierShift

function TierShift.new()
    local self = {}
    setmetatable(self, TierShift)

    self.initialized = false

    -- Events
    self.OnReset = nil
    self.OnUpgrade = nil
    self.OnDownGrade = nil
    self.OnUpdate = nil
    self.OnAdded = nil
    self.OnRemoved = nil
    
    -- Config
    self._CanUpgrade = false
    self._CanDownGrade = false
    self._CanReset = false

    self._MaxPointsForUpgrade = 99
    self._MaxPointsForDownGrade = 99

    -- DATA
    self.UsedPoints = 0
    self.AvailablePoints = 0
    self._table = {} :: Expectedtable

    return self
end

type TierShift = typeof(TierShift.new())
type Expectedtable = {[string]: {min:number, max:number, curr:number}}

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

        self.AvailablePoints = AVAILABLEPOINTS
        self.UsedPoints = USEDPOINTS
end

function TierShift:GivePoint(Value:number)
    local self = self :: TierShift
    assert(self.initialized == true, "TierShift is not initialized.")
    assert(typeof(Value) == "number", "Not a number was specified.")
    self.AvailablePoints += Value
end 

function TierShift:Add(string:string, CurrentValueOr0:number?, min:number, max:number)
    local self = self :: TierShift
    
    assert(self.initialized == true, "TierShift is not initialized.")
    assert(typeof(CurrentValueOr0) == "number", "CurrentValueor0 must be a number!")
    assert(CurrentValueOr0 >= 0, "Current Value must be higher or equal to 0")
    assert(typeof(string) == "string", "Passed in argument has to be a string!")

    assert(self._table[string] == nil, "Already known identifier has been attempted to add.")

    assert(min <= max, "Minimum cannot exceed maximum!")
    assert(CurrentValueOr0 >= min and CurrentValueOr0 <= max, "Initial value must be within the allowed range!")

    self._table[string] = {min = min, max = max, curr = CurrentValueOr0 or min}
    return true
end

function TierShift:Remove(string:string)
    local self = self :: TierShift

    assert(self.initialized == true, "TierShift is not initialized.")
    assert(typeof(string) == "string", "Passed in argument has to be a string!")
    
    self._table[string] = nil

    return true
end

function TierShift:Upgrade(id:string, value: number): boolean
        local self = self :: TierShift
        assert(self.initialized == true, "TierShift is not initialized.")
        assert(typeof(value) == "number", "Upgrade value must be a number!")
        assert(value > 0, "Upgrade value must be bigger than 0!")
        assert(typeof(id) == "string", "Passed in argument has to be a string!")
        assert(self._table[id] ~= nil, "Could not find identifier to upgrade")

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
        self.UsedPoints += value
        return true
end

function TierShift:DownGrade(id:string, value:number): boolean
        local self = self :: TierShift
        assert(self.initialized == true, "TierShift is not initialized.")
        assert(typeof(value) == "number", "Upgrade value must be a number!")
        assert(value > 0, "Upgrade value must be bigger than 0!")
        assert(typeof(id) == "string", "Passed in argument has to be a string!")
        assert(self._table[id] ~= nil, "Could not find identifier to upgrade")

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
        self.UsedPoints -= value

        return true
end

function TierShift:Reset()
        local self = self :: TierShift
        assert(self.initialized == true, "TierShift is not initialized.")
        assert(self._CanReset == true, "TierShift Cannot reset this version!")
        
        self.UsedPoints = 0

        for i, v in pairs(self._table) do
            v.curr = v.min
        end
end

return TierShift