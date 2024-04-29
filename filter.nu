
def valid_flacs [target: string] {
  each { |it|
    let parsed = parse --regex '-\d{2}-(?<song>.+)\.flac';
    if parsed == null {
      return false
    }
    if ($parsed.song | is-empty) {
      return false
    }

    $parsed.song.0 | str contains -i $target
  }
}

[
  'Chris Spedding\\Hollywood Vice Squad\\Chris Spedding-Hollywood Vice Squad-Closet Killer.flac'
  'The Beatles-Yellow Submarine-01-Yellow Submarine.flac'
] | valid_flacs killer
