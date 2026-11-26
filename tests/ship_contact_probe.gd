extends SceneTree
## Empirical probe: what do PhysicsDirectBodyState2D contact getters return in
## this Godot version (global vs local position, normal direction, impulse)?
## Run: Godot --headless --path <root> --script res://tests/ship_contact_probe.gd

class Probe extends RigidBody2D:
	var frames := 0
	func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
		frames += 1
		for i in state.get_contact_count():
			print("frame %d body_pos=%s rot=%.2f contact_pos=%s normal=%s impulse=%s collider_vel=%s my_vel=%s" % [
				frames, state.transform.origin, state.transform.get_rotation(),
				state.get_contact_local_position(i), state.get_contact_local_normal(i),
				state.get_contact_impulse(i), state.get_contact_collider_velocity_at_position(i),
				state.linear_velocity])

func _initialize() -> void:
	var root_node := Node2D.new()
	get_root().add_child(root_node)
	# Wall to the right of the body, vertical face at x = 1000.
	var wall := StaticBody2D.new()
	var ws := CollisionShape2D.new()
	var r := RectangleShape2D.new()
	r.size = Vector2(100, 1000)
	ws.shape = r
	wall.add_child(ws)
	wall.position = Vector2(1050, 500)
	root_node.add_child(wall)
	var b := Probe.new()
	b.gravity_scale = 0.0
	b.contact_monitor = true
	b.max_contacts_reported = 4
	b.rotation = 0.0
	var cs := CollisionPolygon2D.new()
	cs.polygon = PackedVector2Array([Vector2(50, 0), Vector2(30, -12), Vector2(-45, -25), Vector2(-45, 25), Vector2(30, 12)])
	b.add_child(cs)
	b.continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.45
	pm.friction = 0.2
	b.physics_material_override = pm
	b.position = Vector2(850, 480)
	b.linear_velocity = Vector2(400, 0)
	root_node.add_child(b)
	await create_timer(0.6).timeout
	quit()
