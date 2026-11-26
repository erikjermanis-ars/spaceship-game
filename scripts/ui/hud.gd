extends CanvasLayer
## HUD root. Each widget is its own full-rect Control (see scenes/ui/hud.tscn)
## that pulls what it needs from Game, Game.player and the gameplay systems
## (looked up by group), so the HUD works with whatever is present.

func _ready() -> void:
	layer = 10
	# The HUD itself pauses with the game; help + pause overlay opt out.
	process_mode = Node.PROCESS_MODE_INHERIT
