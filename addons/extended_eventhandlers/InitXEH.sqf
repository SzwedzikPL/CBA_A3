// #define DEBUG_MODE_FULL
#include "script_component.hpp"

// Compile all necessary scripts and start one vehicle crew initialisation thread
SLX_XEH_DisableLogging = isClass(configFile/"CfgPatches"/"Disable_XEH_Logging");

XEH_LOG("XEH: PreInit Started. v"+getText(configFile >> "CfgPatches" >> "Extended_Eventhandlers" >> "version"));
if (time > 0) then { XEH_LOG("XEH WARNING: Time > 0; This probably means there are no XEH compatible units by default on the map, perhaps add the SLX_XEH_Logic module.") };

SLX_XEH_objects = [];
// All events except the init event
SLX_XEH_OTHER_EVENTS = [XEH_EVENTS,XEH_CUSTOM_EVENTS];

// XEH for non XEH supported addons
// Only works until someone uses removeAllEventhandlers on the object
// Only works if there is at least 1 XEH-enabled object on the Map - Place SLX_XEH_Logic to make sure XEH initializes.
// TODO: Perhaps do a config verification - if no custom eventhandlers detected in _all_ CfgVehicles classes, don't run this XEH handler - might be too much processing.

SLX_XEH_EVENTS_NAT = [XEH_EVENTS];
SLX_XEH_EXCLUDES = ["LaserTarget"]; // TODO: Anything else?? - Ammo crates for instance have no XEH by default due to crashes) - however, they don't appear in 'vehicles' list anyway.
SLX_XEH_PROCESSED_OBJECTS = []; // Used to maintain the list of processed objects
SLX_XEH_CLASSES = []; // Used to cache classes that have full XEH setup
SLX_XEH_FULL_CLASSES = []; // Used to cache classes that NEED full XEH setup
SLX_XEH_EXCL_CLASSES = []; // Used for exclusion classes

// Process each new unit
SLX_XEH_FNC_SUPPORTM = {
	// Add all (Init + "Other" XEH eventhandlers")
	_fnc_full = {
		[_obj] call SLX_XEH_EH_Init;
		{ _obj addEventHandler [_x, compile format["_this call SLX_XEH_EH_%1", _x]] } forEach SLX_XEH_EVENTS_NAT;
	};
	
	// Check existing "Other" XEH eventhandlers, add those which are missing
	_fnc_partial = {
		{
			_event = (_cfg >> _x);
			_XEH = false;
	
			if (isText _event) then {
				_eventAr = toArray(getText(_event));
				if (count _eventAr > 13) then {
					_ar = [];
					for "_i" from 0 to 13 do {
						PUSH(_ar,_eventAr select _i);
					};
					if (toString(_ar) == "_this call SLX") then { _full = false; _XEH = true };
				};
			};
			if !(_XEH) then { _partial = true; TRACE_3("Adding missing EH",_obj,_type,_x); _obj addEventHandler [_x, compile format["_this call SLX_XEH_EH_%1", _x]] };
		} forEach SLX_XEH_EVENTS_NAT;
	};

	private ["_obj", "_cfg", "_init", "_initAr", "_XEH", "_type", "_full", "_partial"];
	_obj = _this select 0;
	_type = typeOf _obj;

	PUSH(SLX_XEH_PROCESSED_OBJECTS,_obj);

	// Already has Full XEH EH entries - Needs nothing!
	if (_type in SLX_XEH_CLASSES) exitWith { TRACE_2("Already XEH (cache hit)",_obj,_type) };

	// No XEH EH entries at all - Needs full XEH
	if (_type in SLX_XEH_FULL_CLASSES) exitWith {
		TRACE_2("Adding XEH Full (cache hit)",_obj,_type);
		call _fnc_full;
	};

	if (_type in SLX_XEH_EXCL_CLASSES) exitWith { TRACE_2("Exclusion, abort (cache hit)",_obj,_type) };

	_cfg = (configFile >> "CfgVehicles" >> _type >> "EventHandlers");
	// No EH class - Needs full XEH
	if !(isClass _cfg) exitWith {
		TRACE_2("Adding XEH Full and caching",_obj,_type);
		call _fnc_full;
		PUSH(SLX_XEH_FULL_CLASSES,_type);
	};

	_excl = getNumber(configFile >> "CfgVehicles" >> "SLX_XEH_DISABLED") == 1;
	if !(_excl) then { { if (_obj isKindOf _x) exitWith { _excl = true } } forEach SLX_XEH_EXCLUDES };
	if (_excl) exitWith {
		TRACE_2("Exclusion, abort and caching",_obj,_type);
		PUSH(SLX_XEH_EXCL_CLASSES,_type);
	};

	// Check 1 - a XEH object variable
	// Cannot use anymore because we want to do deeper verifications
	//_XEH = _obj getVariable "Extended_FiredEH";
	//if !(isNil "_XEH") exitWith { TRACE_2("Has XEH (1)",_obj,_type) };

	// Check 2 - XEH init EH detected
	_init = _cfg >> "init";

	_XEH = false;
	if (isText _init) then {
		_initAr = toArray(getText(_init));
		if (count _initAr > 11) then {
			_ar = [];
			for "_i" from 0 to 11 do {
				PUSH(_ar,_initAr select _i);
			};
			if (toString(_ar) == "if(isnil'SLX") then { _XEH = true };
		};
	};

	_full = false; // Used for caching objects that need ALL eventhandlers assigned, incl init.
	if (_XEH) then {
		TRACE_2("Has XEH init",_obj,_type)
	} else {
		TRACE_2("Adding XEH init",_obj,_type);
		[_obj] call SLX_XEH_EH_Init;
		_full = true;
	};

	// Add script-eventhandlers for those events that are not setup properly.
	_partial = false;
	call _fnc_partial;

	if !(_partial) then { TRACE_2("Caching",_obj,_type); PUSH(SLX_XEH_CLASSES,_type); };
	if (_full) then { TRACE_2("Caching (full)",_obj,_type); PUSH(SLX_XEH_FULL_CLASSES,_type); };
};

