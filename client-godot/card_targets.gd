extends RefCounted
## Preview uses authorized snapshot data only; the server remains authoritative.
static func resolve(snapshot: Dictionary, definition: String, square: String) -> Dictionary:
	var invalid = {"valid": false, "target": {}, "effects": []}
	if square == "" or not snapshot.get("can_cast", false) or snapshot.get("status") != "active":
		return invalid
	var own = snapshot.viewer_side
	var piece = {}
	for candidate in snapshot.pieces:
		if candidate.square == square:
			piece = candidate
	var target = {}
	var effects = []
	match definition:
		"arcane_focus":
			if snapshot.my_mana >= 5: return invalid
		"arcane_draw":
			if snapshot.my_deck_count <= 0: return invalid
		"temporal_boost":
			for card in snapshot.get("my_discard", []):
				if card.definition_id == definition: return invalid
		"silence_seal":
			pass
		"hidden_snare":
			if not piece.is_empty() or snapshot.get("my_traps", []).size() >= 2: return invalid
			for trap in snapshot.get("my_traps", []):
				if trap.square == square: return invalid
			target = {"square": square}
		"oracle_eye", "trap_disarm":
			target = {"square": square}
		"dispel":
			if piece.is_empty(): return invalid
			for effect in snapshot.public_effects:
				if effect.get("piece_id") == piece.id and effect.kind in ["shield", "frozen"]:
					effects.append(effect)
			if effects.is_empty(): return invalid
			if effects.size() == 1: target = {"effect_id": effects[0].id}
		_:
			if piece.is_empty() or piece.kind == "k": return invalid
			var friendly = definition in ["arcane_shield", "ward"]
			if (piece.side == own) != friendly: return invalid
			if definition == "shield_break":
				var shielded = false
				for effect in snapshot.public_effects:
					if effect.get("piece_id") == piece.id and effect.kind == "shield": shielded = true
				if not shielded: return invalid
			target = {"piece_id": piece.id}
	return {"valid": true, "target": target, "effects": effects}
