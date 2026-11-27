-- luacheck configuration for the WhoRolled addon (Lua 5.1, as embedded in the WoW client).
std = "lua51"
max_line_length = 120
self = false -- methods are declared with ":" even when they do not use self

-- Globals the addon defines.
globals = {
  "SlashCmdList",
  "WhoRolledDB", -- SavedVariables of WhoRolled
  "SLASH_WHOROLLED1",
  "SLASH_WHOROLLED2",
  "UISpecialFrames", -- the history window is added so Escape closes it
}

-- WoW API and global strings used (read only).
read_globals = {
  "Ambiguate",
  "BackdropTemplateMixin",
  "C_Item",
  "C_LootHistory",
  "C_Timer",
  "CreateFrame",
  "CUSTOM_CLASS_COLORS",
  "Enum",
  "GameFontHighlightSmall",
  "GameTooltip",
  "GetBuildInfo",
  "GetItemInfo",
  "GetLocale",
  "GetLootRollItemLink",
  "GetNumGroupMembers",
  "GetTime",
  "GREED",
  "IsInRaid",
  "NEED",
  "NUM_GROUP_LOOT_FRAMES",
  "PASS",
  "RAID_CLASS_COLORS",
  "SetItemRef",
  "UIParent",
  "UnitClass",
  "UnitName",
  "date",
  "time",
  "tinsert",
  "wipe",
}

files["spec/"] = { std = "+busted" }
