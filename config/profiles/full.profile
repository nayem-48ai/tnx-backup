# Profile: full
# Backs up whole /sdcard (incl. hidden), Android/media only, excludes Android/data + obb
# DESC: Everything on /sdcard (recommended full backup)
- /Android/data/**
- /Android/obb/**
+ /Android/media/**
- **/.thumbnails/**
+ **
