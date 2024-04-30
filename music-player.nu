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

    if $debug {
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
  mut artist: string = ''
  mut album: string = ''
  mut title: string = ''

  for comment in $vorbis {
    if $comment.key == 'artist' {
      $artist = $comment.value
    } else if $comment.key == 'album' {
      $album = $comment.value
    } else if $comment.key == 'title' {
      $title = $comment.value
    } else {
      continue
    }
    $item_count += 1
    if $item_count >= 3 {
      break;
    }
  }

  if $item_count < 3 {
    $default_description
  } else {
    { artist: $artist, album: $album, song: $title}
  }
}
