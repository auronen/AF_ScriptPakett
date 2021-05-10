/*
 *	Torch HotKey
 *		- enables hotkey 'keyTorchToggleKey' equipping torches
 *		- 'keyTorchToggleKey' can be defined either in Gothic.ini file section [KEYS] or mod.ini file section [KEYS] (master is Gothic.ini)
 *		- if 'keyTorchToggleKey' is not defined then by default KEY_T will be used for toggling
 *		- fixes issue of disappearing torches in G2A
 *			- number of torches will be stored prior game saving
 *			- when game is loaded script will compare number of torches in players inventory, if there is torch missing it will add it back
 *			- reinserts to world ItLsTorchBurning items before saving (fixes bug of disappearing dropped torches) and before level change
 *		- compatible with sprint mode (reapplies overlay HUMANS_SPRINT.MDS when torch is removed/equipped)
 *		- will re-lit all mobs, that were previously lit by player (list can be maintained in file 'torchHotKey_API.d' in array TORCH_ASC_MODELS [];
 *		- Ctrl + 'keyTorchToggleKey' will put torch to right hand (with Union you can throw torch away in G1)
 */

var int PC_CarriesTorch;
var int PC_NumberOfTorches;

func int MobIsTorch__TorchHotKey (var int mobPtr) {
	//0x007DD9E4 const oCMobFire::`vftable' 
	if (!Hlp_Is_oCMobFire (mobPtr)) { return FALSE; };

	if (!TORCH_ASC_MODELS_MAX) { return FALSE; };

	//Get visual name
	var string mobVisualName; mobVisualName = Vob_GetVisualName (mobPtr);

	//Check if this is indeed torch/mob for which we want to restore it's state
	repeat (i, TORCH_ASC_MODELS_MAX); var int i;
		var string testVisual; testVisual = MEM_ReadStatStringArr (TORCH_ASC_MODELS, i);
		if (Hlp_StrCmp (mobVisualName, testVisual)) {
			return TRUE;
		};
	end;

	return FALSE;
};

func void ReInsertBurningTorches__TorchHotKey () {
	var int vobPtr;
	
	//Create array
	var int vobListPtr; vobListPtr = MEM_ArrayCreate ();

	//Search by zCVisual or zCParticleFX does not work
	if (!SearchVobsByClass ("oCItem", vobListPtr)) {
		MEM_Info ("No oCItem objects found.");
		return;
	};
	
	var int counter; counter = 0;
	var zCArray vobList; vobList = _^ (vobListPtr);

	var int ptr;

	//Loop through all objects
	var int i; i = 0;
	var int count; count = vobList.numInArray;

	//we have to use separate variable here for count
	while (i < count);
		//Read vobPtr from vobList array
		vobPtr = MEM_ArrayRead (vobListPtr, i);

		if (Hlp_Is_oCItem (vobPtr)) {
			var oCItem itm; itm = _^ (vobPtr);

			if (Hlp_IsValidItem (itm)) {
				var int amount; amount = itm.amount;

				//G1 does not have this one - so define locally because of parsing
				const int ITEM_DROPPED = 1 << 10;

				//This function cannot be called in G1, G1 torches which are in hand have same flag value 1 << 10 (const int ITEM_BURN = 1 << 10;)
				//Luckily in G1 torches work fine :)
				
				//All dropped ItLsTorchBurning do have ITEM_DROPPED flag - so we can use this
				if ((Hlp_GetInstanceID (itm) == ItLsTorchBurning) && (amount) && (itm.flags & ITEM_DROPPED)) {
					//Get item trafo
					var int trafo[16];
					MEM_CopyWords (_@ (itm._zCVob_trafoObjToWorld), _@ (trafo), 16);

					//Remember flags
					var int flags; flags = itm.flags;
					var int mainflag; mainflag = itm.mainflag;

					//Remove found item from world
					Wld_RemoveItem (itm);

					//Insert new item to same position
					vobPtr = InsertItem ("ItLsTorchBurning", amount, _@ (trafo));
					
					//Restore flags
					itm = _^ (vobPtr);
					itm.flags = flags;
					itm.mainflag = mainflag;
				};
			};
		};
	
		i += 1;
	end;

	//Free array
	MEM_ArrayFree (vobListPtr);
};

