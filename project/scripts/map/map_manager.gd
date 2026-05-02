extends Node

signal map_loaded(map_data: Dictionary)

@export var tile_size: Vector2i = Vector2i(64, 64)
@export var map_width: int = 120
@export var map_height: int = 120

var _fog_revealed: Array = []

var terrain_layer: TileMapLayer = null
var object_layer: TileMapLayer = null

func _ready() -> void:
	terrain_layer = get_node_or_null("TerrainLayer") as TileMapLayer
	object_layer  = get_node_or_null("ObjectLayer")  as TileMapLayer

func load_map(map_resource: Resource) -> void:
	map_loaded.emit({})

func world_to_cell(world_pos: Vector2) -> Vector2i:
	if terrain_layer == null:
		return Vector2i.ZERO
	return terrain_layer.local_to_map(world_pos)

func cell_to_world(cell: Vector2i) -> Vector2:
	if terrain_layer == null:
		return Vector2.ZERO
	return terrain_layer.map_to_local(cell)

func is_passable(cell: Vector2i) -> bool:
	if terrain_layer == null:
		return true
	var tile_data: TileData = terrain_layer.get_cell_tile_data(cell)
	if tile_data == null:
		return false
	return tile_data.get_custom_data("passable")
