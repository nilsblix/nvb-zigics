# zigics

## WIP (very much)

Some things to keep in mind:

When building scenes, if one is creating a constraint, "input body" has to be
fresh. I.e, the statement declaring constraint has to come after the creation
of the body. If this is not met, the system will seg-fault. Something to do
with zig being annoying with `array[last_id]`.

## TODO:
* Dynamic vs kinematic bodies: Dynamic is full self-integration, while
kinematic is part of a bigger object (doesn't have its own integration but is
dependant on another source).
