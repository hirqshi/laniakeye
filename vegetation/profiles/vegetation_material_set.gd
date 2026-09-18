class_name VegetationMaterialSet
extends Resource

@export_category("Shared Materials")
@export var bark_material: ShaderMaterial
@export var leaf_material: ShaderMaterial

@export_category("Texture Sets")
@export var bark_albedo_array: Texture2DArray
@export var bark_normal_array: Texture2DArray
@export var bark_roughness_array: Texture2DArray
@export var bark_ao_array: Texture2DArray

@export var leaf_albedo_array: Texture2DArray
@export var leaf_normal_array: Texture2DArray
@export var leaf_roughness_array: Texture2DArray
@export var leaf_ao_array: Texture2DArray
@export var leaf_opacity_array: Texture2DArray
