# Hand-rolled core, no framework

We build the server on our own player, character, money, inventory and job code rather than on ESX, QBCore, Qbox or ND. Cfx documents none of them as supported and affirms no affiliation, and depending on a core we cannot read or change is not an acceptable basis for the server.

The direct consequence is that framework-dependent community resources become unusable. Garage, housing, phone and job scripts are written against ESX/QB conventions, so "no framework" means "no borrowing them" — everything the server needs, we write.

## Consequences

- There is no partial-success state. With a framework you can launch with borrowed voice, chat and a community core and add depth later; hand-rolled means there is nothing to launch until the core itself works. Burning out or getting stuck leaves no playable server at all.
- Every system is ours to design, so the v1 list *is* the scope. Scope discipline matters far more here than on a framework server, because there is no borrowed floor to fall back to.
- Nothing is upgradeable from a community script later. Each system we hand-roll is a permanent maintenance cost of our own.
- The upside is real: few systems, no compatibility conflicts, and the data model matches what we actually want instead of bending to someone else's conventions.