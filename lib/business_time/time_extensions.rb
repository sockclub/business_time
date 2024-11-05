module BusinessTime
  module TimeExtensions
    # True if this time is on a workday (between 00:00:00 and 23:59:59), even if
    # this time falls outside of normal business hours.
    # holidays option allows you to pass in a different Array of holiday dates on
    # each call vs the BusinessTime::Config.holidays which is always static.
    def workday?(options={})
      weekday? &&
        !BusinessTime::Config.holidays.include?(to_date) &&
        !to_array_of_dates(options[:holidays]).include?(to_date)
    end

    # True if this time falls on a weekday.
    def weekday?
      BusinessTime::Config.weekdays.include?(wday)
    end

    # TODO rdoc
    def beginning_of_workday
      beginning = BusinessTime::Config.beginning_of_workday(self)
      self.change(
        hour: beginning.hour,
        min: beginning.min,
        sec: beginning.sec
      )
    end

    # TODO rdoc
    def end_of_workday
      ending = BusinessTime::Config.end_of_workday(self)
      self.change(
        hour: ending.hour,
        min: ending.min,
        sec: ending.sec
      )
    end

    # TODO rdoc
    def before_business_hours?
      to_i < beginning_of_workday.to_i
    end

    # TODO rdoc
    def after_business_hours?
      to_i > end_of_workday.to_i
    end

    # Rolls forward to the next beginning_of_workday
    # when the time is outside of business hours
    def roll_forward(options={})
      next_time = if before_business_hours? || !workday?(options)
                    beginning_of_workday
                  elsif after_business_hours? || end_of_workday == self
                    (self + 1.day).beginning_of_workday
                  else
                    clone
                  end

      while !next_time.workday?(options)
        next_time = (next_time + 1.day).beginning_of_workday
      end

      next_time
    end

    def first_business_day(options = {})
      Time.first_business_day(self, options)
    end

    # Rolls backwards to the previous end_of_workday when the time is outside
    # of business hours
    def roll_backward(options={})
      prev_time = if before_business_hours? || !workday?(options)
                    (self - 1.day).end_of_workday
                  elsif after_business_hours?
                    end_of_workday
                  else
                    clone
                  end

      while !prev_time.workday?(options)
        prev_time = (prev_time - 1.day).end_of_workday
      end

      prev_time
    end

    def previous_business_day(options = {})
      Time.previous_business_day(self, options)
    end

    module ClassMethods
      # Gives the time at the end of the workday, assuming that this time falls on a
      # workday.
      # Note: It pretends that this day is a workday whether or not it really is a
      # workday.
      def deprecation_warning(message)
        ActiveSupport::Deprecation.new("1.0", "business_time").warn(message)
      end

      def end_of_workday(day)
        deprecation_warning("`Time.end_of_workday?(time)` is deprecated. Please use `time.end_of_workday`")
        day.end_of_workday
      end

      # Gives the time at the beginning of the workday, assuming that this time
      # falls on a workday.
      # Note: It pretends that this day is a workday whether or not it really is a
      # workday.
      def beginning_of_workday(day)
        deprecation_warning("`Time.beginning_of_workday?(time)` is deprecated. Please use `time.beginning_of_workday`")
        day.beginning_of_workday
      end

      # True if this time is on a workday (between 00:00:00 and 23:59:59), even if
      # this time falls outside of normal business hours.
      def workday?(day, options={})
        deprecation_warning("`Time.workday?(time)` is deprecated. Please use `time.workday?`")
        day.workday?(options)
      end

      # True if this time falls on a weekday.
      def weekday?(day)
        deprecation_warning("`Time.weekday?(time)` is deprecated. Please use `time.weekday?`")
        day.weekday?
      end

      def before_business_hours?(time)
        deprecation_warning("`Time.before_business_hours?(time)` is deprecated. Please use `time.before_business_hours`")
        time.before_business_hours?
      end

      def after_business_hours?(time)
        deprecation_warning("`Time.after_business_hours?(time)` is deprecated. Please use `time.after_business_hours`")
        time.after_business_hours?
      end

      # Rolls forward to the next beginning_of_workday
      # when the time is outside of business hours
      def roll_forward(time, options={})
        deprecation_warning("`Time.roll_forward?(time)` is deprecated. Please use `time.roll_forward`")
        options.roll_forward
      end

      # Returns the time parameter itself if it is a business day
      # or else returns the next business day
      def first_business_day(time, options={})
        while !time.workday?(options)
          time = time + 1.day
        end

        time
      end

      # Rolls backwards to the previous end_of_workday when the time is outside
      # of business hours
      def roll_backward(time, options={})
        deprecation_warning("`Time.roll_backwards?(time)` is deprecated. Please use `time.roll_backwards`")
        options.roll_backward
      end

      # Returns the time parameter itself if it is a business day
      # or else returns the previous business day
      def previous_business_day(time, options={})
        while !time.workday?(options)
          time = time - 1.day
        end

        time
      end

      def work_hours_total(day, options={})
        return 0 unless day.workday?(options)

        day = day.strftime('%a').downcase.to_sym

        if hours = BusinessTime::Config.work_hours[day]
          BusinessTime::Config.work_hours_total[day] ||= begin
            hours_last = hours.last
            if hours_last == ParsedTime.new(0, 0)
              (ParsedTime.new(23, 59) - hours.first) + 1.minute
            else
              hours_last - hours.first
            end
          end
        else
          BusinessTime::Config.work_hours_total[:default] ||= begin
            BusinessTime::Config.end_of_workday - BusinessTime::Config.beginning_of_workday
          end
        end
      end

      private

      def change_business_time time, hour, min=0, sec=0
        time.change(:hour => hour, :min => min, :sec => sec)
      end
    end

    def business_time_until(to_time, options={})
      # Make sure that we will calculate time from A to B "clockwise"
      if self < to_time
        time_a = self
        time_b = to_time
        direction = 1
      else
        time_a = to_time
        time_b = self
        direction = -1
      end

      # Align both times to the closest business hours
      time_a = time_a.roll_forward(options)
      time_b = time_b.roll_forward(options)

      if time_a.to_date == time_b.to_date
        time_b - time_a
      else
        end_of_workday = time_a.end_of_workday
        end_of_workday += 1 if end_of_workday.to_s =~ /23:59:59/

        first_day       = end_of_workday - time_a
        days_in_between = ((time_a.to_date + 1)..(time_b.to_date - 1)).sum{ |day| Time::work_hours_total(day) }
        last_day        = time_b - time_b.beginning_of_workday

        first_day + days_in_between + last_day
      end * direction
    end

    def during_business_hours?(options={})
      workday?(options) && to_i.between?(beginning_of_workday.to_i, end_of_workday.to_i)
    end

    def consecutive_workdays(options={})
      workday?(options) ? consecutive_days { |date| date.workday?(options) } : []
    end

    def consecutive_non_working_days(options={})
      !workday?(options) ? consecutive_days { |date| !date.workday?(options) } : []
    end

    private

    def consecutive_days
      days = []
      date = self + 1.day
      while yield(date)
        days << date
        date += 1.day
      end
      date = self - 1.day
      while yield(date)
        days << date
        date -= 1.day
      end
      (days << self).sort
    end

    def to_array_of_dates(values)
      Array.wrap(values).map(&:to_date)
    end
  end
end
