DebuffFilter = LibStub("AceAddon-3.0"):NewAddon("DebuffFilter", "AceConsole-3.0", "AceEvent-3.0")
-- ButtonFacade library skins buttons (can change their display in many different ways)
local LBF = LibStub("LibButtonFacade", true)
-- time left in which tenths of a second are displayed
local DEBUFF_FILTER_TIMELEFT_TENTHSSEC = 5

local DEBUFF_FILTER_NO_COOLDOWN = 0
local DEBUFF_FILTER_COOLDOWN_ONLY = 1
local DEBUFF_FILTER_COOLDOWN_AND_TIMER = 2

local DEBUFF_FILTER_NO_SORT = 0
local DEBUFF_FILTER_SORT_ALPHA_ATOZ = 1
local DEBUFF_FILTER_SORT_ALPHA_ZTOA = 2
local DEBUFF_FILTER_SORT_TIMEREM_LONGTOSHORT = 3
local DEBUFF_FILTER_SORT_TIMEREM_SHORTTOLONG = 4

local DEBUFF_FILTER_FRIENDS_ENEMIES = 0
local DEBUFF_FILTER_ONLY_FRIENDS = 1
local DEBUFF_FILTER_ONLY_ENEMIES = 2

-- default value to update time display when debuff is about to finish
local DEBUFF_FILTER_TIMELEFT_NUMFRACSEC = 0.2

function DebuffFilter:DebugTrace (arg1, enter)
	if self.db and DebuffFilter.PlayerConfig.General.showTrace == true then
		if (enter) then
			DEFAULT_CHAT_FRAME:AddMessage("DebuffFilter:"..arg1.." enter")
		else
			DEFAULT_CHAT_FRAME:AddMessage("DebuffFilter:"..arg1.." exit")
		end
	end
end

function DebuffFilter:DebugPrint (arg1)
	if DebuffFilter.PlayerConfig.General.showDebug == true then
		DEFAULT_CHAT_FRAME:AddMessage("DebuffFilter:"..arg1)
	end
end

-- grabs settings for the options screen, this is done by traversing
-- the configuration table which mirrors the table used for displaying
-- the options screen
function DebuffFilter:getfunc(info)
	local value = DebuffFilter.PlayerConfig
	for i = 1, #info do
		value = value[info[i]]
	end
	return value
end

