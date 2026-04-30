extends Node

## MapManager — owns the tile map, fog of war, and pathfinding regions.

signal map_loaded(map_data: Dictionary)

@export var tile_size: Vector2i = Vector2i(64, 64)
@export var map_width: int = 120
@export var map_height: int = 120

var _fog_revealed: Array = []  # Array of bool per player per cell

@onready var terrain_layer: TileMapLayer = $TerrainLayer
@onready var object_layer: TileMapLayer = $ObjectLayer

func load_map(map_resource: Resource) -> void:
	# TODO: parse map_resource and populate tile layers
	map_loaded.emit({})

func world_to_cell(world_pos: Vector2) -> Vector2i:
	return terrain_layer.local_to_map(world_pos)

func cell_to_world(cell: Vector2i) -> Vector2:
	return terrain_layer.map_to_local(cell)

func is_passable(cell: Vector2i) -> bool:
	var tile_data: TileData = terrain_layer.get_cell_tile_data(cell)
	if tile_data == null:
		return false
	return tile_data.get_custom_data("passable")
