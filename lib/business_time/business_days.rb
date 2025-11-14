require 'active_support/time'

module BusinessTime
  class BusinessDays
    include Comparable
    attr_reader :days

    def initialize(days, options={})
      @days = days
    end

    def <=>(other)
      if other.class != self.class
        raise ArgumentError.new("#{self.class} can't be compared with #{other.class}")
      end
      self.days <=> other.days
    end

    def after(time = Time.current, options={})
      non_negative_days? ? calculate_after(time, @days, options) : calculate_before(time, -@days, options)
    end

    alias_method :from_now, :after
    alias_method :since, :after

    def before(time = Time.current, options={})
      non_negative_days? ? calculate_before(time, @days, options) : calculate_after(time, -@days, options)
    end

    alias_method :ago, :before
    alias_method :until, :before

    private

    def non_negative_days?
      @days >= 0
    end

    def calculate_after(time, days, options={})
      if !(time.is_a?(Date) || time.is_a?(DateTime) || time.is_a?(Time))
        raise ArgumentError.new("BusinessDays can only be calculated from Date, DateTime, or Time objects")
      end

      if !time.workday?(options)
        time = Time.roll_forward(time, options)
      end

      while days > 0 || !time.workday?(options)
        days -= 1 if time.workday?(options)
        time += 1.day
      end

      # If we have a Time or DateTime object, we can roll_forward to the
      #   beginning of the next business day
      if !time.is_a?(Date) && !time.during_business_hours?
        time = Time.roll_forward(time, options)
      end

      time
    end

    def beginning_of_previous_workday(time, options={})
      Time.beginning_of_workday(Time.roll_backward(time, options))
    end

    def calculate_before(time, days, options={})
      if !(time.is_a?(Date) || time.is_a?(DateTime) || time.is_a?(Time))
        raise ArgumentError.new("BusinessDays can only be calculated from Date, DateTime, or Time objects")
      end

      # Move to the beginning of the workday if we're starting on a non-workday
      if !time.workday?(options)
        time = beginning_of_previous_workday(time, options)
      end

      while days > 0 || !time.workday?(options)
        days -= 1 if time.workday?(options)
        time -= 1.day
      end

      # If we have a Time or DateTime object, we can roll_forward to the
      #   beginning of the next business day
      if !time.is_a?(Date) && !time.during_business_hours?
        time = beginning_of_previous_workday(time, options)
      end

      time
    end
  end
end
