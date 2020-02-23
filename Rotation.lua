local DMW = DMW
local Hunter = DMW.Rotations.HUNTER
local Rotation = DMW.Helpers.Rotation
local Setting = DMW.Helpers.Rotation.Setting
local Player, Pet, Buff, Debuff, Spell, Target, Talent, Item, GCD, Health, CDs, HUD, Enemy20Y, Enemy20YC, Enemy30Y, Enemy30YC ,CTime
local ShotTime = GetTime()

local castingAimedShot = false

local quiverSpeed = 1.00
local aimedCastTime = 3500;
local multiCastTime = 500;

local bagSlots = {20, 21, 22, 23};
local updateRequired = false;

local infight = false
local FHowlPetButton = nil

local function Locals()
    Player = DMW.Player
    Buff = Player.Buffs
	CTimer = Player.CombatTime
    Debuff = Player.Debuffs
	Health = Player.Health
	Pet = DMW.Player.Pet
    HP = Player.HP
    Power = Player.PowerPct
    --PetPower = Pet.PowerPct
    Spell = Player.Spells
    Talent = Player.Talents
    Trait = Player.Traits
    Item = Player.Items
    Target = Player.Target or false
    HUD = DMW.Settings.profile.HUD
    CDs = Player:CDs()
	GCD = Player:GCD()
	Enemy40Y, Enemy40YC = Player:GetEnemies(40)
	Enemy20Y, Enemy20YC = Player:GetEnemies(20)
    Enemy30Y, Enemy30YC = Player:GetEnemies(30)
    Player40Y, Player40YC = Player:GetEnemies(40)
 end



--SpellId 26635 Berserking
local function GetBerserkingHaste()
	return math.min((1.30 - (UnitHealth("player") / UnitHealthMax("player"))) / 3, 0.3) + 1;
end

local helpfulRangeModifiers = {
	[3045] = 1.4, -- rapid fire
	[6150] = 1.3, -- quick shots
	[28866] = 1.2, -- naxx trinket
};

local harmfulRangeModifiers = {
	[89] = 1.45, -- cripple
	[19365] = 2.0, -- MC core hound debuff
	[17331] = 1.1, -- LBRS dagger proc
};

local sAimedShot = GetSpellInfo(19434);
local sMultiShot = GetSpellInfo(2643);


local castTime = 0;
local icon = 0;

local startTime = 0
local endTime = 0;

local dStart = 0;
local dPred = 0;

local bossenraged = false

local quiver = {}    --Blizzard's API does not allow me to determine haste from quiver so I have to do it manually.
quiver[2101]  = 1.10 --Light Quiver
quiver[2102]  = 1.10 --Small Ammo Pouch
quiver[2662]  = 1.14 --Ribbly's Quiver
quiver[2663]  = 1.14 --Ribbly's Bandolier
quiver[3573]  = 1.10 --Hunting Quiver
quiver[3574]  = 1.10 --Hunting Ammo Sack
quiver[3604]  = 1.11 --Bandolier of the Night Watch
quiver[3605]  = 1.11 --Quiver of the Night Watch
quiver[5439]  = 1.10 --Small Quiver
quiver[5441]  = 1.10 --Small Shot Pouch
quiver[7278]  = 1.10 --Light Leather Quiver
quiver[7279]  = 1.10 --Small Leather Ammo Pouch
quiver[7371]  = 1.12 --Heavy Quiver
quiver[7372]  = 1.12 --Heavy Leather Ammo Pouch
quiver[8217]  = 1.13 --Quickdraw Quiver
quiver[8218]  = 1.13 --Thick Leather Ammo Pouch
quiver[11362] = 1.10 --Medium Quiver
quiver[11363] = 1.10 --Medium Shot Pouch
quiver[18714] = 1.15 --Ancient Sinew Wrapped Lamina
quiver[19319] = 1.15 --Harpy Hide Quiver
quiver[19320] = 1.15 --Gnoll-Skin Bandolier



