# script to play random music

let dirs = (ls z:/flac | where type == dir)

let directory_count = ($dirs | length)

# ideas
# maximum length song
# exclude/include classical/comedy
# dynamic matches on string: artist/album/song
#  with select (using nu table)
# play random albums|artists instead of songs

use flac-decoder.nu decode-flac


def main [n: int
  --debug (-d)
  --flac-details (-f)
] {
  mut x = 0;
  while $x < $n {
    $x = $x + 1
    # choose a random artist (directory)
    let r = (random int ..<$directory_count)

    if $debug { print "DEBUG MODE" }

    # get all flac files in the artist's directory
    let name = ($dirs | get $r | get name)
    let pattern = $"($name)/**/*.flac"

    # this can fail if there are no .flac files (like willie nelson's mp3s)
    # todo - handle
    let all_flacs = try { ls ($pattern | into glob) }
    if $all_flacs == null {
      print $"no .flac files found for ($name)"
      continue;
    }

    let ix = (random int ..<($all_flacs | length))

    let flac_file_record = ($all_flacs | get $ix)
    if $debug { print $flac_file_record }

    # -wait gives an error.
    #powershell -command $"start-process -wait \"($all_flacs | get $ix | get name)\""
    let flac_name = ($all_flacs | get $ix | get name)

    let flac_info = decode-flac $flac_name

    if $debug { print $flac_info }

    if $flac_info.0.type != 'STREAMINFO' {
      # error
      return "error- No STREAMINFO in .flac file"
    }

    mut streaminfo = [];
    mut vorbis = [];

    for info in $flac_info {
      if $info.type == "VORBIS_COMMENT" {
        $vorbis = $info.contents
      } else if $info.type == 'STREAMINFO' {
        $streaminfo = $info.contents;
      }
    }

    if $debug or $flac_details {
      print $streaminfo
      if ($vorbis | is-not-empty) {
        print $vorbis
      }
    }

    let raw_seconds = ($streaminfo.sample_count / $streaminfo.sample_rate)
    let raw = $raw_seconds | math round --precision 2
    let seconds = ($raw_seconds | math ceil) + 1

    let time = ($"($seconds)sec" | into duration --unit sec)
    let time_text = $"raw ($raw) adjusted: ($seconds) secs \(($time)\)"
    let default_description = ($flac_file_record | select name | insert time $"($time_text)")

    if $debug {
      print $default_description
    }

    let description = make-description $vorbis $default_description
    print ($description | insert time $"($time_text)")

    # how to invoke with powershell, but use cross-platform start
    #powershell -command $"start-process \"($flac_name)\""
    start $"($flac_name)"

    sleep ($"($seconds)sec" | into duration)
  }
}

def make-description [
  vorbis: table,
  default_description
] {
  mut item_count = 0
  mut artist = [];
  mut album = [];
  mut title = [];
  mut genre = [];
  mut composer = [];
  mut albumartist = [];

  # consider - loop through and find ALL artist (classical often has
  # soloist/orchestra/conductor). how to present?
  # also artist three times: Al Di Meola, John McLaughlin, Paco DeLucia
  #
  # add composer if present
  # consider album artist (make first 'cause probably dupe of artist) also
  # when guest artists, want album artist
  #
  # often multiple style
  # sometimes no genre (but genre tends to be more generic when present)
  # sometimes genre and styles
  # sometimes multiple composer

  for comment in $vorbis {
    if $comment.key == 'artist' {
      $artist = ($artist | append $comment.value)
    } else if $comment.key == 'album' {
      $album = ($album | append $comment.value)
    } else if $comment.key == 'title' {
      $title = ($title | append $comment.value)
    } else if $comment.key == 'genre' {
      $genre = ($genre | append $comment.value)
    } else if $comment.key == 'composer' {
      $composer = ($composer | append $comment.value)
    } else if $comment.key == 'albumartist' {
      $albumartist = ($albumartist | append $comment.value)
    } else {
      continue
    }
    $item_count += 1
  }

  if ($artist | is-empty) and ($album | is-empty) and ($title | is-empty) {
    return $default_description;
  }

  let classical = $genre | any { |it| ($it | str downcase) == 'classical' }

  # if genre is/contains classical, play entire album? songs matching pattern?
  # - composer
  # - artist
  # - if conductor != artist, conductor
  # - orchestra
  # also, select all pieces of music that start with Symphony blah blah Op. #
  # ^^^ hard part due to no consistency, different numbering, etc. but usually
  # consistent on a single album. key - how many characters to match on at start
  # of the song title/name?
  # Key on Op, BWV, etc?
  # next step - read all classical items and collate tags

  mut description = {};
  if ($albumartist | is-not-empty) {
    $description = ($description | insert 'album artist' (join $albumartist));
  }
  mut description = {
    artist: (join $artist),
    album: (join $album),
    song: (join $title),
  }

  if ($composer | length) == 1 {
    $description = ($description | insert 'composer' $composer.0)
  } else if ($composer | length) >= 2 {
    $description = ($description | insert 'composers' (join $composer));
  }

  $description
}

def join [
  items: list
  joiner: string = '; '
] {
  $items | str join $joiner
}
