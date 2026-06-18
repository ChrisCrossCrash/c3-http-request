# Contributing

Contributions are welcome. Please open an issue before starting significant work so we can discuss the approach first.

## Running Tests

Tests use the [GUT](https://github.com/bitwes/Gut) framework. Run the full suite headlessly:

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

To run a single test file, add `-gtest=res://tests/test_c3_http_request.gd` (swap in the desired file).

All tests must pass before a pull request is approved. No real HTTP calls are made — `TestableImpl` inside `tests/test_c3_http_request.gd` intercepts all network behavior in-process.

## Code Style

### Indentation

Use **tabs** for indentation. Never use spaces.

### Line Length

Aim for a soft maximum of **80 characters** per line. Exceeding it occasionally is fine — don't contort code to fit — but long lines should be the exception.

### Multi-line Function Signatures

When a function signature doesn't fit on one line, indent the parameters one tab and place the closing `) -> ReturnType:` on its own line at zero indent (same level as `func`). Parameters may be grouped on one line or split one-per-line — use whichever is clearer:

```gdscript
# Short params grouped on one line
func request(
	path: String, method: Method, body: Dictionary = {}, query: Dictionary = {}
) -> ApiResponse:

# Many params, one per line
func _on_request_completed(
	_result: int,
	_response_code: int,
	body: PackedByteArray,
	pre: String
) -> void:
```

The closing paren must never share a line with parameters:

```gdscript
# Avoid
func request(
	path: String, method: String, body: Dictionary = {}) -> ApiResponse:
```

### Type Hints

Always annotate variable declarations and function signatures with type hints. Prefer explicit types over `Variant`.

For variables, use `:=` to infer the type from the assigned value rather than spelling it out explicitly. Always annotate function return types and parameters.

```gdscript
# Good
var speed := 5.0
func get_label() -> String:

# Avoid
var speed = 5.0
func get_label():
```

Use an explicit type annotation when inference would produce a broader type than intended — for example, `instantiate()` returns `Node`, so the specific type must be declared manually:

```gdscript
var player: CharacterBody2D = player_scene.instantiate()
```

Awaiting a **signal** also requires an explicit type — GDScript cannot infer the type from signal parameters, even when they are typed. Awaiting a **function call** is fine; `:=` works because the function's return type is known:

```gdscript
# Signal await — explicit type required
var data: SomeClass.SomeType = await some_node.some_signal

# Function await — := works
var result := await C3HTTPRequest.request("https://api.example.com/")
```

### Comments

Comment when the code alone doesn't tell the full story — to explain a non-obvious decision, a hidden constraint, or a subtle invariant. Avoid comments that describe _what_ the code does; those become lies as the code evolves without the comment being updated.

```gdscript
# Good: explains a non-obvious decision
# Slight delay prevents physics body from sleeping before impulse registers
await get_tree().physics_frame

# Avoid: restates what the code already says
# Set speed to 5
speed = 5.0
```

Brief section labels that divide a long function into logical stages are fine when they genuinely help a reader navigate:

```gdscript
func sync_profile() -> void:
	# Fetch
	var profile := await client.request("/profile", "GET")
	# ...

	# Merge local changes
	var payload := _merge_pending_edits(profile.body)
	# ...

	# Upload
	var saved := await client.request("/profile", "PUT", payload)
	# ...
```

Use `##` documentation comments to surface information as a tooltip in the editor — on a class, an exported variable, or any public method where the name and signature alone don't tell the full story. `##` comments are rendered by Godot's editor and support BBCode. For private methods whose purpose isn't immediately apparent, use the same documentation style with `#` instead — single-hash comments are invisible to auto-generated documentation. Plain `#` comments should use prose, not BBCode.

```gdscript
## The maximum speed the player can reach, in units per second.
@export var max_speed: float = 10.0
```

### Declaration Order

Follow Godot's recommended declaration order within a class:

1. `class_name`
2. `extends`
3. `## Class-level doc comment`
4. Signals
5. Enums
6. Constants
7. `@export` variables
8. Public variables
9. Private variables (prefix with `_`)
10. `@onready` variables
11. Built-in virtual methods (`_ready`, `_process`, `_physics_process`, etc.)
12. Public methods
13. Private methods (prefix with `_`)
14. Inner classes (`class InnerName:`)

---

## Example File

```gdscript
class_name ItemSlot
extends Node3D
## Represents a single slot in the player's physical inventory space.
## Tracks occupancy and exposes methods for placing and removing items.

signal item_placed(item: RigidBody3D)
signal item_removed(item: RigidBody3D)

enum SlotState {
	EMPTY,
	OCCUPIED,
	RESERVED,
}

const SNAP_DISTANCE: float = 0.25

## Whether this slot accepts items automatically from the conveyor.
@export var auto_accept: bool = false

## The item category this slot is restricted to, if any.
@export var filter_category: String = ""

var state := SlotState.EMPTY

var _current_item: RigidBody3D = null
var _snap_tween: Tween = null

@onready var _collision_area: Area3D = $CollisionArea
@onready var _highlight_mesh: MeshInstance3D = $HighlightMesh


func _ready() -> void:
	_collision_area.body_entered.connect(_on_body_entered)
	_highlight_mesh.visible = false


func _physics_process(_delta: float) -> void:
	if state == SlotState.RESERVED and _current_item == null:
		# Reservation timed out externally — clean up so the slot doesn't stay locked.
		state = SlotState.EMPTY


## Places an item into this slot, snapping it into position.
## Returns false if the slot is already occupied or the item is filtered out.
func place_item(item: RigidBody3D) -> bool:
	if state != SlotState.EMPTY:
		return false
	if not _passes_filter(item):
		return false

	_current_item = item
	state = SlotState.OCCUPIED
	_snap_item_to_position(item)
	item_placed.emit(item)
	return true


## Removes and returns the current item, leaving the slot empty.
## Returns null if the slot is already empty.
func remove_item() -> RigidBody3D:
	if state == SlotState.EMPTY:
		return null

	var item := _current_item
	_current_item = null
	state = SlotState.EMPTY
	item_removed.emit(item)
	return item


# An empty filter_category means all items are accepted.
# Otherwise, the item must have a matching "category" meta value.
func _passes_filter(item: RigidBody3D) -> bool:
	if filter_category.is_empty():
		return true
	return item.get_meta("category", "") == filter_category


# Temporarily freezes the item's physics body and tweens it to this slot's
# position. Physics is re-enabled after the tween completes so the solver
# doesn't fight the animation.
func _snap_item_to_position(item: RigidBody3D) -> void:
	# Disable physics influence during snap so the tween isn't fought by the solver.
	item.freeze = true

	_snap_tween = create_tween()
	_snap_tween.tween_property(item, "global_position", global_position, 0.1)
	await _snap_tween.finished

	item.freeze = false


# Shows the highlight mesh when a physics body enters the collision area.
# The highlight is hidden again by `place_item()` once an item is accepted.
func _on_body_entered(body: Node3D) -> void:
	if body is RigidBody3D and state == SlotState.EMPTY:
		_highlight_mesh.visible = true
```

## Releasing

Releases are tag-driven. Pushing a `v*` tag triggers [`.github/workflows/release.yml`](.github/workflows/release.yml), which runs the test suite, builds the asset zip, and publishes a GitHub Release with the zip attached and notes taken from the changelog.

The single source of truth for the version is `const VERSION` in [`c3_http_request/c3_http_request.gd`](c3_http_request/c3_http_request.gd). [`scripts/build_asset.py`](scripts/build_asset.py) refuses to build unless the tag matches it exactly, so the bump and the tag can never drift.

To cut a release (e.g. `v0.2.0`):

1. Update `const VERSION` in [`c3_http_request/c3_http_request.gd`](c3_http_request/c3_http_request.gd).
2. Add a section for the version to [`CHANGELOG.md`](CHANGELOG.md), following the [Keep a Changelog](https://keepachangelog.com/) format already in the file. The release workflow publishes this section verbatim as the GitHub Release body, so write it for release-notes readers — and call out breaking changes with a migration note.
3. Verify locally before tagging:
    - Run the full test suite (see [Running Tests](#running-tests)).
    - Dry-run the build: `python scripts/build_asset.py v0.2.0` (confirms the tag/`VERSION` check passes and produces `build/c3_http_request_v0.2.0.zip`).
    - Preview the release body: `python scripts/extract_changelog.py v0.2.0` (prints the changelog section the workflow will publish).
4. Commit the version bump and changelog to `main`.
5. Create an annotated tag matching `VERSION`, using the changelog section as the tag body so `git show v0.2.0` carries the same notes:

   ```bash
   git tag -a v0.2.0 --cleanup=whitespace -m "v0.2.0" -m "$(python scripts/extract_changelog.py v0.2.0)"
   ```

   `--cleanup=whitespace` is required because the changelog's `### Added` / `### Changed` subheadings start with `#`; without it, `git tag`'s default `strip` cleanup would delete those lines as if they were comments.

   Then push the branch and the tag together — the tag push triggers the release workflow:

   ```bash
   git push origin main v0.2.0
   ```
6. After the workflow succeeds, update the [Godot Asset Store](https://store.godotengine.org/asset/c3designs/c3-http-request/manage/) by uploading the new release bundle.
7. After the release is approved, update the detailed description for the asset to match the latest version's features and changes.
