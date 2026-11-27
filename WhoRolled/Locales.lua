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
L.WAITING_CHOICES = "Waiting for choices..."
L.ALL_PASSED = "everyone passed"
L.HISTORY_TITLE = "WhoRolled – loot rolls"
L.HISTORY_EMPTY = "No rolls recorded yet. Type /whorolled test to try it."
L.CLEARED = "History cleared."
L.DEBUG = "Debug messages: %s"
L.ON = "on"
L.OFF = "off"
L.SOURCE = "Data source: %s (in use: %s)"
L.ATTACH = "Panels next to roll frames: %s"
L.MOVE_LABEL = "WhoRolled – loot rolls\nDrag me, then close (X) to lock"
L.MOVE_UNLOCKED = "Drag the green box to place the loot rolls, then close it (X) to lock."
L.MOVE_LOCKED = "Loot roll position locked."
L.MOVE_RESET = "Loot roll position reset: /reload to give them back to the game."
L.OPT_INTRO = "Shows who chose Need, Greed or Pass on each loot roll. Also in the add-on menu by the minimap "
  .. "(left click: options, right click: history)."
L.OPT_DISPLAY = "Display"
L.OPT_ATTACH = "Show a panel next to each loot roll"
L.OPT_EXPANDED = "Show the full list of players by default (else click \"Details\")"
L.CLICK_DETAILS = "|TInterface\\Buttons\\UI-PlusButton-Up:12|t Details"
L.CLICK_HIDE = "|TInterface\\Buttons\\UI-MinusButton-Up:12|t Hide"
L.ITEM_HEARTHSTONE = "Hearthstone"
L.ITEM_SILK = "Silk Cloth"
L.ITEM_LINEN = "Linen Cloth"
L.ITEM_SILVERLEAF = "Silverleaf"
L.ITEM_COPPER_ORE = "Copper Ore"
L.ITEM_MINOR_HEALING = "Minor Healing Potion"
L.ITEM_PEACEBLOOM = "Peacebloom"
L.ITEM_MAGEWEAVE = "Mageweave Cloth"
L.ITEM_SPRING_WATER = "Refreshing Spring Water"
L.ITEM_TOUGH_JERKY = "Tough Jerky"
L.OPT_MOVE = "Move the loot rolls"
L.OPT_LOCK = "Lock the loot rolls"
L.OPT_RESET_POS = "Reset position"
L.OPT_TEST = "Test roll"
L.OPT_TEST_5 = "Test roll x5"
L.TEST_TAG = "Test"
L.OPT_HISTORY = "History"
L.OPT_OPEN_HISTORY = "Open the history"
L.OPT_MAX_HISTORY = "Items kept"
L.OPT_CLEAR = "Clear the history"
L.OPT_CLEAR_CONFIRM = "Erase the WhoRolled roll history?"
L.OPT_DATA = "Roll data"
L.OPT_SOURCE_AUTO = "Automatic (recommended)"
L.OPT_SOURCE_API = "Loot history (C_LootHistory)"
L.OPT_SOURCE_CHAT = "Loot chat messages"
L.OPT_IN_USE = "In use: %s"
L.OPT_DEBUG = "Print debug messages in the chat"
L.OPT_UNAVAILABLE = "The options panel is not available on this client: use /whorolled help"
L.OPT_COMBAT = "Could not open the options (in combat?): try again out of combat"
L.HELP = {
  "/whorolled – open the options",
  "/whorolled history – show or hide the history",
  "/whorolled move – move the loot roll frames",
  "/whorolled reset – give the loot roll position back to the game",
  "/whorolled test [1-10] – play fake rolls (one by default) to check the display",
  "/whorolled attach – toggle panels next to roll frames",
  "/whorolled source auto|api|chat – where roll data comes from",
  "/whorolled status – show diagnostic info",
  "/whorolled debug – toggle debug messages",
  "/whorolled clear – erase the history",
}

