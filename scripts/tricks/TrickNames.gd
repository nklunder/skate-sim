class_name TrickNames

## Maps a measured TrickSignature to a display name.
##
## THIS IS THE ONLY FILE YOU EDIT TO ADD OR RENAME A TRICK.
##
## How to add one:
##   1. Do the trick in game.
##   2. Read the "Signature:" line off the HUD, e.g.
##        pop=OLLIE flip=KICK scoop=-360 body=-180 world=-540 with_scoop=true
##   3. Add a row below with the fields you care about and the name you want.
##
## Matching rules, in plain terms:
##
##   * A row describes a trick EXACTLY. Any of `flip`, `scoop`, `body` you leave out must be zero
##     for the row to match. So {scoop = -360, flip = KICK} means "360 scoop, kickflip, and no body
##     rotation" - it will NOT also claim a 360 flip that had a 180 body rotation in it.
##   * `pop` is the exception: leave it out and the row covers all four stances, with the stance
##     name added as a prefix automatically ("360 Flip" -> "Switch 360 Flip").
##   * The derived fields (`board_world`, `body_with_scoop`, `lands_switch`) are opt-in: they are
##     only checked if you list them.
##   * Write `ANY` as a value to explicitly ignore a field, e.g. scoop = ANY.
##   * Rows are checked top to bottom, FIRST MATCH WINS.
##
## If a trick comes out with the wrong name, the usual cause is a row above it matching first.
## If it comes out as a generated description instead of a name, no row matched - check that the
## fields you left out really are zero in the HUD readout.

const KICK := TrickSignature.Flip.KICK
const HEEL := TrickSignature.Flip.HEEL
const NO_FLIP := TrickSignature.Flip.NONE

const OLLIE := TrickSignature.Pop.OLLIE
const NOLLIE := TrickSignature.Pop.NOLLIE
const SWITCH := TrickSignature.Pop.SWITCH_OLLIE
const FAKIE := TrickSignature.Pop.FAKIE_OLLIE

## Write this as a value to ignore a field that would otherwise default to zero.
const ANY := "*"

## Every field a rule may match on. A typo fails loudly rather than silently never matching.
const FIELDS: PackedStringArray = [
	"pop", "flip", "scoop", "body", "board_world", "body_with_scoop", "lands_switch",
]

## Fields that must be inert when a row does not mention them. This is what stops a general row
## from silently swallowing a more elaborate trick.
const DEFAULT_ZERO: PackedStringArray = ["flip", "scoop", "body"]

const TABLE: Array[Dictionary] = [
	# --- Named by net result: board cancelled out, but the body turned. -----
	# These list scoop = ANY because the cancellation is the point, not the input pair.
	{board_world = 0, body = -180, scoop = ANY, name = "Body Varial"},
	{board_world = 0, body = 180, scoop = ANY, name = "FS Body Varial"},

	# --- Bigspin family: board and body turning together --------------------
	# NOTE: `scoop` is board rotation RELATIVE TO THE BODY, while `board_world` is the total the
	# board turns in the world (= scoop + body). A trick described as "360 degrees of spin" is 360
	# of *world* rotation, and the body supplies half of it - so it appears here as scoop = -180
	# with body = -180, NOT scoop = -360. Always check the `world=` value on the HUD readout.
	#
	# The whole family is one motion (board 360 in the world, body 180); the flip decides the name.
	{scoop = -180, body = -180, flip = NO_FLIP, name = "Bigspin"},
	{scoop = -180, body = -180, flip = KICK, name = "Bigflip"},
	{scoop = -180, body = -180, flip = HEEL, name = "Bigspin Heelflip"},

	{scoop = 180, body = 180, flip = NO_FLIP, name = "FS Bigspin"},
	{scoop = 180, body = 180, flip = KICK, name = "FS Bigflip"},
	{scoop = 180, body = 180, flip = HEEL, name = "FS Bigspin Heelflip"},

	# --- 360 scoop family ----------------------------------------------------
	{scoop = -360, flip = KICK, name = "360 Flip"},
	{scoop = 360, flip = KICK, name = "360 Hardflip"},
	{scoop = 360, flip = HEEL, name = "Laser Flip"},
	{scoop = -360, flip = HEEL, name = "360 Inward Heelflip"},
	{scoop = -360, name = "360 Pop Shove-it"},
	{scoop = 360, name = "FS 360 Pop Shove-it"},

	# --- 180 scoop family ----------------------------------------------------
	{scoop = -180, flip = KICK, name = "Varial Kickflip"},
	{scoop = 180, flip = KICK, name = "Hardflip"},
	{scoop = -180, flip = HEEL, name = "Inward Heelflip"},
	{scoop = 180, flip = HEEL, name = "Varial Heelflip"},
	{scoop = -180, name = "Pop Shove-it"},
	{scoop = 180, name = "FS Pop Shove-it"},

	# --- Body rotation with a flip ------------------------------------------
	{body = 180, flip = KICK, name = "FS Flip"},
	{body = -180, flip = KICK, name = "BS Flip"},
	{body = 180, flip = HEEL, name = "FS Heelflip"},
	{body = -180, flip = HEEL, name = "BS Heelflip"},

	# --- Body rotation only -------------------------------------------------
	{body = 180, name = "FS 180"},
	{body = -180, name = "BS 180"},
	{body = 360, name = "FS 360"},
	{body = -360, name = "BS 360"},

	# --- Flip only ----------------------------------------------------------
	{flip = KICK, name = "Kickflip"},
	{flip = HEEL, name = "Heelflip"},

	# --- Plain pops. These pin `pop`, so no stance prefix is added. ----------
	{pop = OLLIE, name = "Ollie"},
	{pop = NOLLIE, name = "Nollie"},
	{pop = SWITCH, name = "Switch Ollie"},
	{pop = FAKIE, name = "Fakie"},
]