--could use GetRangedHaste() but it updates too slowly
local function GetCurrentRangeHaste()
	
	local speed = quiverHaste;
	
	local stop = 0;
	for i = 1, 40 do
		if(stop ~= 1) then
			local spellId = select(10, UnitAura("player", i, "HELPFUL"))
			if(spellId == nil) then
				stop = stop + 1;
			else
				local coef = spellId == 26635 and GetBerserkingHaste() or helpfulRangeModifiers[spellId];
				if(coef) then
					speed = speed * coef;
				end
			end
		end
		
		if(stop < 2) then
			local spellId = select(10, UnitAura("player", i, "HARMFUL"))
			if(spellId == nil) then
				stop = stop + 2;
			else
				local div = harmfulRangeModifiers[spellId]
				if(div) then
					speed = speed / div;
				end
			end
		end
	
		if(stop == 3) then
			break;
		end
	end
	
	return speed;
end
 
	
local function GetQuiverInfo()
	quiverHaste = 1.0
	for i = 1, 4 do
		local invID = ContainerIDToInventoryID(i)  
		local bagID = GetInventoryItemID("player",invID)
		if (bagID ~= nil) then
			if (quiver[bagID]) then
				if (quiverHaste < quiver[bagID]) then
					quiverHaste = quiver[bagID]
				end
			end
		end
	end
	updateRequired = false;
end 


 
local function CombatLogEvent(...)
	local timeStamp, subEvent, _, sourceID, _, _, _, targetID = ...;
	

	if(subEvent == "SPELL_CAST_START") then
		if(sourceID ~= UnitGUID("player")) then return end

		local spellName = select(13, ...);
		--print(spellName)
		
		if(spellName == sAimedShot) then
			castTime = aimedCastTime;
			castingAimedShot = true
		elseif(spellName == sMultiShot) then
			castTime = multiCastTime;
		else
			return;
		end
		
		if(updateRequired) then
			GetQuiverInfo()
		end
		
		castTime = castTime / GetCurrentRangeHaste();
		
		startTime = GetTime() * 1000;
		endTime = startTime + castTime;
		
		dStart = GetTime();
		dPred = dStart + castTime;
		
	elseif(subEvent == "SPELL_CAST_SUCCESS") then
		if(sourceID ~= UnitGUID("player")) then return end
		
		local spellName = select(13, ...);
		
		if(spellName == sAimedShot or spellName == sMultiShot) then
			castingAimedShot = false
		end
	end
end

local function SpellInterrupted(source, castGUID, spellID)
	if(source ~= "player") then return end
	
	local spellName = GetSpellInfo(spellID);
	
	if(spellName == sAimedShot or spellName == sMultiShot) then
		castingAimedShot = false
		
	end
end


local function ifMSG(msg, targetName)
	if not infight then return end
	if msg == "Enrage" 
	and not bossenraged	
	and (targetName == "Magmadar"
	    or targetName == "Flamegor"
	    or targetName == "Chromaggus"
	    or targetName == "Princess Huhuran"
	    or targetName == "Gluth")
	then
		bossenraged = true
	elseif msg == "EnrageStop" 
	    and bossenraged
	    then
    	bossenraged = false
	end
	--print(bossenraged)
end
 
 
 
 local function Auto()
 --Autoshot
	if not IsAutoRepeatSpell(Spell.AutoShot.SpellName) 
	and (DMW.Time - ShotTime) > 0.5 
	and Target.Distance > 8 
	and Spell.AutoShot:Cast(Target) 
	and not castingAimedShot
	then
	StartAttack()
	ShotTime = DMW.Time
	return true
		end
  end

local function Defensive()
 --Aspect of the Monkey
	 if  Setting("Aspect Of The Monkey") 
	 and Player.Combat  
	 and Player.HP < Setting("Aspect of the Monkey HP") 
	 and Player.PowerPct > 20  
	 and Target.Distance < 8 
	 and not Buff.AspectOfTheMonkey:Exist(Player)
	 and not castingAimedShot
	 and not Player.Casting
	 and Spell.AspectOfTheMonkey:Cast(Player) then
		return true 
	end
end




local function Utility()
	Locals()
-- Pet management
	if Setting("Call Pet") 
	and (not Pet or Pet.Dead) 
	and not castingAimedShot
	and not Player.Casting	
	and Spell.CallPet:Cast(Player) then
            return true 
	end

