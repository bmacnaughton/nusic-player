# script to play random music

const music_dir = "z:/flac"

#
#let dirs = (ls $music_dir | where type == dir)
## ls z:/flac/** | where type == dir | get name | parse 'z:\flac\{artist}\{album}'
#
# replace \ with / in filenames
# ls z:/flac/ | where type == dir | each { |it| update name ($it.name | str replace '\' '/' -a) }

# find name in all flac files, case insensitive
# ls z:/flac/**/*.flac | where (($it.name | str downcase) | str contains 'jimi')


# ideas
# maximum length song
# exclude/include classical/comedy
# dynamic matches on string: artist/album/song
#  with select (using nu table)
# play random albums|artists instead of songs

# arg:
# - number: play n random songs
# - string: select artist
# music-filter artist
# music-filter artist album

#
# choose is name or album or song (requires reading a lot of directories)
#
export def choose [target: string] {
  let skip_count = $music_dir | path split | length
  let flacs = ls ($"($music_dir)/**/*.flac" | into glob)
  let selected = $flacs | where (
      $it.name | skip $skip_count | str contains --ignore-case $target
    )

  $selected
}

export def "choose artist" [artist: string] {
  # top-level directories are the artists but we want the artist's albums
  let artists = ls ($"($music_dir)/*/*" | into glob) | where type == dir
  # select based on the artist name, not the album name (or other path)
  let selected = $artists | where (
      $it.name | path split | drop | last | str contains --ignore-case $artist
    )

  $selected
}

export def "choose album" [album: string] {
  # albums are the next directory level after artists
  let albums = ls ($"($music_dir)/*/*" | into glob) | where type == dir

  # select only based on the last directory name (the album name)
  let selected = $albums | where (
      $it.name | path split | last | str contains --ignore-case $album
    )

  $selected
}

export def "choose-deprecated song" [song: string] {
  let flacs = ls ($"($music_dir)/**/*.flac" | into glob)
  print $"found ($flacs | length) songs"

  let selected = $flacs | where (
      $it.name | parse --regex '-\d{2}-(?<song>.+)\.flac$' |
          # no idea why i need to do this. the ls found only .flac files. all
          # .flac files have a -00- (two digits between dashes) sequence number.
          #
          try { get song.0 } catch { '' } |
          str contains --ignore-case $song
    )

  $selected
}

export def "choose song" [song: string] {
  let flacs = ls ($"($music_dir)/**/*.flac" | into glob)
  print $"found ($flacs | length) songs"

  let selected = $flacs | where ( $it | get name | is-known-format-flac $song )

  $selected
}


def is-known-format-flac [target: string] {
  each { |it|
    let parsed = $it | parse --regex '-\d{2}-(?<song>.+)\.flac';
    if parsed == null {
      return false
    }
    if ($parsed.song | is-empty) {
      return false
    }

    $parsed.song.0 | str contains -i $target
  }
}