-- modify configuration table, by traversing it -- it mirrors the table
-- used for displaying the options screen
function DebuffFilter:setfunc(info, value)
	local parent = DebuffFilter.PlayerConfig

	for i = 1,#info-1 do
		parent = parent[info[i]]
	end
	parent[info[#info]] = value
end

local BuffOrDebuff = {
	type = "group",
	name = function(info) return info[#info] end,
    args = {
		-- only (de)buff player applied is shown
		selfapplied={
			name= DFILTER_OPTIONS_SELFAPPLIED,
			desc= DFILTER_OPTIONS_SELFAPPLIED_TOOLTIP,
			type= "toggle",
			set = function(info, value)
					if not value then value = nil end
					DebuffFilter:setfunc(info,value)
				end,
			get = "getfunc",
			order=5,
		},
		-- dont combine (de)buffs
		dontcombine={
			name= DFILTER_OPTIONS_DONTCOMBINE,
			desc= DFILTER_OPTIONS_DONTCOMBINE_TOOLTIP,
			type= "toggle",
			set = function(info, value)
					if not value then value = nil end
					DebuffFilter:setfunc(info,value)
				end,
			get = "getfunc",
			order=6,
		},
		del={
			name= DFILTER_OPTIONS_DEL,
			type= "execute",
			order=3,
			func=function(info)
					info.options.args.Buffs.args[info[2]].args[info[3]].args.List.args[info[5]] = nil 
					DebuffFilter.PlayerConfig.Buffs[info[2]][info[3]].List[info[5]] = nil
				end,
		},
		intervalFractionSecond = {
			order=7,
			name = "Time updates",
			desc = function(info)
					return "Period that time is updated below " .. DebuffFilter.PlayerConfig.Frames[info[2]][info[3]].thresholdDisplayFractions .. " seconds"
				end,	
			type = "range",
			min = 0.1,
			max = 1,
			step = 0.1,
			set = function(info, value)
					if value == DEBUFF_FILTER_TIMELEFT_NUMFRACSEC then value = nil end
					DebuffFilter:setfunc(info,value)
				end,
			get = function(info)
					local value = DebuffFilter.PlayerConfig.Buffs[info[2]][info[3]].List[info[5]].intervalFractionSecond
					if value == nil then value = DEBUFF_FILTER_TIMELEFT_NUMFRACSEC end
					return value
				end,
		},
		-- display (de)buff if there is a match of value below with name of (de)buff's texture
		texture={
			type="input",
			name=DFILTER_OPTIONS_TEXTURE,
			set = function(info, value)
					value = value:match("^%s*(.-)%s*$")
					if value:len() == 0 then value = nil end
					DebuffFilter:setfunc(info,value)
				end,
			order=9,
			get = "getfunc",
		},
		changeicon={
			type="input",
			name="Change icon",
			desc="Enter name of a bag item -- its icon will replace spell's icon, even after bag item disappears",
			-- works well, even though it's messy, i can't get an icon simply with the name, blizzard has placed restraints
			set = function(info, value)
					value = value:match("^%s*(.-)%s*$")
					if not (value:len() == 0) then
						local itemID, sName
						for bag = 0, NUM_BAG_SLOTS do
							for bagslot = 1, GetContainerNumSlots(bag) do
								itemID = GetContainerItemID(bag, bagslot)
								if itemID then
									sName = GetItemInfo(itemID);
									if sName and sName == value then
										DebuffFilter:setfunc(info,itemID)
										break
									end
								end	
							end
						end
					else
						DebuffFilter:setfunc(info,nil)
					end
				end,
			order=8,
			get = function(info)
					local changeicon = DebuffFilter.PlayerConfig.Buffs[info[2]][info[3]].List[info[5]].changeicon
					local sName
					if changeicon then sName = GetItemInfo(changeicon) end
					if sName == nil then sName = "" end
					return sName
				end,
		},
	},
}

local BuffsOrDebuffsList = {
	name = function(info)
			if info[#info] == "Buffs" then return DFILTER_OPTIONS_BUFFS
			else return DFILTER_OPTIONS_DEBUFFS end end,
	type = "group",
	childGroups = "tab",
	args = {
		enterBuff={
			type="input",
			name=DFILTER_OPTIONS_NAME,
			disabled = function(info) return DebuffFilter.PlayerConfig.Buffs[info[2]][info[3]].showAllBuffs or not
					DebuffFilter.PlayerConfig.Buffs[info[2]][info[3]].enabled end,
			desc= function(info) return "New "..((info[3]):lower()):sub(1,-2).." to add to list" end,
			order=15,
			set = function(info, value)	
					info.options.args.Buffs.args[info[2]].args[info[3]].args.List.args[value] = BuffOrDebuff
					local intervalFractionSecond = DebuffFilter.PlayerConfig.Frames[info[2]][info[3]].intervalFractionSecond
					if intervalFractionSecond == DEBUFF_FILTER_TIMELEFT_NUMFRACSEC then
						intervalFractionSecond = nil
					end
					DebuffFilter.PlayerConfig.Buffs[info[2]][info[3]].List[value] = {
						intervalFractionSecond = intervalFractionSecond }
				end,
			get = function(info)
					-- remove old debuffs/buffs in list and add correct ones for the target frame
					-- that is selected.  This is done here since the get function does not work
					-- in a group node.  If it does work, it's because a subnode inherited it.
					local buffList = info.options.args.Buffs.args[info[2]].args[info[3]].args.List.args
					for k, v in pairs(buffList) do
						buffList[k] = nil
					end
					for k, v in pairs(DebuffFilter.PlayerConfig.Buffs[info[2]][info[3]].List) do
						buffList[k] = BuffOrDebuff
					end
				end,
		},
		enabled={
			name= "Show Frame",
			desc= "Show or hide current frame",
			type= "toggle",
			order = 5,
			set = function(info, value) 
					DebuffFilter:setfunc(info, value)
					local eFL = DebuffFilter.enabledFramesList
					if value then
						DebuffFilter.Frames[info[2]][info[3]].frame:Show()
						if not eFL[info[2]] then
							eFL[info[2]] = {}
						end
						eFL[info[2]][info[3]] = true
					else
						DebuffFilter.Frames[info[2]][info[3]].frame:Hide()
						eFL[info[2]][info[3]] = nil
						if eFL[info[2]].Buffs == nil and eFL[info[2]].Debuffs == nil then
							eFL[info[2]] = nil
						end
					end
				end,
			get = "getfunc",
		},
		showAllBuffs = {
			type = "toggle",
			name = "Show all",
			desc = function(info) return "Show all "..(info[3]):lower() end,
			disabled = function(info) return not DebuffFilter.PlayerConfig.Buffs[info[2]][info[3]].enabled end,
			order=6,
			set = "setfunc",	
			get = "getfunc",
		},
		-- combine buffs and debuffs into selected frame
		combineBuffsDebuffsFrames={
			name= function(info) 
					local ret_str = "Add debuffs"
					if info[3] == "Debuffs" then ret_str = "Add buffs" end
					return ret_str
				end,
			desc= function(info) 
					local ret_str
					if info[3] == "Debuffs" then 
						ret_str = "Add '" .. info[2] .. "' buffs to this frame"
					else
						ret_str = "Add '" .. info[2] .. "' debuffs to this frame"
					end
					return ret_str
				end,
			type= "toggle",
			order = 7,
			set = "setfunc",
			get = "getfunc",
		},
		onlyFriendsOrEnemies = {
			type = "select",
			name = "Only on: ",
			desc = "Show only on friends or enemies",
			disabled = function(info) return not DebuffFilter.PlayerConfig.Buffs[info[2]][info[3]].enabled end,
			order=8,
        	values = {
				[DEBUFF_FILTER_FRIENDS_ENEMIES] = "",
				[DEBUFF_FILTER_ONLY_ENEMIES] = "enemies",
				[DEBUFF_FILTER_ONLY_FRIENDS] = "friends",
			},
			set = "setfunc",	
			get = "getfunc",
		},
		showAll = {
			type = "multiselect",
			name = "Show all:",
			order = 9,
			width = "half",
			disabled = function(info) return not DebuffFilter.PlayerConfig.Buffs[info[2]][info[3]].enabled
						or DebuffFilter.PlayerConfig.Buffs[info[2]][info[3]].showAllBuffs end,
			values = { showAllMyBuffs="My", showAllNonRaiderBuffs="Nonraider", showAllStealableBuffs="Stealable",
				showAllMagicBuffs="Magic", showAllPoisonBuffs="Poison", showAllDiseaseBuffs="Disease",
				showAllCurseBuffs="Curse", },
			set = function(info, key, value)
					DebuffFilter.PlayerConfig.Buffs[info[2]][info[3]][key] = value
					local fc = DebuffFilter.Frames[info[2]][info[3]].ComparisonList
					if value then
						if key == "showAllMyBuffs" then fc[key] = {name="ismine",value=true}
						elseif key == "showAllStealableBuffs" then fc[key] = {name="isStealable",value=1} 
						elseif key == "showAllMagicBuffs" then fc[key] = {name="debufftype",value="Magic"} 
						elseif key == "showAllPoisonBuffs" then fc[key] = {name="debufftype",value="Poison"} 
						elseif key == "showAllDiseaseBuffs" then fc[key] = {name="debufftype",value="Disease"} 
						elseif key == "showAllCurseBuffs" then fc[key] = {name="debufftype",value="Curse"} end
					else
						fc[key] = nil
					end
				end,
			get = function(info, key)
					return DebuffFilter.PlayerConfig.Buffs[info[2]][info[3]][key]
				end,
		},
		buffDurationToggle={
			name= "Filter using duration",
			desc = function(info) return "Show only selected "..(info[3]):lower().." that last at most "..
				"this number of seconds -- does not apply to "..(info[3]):lower().." listed below" end,
			type= "toggle",
			order = 11,
			set = "setfunc",
			get = "getfunc",
		},	
		buffExpiretimeToggle={
			name= "Filter using expire time",
			desc = function(info) return "Show only selected "..(info[3]):lower().." when they expire "..
				"in less than (or equal to) this number of seconds" end,
			type= "toggle",
			order = 12,
			set = "setfunc",
			get = "getfunc",
		},
		buffDuration = {
			order=13,
			disabled = function(info) return not DebuffFilter.PlayerConfig.Buffs[info[2]][info[3]].buffDurationToggle end,
			name = "Duration",
			desc = function(info) return "Show only selected "..(info[3]):lower().." that last at most "..
				"this number of seconds -- does not apply to "..(info[3]):lower().." listed below" end,
			type = "range",
			min = 10,
			max = 130,
			step = 10,
			set = "setfunc",
			get = "getfunc",
		},
		buffExpiretime = {
			order=14,
			disabled = function(info) return not DebuffFilter.PlayerConfig.Buffs[info[2]][info[3]].buffExpiretimeToggle end,
			name = "Expire time",
			desc = function(info) return "Show only selected "..(info[3]):lower().." when they expire "..
				"in less than (or equal to) this number of seconds" end,
			type = "range",
			min = 10,
			max = 130,
			step = 10,
			set = "setfunc",
			get = "getfunc",
		},
		copyFromFrame={
			name= function(info) return "Copy "..(info[3]):lower().." from frame:" end,
			type= "select",
			order = 16,
			values= function(info)
					local table = {}
					for k, v in pairs(DebuffFilter.Frames) do
						if k ~= info[2] and not v.Cooldowns then table[k] = k end
					end
					return table
				end,
			set= function(info, value)
					local buffList = info.options.args.Buffs.args[info[2]].args[info[3]].args.List.args
					for k, v in pairs(DebuffFilter.PlayerConfig.Buffs[value][info[3]].List) do
						DebuffFilter.PlayerConfig.Buffs[info[2]][info[3]].List[k] = v
						buffList[k] = BuffOrDebuff
					end
				end,
		},
		List={
			name= function(info) return "List of "..(info[3]):lower()..": (drag bottom right corner if not visible)" end,
			--name = DFILTER_OPTIONS_NAME,
			type = "group",
			disabled = function(info) return DebuffFilter.PlayerConfig.Buffs[info[2]][info[3]].showAllBuffs or not
					DebuffFilter.PlayerConfig.Buffs[info[2]][info[3]].enabled end,
			args = {
			},
		},	
	},
}

function DebuffFilter:ValidateInCombatButtonsCastSpells(info)
	if DebuffFilter.PlayerInCombat and info[3] == "Cooldowns" and 
			DebuffFilter.PlayerConfig.Cooldowns[info[2]].ButtonsCastSpells then 
		return "Cannot change while in combat and while buttons can cast spells" 
	end
	return true
end

function DebuffFilter:GeneralValidateInCombatButtonsCastSpells(info)
	local cooldownFrameWithButtonsCastSpells = false
	for k, CooldownFrame in pairs(DebuffFilter.PlayerConfig.Cooldowns) do
		if CooldownFrame.ButtonsCastSpells then cooldownFrameWithButtonsCastSpells = true end
	end
	if DebuffFilter.PlayerInCombat and cooldownFrameWithButtonsCastSpells then 
		return "Cannot change while in combat and while buttons can cast spells" 
	end
	return true
end

local frameOptions = {
	type = "group",
	name = function(info)
			if info[#info] == "Buffs" then return DFILTER_OPTIONS_BUFFS
			elseif info[#info] == "Debuffs" then return DFILTER_OPTIONS_DEBUFFS
			else return "Cooldowns" end end,
	-- display only Cooldowns, or only Buffs and Debuffs, but not all 3 tabs
	hidden = function(info)
			local retval = true
			if info[#info] == "Cooldowns" then
				if DebuffFilter.Frames[info[2]].Cooldowns then
					retval = false
				end
			else
				if not DebuffFilter.Frames[info[2]].Cooldowns then
					retval = false
				end
			end
			return retval
		end,
	args = {
        grow = {
        	order=1,
        	name = DFILTER_OPTIONS_GROW,
        	desc = DFILTER_OPTIONS_GROW_TOOLTIP,
        	hidden = false,
        	type = "select",
        	validate= "ValidateInCombatButtonsCastSpells",
        	values = {
				rightdown = "Right-Down",
				rightup = "Right-Up",
				leftdown = "Left-Down",
				leftup = "Left-Up",
			},
			set = function(info, value) 
						DebuffFilter:setfunc(info, value)
						DebuffFilter_UpdateLayout(info[2],info[3])
				end,	
            get = "getfunc",
        },
        per_row = {
        	order=2,
        	name = DFILTER_OPTIONS_ROW,
        	desc = DFILTER_OPTIONS_ROW_TOOLTIP,
        	hidden = false,
        	type = "range",
        	validate= "ValidateInCombatButtonsCastSpells",
        	min = 1,
        	max = 8,
        	step = 1,
			set = function(info, value) 
						DebuffFilter:setfunc(info, value)
						DebuffFilter_UpdateLayout(info[2],info[3])
				end,	
            get = "getfunc",
        },
		scale = {
        	order=3,
			name = "frame scale",
			desc = "Scales the frame only up or down in size",
        	hidden = false,
        	validate= "ValidateInCombatButtonsCastSpells",
			type = "range",
			min = 0.5,
			max = 3,
			step = 0.05,
			set = function(info, value) 
						DebuffFilter:setfunc(info, value)
						DebuffFilter:FrameSetScale(DebuffFilter.Frames[info[2]][info[3]].frame,value)
				end,	
			get = "getfunc",
		},
		cooldown={
			name= DFILTER_OPTIONS_COOLDOWNCOUNT,
			desc="If \"No cooldown\" is selected, value from General Settings is used",
        	hidden = false,
			type= "select",
        	validate= "ValidateInCombatButtonsCastSpells",
			order = 4,
			values= {[DEBUFF_FILTER_NO_COOLDOWN]="No cooldown",[DEBUFF_FILTER_COOLDOWN_ONLY]=DFILTER_OPTIONS_COOLDOWNCOUNT,
				[DEBUFF_FILTER_COOLDOWN_AND_TIMER]="Cooldown and time"},
			set = function(info, value) 
					DebuffFilter:setfunc(info, value)
					DebuffFilter_UpdateLayout(info[2],info[3])
				end,
			get = "getfunc",
		},
		reverseCooldown={
        	order=5,
			name= "Reverse cooldown",
			desc= "Reverse cooldown display",
        	hidden = false,
        	disabled = function(info) return DebuffFilter.PlayerConfig.General.reverseCooldown end,
			type= "toggle",
        	validate= "ValidateInCombatButtonsCastSpells",
			set = function(info, value) 
					DebuffFilter:setfunc(info, value)
					DebuffFilter_UpdateLayout(info[2],info[3])
				end,
			get = "getfunc",
		},
		sort={
			name=function(info) return "Sort "..(info[3]):lower()..":" end,
			desc="If \"No sort\" is selected, value from General Settings is used",
        	hidden = false,
			type= "select",
        	validate= "ValidateInCombatButtonsCastSpells",
			order = 6,
			values= {[DEBUFF_FILTER_NO_SORT]="No sort",
				[DEBUFF_FILTER_SORT_ALPHA_ATOZ]="From A to Z",
				[DEBUFF_FILTER_SORT_ALPHA_ZTOA]="From Z to A",
				[DEBUFF_FILTER_SORT_TIMEREM_LONGTOSHORT]="Longest time to shortest",
				[DEBUFF_FILTER_SORT_TIMEREM_SHORTTOLONG]="Shortest time to longest",
			},
			set = function(info, value) 
					DebuffFilter:setfunc(info, value)
					DebuffFilter_UpdateLayout(info[2],info[3])
				end,
			get = "getfunc",
		},
		thresholdDisplayFractions = {
			order=7,
			name = "Display Fractions",
			desc = "Threshold under which fractions are displayed",
        	hidden = false,
			type = "range",
			min = 1,
			max = 10,
			step = 1,
			set = "setfunc",	
			get = "getfunc",
		},
		-- period to update time display when debuff is about to finish
		intervalFractionSecond = {
			order=8,
			name = "Time updates",
			desc = function(info) 
					return "Period that time is updated below " .. DebuffFilter.PlayerConfig.Frames[info[2]][info[3]].thresholdDisplayFractions .. " seconds"
				end,
        	hidden = false,
			type = "range",
			min = 0.1,
			max = 1,
			step = 0.1,
			set = function(info, value) 
					DebuffFilter:setfunc(info, value)
					if value == DEBUFF_FILTER_TIMELEFT_NUMFRACSEC then value = nil end
					if info[3] ~= "Cooldowns" then
						for k, v in pairs(DebuffFilter.PlayerConfig.Buffs[info[2]][info[3]].List) do
							v.intervalFractionSecond = value
						end
					else
						for k, v in pairs(DebuffFilter.PlayerConfig.Cooldowns[info[2]].List) do
							v.intervalFractionSecond = value
						end
					end
				end,	
			get = "getfunc",
		},
		ghostTimer={
			order=9,
        	hidden = false,
			name= "Ghost timer",
			desc= "Display timer as opaque after timer finishes",
			type= "toggle",
			set = "setfunc",
			get = "getfunc",
		},
		ghostTimerDuration={
			order=10,
        	hidden = false,
			name = "Ghost duration",
			desc = "Duration of ghost timer",
			type = "range",
			min = 1,
			max = 10,
			step = 1,
			set = "setfunc",	
			get = "getfunc",
		},
		displayAbbreviations={
			order=11,
        	hidden = false,
			name= "Name abbreviations",
			desc= "Display name abbreviation next to each button",
			type= "toggle",
			set = function(info, value) 
					DebuffFilter:setfunc(info, value)
					DebuffFilter_UpdateLayout(info[2],info[3])
				end,
			get = "getfunc",
		},
	},
}

local frameLayoutTabs = {
	type = "group",
	name = function(info) return info[#info] end,
	childGroups = "tab",
	args = {
		Debuffs = frameOptions,
		Buffs = frameOptions,
		Cooldowns = frameOptions,
	}	
}

local frameBuffsTabs = {
	type = "group",
	name = function(info) return info[#info] end,
	childGroups = "tab",
	args = {
		Debuffs = BuffsOrDebuffsList,
		Buffs = BuffsOrDebuffsList,
	},
}

local newFrameName = {
	type = "group",
	name = function(info) return info[#info] end,
	args={
		del={
			name= DFILTER_OPTIONS_DEL,
			type= "execute",
			func=function(info)
				info.options.args.Frames.args[info[3]] = nil
				info.options.args.Buffs.args[info[3]] = nil
				info.options.args.General.args.listNewFrames.args[info[3]] = nil
				
				if LBF then
					local groupID
					for a, b in ipairs({"Buffs","Debuffs"}) do
						groupID = info[3].." "..b.." Frame"
						DebuffFilter.Frames[info[3]][b].buttonfacadeGroup:Delete()
						DebuffFilter.PlayerConfig.ButtonFacade[groupID] = nil
					end
				end	

				DebuffFilter.Frames[info[3]].Buffs.frame:Hide()
				DebuffFilter.Frames[info[3]].Debuffs.frame:Hide()
				DebuffFilter.Frames[info[3]] = nil
				
				DebuffFilter.PlayerConfig.Buffs[info[3]] = nil
				DebuffFilter.PlayerConfig.Frames[info[3]] = nil
				
				DebuffFilter.enabledFramesList[info[3]] = nil
			end,
		},
		newFrameTarget={
			type="input",
			name="Target for new frame:",
			desc="target, player, focus, pet, raid1, focustarget...",
			set = function(info, value)
					DebuffFilter.PlayerConfig.Frames[info[3]].Buffs.frametarget = value
					DebuffFilter.PlayerConfig.Frames[info[3]].Debuffs.frametarget = value
				end,
			get = function(info)
					return DebuffFilter.PlayerConfig.Frames[info[3]].Buffs.frametarget
				end,
		},
	},	
}

local Cooldown = {
	type = "group",
	name = function(info) return info[#info] end,
    args = {
		del={
			name= DFILTER_OPTIONS_DEL,
			type= "execute",
			order=3,
			func=function(info)
					if not (DebuffFilter.PlayerInCombat and DebuffFilter.PlayerConfig.Cooldowns[info[3]].ButtonsCastSpells) then
						info.options.args.Cooldowns.args.listCooldownFrames.args[info[3]].args.listCooldowns.args[info[5]] = nil 
						DebuffFilter.PlayerConfig.Cooldowns[info[3]].List[info[5]] = nil
					end
				end,
		},
		intervalFractionSecond = {
			order=7,
			name = "Time updates",
			desc = function(info)
					return "Period that time is updated below " .. DebuffFilter.PlayerConfig.Frames[info[3]].Cooldowns.thresholdDisplayFractions .. " seconds"
				end,	
			type = "range",
			min = 0.1,
			max = 1,
			step = 0.1,
			set = function(info, value)
					if value == DEBUFF_FILTER_TIMELEFT_NUMFRACSEC then value = nil end
					DebuffFilter.PlayerConfig.Cooldowns[info[3]].List[info[5]].intervalFractionSecond = value
				end,
			get = function(info)
					local value = DebuffFilter.PlayerConfig.Cooldowns[info[3]].List[info[5]].intervalFractionSecond
					if value == nil then value = DEBUFF_FILTER_TIMELEFT_NUMFRACSEC end
					return value
				end,
		},
    },
}    

function DebuffFilter:setfuncCooldown(info, value)
	DebuffFilter.PlayerConfig.Cooldowns[info[3]][info[4]] = value
end

function DebuffFilter:getfuncCooldown(info)
	return DebuffFilter.PlayerConfig.Cooldowns[info[3]][info[4]]
end

local newCooldownFrameName = {
	name = function(info) return info[#info] end,
	order = 4,
	type = "group",
	childGroups = "tab",
	args = {
		enabled={
			name="Show Frame",
			desc="Show or hide current frame",
			type= "toggle",
			order=2,
			set = function(info, value)
					DebuffFilter.PlayerConfig.Cooldowns[info[3]].enabled = value
					local eCL = DebuffFilter.enabledCooldownsList
					if value then
						DebuffFilter.Frames[info[3]].Cooldowns.frame:Show()
						eCL[info[3]] = true
					else
						DebuffFilter.Frames[info[3]].Cooldowns.frame:Hide()
						eCL[info[3]] = nil
					end
				end,
			get = "getfuncCooldown",			
		},
		del={
			name= DFILTER_OPTIONS_DEL,
			desc="Delete cooldown frame",
			type= "execute",
			order=3,
			func=function(info)
					info.options.args.Frames.args[info[3]] = nil
					info.options.args.Cooldowns.args.listCooldownFrames.args[info[3]] = nil
					
					if LBF then
						local groupID
						groupID = info[3].."Cooldowns Frame"
						DebuffFilter.Frames[info[3]].Cooldowns.buttonfacadeGroup:Delete()
						DebuffFilter.PlayerConfig.ButtonFacade[groupID] = nil
					end	
					
					DebuffFilter.Frames[info[3]].Cooldowns.frame:Hide()
					DebuffFilter.Frames[info[3]] = nil
					
					DebuffFilter.PlayerConfig.Cooldowns[info[3]] = nil
					DebuffFilter.PlayerConfig.Frames[info[3]] = nil
					
					DebuffFilter.enabledCooldownsList[info[3]] = nil
				end,
		},
		showAll={
			name= "Show all",
			desc="Show all, even when not on cooldown",
			type= "toggle",
			disabled = function(info) return not DebuffFilter.PlayerConfig.Cooldowns[info[3]].enabled end,
			order=4,
			set = "setfuncCooldown",
			get = function(info)
					return DebuffFilter.PlayerConfig.Cooldowns[info[3]].showAll or
						DebuffFilter.PlayerConfig.Cooldowns[info[3]].ButtonsCastSpells
				end,			
		},
		ButtonsCastSpells={
			name= "Buttons cast spells",
			desc="When enabled, no filtering or sorting can occur in combat",
			type= "toggle",
			disabled = function(info) return not DebuffFilter.PlayerConfig.Cooldowns[info[3]].enabled end,
			order=5,
			validate=function(info)
					if DebuffFilter.PlayerInCombat then
						return "Cannot change while in combat" 
					end
					return true
				end,
			set = function(info, value)
					local cooldownFrameSetup = DebuffFilter.PlayerConfig.Cooldowns[info[3]]
					cooldownFrameSetup.ButtonsCastSpells = value
					if value then cooldownFrameSetup.showAll = true end
					local cooldownFrame = DebuffFilter.Frames[info[3]].Cooldowns
					for k, Button in ipairs(cooldownFrame.buttons) do
						Button:Hide()
					end
					-- create new buttons that inherit or not inherit the template SecureActionButtonTemplate 
					-- This template allows them to cast spells, but then they cannot be moved, resized, or have their
					-- attributes changed during combat
					cooldownFrame.buttons = {}
					for cooldownname, CooldownItem in pairs(cooldownFrameSetup.List) do
						DebuffFilter:CreateCooldownButton(info[3], cooldownname)
					end
				end,
			get = "getfuncCooldown",			
		},
		showAvailable={
			name= "Show available",
			desc="Show all available spells",
			type= "toggle",
			disabled = function(info) return not DebuffFilter.PlayerConfig.Cooldowns[info[3]].enabled
				or DebuffFilter.PlayerConfig.Cooldowns[info[3]].showAll end,
			order=6,
			set = "setfuncCooldown",
			get = "getfuncCooldown",			
		},
		cooldownExpiretimeToggle={
			name= "Filter using expire time",
			desc = function(info) return "Show cooldowns only when they expire "..
				"in less than (or equal to) this number of seconds" end,
			type= "toggle",
			order = 7,
			set = "setfuncCooldown",
			get = "getfuncCooldown",
		},
		cooldownExpiretime = {
			order=8,
			disabled = function(info) return not DebuffFilter.PlayerConfig.Cooldowns[info[3]].cooldownExpiretimeToggle end,
			name = "Expire time",
			desc = function(info) return "Show cooldowns only when they expire "..
				"in less than (or equal to) this number of seconds" end,
			type = "range",
			min = 10,
			max = 130,
			step = 10,
			set = "setfuncCooldown",
			get = "getfuncCooldown",
		},
		newCooldown={
			order=15,
			type="input",
			validate=function(info)
					if DebuffFilter.PlayerInCombat and DebuffFilter.PlayerConfig.Cooldowns[info[3]].ButtonsCastSpells then
						return "Cannot change while in combat and while buttons can cast spells"
					end
					return true
				end,
			disabled = function(info) return not DebuffFilter.PlayerConfig.Cooldowns[info[3]].enabled end,
			width="double",
			name="Name for new cooldown:",
			desc="Name for new cooldown",
			set = function(info, value)
					info.options.args.Cooldowns.args.listCooldownFrames.args[info[3]].args.listCooldowns.args[value] = Cooldown
					DebuffFilter.PlayerConfig.Cooldowns[info[3]].List[value] = {}
					DebuffFilter:CheckForCooldownItemIDs()
					DebuffFilter:CreateCooldownButton(info[3],value)
				end,
			-- Create list of cooldowns for the options cooldown dialog
			get = function(info)
					local cooldownList = info.options.args.Cooldowns.args.listCooldownFrames.args[info[3]].args.listCooldowns.args
					for k, v in pairs(cooldownList) do
						cooldownList[k] = nil
					end
					for k, v in pairs(DebuffFilter.PlayerConfig.Cooldowns[info[3]].List) do
						cooldownList[k] = Cooldown
					end
				end,
		},
		listCooldowns={
			order=16,
			type="group",
			disabled = function(info) return not DebuffFilter.PlayerConfig.Cooldowns[info[3]].enabled end,
			name="List of cooldowns: (drag bottom right corner if not visible)",
			args={
			},
		},
	},
}

function DebuffFilter:checkFrameNoExists(info,value)
	if DebuffFilter.Frames[value] ~= nil then
		return "Frame with name '"..value.."' already exists"
	end
	return true
end

local options = {
	handler = DebuffFilter,
	name="DebuffFilter",
	type = "group",
	args = {

	BlizOptions ={
		type = "group",
		name = "Open Standalone Dialog",
		args={
			version={
				order=1,
				type="description",
				name=function(info) return "version: "..GetAddOnMetadata("DebuffFilter", "Version") end,
			},
			config = {
				order=11,
				type = "execute",
				name = "Standalone Config",
				desc = "Setup addon in a movable standalone dialog",
				func = "OpenConfigDialog"
			},
		},
	},
	General = {
		order = 1,
		type = "group",
		name = "General Settings",
		childGroups = "tab",
		args = {
			version={
				order=1,
				type="description",
				name=function(info) return "version: "..GetAddOnMetadata("DebuffFilter", "Version") end,
			},
			enabled={
				order=2,
				name= "Enabled",
				desc= "Enables/disables this addon",
				type= "toggle",
				set = function(info, value) 
						DebuffFilter:setfunc(info, value)
						if value then
							DebuffFilterFrame:GetAnimationGroups():Play()
							DebuffFilterFrame:Show()
						else
							DebuffFilterFrame:GetAnimationGroups():Stop()
							DebuffFilterFrame:Hide()
						end
					end,
				get = "getfunc",
			},
			cooldown={
				name= DFILTER_OPTIONS_COOLDOWNCOUNT,
				desc=DFILTER_OPTIONS_COOLDOWNCOUNT_TOOLTIP,
				type= "select",
				validate="GeneralValidateInCombatButtonsCastSpells",
				order = 5,
				values= {[DEBUFF_FILTER_NO_COOLDOWN]="No cooldown",[DEBUFF_FILTER_COOLDOWN_ONLY]=DFILTER_OPTIONS_COOLDOWNCOUNT,
					[DEBUFF_FILTER_COOLDOWN_AND_TIMER]="Cooldown and time"},
				set= function(info, value)
						DebuffFilter:setfunc(info, value)
						for target, v in pairs(DebuffFilter.Frames) do
							for buffs, b in pairs(v) do
								DebuffFilter_UpdateLayout(target,buffs)
							end
						end
					end,
				get = "getfunc",
			},
			reverseCooldown={
				order=3,
				name= "Reverse cooldown",
				desc= "Reverse cooldown display",
				type= "toggle",
				set = "setfunc",
				get = "getfunc",
			},	
			sort={
				name= "Sort buffs/debuffs:",
				--desc="",
				type= "select",
				validate="GeneralValidateInCombatButtonsCastSpells",
				order = 6,
				values= {[DEBUFF_FILTER_NO_SORT]="No sort",
					[DEBUFF_FILTER_SORT_ALPHA_ATOZ]="From A to Z",
					[DEBUFF_FILTER_SORT_ALPHA_ZTOA]="From Z to A",
					[DEBUFF_FILTER_SORT_TIMEREM_LONGTOSHORT]="Longest time to shortest",
					[DEBUFF_FILTER_SORT_TIMEREM_SHORTTOLONG]="Shortest time to longest",
				},	
				set= "setfunc",
				get = "getfunc",
			},
			combat={
				order=7,
				name= DFILTER_OPTIONS_COMBAT,
				desc= DFILTER_OPTIONS_COMBAT_TOOLTIP,
				type= "toggle",
				set = function(info, value) 
						DebuffFilter:setfunc(info, value)
						if value then
							if (not DebuffFilter.PlayerInCombat) then
								DebuffFilterFrame:Hide();
							end
						else
							DebuffFilterFrame:Show();
						end
					end,	
				get = "getfunc",
			},
			tooltips={
				order=8,
				name= DFILTER_OPTIONS_TOOLTIPS,
				desc= DFILTER_OPTIONS_TOOLTIPS_TOOLTIP,
				type= "toggle",
				set = function(info, value) 
						DebuffFilter:setfunc(info, value)
						-- see lock option below for explanation
						if not value and DebuffFilter.PlayerConfig.General.lock then 
							DebuffFilter_LockFrames(true) 
						else
							DebuffFilter_LockFrames(false)
						end	
					end,	
				get = "getfunc",
			},
			backdrop={
				order=9,
				name= DFILTER_OPTIONS_BACKDROP,
				desc= DFILTER_OPTIONS_BACKDROP_TOOLTIP,
				type= "toggle",
				set = function(info, value) 
						DebuffFilter:setfunc(info, value)
						for k, v in pairs(DebuffFilter.Frames) do
							for a, Frame in pairs(v) do
								if value then
									Frame.frameBackdrop:Show()
								else
									Frame.frameBackdrop:Hide()
								end
							end
						end	
					end,	
				get = "getfunc",
			},
			lock={
				order=10,
				name= DFILTER_OPTIONS_LOCK,
				desc= "If tooltips are not shown, mouse click-thru is allowed",
				type= "toggle",
				set = function(info, value) 
						DebuffFilter:setfunc(info, value)
						-- to allow tooltips to be shown, the frames won't be allowed to be moved, but
						-- the buttons will still accept mouse input
						if value and not DebuffFilter.PlayerConfig.General.tooltips then 
							DebuffFilter_LockFrames(true) 
						else
							DebuffFilter_LockFrames(false)
						end	
					end,	
				get = "getfunc",
			},
			resetposition={
				order=14,
				name= "Reset Frame Positions",
				type= "execute",
				validate="GeneralValidateInCombatButtonsCastSpells",
				func=function()
					DebuffFilter.xvalues.xvalue = 478
					DebuffFilter.xvalues.nextxvalue = 578
					DebuffFilter.yvalue = 335
					local anchor;
					-- a frame's position is affected by its scale, so I need to reset scales too
					DebuffFilter.PlayerConfig.General.scale = 1.2
					DebuffFilterFrame:SetScale(1.2)
					for target, v in pairs(DebuffFilter.Frames) do
						for buffs, Frame in pairs(v) do
							DebuffFilter.PlayerConfig.Frames[target][buffs].scale = 1
							DebuffFilter:FrameSetScale(Frame.frame, 1);
							
							anchor = {"TOPLEFT","UIParent","BOTTOMLEFT",DebuffFilter.xvalues.xvalue,DebuffFilter.yvalue}
							DebuffFilter.PlayerConfig.Frames[target][buffs].anchor = anchor			
							Frame.frame:ClearAllPoints()
							Frame.frame:SetPoint(unpack(anchor))

							if buffs ~= "Cooldowns" then DebuffFilter:swapXvalues() end

						end
						DebuffFilter:adjustAnchorPoints()
					end
				end,		
			},
			intervalFractionSecond = {
				order=13,
				name = "Time updates",
				desc = function(info)
						return "Period that time is updated below " .. DebuffFilter.PlayerConfig.General.thresholdDisplayFractions .. " seconds"
					end,	
				type = "range",
				min = 0.1,
				max = 1,
				step = 0.1,
				set = function(info, value) 
						DebuffFilter:setfunc(info, value)
						for target, v in pairs(DebuffFilter.PlayerConfig.Frames) do
							for a, FrameLayout in pairs(v) do
								FrameLayout.intervalFractionSecond = value
							end
						end
						-- do not set nil value above since frame layout's get function does not check for nil value
						if value == DEBUFF_FILTER_TIMELEFT_NUMFRACSEC then value = nil end
						for target, v in pairs(DebuffFilter.PlayerConfig.Buffs) do
							for a, Buffs in pairs(v) do
								for c, d in pairs(Buffs.List) do
									d.intervalFractionSecond = value
								end
							end
						end
						for target, Cooldowns in pairs(DebuffFilter.PlayerConfig.Cooldowns) do
							for a, Cooldown in pairs(Cooldowns.List) do
								Cooldown.intervalFractionSecond = value
							end
						end
					end,	
				get = "getfunc",
			},
			scale = {
				order=11,
				name = DFILTER_OPTIONS_SCALE,
				desc = DFILTER_OPTIONS_SCALE_TOOLTIP,
				type = "range",
				validate="GeneralValidateInCombatButtonsCastSpells",
				min = 0.5,
				max = 3,
				step = 0.05,
				set = function(info, value) 
						DebuffFilter:setfunc(info, value)
						DebuffFilter:SetScale(value)
					end,	
				get = "getfunc",
			},
			thresholdDisplayFractions = {
				order=12,
				name = "Display Fractions",
				desc = "Threshold under which fractions are displayed",
				type = "range",
				min = 1,
				max = 10,
				step = 1,
				set = function(info, value) 
						DebuffFilter:setfunc(info, value)
						for target, v in pairs(DebuffFilter.PlayerConfig.Frames) do
							for a, FrameLayout in pairs(v) do
								FrameLayout.thresholdDisplayFractions = value
							end
						end
					end,	
				get = "getfunc",
			},
			--[[header={
				order=11,
				name="",
				type= "header",
			},]]
			noBoxAroundTime={
				order=15,
				name= "No box around time",
				desc= "No black box around the time",
				type= "toggle",
				set = function(info, value)
						DebuffFilter:setfunc(info, value)
						local alpha = 1
						if value then
							alpha = 0							
						end
						for target, v in pairs(DebuffFilter.Frames) do
							for a, Frame in pairs(v) do
								for c, button in ipairs(Frame.buttons) do
									button.time_frame.DBFframetexture:SetTexture(0,0,0,alpha)
									button.DBFbuttonName.bckgrnd:SetTexture(0,0,0,alpha)
								end
							end
						end	
					end,
				get = "getfunc",
			},
			disableOverlay={
				order=16,
				name= "Disable Overlay",
				desc= "Disables the flashy overlay that occurs around some buttons",
				type= "toggle",
				set = function(info, value)
						DebuffFilter:setfunc(info, value)
						if not value then
							DebuffFilter:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
							DebuffFilter:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
						else
							DebuffFilter:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
							DebuffFilter:UnregisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
							for Framename, v in pairs(DebuffFilter.enabledCooldownsList) do
								for _, CooldownButton in ipairs(DebuffFilter.Frames[Framename].Cooldowns.buttons) do
									ActionButton_HideOverlayGlow(CooldownButton)
								end
							end
						end
					end,
				get = "getfunc",
			},
			count={
				order=17,
				name= DFILTER_OPTIONS_COUNT,
				desc= DFILTER_OPTIONS_COUNT_TOOLTIP,
				type= "toggle",
				set = function(info, value) 
						DebuffFilter:setfunc(info, value)
						for target, v in pairs(DebuffFilter.Frames) do
							for buffOrCooldown, Frame in pairs(v) do
								if buffOrCooldown ~= "Cooldowns" then
									if value then 
										Frame.frameCount:Show()
									else
										Frame.frameCount:Hide()
									end
								end
							end
						end	
					end,
				get = "getfunc",
			},
			ghostTimer={
				order=18,
				name= "Ghost timer",
				desc= "Display timer as opaque after timer finishes",
				type= "toggle",
				set = "setfunc",
				get = "getfunc",
			},
			ghostTimerOpacity={
				order=19,
				name = "Ghost opacity",
				desc = "How faded ghost timers appear",
				type = "range",
				min = 0.05,
				max = 0.95,
				step = 0.05,
				set = "setfunc",	
				get = "getfunc",
			},
			ghostTimerDuration={
				order=20,
				name = "Ghost duration",
				desc = "Duration of ghost timer",
				type = "range",
				min = 1,
				max = 10,
				step = 1,
				set = function(info, value) 
						DebuffFilter:setfunc(info, value)
						for target, v in pairs(DebuffFilter.PlayerConfig.Frames) do
							for a, FrameLayout in pairs(v) do
								FrameLayout.ghostTimerDuration = value
							end
						end
					end,	
				get = "getfunc",
			},
			displayAbbreviations={
				order=21,
				name= "Name abbreviations",
				desc= "Display name abbreviation next to each button",
				type= "toggle",
				set= function(info, value)
						DebuffFilter:setfunc(info, value)
						for target, v in pairs(DebuffFilter.Frames) do
							for buffs, b in pairs(v) do
								DebuffFilter_UpdateLayout(target,buffs)
							end
						end
					end,
				get = "getfunc",
			},
			newFrame={
				order=22,
				type="input",
				width="double",
				validate="checkFrameNoExists",
				name="Name for new frame:",
				desc="Can duplicate existing frames or show buffs for new targets, like pet, raid1...",
				set = function(info, value)
						info.options.args.Frames.args[value] = frameLayoutTabs
						info.options.args.Buffs.args[value] = frameBuffsTabs
						info.options.args.General.args.listNewFrames.args[value] = newFrameName

						local frameitem, groupID
						DebuffFilter.Frames[value] = {}
						for a, b in ipairs({"Buffs","Debuffs"}) do
							-- frame's target can be changed by user
							DebuffFilter.PlayerConfig.Frames[value][b].frametarget = value
							DebuffFilter:createFrame(value, b)
							DebuffFilter.PlayerConfig.Frames[value][b].intervalFractionSecond = DebuffFilter.PlayerConfig.General.intervalFractionSecond
							DebuffFilter.PlayerConfig.Frames[value][b].thresholdDisplayFractions = DebuffFilter.PlayerConfig.General.thresholdDisplayFractions
							-- if there's ButtonFacade, create a group for frame so it can be skinned
							if LBF then
								groupID = value.." "..b.." Frame"
								frameitem = DebuffFilter.Frames[value][b]
								frameitem.buttonfacadeGroup = LBF:Group("DebuffFilter", groupID)
							end	
						end	
						DebuffFilter:adjustAnchorPoints()
					end,
			},
			listNewFrames={
				order=23,
				type="group",
				name="List of new frames: (drag bottom right corner if not visible)",
				args={
				},
			},
			showDebug = {
				hidden = true,
				name = "ShowDebug",
				desc = "Show debug messages",
				type = "toggle",
				set = "setfunc",
				get = "getfunc",
			},
			showTrace = {
				hidden = true,
				name = "ShowTrace",
				desc = "Show trace messages",
				type = "toggle",
				set = "setfunc",
				get = "getfunc",
			},
		},	
	},
	Frames = {
		order = 2,
		type = "group",
		name = "Frame Layout",
		childGroups = "select",
		-- tooltip won't appear
		--desc = DFILTER_OPTIONS_TARGET_TOOLTIP,
		args = {
		},
	},
	Buffs = {
		order = 3,
		type = "group",
		name = "Frame Buffs",
		childGroups = "select",
		--desc = DFILTER_OPTIONS_TARGET_TOOLTIP,
		args = {
		},

	},
	Cooldowns = {
		order = 4,
		type = "group",
		name = "Cooldowns",
		childGroups = "tab",
		--desc = DFILTER_OPTIONS_TARGET_TOOLTIP,
		args = {
			newCooldownFrame={
				order=15,
				type="input",
				validate="checkFrameNoExists",
				width="double",
				name="Name for new cooldown frame:",
				desc="Name for new cooldown frame",
				set = function(info, value)
						info.options.args.Frames.args[value] = frameLayoutTabs
						DebuffFilter.PlayerConfig.Frames[value].Cooldowns.frametarget = "cooldown"
						info.options.args.Cooldowns.args.listCooldownFrames.args[value] = newCooldownFrameName

						local frameitem, groupID
						DebuffFilter.Frames[value] = {}
						DebuffFilter:createCooldownFrame(value, "Cooldowns")
						DebuffFilter.PlayerConfig.Frames[value].Cooldowns.intervalFractionSecond = DebuffFilter.PlayerConfig.General.intervalFractionSecond
						DebuffFilter.PlayerConfig.Frames[value].Cooldowns.thresholdDisplayFractions = DebuffFilter.PlayerConfig.General.thresholdDisplayFractions
						-- if there's ButtonFacade, create a group for frame so it can be skinned
						if LBF then
							groupID = value.."Cooldowns Frame"
							frameitem = DebuffFilter.Frames[value].Cooldowns
							frameitem.buttonfacadeGroup = LBF:Group("DebuffFilter", groupID)
						end
						DebuffFilter:adjustAnchorPoints()
					end,
			},
			listCooldownFrames={
				order=16,
				type="group",
				name="List of cooldown frames:",
				childGroups = "select",
				args={
				},
			},
		},
	},

	},
}

-- taken from bongos, like below
function DebuffFilter:FrameSetScale(frame, scale)
	local ratio, x, y, layout;
	
	ratio = frame:GetScale() / scale;

	x, y = frame:GetLeft() * ratio, frame:GetTop() * ratio;
	-- store new position of frame in config file
	layout = DebuffFilter.PlayerConfig.Frames[frame.DBFframename][frame.DBFbuffOrDebuff]
	layout.anchor = {"TOPLEFT", "UIParent", "BOTTOMLEFT", x, y};			

	frame:ClearAllPoints();
	frame:SetPoint(unpack(layout.anchor));
	frame:SetScale(scale);
end

-- taken from bongos
function DebuffFilter:SetScale(scale)
	local ratio, x, y, frame, layout;

	ratio = DebuffFilterFrame:GetScale() / scale;

	for target, v in pairs(DebuffFilter.Frames) do
		for buffs, b in pairs(v) do
			frame = DebuffFilter.Frames[target][buffs].frame
			x, y = frame:GetLeft() * ratio, frame:GetTop() * ratio;
			-- store new position of frame in config file
			layout = DebuffFilter.PlayerConfig.Frames[target][buffs]
			layout.anchor = {"TOPLEFT", "UIParent", "BOTTOMLEFT", x, y};			

			frame:ClearAllPoints();
			frame:SetPoint(unpack(layout.anchor));
		end	
	end

	DebuffFilterFrame:SetScale(scale);
end

-- I use two x positions, one for the buff, and the other for the debuff
function DebuffFilter:swapXvalues()
	local tempxvalue
	tempxvalue = DebuffFilter.xvalues.xvalue;
	DebuffFilter.xvalues.xvalue = DebuffFilter.xvalues.nextxvalue;
	DebuffFilter.xvalues.nextxvalue = tempxvalue;
end

-- for new frames, or resetting frames, this function calculates new positions
-- the positions are arranged like a grid
function DebuffFilter:adjustAnchorPoints()
	local yvalue, xvalue, nextxvalue = DebuffFilter.yvalue, DebuffFilter.xvalues.xvalue, DebuffFilter.xvalues.nextxvalue
	yvalue = yvalue - 60;
	-- if y has fallen too much, set its position back to top of screen
	if yvalue < 150 then
		xvalue = nextxvalue + 100
		nextxvalue = xvalue + 100
		yvalue = 515
		-- if x has gone too far right, set its position back to left of screen
		if xvalue > 885 then
			xvalue = xvalue - 1020
			nextxvalue = xvalue + 100
		end
	end
	DebuffFilter.yvalue, DebuffFilter.xvalues.xvalue, DebuffFilter.xvalues.nextxvalue = yvalue, xvalue, nextxvalue
end

-- settings that are stored on file and are referenced through DebuffFilter.PlayerConfig.  
-- ['**'] is a wildcard, and it can be replaced by any string -- it is used by Ace-DB
function DebuffFilter:InitDefaults()
	local defaults = {
		profile = {
			General = {
				enabled = true,
				count = false,
				cooldown = DEBUFF_FILTER_NO_COOLDOWN,
				cooldowncount = false,
				reverseCooldown = false,
				sort = DEBUFF_FILTER_NO_SORT,
				combat = false,
				tooltips = false,
				backdrop = false,
				lock = true,
				scale = 1,
				showDebug = false,
				showTrace = false,
				intervalFractionSecond = DEBUFF_FILTER_TIMELEFT_NUMFRACSEC,
				thresholdDisplayFractions = DEBUFF_FILTER_TIMELEFT_TENTHSSEC,
				noBoxAroundTime = false,
				disableOverlay = false,
				ghostTimerOpacity = 0.45,
				ghostTimerDuration = 3,
				ghostTimer = false,
				displayAbbreviations = false,
			},
			Frames = {
				['**'] = {
					['**'] = {
						per_row = 8,
						scale = 1,
						grow = "rightdown",
						time_tb = "bottom",
						time_lr = "right",
						cooldown = DEBUFF_FILTER_NO_COOLDOWN,
						reverseCooldown = false,
						sort = DEBUFF_FILTER_NO_SORT,
						intervalFractionSecond = DEBUFF_FILTER_TIMELEFT_NUMFRACSEC,
						thresholdDisplayFractions = DEBUFF_FILTER_TIMELEFT_TENTHSSEC,
						ghostTimerDuration = 3,
						ghostTimer = false,
						displayAbbreviations = false,
					},
				},
			},
			Buffs = {
				target = {
					Debuffs = {
						enabled = true,
						showAllMyBuffs = true,
						showAllNonRaiderBuffs = true,
					},
					Buffs = {
						enabled = true,
						showAllMyBuffs = true,
						showAllNonRaiderBuffs = true,
					},
				},
				player = {
					Debuffs = {
						enabled = true,
						showAllNonRaiderBuffs = true,
					},
					Buffs = {
						enabled = true,
						showAllMyBuffs = true,
					},
				},
				['**'] = {
					Buffs = {
						showAllBuffs = false,
						showAllStealableBuffs = false,
						showAllMagicBuffs = false,
						showAllPoisonBuffs = false,
						showAllDiseaseBuffs = false,
						showAllCurseBuffs = false,
						combineBuffsDebuffsFrames = false,
						buffDurationToggle = false,
						buffExpiretimeToggle = false,
						buffDuration = 30,
						buffExpiretime = 30,
						onlyFriendsOrEnemies = DEBUFF_FILTER_FRIENDS_ENEMIES,
						-- cannot use ['**'] for list of buffs, otherwise buffs with default values won't get stored
						["List"] = {
						},
					},
					Debuffs = {
						showAllBuffs = false,
						showAllStealableBuffs = false,
						showAllMagicBuffs = false,
						showAllPoisonBuffs = false,
						showAllDiseaseBuffs = false,
						showAllCurseBuffs = false,
						combineBuffsDebuffsFrames = false,
						buffDurationToggle = false,
						buffExpiretimeToggle = false,
						buffDuration = 30,
						buffExpiretime = 30,
						onlyFriendsOrEnemies = DEBUFF_FILTER_FRIENDS_ENEMIES,
						["List"] = {
						},
					},
				},
			},
			Cooldowns={
				['**']={
					enabled = true,
					showAll = false,
					showAvailable = false,
					ButtonsCastSpells = false,
					cooldownExpiretimeToggle = false,
					cooldownExpiretime = 30,
					["List"]={
					},
				},
			},
			ButtonFacade = {
			},
		},
	}
	return defaults
end

-- the direction that debuffs/buffs are organized, what side their time is on,
-- and what side the number of debuffs/buffs is placed
DebuffFilter.Orientation = {
	rightdown = { point="LEFT", relpoint="RIGHT", x=34, y=0 },
	rightup = { point="LEFT", relpoint="RIGHT", x=34, y=0 },
	leftdown = { point="RIGHT", relpoint="LEFT", x=-34, y=0 },
	leftup = { point="RIGHT", relpoint="LEFT", x=-34, y=0 },
	bottom = { point="TOP", relpoint="BOTTOM", x=0, y=-2, next_time="top" },
	top = { point="BOTTOM", relpoint="TOP", x=0, y=2, next_time="bottom" },
	left = { point="RIGHT", relpoint="LEFT", x=-4, y=0, next_time="right" },
	right = { point="LEFT", relpoint="RIGHT", x=4, y=0, next_time="left" },
}

function DebuffFilter_Button_OnLoad(self)
	local name = self:GetName();

	self.icon = _G[name .. "Icon"];
	-- frame which holds button's time, and surrounds it with a black background
	self.time_frame = _G[name .. "Duration"]
	self.time_frame.time = _G[name .. "DurationString"];
	self.time_frame.DBFframetexture = _G[name .. "DurationBckgrnd"]
	self.cooldown = _G[name .. "Cooldown"];
	-- current number of debuff/buff's stack
	self.count = _G[name .. "Count"];
	-- number of same debuffs/buffs that are combined
	self.count2 = _G[name .. "Count2"];
	self.border = _G[name .. "Border"];
	self.DBFbuttonName = _G[name .. "ButtonName"];
	self.DBFbuttonName.string = _G[name .. "ButtonNameString"];
	self.DBFbuttonName.bckgrnd = _G[name .. "ButtonNameBckgrnd"];
	self.DBFbuttonName.strlen = 0
end

function DebuffFilter_OnMouseDown(self, button)
	if (button == "LeftButton" and IsShiftKeyDown()) then
		-- backdrop has no name, so allow frame to be moved if backdrop is selected
		if self:GetName() == nil or not DebuffFilter.PlayerConfig.General.lock then
			self:GetParent():StartMoving();
		end	
	elseif (button == "RightButton" and IsControlKeyDown()) then
		local next_time;
		local frame = self:GetParent();
		local layout = DebuffFilter.PlayerConfig.Frames[frame.DBFframename][frame.DBFbuffOrDebuff];

		-- switch position of the debuffs/buffs time, if it's bottom make it top
		-- if there's only 1 per row, switch it to left or right side
		if (layout.per_row == 1) then
			next_time = DebuffFilter.Orientation[layout.time_lr].next_time;
			layout.time_lr = next_time;
		else
			next_time = DebuffFilter.Orientation[layout.time_tb].next_time;
			layout.time_tb = next_time;
		end

		local displayAbbreviations = layout.displayAbbreviations or DebuffFilter.PlayerConfig.General.displayAbbreviations
		-- reposition the times for the debuffs/buffs of a certain frame
		DebuffFilter_SetTimeOrientation(next_time, DebuffFilter.Frames[frame.DBFframename][frame.DBFbuffOrDebuff].buttons, displayAbbreviations);
		DebuffFilter_Print(frame.DBFframename.." "..frame.DBFbuffOrDebuff.. " time orientation: " .. next_time);
	end
end

function DebuffFilter_OnMouseUp(self, button)
	if (button == "LeftButton") then
		local frame = self:GetParent();
		frame:StopMovingOrSizing();
		
		-- store the new frame position in config file
		local anchor = {"TOPLEFT","UIParent","BOTTOMLEFT",frame:GetLeft(),frame:GetTop()};
		DebuffFilter.PlayerConfig.Frames[frame.DBFframename][frame.DBFbuffOrDebuff].anchor = anchor;
	end
end

function DebuffFilter_Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Debuff Filter|r: " .. tostring(msg));
end

local hideTime = function(time_frame)
	if time_frame.DBFisTimeVisible then
		time_frame:Hide()
		time_frame.DBFisTimeVisible = false
	end	
end

local createSpellAbbreviation = function(name)
	local nameAbbr = ""
	local nameAbbrLen = 0
	if name then
		nameAbbr = name:gsub("([%w:])[%w']*%s*","%1")
		nameAbbrLen = nameAbbr:len()
		if nameAbbrLen == 1 then
			nameAbbr = name:sub(1,3)
			nameAbbrLen = nameAbbr:len()
		elseif nameAbbrLen == 2 then
			nameAbbr = name:gsub("(%w[%w'])[%w']*%s*","%1")
			nameAbbrLen = nameAbbr:len()
		end	
		if nameAbbrLen > 4 then
			nameAbbr = nameAbbr:sub(1,4)
			nameAbbrLen = nameAbbr:len()
		end
	end	
	return nameAbbr, nameAbbrLen
end

function DebuffFilter_ShowButton(button, bt, framename, buffOrDebuff, displayAbbreviations)

	local time_frame = button.time_frame

	-- sets the color of the border of the debuff, but I can't find
	-- the DebuffTypeColor list anywhere
	if bt.isdebuff then
		local color
		if (bt.debufftype) then
			color = DebuffTypeColor[bt.debufftype];
		else
			color = DebuffTypeColor["none"];
			bt.debufftype = "none"
		end
		-- save time maybe by setting the border color only if it's changed
		if button.DBFdebufftype ~= bt.debufftype then
			button.border:SetVertexColor(color.r, color.g, color.b) 
			button.DBFdebufftype = bt.debufftype
		end	
		button.border:Show()
	else
		button.border:Hide()
	end

	-- needed for gametooltip -- so i know to use SetUnitDebuff or SetUnitBuff
	button.isdebuff = bt.isdebuff
	-- needed for gametooltip, so it knows what (de)buff description to use
	button.index = bt.index;

	if button.DBFnum_combines ~= bt.num_combines then
		button.DBFnum_combines = bt.num_combines
		if bt.num_combines == 1 then
			button.count2:Hide();
		else
			button.count2:SetText(bt.num_combines)
			button.count2:Show();
		end	
	end

	-- save time maybe by setting the texture if it's changed
	if button.DBFtexture ~= bt.texture then
		button.icon:SetTexture(bt.texture);
		button.DBFtexture = bt.texture
	end

	if displayAbbreviations then
		local nameAbbr, nameAbbrLen = createSpellAbbreviation(bt.name)
		button.DBFbuttonName.string:SetText(nameAbbr)
		if nameAbbrLen ~= button.DBFbuttonName.strlen then
			button.DBFbuttonName:SetWidth(button.DBFbuttonName.string:GetStringWidth()+4)
			button.DBFbuttonName.strlen = nameAbbrLen
		end
		button.DBFbuttonName:Show()
	else
		button.DBFbuttonName:Hide()
	end

	if bt.ghostTimer then
		button.icon:SetVertexColor(1.0,1.0,1.0,DebuffFilter.PlayerConfig.General.ghostTimerOpacity)
	else
		button.icon:SetVertexColor(1.0,1.0,1.0,1.0)
	end
	
	-- show stack number of a debuff/buff
	if button.DBFapplications ~= bt.applications then
		button.DBFapplications = bt.applications
		if (bt.applications > 1) then
			button.count:SetText(bt.applications);
			button.count:Show();
		else
			button.count:Hide();
		end
	end

	local cooldown = button.cooldown
	local framelayout = DebuffFilter.PlayerConfig.Frames[framename][buffOrDebuff]
	local generaloptions = DebuffFilter.PlayerConfig.General
	-- show time remaining for a debuff/buff, if it exists, as a time
	-- and/or display it as a cooldown on the debuff/buff itself in the form of a rotating shadow
	if (bt.duration and bt.duration > 0 and not bt.ghostTimer) then
		if (framelayout.cooldown > DEBUFF_FILTER_NO_COOLDOWN or generaloptions.cooldown > DEBUFF_FILTER_NO_COOLDOWN) then
			local reverseCooldownState = not(framelayout.reverseCooldown or generaloptions.reverseCooldown)

			-- cannot call setcooldown every 0.025 seconds, otherwise it looks awful, and not like a cooldown
			if not (cooldown.DBFexpiretime == bt.expiretime and cooldown.DBFduration == bt.duration) then
				cooldown:SetCooldown(bt.expiretime-bt.duration, bt.duration)
				cooldown.DBFexpiretime = bt.expiretime
				cooldown.DBFduration = bt.duration
				cooldown:SetReverse(reverseCooldownState)
				cooldown.DBFreverseCooldownState = reverseCooldownState
			else
				cooldown:Show()
				-- setreverse might be an expensive call, so I check a variable to see whether to change it
				if cooldown.DBFreverseCooldownState ~= reverseCooldownState then
					cooldown:SetReverse(reverseCooldownState)
					cooldown.DBFreverseCooldownState = reverseCooldownState
				end	
			end
			
		else
			cooldown:Hide()
		end
		-- make time visible and have it updated every second, if debuff/buff has a time.  Also, the user
		-- must not choose the "cooldown only" option for the frame, or if the "no cooldown" option is chosen
		-- for the frame, the user must not choose the "cooldown only" option in general settings
		if (framelayout.cooldown == DEBUFF_FILTER_COOLDOWN_AND_TIMER or (framelayout.cooldown == DEBUFF_FILTER_NO_COOLDOWN
				and generaloptions.cooldown ~= DEBUFF_FILTER_COOLDOWN_ONLY)) then
			
			DebuffFilter_SetTime(time_frame, bt.expiretime - GetTime(), framelayout.thresholdDisplayFractions, bt.intervalFractionSecond);

			if not time_frame.DBFisTimeVisible then
				--button:SetScript("OnUpdate",DebuffFilter_Button_OnUpdate);
				time_frame:Show()
				time_frame.DBFisTimeVisible = true
			end
		else
			hideTime(time_frame)
		end	
	else
		cooldown:Hide()
		hideTime(time_frame)
	end

	button:Show();
end

local UpdateAllEnabledFrames = function(self)
	for target, v in pairs(DebuffFilter.enabledFramesList) do
		for buffs, b in pairs(v) do
			DebuffFilter_Frame_Update(target,buffs)
		end
	end
	for cooldownframename, v in pairs(DebuffFilter.enabledCooldownsList) do
		DebuffFilter_CooldownFrame_Update(cooldownframename)
	end
end

function DebuffFilter:Sort(arr, len, comp_func)
	if len > 1 then
		if len > 10 then
			local start = DebuffFilter:merge_sort(arr, 1, len, comp_func)
			
			arr[1] = start
			for a = 2, len do
				arr[a] = start.next
				start = start.next
			end
		else
			local d, key
			for c = 1, (len-1) do
				d = c
				key = arr[c+1]
				while d > 0 and not comp_func(arr[d], key) do
					arr[d+1] = arr[d]
					d = d - 1
				end
				arr[d+1] = key
			end
		end
	end	
end

function DebuffFilter:merge_sort(arr, a, b, comp_func)
	local ret_val
	if (b - a) > 8 then
		local mid = floor((b+a)/2)
		local left = DebuffFilter:merge_sort(arr, a, mid, comp_func)
		local right = DebuffFilter:merge_sort(arr, mid+1, b, comp_func)
		ret_val = DebuffFilter:merge(left, right, comp_func)
	else
		ret_val = arr[a]
		local key, iter
		arr[a].next = nil
		for c = a, (b-1) do
			key = arr[c+1]
			iter = key
			iter.next = ret_val
			if comp_func(iter.next, key) then
				iter = iter.next
				while iter.next and comp_func(iter.next, key) do
					iter = iter.next
				end
				key.next = iter.next
				iter.next = key
			else
				ret_val = key
			end	
		end
	end
	return ret_val
end

function DebuffFilter:merge(left, right, comp_func)
	local start, iter
	if comp_func(left, right) then
		start = left
		left = left.next
	else
		start = right
		right = right.next
	end
	iter = start
	while left and right do
		if comp_func(left, right) then
			iter.next = left
			left = left.next
		else
			iter.next = right
			right = right.next
		end
		iter = iter.next
	end
	if left then
		iter.next = left
	else
		iter.next = right
	end
	iter = start
	return start
end

local sortTableArray = function(table_array, framelayout, width, ButtonsCastSpells)
	local sort_method = DEBUFF_FILTER_NO_SORT
	if framelayout.sort ~= DEBUFF_FILTER_NO_SORT then
		sort_method = framelayout.sort
	else
		if DebuffFilter.PlayerConfig.General.sort ~= DEBUFF_FILTER_NO_SORT then
			sort_method = DebuffFilter.PlayerConfig.General.sort
		end
	end	
	if sort_method ~= DEBUFF_FILTER_NO_SORT then
		if sort_method == DEBUFF_FILTER_SORT_ALPHA_ATOZ then
			DebuffFilter:Sort(table_array, width, function(a,b) return a.name < b.name end)
		elseif sort_method == DEBUFF_FILTER_SORT_ALPHA_ZTOA then
			DebuffFilter:Sort(table_array, width, function(a,b) return a.name > b.name end)
		-- cannot move buttons in combat when they can cast spells
		elseif sort_method == DEBUFF_FILTER_SORT_TIMEREM_LONGTOSHORT and not ButtonsCastSpells then
			DebuffFilter:Sort(table_array, width, function(a,b) return a.expiretime2 > b.expiretime2 end)
		elseif sort_method == DEBUFF_FILTER_SORT_TIMEREM_SHORTTOLONG and not ButtonsCastSpells then
			DebuffFilter:Sort(table_array, width, function(a,b) return a.expiretime2 < b.expiretime2 end)
		end
	end	
end

local checkCooldown = function(start, duration, button)
	local expiretime2 = start + duration
	local cooldownIsGhost
	if start ~= 0 then
		if duration > 1.5 then
			button.DBFexpiretime2 = expiretime2
			button.DBFcooldownStart = start
			button.DBFduration = duration
			button.DBFonCooldown = true
			-- will eliminate ghost timer if one already started
			button.DBFghostStart = nil
		else
			-- if a GCD occurs at the end of a spell's cooldown, it overlaps it, so I need to get the data about
			-- the spell's cooldown from the previous iteration
			if button.DBFexpiretime2 and GetTime() <= button.DBFexpiretime2 and button.DBFexpiretime2 < expiretime2 then 
				start = button.DBFcooldownStart
				duration = button.DBFduration
				expiretime2 = button.DBFexpiretime2
			else
				-- previous iteration spell was on cooldown, so now we need a ghost timer
				if button.DBFonCooldown == true then
					cooldownIsGhost = true
					button.DBFonCooldown = false
				end
				-- needed to ignore global cooldown when sorting cooldowns according to time
				expiretime2 = 0 
			end
		end
	else
		if button.DBFonCooldown == true then
			cooldownIsGhost = true
			button.DBFonCooldown = false
		end
	end
	return start, duration, expiretime2, cooldownIsGhost
end

function DebuffFilter_CooldownFrame_Update(framename)
	local frameitem = DebuffFilter.Frames[framename].Cooldowns
	local framelayout = DebuffFilter.PlayerConfig.Frames[framename].Cooldowns
	local generaloptions = DebuffFilter.PlayerConfig.General
	local buttons = frameitem.buttons;
	-- stores button indices for cooldowns, so that cooldown buttons can be rearranged, and for other purposes too
	local buttonsbyspell = frameitem.buttonsbyspell
	local ghostTimer = framelayout.ghostTimer or generaloptions.ghostTimer
	-- include cooldown in list of timers as a ghost
	local cooldownIsGhost = false
	local button
	local framecooldowns = DebuffFilter.PlayerConfig.Cooldowns[framename]
	local showAvailable = framecooldowns.showAvailable
	local showAll = framecooldowns.showAll
	local time_frame, texture, start, duration, enabled, cooldown, expiretime2, filterwithexpire
	-- used to store filtered cooldowns, so that they can be sorted
	local cd_table_array = DebuffFilter.cd_table_array
	local cd_table
	local width = 0
	local sName, CooldownItem, spellIsUsable, noManaForSpell, cooldownIsAvailable
	local curtime = GetTime()
	-- iterate through every cooldown, filter it, and store correct ones in temporary array for sorting
	for name, CooldownItem in pairs(framecooldowns.List) do
		-- I assume that if start == 0, then the item or spell is not on cooldown
		start = nil
		button = buttons[buttonsbyspell[name]]
		cooldownIsGhost = false
		if CooldownItem.itemID then
			start, duration, enabled = GetItemCooldown(CooldownItem.itemID)
			texture = GetItemIcon(CooldownItem.itemID)
			if start then 
				start, duration, expiretime2, cooldownIsGhost = checkCooldown(start, duration, button)
				cooldownIsAvailable = ((start == 0 or duration <= 1.5) and enabled ~= 0)
			end
		else
			start, duration, enabled = GetSpellCooldown(name)
			texture = GetSpellTexture(name)
			spellIsUsable, noManaForSpell = IsUsableSpell(name)
			if start then
				start, duration, expiretime2, cooldownIsGhost = checkCooldown(start, duration, button)
				cooldownIsAvailable = ((start == 0 or duration <= 1.5) and (spellIsUsable or (not spellIsUsable and noManaForSpell)))
			end	
		end
		if start then
			if ghostTimer and not showAvailable then 
				-- cooldownIsGhost is set to true before this point only when a spell finishes its cooldown.
				-- At that point, button.DBFghostStart is initialized, and elseif block runs instead afterwards
				if cooldownIsGhost then
					start = button.DBFexpiretime2
					duration = framelayout.ghostTimerDuration
					expiretime2 = start
					button.DBFghostStart = start
				elseif button.DBFghostStart and curtime < (framelayout.ghostTimerDuration + button.DBFghostStart) then
					start = button.DBFghostStart
					duration = framelayout.ghostTimerDuration
					expiretime2 = start
					cooldownIsGhost = true
				end
			end
			-- could not do this before because value of expiretime2 from previous iteration was needed
			button.DBFexpiretime2 = expiretime2
			filterwithexpire = not framecooldowns.cooldownExpiretimeToggle or expiretime2 <= (GetTime() + framecooldowns.cooldownExpiretime)
			if showAll or (showAvailable and cooldownIsAvailable) or 
					(not showAvailable and enabled ~= 0 and button.DBFonCooldown and filterwithexpire) 
					or cooldownIsGhost then
				width = width + 1
				cd_table = cd_table_array[width]
				if cd_table == nil then
					cd_table_array[width] = {
						name=name, start=start, duration=duration, expiretime2=expiretime2, texture=texture,
						itemID = CooldownItem.itemID, spellIsUsable=spellIsUsable, noManaForSpell=noManaForSpell,
						ghostTimer = cooldownIsGhost
					}
					cd_table = cd_table_array[width]
				else
					cd_table.name = name
					cd_table.start = start
					cd_table.texture = texture
					cd_table.duration = duration
					cd_table.expiretime2 = expiretime2
					cd_table.itemID = CooldownItem.itemID
					cd_table.spellIsUsable = spellIsUsable
					cd_table.noManaForSpell = noManaForSpell
					cd_table.ghostTimer = cooldownIsGhost
				end
			end	
		end
	end
	
	sortTableArray(cd_table_array, framelayout, width, framecooldowns.ButtonsCastSpells)
	
	local bt, buttonname, inRange, hotKey, spellCurrentlyCasting, tempbutton
	spellCurrentlyCasting = UnitCastingInfo("player")
	local reverseCooldownState = not(framelayout.reverseCooldown or generaloptions.reverseCooldown)
	local displayAbbreviations = framelayout.displayAbbreviations or generaloptions.displayAbbreviations
	for j = 1, width do
		bt = cd_table_array[j]

		if buttonsbyspell[bt.name] ~= j then
			-- button holding current cooldown has index buttonsbyspell[bt.name], it needs to be swapped with button
			-- with index j - then buttonsbyspell needs to be changed so that indices are corrected
			tempbutton = buttons[buttonsbyspell[bt.name]]
			buttons[buttonsbyspell[bt.name]] = buttons[j]
			buttonsbyspell[buttons[j].DBFname] = buttonsbyspell[bt.name]
			
			buttons[j].DBFinCorrectPosition = false
			buttons[j] = tempbutton

			buttonsbyspell[bt.name] = j
			
			-- set the position of the button, and its time
			DebuffFilter_SetButtonLayout(framelayout, frameitem.frame, buttons, j, displayAbbreviations);
			buttons[j].DBFinCorrectPosition = true
			
		else
			if not buttons[j].DBFinCorrectPosition then
				DebuffFilter_SetButtonLayout(framelayout, frameitem.frame, buttons, j, displayAbbreviations)
				buttons[j].DBFinCorrectPosition = true
			end
		end

		button = buttons[j];

		hotKey = button.DBFhotKey
		time_frame = button.time_frame

		if button.DBFtexture ~= bt.texture then
			button.icon:SetTexture(bt.texture);
			button.DBFtexture = bt.texture
		end
		if bt.ghostTimer then
			button.icon:SetVertexColor(1.0,1.0,1.0,DebuffFilter.PlayerConfig.General.ghostTimerOpacity)
		else
			button.icon:SetVertexColor(1.0,1.0,1.0,1.0)
		end
		if displayAbbreviations then
			button.DBFbuttonName:Show()
		else
			button.DBFbuttonName:Hide()
		end
		
		-- everything below was taken from ActionButton.lua in FrameXML folder - this comes from Blizzard's interface files
		if not bt.itemID then
			if ( bt.spellIsUsable ) then
				button.icon:SetVertexColor(1.0, 1.0, 1.0);
				button.DBFnormalTexture:SetVertexColor(1.0, 1.0, 1.0);
			elseif ( bt.noManaForSpell ) then
				button.icon:SetVertexColor(0.5, 0.5, 1.0);
				button.DBFnormalTexture:SetVertexColor(0.5, 0.5, 1.0);
			else
				button.icon:SetVertexColor(0.4, 0.4, 0.4);
				button.DBFnormalTexture:SetVertexColor(1.0, 1.0, 1.0);
			end
			inRange = IsSpellInRange(bt.name, "target")
			if bt.name == spellCurrentlyCasting then
				button:SetChecked(1)
			else
				button:SetChecked(0)
			end	
		else
			if IsEquippedItem(bt.name) then
				button.border:SetVertexColor(0, 1.0, 0, 0.35);
				button.border:Show();
			else
				button.border:Hide();
			end
			inRange = IsItemInRange(bt.itemID, "target")
		end
		if ( inRange == 0 ) then
			hotKey:Show();
			hotKey:SetVertexColor(1.0, 0.1, 0.1);
		elseif ( inRange == 1 ) then
			hotKey:Show();
			hotKey:SetVertexColor(0.6, 0.6, 0.6);
		else
			hotKey:Hide();
		end

		local intervalFractionSecond
		CooldownItem = framecooldowns.List[bt.name]
		if CooldownItem.intervalFractionSecond then
			intervalFractionSecond = CooldownItem.intervalFractionSecond
		else
			intervalFractionSecond = framelayout.intervalFractionSecond
		end	
		cooldown = button.cooldown

		--if bt.start ~= 0 and bt.enabled ~= 0 and not bt.ghostTimer then
		-- should probably check enabled, but i forgot to include it in table(bug), but I've tested cooldowns and they were ok, besides, enabled is always nil
		-- if a spell is used, whose cooldown is about to start sometime in future (like Inner Focus), duration is actually 0.001, except for Stealth, which is 10
		if bt.start ~= 0 and not bt.ghostTimer and bt.duration ~= 0.001 then
			if (framelayout.cooldown > DEBUFF_FILTER_NO_COOLDOWN or generaloptions.cooldown > DEBUFF_FILTER_NO_COOLDOWN) then
				-- cannot call setcooldown every 0.025 seconds, otherwise it looks awful, and not like a cooldown
				if not (cooldown.DBFstart == bt.start and cooldown.DBFduration == bt.duration) then
					cooldown:SetCooldown(bt.start, bt.duration)
					cooldown:SetReverse(reverseCooldownState)
					cooldown.DBFreverseCooldownState = reverseCooldownState
					cooldown.DBFstart = bt.start
					cooldown.DBFduration = bt.duration
				else
					if not cooldown:IsShown() then cooldown:Show() end
					-- setreverse might be an expensive call, so I check a variable to see whether to change it
					if cooldown.DBFreverseCooldownState ~= reverseCooldownState then
						cooldown:SetReverse(reverseCooldownState)
						cooldown.DBFreverseCooldownState = reverseCooldownState
					end	
				end
			else
				cooldown:Hide()
			end
			if (framelayout.cooldown == DEBUFF_FILTER_COOLDOWN_AND_TIMER or (framelayout.cooldown == DEBUFF_FILTER_NO_COOLDOWN
					and generaloptions.cooldown ~= DEBUFF_FILTER_COOLDOWN_ONLY)) then

				if bt.duration > 1.5 then
					DebuffFilter_SetTime(time_frame, bt.start + bt.duration - GetTime(), framelayout.thresholdDisplayFractions, intervalFractionSecond);

					if not time_frame.DBFisTimeVisible then
						time_frame:Show()
						time_frame.DBFisTimeVisible = true
					end
				end
			else
				hideTime(time_frame)
			end	
		else
			cooldown:Hide()
			hideTime(time_frame)
		end
		
		if not button:IsShown() then button:Show() end
		
	end
	
	-- hide remaining buttons that were visible from before
	width = width + 1;
	for ii = width, #buttons do
		buttons[ii]:Hide()
	end
end

-- when recreating buttons, if we dont set these fields to nil, I think they will still point to the old buttons
local deleteButton = function(name, cooldown)
	_G[name .. "Icon"]=nil
	-- frame which holds button's time, and surrounds it with a black background
	_G[name .. "Duration"]=nil
	_G[name .. "DurationString"]=nil
	_G[name .. "DurationBckgrnd"]=nil
	_G[name .. "Cooldown"]=nil
	-- current number of debuff/buff's stack
	_G[name .. "Count"]=nil
	-- number of same debuffs/buffs that are combined
	_G[name .. "Count2"]=nil
	_G[name .. "Border"]=nil
	_G[name .. "ButtonName"]=nil
	_G[name .. "ButtonNameString"]=nil
	_G[name .. "ButtonNameBckgrnd"]=nil
	if cooldown then
		_G[name .. "NormalTexture"]=nil
		_G[name .. "HotKey"]=nil
	end	
end

function DebuffFilter_Frame_Update(framename, buffOrDebuff)

	local frameitem = DebuffFilter.Frames[framename][buffOrDebuff];
	local framelayout = DebuffFilter.PlayerConfig.Frames[framename][buffOrDebuff];
	local generaloptions = DebuffFilter.PlayerConfig.General
	local buttons = frameitem.buttons;
	local frametarget = DebuffFilter.PlayerConfig.Frames[framename].Buffs.frametarget
	local targetIsFriend = UnitIsFriend("player",frametarget)
	-- these two tables are only used in this function, i save memory by not recreating them
	local already_seen_debuffs = DebuffFilter.already_seen_debuffs;
	-- used to store filtered buffs/debuffs, so that they can be sorted
	local buff_table_array = DebuffFilter.buff_table_array

	local button;
	local name, texture, applications, duration, expiretime, caster
	local nametexture;
	local width = 0;

	local debuff = nil
	local buff_table = nil
	-- determines if a (de)buff is in a group that user wants shown
	local buffInGroup
	-- under 5 seconds, period between updates of button time (from 0.1 to 1 second)
	local intervalFractionSecond = DEBUFF_FILTER_TIMELEFT_NUMFRACSEC
		
	local casterGUID, BB, maskedBB
	
	local ghostTimer = framelayout.ghostTimer or generaloptions.ghostTimer
	local curtime = GetTime()

	local i, isdebuff, changeicon
	-- total number of buffs or debuffs for the frame's target (before filter)
	local numbuffs = 0
	local sb
	-- add buffs or debuffs to current frame (combining buffs and debuffs together) if user wants
	DebuffFilter.de_buffsList[1] = buffOrDebuff
	DebuffFilter.de_buffsList[2] = nil
	if DebuffFilter.PlayerConfig.Buffs[framename][buffOrDebuff].combineBuffsDebuffsFrames then
		DebuffFilter.de_buffsList[1] = "Buffs"
		DebuffFilter.de_buffsList[2] = "Debuffs"
	end
	-- iterate through every debuff/buff player has, filter it, and store correct ones in temporary array for sorting
	for _, de_buffs in ipairs(DebuffFilter.de_buffsList) do
		
		sb = DebuffFilter.PlayerConfig.Buffs[framename][de_buffs]

		if sb.onlyFriendsOrEnemies == DEBUFF_FILTER_FRIENDS_ENEMIES or
			sb.onlyFriendsOrEnemies == DEBUFF_FILTER_ONLY_FRIENDS and targetIsFriend or 
			sb.onlyFriendsOrEnemies == DEBUFF_FILTER_ONLY_ENEMIES and not targetIsFriend then
			
			i = 1
			isdebuff = de_buffs == "Debuffs"

			if isdebuff then
				name, _, texture, applications, frameitem.Comparisons["debufftype"], duration, expiretime, caster, frameitem.Comparisons["isStealable"] = UnitDebuff(frametarget, i);
			else
				name, _, texture, applications, frameitem.Comparisons["debufftype"], duration, expiretime, caster, frameitem.Comparisons["isStealable"] = UnitBuff(frametarget, i);
			end
			while texture do
				buffInGroup = sb.showAllBuffs
				frameitem.Comparisons["ismine"] = caster == "player";

				if not buffInGroup and sb.showAllNonRaiderBuffs and caster ~= nil then
					casterGUID = UnitGUID(caster);
					-- thanks, stellschraube!
					if casterGUID ~= nil then
						BB = casterGUID:sub(0,casterGUID:find("-")-1)
						if BB == "Creature" or BB == "GameObject" then
							buffInGroup = true
						end
					end
				end

				-- check if (de)buff is in a group of debuffs/buffs that user selected
				if not buffInGroup then
					for k, v in pairs(DebuffFilter.Frames[framename][de_buffs].ComparisonList) do
						if frameitem.Comparisons[v.name] == v.value then
							buffInGroup = true
							break
						end	
					end
				end

				-- if the (de)buff is in a group, but its duration is too long, dont show it, unless the (de)buff
				-- was typed manually into the list
				if buffInGroup and sb.buffDurationToggle then
					if duration > sb.buffDuration or duration == 0 then
						buffInGroup = false
					end
				end

				debuff = nil
				-- check if current debuff/buff is on list of debuffs/buffs to display
				if not buffInGroup then
					debuff = DebuffFilter.PlayerConfig.Buffs[framename][de_buffs].List[name];
					-- don't show (de)buff unless its expiration is less than a certain period of time
					if debuff and sb.buffExpiretimeToggle and (expiretime > (GetTime() + sb.buffExpiretime) or expiretime == 0) then
						debuff = nil
					end
					if debuff and debuff.intervalFractionSecond then
						intervalFractionSecond = debuff.intervalFractionSecond
					end	
				else
					if sb.buffExpiretimeToggle and (expiretime > (GetTime() + sb.buffExpiretime) or expiretime == 0) then
						buffInGroup = false
					else
						intervalFractionSecond = DebuffFilter.PlayerConfig.Frames[framename][de_buffs].intervalFractionSecond
					end	
				end

				-- if texture field is not nil, look for a match with the name of debuff/buff's texture
				-- problem with this, is that i have seen spells who have texture names that are much different than the spell name
				if (debuff and (not debuff.selfapplied or frameitem.Comparisons["ismine"]) and (not debuff.texture or string.match(texture, debuff.texture))) 
						or buffInGroup then

					nametexture = name .. texture;
					
					if debuff and debuff.changeicon then
						changeicon = GetItemIcon(debuff.changeicon)
						if changeicon then texture = changeicon end
					end
					
					if (already_seen_debuffs[nametexture] and not (debuff and debuff.dontcombine)) then
						-- below just ensures that buff with longer time span is shown
						buff_table = buff_table_array[already_seen_debuffs[nametexture]]
						if expiretime > buff_table.expiretime then
							buff_table.expiretime = expiretime
							buff_table.index=i
							buff_table.applications = applications
							buff_table.duration = duration
							buff_table.num_combines = buff_table.num_combines + 1
							buff_table.expiretime2 = expiretime
						end
					else
						width = width + 1

						buff_table = buff_table_array[width]
						if buff_table == nil then
							buff_table_array[width] = {
								name=name, texture=texture, applications=applications, duration=duration, expiretime=expiretime,
								index=i, num_combines=1, expiretime2 = expiretime, isdebuff = isdebuff, debufftype = frameitem.Comparisons["debufftype"],
								intervalFractionSecond=intervalFractionSecond, ghostTimer = false
							}
							buff_table = buff_table_array[width]
						else
							buff_table.name = name
							buff_table.texture = texture
							buff_table.applications=applications
							buff_table.duration=duration
							buff_table.expiretime=expiretime
							buff_table.index=i
							buff_table.num_combines=1
							buff_table.expiretime2 = expiretime
							buff_table.isdebuff = isdebuff
							buff_table.debufftype = frameitem.Comparisons["debufftype"]
							buff_table.intervalFractionSecond = intervalFractionSecond
							buff_table.ghostTimer = false
						end
						-- used for sorting, to keep sorting function minimal, 72000 seconds = 20 hours
						if buff_table.expiretime2 == 0 then buff_table.expiretime2 = curtime + 72000 end
						already_seen_debuffs[nametexture] = width;
						
						-- remember names of (de)buffs in an array that is indexed by name
						if ghostTimer then DebuffFilter.ghost_timers[name] = width end
					end
				end	

				i = i + 1;
				if isdebuff then
					name, _, texture, applications, frameitem.Comparisons["debufftype"], duration, expiretime, caster, frameitem.Comparisons["isStealable"] = UnitDebuff(frametarget, i);
				else
					name, _, texture, applications, frameitem.Comparisons["debufftype"], duration, expiretime, caster, frameitem.Comparisons["isStealable"] = UnitBuff(frametarget, i);
				end
			end
			numbuffs = numbuffs + i - 1

			-- better to reuse this table then use up memory by creating a new one
			for k in pairs(already_seen_debuffs) do
				already_seen_debuffs[k] = nil;
			end
		end	
	end	

	local bt
	if ghostTimer then
		local curtime = GetTime()
		local targetGUID = UnitGUID(frametarget)
		-- dont create ghost timers if (de)buffs disappear because target has changed
		if targetGUID == frameitem.lastIterTargetGUID then
			duration = framelayout.ghostTimerDuration 
			-- copy (de)buffs from last iteration that don't appear in current iteration into buff_table as ghost timers
			for j = 1, frameitem.buffsFromLastIterationCount do
				debuff = frameitem.buffsFromLastIteration[j]
				-- dont copy (de)buff if it's a ghost timer that has expired
				if not DebuffFilter.ghost_timers[debuff.name] and (debuff.ghostTimer == false or curtime < debuff.expiretime) then
					width = width + 1

					buff_table = buff_table_array[width]
					if buff_table == nil then
						buff_table_array[width] = {
							name=debuff.name, texture=debuff.texture, applications=debuff.applications, duration=duration, expiretime=debuff.expiretime,
							index=-1, num_combines=debuff.num_combines, expiretime2=debuff.expiretime2, isdebuff = debuff.isdebuff, debufftype = debuff.debufftype,
							intervalFractionSecond=debuff.intervalFractionSecond, ghostTimer = true
						}
						buff_table = buff_table_array[width]
					else
						buff_table.name = debuff.name
						buff_table.texture = debuff.texture
						buff_table.applications=debuff.applications
						buff_table.duration=duration
						buff_table.expiretime=debuff.expiretime
						buff_table.index=-1
						buff_table.num_combines=debuff.num_combines
						buff_table.expiretime2=debuff.expiretime2
						buff_table.isdebuff = debuff.isdebuff
						buff_table.debufftype = debuff.debufftype
						buff_table.intervalFractionSecond = debuff.intervalFractionSecond
						buff_table.ghostTimer = true
					end
					-- if the (de)buff copied wasn't a ghost timer, it is now and it needs a new expiration time
					if debuff.ghostTimer == false then
						buff_table.expiretime = buff_table.expiretime + duration
					end	
				end
			end
		end
		frameitem.lastIterTargetGUID = targetGUID

		-- copy contents of buff_table_array into buffsFromLastIteration, so that next iteration knows what timers current iteration had
		for j = 1, width do
			bt = buff_table_array[j]
			buff_table = frameitem.buffsFromLastIteration[j]
			if buff_table == nil then
				frameitem.buffsFromLastIteration[j] = {
					name=bt.name, texture=bt.texture, applications=bt.applications, duration=bt.duration, expiretime=bt.expiretime,
					index=bt.index, num_combines=bt.num_combines, expiretime2=bt.expiretime2, isdebuff = bt.isdebuff, debufftype=bt.debufftype,
					intervalFractionSecond=bt.intervalFractionSecond, ghostTimer=bt.ghostTimer
				}
				buff_table = frameitem.buffsFromLastIteration[j]
			else
				buff_table.name = bt.name
				buff_table.texture = bt.texture
				buff_table.applications=bt.applications
				buff_table.duration=bt.duration
				buff_table.expiretime=bt.expiretime
				buff_table.index=bt.index
				buff_table.num_combines=bt.num_combines
				buff_table.expiretime2 = bt.expiretime2
				buff_table.isdebuff = bt.isdebuff
				buff_table.debufftype = bt.debufftype
				buff_table.intervalFractionSecond = bt.intervalFractionSecond
				buff_table.ghostTimer = bt.ghostTimer
			end
		end
		frameitem.buffsFromLastIterationCount = width

		for name in pairs(DebuffFilter.ghost_timers) do
			DebuffFilter.ghost_timers[name] = nil
		end
	end	
		
	-- display number of debuffs/buffs raider has
	if (width == 0) then
		frameitem.frameCount:SetText("");
	else
		frameitem.frameCount:SetText(numbuffs);
	end

	sortTableArray(buff_table_array, framelayout, width, false)
	
	local enableMouse = not(generaloptions.lock and not generaloptions.tooltips)
	local buttonname
	local displayAbbreviations = framelayout.displayAbbreviations or generaloptions.displayAbbreviations

	-- display buffs/debuffs for frame
	for j = 1, width do
		bt = buff_table_array[j]
		
		button = buttons[j];
		if (not button) then
			buttonname = "DebuffFilterButton"..framename..buffOrDebuff..j
			if _G[buttonname] ~= nil then 
				deleteButton(buttonname, false)
				_G[buttonname] = nil 
			end
			button = CreateFrame("Button", buttonname, frameitem.frame, "DebuffFilter_BuffButtonTemplate");
			buttons[j] = button
			-- needed by gametooltip for debuff/buff description
			button.target = frametarget;

			if generaloptions.noBoxAroundTime then
				button.time_frame.DBFframetexture:SetTexture(0,0,0,0)
				button.DBFbuttonName.bckgrnd:SetTexture(0,0,0,0)
			else
				button.time_frame.DBFframetexture:SetTexture(0,0,0,1)
				button.DBFbuttonName.bckgrnd:SetTexture(0,0,0,1)
			end
			
			button.time_frame.DBFisTimeVisible = false;
			-- background of button's time is not resized unless the string length of the time changes
			button.time_frame.DBFtimeLen = 0
			button:EnableMouse(enableMouse);
			-- dont want ButtonFacade to use Count field, since it places it at bottom center of button,
			if LBF then 
				frameitem.buttonfacadeGroup:AddButton(button,{Count=false})
			end

			-- set the position of the button, and its time
			DebuffFilter_SetButtonLayout(framelayout, frameitem.frame, buttons, j, displayAbbreviations);
		end

		DebuffFilter_ShowButton(button, bt, framename, buffOrDebuff, displayAbbreviations);
	end

	-- hide remaining buttons that were visible from before
	for ii = width+1,#buttons do
		buttons[ii]:Hide()
	end
end

-- in combat, so show frames
function DebuffFilter:PLAYER_REGEN_DISABLED(eventName, ...)
	DebuffFilterFrame:Show();
	DebuffFilter.PlayerInCombat = true
end

-- not in combat, so hide frames
function DebuffFilter:PLAYER_REGEN_ENABLED(eventName, ...)
	if DebuffFilter.PlayerConfig.General.combat then
		DebuffFilterFrame:Hide();
	end
	DebuffFilter.PlayerInCombat = false
end

function DebuffFilter_SetTime(time_frame, time, thresholdDisplayFractions, intervalFractionSecond)
	local timeToShow

	if (time < thresholdDisplayFractions) and not(intervalFractionSecond == 1) then
		if time < 0 then
			timeToShow = "0.0"
		else
			-- truncate the hundredths of seconds and smaller, and make result a multiple of intervalFractionSecond
			local fracSec = time - mod(time, intervalFractionSecond)
			timeToShow = tostring(fracSec)
			if timeToShow:len() == 1 then timeToShow = timeToShow .. ".0" end
		end	
	else
		local min, sec;

		time = math.floor(time);
		if time < 0 then
			timeToShow = "0"
		else	
			if ( time >= 60 ) then
				min = math.floor(time/60);
				sec = time - min*60;
			else
				sec = time;
				min = 0;
			end
			timeToShow = tostring(sec)
			if min > 0 then
				if sec <= 9 then
					timeToShow = "0" .. timeToShow
				end
				timeToShow = min .. ":" .. timeToShow
			end
		end	
	end	

	local textcolor
	if (10 >= time) then
		textcolor = 0.27
	else
		textcolor = 0.82
	end
	if time_frame.DBFtextcolor ~= textcolor then
		time_frame.DBFtextcolor = textcolor
		time_frame.time:SetTextColor(1, textcolor, 0);
	end	

	if time_frame.DBFtimeToShow ~= timeToShow then
		time_frame.DBFtimeToShow = timeToShow
		time_frame.time:SetText(timeToShow)
	end	
	local timeLen = timeToShow:len()
	-- adjust black box surrounding time if the time's length has changed
	if time_frame.DBFtimeLen ~= timeLen then
		time_frame.DBFtimeLen = timeLen
		time_frame:SetWidth(time_frame.time:GetStringWidth()+4)
	end
end

-- reposition or redraw frame's debuffs/buffs after options have been changed
function DebuffFilter_UpdateLayout(framename,buffOrDebuff)
	
	local button;
	local frameitem = DebuffFilter.Frames[framename][buffOrDebuff];
	local layout = DebuffFilter.PlayerConfig.Frames[framename][buffOrDebuff];
	local displayAbbreviations = layout.displayAbbreviations or DebuffFilter.PlayerConfig.General.displayAbbreviations
	local buttons = frameitem.buttons

	for ii = 1,#buttons do
		DebuffFilter_SetButtonLayout(layout, frameitem.frame, buttons, ii, displayAbbreviations);
	end
	
	DebuffFilter_SetCountOrientation(layout, frameitem);
end

-- set the location of a debuff/buff and the location of its time
function DebuffFilter_SetButtonLayout(layout, frame, buttons, index, displayAbbreviations)
	local point, relpoint, x, y;
	local grow = layout.grow;
	local per_row = layout.per_row;
	local offset = 16;
	local generaloptions = DebuffFilter.PlayerConfig.General
	local button = buttons[index]

	point, relpoint = DebuffFilter.Orientation[grow].point, DebuffFilter.Orientation[grow].relpoint;
	x, y = DebuffFilter.Orientation[grow].x, DebuffFilter.Orientation[grow].y;

	if (per_row == 1 or layout.cooldown == DEBUFF_FILTER_COOLDOWN_ONLY
			or (layout.cooldown == DEBUFF_FILTER_NO_COOLDOWN and 
			generaloptions.cooldown == DEBUFF_FILTER_COOLDOWN_ONLY)) then
		offset = 4;
	end
	if displayAbbreviations then
		offset = offset + 16
	end	

	button:ClearAllPoints()
	local horiz_index = mod(index, per_row)
	local vert_index = floor((index-1)/per_row)
	if (index > 1) then
		-- start a new row if the current one has enough debuffs/buffs
		if (horiz_index == 1 or per_row == 1) then
			if (layout.grow == "rightdown" or layout.grow == "leftdown") then
				--button:SetPoint("TOP", buttons[index-per_row], "BOTTOM", 0, -offset);
				-- could not use previous way of using SetPoint with cooldown buttons for some reason
				button:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, vert_index*(-30-offset));
			else
				--button:SetPoint("BOTTOM", buttons[index-per_row], "TOP", 0, offset);
				button:SetPoint("BOTTOM", frame, "BOTTOM", 0, vert_index*(30+offset));
			end
		else
			if horiz_index == 0 then horiz_index = per_row end
			--button:SetPoint(point, buttons[index-1], relpoint, x, y)
			if (layout.grow == "rightdown" or layout.grow == "leftdown") then
				button:SetPoint("TOPLEFT", frame, "TOPLEFT", (horiz_index-1)*x, vert_index*(-30-offset))
			else
				button:SetPoint("BOTTOM", frame, "BOTTOM", (horiz_index-1)*x, vert_index*(30+offset))
			end
		end
	else
		button:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0);
	end
	-- place time to the left or right of debuff/buff if debuffs/buffs are arranged vertically
	if per_row == 1 then
		DebuffFilter_SetTimeOrientation(layout.time_lr, button, displayAbbreviations);
	else
		DebuffFilter_SetTimeOrientation(layout.time_tb, button, displayAbbreviations);
	end
end

function DebuffFilter_SetTimeOrientation(orientation, button, displayAbbreviations)
	local point, relpoint, x, y;

	point, relpoint = DebuffFilter.Orientation[orientation].point, DebuffFilter.Orientation[orientation].relpoint;
	x, y = DebuffFilter.Orientation[orientation].x, DebuffFilter.Orientation[orientation].y;

	-- set the position of the time, somewhere around the debuff/buff
	if (button.time_frame) then
		button.time_frame:ClearAllPoints();
		button.time_frame:SetPoint(point, button, relpoint, x, y);
		if displayAbbreviations then
			button.DBFbuttonName:ClearAllPoints();
			button.DBFbuttonName:SetPoint(relpoint, button, point, -x, -y);
		end	
	-- set the positions of the times for the debuffs/buffs of a certain frame
	else
		local buttons = button

		for ii = 1,#buttons do
			buttons[ii].time_frame:ClearAllPoints()
			buttons[ii].time_frame:SetPoint(point, buttons[ii], relpoint, x, y)
			if displayAbbreviations then
				buttons[ii].DBFbuttonName:ClearAllPoints();
				buttons[ii].DBFbuttonName:SetPoint(relpoint, buttons[ii], point, -x, -y);
			end	
		end

	end
end

-- set the location for the number of debuffs/buffs for the frame
function DebuffFilter_SetCountOrientation(layout, frameitem)
	local grow = layout.grow;
	local per_row = layout.per_row;
	local frame = frameitem.frame;

	local count = frameitem.frameCount;
	if count then
		count:ClearAllPoints();


		if (per_row > 1) then
			if (grow == "rightdown" or grow == "rightup") then
				count:SetPoint("RIGHT", frame, "LEFT", 0, 0);
			else
				count:SetPoint("LEFT", frame, "RIGHT", 0, 0);
			end
		else
			if (grow == "rightdown" or grow == "leftdown") then
				count:SetPoint("BOTTOM", frame, "TOP", 0, 8);
			else
				count:SetPoint("TOP", frame, "BOTTOM", 0, -8);
			end
		end
	end
end

-- lock the frames, so they cannot be moved, or unlock them
-- also allows mouse events to pass through debuffs/buffs if locked
function DebuffFilter_LockFrames(lock)
	local buttons

	for target, v in pairs(DebuffFilter.Frames) do
		for buffOrCooldown, Frame in pairs(v) do
			-- dont disable mouse if we need buttons to cast spells.  of course, wont be able to click-thru them
			if not (buffOrCooldown == "Cooldowns" and DebuffFilter.PlayerConfig.Cooldowns[target].ButtonsCastSpells) then
			
				Frame.frame:EnableMouse(not lock);

				buttons = Frame.buttons
				for ii = 1,#buttons do
					buttons[ii]:EnableMouse(not lock);
				end
			end	
		end	
	end
end

-- code was moved from OnInitialize because otherwise, the saved positions of the frames could not be loaded.
-- These saved positions are only needed when user upgrades from old version of Debuff Filter.
-- These frames are from the xml file, and the saved positions are from the game -- the game saves the positions
-- of every xml frame when user logs out.
function DebuffFilter:VARIABLES_LOADED(eventName, ...)
	
	if DebuffFilter.portingXMLframes then
		local xmlFrameName, xmlframe, frameLayout
		for a, b in pairs({target="",focus="F",player="P"}) do
			for c, buff in ipairs({"Buffs","Debuffs"}) do
				xmlFrameName = "DebuffFilter_" .. b .. buff:sub(1,-2) .. "Frame"
				xmlframe = _G[xmlFrameName]
				frameLayout = DebuffFilter.PlayerConfig.Frames[a][buff]
				if xmlframe then 
					frameLayout.anchor = {"TOPLEFT", "UIParent", "BOTTOMLEFT", xmlframe:GetLeft(), xmlframe:GetTop()}
					DebuffFilter.Frames[a][buff].frame:ClearAllPoints();
					DebuffFilter.Frames[a][buff].frame:SetPoint(unpack(frameLayout.anchor));
				end	
			end
		end
	end	
end

function DebuffFilter:OnSkin(skin, gloss, backdrop, group, button, colors)
	if group then
		DebuffFilter.PlayerConfig.ButtonFacade[group] = {skin, gloss, backdrop, colors}
	end
end
	
local overlayGlowHideOrShow = function(spellID,show)
	local buttonSpellID
	for Framename, v in pairs(DebuffFilter.enabledCooldownsList) do
		for _, CooldownButton in ipairs(DebuffFilter.Frames[Framename].Cooldowns.buttons) do
			if CooldownButton.DBFname then 
				_, buttonSpellID = GetSpellBookItemInfo(CooldownButton.DBFname)
				if spellID == buttonSpellID then
					if show then
						ActionButton_ShowOverlayGlow(CooldownButton)
					else
						ActionButton_HideOverlayGlow(CooldownButton)
					end
				end
			end
		end
	end
end

function DebuffFilter:SPELL_ACTIVATION_OVERLAY_GLOW_SHOW(eventName, ...)
	overlayGlowHideOrShow(select(1,...),true)
end

function DebuffFilter:SPELL_ACTIVATION_OVERLAY_GLOW_HIDE(eventName, ...)
	overlayGlowHideOrShow(select(1,...),false)
end

-- needed to iterate through every item player is wearing
local inventorySlotIDS = {
	GetInventorySlotInfo("HeadSlot"),
	GetInventorySlotInfo("NeckSlot"),
	GetInventorySlotInfo("ShoulderSlot"),
	GetInventorySlotInfo("BackSlot"),
	GetInventorySlotInfo("ChestSlot"),
	GetInventorySlotInfo("ShirtSlot"),
	GetInventorySlotInfo("TabardSlot"),
	GetInventorySlotInfo("WristSlot"),
	GetInventorySlotInfo("HandsSlot"),
	GetInventorySlotInfo("WaistSlot"),
	GetInventorySlotInfo("LegsSlot"),
	GetInventorySlotInfo("FeetSlot"),
	GetInventorySlotInfo("Finger0Slot"),
	GetInventorySlotInfo("Finger1Slot"),
	GetInventorySlotInfo("Trinket0Slot"),
	GetInventorySlotInfo("Trinket1Slot"),
	GetInventorySlotInfo("MainHandSlot"),
	GetInventorySlotInfo("SecondaryHandSlot"),
	GetInventorySlotInfo("AmmoSlot"),
	GetInventorySlotInfo("Bag0Slot"),
	GetInventorySlotInfo("Bag1Slot"),
	GetInventorySlotInfo("Bag2Slot"),
	GetInventorySlotInfo("Bag3Slot"),
}

local updateItemID = function(itemID)
	local sName
	if itemID then
		sName = GetItemInfo(itemID);
	end	
	if sName then
		for k, CooldownFrame in pairs(DebuffFilter.PlayerConfig.Cooldowns) do
			if CooldownFrame.List[sName] then
				CooldownFrame.List[sName].itemID = itemID
			end
		end
	end	
end

-- check if new thing equipped is on list of cooldowns. If it is, record its itemID
function DebuffFilter:PLAYER_EQUIPMENT_CHANGED(eventName, ...)
	local slotID, itemInSlot = select(1,...), select(2,...)
	local itemID
	if itemInSlot then
		itemID = GetInventoryItemID("player", slotID)
		updateItemID(itemID)
	end
end

-- check every item in bag, and record its itemID if the item is on the list of cooldowns
function DebuffFilter:BAG_UPDATE(eventName, ...)
	local bag = select(1,...)
	local itemID, sName
	if bag >= 0 and bag <= NUM_BAG_SLOTS then
		for bagslot = 1, GetContainerNumSlots(bag) do
			itemID = GetContainerItemID(bag, bagslot)
			sName = nil
			if itemID then
				sName = GetItemInfo(itemID)
			end
			if sName then
				for k, CooldownFrame in pairs(DebuffFilter.PlayerConfig.Cooldowns) do
					-- dont replace itemID, since a different item with same name may be equipped
					if CooldownFrame.List[sName] and CooldownFrame.List[sName].itemID == nil then
						CooldownFrame.List[sName].itemID = itemID
					end
				end
			end
		end
	end
end

-- check everything in the bags and everything player is wearing for items that are on the list of cooldowns.
-- Record their itemID.
function DebuffFilter:CheckForCooldownItemIDs()
	local itemID
	for bag = 0, NUM_BAG_SLOTS do
		for bagslot = 1, GetContainerNumSlots(bag) do
			itemID = GetContainerItemID(bag, bagslot)
			updateItemID(itemID)
		end
	end
	for ii = 1,#inventorySlotIDS do
		itemID = GetInventoryItemID("player", inventorySlotIDS[ii])
		updateItemID(itemID)
	end
end

function DebuffFilter:CreateCooldownButton(framename, cooldownname)
	local buttonsbyspell, buttonname, button, buttons, frameitem
	local generaloptions = DebuffFilter.PlayerConfig.General

	frameitem = DebuffFilter.Frames[framename].Cooldowns
	buttonsbyspell = frameitem.buttonsbyspell
	buttons = frameitem.buttons
	local j = #buttons + 1
	local Cooldowns = DebuffFilter.PlayerConfig.Cooldowns[framename]
	local CooldownItem = Cooldowns.List[cooldownname]

	local enableMouse = Cooldowns.ButtonsCastSpells or not(generaloptions.lock and not generaloptions.tooltips)

	buttonname = "DebuffFilterButton"..framename.."Cooldowns"..j
	if _G[buttonname] ~= nil then 
		deleteButton(buttonname, true)
		_G[buttonname] = nil 
	end
	-- if user wants buttons that can cast spells, use SecureActionButtonTemplate.  However, the buttons cannot
	-- be moved, resized, or have their attributes changed during combat.
	if Cooldowns.ButtonsCastSpells then
		button = CreateFrame("CheckButton", buttonname, frameitem.frame, "DebuffFilter_CooldownButtonTemplate,SecureActionButtonTemplate")
	else	
		button = CreateFrame("CheckButton", buttonname, frameitem.frame, "DebuffFilter_CooldownButtonTemplate")
	end	
	button.DBFnormalTexture = _G[buttonname .. "NormalTexture"]
	button.DBFhotKey = _G[buttonname .. "HotKey"]
	button.DBFhotKey:SetText(RANGE_INDICATOR)
	buttons[j] = button
	-- store button index for cooldown button, so it can be repositioned
	buttonsbyspell[cooldownname] = j
	button.DBFname = cooldownname

	if CooldownItem.itemID then
		button.DBFtexture = GetItemIcon(CooldownItem.itemID)
		-- buttons are checked (pushed in) only if its the spell currently being cast
		button:SetChecked(0)
	else
		button.DBFtexture = GetSpellTexture(cooldownname)
		button.border:Hide();
	end
	-- enable the buttons to cast spells
	if Cooldowns.ButtonsCastSpells then
		if CooldownItem.itemID then
			button:SetAttribute("type", "item");
			button:SetAttribute("item", cooldownname);
		else
			button:SetAttribute("type", "spell");
			button:SetAttribute("spell", cooldownname);
		end
	end
	
	if button.DBFtexture then button.icon:SetTexture(button.DBFtexture) end

	if generaloptions.noBoxAroundTime then
		button.time_frame.DBFframetexture:SetTexture(0,0,0,0)
		button.DBFbuttonName.bckgrnd:SetTexture(0,0,0,0)
	else
		button.time_frame.DBFframetexture:SetTexture(0,0,0,1)
		button.DBFbuttonName.bckgrnd:SetTexture(0,0,0,1)
	end
	
	button.DBFbuttonName.string:SetText(createSpellAbbreviation(cooldownname))
	button.DBFbuttonName:SetWidth(button.DBFbuttonName.string:GetStringWidth()+4)

	button.time_frame.DBFisTimeVisible = false;
	-- background of button's time is not resized unless the string length of the time changes
	button.time_frame.DBFtimeLen = 0
	button:EnableMouse(enableMouse);
	-- dont want ButtonFacade to use Count field, since it places it at bottom center of button,
	if LBF then 
		frameitem.buttonfacadeGroup:AddButton(button,{Count=false})
	end
end

function DebuffFilter:PLAYER_LOGIN(eventName, ...)

	DebuffFilter:CheckForCooldownItemIDs()
	DebuffFilter:RegisterEvent("BAG_UPDATE")
	DebuffFilter:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")

	local groupID, frameitem, bfOptions
	for target, v in pairs(DebuffFilter.Frames) do
		for buffs, Frame in pairs(v) do
			if LBF then
				groupID = target.." "..buffs.." Frame"
				frameitem = DebuffFilter.Frames[target][buffs]
				frameitem.buttonfacadeGroup = LBF:Group("DebuffFilter", groupID)
				bfOptions = DebuffFilter.PlayerConfig.ButtonFacade[groupID]
				if bfOptions then
					frameitem.buttonfacadeGroup:Skin(unpack(bfOptions))
				end
			end	
		end
	end

	-- cooldown buttons are created at start, unlike debuff buttons, which are created when needed.
	for framename, Cooldowns in pairs(DebuffFilter.PlayerConfig.Cooldowns) do
		for cooldownname, CooldownItem in pairs(Cooldowns.List) do
			DebuffFilter:CreateCooldownButton(framename, cooldownname)
		end
	end

	-- Update frames every 0.025 seconds
	local updater = DebuffFilterFrame:CreateAnimationGroup()
	updater:SetLooping('REPEAT')
	local anim = updater:CreateAnimation('Animation'); 
	anim:SetOrder(1)
	anim:SetScript('OnFinished', UpdateAllEnabledFrames)
	anim:SetDuration(0.025)
	if DebuffFilter.PlayerConfig.General.enabled then updater:Play() end

	if not DebuffFilter.PlayerConfig.General.disableOverlay then 
		DebuffFilter:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW")
		DebuffFilter:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE")
	end
end

-- stub to make AceAddon happy, perhaps not needed
function DebuffFilter:OnEnable()
end

function DebuffFilter:BeforeRefreshConfig()
	DebuffFilterFrame:GetAnimationGroups():Stop()
end

-- Profile has changed, so reinitialize addon
function DebuffFilter:RefreshConfig()
	
	-- configuration for current character, as read from the savedvariables file
	DebuffFilter.PlayerConfig = self.db.profile;

	for framename, v in pairs(DebuffFilter.enabledFramesList) do
		for buffs, j in pairs(v) do
			DebuffFilter.enabledFramesList[framename][buffs] = nil
		end
		DebuffFilter.enabledFramesList[framename] = nil
	end
	for framename, v in pairs(DebuffFilter.enabledCooldownsList) do
		DebuffFilter.enabledCooldownsList[framename] = nil
	end

	local frames = DebuffFilter.PlayerConfig.Frames
	-- create default frames in configuration if they don't exist
	for a, b in ipairs({"focus","target","player","targettarget"}) do
		if frames[b] == nil then
			frames[b] = {}
		end
		if frames[b].Buffs.frametarget == nil then
			frames[b].Buffs.frametarget = b
			frames[b].Debuffs.frametarget = b
		end
	end
	
	for k, targetFrames in pairs(DebuffFilter.Frames) do
		for i, targetBuffFrame in pairs(targetFrames) do
			if LBF then
				targetBuffFrame.buttonfacadeGroup:Delete()
			end	
			targetBuffFrame.frame:Hide()
		end
	end
	
	-- holds all widget objects, such as the frames and buttons
	DebuffFilter.Frames = {}

	DebuffFilterFrame:SetScale(DebuffFilter.PlayerConfig.General.scale)

	for k, v in pairs(options.args.Frames.args) do
		options.args.Frames.args[k] = nil
	end
	for k, v in pairs(options.args.Cooldowns.args.listCooldownFrames.args) do
		options.args.Cooldowns.args.listCooldownFrames.args[k] = nil
	end
	for k, v in pairs(options.args.General.args.listNewFrames.args) do
		options.args.General.args.listNewFrames.args[k] = nil
	end
	for k, v in pairs(options.args.Buffs.args) do
		options.args.Buffs.args[k] = nil
	end
	
	-- position where frames start to be placed 
	DebuffFilter.xvalues = { xvalue = 478, nextxvalue = 578};
	DebuffFilter.yvalue = 335;
	for k, Frame in pairs(DebuffFilter.PlayerConfig.Frames) do
		-- create entries for frames in dropdown menus
		options.args.Frames.args[k] = frameLayoutTabs
		DebuffFilter.Frames[k] = {}
		if Frame.Cooldowns.anchor then
			options.args.Cooldowns.args.listCooldownFrames.args[k] = newCooldownFrameName
			DebuffFilter:createCooldownFrame(k,"Cooldowns")
		else
			-- don't allow default frames to be listed, don't want to allow user to delete them
			if k ~= "player" and k ~= "target" and k ~= "focus" then
				options.args.General.args.listNewFrames.args[k] = newFrameName
			end
			options.args.Buffs.args[k] = frameBuffsTabs
			for a, b in ipairs({"Buffs","Debuffs"}) do
				DebuffFilter:createFrame(k, b)
			end
		end
		DebuffFilter:adjustAnchorPoints()
	end

	if (DebuffFilter.PlayerConfig.General.lock and not DebuffFilter.PlayerConfig.General.tooltips) then
		DebuffFilter_LockFrames(true);
	end

	if not DebuffFilter.PlayerConfig.General.enabled or DebuffFilter.PlayerConfig.General.combat and 
		not UnitAffectingCombat("player") then
			DebuffFilterFrame:Hide();
	end

	DebuffFilter:OnEnable()
	DebuffFilter:CheckForCooldownItemIDs()
	
	local groupID, frameitem, bfOptions
	for target, v in pairs(DebuffFilter.Frames) do
		for buffs, Frame in pairs(v) do
			if LBF then
				groupID = target.." "..buffs.." Frame"
				frameitem = DebuffFilter.Frames[target][buffs]
				frameitem.buttonfacadeGroup = LBF:Group("DebuffFilter", groupID)
				bfOptions = DebuffFilter.PlayerConfig.ButtonFacade[groupID]
				if bfOptions then
					frameitem.buttonfacadeGroup:Skin(unpack(bfOptions))
				end
			end	
		end
	end

	for framename, Cooldowns in pairs(DebuffFilter.PlayerConfig.Cooldowns) do
		for cooldownname, CooldownItem in pairs(Cooldowns.List) do
			DebuffFilter:CreateCooldownButton(framename, cooldownname)
		end
	end

	if DebuffFilter.PlayerConfig.General.enabled then DebuffFilterFrame:GetAnimationGroups():Play() end
end

function DebuffFilter:OnInitialize()
  	-- Code that you want to run when the addon is first loaded goes here.
	DebuffFilter:DebugTrace ("OnInitialize", true)
	
	-- I previously did not use profiles with Ace3.0, so I need to convert the DB
	if DebuffFilterDB and DebuffFilterDB.char ~= nil then
		for k, v in pairs(DebuffFilterDB.profileKeys) do
			DebuffFilterDB.profileKeys[k] = k
		end
		DebuffFilterDB.profiles = DebuffFilterDB.char
		DebuffFilterDB.char = nil
	end	
	
	-- create /dfilter command that enables changing options
	DebuffFilter:RegisterChatCommand("dfilter", "SlashProcessorFunc")
	-- options tables used to create options dialog
    self.optionsFrame = {}
    -- options tables are added to the Blizzard Interface Options panel
    -- only thing I add is function to open standalone dialog, because the Buffs panel is only ok in standalone dialog
    self.optionsFrame.BlizOptions = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("DebuffFilter", "DebuffFilter", nil, "BlizOptions")
    -- configuration settings read from savedvariables folder
    self.db = LibStub("AceDB-3.0"):New("DebuffFilterDB", DebuffFilter:InitDefaults())
	self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")
	self.db.RegisterCallback(self, "OnProfileShutdown", "BeforeRefreshConfig")
	options.args.Profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db)
	-- with libdualspec, can setup profiles to automatically change when changing specs
	local LibDualSpec = LibStub("LibDualSpec-1.0")
  	LibDualSpec:EnhanceDatabase(self.db, "DebuffFilter")
  	LibDualSpec:EnhanceOptions(options.args.Profiles, self.db)
	LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("DebuffFilter", options)
	
	-- configuration for current character, as read from the savedvariables file
	DebuffFilter.PlayerConfig = self.db.profile;

	-- used in update frame function if we are combining buffs and debuffs
	DebuffFilter.de_buffsList = {}
	-- stores already seen debuffs/buffs so that they can be combined and stacked
	DebuffFilter.already_seen_debuffs = {}
	-- stores (de)buffs and cooldowns that are to be displayed, so that they can be sorted
	DebuffFilter.buff_table_array = {}
	DebuffFilter.cd_table_array = {}
	DebuffFilter.ghost_timers = {}
	
	-- iterate over list and display each frame every 0.025 seconds
	DebuffFilter.enabledFramesList = {}
	DebuffFilter.enabledCooldownsList = {}

	-- create default frames in configuration if they don't exist
	for a, b in ipairs({"focus","target","player","targettarget"}) do
		if DebuffFilter.PlayerConfig.Frames[b] == nil then
			DebuffFilter.PlayerConfig.Frames[b] = {}
		end	
	end
	
	-- stores whether to grab the game's saved positions, of the xml frames from the old version of Debuff Filter
	DebuffFilter.portingXMLframes = false
	-- port settings from old version of Debuff Filter
	if DebuffFilter_Config then
		local DebuffFilter_Player = (UnitName("player").." - "..GetRealmName());
		local stri, ksub
		local buffOrDebuff, framename
		if DebuffFilter_Config[DebuffFilter_Player] then
			DebuffFilter.portingXMLframes = true
			for k, v in pairs(DebuffFilter_Config[DebuffFilter_Player]) do
				-- dont want to repeat code that checks what the frame name is, so i use ksub
				ksub = k
				if k:sub(1,4) == "all_" then
					ksub = k:sub(5)
				end

				buffOrDebuff = "Buffs"
				stri = ksub:find("debuff")
				if stri == nil then stri = ksub:find("buff") else buffOrDebuff = "Debuffs" end
				if stri == nil then
					DebuffFilter.PlayerConfig.General[k] = v
				else
					if stri == 1 then
						framename = "target"
					elseif stri == 2 and ksub:sub(1,1) == "p" then
						framename = "player"
					elseif stri == 2 and ksub:sub(1,1) == "f" then
						framename = "focus"
					end
					if k:sub(1,4) == "all_" then
						DebuffFilter.PlayerConfig.Buffs[framename][buffOrDebuff].showAllBuffs = v
					else
						if k:find("_layout") then
							for a, b in pairs(v) do
								DebuffFilter.PlayerConfig.Frames[framename][buffOrDebuff][a] = b
							end	
						elseif k:find("_list") then
							for a, b in pairs(v) do
								DebuffFilter.PlayerConfig.Buffs[framename][buffOrDebuff].List[a] = b
							end
						elseif k:sub(-1) == "s" then
							DebuffFilter.PlayerConfig.Buffs[framename][buffOrDebuff].enabled = v
						end
					end
				end
			end
			DebuffFilter_Config[DebuffFilter_Player] = nil
		end	
	end
	if DebuffFilter.PlayerConfig.General.cooldowncount == true then
		DebuffFilter.PlayerConfig.General.cooldowncount = false
		DebuffFilter.PlayerConfig.General.cooldown = DEBUFF_FILTER_COOLDOWN_ONLY
	end
			
	if LBF then
		-- buttonfacade callback
		LBF:RegisterSkinCallback("DebuffFilter", self.OnSkin, self)
	end

	-- holds all widget objects, such as the frames and buttons
	DebuffFilter.Frames = {}

	DebuffFilterFrame:SetScale(DebuffFilter.PlayerConfig.General.scale)

	-- position where frames start to be placed 
	DebuffFilter.xvalues = { xvalue = 478, nextxvalue = 578};
	DebuffFilter.yvalue = 335;
	for k, Frame in pairs(DebuffFilter.PlayerConfig.Frames) do
		-- create entries for frames in dropdown menus
		options.args.Frames.args[k] = frameLayoutTabs
		DebuffFilter.Frames[k] = {}
		if Frame.Cooldowns.anchor then
			options.args.Cooldowns.args.listCooldownFrames.args[k] = newCooldownFrameName
			DebuffFilter:createCooldownFrame(k,"Cooldowns")
		else
			-- Name of the frame used to be its target also, but addon was updated so frames could be duplicated.
			-- I had to move frametarget one level lower, since I replaced Buffs and Debuffs with ['**'] for the defaults DB
			if Frame.Buffs.frametarget == nil then
				-- if frametarget is nil, it will be a table, because I use ['**']
				if type(Frame.frametarget) == "table" then
					Frame.Buffs.frametarget = k
					Frame.Debuffs.frametarget = k
				else
					Frame.Buffs.frametarget = Frame.frametarget
					Frame.Debuffs.frametarget = Frame.frametarget
					Frame.frametarget = nil
				end
			end
			-- don't allow default frames to be listed, don't want to allow user to delete them
			if k ~= "player" and k ~= "target" and k ~= "focus" then
				options.args.General.args.listNewFrames.args[k] = newFrameName
			end
			options.args.Buffs.args[k] = frameBuffsTabs
			for a, b in ipairs({"Buffs","Debuffs"}) do
				DebuffFilter:createFrame(k, b)
			end
		end
		DebuffFilter:adjustAnchorPoints()
	end

	if (DebuffFilter.PlayerConfig.General.lock and not DebuffFilter.PlayerConfig.General.tooltips) then
		DebuffFilter_LockFrames(true);
	end

	DebuffFilter:RegisterEvent("PLAYER_REGEN_DISABLED");
	DebuffFilter:RegisterEvent("PLAYER_REGEN_ENABLED");

	if not DebuffFilter.PlayerConfig.General.enabled or DebuffFilter.PlayerConfig.General.combat and 
		not UnitAffectingCombat("player") then
			DebuffFilterFrame:Hide();
	end

	DebuffFilter:RegisterEvent("VARIABLES_LOADED")
	DebuffFilter:RegisterEvent("PLAYER_LOGIN")

	DebuffFilter:DebugTrace ("OnInitialize")

end

local createFrameAndAnchorIt = function(framename,buff)
	local frames = DebuffFilter.PlayerConfig.Frames
	local frameitem = DebuffFilter.Frames[framename][buff]

	-- do this because perhaps the variable might still point to old frame otherwise
	if _G["DebuffFilter"..framename..buff.."Count"] ~= nil then _G["DebuffFilter"..framename..buff.."Count"] = nil end
	frameitem.frame = CreateFrame("Frame","DebuffFilter"..framename..buff,nil,"DebuffFilter_FrameTemplate");
	-- needed so that when a button is clicked, I can grab the frame's name and buff, so I can get layout information
	frameitem.frame.DBFframename = framename
	frameitem.frame.DBFbuffOrDebuff = buff
	frameitem.frameBackdrop = CreateFrame("Button",nil,frameitem.frame,"DebuffFilter_BackdropTemplate");
	frameitem.frameBackdropTitle = frameitem.frameBackdrop:CreateFontString(nil,"ARTWORK","DebuffFilter_NameTemplate");
	frameitem.frameBackdropTitle:SetText(framename .. " " ..buff);

	local frameLayout = frames[framename][buff]
	
	frameitem.frame:SetScale(frameLayout.scale)
	if frameLayout.anchor == nil then
		frameLayout.anchor = {"TOPLEFT","UIParent","BOTTOMLEFT",DebuffFilter.xvalues.xvalue,DebuffFilter.yvalue}
		
		local parentMaxY = DebuffFilterFrame:GetParent():GetTop() / DebuffFilter.PlayerConfig.General.scale
		local parentMaxX = DebuffFilterFrame:GetParent():GetRight() / DebuffFilter.PlayerConfig.General.scale
		local frameWidth = frameitem.frame:GetWidth()
		if (DebuffFilter.xvalues.xvalue + frameWidth) > parentMaxX then
			frameLayout.anchor[4] = parentMaxX - frameWidth
		end
		if DebuffFilter.yvalue > parentMaxY then
			frameLayout.anchor[5] = parentMaxY
		end
	end	

	frameitem.frame:ClearAllPoints();
	frameitem.frame:SetPoint(unpack(frameLayout.anchor));
	-- cooldowns only have 1 frame, so next frame goes at the same x, not the nextx
	if buff ~= "Cooldowns" then DebuffFilter:swapXvalues() end
end

function DebuffFilter:createFrame(framename, buff)
	
	DebuffFilter.Frames[framename][buff] = {}
	local frameitem = DebuffFilter.Frames[framename][buff]

	frameitem.buttons = {}
	frameitem.buffsFromLastIteration = {}
	frameitem.buffsFromLastIterationCount = 0
	
	-- store only the (de)buff groups that user selected in comparisonlist, so that other comparisons
	-- can be skipped when filtering
	frameitem.Comparisons = {}
	frameitem.ComparisonList = {}
	local fc = frameitem.ComparisonList
	local sb = DebuffFilter.PlayerConfig.Buffs[framename][buff]
	if sb.showAllMyBuffs then fc.showAllMyBuffs = {name="ismine",value=true} end
	if sb.showAllStealableBuffs then fc.showAllStealableBuffs = {name="isStealable",value=1} end
	if sb.showAllMagicBuffs then fc.showAllMagicBuffs = {name="debufftype",value="Magic"} end
	if sb.showAllPoisonBuffs then fc.showAllPoisonBuffs = {name="debufftype",value="Poison"} end
	if sb.showAllDiseaseBuffs then fc.showAllDiseaseBuffs = {name="debufftype",value="Disease"} end
	if sb.showAllCurseBuffs then fc.showAllCurseBuffs = {name="debufftype",value="Curse"} end
	
	createFrameAndAnchorIt(framename, buff)
	
	-- hide a frame that the player unchecked
	if (not DebuffFilter.PlayerConfig.Buffs[framename][buff].enabled) then
		frameitem.frame:Hide();
	else
		if not DebuffFilter.enabledFramesList[framename] then
			DebuffFilter.enabledFramesList[framename] = {}
		end
		DebuffFilter.enabledFramesList[framename][buff] = true
	end

	if (DebuffFilter.PlayerConfig.General.backdrop) then
		frameitem.frameBackdrop:Show()
	end

	-- number of debuffs/buffs for a frame, including those not shown
	frameitem.frameCount = _G["DebuffFilter"..framename..buff.."Count"];
	if (DebuffFilter.PlayerConfig.General.count) then
		frameitem.frameCount:Show();
	end

	-- position frameCount
	DebuffFilter_SetCountOrientation(DebuffFilter.PlayerConfig.Frames[framename][buff], frameitem);
end

function DebuffFilter:createCooldownFrame(framename, buff)
	DebuffFilter.Frames[framename][buff] = {}
	local frameitem = DebuffFilter.Frames[framename][buff]

	frameitem.buttons = {}
	-- stores button indices for cooldowns, so that cooldown buttons can be rearranged
	frameitem.buttonsbyspell = {}
	
	createFrameAndAnchorIt(framename, buff)
	
	if DebuffFilter.PlayerConfig.Cooldowns[framename].enabled then
		DebuffFilter.enabledCooldownsList[framename] = true
	else
		frameitem.frame:Hide();
	end

	if (DebuffFilter.PlayerConfig.General.backdrop) then
		frameitem.frameBackdrop:Show()
	end
end

function DebuffFilter:SlashProcessorFunc(input)
	DebuffFilter:DebugTrace ("SlashProcessorFunc", true)
  	-- Process the slash command ('input' contains whatever follows the slash command)
	if not input or input:trim() == "" then
		-- open addon's options in the Blizzard Interface Options panel
		--InterfaceOptionsFrame_OpenToCategory(self.optionsFrame.General)
		DebuffFilter:OpenConfigDialog()
	elseif input == "help" then
		DEFAULT_CHAT_FRAME:AddMessage("Debuff Filter commands:");
		DEFAULT_CHAT_FRAME:AddMessage("/dfilter: display the configuration menu in Blizzard's Interface Options panel.");
		DEFAULT_CHAT_FRAME:AddMessage("/dfilter |cff00ccffdialog|r: display configuration menu in a standalone panel.");
		DEFAULT_CHAT_FRAME:AddMessage("To move the frames, shift+left click and drag a backdrop or a monitored debuff/buff.");
		DEFAULT_CHAT_FRAME:AddMessage("To change a time orientation, ctrl+right click.");
	end
	DebuffFilter:DebugTrace ("SlashProcessorFunc")
end

-- this is a standalone dialog, it can be resized and moved, so user can see his config changes
function DebuffFilter:OpenConfigDialog()
	InterfaceOptionsFrame:Hide()
	-- BlizOptions are only shown through Blizzard's Interface panel, it is used to open this standalone dialog
	options.args.BlizOptions.hidden = true
	DebuffFilter.Container = LibStub("AceGUI-3.0"):Create("Frame")
	-- gotta create a new container, and then release it always, otherwise a bug can occur where you
	-- close, but the execute buttons are still visible, and still work!  (like delete)
	DebuffFilter.Container:SetCallback("OnClose",function(widget) options.args.BlizOptions.hidden = false 
			LibStub("AceGUI-3.0"):Release(DebuffFilter.Container)
		end)
	LibStub("AceConfigDialog-3.0"):Open("DebuffFilter",DebuffFilter.Container)
	local parentMaxY = DebuffFilterFrame:GetParent():GetTop()
	if 650 < parentMaxY then DebuffFilter.Container:SetHeight(650) end
end