--Mend Pet
	if Setting("Mend Pet") 
	and Player.Combat 
	and not Player.Moving 
	and Pet and not Pet.Dead 
	and Pet.HP <= Setting("Mend Pet HP") 
	and Player.PowerPct > 30 
	and not castingAimedShot
	and not Player.Casting
	and Spell.MendPet:Cast(Pet) then
        return true
	end

	-- Revive Pet	find a way to check if we dont have active pet or dismissed it .
	--if Setting("Revive Pet") and (Pet.Dead) and Spell.RevivePet:Cast(Player) then
    --     return true 
	--end
	
-- Aspect of the Cheetah
	if Setting("Aspect Of The Cheetah") 
	and not Player.Combat 
	and Player.CombatLeftTime > 8 
	and not Spell.AspectOfTheHawk:LastCast() 
	and Player.Moving 
	and not Buff.AspectOfTheCheetah:Exist(Player) 
	and Spell.AspectOfTheCheetah:Cast(Player) then
		return true
	end

-- Trueshot Selfbuff

	if Setting("TrueShot Buff") 
	and not Player.Combat 
	and not Buff.TrueshotAura:Exist(Player) 
	and Player.PowerPct > 80 
	and Spell.TrueshotAura:Cast(Player) then
		return true
	end
	

-- Use best available Healf potion --
	if Setting("Use Best HP Potion") then
		if HP <= Setting("Use Potion at #% HP") and Player.Combat then
			if GetItemCount(13446) >= 1 and GetItemCooldown(13446) == 0 then
				name = GetItemInfo(13446)
				RunMacroText("/use " .. name)
				return true 
			elseif GetItemCount(3928) >= 1 and GetItemCooldown(3928) == 0 then
				name = GetItemInfo(3928)
				RunMacroText("/use " .. name)
				return true
			elseif GetItemCount(1710) >= 1 and GetItemCooldown(1710) == 0 then
				name = GetItemInfo(1710)
				RunMacroText("/use " .. name)
				return true
			elseif GetItemCount(929) >= 1 and GetItemCooldown(929) == 0 then
				name = GetItemInfo(929)
				RunMacroText("/use " .. name)
				return true
			elseif GetItemCount(858) >= 1 and GetItemCooldown(858) == 0 then
				name = GetItemInfo(858)
				RunMacroText("/use " .. name)
				return true
			elseif GetItemCount(118) >= 1 and GetItemCooldown(118) == 0 then
				name = GetItemInfo(118)
				RunMacroText("/use " .. name)
				return true
			end
		end
	end
	
-- Use Demonic or Dark Rune --
	if Setting("Use Demonic or Dark Rune") and Target and Target.ValidEnemy and Target.TTD > 6 and Target:IsBoss() and HP > 60 then
		if Power <= Setting("Use Rune at #% Mana") and Player.Combat then
			if GetItemCount(12662) >= 1 and GetItemCooldown(12662) == 0 then
				name = GetItemInfo(12662)
				RunMacroText("/use " .. name)
				return true 
			elseif GetItemCount(20520) >= 1 and GetItemCooldown(20520) == 0 then
				name = GetItemInfo(20520)
				RunMacroText("/use " .. name)
				return true	
			end
		end
	end	

