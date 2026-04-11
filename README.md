# Archive manager v3.5.1

----------

Manager script and web frontend for viewing, adding, removing, checking, tagging, and sharing image or video items.

----------

## Usage:
bash archive-manager.sh <option> [<args>]
|option and args| what it does                                          |
|C              | commit new items                                      |
|R <item>       | remove an item                                        |
|PL             | generate local item list                              |
|PS <itemlist>  | tag local items or make patch for remote archive copy |
|-softcheck     | check thumbnails filenames                            |
|-hardcheck     | check item hashes                                     |
|-thumbnailgen  | regenerate all thumbnails                             |
|G <item> <tag> | tag an item                                           |
|U <item>       | untag an item                                         |
|F              | regenerate thm.tar.zst                                |
|W              | start a web server                                    |

----------

The file structure should look like:
```
img/
├── archive-manager.sh
├── index.html
├── sto/
│   └── 01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b-tag.jxl
│       ...
├── thm/
│   └── 01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b-tag.webp
│       ...
├── thm.tar.zst
└── tmp/
```
This file structure is called an *archive*.
Because the item(s) in sto/ has .jxl extension (an image format), this is an image archive.
Video archives have the same file structure except the items in sto/ has .mp4 extension.
Type of an archive can be either image or video, but not both.

To commit (add) new items, place the files in tmp/ and run *archive-manager.sh C*

Images are converted to JXL format when committing.
Videos are expected to be in MP4 format, they are not committed otherwise.
Thumbnails are automatically created from these, and are all WEBP files.

Files under sto/ are the items, and are named as <sha256 hash>-<tags>.<file type>.
Thumbnails are stored in thm/ and are named the same as the items, but the file type is WEBP.

You can specify the tags when committing an item by setting the first character of its file name to underscore (_).
For example,
**tmp/_tag1-tag_2.qwe.asd** will be committed as **sto/01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b-tag1-tag_2.jxl**

Never have spaces in tags, use "_" or "-"!

The archive can have remote copies, and new items/tags can be applied on the remote copy with **PL/PS** options.
Person A can generate an itemlist file with the **PL** option.
Person B can open this file with **PS** option and automatically do:
1. tag and remove their items to match Person A's items,
2. create a .tar file containing items that B has but A doesn't.
Person A can extract this file into tmp/ and commit to obtain B's items.

To view the archive properly, start an http server and open main.html, where items can be sorted and searched.
Option **W** opens the python web server if it is installed.

The webpage detects the archive type from its path, and if *img* or *vid* is not a part of the path, type is asked.

Designed to have minimal dependencies: *imagemagick*, *ffmpeg*, *sha256sum*.
