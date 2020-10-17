make a snapshot of the data files:
```
tar cT <(git status --ignored --porcelain | awk -F'!! ' '{print $2}') --exclude='maps' > snapshot_$(date +%s).tar
```