private ["_cfgRespawn", "_respawn"];
_cfgRespawn = (missionConfigFile/"respawn");
_respawn = false;
if ( isNumber(_cfgRespawn) ) then
{
	_respawn = !(getNumber(_cfgRespawn) in [0, 1, 4, 5]);
};
if ( isText(_cfgRespawn) ) then
{
	_respawn = !(getText(_cfgRespawn) in ["none", "bird", "group", "side"]);
};

SLX_XEH_MACHINE =
[
	!isDedicated, // 0 - isClient (and thus has player)
	false, // 1 - isJip
	!isServer, // 2 - isDedicatedClient (and thus not a Client-Server)
	isServer, // 3 - isServer
	isDedicated, // 4 - isDedicatedServer (and thus not a Client-Server)
	false, // 5 - Player Check Finished
	!isMultiplayer, // 6 - SP?
	false, // 7 - StartInit Passed
	false, // 8 - Postinit Passed
	isMultiplayer && _respawn      // 9 - Multiplayer && respawn?
];


SLX_XEH_F_INIT = {
	private [
		"_i", "_c", "_entry", "_entryServer", "_entryClient", "_Inits"
	];
	_Inits = [];
	#ifdef DEBUG_MODE_FULL
	_msg = format["XEH BEG: Init %1", _this];
	XEH_LOG(_msg);
	#endif

	if (isClass _this) then
	{
		_i = 0;
		_c = count _this;
		while { _i<_c } do
		{
			_entry = _this select _i;
			if (isClass _entry) then
			{
				_entryServer = (_entry/"serverInit");
				_entryClient = (_entry/"clientInit");
				_entry = (_entry/"init");
				if (isText _entry) then
				{
					_Inits set [count _Inits, compile(getText _entry)];
				};
				if (SLX_XEH_MACHINE select 3) then
				{
					if (isText _entryServer) then
					{
						_Inits set [count _Inits, compile(getText _entryServer)];
					};
				};
				if (!isDedicated) then
				{
					if (isText _entryClient) then
					{
						_Inits set [count _Inits, compile(getText _entryClient)];
					};
				};
			} else {
				if (isText _entry) then
				{
					_Inits set [count _Inits, compile(getText _entry)];
				};
			};
			_i = _i+1;
		};
		{
			#ifdef DEBUG_MODE_FULL
				XEH_LOG(_x);
			#endif
			call _x;
		} forEach _Inits;
	};
	#ifdef DEBUG_MODE_FULL
	_msg = format["XEH END: Init %1", _this];
	XEH_LOG(_msg);
	#endif
};

