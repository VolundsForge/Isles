extends Node

## Puts a hunting bow in the player's hands.

const BOW_PATH := "res://items/isle_bow.tres"


func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var player: Node = get_parent()
	if player == null or player.get("inventory_data") == null:
		return
	var inv: CogitoInventory = player.inventory_data
	inv.owner = player
	if inv.inventory_slots.size() < inv.inventory_size.x * inv.inventory_size.y:
		inv.inventory_slots.resize(inv.inventory_size.x * inv.inventory_size.y)

	var bow: WieldableItemPD = load(BOW_PATH).duplicate(true) as WieldableItemPD
	bow.charge_current = bow.charge_max
	var bow_slot := InventorySlotPD.new()
	bow_slot.create(bow, 1)
	inv.pick_up_slot_data(bow_slot)
	bow.use(player)