func void TorchesReSendTrigger__TorchHotKey () {
	var int vobPtr;
	
	//Create array
	var int vobListPtr; vobListPtr = MEM_ArrayCreate ();

	//Search by zCVisual or zCParticleFX does not work
	if (!SearchVobsByClass ("oCMobFire", vobListPtr)) {
		MEM_Info ("No oCMobFire objects found.");
		return;
	};
	
	var int counter; counter = 0;
	var zCArray vobList; vobList = _^ (vobListPtr);

	var int ptr;

	//Loop through all objects
	var int i; i = 0;
	var int count; count = vobList.numInArray;

	//we have to use separate variable here for count
	while (i < count);
		//Read vobPtr from vobList array
		vobPtr = MEM_ArrayRead (vobListPtr, i);

		if (MobIsTorch__TorchHotKey (vobPtr)) {
			var oCMob mob; mob = _^ (vobPtr);

			if ((mob.bitfield & oCMob_bitfield_hitp) == 20) {
				//Trigger vob - will lit fireplace
				MEM_TriggerVob (vobPtr);
			};
		};
	
		i += 1;
	end;

	//Free array
	MEM_ArrayFree (vobListPtr);
};

//0x0067E6E0 protected: virtual void __thiscall oCMobInter::StartStateChange(class oCNpc *,int,int)
func void _eventMobStartStateChange__TorchHotKey (var int dummyVariable) {
	if (!Hlp_Is_oCMobFire (ECX)) { return; };

	var int npcPtr; npcPtr = MEM_ReadInt (ESP + 4);
	if (!Hlp_Is_oCNpc (npcPtr)) { return; };
	var oCNpc slf; slf = _^ (npcPtr);

	if (!Hlp_IsValidNPC (slf)) { return; };

	var int fromState; fromState = MEM_ReadInt (ESP + 8);
	var int toState; toState = MEM_ReadInt (ESP + 12);

	//Is this torch ? is state changing from 0 to 1 ?
	if (MobIsTorch__TorchHotKey (ECX)) && (fromState == 0) && (toState == 1) {
		var oCMob mob; mob = _^ (ECX);

		//This is a little bit dirty workaround, but gets work done
		if ((mob.bitfield & oCMob_bitfield_hitp) != 20) {
			mob.bitfield = (mob.bitfield & oCMob_bitfield_hitp) << 1;

			//I case of G2A I didn't test if this works at all
			//Will leave here couple of additional details - that can be helpful in case of issues
			if (zERROR_GetFilterLevel () > 0) {
				var string msg;

				MEM_Info ("_eventMobStartStateChange__TorchHotKey");

				msg = ConcatStrings ("name: ", mob.name);
				MEM_Info (msg);
				
				msg = IntToString (mob.bitfield & oCMob_bitfield_hitp);
				msg = ConcatStrings ("mob.bitfield & oCMob_bitfield_hitp: ", msg);
				MEM_Info (msg);
			};
		};
	};
};

func void PlayerReApplySprintMode__TorchHotKey () {
	//Don't remove overlay if timed overlay is active
	if (!NPC_HasTimedOverlay (hero, "HUMANS_SPRINT.MDS")) {
		//In case of sprinting torch will remove overlay
		if (NPC_HasOverlay (hero, "HUMANS_SPRINT.MDS")) {
			Mdl_RemoveOverlayMds (hero, "HUMANS_SPRINT.MDS");
			Mdl_ApplyOverlayMds (hero, "HUMANS_SPRINT.MDS");
		};
	};

	/*
	//Timed overlay is not affected by HUMANS_TORCH.MDS removal/addition
	if (NPC_HasTimedOverlay (hero, "HUMANS_SPRINT.MDS")) {
		var int remainingTime; remainingTime = roundf (NPC_GetTimedOverlayTimer (hero, "HUMANS_SPRINT.MDS"));
		NPC_RemoveTimedOverlay (hero, "HUMANS_SPRINT.MDS");
		Mdl_ApplyOverlayMdsTimed (hero, "HUMANS_SPRINT.MDS", remainingTime);
	};
	*/
};

