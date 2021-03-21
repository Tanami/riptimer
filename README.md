[![Discord server](https://discordapp.com/api/guilds/516841820567896064/widget.png?style=shield)](https://bhop.rip/discord)

make a snapshot of the data files:
```
tar cT <(git status --ignored --porcelain | awk -F'!! ' '{print $2}') --exclude='maps' > snapshot_$(date +%s).tar
```