// Add / Remove the playerEvents
SLX_XEH_F_ADDPLAYEREVENTS = {
	if (isNull _this) exitWith {}; // not a valid object
	{ _event = format["Extended_%1EH",_x]; _curEvt = _this getVariable [_event, []]; _this setVariable [_event, [if (count _curEvt > 0) then { _curEvt select 0 } else { {} }, compile format["_this call ((_this select 0) getVariable '%1_Player')",_event]]] } forEach SLX_XEH_OTHER_EVENTS;
};
SLX_XEH_F_REMOVEPLAYEREVENTS = {
	if (isNull _this) exitWith {}; // not a valid object
	{ _event = format["Extended_%1EH",_x]; _curEvt = _this getVariable [_event, []]; if (count _curEvt > 0) then { _this setVariable [_event, [_curEvt select 0]] } } forEach SLX_XEH_OTHER_EVENTS;
};

// The actual XEH functions that are called from within the engine eventhandlers.
// This can also be uesd for better debugging
#ifdef DEBUG_MODE_FULL
	#define XEH_FUNC(A) SLX_XEH_EH_##A = { if ('A' in ['Respawn', 'MPRespawn', 'Killed', 'MPKilled', 'Hit', 'MPHit']) then { diag_log ['A',_this, local (_this select 0), typeOf (_this select 0)] }; {_this call _x}forEach((_this select 0)getVariable'Extended_##A##EH') }
#endif
#ifndef DEBUG_MODE_FULL
	#define XEH_FUNC(A) SLX_XEH_EH_##A = { {_this call _x}forEach((_this select 0)getVariable'Extended_##A##EH') }
#endif

XEH_FUNC(Hit);
XEH_FUNC(AnimChanged);
XEH_FUNC(AnimStateChanged);
XEH_FUNC(Dammaged);
XEH_FUNC(Engine);
XEH_FUNC(FiredNear);
XEH_FUNC(Fuel);
XEH_FUNC(Gear);
XEH_FUNC(GetIn);
XEH_FUNC(GetOut);
XEH_FUNC(IncomingMissile);
XEH_FUNC(Hit);
XEH_FUNC(Killed);
XEH_FUNC(LandedTouchDown);
XEH_FUNC(LandedStopped);
XEH_FUNC(Respawn);
XEH_FUNC(MPHit);
XEH_FUNC(MPKilled);
XEH_FUNC(MPRespawn);

SLX_XEH_EH_Init = { [_this select 0,'Extended_Init_EventHandlers']call SLX_XEH_init };
SLX_XEH_EH_RespawnInit = { [_this select 0, "Extended_Init_EventHandlers", true] call SLX_XEH_init };
SLX_XEH_EH_GetInMan = { {[_this select 2, _this select 1, _this select 0] call _x}forEach((_this select 2)getVariable'Extended_GetInManEH') };
SLX_XEH_EH_GetOutMan = { {[_this select 2, _this select 1, _this select 0] call _x}forEach((_this select 2)getVariable'Extended_GetOutManEH') };
SLX_XEH_EH_Fired =
{
	#ifdef DEBUG_MODE_FULL
		// diag_log ['Fired',_this, local (_this select 0), typeOf (_this select 0)];
	#endif
	_this call SLX_XEH_EH_FiredBis; _feh = ((_this select 0)getVariable'Extended_FiredEH'); if (count _feh > 0) then { _c=count _this;if(_c<6)then{_this set[_c,nearestObject[_this select 0,_this select 4]];_this set[_c+1,currentMagazine(_this select 0)]}else{_this = +_this; _mag=_this select 5;_this set[5,_this select 6];_this set[6,_mag]};{_this call _x}forEach _feh }
};
SLX_XEH_EH_FiredBis = {
	{_this call _x}forEach((_this select 0)getVariable'Extended_FiredBisEH');
};

