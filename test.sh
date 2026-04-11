#!/bin/bash

manager="*archive-manager*"

fail() { echo -e "\e[31m"; echo -e "$*"; echo -e "\e[0m"; exit 1; }
assert() { [[ "$2" != "$3" ]] && fail "assertion $1 failed\narg 1: \e[34m$2\e[31m\narg 2: \e[34m$3"; }
echotest() { echo -e "\e[33m"; echo "$*"; echo -e "\e[0m"; }
cleanup() {
rm archivepatchitemlist*;
rm -r tmp thm sto;
rm thm.tar.zst;
}
cleanup

mkdir tmp thm sto
touch thm.tar.zst

rhash="384f5ed9aa654dca16032c6e9f046b12e171c439e1e504d7d09db4e4155979c5"
ghash="7539cfb88438a64790288b62eaa94f876bc38ee1223c70fdeea964a5b841fb18"
bhash="b6e3eefd0dbe69a5b9cec72a99f7186d15ddc737c8417673d2709e98357e6dfc"

assert "sanity check" "a" "a"

magick -size 800x800 canvas:#f00 -strip tmp/1.jxl
magick -size 800x800 canvas:#0f0 -strip tmp/_green.jpg
magick -size 800x800 canvas:#00f -strip tmp/_blue-image.webp

echotest "testing C"
bash $manager C || fail "test C"
assert "test C" "$(/bin/ls sto)" "$rhash.jxl
$ghash-green.jxl
$bhash-blue-image.jxl"

echotest "testing R"
bash $manager R qwe/asd/$ghash-green.zxc || fail "failed test R"
assert "test R" "$(/bin/ls sto)" "$rhash.jxl
$bhash-blue-image.jxl"

echotest "testing G"
bash $manager G qwe/asd/$bhash-blue-image.zxc zort || fail "failed test G"
assert "test G" "$(/bin/ls sto)" "$rhash.jxl
$bhash-blue-image-zort.jxl"

echotest "testing U"
bash $manager U qwe/asd/$bhash-blue-image-zort.zxc || fail "failed test U"
assert "test U" "$(/bin/ls sto)" "$rhash.jxl
$bhash.jxl"

bash $manager G qwe/asd/$bhash.zxc blue-image || fail "failed test U-G"

echotest "testing F"
bash $manager F || fail "failed test F"

echotest "testing PL"
magick -size 800x800 canvas:#0f0 -strip tmp/_green.jpg
bash $manager C || fail "failed test PL-C"
bash $manager PL || fail "failed test PL"
assert "test PL" "$(cat archivepatchitemlist*)" "$rhash.jxl
$ghash-green.jxl
$bhash-blue-image.jxl"

echotest "testing PS"
echo "$ghash-green_conflict.jxl
$rhash-added.jxl
$bhash.jxl" > archivepatchitemlist*
x=$(yes n | bash $manager PS archivepatchitemlist* || fail "failed test PS")
echo "$x"
# exit 2
[[ "$x" == *"TAGGED LOCAL ITEM $ghash-green WAS TAGGED ON REMOTE COPY WITH: green_conflict; CONFLICTING, SKIPPING"* ]] || fail "failed PS conflicting tags"
[[ "$x" == *"TAGGED LOCAL ITEM $bhash-blue-image WAS NOT TAGGED ON REMOTE COPY, SKIPPING"* ]] || fail "failed PS remote untagged tags"
[[ "$x" == *"UNTAGGED LOCAL ITEM $rhash WAS TAGGED ON REMOTE COPY WITH: added"* ]] || fail "failed PS local untagged tags"

[[ "$1" != "nocleanup" ]] && cleanup

echo -e "\e[32mtest done\e[39m"
