local _, ns = ...

-- Missing keys fall back to the key itself, so a typo never errors.
local L = setmetatable({}, { __index = function(_, k) return k end })
ns.L = L

-- Need / Greed / Pass come from the game's own strings when available,
-- so they always match the loot frame wording.
L.NEED = NEED or "Need"
L.GREED = GREED or "Greed"
L.PASS = PASS or "Pass"
L.TRANSMOG = "Transmog"
L.PENDING = "Waiting"
L.WAITING_CHOICES = "Waiting for choices…"
L.ALL_PASSED = "everyone passed"
L.HISTORY_TITLE = "WhoRolled – loot rolls"
L.HISTORY_EMPTY = "No rolls recorded yet. Type /whorolled test to try it."
L.CLEARED = "History cleared."
L.DEBUG = "Debug messages: %s"
L.ON = "on"
L.OFF = "off"
L.SOURCE = "Data source: %s (in use: %s)"
L.ATTACH = "Panels next to roll frames: %s"
L.MOVE_LABEL = "WhoRolled – loot rolls\nDrag me, then /whorolled move"
L.MOVE_UNLOCKED = "Drag the green box to place the loot rolls, then type /whorolled move again to lock."
L.MOVE_LOCKED = "Loot roll position locked."
L.MOVE_RESET = "Loot roll position reset: /reload to give them back to the game."
L.HELP = {
  "/whorolled – show or hide the history",
  "/whorolled move – move the loot roll frames (again to lock)",
  "/whorolled reset – give the loot roll position back to the game",
  "/whorolled test – play a fake roll to check the display",
  "/whorolled attach – toggle panels next to roll frames",
  "/whorolled source auto|api|chat – where roll data comes from",
  "/whorolled status – show diagnostic info",
  "/whorolled debug – toggle debug messages",
  "/whorolled clear – erase the history",
}

if GetLocale() == "frFR" then
  L.TRANSMOG = "Transmo"
  L.PENDING = "En attente"
  L.WAITING_CHOICES = "En attente des choix…"
  L.ALL_PASSED = "tout le monde a passé"
  L.HISTORY_TITLE = "WhoRolled – jets de butin"
  L.HISTORY_EMPTY = "Aucun jet enregistré. Tapez /whorolled test pour essayer."
  L.CLEARED = "Historique effacé."
  L.DEBUG = "Messages de débogage : %s"
  L.ON = "activés"
  L.OFF = "désactivés"
  L.SOURCE = "Source des données : %s (utilisée : %s)"
  L.ATTACH = "Panneaux à côté des jets : %s"
  L.MOVE_LABEL = "WhoRolled – jets de butin\nDéplacez-moi, puis /whorolled move"
  L.MOVE_UNLOCKED = "Déplacez le cadre vert pour placer les jets de butin, "
    .. "puis retapez /whorolled move pour verrouiller."
  L.MOVE_LOCKED = "Position des jets de butin verrouillée."
  L.MOVE_RESET = "Position des jets de butin réinitialisée : /reload pour la rendre au jeu."
  L.HELP = {
    "/whorolled – afficher ou masquer l'historique",
    "/whorolled move – déplacer les jets de butin (une 2e fois pour verrouiller)",
    "/whorolled reset – rendre la position des jets de butin au jeu",
    "/whorolled test – simuler un jet pour vérifier l'affichage",
    "/whorolled attach – activer/désactiver les panneaux à côté des jets",
    "/whorolled source auto|api|chat – origine des données de jets",
    "/whorolled status – informations de diagnostic",
    "/whorolled debug – activer/désactiver le débogage",
    "/whorolled clear – effacer l'historique",
  }
end