// XEH init functions
SLX_XEH_initPlayable =
{
	_unit = _this select 0;
	_var = _unit getVariable "SLX_XEH_PLAYABLE";
	if !(isNil "_var") exitWith {}; // Already set
	if (_unit in playableUnits || isPlayer _unit || _unit == player) then
	{
		#ifdef DEBUG_MODE_FULL
			diag_log ['Playable unit!', _unit];
		#endif
		if (_unit == player) then {
			_unit setVariable ['SLX_XEH_PLAYABLE', true, true]; // temporary until better solution for players in MP..
		} else {
			// Workaround for JIP players thinking they are respawners :P
			_unit setVariable ['SLX_XEH_PLAYABLE', true];
		};
	};
};

SLX_XEH_init = compile preProcessFileLineNumbers "extended_eventhandlers\Init.sqf";
SLX_XEH_initPost = compile preProcessFileLineNumbers "extended_eventhandlers\InitPost.sqf";
SLX_XEH_initOthers = compile preProcessFileLineNumbers "extended_eventhandlers\InitOthers.sqf";

/*
* Process the crews of vehicles. This "thread" will run just
* before the mission init.sqf is processed. The order of execution is
*
*  1) all config.cpp init EHs (including all Extended_Init_Eventhandlers)
*  2) all the init lines in the mission.sqm
*  3) spawn:ed "threads" are started
*  4) the mission's init.sqf/sqs is run
*/
_cinit = [] spawn compile preProcessFileLineNumbers "extended_eventhandlers\PostInit.sqf";


// Load and call any "pre-init", run-once event handlers
call compile preprocessFileLineNumbers "extended_eventhandlers\PreInit.sqf";
XEH_LOG("XEH: PreInit Finished");

// Loading Screen used during PostInit - terminated in PostInit.sqf
_text = "Post Initialization Processing...";
if !(isDedicated) then
{
	// Black screen behind loading screen
	4711 cutText ["", "BLACK OUT", 0.01];

/*
	if !(isNil "CBA_help_credits") then {
		// Randomly pick 2 addons from cfgPatches to display credits
		_credits = [CBA_help_credits, "CfgPatches"] call CBA_fnc_hashGet;
		_cr = [];
		_tmp = [];
		{ PUSH(_tmp,_x) } forEach ((_credits select 0) select 1);
		_tmp = [_tmp] call CBA_fnc_shuffle;
		for "_i" from 0 to 1 do {
			_key = _tmp select _i;
			_entry = format["%1, by: %2", _key, [[_credits select 0, _key] call CBA_fnc_hashGet, ", "] call CBA_fnc_join];
			PUSH(_cr,_entry);
		};
		_text = [_cr, ". "] call CBA_fnc_join;
	};
*/
};

/*
// Disabled loadingScreen, only purpose left was to give mission scripts some extra time, as well as spawned instances
// as well as provide Credits system to CBA and 3rd parties
// the actual compiling of scripts is done in Killed EH anyway.
#define CFG "CfgSettings" >> "cba" >> "loadingScreen"
if (isDedicated || isMultiplayer || (!isMultiplayer && !isNull player)) then {
	_disabled = false;

	_cfg = missionConfigFile >> CFG;
	if (isNumber(_cfg >> "disabled")) then { _disabled = getNumber(_cfg >> "disabled") == 1 };
	if (_disabled) exitWith { CBA_loadingscreen_disabled = true };

	_cfg = configFile >> CFG;
	if (isNumber(_cfg >> "disabled")) then { _disabled = getNumber(_cfg >> "disabled") == 1 };
	if (_disabled) exitWith { CBA_loadingscreen_disabled = true };

	startLoadingScreen [_text, "RscDisplayLoadMission"];
};
*/