-- Use best available Mana potion --
	if Setting("Use Best Mana Potion") and Target and Target.ValidEnemy and Target.TTD > 6 and Target:IsBoss() then
		if Power <= Setting("Use Potion at #% Mana") and Player.Combat then
			if GetItemCount(13444) >= 1 and GetItemCooldown(13444) == 0 then
				name = GetItemInfo(13444)
				RunMacroText("/use " .. name)
				return true 
			elseif GetItemCount(13443) >= 1 and GetItemCooldown(13443) == 0 then
				name = GetItemInfo(13443)
				RunMacroText("/use " .. name)
				return true
			elseif GetItemCount(6149) >= 1 and GetItemCooldown(6149) == 0 then
				name = GetItemInfo(6149)
				RunMacroText("/use " .. name)
				return true
			elseif GetItemCount(3827) >= 1 and GetItemCooldown(3827) == 0 then
				name = GetItemInfo(3827)
				RunMacroText("/use " .. name)
				return true
			elseif GetItemCount(3385) >= 1 and GetItemCooldown(3385) == 0 then
				name = GetItemInfo(3385)
				RunMacroText("/use " .. name)
				return true
			elseif GetItemCount(2455) >= 1 and GetItemCooldown(2455) == 0 then
				name = GetItemInfo(2455)
				RunMacroText("/use " .. name)
				return true
			end
		end
	end
 end
 
 local function findPetButton()

			if GetPetActionInfo(1) == (GetSpellInfo(24597) or GetSpellInfo(24604) or GetSpellInfo(24605) or GetSpellInfo(24603))
			then 
				FHowlPetButton = 1
				return true
			elseif GetPetActionInfo(2) == (GetSpellInfo(24597) or GetSpellInfo(24604) or GetSpellInfo(24605) or GetSpellInfo(24603))
			then 
				FHowlPetButton = 2
				return true
			elseif GetPetActionInfo(3) == (GetSpellInfo(24597) or GetSpellInfo(24604) or GetSpellInfo(24605) or GetSpellInfo(24603))
			then 
				FHowlPetButton = 3
				return true
			elseif GetPetActionInfo(4) == (GetSpellInfo(24597) or GetSpellInfo(24604) or GetSpellInfo(24605) or GetSpellInfo(24603))
			then 
				FHowlPetButton = 4
				return true
			elseif GetPetActionInfo(5) == (GetSpellInfo(24597) or GetSpellInfo(24604) or GetSpellInfo(24605) or GetSpellInfo(24603))
			then 
				FHowlPetButton = 5
				return true
			elseif GetPetActionInfo(6) == (GetSpellInfo(24597) or GetSpellInfo(24604) or GetSpellInfo(24605) or GetSpellInfo(24603))
			then 
				FHowlPetButton = 6
				return true
			elseif GetPetActionInfo(7) == (GetSpellInfo(24597) or GetSpellInfo(24604) or GetSpellInfo(24605) or GetSpellInfo(24603))
			then 
				FHowlPetButton = 7
				return true
			elseif GetPetActionInfo(8) == (GetSpellInfo(24597) or GetSpellInfo(24604) or GetSpellInfo(24605) or GetSpellInfo(24603))
			then 
				FHowlPetButton = 8
				return true
			elseif GetPetActionInfo(9) == (GetSpellInfo(24597) or GetSpellInfo(24604) or GetSpellInfo(24605) or GetSpellInfo(24603))
			then 
				FHowlPetButton = 9
				return true
			elseif GetPetActionInfo(10) == (GetSpellInfo(24597) or GetSpellInfo(24604) or GetSpellInfo(24605) or GetSpellInfo(24603))
			then 
				FHowlPetButton = 10
				return true
			end
end		
 
 
--FuriousHowl by Pet
local function petbuff()
		Locals()
		if Setting("FuriousHowl if pulled back")
		--and PetPower >= 60
		and findPetButton()
		and Player.Combat
		and (GetPetActionCooldown(FHowlPetButton) == 0)
		and Setting("Pet Pullback at mend Pet HP")
		and (Pet.HP < Setting("Mend Pet HP") or HUD.PetAttack == 2) 
		and Pet and not Pet.Dead
		and CTimer > 5
		then
		        CastPetAction(FHowlPetButton)
		end
end
 
 
local function Shots()	
	Locals()

--Auto Shot		
		if Player.Combat
		    then
		    infight = true
		elseif not Player.Combat
		    then 
		    infight = false
		end
						
		if  Target.Facing then  
		
			Auto() 
		end		
		
--TranquilizingShot (if Boss goes Enraged)
		if Setting("Tranq Shot")
		    and Spell.TranquilizingShot:Known()
			and Spell.TranquilizingShot:IsReady()
		    and bossenraged
	    	and Target.Facing 
	    	and Target.Distance > 8
	    	and not castingAimedShot
	        and not Player.Casting
	    	and not (Target.CreatureType == "Totem") 
	    	and Spell.TranquilizingShot:Cast(Target) then
			    return true
		end		
		


--Concussive Shot  ( fix if mob targets you  or pet lost threat)
		if Setting("Concussiv Shot") 
	    	and Target.Distance < Setting("Concussiv Shot Distance") 
	    	and Target.Facing 
	    	and Target.Distance > 8
	    	and not castingAimedShot
	        and not Player.Casting
	    	and not (Target.CreatureType == "Totem") 
	    	and Spell.ConcussiveShot:Cast(Target) then
			    return true
		end

