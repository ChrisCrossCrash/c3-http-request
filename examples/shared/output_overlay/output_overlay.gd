@tool
class_name OutputOverlay
extends RichTextLabel
## On-screen console: mirrors a line both to the output panel (via [method print])
## and to the screen, auto-scrolling to follow the newest output.


## Prints its arguments both to stdout and on screen. Like [method print], the
## arguments are concatenated with no separator.
func print_with_overlay(...args: Array) -> void:
	var parts: PackedStringArray = []
	for item in args:
		parts.append(str(item))
	var line := "".join(parts)
	# add_text appends literally; append_text parses BBCode. Match bbcode_enabled
	# so callers that pass tagged text get them rendered and others stay literal.
	if bbcode_enabled:
		append_text(line + "\n")
	else:
		add_text(line + "\n")
	print(line)
