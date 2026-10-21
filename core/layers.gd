class_name Layers
## Physics layer bits used across the project (also named in Project Settings).
##   1 world    - floors, walls, platforms, solid parts of traps
##   2 players
##   3 machines - background logic blocks: collide with world + each other only
##   4 crates   - foreground boxes: collide with world, players, crates
##   6 hurtbox  - the part of a player that traps hurt (a bit smaller than the body)

const WORLD := 1
const PLAYERS := 2
const MACHINES := 4
const CRATES := 8
const HURTBOX := 32