if GetLocale() == "frFR" then
  L.TRANSMOG = "Transmo"
  L.PENDING = "En attente"
  L.WAITING_CHOICES = "En attente des choix..."
  L.ALL_PASSED = "tout le monde a passé"
  L.HISTORY_TITLE = "WhoRolled – jets de butin"
  L.HISTORY_EMPTY = "Aucun jet enregistré. Tapez /whorolled test pour essayer."
  L.CLEARED = "Historique effacé."
  L.DEBUG = "Messages de débogage : %s"
  L.ON = "activés"
  L.OFF = "désactivés"
  L.SOURCE = "Source des données : %s (utilisée : %s)"
  L.ATTACH = "Panneaux à côté des jets : %s"
  L.MOVE_LABEL = "WhoRolled – jets de butin\nDéplacez-moi, puis fermez (X) pour verrouiller"
  L.MOVE_UNLOCKED = "Déplacez le cadre vert pour placer les jets de butin, puis fermez-le (X) pour verrouiller."
  L.MOVE_LOCKED = "Position des jets de butin verrouillée."
  L.MOVE_RESET = "Position des jets de butin réinitialisée : /reload pour la rendre au jeu."
  L.OPT_INTRO = "Affiche qui a choisi Besoin, Cupidité ou Passer sur chaque jet de butin. Aussi dans le menu "
    .. "des add-ons près de la minicarte (clic gauche : options, clic droit : historique)."
  L.OPT_DISPLAY = "Affichage"
  L.OPT_ATTACH = "Afficher un panneau à côté de chaque jet de butin"
  L.OPT_EXPANDED = "Afficher la liste complète des joueurs par défaut (sinon, cliquer sur « Détails »)"
  L.CLICK_DETAILS = "|TInterface\\Buttons\\UI-PlusButton-Up:12|t Détails"
  L.CLICK_HIDE = "|TInterface\\Buttons\\UI-MinusButton-Up:12|t Masquer"
  L.ITEM_HEARTHSTONE = "Pierre de foyer"
  L.ITEM_SILK = "Étoffe de soie"
  L.ITEM_LINEN = "Étoffe de lin"
  L.ITEM_SILVERLEAF = "Feuillargent"
  L.ITEM_COPPER_ORE = "Minerai de cuivre"
  L.ITEM_MINOR_HEALING = "Potion de soins mineure"
  L.ITEM_PEACEBLOOM = "Pacifique"
  L.ITEM_MAGEWEAVE = "Étoffe de tisse-mage"
  L.ITEM_SPRING_WATER = "Eau de source rafraîchissante"
  L.ITEM_TOUGH_JERKY = "Viande séchée coriace"
  L.OPT_MOVE = "Déplacer les jets de butin"
  L.OPT_LOCK = "Verrouiller les jets de butin"
  L.OPT_RESET_POS = "Position par défaut"
  L.OPT_TEST = "Jet de test"
  L.OPT_TEST_5 = "Jet de test x5"
  L.TEST_TAG = "Test"
  L.OPT_HISTORY = "Historique"
  L.OPT_OPEN_HISTORY = "Ouvrir l'historique"
  L.OPT_MAX_HISTORY = "Objets conservés"
  L.OPT_CLEAR = "Effacer l'historique"
  L.OPT_CLEAR_CONFIRM = "Effacer l'historique des jets de WhoRolled ?"
  L.OPT_DATA = "Données des jets"
  L.OPT_SOURCE_AUTO = "Automatique (recommandé)"
  L.OPT_SOURCE_API = "Historique du butin (C_LootHistory)"
  L.OPT_SOURCE_CHAT = "Messages de butin du chat"
  L.OPT_IN_USE = "Utilisée : %s"
  L.OPT_DEBUG = "Afficher les messages de débogage dans le chat"
  L.OPT_UNAVAILABLE = "Le panneau d'options n'est pas disponible sur ce client : utilisez /whorolled help"
  L.OPT_COMBAT = "Impossible d'ouvrir les options (en combat ?) : réessayez hors combat"
  L.HELP = {
    "/whorolled – ouvrir les options",
    "/whorolled history – afficher ou masquer l'historique",
    "/whorolled move – déplacer les jets de butin",
    "/whorolled reset – rendre la position des jets de butin au jeu",
    "/whorolled test [1-10] – simuler des jets (un par défaut) pour vérifier l'affichage",
    "/whorolled attach – activer/désactiver les panneaux à côté des jets",
    "/whorolled source auto|api|chat – origine des données de jets",
    "/whorolled status – informations de diagnostic",
    "/whorolled debug – activer/désactiver le débogage",
    "/whorolled clear – effacer l'historique",
  }
end
