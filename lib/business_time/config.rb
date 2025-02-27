require 'active_support/core_ext'

module BusinessTime

  # controls the behavior of this gem.  You can change
  # the beginning_of_workday, end_of_workday, and the list of holidays
  # manually, or with a yaml file and the load method.
  class Config
    DEFAULT_CONFIG = {
      holidays:              Set.new,
      beginning_of_workday:  ParsedTime.parse('9:00 am'),
      end_of_workday:        ParsedTime.parse('5:00 pm'),
      work_week:             %w(mon tue wed thu fri),
      work_hours:            {},
      work_hours_total:      {},
      _weekdays:             nil,
      fiscal_month_offset:   10,
    }

    class << self
      def beginning_of_workday=(time)
        config[:beginning_of_workday] = ParsedTime.parse(time)
      end

      def end_of_workday=(time)
        config[:end_of_workday] = ParsedTime.parse(time)
      end

      def work_hours=(work_hours)
        work_hours.each_with_object(config[:work_hours] = {}) do |(day, hours), c|
          c[day] = hours.map do |time|
            ParsedTime.parse(time)
          end
        end
      end

      private

      def config
        return local_config if local_config?
        Thread.main[:business_time_config] ||= default_config
      end

      def config=(config)
        return self.local_config = config if local_config?
        Thread.main[:business_time_config] = config
      end

      def local_config
        local_config_stack.last
      end

      def local_config=(config)
        local_config_stack.last.replace(config)
      end

      def local_config_stack
        Thread.current[:business_time_local_config] ||= []
      end

      def local_config?
        !local_config_stack.empty?
      end

      def threadsafe_cattr_accessor(name)
        threadsafe_cattr_reader(name)
        threadsafe_cattr_setter(name)
      end

      def threadsafe_cattr_reader(name)
        define_singleton_method name do
          config[name]
        end
      end

      def threadsafe_cattr_setter(name)
        define_singleton_method "#{name}=" do |value|
          config[name] = value
        end
      end
    end

    threadsafe_cattr_reader :work_week

    # You can set this yourself, either by the load method below, or
    # by saying
    #   BusinessTime::Config.holidays << my_holiday_date_object
    # someplace in the initializers of your application.
    threadsafe_cattr_accessor :holidays

    # working hours for each day - if not set using global variables :beginning_of_workday
    # and end_of_workday. Keys will be added ad weekdays.
    # Example:
    #    {:mon => ["9:00","17:00"],:tue => ["9:00","17:00"].....}
    threadsafe_cattr_reader :work_hours

    # total work hours for a day. Never set, always calculated.
    threadsafe_cattr_accessor :work_hours_total

    threadsafe_cattr_accessor :_weekdays # internal

    threadsafe_cattr_accessor :fiscal_month_offset

    class << self
      # You can set this yourself, either by the load method below, or
      # by saying
      #   BusinessTime::Config.end_of_workday = "5:30 pm"
      # someplace in the initializers of your application.
      def end_of_workday(day=nil)
        eod = config[:end_of_workday]
        if day
          wday = work_hours[int_to_wday(day.wday)]
          eod = wday.last if wday
        end

        eod == ParsedTime.new(0, 0) ? ParsedTime.new(23, 59, 59) : eod
      end

      # You can set this yourself, either by the load method below, or
      # by saying
      #   BusinessTime::Config.beginning_of_workday = "8:30 am"
      # someplace in the initializers of your application.
      def beginning_of_workday(day=nil)
        if day
          wday = work_hours[int_to_wday(day.wday)]
          wday ? wday.first : config[:beginning_of_workday]
        else
          config[:beginning_of_workday]
        end
      end

      # You can set this yourself, either by the load method below, or
      # by saying
      #   BusinessTime::Config.work_week = [:sun, :mon, :tue, :wed, :thu]
      # someplace in the initializers of your application.
      def work_week=(days)
        config[:work_week] = days
        self._weekdays = nil
      end

      def weekdays
        return _weekdays unless _weekdays.nil?

        days = (!work_hours.empty? ? work_hours.keys : work_week).map do |day_name|
          wday_to_int(day_name)
        end.compact

        self._weekdays = days.sort.to_set
      end

      # loads the config data from a yaml file written as:
      #
      #   business_time:
      #     beginning_od_workday: 8:30 am
      #     end_of_workday: 5:30 pm
      #     holidays:
      #       - Jan 1st, 2010
      #       - July 4th, 2010
      #       - Dec 25th, 2010
      def load(file)
        reset
        data = YAML::load(file.respond_to?(:read) ? file : File.open(file))
        config = (data["business_time"] || {})

        # load each config variable from the file, if it's present and valid
        config_vars = %w(beginning_of_workday end_of_workday work_week work_hours)
        config_vars.each do |var|
          send("#{var}=", config[var]) if config[var] && respond_to?("#{var}=")
        end

        (config["holidays"] || []).each do |holiday|
          holidays << Date.parse(holiday)
        end
      end

      def with(config)
        local_config_stack.push(config().dup)
        config.each { |k,v| send("#{k}=", v) } # calculations are done on setting
        yield
      ensure
        local_config_stack.pop
      end

      def default_config
        deep_dup(DEFAULT_CONFIG)
      end

      private

      DAY_NAMES = [
        'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'
      ]
      private_constant :DAY_NAMES

      def wday_to_int day_name
        lowercase_day_names = DAY_NAMES.map(&:downcase)
        lowercase_day_names.find_index(day_name.to_s.downcase)
      end

      def int_to_wday num
        DAY_NAMES.map(&:downcase).map(&:to_sym)[num]
      end

      def reset
        local_config_stack.clear
        self.config = default_config
      end

      def deep_dup(object)
        Marshal.load(Marshal.dump(object))
      end
    end

    # reset the first time we are loaded.
    reset
  end
end
