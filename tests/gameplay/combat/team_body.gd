extends Node2D
## A plain body with an actor id of its own (actors G5), for combat tests that need actors of
## two teams without the actor kit: Combat keeps the row under `actor_id`, reads its team from
## the actor table and keeps its health (as for any body without a Health component).

## Its id in the test's actor table.
var actor_id: int = -1
