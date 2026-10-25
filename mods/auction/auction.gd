extends PartyMode
## Auction: the cards are sold one at a time. Everyone gets coins each round
## (they add up); jump to bid one coin more than the last bid. When nobody bids
## for a little while, the highest bid wins the card and pays for it. Cards
## nobody bought go, for free, to whoever is left without one. Then the race,
## scored as usual (coins aren't points).

const FIRST_WAIT := 3.0    # seconds for a first bid on a card
const AFTER_BID := 2.0     # seconds left after each bid
const COINS_PER_ROUND := 5
const MAX_COINS := 30

var _lot := -1             # the card being sold (index in ctl.box)
var _price := 0
var _leader := 0           # who bid the most so far (0: nobody)
var _left := 0.0
var _unsold: Array = []


func _init() -> void:
	name = "Auction"
	description = "The cards are sold one at a time: jump to bid your coins (5 more each round). Unsold cards go to whoever has none."
	custom_pick = true


func pick_started(ctl: Node) -> void:
	# Coins for this round (kept in the party, so they last).
	var coins: Dictionary = Party.session.get("auction_coins", {})
	for slot in ctl.slots:
		coins[str(slot)] = mini(int(coins.get(str(slot), 0)) + COINS_PER_ROUND, MAX_COINS)
	Party.session["auction_coins"] = coins
	_unsold.clear()
	_lot = -1
	_next(ctl)


func process_pick(ctl: Node, delta: float) -> void:
	if _lot < 0:
		return
	# Bids: anyone without a card, who can pay one point more.
	for slot in ctl.slots:
		if ctl.picks.has(slot) or slot == _leader:
			continue
		if ctl.pressed(slot, "action_1") and _coins(slot) >= _price + 1:
			_price += 1
			_leader = slot
			_left = AFTER_BID
	_left -= delta
	ctl.say("%s: %s" % [Party.ITEMS.get(ctl.box[_lot], {}).get("name", "?"),
		("%d by %s" % [_price, Party.label(_leader)]) if _leader != 0 else "jump to bid"])
	var purses := []
	for slot in ctl.slots:
		purses.append("%s %d" % [Party.label(slot), _coins(slot)])
	ctl.note("%.1f s    coins: %s" % [maxf(0.0, _left), ", ".join(purses)])
	if _left > 0.0:
		return
	if _leader != 0:
		ctl.picks[_leader] = _lot
		Party.session.auction_coins[str(_leader)] = _coins(_leader) - _price
	else:
		_unsold.append(_lot)
	_next(ctl)


## On to the next card, or done: the unsold ones go to whoever has no card.
func _next(ctl: Node) -> void:
	_lot += 1
	_price = 0
	_leader = 0
	_left = FIRST_WAIT
	var waiting: Array = ctl.slots.filter(func(s): return not ctl.picks.has(s))
	if _lot >= ctl.box.size() or waiting.is_empty():
		for i in range(_lot, ctl.box.size()):
			_unsold.append(i)
		for slot in waiting:
			if _unsold.is_empty():
				break
			ctl.picks[slot] = _unsold.pop_front()
		_lot = -1
		ctl.update_box()
		ctl.start_place()
		return
	# Everyone still bidding stands on the card for sale.
	for slot in waiting:
		ctl.cursors[slot] = _lot
	ctl.update_box()


func _coins(slot: int) -> int:
	return int(Party.session.get("auction_coins", {}).get(str(slot), 0))
