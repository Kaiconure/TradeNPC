_**Attribution:** TradeNPC was originally created by Ivaar. Check out the original version [here](https://github.com/Ivaar/Windower-addons/tree/master/TradeNPC)._
# TradeNPC

Trade an npc up to 8 stacks of items and gil with a single command.

### Command Usage:
```
tradenpc <quantity> <item name> [npc name]
```

Quantities greater than an items stack size are accepted, if you specify too many items the trade will not occur.

For gil CSV and EU decimal mark are optional. e.g. 100000 or 100,000 or 100.000

For items, quantity can be `all` or `*` to try and trade all instances of a given item found in your inventory.

Accepts auto-translate, short or full item name.

If the item name is more than one word you must use quotes or auto-translate.

Multiple items can be traded in one command.

If trading gil it must be the first set of arguments or the trade will not occur.

If you need to exceed the chatlog character limit, you can type the command from console or execute via a txt script.

### Additional Features

*[Options added by [@Kaiconure](https://github.com/Kaiconure/TradeNPC)]*

You can now use TradeNPC to assist further with certain repetitive tasks:

1. **Trade all trust ciphers.** When standing near a Trust Recruiter NPC, you can run `tradenpc cipher` and every cipher in your inventory will be traded and activated.
2. **Repeat item turn-in quests.** You can add an optional `multi` argument before the item count to indicate that you should keep on trading until you run out of sufficient items. For example, running `tradenpc multi 2 "Bat Wing" Secodiand` will keep on trading two bat wings to Secodiand until you're down to 0 or 1 wings in your inventory.

### Examples

```
//tradenpc 100 "1 byne bill"

//tradenpc 792 alexandrite

//tradenpc 10,000 gil 24 "fire crystal" 12 "earth crystal" 18 "water crystal" 6 "dark crystal" "Ephemeral Moogle"

//tradenpc cipher

//tradenpc multi 4 "Yagudo Necklace" "Nanaa Mihgo"

//tradenpc all "H. Kindred Crest" Shami
```
