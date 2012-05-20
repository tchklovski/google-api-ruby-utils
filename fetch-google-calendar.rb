#!/usr/bin/env ruby

# A script to fetch calendar events from Google via Google Calendar API
#
# Prints to stdout, as json, the events on the requested calendar
# You can specify which of the shared calendars (the default is primary) to access,
# and whether you want all or just upcoming.

# See README.md for installation

# Reference:
# https://developers.google.com/google-apps/calendar/setup
# https://developers.google.com/google-apps/calendar/instantiate
# https://developers.google.com/google-apps/calendar/v3/reference/events/list#examples
# https://developers.google.com/google-apps/calendar/v3/reference/

require 'google/api_client' # see http://code.google.com/p/google-api-ruby-client/
require 'json'
require 'slop' # see https://github.com/injekt/slop
require 'yaml'

module OAuth
  class Google
    @@config_file=ENV['HOME'] + '/.google-api.yaml'
    class << self
      def load
        if File.exist?(@@config_file)
          return YAML.load_file(@@config_file)
        else
          warn "ERROR: #@@config_file not found"
          self.abort_config_needed
        end
      end

      def abort_config_needed
        abort <<INTRO_TO_AUTH

  This utility requires valid oauth credentials and token for your project in
  the config file '#@@config_file'.

  You can create it by jumping through some oauth hoops by setting up a project
  and then using the google-api command, provided by the google-api-client gem:

  - Go to Google API Console at https://code.google.com/apis/console/ and
    set up a project that you will use to access this data.
  - In the "API Access" section, in the list of "Redirect URIs" include
    'http://localhost:12736/'.
  - Get your project's CLIENT_ID and CLIENT_SECRET to use below.
  - Users (including you) need to grant permissions to access their calendars.
   - Generate the config file '#@@config_file' by calling the following, which
     will launch the browser and write the config file:

    (LD_LIBRARY_PATH=
     CLIENT_ID=[YOUR-CLIENT_ID]
     CLIENT_SECRET=[YOUR-CLIENT-SECRET]
     google-api oauth-2-login --scope=https://www.googleapis.com/auth/calendar --client-id="$CLIENT_ID" --client-secret="$CLIENT_SECRET" )
INTRO_TO_AUTH
      end
    end
  end
end

module Calendar
  class Time < ::Time
    @@hour = 60*60
    @@day = 24*@@hour

    def start_of_day
      Time.local(year, month, day)
    end

    def make_upcoming_filter(num_days)
      now=Time.now
      # set starts_before to 3am of num_days from today
      starts_before = now.start_of_day + (num_days*@@day + 3*@@hour)
      ends_after = now  # want to specify starts_after, but that's not provided
      return {
        :timeMax => starts_before.iso8601,
        :timeMin => ends_after.iso8601,
        :singleEvents => "true",
        :orderBy => "startTime"}
    end
  end
end

module EventSugar
  def local_start_time
    self["start"]["dateTime"]
  end

  def starts_after?(time)
    local_start_time > time
  end
end

module Calendar
  class GoogleAPIClient < ::Google::APIClient
    def initialize(oauth)
      super
      authorization.client_id     = oauth["client_id"]
      authorization.client_secret = oauth["client_secret"]
      authorization.scope         = oauth["scope"]
      authorization.refresh_token = oauth["refresh_token"]
      authorization.access_token  = oauth["access_token"]

      # NB: seems authorization.expired? does not work b/c times are not stored
      # in the yaml -- so we just call authorization.fetch_access_token! on error
      # see update_token! in
      # http://code.google.com/p/google-api-ruby-client/wiki/OAuth2
      #if authorization.refresh_token && authorization.expired?
      #  authorization.fetch_access_token!
      #end
    end

    def fetch_data_with_retry(api_method, query)
      data = execute_aux(api_method, query).data
      if data_error(data) # retry executing after refereshing access_token
        authorization.fetch_access_token!
        data = execute_aux(api_method, query).data
      end
      if err = data_error(data) # raise exception if still an error
        raise RuntimeError, err.to_json
      end
      return data
    end

    private
    def execute_aux(api_method, parameters)
      execute(:api_method => api_method, :parameters => parameters)
    end

    def data_error(data)
      data.to_hash["error"]
    end
  end
end

module Calendar
  class GoogleCalendarClient < GoogleAPIClient
# Query params are described in:
# https://developers.google.com/google-apps/calendar/v3/reference/events/list

    def events(query)
      Enumerator.new {|y| events_aux(query){|event| y << event}}
    end

    def upcoming_events(query, num_days)
      t=Calendar::Time.new
      query = query.update(t.make_upcoming_filter(num_days))
      events(query).find_all do |event|
        # TODO: consider including the recently started (like 15 mins?)
        # to handle running late.
        event.extend(EventSugar).starts_after? Time.now
      end
    end

    private
    def events_aux(cal_query, &block) # requires a block
      data = list_events(cal_query)
      data.items.each(&block)
      if page_token = data.next_page_token
        events_aux(cal_query.merge(:pageToken => page_token), &block)
      end
    end

    def list_events(calendar_query)
      fetch_data_with_retry(calendar_service.events.list, calendar_query)
    end

    def calendar_service
      discovered_api('calendar', 'v3')
    end
  end
end

def parse_command_line_opts
  Slop.parse(:help => true) do
    banner <<BANNER
#{$0} [options]
  Fetch calendar events from Google via Google Calendar API.

  Prints to stdout, as json, the events on the requested calendar.
BANNER

    on :c, :calendar=, 'calendar id (defaults to "primary")',
    :default => 'primary'
    on 'upcoming=?',
    'events that start before 3am of next day and end after now.
                        Provide a number to make it that many days ahead.',
    :as => :float, :default => 1
  end
end

opts = parse_command_line_opts
exit if opts.help?

cal = Calendar::GoogleCalendarClient.new(OAuth::Google.load)
query = {:calendarId => opts[:calendar]}

events = opts.upcoming? ? cal.upcoming_events(query, opts[:upcoming]) : cal.events(query)
events.each{|ev| puts ev.to_json }
