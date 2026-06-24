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


## Prints a single BBCode-tagged line, rendered with its tags both on screen
## (via [method append_text]) and in the terminal (via [method print_rich]) — for
## lines that must stand out from ordinary output. Pass already-tagged text, e.g.
## [code]"[color=yellow]heads up[/color]"[/code]. Unlike [method print_with_overlay],
## the tags are always parsed, so plain brackets in the argument are not safe here.
func print_rich_with_overlay(bbcode: String) -> void:
	append_text(bbcode + "\n")
	print_rich(bbcode)