## Returns the display name for a measured trick. Falls back to a generated description so an
## unrecognised combination is still readable (and its signature discoverable) rather than "Unknown".
static func resolve(sig: TrickSignature) -> String:
	for rule in TABLE:
		if _matches(rule, sig):
			var name: String = rule["name"]
			# A rule that pins `pop` owns its whole name; otherwise the stance is a prefix, which is
			# what keeps the table from needing four rows per trick.
			if not rule.has("pop"):
				var word: String = _pop_word(sig.pop)
				if word != "":
					return word + " " + name
			return name
	return _describe_unnamed(sig)

static func _matches(rule: Dictionary, sig: TrickSignature) -> bool:
	for key in rule:
		if key == "name":
			continue
		assert(FIELDS.has(key),
			"TrickNames: unknown field '%s' in rule '%s'. Valid fields: %s"
			% [key, rule.get("name", "?"), ", ".join(FIELDS)])
		var want: Variant = rule[key]
		# Type-check before comparing: GDScript raises on int == String rather than returning false.
		if want is String and want == ANY:
			continue
		if _field(sig, key) != want:
			return false
	# Anything the row stayed silent about must be inert, so "360 Flip" does not also answer to a
	# 360 flip with a body rotation folded in.
	for key in DEFAULT_ZERO:
		if not rule.has(key) and _field(sig, key) != 0:
			return false
	return true

static func _field(sig: TrickSignature, key: String) -> Variant:
	match key:
		"pop": return sig.pop
		"flip": return sig.flip
		"scoop": return sig.scoop_deg
		"body": return sig.body_deg
		"board_world": return sig.board_world_deg
		"body_with_scoop": return sig.body_with_scoop
		"lands_switch": return sig.lands_switch
	return null

static func _pop_word(pop: TrickSignature.Pop) -> String:
	match pop:
		TrickSignature.Pop.NOLLIE: return "Nollie"
		TrickSignature.Pop.SWITCH_OLLIE: return "Switch"
		TrickSignature.Pop.FAKIE_OLLIE: return "Fakie"
	return ""

## Generative fallback for combinations with no table row yet.
static func _describe_unnamed(sig: TrickSignature) -> String:
	var parts: PackedStringArray = []
	var word: String = _pop_word(sig.pop)
	if word != "":
		parts.append(word)
	if sig.body_deg != 0:
		parts.append("%d Body" % absi(sig.body_deg))
	if sig.scoop_deg != 0:
		parts.append("%d Scoop" % absi(sig.scoop_deg))
	match sig.flip:
		TrickSignature.Flip.KICK: parts.append("Kickflip")
		TrickSignature.Flip.HEEL: parts.append("Heelflip")
	if parts.is_empty():
		return "Ollie"
	return " ".join(parts)
