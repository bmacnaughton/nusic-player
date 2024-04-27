# script to play random music

let dirs = (ls z:/flac | where type == dir)

let directory_count = ($dirs | length)

# ideas
# maximum length song
# exclude/include classical/comedy
# dynamic matches on string: artist/album/song
#  with select (using nu table)
# play random albums|artists instead of songs


def main [musician: string
  --debug (-d)
] {
  let tab = $dirs | get name | parse 'z:\flac\{artist}' |
    where { |it| $it.artist | str contains --ignore-case $musician}

  if ($tab | length) > 1 {
    $tab | input list "Select"
  } else if ($tab | is-empty) != true {
    $tab | get 0
  } else {
    "no match"
  }
}

