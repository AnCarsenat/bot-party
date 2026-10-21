class_name NetCheck
## Online checks that are safe anywhere, including @tool scripts in the editor
## (where the Net autoload doesn't run).


static func _net(node: Node) -> Node:
	if Engine.is_editor_hint() or node == null or not node.is_inside_tree():
		return null
	return node.get_tree().root.get_node_or_null("Net")


## This computer is a client: it shows the host's game and decides nothing.
static func client(node: Node) -> bool:
	var n := _net(node)
	return n != null and n.is_client()


static func host(node: Node) -> bool:
	var n := _net(node)
	return n != null and n.is_host()


static func online(node: Node) -> bool:
	var n := _net(node)
	return n != null and n.is_online()


## A client is applying something the host sent (gameplay code may run).
static func applying(node: Node) -> bool:
	var n := _net(node)
	return n != null and n.applying()


## Host: also run `method` with `args` on `node` on every client (one-off effects).
static func event(node: Node, method: String, args: Array = []) -> void:
	var n := _net(node)
	if n != null and n.is_host():
		n.send_event(node, method, args)
