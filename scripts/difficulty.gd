class_name Difficulty
extends RefCounted
## LAST REBOUND: game modes. Three story difficulties and the endless Last Rebound.
##
## Story presets:
##   gong_scale        multiplies every gong's diameter (not the summit plaza)
##   launch_bonus      metres added to every gong's launch height
##   move_force        air-control force on the ember (32 = baseline)
##   max_speed         horizontal speed cap
##   checkpoints       gongs with braziers (by node name)
##   swinging          {gong name: [amplitude degrees, speed rad/s]}: gongs that swing on their arm
##   cracked           gongs that hold one landing, then crumble and reform
##   wind              [min gap s, max gap s, gust length s, force N]; empty = calm
##   abyss_speed       how fast the abyss climbs (0 = no abyss); abyss_gap = reset distance below you
##   lightning         [min, max] seconds between random strikes

enum Level { EASY, NORMAL, HARD, ENDLESS }

const ORDER := [Level.EASY, Level.NORMAL, Level.HARD, Level.ENDLESS]

const PRESETS := {
	Level.EASY: {
		"id": "easy",
		"name": "Easy",
		"tagline": "The storm is gentle. Every gong is a brazier.",
		"gong_scale": 1.25,
		"launch_bonus": 1.0,
		"move_force": 38.0,
		"max_speed": 12.0,
		"checkpoints": ["Gong03", "Gong04", "Gong05", "Gong06", "Gong07", "Gong08", "Gong09", "Gong10"],
		"swinging": {},
		"cracked": [],
		"wind": [],
		"abyss_speed": 0.0,
		"abyss_gap": 0.0,
		"lightning": [10.0, 18.0],
	},
	Level.NORMAL: {
		"id": "normal",
		"name": "Normal",
		"tagline": "Two gongs swing. The tower as it stands.",
		"gong_scale": 1.0,
		"launch_bonus": 0.0,
		"move_force": 32.0,
		"max_speed": 11.0,
		"checkpoints": ["Gong04", "Gong07", "Gong10"],
		"swinging": {"Gong05": [12.0, 0.45], "Gong09": [14.0, 0.5]},
		"cracked": [],
		"wind": [],
		"abyss_speed": 0.0,
		"abyss_gap": 0.0,
		"lightning": [7.0, 15.0],
	},
	Level.HARD: {
		"id": "hard",
		"name": "Hard",
		"tagline": "Swinging gongs. Cracked bronze. Wind. The abyss.",
		"gong_scale": 0.82,
		"launch_bonus": 0.0,
		"move_force": 30.0,
		"max_speed": 11.0,
		"checkpoints": ["Gong07", "Gong10"],
		"swinging": {
			"Gong02": [14.0, 0.55], "Gong04": [16.0, 0.6], "Gong06": [18.0, 0.65],
			"Gong07": [10.0, 0.5], "Gong08": [18.0, 0.7], "Gong09": [20.0, 0.75], "WarGong": [12.0, 0.6],
		},
		"cracked": ["Gong03", "Gong05", "Gong08"],
		"wind": [7.0, 11.0, 2.4, 13.0],
		"abyss_speed": 0.8,
		"abyss_gap": 16.0,
		"lightning": [4.0, 9.0],
	},
	Level.ENDLESS: {
		"id": "endless",
		"name": "Last Rebound",
		"tagline": "Endless tower. One life. Climb for XP.",
		"move_force": 31.0,
		"max_speed": 11.0,
		"lightning": [4.0, 8.0],
	},
}

## Ranks by level (Endless XP).
const RANKS := [
	[1, "Ash"], [2, "Cinder"], [3, "Spark"], [5, "Flame"], [8, "Blaze"],
	[12, "Inferno"], [18, "Sunfire"], [25, "The Last Rebound"],
]

## Ember colours unlocked by level: [level, name, core colour, light colour].
const EMBERS := [
	[1, "Classic", Color(1.0, 0.62, 0.32), Color(1.0, 0.52, 0.2)],
	[3, "Frost", Color(0.55, 0.85, 1.0), Color(0.45, 0.75, 1.0)],
	[5, "Venom", Color(0.55, 1.0, 0.45), Color(0.45, 1.0, 0.35)],
	[8, "Amethyst", Color(0.85, 0.5, 1.0), Color(0.75, 0.4, 1.0)],
	[12, "Sunfire", Color(1.0, 0.88, 0.45), Color(1.0, 0.85, 0.4)],
]


static func get_preset(level: int) -> Dictionary:
	return PRESETS[level]


static func from_id(id: String) -> int:
	if id == "last":
		return Level.ENDLESS
	for level in PRESETS:
		if PRESETS[level]["id"] == id:
			return level
	return Level.NORMAL


## Player level from total XP: L2 at 60 XP, L3 at 240, L5 at 960, L10 at 4,860.
static func level_for_xp(xp: int) -> int:
	return int(floor(sqrt(xp / 60.0))) + 1


static func xp_for_level(lv: int) -> int:
	return int(60 * (lv - 1) * (lv - 1))


static func rank_for_level(lv: int) -> String:
	var name := "Ash"
	for r in RANKS:
		if lv >= r[0]:
			name = r[1]
	return name


static func unlocked_embers(lv: int) -> Array:
	var out := []
	for e in EMBERS:
		if lv >= e[0]:
			out.append(e)
	return out


static func ember_by_name(ember_name: String) -> Array:
	for e in EMBERS:
		if e[1] == ember_name:
			return e
	return EMBERS[0]