func void _eventGameKeyEvent__TorchHotKey (var int dummyVariable) {
	if (!Hlp_IsValidNPC (hero)) { return; };

	if (((GameKeyEvent_Key == MEM_GetKey ("keyTorchToggleKey")) && GameKeyEvent_Pressed) || ((GameKeyEvent_Key == MEM_GetSecondaryKey ("keyTorchToggleKey")) && GameKeyEvent_Pressed)) {
		//Get Ctrl key status
		var int altPressed; altPressed = MEM_KeyState (KEY_LCONTROL);
		
		if ((altPressed == KEY_PRESSED) || (altPressed == KEY_HOLD)) {
			//Put torch to right hand
			var int retVal; retVal = oCNpc_DoExchangeTorch (hero);
		} else {
			//On & Off
			if (NPC_TorchSwitchOnOff (hero) != -1) {
				PlayerReApplySprintMode__TorchHotKey ();
			};
		};
	};
};

/*
 *	Seems like on world change torch remains in hand in both G1 & G2A
 */
func void _eventGameState__TorchHotKey (var int state) {
	if (!Hlp_IsValidNPC (hero)) { return; };

	//Game saving event
	if (state == Gamestate_PreSaveGameProcessing) {
		//Reinserts ItLsTorchBurning for G2A
		if (MEMINT_SwitchG1G2 (0, 1)) {
			ReInsertBurningTorches__TorchHotKey ();
		};

		//Remember how many torches we have in inventory when saving
		PC_CarriesTorch = NPC_CarriesTorch (hero);
		
		PC_NumberOfTorches = 0;

		if (PC_CarriesTorch) {
			//Get number of all torches in inventory
			PC_NumberOfTorches = NPC_CarriesTorch (hero); //1 which is in hand
			PC_NumberOfTorches += NPC_HasItems (hero, ItLsTorch);
			PC_NumberOfTorches += NPC_HasItems (hero, ItLsTorchBurning);
			PC_NumberOfTorches += NPC_HasItems (hero, ItLsTorchBurned);
		};
	} else
	//Game loaded
	if (state == Gamestate_Loaded) {
		//Re-create if torches are missing
		if (PC_NumberOfTorches) {
			var int total;
			total = NPC_CarriesTorch (hero); //in G1 torch wont disappear - so we want to count it (in G2A it will disappear, so value will be 0)
			total += NPC_HasItems (hero, ItLsTorch);
			total += NPC_HasItems (hero, ItLsTorchBurning);
			total += NPC_HasItems (hero, ItLsTorchBurned);
			
			if (total < PC_NumberOfTorches) {
				CreateInvItems (hero, ItLsTorch, PC_NumberOfTorches - total);
			};
			
			PC_NumberOfTorches = 0;
		};

		//Put back torch
		if (PC_CarriesTorch) {
			NPC_TorchSwitchOn (hero);
		};

		//Resends triggers to all lit mobs
		TorchesReSendTrigger__TorchHotKey ();
	} else
	//Level change event
	if (state == Gamestate_ChangeLevel) {
		//Reinserts ItLsTorchBurning for G2A
		if (MEMINT_SwitchG1G2 (0, 1)) {
			ReInsertBurningTorches__TorchHotKey ();
		};
	};
};

func void G12_TorchHotKey_Init () {
	//Init Game key events
	Game_KeyEventInit ();

	//Add listener for key
	GameKeyEvent_AddListener (_eventGameKeyEvent__TorchHotKey);

	//TriggerChangeLevel event
	G12_GameState_Extended_Init ();

	//Mob start change event
	G12_MobStartStateChangeEvent_Init ();

	//Add listener for mob state change
	MobStartStateChangeEvent_AddListener (_eventMobStartStateChange__TorchHotKey);

	//Add listener for saving/world change/loaded game
	if (_LeGo_Flags & LeGo_Gamestate) {
		Gamestate_AddListener (_eventGameState__TorchHotKey);
	};

	//Load controls from .ini files Gothic.ini is master, mod.ini is secondary
	
	//Custom key from Gothic.ini
	if (!MEM_GothOptExists ("KEYS", "keyTorchToggleKey")) {
		//Custom key from mod .ini file
		if (!MEM_ModOptExists ("KEYS", "keyTorchToggleKey")) {
			//KEY_T if not specified
			MEM_SetKey ("keyTorchToggleKey", KEY_T);
		} else {
			//Update from mod .ini file
			var string keyString; keyString = MEM_GetModOpt ("KEYS", "keyTorchToggleKey");
			MEM_SetKey ("keyTorchToggleKey", MEMINT_KeyStringToKey (keyString));
		};
	};
};