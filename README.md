# Archive manager v3.2.3

----------

Manager script and frontend for viewing, adding/removing, checking, tagging, syncing image/video items.
This script is written for bash, using another shell is not recommended.

----------

## Usage:
Use -S                to sync new items
Use -R <item>         to remove items
Use -PL               to generate local item list
Use -PS <itemlist>    to parse remote item list, tag local items, make patch for remote archive copy
Use -SC               to softcheck, check thumbnails
Use -HC               to hardcheck, check item hashes
Use -T                to regenerate all thumbnails
Use -G <item> <tag>   to tag an item
Use -U <item>         to untag an item
Use -F                to regenarate thm.tar.zst

----------

The file structure should look like:
```
img/
├── archive-manager.sh
├── index.html
├── sto/
│   └── 01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b-tag.png
│       ...
├── thm/
│   └── 01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b-tag.jpg
│       ...
├── thm.tar.zst
└── tmp/
```
This file structure is called an *archive*.
Because the item(s) in sto/ has .png extension, this is an image archive.
Video archives have the same file structure except the items in sto/ has .mp4 extension.
Type of an archive can be either image or video, but not both.

To sync (add) new items, place the files in tmp/ and run *archive-manager.sh -S*

Images are converted to PNG format when syncing.
Videos are expected to be using h264, they are not synced otherwise.
Thubnails are all JPG files.

New files with names starting with "_" are set as tags, for example:
tmp/_tag1-tag_2.qwe.asd.png will be synced as sto/01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b-tag1-tag_2.png

Never have spaces in tags, use "_" or "-"!

The archive can have remote copies, and new items/tags can be applied on the remote copy with -PL/-PS flags.
Itemlist generated on -PL flag can be opened with -PS flag, and tag differences can be resolved.
A .tar file of new items can also be created for the remote copy to extract and sync.

To view the archive properly, start your favorite http server and open index.html, where items can be sorted and searched.
You can use the python http server if you installed python:
```python -m http.server```

Designed to have minimal dependencies: *imagemagick*, *ffmpeg*, *sha256sum*.