--Serpent Sting
		if Setting("Serpent Sting") 
	    	and HUD.Serpent == 1 
	    	and Target.Facing 
	    	and not Player.Casting
	    	and not castingAimedShot
	    	and Target.Distance > 8  
	    	and Player.PowerPct > 6 
	    	and Target.TTD > 5
	    	and not (Target.CreatureType == "Mechanical" or Target.CreatureType == "Elemental" or CreatureType == "Totem") 
	    	and not Debuff.SerpentSting:Exist(Target) 
	    	and Spell.SerpentSting:Cast(Target) then
                return true
        end
		
--Aimed shot Clipped Rotation
		
		if Setting("Aimed Shot")
		    and Setting("Clipped Rotation") 
		    and Target.Facing 
		    and not Player.Casting
		    and Spell.AimedShot:IsReady()
		    and not Spell.AimedShot:LastCast()
		    and Target.Distance > 8 
		    and Player.PowerPct > 4 
		    and Target.TTD > 6
		    and not (Target.CreatureType == "Totem") 
		    and not Player.Moving
			and not castingAimedShot
		    and Spell.AimedShot:Cast(Target) 		
		then
			    RunMacroText("/cleartarget")
                RunMacroText("/targetlasttarget")
                return true

		elseif Setting("Aimed Shot")
		    and Target.Facing 
		    and not Player.Casting
		    and Spell.ArcaneShot:IsReady()
		    and Target.Distance > 8 
		    and Player.PowerPct > 4 
		    and not (Target.CreatureType == "Totem") 
		    and Player.Moving and Spell.ArcaneShot:Cast(Target)
		then
                return true
        end	
		
--Aimed shot full Rotation
		if Setting("Aimed Shot") 
		    and not Setting("Clipped Rotation") 
		    and Target.Facing 
		    and not Player.Casting
		    and Spell.AimedShot:IsReady()
		    and not Spell.AimedShot:LastCast()
		    and Spell.AutoShot:LastCast()
		    and Target.Distance > 8 
		    and Player.PowerPct > 4 
		    and Target.TTD > 6
		    and not (Target.CreatureType == "Totem") 
		    and not Player.Moving 
			and not castingAimedShot
		    and Spell.AimedShot:Cast(Target) 		
		then
			    RunMacroText("/cleartarget")
                RunMacroText("/targetlasttarget")			
                return true
		elseif Setting("Aimed Shot")
		    and Target.Facing 
		    and not Player.Casting
		    and Spell.ArcaneShot:IsReady()
		    and Target.Distance > 8 
		    and Player.PowerPct > 4 
		    and not (Target.CreatureType == "Totem") 
		    and Player.Moving and Spell.ArcaneShot:Cast(Target)
		then
                return true
        end	

--Multi shot Clipped Rotation
		if Setting("Multi Shot")
		    and Setting("Clipped Rotation")
		    and HUD.Multi == 1 
		    and Target.Facing 
		    and not Player.Casting
		    and Spell.MultiShot:IsReady()
		    and Target.Distance > 8 
		    and Player.PowerPct > 4
		    and Target.TTD > 2
		    and not (Target.CreatureType == "Totem") 
		    and not Player.Moving 
			and not castingAimedShot
		    and Spell.MultiShot:Cast(Target) then
                return true
        end		

--Multi shot full Rotation	
		if Setting("Multi Shot")
		    and not Setting("Clipped Rotation") 
		    and HUD.Multi == 1 
		    and Target.Facing 
		    and not Player.Casting
		    and Spell.MultiShot:IsReady()
	    	and Target.Distance > 8 
	    	and Player.PowerPct > 4
	    	and Target.TTD > 2 
	    	and not (Target.CreatureType == "Totem") 
	    	and not Player.Moving 
			and not castingAimedShot			
	    	and Spell.MultiShot:Cast(Target) then
                return true
        end	
			
--Arcane Shot	
		if Setting("Arcane Shot") 
	    	and Target.Facing 
	    	and not Player.Casting
	    	and Spell.ArcaneShot:IsReady()
	    	and Target.Distance > 8 
	    	and Player.PowerPct > 4 
	    	and not (Target.CreatureType == "Totem")
			and not castingAimedShot			
	    	and Spell.ArcaneShot:Cast(Target) then
                return true
		end		
