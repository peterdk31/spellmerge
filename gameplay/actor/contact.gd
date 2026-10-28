class_name Contact
extends ActorComponent
## Contact, the "hit" component (actors G4, docs/milestones/M2-actors.md, "The components"): the
## damage an actor's touch does. Its Hurtbox hands it to Combat with the rest of the actor
## (`register_actor`), so an actor without a Hurtbox hurts nobody by touch.
##
## A touch hurts every actor of another team whose hurt circle it overlaps, once a second per
## victim (Combat, actors G5), so an imp walking through imps hurts none.

## Damage of one touch (an enemy's from `EnemyBase.contact_damage`); 0 hurts nobody.
@export var damage: int = 0
