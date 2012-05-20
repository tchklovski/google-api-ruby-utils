# google-api-ruby-utils

Ruby command-line utilities for accessing things like google calendar.
Not comprehensive -- just focuses on a specific need of listing calendar events.
But, straightforward to extend.

## Installation

Assumes you're using RVM. Tested with ruby1.9.3

    gem install google-api-client slop
    git clone git://github.com/tchklovski/google-api-ruby-utils.git

## Usage

    cd google-api-ruby-utils
    ./fetch-google-calendar --help

If oauth is not initialized when you request results, the script will output
an explanation of what it needs for Google API OAuth.


## Author

Timothy Chklovski (@tchklovski)

## License

This is software is distributed under the same license as Ruby itself.
See http://www.ruby-lang.org/en/LICENSE.txt.