end  




local function huntermeleeattacks()	
	Locals()
--Melee
		if  Target.Distance < 6 and  Target.Facing  then
		    StartAttack()
		end			
--Raport Strike
		if  Target.Facing and  Target.Distance < 5 and  Target.TTD > 2 and Spell.RaptorStrike:Cast(Target) then
			return true	
		end
--Wing Clip
		if  Target.Facing and  Target.Distance < 5 and not Debuff.WingClip:Exist(Target) and not (Target.CreatureType == "Totem") and Spell.WingClip:Cast(Target) then
			return true	
		end	
--Mongoose Bite		
		if Target.Facing and  Target.Distance < 5  and Spell.MongooseBite:IsReady() and Spell.MongooseBite:Cast(Target) then
			return true	
		end	
end	


function Hunter.Rotation()
    Locals()

		if Utility() then
			return true 
		end
		
    if Target and Target.ValidEnemy and Target.Distance < 41 then
		if Defensive() then
			return true
		end

--Aspect of the Hawk
		if Setting("Aspect of the Hawk") and Target.Facing and not Player.Casting and not castingAimedShot and Target.Distance > 8 and (not Buff.AspectOfTheHawk:Exist(Player) or Buff.AspectOfTheMonkey:Exist(Player)) and Player.PowerPct > 30 and Spell.AspectOfTheHawk:Cast(Player) then
			return true
		end	 
		
--Pet Auto		
        if Setting("Auto Pet Attack")
			and HUD.PetAttack == 1 
            and not Setting("Pet Pullback at mend Pet HP") 
            and Pet and not Pet.Dead 
            and not UnitIsUnit(Target.Pointer, "pettarget") 
            then
        PetAttack()
            elseif Setting("Auto Pet Attack")
                and Setting("Pet Pullback at mend Pet HP")
                and Pet and not Pet.Dead 
                --and not UnitIsUnit(Target.Pointer, "pettarget")
                and Pet.HP < Setting("Mend Pet HP")
                then
            PetPassiveMode()
                elseif Setting("Auto Pet Attack")
                and Setting("Pet Pullback at mend Pet HP")
				and HUD.PetAttack == 1
                and Pet and not Pet.Dead 
                and not UnitIsUnit(Target.Pointer, "pettarget")
                and Pet.HP > Setting("Send Pet back in")
                then
                PetAttack() 
        end
		
--Hunter's Mark
        if Setting("HuntersMark")
		and HUD.Mark == 1 
        and Target.Facing 
        and not Player.Casting
        and not castingAimedShot
        and Target.Distance < 100 
        and Target.TTD > 10 
		--and not Spell.HuntersMark:LastCast() 
        and not Debuff.HuntersMark:Exist(Target) 
        and not (Target.CreatureType == "Totem")  
        and Spell.HuntersMark:Cast(Target) then
                return true
				
            end
		
	
		petbuff()

		
--Shots fired or Switch Meele	
		
				
		if Target.Facing and Setting("Seconds for PetAggro") == 0 and Target.Distance < 41 and Target.Distance > 8 then
		Shots()
		elseif Target.Facing and Setting("Seconds for PetAggro") > 0 and CTimer >= Setting("Seconds for PetAggro") and Target.Distance < 41 and Target.Distance > 8 then 
		Shots()
		elseif Target.Facing and Target.Distance <= 8 and Target.Distance >= 6 then
		StopAttack()
		elseif Target.Facing and Target.Distance < 6 then
		huntermeleeattacks()
		
		end	
   	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
eventFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED");
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
eventFrame:RegisterEvent("CHAT_MSG_ADDON");

eventFrame:SetScript("OnEvent", function(self, event, ...)
	if(event == "COMBAT_LOG_EVENT_UNFILTERED" ) then
		CombatLogEvent(CombatLogGetCurrentEventInfo());
	elseif(event == "UNIT_SPELLCAST_INTERRUPTED") then
		SpellInterrupted(...);
	elseif(event == "PLAYER_ENTERING_WORLD") then
		GetQuiverInfo();
		updateRequired = true;
	elseif(event == "CHAT_MSG_ADDON") then
	    ifMSG(msg, targetName)
	end
end) 